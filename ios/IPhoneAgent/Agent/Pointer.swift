import Foundation

/// Touch-like gestures on the phone, built from relative mouse moves. Port of phone.py.
///
/// The pointer is relative, so the app tracks where it is (in mouse units) and moves from there; every few
/// gestures it slams it into the top-left corner (`home`) again to cancel drift. Coordinates are fractions of
/// the screen (0..1, origin top-left), so they work for any frame size.
@MainActor final class Pointer: ObservableObject {
    /// 167: an iPad's screen is ~8x the mouse units of an iPhone's (3900 x 5270 measured on the customer's iPad 9, 11-25,
    /// against ~445 x 620): distances given in units are scaled so they land as far across the screen as on an iPhone.
    /// 166's calibration probed 75 units from the corner: on the iPad that was the status bar's clock, which opens
    /// Notification Center, so no probe click ever reached the calibration screen.
    static var padScale: Int { CommandChannel.onPad() ? 8 : 1 }
    static var calibrationMove: Int { 200 * padScale }  // mouse units moved diagonally for a manual (one point) calibration
    static var calibrationStops: [Int] { [150, 350].map { $0 * padScale } }  // automatic calibration finds the pointer here
    static let rehomeEvery = 10             // gestures between re-homing
    static let hold = 0.25                  // s to rest before lifting, so iOS adds no momentum
    static let tapGap = 0.15                // s to stay still after a click, so iOS sees a finished tap
    static var nudge: Int { CommandChannel.onPad() ? 60 : 12 }  // units the pointer is wiggled by to find it on screen
    static let aimTolerance = 0.008         // screen fraction; a bigger miss is corrected before pressing
    static let maxMiss = 0.06               // bigger misses are still corrected, but not learned from; they mark the calibration stale
    static let aimPasses = 3                // closed loop: look, correct, look again, at most this many corrections
    static let edge = 0.05                  // screen fraction; a pointer this close to the border, past its target, was stopped by it
    private static let gestureEdgeInset = 0.025 // visible pointer centre can remain inside the border during a system edge gesture
    static let edgeAlongTolerance = 0.03    // screen fraction; how far along the border a system swipe may start from its spot

    struct Span: Codable, Equatable { var w: Int, h: Int }
    private struct Saved: Codable {
        var w: Int, h: Int, seen: [String: [[Double]]]?, quality: Double?, aspect: Double?, stale: Bool?
        var maps: [String: ProbeMap]? = nil
        var motionVersion: Int? = nil
        var requiresFeedback: Bool? = nil
        var borderLift: Double? = nil
    }
    static let calibrationTolerance = 0.015
    private var maps: [String: ProbeMap]?
    private var provisional = false
    private var backup: Saved?
    private var requiresFeedback = false

    let device: HIDDevice
    weak var screen: ScreenSource?
    private let file: URL
    @Published private(set) var span: Span? {  // mouse units needed to cross the full screen width / height
        didSet { Self.shareSpan(span) }
    }

    /// The iPad home (CommandChannel) clamps its tracked position to the calibrated screen size.
    static func shareSpan(_ span: Span?) {
        guard let span, span.w > 100, span.h > 100 else { return }
        CommandChannel.padSpan = (span.w, span.h)
    }

    /// 162 (iPad): the pointer's height on screen (0 top … 1 bottom) from two frames around a 60-unit wiggle, when the
    /// iPad home does not know where it is. Not in the status bar (Vision skips it): from there it moves 600 down first
    /// (a push that far past the bottom is harmless). nil without a live screen. Not behind oneAtATime: it runs inside
    /// a gesture's home.
    /// 174 (user 11-25: "不要让它走上边、左边和下面…尽量叫它走右边，也不要走右上角"): an iPad's home is the middle of the
    /// screen, found by looking, never a corner (pushes past the top, the left and the bottom brought in Notification
    /// Center, Stage Manager's recent apps and the Dock). Find the arrow (a nudge sideways, Vision.arrows), move to the
    /// middle, look again, up to three times; where it was last seen is the home (padHomeSpot). Not seen: down a little
    /// and look again (177: never a push past an edge). Returns why it failed (nil: home).
    func padHome(toMiddle: Bool = false) async -> String? {
        guard CommandChannel.onPad(), let screen, screen.live else { return "iPad 上 Echo 收不到画面：请确认「共享整个屏幕」开着" }
        CommandChannel.padPos = nil
        var spot = await padSpot(nudge: 60)
        if spot == nil { spot = await padSpot(nudge: -60) }
        // 177 (user 11-25: "右上角、右下角都不要有"): 176 pushed right when the arrow was not seen; it sat in the status
        // bar (not looked at: the clock changes there), and the push took it along the top into the top-right corner.
        // Unseen, it now goes down a little (a status-bar arrow comes out under it), at most three times, no edge pushed.
        for step in 1...3 where spot == nil {
            log("ipad home: arrow not seen; down a little (\(step))")
            _ = try? await device.send("move 0 \(CommandChannel.padSpan.h * 8 / 100)")  // place unknown: slow (padPush)
            spot = await padSpot(nudge: 60)
            if spot == nil { spot = await padSpot(nudge: -60) }
        }
        guard var p = spot else {
            log("ipad home: arrow not seen")
            return "画面里找不到游标箭头（晃动游标也没看到变化）：请把 Echo 留在最前面再校准一次"
        }
        // 175 (174 on the iPad, 11-25: "arrow lost on the way to the middle", twice): the span kept from the last
        // calibration was 173's, measured at 20 counts a report, twice the units a screen of today's pace, so the move
        // went twice as far, out of the window looked in. The first move goes half way; what it really moved sets the
        // units a screen (kept as padSpan); the arrow is looked for on the whole screen, the tip away from where it was.
        var w = Double(CommandChannel.padSpan.w), h = Double(CommandChannel.padSpan.h)
        // 180 (user 11-25: no detours): an ordinary home takes the arrow where it is seen; only calibration brings it to
        // the middle (and learns the units a screen on the way).
        for pass in 0..<(toMiddle ? 4 : 0) {
            let ex = 0.5 - Double(p.x), ey = 0.5 - Double(p.y)
            if abs(ex) <= 0.015 && abs(ey) <= 0.015 { break }
            let k = pass == 0 ? 0.5 : 1.0
            let ux = Int(ex * k * w), uy = Int(ey * k * h)
            CommandChannel.padPos = (Int(Double(p.x) * w), Int(Double(p.y) * h))
            let before = screen.frame, sent = now()
            guard (try? await device.send("move \(ux) \(uy)")) != nil, let before,
                  let after = await stopped(since: sent, on: screen, wait: 0.9),
                  let seen = Self.movedArrow(Vision.arrows(before, after, near: CGPoint(x: 0.5, y: 0.5), window: 0.6), from: p) else {
                log("ipad home: arrow lost on the way to the middle")
                return "游标往屏幕中间移动时跟丢了箭头：请再按一次校准"
            }
            let mx = Double(seen.x - p.x), my = Double(seen.y - p.y)
            if abs(ux) >= 40, abs(mx) >= 0.02 { w = min(max(Double(ux) / mx, w / 3), w * 3) }
            if abs(uy) >= 40, abs(my) >= 0.02 { h = min(max(Double(uy) / my, h / 3), h * 3) }
            p = seen
        }
        log(String(format: "ipad home: the arrow at (%.3f, %.3f); a screen ~%.0f x %.0f units", Double(p.x), Double(p.y), w, h))
        CommandChannel.padSpan = (Int(w), Int(h))
        CommandChannel.padPos = (Int(Double(p.x) * w), Int(Double(p.y) * h))
        Self.padHomeSpot = p
        return nil
    }

    /// 175: after a move, the arrow's new spot among the tips seen: the one away from where it was (`from`); a single tip
    /// (the old spot not seen, or the two overlapping) is taken as it is.
    static func movedArrow(_ tips: [CGPoint], from: CGPoint) -> CGPoint? {
        if tips.count == 1 { return tips[0] }
        return tips.filter { hypot($0.x - from.x, $0.y - from.y) > 0.012 }
            .max { hypot($0.x - from.x, $0.y - from.y) < hypot($1.x - from.x, $1.y - from.y) }
    }

    /// 180: calibration's home brings the arrow to the middle (TouchCalibration sets it around its first home).
    static var padHomeToMiddle = false

    /// Where an iPad's home left the arrow (screen fractions); nil before one.
    static var padHomeSpot: CGPoint?

    /// 174: where home leaves the pointer, in this pointer's units: an iPad's seen spot, elsewhere the corner.
    private func homeUnits() -> (Int, Int) {
        guard CommandChannel.onPad(), let p = Self.padHomeSpot else { return (0, 0) }
        return (dx(Double(p.x)), dy(Double(p.y)))
    }

    /// The arrow's spot: nudge it sideways and back, and compare the frames.
    private func padSpot(nudge: Int) async -> CGPoint? {
        guard let screen, screen.live else { return nil }
        await screen.settled(quiet: 0.2, least: 0.3, most: 1.5)
        let before = screen.frame, sent = now()
        guard (try? await device.send("move \(nudge) 0")) != nil else { return nil }
        var after = await screen.fresh(since: sent, timeout: 1.0)
        if after != nil {
            await screen.settled(quiet: 0.15, least: 0.1, most: 0.6)
            after = screen.frame
        }
        _ = try? await device.send("move \(-nudge) 0")
        guard let before, let after else { return nil }
        return Self.arrowBefore(before, after, near: CGPoint(x: 0.5, y: 0.5), nudge: nudge, window: 0.5)
    }

    func padFindY() async -> Double? {
        func wiggle() async -> Double? {
            guard let screen, screen.live else { return nil }
            await screen.settled(quiet: 0.2, least: 0.3, most: 1.5)
            let before = screen.frame, sent = now()
            guard (try? await device.send("move 60 0")) != nil else { return nil }
            var after = await screen.fresh(since: sent, timeout: 1.0)
            if after != nil {
                await screen.settled(quiet: 0.15, least: 0.1, most: 0.6)
                after = screen.frame
            }
            _ = try? await device.send("move -60 0")
            guard let before, let after else { return nil }
            let shift = 60 / Double(max(1, CommandChannel.padSpan.w))
            // 174: the arrow (Vision.arrow); either of its two spots has the height
            if let tip = Vision.arrows(before, after, near: CGPoint(x: 0.5, y: 0.5), window: 0.5).first { return Double(tip.y) }
            return Vision.pointer(before, after, near: CGPoint(x: 0.5, y: 0.5), shift: shift, reach: CGPoint(x: 0.5, y: 0.5)).map { Double($0.y) }
        }
        if let y = await wiggle() { return y }
        guard (try? await device.send("move 0 600")) != nil else { return nil }
        return await wiggle()
    }
    private var pos: (Int, Int)?  // pointer position in mouse units; nil = unknown
    private var moves = 0
    private var lastClick: LastClick?  // the last tap's spot, for clicking again in place
    private var hops = 0  // nearby taps since the pointer was last homed
    private var strokeCommand: Bool?  // does the firmware take `stroke` (v16+)? nil until the first drawing tries it
    // A run of drawing strokes (circle/path) re-homes to the corner only at its start, then continues from the tracked
    // position: no trip to the top-left between every stroke. Any tap or other gesture ends the run (clears drawChain),
    // so the next drawing starts clean again. unitsSinceDrawHome bounds the drift that builds across a long run: once
    // the strokes have moved more than the budget, the next one re-homes.
    private var drawChain = false
    private var unitsSinceDrawHome = 0
    private var link = 0  // device.links when the pointer was last homed
    /// where the pointer really landed (seen on screen) for the fraction we aimed at, per axis; a line fit
    /// through them corrects every later move, so taps get better as the agent works
    private(set) var seen: [String: [(Double, Double)]] = ["x": [], "y": []]
    @Published private(set) var quality: Double?  // pointer error at the last check, fraction of the screen
    private(set) var aspect: Double?  // frame width / height when calibrated
    /// An aimed tap missed by more than maxMiss or hit the border: the span no longer fits this phone (log25: saved
    /// 494 x 1110, real ~445 x 620). Every tap aims until the next calibration clears it.
    @Published private(set) var stale = false
    var log: (String) -> Void = { print($0) }
    /// The device screen's width / height (iPhone or iPad), stored with a calibration.
    var screenAspect: () -> Double = { 9 / 19.5 }
    /// Last-resort pointer finder on a frame (the vision model), when the pixel diff finds nothing.
    var locate: ((Data) async -> CGPoint?)?
    /// Finds the pointer for an aim instead of wiggling it on the mirrored screen (tests).
    var finder: ((Double, Double) async throws -> CGPoint?)?

    init(device: HIDDevice, calibrationFile: URL, screen: ScreenSource? = nil) {
        self.device = device
        self.file = calibrationFile
        self.screen = screen
        if let data = try? Data(contentsOf: calibrationFile), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            span = Span(w: saved.w, h: saved.h)
            Self.shareSpan(span)  // didSet does not run in init
            (quality, aspect, stale) = (saved.quality, saved.aspect, saved.stale ?? false)
            maps = saved.maps
            requiresFeedback = saved.requiresFeedback ?? false
            if let lift = saved.borderLift { borderLiftY = min(max(lift, -Self.borderLiftLimit), Self.borderLiftLimit) }
            // Older builds certified open-loop movement. Remeasure using endpoint
            // feedback before treating those parameters as validated.
            if saved.motionVersion != ProbeMotion.version { stale = true }
            for axis in ["x", "y"] {
                seen[axis] = (saved.seen?[axis] ?? []).filter { $0.count == 2 }.map { ($0[0], $0[1]) }.suffix(12)
            }
        }
    }

    var calibrated: Bool { span != nil }
    /// Calibrated, not marked stale, and last measured within the calibration tolerance.
    var trusted: Bool { calibrated && !stale && (quality ?? 1) <= Self.calibrationTolerance }

    private func remember(_ axis: String, _ sample: (Double, Double)) {
        seen[axis] = Array((seen[axis, default: []] + [sample]).suffix(12))  // deque(maxlen=12)
    }

    /// Find the pointer on screen at two known distances from the corner and fit the mapping from both.
    /// Returns true when it calibrated itself; otherwise the user taps the pointer (finishCalibration).
    /// `progress` gets 0 (homing), then 1, 2 (each probe).
    func startCalibration(progress: ((Int) -> Void)? = nil) async throws -> Bool {
        pos = nil
        lastClick = nil
        progress?(0)
        try await device.send("home")
        var found: [(Int, Double, Double)] = []
        for (i, units) in Self.calibrationStops.enumerated() {
            progress?(i + 1)
            let step = units - (found.last?.0 ?? 0)
            try await device.send("move \(step) \(step)")
            guard let screen, screen.live, let p = try await findPointer() else { break }
            found.append((units, p.x, p.y))
        }
        if found.count < 2 {
            log("calibration: pointer not found on screen, waiting for a tap")
            if found.isEmpty {
                try await device.send("home")
                try await device.send("move \(Self.calibrationMove) \(Self.calibrationMove)")
            }
            return false
        }
        let (u1, x1, y1) = found[0], (u2, x2, y2) = found[1]
        let s = Span(w: Int((Double(u2 - u1) / (x2 - x1)).rounded(.toNearestOrEven)), h: Int((Double(u2 - u1) / (y2 - y1)).rounded(.toNearestOrEven)))
        span = s
        requiresFeedback = false
        (quality, aspect, stale) = (nil, screenAspect(), false)
        seen = ["x": [], "y": []]
        for (units, x, y) in found {  // where each stop landed, so moves are corrected for the offset too
            remember("x", (Double(units) / Double(s.w), x))
            remember("y", (Double(units) / Double(s.h), y))
        }
        save()
        log("calibration: span \(s.w) x \(s.h)")
        return true
    }

    /// Wiggle the pointer and find it anywhere on screen (the span may still be unknown).
    private func findPointer() async throws -> CGPoint? {
        guard let screen else { return nil }
        await screen.settled(quiet: 0.2, least: 0.3, most: 1.5)
        let before = screen.frame, sent = now()
        try await device.send("move \(Self.nudge) 0")
        var after = await screen.fresh(since: sent, timeout: 1.0)
        if after != nil {
            await screen.settled(quiet: 0.15, least: 0.1, most: 0.6)
            after = screen.frame
        }
        try await device.send("move -\(Self.nudge) 0")
        guard let before, let after else { return nil }
        let pixel = CommandChannel.onPad() ? Self.arrowBefore(before, after, near: CGPoint(x: 0.5, y: 0.5), nudge: Self.nudge, window: 0.5)
            : Vision.pointer(before, after, near: CGPoint(x: 0.5, y: 0.5), shift: 0.025, reach: CGPoint(x: 0.5, y: 0.5))
        var found = pixel
        if found == nil { found = await locate?(after) }
        guard let p = found else { return nil }
        if pixel == nil { log(String(format: "calibration: vision model found the pointer at (%.3f, %.3f)", p.x, p.y)) }
        return 0.03 < p.x && p.x < 0.97 && 0.03 < p.y && p.y < 0.97 ? p : nil
    }

    /// x, y: where the pointer ended up after startCalibration() (one point, picked by the user).
    func finishCalibration(x: Double, y: Double) {
        maps = nil
        lastClick = nil
        requiresFeedback = false
        (quality, aspect, stale) = (nil, screenAspect(), false)
        span = Span(w: Int((Double(Self.calibrationMove) / x).rounded(.toNearestOrEven)), h: Int((Double(Self.calibrationMove) / y).rounded(.toNearestOrEven)))
        seen = ["x": [], "y": []]
        save()
    }

    /// Touch-probe result: per-axis lines landed = a * units + b fitted from taps the app caught itself.
    /// The span is 1/a; every probe becomes a landing sample, so `fix` also corrects the offset b.
    @discardableResult func applyProbe(x: ProbeFit.Line, y: ProbeFit.Line, samples: [(ux: Double, uy: Double, fx: Double, fy: Double)], feedback: Bool = false) -> Bool {
        lastClick = nil  // calibration moved the pointer behind the tracked position
        if !provisional { backup = snapshot() }
        provisional = true
        let mx = ProbeMap(samples.map { ($0.ux, $0.fx) }), my = ProbeMap(samples.map { ($0.uy, $0.fy) })
        guard let mx, let my, x.a.isFinite, y.a.isFinite, x.a > 0, y.a > 0 else { discardProbe(); return false }
        guard (1...100_000).contains(1 / x.a), (1...100_000).contains(1 / y.a) else { discardProbe(); return false }
        maps = ["x": mx, "y": my]
        requiresFeedback = feedback
        let s = Span(w: Int((1 / x.a).rounded()), h: Int((1 / y.a).rounded()))
        span = s
        (quality, aspect, stale) = (max(mx.scatter, my.scatter), screenAspect(), false)
        seen = ["x": [], "y": []]
        for p in samples {  // an axis stopped at the border is no landing (logs27: x 0.998 broke the x correction)
            if ProbeFit.usable(p.fx) { remember("x", (p.ux / Double(s.w), p.fx)) }
            if ProbeFit.usable(p.fy) { remember("y", (p.uy / Double(s.h), p.fy)) }
        }
        pos = nil
        log(String(format: "calibration: touch probe span %d x %d, offset %.3f / %.3f, residual %.2f%%",
                   s.w, s.h, x.b, y.b, max(mx.scatter, my.scatter) * 100))
        // 174: the locating moves went slow, the probes fast: where they measured the screen apart, the slow pace's
        // ratio was off by as much (pushes past an edge go slow, scaled by it).
        if CommandChannel.onPad(), let located = CommandChannel.padLocatedSpan {
            CommandChannel.padLocatedSpan = nil
            let old = CommandChannel.padSlowRatio
            if let r = CommandChannel.correctedSlowRatio(old, located: located, probed: (s.w, s.h)) {
                CommandChannel.padSlowRatio = r
                log(String(format: "calibration: slow pace ratio %.2f → %.2f (located %d x %d, probed %d x %d)",
                           old, CommandChannel.padSlowRatio, located.w, located.h, s.w, s.h))
            }
        }
        return true
    }

    /// A measured check (e.g. a probe tap) as the current accuracy.
    @discardableResult func setQuality(_ q: Double) -> Bool {
        // A feedback calibration certifies corrected physical endpoints. The raw
        // map remains an uncertain initial estimate; retain its scatter separately.
        let measured = requiresFeedback ? q : max(q, maps?.values.map(\.scatter).max() ?? 0)
        guard q.isFinite, measured <= Self.calibrationTolerance else { discardProbe(); return false }
        quality = measured
        provisional = false
        backup = nil
        stale = false
        save()
        return true
    }

    var probeScatter: Double { maps?.values.map(\.scatter).max() ?? 1 }

    /// Failed/missing checks restore the previous parameters and mark them due for remeasurement.
    func discardProbe() {
        lastClick = nil
        if provisional {
            span = backup.map { Span(w: $0.w, h: $0.h) }
            maps = backup?.maps
            requiresFeedback = backup?.requiresFeedback ?? false
            quality = backup?.quality
            aspect = backup?.aspect
            seen = (backup?.seen ?? [:]).mapValues { $0.map { ($0[0], $0[1]) } }
        }
        (provisional, backup, pos, stale) = (false, nil, nil, true)
        save()
    }

    private func snapshot() -> Saved? {
        guard let span else { return nil }
        return Saved(w: span.w, h: span.h, seen: seen.mapValues { $0.map { [$0.0, $0.1] } }, quality: quality,
                     aspect: aspect, stale: stale ? true : nil, maps: maps, motionVersion: ProbeMotion.version,
                     requiresFeedback: requiresFeedback ? true : nil, borderLift: borderLiftY)
    }

    /// Calibration plus the observed landings, so the correction survives a restart.
    private func save() {
        guard !provisional, let saved = snapshot() else { return }
        try? JSONEncoder().encode(saved).write(to: file)
    }

    /// One gesture at a time. Over USB 11-09 the end of a run was going Home when the next command came: one gesture
    /// emptied `pos` while the other waited for the corner, and the next line crashed the app.
    private var gestureBusy = false
    private var gestureWaiters: [CheckedContinuation<Void, Never>] = []
    @TaskLocal private static var insideGesture = false

    @discardableResult
    private func oneAtATime<T>(_ body: () async throws -> T) async throws -> T {
        if Self.insideGesture { return try await body() }
        if gestureBusy { await withCheckedContinuation { gestureWaiters.append($0) } }
        gestureBusy = true
        defer { if gestureWaiters.isEmpty { gestureBusy = false } else { gestureWaiters.removeFirst().resume() } }
        return try await Self.$insideGesture.withValue(true) { try await body() }
    }

    func point(_ x: Double, _ y: Double, aim: Bool = false, rehome: Bool = true, edgeStart: Bool = false) async throws {
        guard calibrated else { throw DeviceError(message: "pointer not calibrated") }
        let border = !edgeStart && viaBorders(x, y)
        viaBorder = border && !belowReach(y)  // the lift learned is the right border's
        if border { try await fromBorder(x, y) }
        else { try await moveTo(dx(x), dy(y), rehome: rehome) }
        // Ordinary taps click at the calibrated map without looking for the pointer. On the dark WeChat screens the
        // pixel search found it 6 times in 31 (logs 11-06): every tap wiggled it ~5 times over 4–6 s, often walked it
        // after a misread and lost it, then clicked at this estimate anyway, and all of those taps landed. A tap that
        // changes nothing is aimed next time (missed); precise taps and system edge gestures still look first.
        if aim || (requiresFeedback && edgeStart) { try await self.aim(x, y, edgeStart: edgeStart, required: aim) }
    }

    /// Closed loop: find the real pointer on screen, fix a miss, look again, and learn the error for later moves.
    /// Each correction measures the real scale (mouse units per screen) from how far it moved the pointer, so a stale
    /// span is fixed within a tap instead of overshooting once and clicking there. A pointer stopped by the border
    /// says nothing about the scale: home, move half way, and measure from the corner.
    /// required: a precision tap (send button) corrects a seen pointer and never clicks while it is seen off target.
    /// Unseen, it clicks at the map's estimate only while the calibration is trusted (not stale, measured within
    /// tolerance): on dark screens the pixel diff rarely sees the pointer, and Claude's 发送 was withheld 17 times in
    /// a row until the run failed (logs 11-06, build87), while every unseen tap at the estimate landed. Otherwise
    /// feedback only improves the map's estimate: icons, wallpaper and photos hide the translucent pointer from the
    /// pixel diff (logs43: every home-screen tap was withheld, so every run failed).
    private func aim(_ x: Double, _ y: Double, edgeStart: Bool = false, required: Bool = false) async throws {
        guard let span else { throw DeviceError(message: "pointer not calibrated") }
        let unseenClicks = !required || trusted
        aimSaw = false
        guard var found = try await find(x, y) else {
            guard unseenClicks else {
                log(String(format: "aim (%.3f, %.3f): pointer not found", x, y))
                throw DeviceError(message: "Pointer position could not be verified; no click was sent. Keep the current draft and inspect again.")
            }
            log(String(format: "aim (%.3f, %.3f): pointer not found; clicking at the calibrated estimate", x, y))
            return
        }
        /// Lost while correcting: the corrections moved it somewhere unseen, so start over from the corner.
        func lost() async throws {
            pos = nil
            guard !unseenClicks else {
                log(String(format: "aim (%.3f, %.3f): pointer lost during correction; clicking at the calibrated estimate", x, y))
                if viaBorders(x, y) { try await fromBorder(x, y) } else { try await moveTo(dx(x), dy(y)) }
                return
            }
            throw DeviceError(message: "Pointer was lost during correction; no click was sent.")
        }
        // Only a system gesture may start from the visible cursor's border inset.
        // The other axis, ordinary taps and all calibration points stay exact.
        func error(_ found: Double, _ target: Double) -> Double {
            if edgeStart && ((0...0.01).contains(target) && (0...Self.gestureEdgeInset).contains(found)
                || (0.99...1).contains(target) && (1 - Self.gestureEdgeInset...1).contains(found)) { return 0 }
            return target - found
        }
        // A system swipe can start anywhere near its spot along the border: 1% along the home bar is no miss
        // (logs46: the pointer at 0.210 for 0.200 withheld the app switch and the paste hop lost its way).
        // A swipe that does not start on the border is no click: 0.9 % off (0.859 for 0.850, turning a Home Screen page)
        // failed the whole open, and three of those stopped a run over USB 11-09.
        let swipeStart = edgeStart && !(x <= 0.01 || x >= 0.99 || y <= 0.01 || y >= 0.99)
        let tolerance = (x: swipeStart || (edgeStart && (y <= 0.01 || y >= 0.99)) ? Self.edgeAlongTolerance : Self.aimTolerance,
                         y: swipeStart || (edgeStart && (x <= 0.01 || x >= 0.99)) ? Self.edgeAlongTolerance : Self.aimTolerance)
        func onTarget(_ p: CGPoint) -> Bool {
            abs(error(Double(p.x), x)) <= tolerance.x && abs(error(Double(p.y), y)) <= tolerance.y
        }
        let miss = max(abs(error(Double(found.x), x)), abs(error(Double(found.y), y)))
        if !edgeStart && maps == nil && miss <= Self.maxMiss && !pinned(found, x, y) {  // a probe map already contains its measured offsets
            remember("x", (fix(x, "x"), Double(found.x)))
            remember("y", (fix(y, "y"), Double(found.y)))
            save()
        }
        if !requiresFeedback && (miss > Self.maxMiss || pinned(found, x, y)) { markStale(miss, found, x, y) }
        var gain = (w: Double(span.w), h: Double(span.h))
        for _ in 0..<Self.aimPasses {
            let fx = Double(found.x), fy = Double(found.y)
            if onTarget(found) { break }
            if pinned(found, x, y) {
                if maps != nil { try await ProbeMotion.home(device) } else { try await device.send("home") }
                if CommandChannel.onPad() {  // 174: home is the middle, seen: go to the target from there and look
                    let h = homeUnits()
                    try await ProbeMotion.move(device, dx(x) - h.0, dy(y) - h.1)
                    pos = (dx(x), dy(y))
                    guard let p = try await find(x, y) else { return try await lost() }
                    found = p
                    continue
                }
                let ux = Int((x * gain.w / 2).rounded(.toNearestOrEven)), uy = Int((y * gain.h / 2).rounded(.toNearestOrEven))
                if maps != nil { try await ProbeMotion.move(device, ux, uy) } else { try await device.send("move \(ux) \(uy)") }
                pos = (ux, uy)
                guard let p = try await find(x, y) else { return try await lost() }
                if let g = measured(ux, 0, Double(p.x), x, gain.w) { gain.w = g }
                if let g = measured(uy, 0, Double(p.y), y, gain.h) { gain.h = g }
                found = p
                continue
            }
            let mx = Int((error(fx, x) * gain.w).rounded(.toNearestOrEven)), my = Int((error(fy, y) * gain.h).rounded(.toNearestOrEven))
            if maps != nil { try await ProbeMotion.move(device, mx, my) } else { try await device.send("move \(mx) \(my)") }
            if let p = pos { pos = (p.0 + mx, p.1 + my) }
            guard let p = try await find(x, y) else { return try await lost() }
            if abs(mx) >= 20, let g = measured(mx, fx, Double(p.x), x, gain.w) { gain.w = g }
            if abs(my) >= 20, let g = measured(my, fy, Double(p.y), y, gain.h) { gain.h = g }
            found = p
        }
        if stale { pos = nil }  // the tracked units used the wrong span: home before the next gesture
        guard onTarget(found) else {
            if swipeStart {
                log(String(format: "aim (%.3f, %.3f): still at (%.3f, %.3f); the swipe starts from there", x, y, found.x, found.y))
                return
            }
            pos = nil
            log(String(format: "aim (%.3f, %.3f): still at (%.3f, %.3f); click withheld", x, y, found.x, found.y))
            throw DeviceError(message: "Pointer is still off target after correction; no click was sent. Keep the current draft and inspect another route.")
        }
        log(String(format: "aim (%.3f, %.3f): verified at (%.3f, %.3f)", x, y, found.x, found.y))
        aimSaw = true
    }

    /// 181: the last aim saw the pointer on its target (not clicked at an estimate). 小藍's back arrow by a window's top
    /// is clicked only by a short hop from a spot where the pointer was seen like this.
    private(set) var aimSaw = false

    private func find(_ x: Double, _ y: Double) async throws -> CGPoint? {
        if let finder { return try await finder(x, y) }
        return try await measure(x, y, model: false)
    }

    /// Stopped by the screen border: near the edge and past the target towards it by more than maxMiss (f, t: found,
    /// target on one axis). Closer than that it is an ordinary miss (logs28: the back arrow at 0.06, found at 0.034).
    private static func stopped(_ f: Double, _ t: Double) -> Bool {
        (f > 1 - edge && f > t + maxMiss) || (f < edge && f < t - maxMiss)
    }

    private func pinned(_ p: CGPoint, _ x: Double, _ y: Double) -> Bool {
        Self.stopped(Double(p.x), x) || Self.stopped(Double(p.y), y)
    }

    /// Mouse units per screen from one move (from -> to), when it went far enough, did not end on the border, and is
    /// within a sane range of the current estimate.
    private func measured(_ units: Int, _ from: Double, _ to: Double, _ target: Double, _ current: Double) -> Double? {
        let moved = to - from
        guard abs(moved) > 0.02, !Self.stopped(to, target) else { return nil }
        let g = Double(units) / moved
        return 0.4 * current < g && g < 2.5 * current ? g : nil
    }

    private func markStale(_ miss: Double, _ found: CGPoint, _ x: Double, _ y: Double) {
        let border = pinned(found, x, y) ? " against the border" : ""
        log(String(format: "aim (%.3f, %.3f): pointer at (%.3f, %.3f)", x, y, Double(found.x), Double(found.y))
            + border + ", calibration marked stale")
        if !stale { stale = true; quality = miss; save() }
    }

    /// Wiggle the pointer and find it on screen, near the target first, then anywhere. model: ask the vision
    /// model when the pixels don't show it (~20 s, rarely right); a tap's aim never waits for that.
    private func measure(_ x: Double, _ y: Double, model: Bool = true) async throws -> CGPoint? {
        guard let screen, let span else { return nil }
        let nudge = x < 0.9 ? Self.nudge : -Self.nudge  // stay clear of the screen edge
        await screen.settled(quiet: 0.15, least: 0.1, most: 0.6)  // pointer at rest
        try await device.send("move \(nudge) 0")
        // A frame captured while the BLE command was in flight can still precede the actual move.
        var after = await screen.fresh(since: now(), timeout: 1.2)
        if after != nil {
            await screen.settled(quiet: 0.1, least: 0.05, most: 0.4)
            after = screen.frame
        }
        try await device.send("move \(-nudge) 0")
        let restored = await screen.fresh(since: now(), timeout: 1.2)
        let shift = Double(nudge) / Double(span.w)
        guard let restored, let after else { return nil }
        // The inverse move need not return to exactly the old point. Locate the pointer where it NOW is,
        // rather than clicking on the assumption that undoing relative mouse units restored it.
        if CommandChannel.onPad() {  // 174: the arrow, where it is in `restored`
            if let p = Self.arrowBefore(restored, after, near: CGPoint(x: x, y: y), nudge: nudge, window: 0.5) { return p }
        } else if let p = Vision.pointer(restored, after, near: CGPoint(x: x, y: y), shift: shift)
            ?? Vision.pointer(restored, after, near: CGPoint(x: 0.5, y: 0.5), shift: shift, reach: CGPoint(x: 0.5, y: 0.5)) {
            return p
        }
        return model ? await locate?(restored) : nil
    }

    /// Calibration check without tapping: move to a known point and measure the miss (fraction of the screen).
    /// nil when the pointer could not be found.
    func verify(x: Double = 0.5, y: Double = 0.62) async throws -> Double? {
        try await point(x, y)
        guard let found = try await measure(x, y) else { return nil }
        let error = max(abs(Double(found.x) - x), abs(Double(found.y) - y))
        quality = error
        save()
        return error
    }

    /// How far the learned correction has moved targets away from the plain calibration (fraction of the screen).
    var drift: Double {
        if maps != nil { return 0 }  // the nonlinear map is the calibration, not accumulated drift
        return [0.2, 0.8].flatMap { t in ["x", "y"].map { abs(fix(t, $0) - t) } }.max() ?? 0
    }

    /// Demo data: pretend a calibration with this quality.
    func mockCalibrated(quality: Double) {
        span = span ?? Span(w: 400, h: 860)
        self.quality = quality
    }

    /// The fraction to aim at so the pointer lands on t, from the line through the observed landings.
    func fix(_ t: Double, _ axis: String) -> Double {
        if let map = maps?[axis], let span {
            return Double(map.units(for: t)) / Double(axis == "x" ? span.w : span.h)
        }
        let pts = seen[axis] ?? []
        guard pts.count >= 2 else { return t }
        let n = Double(pts.count)
        let mc = pts.map(\.0).reduce(0, +) / n, mf = pts.map(\.1).reduce(0, +) / n
        let variance = pts.map { pow($0.0 - mc, 2) }.reduce(0, +)
        var a = variance > 1e-4 ? pts.map { ($0.0 - mc) * ($0.1 - mf) }.reduce(0, +) / variance : 1.0  // landed = a*aimed + b
        a = 0.85 < a && a < 1.15 ? a : 1.0
        let b = mf - a * mc
        return abs(b) < 0.1 ? (t - b) / a : t
    }

    private func moveTo(_ tx: Int, _ ty: Int, rehome: Bool = true, positioning: Bool = true) async throws {
        if link != device.links {  // new link: a dropped gesture may have left the button down
            try await device.send("release")
            (pos, link) = (nil, device.links)
        }
        // 180 (user 11-25: "从这边到那边要立马过来，而不是中间还要差一个路"): on an iPad, where the arrow is seen and
        // every sighting sets `pos`, a move goes straight from where the pointer is; it looks for it only when lost.
        if pos == nil || (!CommandChannel.onPad() && rehome && (maps != nil || moves >= Self.rehomeEvery)) {
            let homing = now()
            if maps != nil { try await ProbeMotion.home(device) } else { try await device.send("home") }
            (pos, moves, hops) = (homeUnits(), 0, 0)
            await noteCorner(since: homing)
        }
        guard let (x, y) = pos else { throw DeviceError(message: "pointer position lost; no move was sent") }
        pos = nil  // unknown until the move succeeds
        if maps != nil && positioning { try await ProbeMotion.move(device, tx - x, ty - y) }
        else { try await device.send("move \(tx - x) \(ty - y)") }
        (pos, moves) = ((tx, ty), moves + 1)
    }

    /// Right of the farthest calibrated landing the map only extrapolates: logs(12), 267 units meant for 0.899 (the
    /// alarm's ✓) landed at 0.975, the pointer on the dark sheet was not found, and 14 taps there did nothing.
    func beyondReach(_ x: Double) -> Bool {
        guard let mx = maps?["x"] else { return false }
        return x > min(mx.reach + 0.01, Self.farRight)
    }

    /// The map's far end is not good enough even when it reaches there. Over USB 11-09 and 11-10, from the corner to targets
    /// right of 0.7: a median 0.07 short (Meituan's 搜索 at 0.89, clicked at its edge and then on the box's clear button, so the
    /// search never ran), against 0.006 to 0.039 from the right border. The border is an exact reference.
    /// Build 116 over the cloud, 11-10: WeChat's icon at x 0.848, just inside the old 0.85, was missed twice on every open.
    static let farRight = 0.75

    /// The bottom rows (tab bars, Safari's address bar, toolbars) come back from the bottom border the same way. Build 116
    /// over the cloud, 11-10: moves from the corner landed on the bottom border (0.994 for 0.937), the bar's button lit up in
    /// place of the pointer, and Clock's 鬧鐘 tab, Safari's address bar and Notes' toolbar were clicked under, time after time
    /// (three tasks timed out). Over USB the same day, pushed against the bottom and brought back 20, 40 and 60 units, the
    /// pointer stood at 0.97, 0.94 and 0.91: on the tab.
    static let farBottom = 0.9

    func belowReach(_ y: Double) -> Bool { maps?["y"] != nil && y > Self.farBottom }
    /// 174: never on an iPad (its home is the middle, seen; pushes past the bottom bring in the Dock).
    func viaBorders(_ x: Double, _ y: Double) -> Bool { !CommandChannel.onPad() && (beyondReach(x) || belowReach(y)) }

    /// The right border is an exact reference: home, push the pointer against it at the target's row, then come back
    /// the short distance, which the map measured (the same move from the left border lands that far in).
    private func fromBorder(_ x: Double, _ y: Double) async throws {
        guard let mx = maps?["x"], let my = maps?["y"] else { return try await moveTo(dx(x), dy(y)) }
        if link != device.links {  // new link: a dropped gesture may have left the button down
            try await device.send("release")
            (pos, link) = (nil, device.links)
        }
        let homing = now()
        try await ProbeMotion.home(device)
        pos = nil
        await noteCorner(since: homing)
        let right = beyondReach(x), bottom = belowReach(y)
        let back = right ? mx.units(for: 1 - x) : 0
        // 168: on an iPad a push far past the bottom goes to the Home Screen (and past the right edge opens Slide Over):
        // from the corner it goes only padMargin past the border (tested harmless), not 1.5 screens.
        let pad = CommandChannel.onPad()
        if right {
            // y last: after the 400+ unit push it landed 0.027 low (live test 11-08, the alarm's ✓), against 0.012 after an
            // ordinary move; after the short way back it follows a move like the calibrated ones.
            let push = pad ? mx.units(for: 1) + CommandChannel.padMargin : max(mx.units(for: 1) * 3 / 2, 400)
            try await ProbeMotion.move(device, push, 0)
            try await Task.sleep(nanoseconds: 150_000_000)
            try await ProbeMotion.move(device, -back, 0)
            try await Task.sleep(nanoseconds: 150_000_000)
        } else {
            try await ProbeMotion.move(device, dx(x), 0)
        }
        if bottom {
            let up = my.units(for: 1 - y)
            let push = pad ? my.units(for: 1) + CommandChannel.padMargin : max(my.units(for: 1) * 3 / 2, 600)
            try await ProbeMotion.move(device, 0, push)
            try await Task.sleep(nanoseconds: 150_000_000)
            try await ProbeMotion.move(device, 0, -up)
            log(String(format: "point (%.3f, %.3f): a bottom row; from the bottom border, %ld units up", x, y, up))
        } else {
            try await ProbeMotion.move(device, 0, dy(y - borderLiftY))
        }
        (pos, moves, hops) = ((dx(x), dy(y)), 1, 0)  // where it lands, the lift taken off
        if right { log(String(format: "point (%.3f, %.3f): past the calibrated %.3f; from the right border, %ld units back", x, y, mx.reach, back)) }
    }

    /// Let go of the button and re-home the pointer, whatever state a gesture left.
    func reset() async throws {
        pos = nil
        lastClick = nil
        drawChain = false
        unitsSinceDrawHome = 0
        try await device.send("release")
        if maps != nil { try await ProbeMotion.home(device) } else { try await device.send("home") }
        (pos, moves) = (homeUnits(), 0)
    }

    /// 169 (iPad calibration): the pointer rests where a probe's click was caught, `ux, uy` units from the corner; the
    /// next taps hop on from there instead of going back to the corner.
    func restAt(ux: Int, uy: Int, x: Double, y: Double) {
        Self.syncPad(CGPoint(x: x, y: y))  // 176
        pos = (ux, uy)
        lastClick = LastClick(x: x, y: y, ux: ux, uy: uy, link: device.links, time: Date().timeIntervalSince1970)
        hops = 0
    }

    /// Calibration check: the pointer still rests where its real click landed; move it by the measured miss
    /// (screen fractions) and click there, without re-homing.
    func clickBy(_ ex: Double, _ ey: Double) async throws {
        guard let span else { throw DeviceError(message: "pointer not calibrated") }
        let mx = Int((ex * Double(span.w)).rounded(.toNearestOrEven)), my = Int((ey * Double(span.h)).rounded(.toNearestOrEven))
        if maps != nil { try await ProbeMotion.move(device, mx, my) } else { try await device.send("move \(mx) \(my)") }
        if let p = pos { pos = (p.0 + mx, p.1 + my) }
        try await device.send("click")
        try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
    }

    /// A tap starts from the corner, except a tap again on the spot just clicked: the pointer still rests where that
    /// click landed, so it clicks again without moving (logs(9) 11-08: five globe-key taps each went back to the
    /// corner first, ~3 s apiece). aim: find the pointer and correct it first, and never click unseen; an aimed tap
    /// always moves, since it follows a tap that changed nothing.
    func tap(_ x: Double, _ y: Double, aim: Bool = false) async throws { try await oneAtATime { try await tapNow(x, y, aim: aim) } }
    private func tapNow(_ x: Double, _ y: Double, aim: Bool) async throws {
        defer { targetHalf = nil }  // for one tap only
        if aim { targetHalf = nil }  // an aimed tap (after one that changed nothing) lands on the spot
        drawChain = false  // a tap ends a drawing run: its drift must not carry into the next stroke
        if y < Self.bannerBand { try await swipeAwayStuckBanner() }  // D116
        var before = screen?.frame, began = now()  // the screen before the move: where the pointer arrives is what changes
        defer { lastSpot = CGPoint(x: x, y: y) }
        if !aim, let last = lastClick, let p = pos, Self.clickAgain(last, x, y, units: p, link: device.links, at: Date().timeIntervalSince1970) {
            if clicksInPlace < Self.clicksInPlaceLimit {
                clicksInPlace += 1
                log(String(format: "tap (%.3f, %.3f): same spot as the last click; clicking again without moving", x, y))
                try await clearOfBanners(y)
                let clickedAt = now()
                try await device.send("click")
                lastClick?.time = Date().timeIntervalSince1970
                try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
                try await answerIfAsked(x, y, clickedAt: clickedAt, before: before)
                return
            }
            // Over USB 11-09: seven clicks here on Safari's address bar did nothing; the pointer lay at the bottom border.
            log(String(format: "tap (%.3f, %.3f): clicked here %ld times again; from the corner this time", x, y, clicksInPlace))
            (lastClick, pos) = (nil, nil)
        }
        clicksInPlace = 0
        // D102, user 11-17 ("每次这个光标都要从左上角重新去点"): 139's runs, 440 taps: 298 went back to the corner first
        // (median 4.9 s from the first move to the click, against 2.8 s for a hop), 170 of them for a target in the top
        // band. A hop now goes there too, but near the top it clicks only where the pointer is seen on the target:
        // unseen or off there (the reason the top band went from the corner: a hop's estimate is the worse one), it goes
        // from the corner after all, and clicks as before. The status bar's clock (a click there stops the sharing)
        // stays from the corner.
        // D151, user 11-19 ("必须走曲线，而且是随机曲线，起点不固定，弧度也是随机，长度也随机，只有终点固定对了就行"): 145's
        // regression, 603 taps: 338 still went back to the corner first, 198 of them for the right side (x > 0.75, the
        // right border) and 110 for the bottom rows (the bottom border). Those hop from where the pointer rests too, and
        // like the top band click only where the pointer is seen on the target; unseen or off there, they go by the
        // border after all, as before (hopNeedsCorner).
        if !aim, !stale, !Self.nearClock(x, y), let last = lastClick, let p = pos, hops < Self.nearbyHops,
           Self.canHop(last, units: p, link: device.links, at: Date().timeIntervalSince1970) {
            // User 11-08: go straight to the next spot from where the pointer rests (the board still curves the
            // move), not back to the top-left corner first. A re-home every few hops keeps the error from adding up;
            // an aimed tap (after one that changed nothing) always starts from the corner.
            // 180: one move, no stop short (176's 85%); the look corrects, the gate keeps it off the edges.
            let (ux, uy) = hopUnits(from: last, to: x, y, units: p)
            lastClick = nil
            pos = nil
            if maps != nil { try await ProbeMotion.move(device, ux, uy) } else { try await device.send("move \(ux) \(uy)") }
            (pos, hops, moves) = ((p.0 + ux, p.1 + uy), hops + 1, moves + 1)
            log(String(format: "tap (%.3f, %.3f): hop %ld from (%.3f, %.3f)", x, y, hops, last.x, last.y))
            // 126 over the cloud 11-12 (g6): Taobao's 购物车 at (0.300, 0.916) was seen at (0.472, 0.953), "too far to
            // trust", and clicked there six times: on 加入购物车, five more in the cart. Seen off target, the wiggle
            // search finds the pointer and corrects it before the click (2-4 s, only then).
            startedOver = false
            let arrival = try await arrive(x, y, before: before, began: began)
            if Self.hopNeedsCorner(y: y, border: viaBorders(x, y), arrival: arrival, startedOver: startedOver,
                                   pad: CommandChannel.onPad()) {
                log(String(format: "tap (%.3f, %.3f): hop %ld not seen on the target near the top or a border; from the corner after all", x, y, hops))
                (before, began) = (screen?.frame, now())
            } else {
                if arrival == .offTarget { try await self.aim(x, y) }
                // D102: a hop seen on the target starts the next from a known spot; only hops not seen add up.
                if arrival == .onTarget { hops = 0 }
                try await clearOfBanners(y)
                let clickedAt = now()
                try await device.send("click")
                if let q = pos { lastClick = LastClick(x: x, y: y, ux: q.0, uy: q.1, link: device.links, time: Date().timeIntervalSince1970) }
                try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
                try await answerIfAsked(x, y, clickedAt: clickedAt, before: before)
                return
            }
        }
        lastClick = nil
        pos = nil
        // Going back near where the pointer rests, the frame before the move already shows it there: it comes back to
        // the same wrong spot, nothing changes and the eye sees nothing (over USB 11-09: Clock's icon tapped 15 times,
        // always the same miss). The frame to compare against is then the one with the pointer in the corner.
        cornerLook = lastSpot.map { hypot($0.x - x, $0.y - y) < Self.restsNear } ?? false
        cornerFrame = nil
        defer { cornerLook = false }
        try await point(x, y, aim: false)
        if let corner = cornerFrame { (before, began) = (corner.data, corner.at) }
        if aim {
            // a precise tap: the arrival check first; the older wiggle search only if it did not see the pointer there
            if try await arrive(x, y, before: before, began: began) != .onTarget { try await self.aim(x, y, required: true) }
        } else {
            // 126 over the cloud 11-12 (g6): Taobao's 购物车 at (0.300, 0.916) was seen at (0.472, 0.953), "too far to
            // trust", and clicked there six times: on 加入购物车, five more in the cart. Seen off target, the wiggle
            // search finds the pointer and corrects it before the click (2-4 s, only then).
            if try await arrive(x, y, before: before, began: began) == .offTarget { try await self.aim(x, y) }
        }
        if viaBorder, let first = firstSeen { learnBorderLift(missedBy: Double(first.y) - y) }
        try await clearOfBanners(y)
        let clickedAt = now()
        try await device.send("click")
        if let p = pos { lastClick = LastClick(x: x, y: y, ux: p.0, uy: p.1, link: device.links, time: Date().timeIntervalSince1970) }
        try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
        try await answerIfAsked(x, y, clickedAt: clickedAt, before: before)
    }

    /// Where the pointer was first seen after the last move (nil: not seen).
    private var firstSeen: CGPoint?
    /// Whether the last move came back from the right border.
    private var viaBorder = false
    /// How far below the target a move back from the right border lands, learned from where it is seen. Over USB 11-09 and 11-10
    /// all 16 such landings seen were 0.029 to 0.042 low (0.027 on 11-08), against a median 0.004 from the corner: a button at
    /// the top right is 0.05 tall, so the half of them nobody sees clicked under it.
    /// 128 over the cloud 11-13 (g1): it started at 0 on every app launch and the Home Screen never shows the pointer, so
    /// nothing was learned there: WeChat (0.848, 0.722) and Calculator (0.846, 0.488) in the right column were missed 5 times
    /// at lift 0 and 0.016 (59.5 s and 25.6 s to open), never at 0.037-0.041. It starts at the usual bias and is saved.
    private(set) var borderLiftY = Pointer.borderLiftStart

    /// 129 over the cloud 11-13 (g1): from 0.035, landings read -0.009, -0.035, -0.073 and +0.057 off took it to -0.023 in
    /// three steps, and Calculator and Meituan in the right column were each missed twice (28 s and 29 s to open). The bias
    /// is a steady one (0.03-0.05 low every time over USB): a reading 0.05 off is another thing taken for the pointer, and
    /// each reading moves it a quarter of the way.
    func learnBorderLift(missedBy error: Double) {
        guard abs(error) < Self.borderMisreading else { return }  // too far to be the same pointer
        borderLiftY = min(max(borderLiftY + error / 4, -Self.borderLiftLimit), Self.borderLiftLimit)
        log(String(format: "border landing %.3f off in y; lift now %.3f", error, borderLiftY))
        save()
    }

    static let borderLiftStart = 0.035

    static let borderMisreading = 0.05
    static let borderLiftLimit = 0.06

    private var clicksInPlace = 0
    static let clicksInPlaceLimit = 2

    /// Thin bars sit at the top, and the corner is close to them. Landings over USB 11-08 and 11-09 with targets above this
    /// line: a hop was off by more than 0.02 in y 45 % of the time (p90 0.065; x 0.102), from the corner 30 % (0.034; x 0.029),
    /// and on the left half never (0.012). A hop meant for Taobao's search bar opened the channel whose icon is under it.
    static let topBand = 0.2

    /// The clock at the top left is red while the screen is shared, and a click on it asks "stop sharing the screen with
    /// Lan Agent?". User 11-09: Cancel, never Stop. While that is up nothing is captured and nothing says so. Over USB 11-09:
    /// frames stopped at once and stayed away (16 s and counting, sharing still "on"), no frame shows the question, and a tap
    /// here with nothing to look at brought them back in 1.6 s. Cancel spans x 0.11-0.48, y 0.52-0.58; Stop is past the middle.
    static let cancelSharing = (x: 0.29, y: 0.555)

    static func nearClock(_ x: Double, _ y: Double) -> Bool { x < 0.4 && y < 0.12 }

    /// Frames still come for a moment after the click that asks: the last one 0.2 to 0.4 s later over USB 11-09, and build 112
    /// took that one for "not asked" and left the question up, frames stopped for 35 s until something else tapped Cancel.
    static let lastFrameAfterAsking = 0.8

    /// After a click near the clock (the back button is right under it): frames go on coming, unless it asked.
    private func answerIfAsked(_ x: Double, _ y: Double, clickedAt: Double, before: Data? = nil) async throws {
        guard Self.nearClock(x, y), let screen, screen.live else { return }
        let settled = clickedAt + Self.lastFrameAfterAsking
        if let fresh = await screen.fresh(since: settled, timeout: max(0, settled - now()) + 2) {
            // B6, 122 on the phone 11-11: in Settings › Keyboard frames went on coming, the whole screen darker, and
            // the back button, Home and the next app did nothing: the question was up, its dimming captured, itself not.
            if let before, Vision.dimmed(before, fresh) {
                log("the screen dimmed after a click near the clock: the question whether to stop sharing; tapping Cancel")
                _ = try await tapCancelSharing()
            }
            return
        }
        // A click that changed nothing shows nothing new either; a small move must.
        let nudged = now()
        if maps != nil {
            try await ProbeMotion.move(device, 8, 0)
            try await ProbeMotion.move(device, -8, 0)
        } else {
            try await device.send("move 8 0")
            try await device.send("move -8 0")
        }
        if await screen.fresh(since: nudged, timeout: 1.5) != nil { return }
        _ = try await tapCancelSharing()
    }

    /// Whether frames came back. For whoever finds them stopped and knows nothing of a click near the clock.
    func answerSharingQuestion() async throws -> Bool { try await oneAtATime { try await tapCancelSharing() } }

    private func tapCancelSharing() async throws -> Bool {
        for attempt in 1...2 {
            log("frames stopped: tapping Cancel on the question whether to stop sharing the screen (try \(attempt))")
            (lastClick, pos) = (nil, nil)  // from the corner: where the pointer really is may be how this came up
            let tapped = now()
            try await tapNow(Self.cancelSharing.x, Self.cancelSharing.y, aim: false)
            if let screen, await screen.fresh(since: tapped, timeout: 2) != nil {
                log("frames are back")
                return true
            }
        }
        log("frames did not come back after tapping Cancel")
        return false
    }

    /// Back where the estimate said, after moves made for something that was not the pointer. Going back the way it came only
    /// works if nothing stopped it. Over USB 11-09 three corrections went 260 units up from 100 under the top edge, the 260
    /// back left it 160 too low, on another card, and every hop after that carried the error: Taobao Live, the order list, an
    /// order. The corner is the one place it can be sent to for sure.
    private func startOver(_ x: Double, _ y: Double) async throws {
        pos = nil
        startedOver = true
        if viaBorders(x, y) { try await fromBorder(x, y) } else { try await moveTo(dx(x), dy(y)) }
    }

    /// Told to go one way and seen going the other: what was seen is not the pointer (over USB 11-09: told up, seen from
    /// (0.301, 0.175) to (0.179, 0.265), and the next two "corrections" of 112 units went against the top edge).
    static func wentAgainst(from a: CGPoint, to b: CGPoint, units ux: Int, _ uy: Int) -> Bool {
        let (mx, my) = (Double(b.x - a.x), Double(b.y - a.y))
        return hypot(mx, my) > jumpLimit / 2 && mx * Double(ux) + my * Double(uy) < 0
    }

    /// Where the last tap aimed: about where the pointer rests.
    private var lastSpot: CGPoint?
    private var cornerLook = false
    /// D102: the arrival check went back to the corner and came again (a hop's landing is then not what is checked).
    private var startedOver = false
    private var cornerFrame: (data: Data, at: Double)?
    /// A target this close to where the pointer rests (a landing can be 9 % off) needs the look from the corner.
    static let restsNear = 0.12

    /// The pointer has just gone to the corner: keep the frame that shows it there, if this tap needs it.
    private func noteCorner(since began: Double) async {
        guard cornerLook, let screen else { return }
        let shown = await stopped(since: began, on: screen, wait: 0.5) ?? screen.frame
        cornerFrame = shown.map { (data: $0, at: now()) }
    }

    enum Arrival { case onTarget, unseen, offTarget }
    /// What the last tap's arrival check saw (nil: the tap clicked again in place, no move to check).
    var lastArrival: Arrival?

    /// Closed loop for every tap (user 11-08: make it tap right, not patch by patch). Open-loop moves land 3–7 % off
    /// (curved moves through iOS's pointer acceleration; the calibration's own note: one command scatters up to 5 %):
    /// the live test's ✓ at (0.895, 0.108) was reached at (0.890, 0.135), a hop meant for 0.395 at 0.461. The pointer
    /// is found where it arrived (Vision.arrival: the frame before the move against the first frame after it), a miss
    /// is corrected by a short move (short moves are near linear) and looked at once more. Unseen (the screen itself
    /// changed there), the click goes at the estimate as before.
    @discardableResult
    /// 174: where the pointer arrived: an iPad's is an arrow (Vision.arrow), an iPhone's a disk (Vision.arrival).
    /// 176: where the arrow was seen is where the board's tracked place (CommandChannel.padPos) is: the two kept apart
    /// let a hop's split at an edge go wrong (175: the check meant for 0.82 went to 0.98, by the Dock).
    /// 176: within a fifth of the screen of the top, the left or the bottom (the right edge brings nothing in).
    static func nearGuardedEdge(_ x: Double, _ y: Double) -> Bool { x < 0.2 || y < 0.2 || y > 0.8 }

    static func syncPad(_ seen: CGPoint) {
        guard CommandChannel.onPad() else { return }
        CommandChannel.padPos = (Int(Double(seen.x) * Double(CommandChannel.padSpan.w)), Int(Double(seen.y) * Double(CommandChannel.padSpan.h)))
    }

    static func sighting(_ before: Data, _ after: Data, near: CGPoint) -> CGPoint? {
        CommandChannel.onPad() ? Vision.arrow(before, after, near: near) : Vision.arrival(before, after, near: near)
    }

    /// 174: where an iPad's arrow was before a sideways nudge of `nudge` units: of two tips on one row the one on the
    /// side it came from; one tip (the spots overlapped) is that spot; otherwise the tip nearest `near`.
    static func arrowBefore(_ before: Data, _ after: Data, near: CGPoint, nudge: Int, window: Double = 0.25) -> CGPoint? {
        pickBefore(Vision.arrows(before, after, near: near, window: window), near: near, nudge: nudge)
    }
    static func pickBefore(_ tips: [CGPoint], near: CGPoint, nudge: Int) -> CGPoint? {
        if tips.count == 1 { return tips[0] }
        for a in tips {
            for b in tips where b != a && abs(b.y - a.y) < 0.02 && abs(b.x - a.x) < 0.1 {
                // a is where it was when b lies the way the nudge went
                if (nudge > 0 && b.x > a.x) || (nudge < 0 && b.x < a.x) { return a }
            }
        }
        return tips.min { hypot($0.x - near.x, $0.y - near.y) < hypot($1.x - near.x, $1.y - near.y) }
    }

    func arrive(_ x: Double, _ y: Double, before: Data?, began: Double) async throws -> Arrival {
        let seen = try await look(x, y, before: before, began: began)
        lastArrival = seen
        return seen
    }

    /// Accuracy test 11-08 (sharing on, real touches): where the eye saw the pointer it was right to 0.1-0.2 %, but
    /// 9 of 20 taps never looked and the corrections did not land. Three causes, measured there:
    /// - Direct capture publishes only on change, at most every 0.25 s. The frame of the pointer stopping often came
    ///   in before the move command answered, and the wait for a "new" frame began after the answer: none came.
    ///   The wait now begins when the move began, then lets one publish period pass so the last change is in.
    /// - The board sends 4 units as one count and keeps the rest for the next move, and one count moves the pointer
    ///   3-7 pt: corrections of 2-5 units often sent nothing, and the one correction was never looked at again.
    ///   Corrections now repeat, looking each time, until each axis is within the tolerance; what a unit really
    ///   moved is learned from what was seen.
    /// - After a correction of a few pixels the old and new disks overlap and their diff shows no disk: every look
    ///   compares against the frame before the whole move, where the pointer was elsewhere.
    private func look(_ x: Double, _ y: Double, before: Data?, began: Double) async throws -> Arrival {
        // Accuracy test 11-08: after a relaunch screen sharing was off, every tap skipped this without a word and
        // 20 spots were blind. No frame is said, every time.
        firstSeen = nil
        guard let screen, let span else { return .unseen }
        guard let before else {
            log(String(format: "arrive (%.3f, %.3f): no screen frame before the move (screen sharing off?); clicking at the estimate", x, y))
            return .unseen
        }
        let target = CGPoint(x: x, y: y)
        guard let first = await stopped(since: began, on: screen, wait: 0.9) else {
            log(String(format: "arrive (%.3f, %.3f): no frame after the move; clicking at the estimate", x, y))
            return .unseen
        }
        guard var seen = Self.sighting(before, first, near: target) else {
            log(String(format: "arrive (%.3f, %.3f): pointer not seen; clicking at the estimate", x, y))
            return .unseen
        }
        firstSeen = seen
        Self.syncPad(seen)  // 176
        if CommandChannel.onPad() { pos = (dx(Double(seen.x)), dy(Double(seen.y))) }  // 180: where it really is
        var corrections = 0, unmoved = 0
        while true {
            let ex = x - Double(seen.x), ey = y - Double(seen.y)
            let offX = abs(ex) > Self.arrivalTolerance, offY = abs(ey) > Self.arrivalTolerance
            if !offX && !offY {
                log(String(format: "arrive (%.3f, %.3f): seen at (%.3f, %.3f) after %ld correction(s)", x, y, seen.x, seen.y, corrections))
                return .onTarget
            }
            // Test build 11-12: 476 taps on the phone, 95% corrected at 2.0 s each, though 88% of first stops were already
            // inside a target the size of an input box. Inside the target's own bounds is close enough.
            if let half = targetHalf, abs(ex) <= half.x, abs(ey) <= half.y {
                log(String(format: "arrive (%.3f, %.3f): seen at (%.3f, %.3f), inside the target (±%.3f, ±%.3f): no correction",
                           x, y, seen.x, seen.y, half.x, half.y))
                return .onTarget
            }
            // 176 (175 on the iPad, 11-25: a check seen at (0.946, 0.980) for (0.880, 0.820) was "too far to trust", clicked at
            // the estimate on the bottom edge and missed): an iPad's arrow is found by itself, so it is corrected from farther.
            Self.syncPad(seen)
            guard max(abs(ex), abs(ey)) <= (CommandChannel.onPad() ? 0.6 : 0.15) else {
                log(String(format: "arrive (%.3f, %.3f): seen at (%.3f, %.3f), too far to trust; clicking at the estimate", x, y, seen.x, seen.y))
                return .offTarget
            }
            guard corrections < Self.maxCorrections else {
                log(String(format: "arrive (%.3f, %.3f): seen at (%.3f, %.3f), still off after %ld corrections", x, y, seen.x, seen.y, corrections))
                return .offTarget
            }
            let ux = offX ? Self.fineUnits(ex, perUnit: fineX ?? 1 / Double(span.w)) : 0
            let uy = offY ? Self.fineUnits(ey, perUnit: fineY ?? 1 / Double(span.h)) : 0
            log(String(format: "arrive (%.3f, %.3f): seen at (%.3f, %.3f); correcting by %ld, %ld units", x, y, seen.x, seen.y, ux, uy))
            corrections += 1
            let moved = now()
            if maps != nil { try await ProbeMotion.move(device, ux, uy) } else { try await device.send("move \(ux) \(uy)") }
            if let p = pos { pos = (p.0 + ux, p.1 + uy) }
            // Nothing on screen changed: the board held the counts back (it keeps a remainder); the same again sends them.
            guard let after = await stopped(since: moved, on: screen, wait: 0.6) else { continue }
            guard let next = Self.sighting(before, after, near: target) else {
                log(String(format: "arrive (%.3f, %.3f): pointer not seen after a correction; clicking at the estimate", x, y))
                return .unseen
            }
            // What was seen jumped far past the move: a key lighting up, not the pointer (over USB 11-09: (0.368, 0.544), then
            // after 4 units (0.361, 0.424) on Calculator's AC, and the next "correction" of 83 units pressed the wrong key).
            let commanded = hypot(Double(ux) * (fineX ?? 1 / Double(span.w)), Double(uy) * (fineY ?? 1 / Double(span.h)))
            if Double(hypot(next.x - seen.x, next.y - seen.y)) > max(Self.jumpLimit, 3 * commanded)
                || Self.wentAgainst(from: seen, to: next, units: ux, uy) {
                log(String(format: "arrive (%.3f, %.3f): what was seen jumped to (%.3f, %.3f); not the pointer, starting over from the corner", x, y, next.x, next.y))
                try await startOver(x, y)
                return .unseen
            }
            // What was seen does not follow the moves: it is not the pointer, and the moves only pulled the real one away.
            unmoved = hypot(next.x - seen.x, next.y - seen.y) < 0.002 ? unmoved + 1 : 0
            if unmoved >= 2 {
                log(String(format: "arrive (%.3f, %.3f): what was seen at (%.3f, %.3f) does not move; starting over from the corner", x, y, next.x, next.y))
                try await startOver(x, y)
                return .unseen
            }
            if ux != 0 { fineX = Self.learned(fineX ?? 1 / Double(span.w), moved: Double(next.x - seen.x), units: ux) }
            if uy != 0 { fineY = Self.learned(fineY ?? 1 / Double(span.h), moved: Double(next.y - seen.y), units: uy) }
            seen = next
            if CommandChannel.onPad() { pos = (dx(Double(seen.x)), dy(Double(seen.y))) }  // 180
        }
    }

    /// The newest frame once the pointer has stopped after a move that began at `began`: something captured since
    /// then, and then one publish period with nothing newer, so the last change is in. nil: nothing changed.
    private func stopped(since began: Double, on screen: ScreenSource, wait: Double) async -> Data? {
        guard await screen.fresh(since: began, timeout: wait) != nil else { return nil }
        let answered = now(), cap = answered + 0.8
        while now() < cap, now() - max(answered, screen.updated) < Self.publishQuiet {
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return screen.frame
    }

    /// Units for a correction of `error` (screen fraction): at least one board count (4 units), so it always sends one.
    static func fineUnits(_ error: Double, perUnit: Double) -> Int {
        let units = Int((error / max(perUnit, 1e-6)).rounded())
        return abs(units) >= unitsPerCount ? units : (error < 0 ? -unitsPerCount : unitsPerCount)
    }

    /// Screen fraction per unit a short correction really moved, blended into the estimate (a move the board held
    /// back, one too small to measure, or one the wrong way teaches nothing).
    static func learned(_ estimate: Double, moved: Double, units: Int) -> Double {
        let measured = moved / Double(units)
        guard abs(moved) >= 0.002, measured > 0 else { return estimate }
        return min(max(0.5 * estimate + 0.5 * measured, estimate / 3), estimate * 3)
    }

    /// Screen fraction per unit of short corrections, learned from what the eye saw (nil: from the span).
    private(set) var fineX: Double?, fineY: Double?

    /// A tap within this of its target needs no correction (fraction of the screen; a WeChat list row is ~0.09 high).
    static let arrivalTolerance = 0.008
    /// Half the width and height (0-1) of what the next tap is for, when known: a first stop inside it is clicked as it is.
    var targetHalf: (x: Double, y: Double)?
    func aimLoosely(_ halfX: Double, _ halfY: Double) {
        guard UserDefaults.standard.object(forKey: "tapTargetToleranceV1") as? Bool ?? true else { return }
        targetHalf = (min(max(halfX, 0), 0.2), min(max(halfY, 0), 0.035))
    }
    static let maxCorrections = 3
    static let jumpLimit = 0.04       // a reading that moved more than this, and over 3 times the correction, is not the pointer
    static let leftMargin = 0.03      // a swipe from here presses no button (measured in Settings and on the Home Screen, 11-09)
    static let unitsPerCount = 4      // the board's BLE_MOVE_DIV: 4 app units make one HID count over Bluetooth
    static let publishQuiet = 0.35    // direct capture publishes at most every 0.25 s; one period and the encode

    /// Press and hold at a spot, then let go: the globe key shows its keyboard menu only on a long press (a click
    /// switches nothing visible, user 11-08). Like tap, the spot just clicked is held again without moving.
    func longPress(_ x: Double, _ y: Double, seconds: Double = 0.8) async throws { try await oneAtATime { try await longPressNow(x, y, seconds: seconds) } }
    /// D18: `whileHeld` runs 0.6 s after the press, before the release (Weather's day chart shows an hour's value under
    /// the finger only while it is down).
    func longPress(_ x: Double, _ y: Double, seconds: Double, whileHeld: @escaping @MainActor () async -> Void) async throws {
        try await oneAtATime { try await longPressNow(x, y, seconds: seconds, whileHeld: whileHeld) }
    }
    private func longPressNow(_ x: Double, _ y: Double, seconds: Double, whileHeld: (@MainActor () async -> Void)? = nil) async throws {
        drawChain = false
        if let last = lastClick, let p = pos, Self.clickAgain(last, x, y, units: p, link: device.links, at: Date().timeIntervalSince1970) {
            log(String(format: "long press (%.3f, %.3f): same spot as the last click; holding without moving", x, y))
        } else {
            // build105 live 11-08: the globe key was held 9 of 11 times without its menu coming up: a long press went
            // to the blind estimate (bottom row: 1-4 % off, the key 10 % x 5 %), then held the same spot again.
            let before = screen?.frame, began = now()
            lastClick = nil
            pos = nil
            try await point(x, y)
            // 126 over the cloud 11-12 (g6): Taobao's 购物车 at (0.300, 0.916) was seen at (0.472, 0.953), "too far to
            // trust", and clicked there six times: on 加入购物车, five more in the cart. Seen off target, the wiggle
            // search finds the pointer and corrects it before the click (2-4 s, only then).
            if try await arrive(x, y, before: before, began: began) == .offTarget { try await self.aim(x, y) }
        }
        try await device.send("press")
        do {
            if let whileHeld {
                let settle = min(0.6, seconds)
                try await Task.sleep(nanoseconds: UInt64(settle * 1e9))
                await whileHeld()
                if seconds > settle { try await Task.sleep(nanoseconds: UInt64((seconds - settle) * 1e9)) }
            } else {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
            }
        } catch {
            _ = try? await device.send("release")
            throw error
        }
        try await device.send("release")
        if let p = pos { lastClick = LastClick(x: x, y: y, ux: p.0, uy: p.1, link: device.links, time: Date().timeIntervalSince1970) }
        try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
    }

    static let nearbyHops = 6      // hops not seen on the target before one re-homes again

    /// D103, user 11-17: a message's banner slides in at the top while another app is used ("不在微信的时候如果微信突然
    /// 来了消息，这时候会有误触点进去的情况"), and a click meant for a search bar or a back arrow under it opens the
    /// message's app instead, often on another chat. A click near the top waits (up to 6 s; a banner goes up by itself in
    /// about 5) while one is over it, looked at in the frame just before the click. Text there that does not go in 6 s
    /// is the app's own, and is not waited for again.
    static let bannerBand = 0.16
    static let bannerWait = 6.0
    private var notBanners: Set<String> = []
    private var swipedBanners: Set<String> = []

    /// The banner over the top of these rows ("title|body"), unless it was found to be part of the screen.
    /// 142's z6: 4 waits of 6 s each, none a banner: Notes' search results and Taobao's and Pinduoduo's product titles
    /// over their subtitles look like one, and their text read a little differently each time. A real banner's title
    /// row has its time at the right ("现在", "2分钟前"): no time there, no banner.
    static func bannerKey(_ rows: [[CandidatePicker.Piece]], notBanners: Set<String>) -> String? {
        guard bannerTimeShown(rows), let banner = WatchReport.banner(rows: rows) else { return nil }
        let key = banner.title + "|" + banner.body
        return notBanners.contains(key) ? nil : key
    }

    /// A banner's time at the right of its title row: "现在", "刚刚", "2分钟前", "now", "2m ago".
    static func bannerTimeShown(_ rows: [[CandidatePicker.Piece]]) -> Bool { rows.joined().contains(where: isBannerTime) }
    static func isBannerTime(_ piece: CandidatePicker.Piece) -> Bool {
        piece.box.minX >= 0.72 && piece.box.midY <= bannerBand
            && piece.text.filter({ !$0.isWhitespace }).lowercased().range(
                of: #"^(现在|現在|刚刚|剛剛|now|\d{1,2}(分钟|分鐘|秒|小时|小時|m|min|s|h)(前|ago)?)$"#,
                options: .regularExpression) != nil
    }

    /// D116: where to press to swipe a banner up: on its body, just under the title row that holds its time.
    static func bannerSwipeStart(_ rows: [[CandidatePicker.Piece]]) -> Double? {
        rows.joined().first(where: isBannerTime).map { min(bannerBand - 0.01, Double($0.box.midY) + 0.035) }
    }

    /// D116, q143n on 143 (n12): a 10001 SMS banner ("1分鐘前") stayed over WeChat's title for minutes; after 6 s it was
    /// taken for the screen's own, and the taps meant for the back arrow under it went to the status bar. A real banner
    /// (its time shown) still there after the wait is swiped up once, before the pointer goes to the target: a swipe at
    /// click time would leave the pointer at the swipe's end.
    private func swipeAwayStuckBanner() async throws {
        guard let screen else { return }
        let started = now()
        var rows: [[CandidatePicker.Piece]] = [], seen: String?
        repeat {
            guard let frame = screen.frame else { return }
            rows = await CandidatePicker.rowsOffMain(in: frame, top: 0, bottom: Self.bannerBand)
            guard let key = Self.bannerKey(rows, notBanners: notBanners) else {
                if seen != nil { log(String(format: "tap: the banner went up after %.1f s", now() - started)) }
                return
            }
            if seen == nil { log("tap: a notification banner over the top (\(key.prefix(40))); waiting for it to go") }
            seen = key
            try await Task.sleep(nanoseconds: 500_000_000)
        } while now() - started < Self.bannerWait
        guard let key = seen, !swipedBanners.contains(key), let from = Self.bannerSwipeStart(rows) else { return }
        swipedBanners.insert(key)
        log("tap: the banner is still there after 6 s; swiping it up")
        try await dragNow([CGPoint(x: 0.5, y: from), CGPoint(x: 0.5, y: max(0.01, from - 0.1))], hold: false, quick: true)
        (lastClick, pos) = (nil, nil)  // the pointer is at the top now: the tap goes from the corner
        try await Task.sleep(nanoseconds: 800_000_000)
        guard let frame = screen.frame else { return }
        let after = await CandidatePicker.rowsOffMain(in: frame, top: 0, bottom: Self.bannerBand)
        if Self.bannerKey(after, notBanners: notBanners) != nil {
            notBanners.insert(key)
            log("tap: the banner did not go when swiped: the screen's own")
        } else {
            log("tap: the banner went up when swiped")
        }
    }

    private func clearOfBanners(_ y: Double) async throws {
        guard y < Self.bannerBand, let screen else { return }
        let started = now()
        var seen: String?
        while now() - started < Self.bannerWait {
            guard let frame = screen.frame else { return }
            let rows = await CandidatePicker.rowsOffMain(in: frame, top: 0, bottom: Self.bannerBand)
            guard let key = Self.bannerKey(rows, notBanners: notBanners) else {
                if seen != nil { log(String(format: "tap: the banner went up after %.1f s; clicking", now() - started)) }
                return
            }
            if seen == nil { log("tap: a notification banner over the top (\(key.prefix(40))); waiting for it to go before clicking") }
            seen = key
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        if let seen {
            notBanners.insert(seen)
            log("tap: what looked like a banner is still there after 6 s: the screen's own; clicking")
        }
    }

    /// D102: a hop into the top band clicks only where the pointer was seen on the target; otherwise the tap goes from
    /// the corner after all (not when the arrival check itself already started over from there).
    /// D151: a hop to a target the border path is for (the right side, the bottom rows) likewise.
    /// 174: never on an iPad (v36 boards' round reports): its hops landed within 0.3-1.3% and its homes 1.8-3.9% off (11-25).
    static func hopNeedsCorner(y: Double, border: Bool = false, arrival: Arrival, startedOver: Bool, pad: Bool = false) -> Bool {
        !pad && (y < topBand || border) && arrival != .onTarget && !startedOver
    }
    static let hopWindow = 120.0   // seconds; after longer, start from the corner

    /// The pointer still rests where the last click put it: nothing moved it since and the link is the same.
    static func canHop(_ last: LastClick, units: (Int, Int), link: Int, at now: Double) -> Bool {
        units == (last.ux, last.uy) && link == last.link && now - last.time >= 0 && now - last.time <= hopWindow
    }

    /// Mouse units from the last click's spot to (x, y): the measured probe maps' hop for that distance, or the
    /// calibrated span (linear) without them.
    func hopUnits(from last: LastClick, to x: Double, _ y: Double, units p: (Int, Int)) -> (Int, Int) {
        if let mx = maps?["x"], let my = maps?["y"] { return (mx.hop(x - last.x), my.hop(y - last.y)) }
        return (dx(x) - p.0, dy(y) - p.1)
    }

    struct LastClick: Equatable {
        var x: Double, y: Double, ux: Int, uy: Int, link: Int, time: Double
        var swiped = false  // D108: where a swipe ended, not a click: a tap there moves and looks, never clicks in place
    }
    static let sameSpot = 0.004       // screen fraction: model coordinates on a 0-1000 grid repeat exactly
    static let clickAgainWindow = 60.0  // seconds; after longer the user may have touched or moved things

    /// Click again in place only when nothing has moved the pointer since the last click (its tracked position is
    /// unchanged and the board link is the same) and the target is that same spot.
    static func clickAgain(_ last: LastClick, _ x: Double, _ y: Double, units: (Int, Int), link: Int, at now: Double) -> Bool {
        !last.swiped && abs(last.x - x) <= sameSpot && abs(last.y - y) <= sameSpot && units == (last.ux, last.uy)
            && link == last.link && now - last.time >= 0 && now - last.time <= clickAgainWindow
    }

    /// 174 (user 11-25: 苹果上长按删不了会话，要横滑出红色“删除”): bring out the buttons under a list row. WeChat's come
    /// with a drag left (press, one move, release, no pause between them); WeCom's are the system's swipe actions, which
    /// a pointer's drag only taps (it opened the chat twice, 11-25) and a sideways scroll over the row brings out.
    /// `room`: how far left the drag may go (screen fraction), so it stays inside its window.
    func revealRowActions(_ x: Double, _ y: Double, room: Double, scroll: Bool) async throws {
        try await oneAtATime {
            try await point(x, y, rehome: pos == nil)
            lastClick = nil
            if scroll {
                for _ in 0..<14 { try await device.send("scroll 0 -4") }
                return
            }
            guard let span else { throw DeviceError(message: "pointer not calibrated") }
            let units = max(1, Int((min(max(room, 0.02), 0.2) * Double(span.w)).rounded()))
            try await device.send("press")
            do { try await device.send("move -\(units) 0") } catch {
                _ = try? await device.send("release")
                throw error
            }
            try await device.send("release")
            if let p = pos { pos = (p.0 - units, p.1) }
        }
    }

    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool = true) async throws {
        try await drag([CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)], hold: hold)
    }

    /// D109, user 11-18 ("上滑抖音时就正常划一下就行，你这个滑动感觉是按着慢慢走的滑动"): a model's swipe is pressed and
    /// walked slowly, then held, so lists and pickers stop exactly there (134: one jump never moved Weather's hourly
    /// strip). A feed of one video a screen turns by a quick stroke: a few quick moves and up at once.
    func flick(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) async throws {
        try await oneAtATime { try await dragNow([CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)], hold: false, quick: true) }
    }

    static let flickSteps = 4

    /// D108: a swipe goes straight from where the pointer rests, and leaves it resting at its end, when both ends are
    /// well inside the screen (an edge's own gestures need the edge, reached from the corner as before).
    /// 143's single sentences: all 16 swipes still went to the corner, for a list is scrolled from the margin (AgentLoop's
    /// safeSwipe: x 40) and the margin counted as an edge. Up and down at a side margin is no edge gesture (the back
    /// gesture goes sideways): only sideways swipes keep away from the sides.
    static func swipeHops(from a: CGPoint, to b: CGPoint) -> Bool {
        let xs: ClosedRange<Double> = abs(Double(b.x - a.x)) < 0.1 ? 0.03...0.97 : 0.08...0.92
        return [a, b].allSatisfy { xs.contains(Double($0.x)) && (0.12...0.9).contains(Double($0.y)) }
    }

    /// Press at the first point, move through the rest, release: one continuous stroke. hold rests at the end
    /// first, so lists and pickers stop exactly there; system gestures (home, back) need the flick.
    func drag(_ points: [CGPoint], hold: Bool = true) async throws { try await oneAtATime { try await dragNow(points, hold: hold) } }
    private func dragNow(_ points: [CGPoint], hold: Bool, quick: Bool = false) async throws {
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw DeviceError(message: "drag needs at least two finite points")
        }
        guard calibrated else { throw DeviceError(message: "pointer not calibrated") }
        let drawing = points.count > 2
        // Re-home before a drawing stroke only when the run is starting (the first stroke after a tap or other
        // gesture) or when it has drifted past the budget; otherwise keep the tracked position and move straight to
        // the new start, so the pointer does not visit the corner between every stroke. A re-home at the run's start
        // still clears the error carried in from earlier taps that used to shift the circle ~75 units.
        let budget = span.map { 3 * max($0.w, $0.h) } ?? 800
        let startFromHome = !drawing || !drawChain || unitsSinceDrawHome > budget
        if drawing {
            if startFromHome { pos = nil; unitsSinceDrawHome = 0 }
            drawChain = true
        } else {
            drawChain = false
        }
        let previous = startFromHome ? (0, 0) : (pos ?? (0, 0))
        let travel = hypot(Double(dx(Double(points[0].x)) - previous.0), Double(dy(Double(points[0].y)) - previous.1))
        // D108, user 11-18 ("现在我看他还是从左上角出发啊"): on 142, every swipe went to the corner first, and the tap
        // after it too. A swipe inside the screen starts straight from where the pointer rests (its start needs no
        // aim: a list moves wherever it is pressed).
        let start = CGPoint(x: Double(points[0].x), y: Double(points[0].y))
        if !drawing, hold || quick, Self.swipeHops(from: start, to: points[points.count - 1]), !viaBorders(start.x, start.y),
           let last = lastClick, let p = pos, hops < Self.swipeHopLimit(startY: Double(start.y)),
           Self.canHop(last, units: p, link: device.links, at: Date().timeIntervalSince1970) {
            let (ux, uy) = hopUnits(from: last, to: start.x, start.y, units: p)
            lastClick = nil
            pos = nil
            if maps != nil { try await ProbeMotion.move(device, ux, uy) } else { try await device.send("move \(ux) \(uy)") }
            (pos, hops, moves) = ((p.0 + ux, p.1 + uy), hops + 1, moves + 1)
            log(String(format: "swipe from (%.3f, %.3f): straight from where the pointer rests", start.x, start.y))
        } else {
            try await point(start.x, start.y, rehome: startFromHome, edgeStart: !hold && !drawing && !quick)
        }
        var strokedLine = false  // D167: a 2-point line went in one stroke
        var thumbEnd: CGPoint?  // 174: where an iPad thumb swipe really ended (screen fractions)
        // With the position unknown the next move would go home first: never with the button down.
        if pos == nil { try await moveTo(dx(Double(points[0].x)), dy(Double(points[0].y)), rehome: true) }
        try await device.send("press")
        do {
            if points.count > 2, strokeCommand != false, let start = pos {
                var (x, y) = start
                // The whole stroke in one command: the board streams it at the calibration's pace. Segment by segment,
                // each short last report and round trip made iOS accelerate less and a circle came out ~10% small.
                var deltas: [String] = []
                for p in points.dropFirst() {
                    let (tx, ty) = (dx(Double(p.x)), dy(Double(p.y)))
                    deltas.append("\(tx - x) \(ty - y)")
                    (x, y) = (tx, ty)
                }
                do {
                    try await device.send("stroke " + deltas.joined(separator: " "))
                    (pos, strokeCommand) = ((x, y), true)
                } catch let e as DeviceError where e.message.contains("unknown command") {
                    strokeCommand = false  // older firmware: move point by point below
                }
            }
            // A list scrolls by the stroke only when it goes slowly. 134 over the cloud 11-15 (y2, y4): a sideways swipe
            // went as one jump (press, move -194, release) and Weather's hourly strip never moved, ten swipes in a row.
            // A swipe the model asks for (hold) goes slowly either way (a paging view still turns past half its width);
            // the quick flick is for the page turns the app makes itself (hold false: the Home Screen's pages).
            // D110, user 11-18 ("现在滑动设定也是不流畅"): a swipe went as ~20 "move 0 -19", each a 0.13-0.2 s round trip:
            // the pointer jerked along for ~3.5 s. The whole line goes in one stroke instead, streamed by the board at the
            // calibration's pace (as a drawing is); a swipe then rests before lifting as before, a flick lifts at once.
            // Firmware without stroke: the walk as before.
            var stroked = false
            // Up and down only: 134's sideways jump never moved Weather's hourly strip, so sideways keeps the walk.
            let upDown = abs(Double(points[1].y - points[0].y)) >= abs(Double(points[1].x - points[0].x))
            if points.count == 2, hold || quick, upDown || quick, strokeCommand != false, let from = pos {
                var to = (dx(Double(points[1].x)), dy(Double(points[1].y)))
                var deltas = Self.strokeDeltas(from: from, to: to, step: Self.swipeStrokeStep)
                // 174: on an iPad a swipe goes as a thumb's, bending toward its own side (PadCurve.thumbEnd).
                if CommandChannel.onPad(), let s = span,
                   let e = PadCurve.thumbEnd(from: (Double(points[0].x), Double(points[0].y)),
                                             to: (Double(points[1].x), Double(points[1].y)), span: (s.w, s.h)) {
                    let bent = (dx(e.x), dy(e.y))
                    deltas = PadCurve.thumbPieces(from: from, toward: to, end: bent, step: Self.swipeStrokeStep / 2)
                    log(String(format: "swipe (%.3f, %.3f) → (%.3f, %.3f): a thumb's, ending at (%.3f, %.3f)",
                               Double(points[0].x), Double(points[0].y), Double(points[1].x), Double(points[1].y), e.x, e.y))
                    (to, thumbEnd) = (bent, CGPoint(x: e.x, y: e.y))
                }
                do {
                    try await device.send("stroke " + deltas.map { "\($0.0) \($0.1)" }.joined(separator: " "))
                    (pos, strokeCommand, stroked) = (to, true, true)
                    strokedLine = true
                    moves += 1
                } catch let e as DeviceError where e.message.contains("unknown command") {
                    strokeCommand = false
                }
            }
            if stroked {
                // the line went in one stroke
            } else if points.count == 2 && quick {
                try await quickMove(to: dx(Double(points[1].x)), dy(Double(points[1].y)))
            } else if points.count == 2 && hold {
                try await pacedMove(to: dx(Double(points[1].x)), dy(Double(points[1].y)))
            } else if strokeCommand != true || points.count <= 2 {
                for p in points.dropFirst() {
                    try await moveTo(dx(Double(p.x)), dy(Double(p.y)), rehome: false, positioning: false)  // preserve the drag trajectory
                }
            }
            if hold { try await Task.sleep(nanoseconds: UInt64(Self.hold * 1e9)) }
        } catch {
            pos = nil; drawChain = false
            _ = try? await device.send("release")
            throw error
        }
        try await device.send("release")
        // A 2-point swipe is not part of a drawing run: re-home before whatever comes next, as before. A drawing
        // stroke keeps its tracked end position so the next stroke continues from it; the path length moved is
        // added to the drift budget, so a long run still re-homes once it has gone far enough.
        if drawing {
            var len = 0.0
            var prev = CGPoint(x: dx(Double(points[0].x)), y: dy(Double(points[0].y)))
            for p in points.dropFirst() {
                let q = CGPoint(x: dx(Double(p.x)), y: dy(Double(p.y)))
                len += hypot(q.x - prev.x, q.y - prev.y)
                prev = q
            }
            unitsSinceDrawHome += Int(len + travel)
        } else if hold || quick, let p = pos, Self.swipeHops(from: start, to: points[points.count - 1]) {
            // D108: the pointer rests where the swipe ended: the next tap or swipe may go straight from there.
            // D167: a held stroke rests short of its end (restsAt): the next hop goes from there.
            let asked = thumbEnd ?? points[points.count - 1]
            let end = strokedLine && hold ? Self.restsAt(from: start, to: asked) : asked
            let q = strokedLine && hold ? (dx(Double(end.x)), dy(Double(end.y))) : p
            pos = q
            lastClick = LastClick(x: Double(end.x), y: Double(end.y), ux: q.0, uy: q.1, link: device.links,
                                  time: Date().timeIntervalSince1970, swiped: true)
        } else {
            pos = nil
        }
    }

    /// A list moves about as far as the finger only when the finger moves slowly. Over USB 11-10 in Weather a 335-unit
    /// stroke in one command (about 0.27 s) threw the page two to three screens on, past the 10-day forecast to the bottom,
    /// where the next swipes changed nothing (25 of 29 in one run); a rest at the end did not stop it. 20 units a command
    /// (the round trip spaces them about 0.12 s) moved it about as far as the stroke, 40 twice as far, 10 the same.
    static let swipeStep = 20

    private func pacedMove(to tx: Int, _ ty: Int) async throws {
        guard let (x, y) = pos else { throw DeviceError(message: "pointer position lost; no move was sent") }
        let (ux, uy) = (tx - x, ty - y)
        let n = max(1, Int((Double(max(abs(ux), abs(uy))) / Double(Self.swipeStep)).rounded(.up)))
        var (sx, sy) = (0, 0)
        for i in 1...n {
            let (nx, ny) = (ux * i / n, uy * i / n)
            try await device.send("move \(nx - sx) \(ny - sy)")
            (sx, sy) = (nx, ny)
            pos = (x + sx, y + sy)
        }
        moves += 1
    }

    static let swipeStrokeStep = 200  // the board paces each segment itself; a stroke takes at most 40

    /// D167, x4 over the cloud 11-19 (148): four swipes up Taobao's results from (0.04, 0.80), each hopping straight
    /// from the last one's end (D108), and the fourth opened the app switcher: the pointer had sunk to the home bar.
    /// 147's x4 (小红书), 148's h2 (Weather) and s sets did the same. Measured over 145-148's logs (328 swipes, then the
    /// next tap's hop and where the pointer was seen): a held stroke moves the pointer about 10 % short of its length
    /// (a hop about 4 %), so each swipe up and hop back down left it ~6 % of the swipe lower. A held stroke now rests
    /// where it really ends, and a swipe low on the screen, where a small miss is the home bar, hops at most twice
    /// before it starts from the corner again.
    static let strokeShortfall = 0.1
    static func restsAt(from a: CGPoint, to b: CGPoint) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * (1 - strokeShortfall), y: a.y + (b.y - a.y) * (1 - strokeShortfall))
    }
    static func swipeHopLimit(startY: Double) -> Int { startY > 0.78 ? 2 : nearbyHops }

    /// D110: a straight line from one point to another as a stroke's moves, each at most `step` units on either axis.
    static func strokeDeltas(from a: (Int, Int), to b: (Int, Int), step: Int) -> [(Int, Int)] {
        let (ux, uy) = (b.0 - a.0, b.1 - a.1)
        let n = max(1, Int((Double(max(abs(ux), abs(uy))) / Double(max(1, step))).rounded(.up)))
        var out: [(Int, Int)] = []
        var (sx, sy) = (0, 0)
        for i in 1...n {
            let (nx, ny) = (ux * i / n, uy * i / n)
            out.append((nx - sx, ny - sy))
            (sx, sy) = (nx, ny)
        }
        return out
    }

    /// D109: a flick's stroke: a few quick moves with no pause between them, so iOS sees a fast finger.
    private func quickMove(to tx: Int, _ ty: Int) async throws {
        guard let (x, y) = pos else { throw DeviceError(message: "pointer position lost; no move was sent") }
        let (ux, uy) = (tx - x, ty - y)
        var (sx, sy) = (0, 0)
        for i in 1...Self.flickSteps {
            let (nx, ny) = (ux * i / Self.flickSteps, uy * i / Self.flickSteps)
            try await device.send("move \(nx - sx) \(ny - sy)")
            (sx, sy) = (nx, ny)
            pos = (x + sx, y + sy)
        }
        moves += 1
    }

    func scroll(_ x: Double, _ y: Double, lines: Int) async throws { try await oneAtATime { try await scrollNow(x, y, lines: lines) } }
    private func scrollNow(_ x: Double, _ y: Double, lines: Int) async throws {
        drawChain = false
        try await point(x, y)
        try await device.send("scroll \(lines) 0")
    }

    /// The board only has US keys. Chinese (simplified or traditional: whichever pinyin keyboard the phone has on)
    /// goes in as toneless pinyin left open for the actor to inspect and select the exact candidate. A run with
    /// Latin letters goes in between two Caps Lock presses, which switch the pinyin keyboard to English and back.
    /// Assumes the phone's keyboard is a pinyin keyboard in Chinese mode, and leaves it that way.
    func type(_ text: String) async throws { try await oneAtATime { try await typeNow(text) } }
    private func typeNow(_ text: String) async throws {
        drawChain = false
        let runs = Self.typingRuns(text)
        // Validate every run before the first side effect; never silently skip an emoji or unsupported script.
        for run in runs {
            if run.kind == .chinese {
                guard !Self.pinyin(run.text).isEmpty else { throw DeviceError(message: "cannot transliterate this Han text") }
            } else { _ = try Self.keyboardChunks(run.text) }
        }
        for (index, run) in runs.enumerated() {
            try Task.checkCancellation()
            switch run.kind {
            case .chinese:
                let phrase = String(run.text.prefix(6))  // picked a candidate at a time (AgentLoop.typeFast)
                try await sendKeyboard(Self.pinyin(phrase))
                try await Task.sleep(nanoseconds: 400_000_000)  // let the candidates come up
                let remaining = String(run.text.dropFirst(phrase.count)) + runs.dropFirst(index + 1).map { $0.text }.joined()
                // Keep the composition open. The model must inspect candidates before choosing/committing.
                throw InputNeedsVerification(expected: phrase, remaining: remaining)
            case .latin:
                try await device.send("key capslock")
                try await Task.sleep(nanoseconds: 300_000_000)
                try await sendKeyboard(run.text)
                try await device.send("key capslock")
                try await Task.sleep(nanoseconds: 300_000_000)
            case .other:
                try await sendKeyboard(run.text)
            }
        }
    }

    /// WeChat watch: each Chinese chunk as pinyin, committed with space (the first candidate), with no look per
    /// chunk; the caller checks the field once. On the full pinyin keyboard this typed a 20-character sentence right
    /// in 3 s, against 15.7 s looking at the candidates (PC harness, 2026-10-25).
    func typeQuick(_ text: String) async throws { try await oneAtATime { try await typeQuickNow(text) } }
    private func typeQuickNow(_ text: String) async throws {
        drawChain = false
        let runs = Self.typingRuns(text)
        for run in runs {
            if run.kind == .chinese {
                guard !Self.pinyin(run.text).isEmpty else { throw DeviceError(message: "cannot transliterate this Han text") }
            } else { _ = try Self.keyboardChunks(run.text) }
        }
        for run in runs {
            try Task.checkCancellation()
            switch run.kind {
            case .chinese:
                for chunk in Self.quickChunks(run.text) {
                    try await sendKeyboard(Self.pinyin(chunk))
                    try await device.send("key space")
                }
            case .latin:
                try await device.send("key capslock")
                try await Task.sleep(nanoseconds: 300_000_000)
                try await sendKeyboard(run.text)
                try await device.send("key capslock")
                try await Task.sleep(nanoseconds: 300_000_000)
            case .other:
                try await sendKeyboard(run.text)
            }
        }
    }

    /// Chinese in chunks of whole words of up to 6 characters (a longer word stays whole), the size the pinyin
    /// keyboard offers as one first candidate.
    static func quickChunks(_ han: String) -> [String] {
        let text = han as NSString, cf = han as CFString
        let tokenizer = CFStringTokenizerCreate(nil, cf, CFRangeMake(0, text.length), kCFStringTokenizerUnitWordBoundary,
                                                Locale(identifier: "zh_CN") as CFLocale)
        var words: [String] = []
        while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
            let r = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            words.append(text.substring(with: NSRange(location: r.location, length: r.length)))
        }
        if words.joined() != han { words = han.map(String.init) }  // the tokenizer skipped something: by character
        var chunks: [String] = [], current = ""
        for word in words {
            if !current.isEmpty && current.count + word.count > 6 { chunks.append(current); current = "" }
            current += word
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    static func keyboardChunks(_ text: String) throws -> [String] {
        guard text.unicodeScalars.allSatisfy({ (32...126).contains($0.value) || $0 == "\n" || $0 == "\t" }) else {
            throw DeviceError(message: "unsupported keyboard text; use the on-screen keyboard for this character")
        }
        var chunks: [String] = [], chunk = ""
        for ch in text {
            if chunk.utf8.count + ch.utf8.count > 400 { chunks.append(chunk); chunk = "" }
            chunk.append(ch)
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        return chunks
    }

    private func sendKeyboard(_ text: String) async throws {
        for chunk in try Self.keyboardChunks(text) {
            var printable = ""
            for ch in chunk {
                if ch == "\n" || ch == "\t" {
                    if !printable.isEmpty { try await device.send("type \(printable)"); printable = "" }
                    try await device.send(ch == "\n" ? "key enter" : "key tab")
                } else { printable.append(ch) }
            }
            if !printable.isEmpty { try await device.send("type \(printable)") }
        }
    }

    enum TypingRunKind: Equatable { case chinese, latin, other }

    /// Splits text into runs of Chinese characters and of everything else; a non-Chinese run with a Latin letter is
    /// .latin (typed in English mode, so its punctuation stays ASCII), otherwise .other (digits, spaces and
    /// punctuation, which the pinyin keyboard turns into full width). Full-width punctuation is typed as its ASCII key.
    static func typingRuns(_ text: String) -> [(kind: TypingRunKind, text: String)] {
        let keys: [Character: Character] = ["，": ",", "。": ".", "！": "!", "？": "?", "：": ":", "；": ";",
                                            "（": "(", "）": ")", "、": "\\", "“": "\"", "”": "\"", "‘": "'", "’": "'"]
        var runs: [(chinese: Bool, text: String)] = []
        for raw in text {
            let ch = keys[raw] ?? raw
            let chinese = ch.unicodeScalars.contains { Self.isHan($0) }
            if let last = runs.last, last.chinese == chinese { runs[runs.count - 1].text.append(ch) }
            else { runs.append((chinese, String(ch))) }
        }
        return runs.map { run -> (kind: TypingRunKind, text: String) in
            if run.chinese { return (.chinese, run.text) }
            return (run.text.contains { $0.isASCII && $0.isLetter } ? .latin : .other, run.text)
        }
    }

    static func isHan(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2FA1F: return true
        default: return false
        }
    }

    /// "无边记" -> "wubianji", "绿"/"綠" -> "lv" (the pinyin keyboard's v for ü); traditional characters work too.
    static func pinyin(_ han: String) -> String {
        let latin = han.applyingTransform(.mandarinToLatin, reverse: false) ?? han
        let v = latin.replacingOccurrences(of: "[ǖǘǚǜü]", with: "v", options: .regularExpression)
        let plain = v.applyingTransform(.stripDiacritics, reverse: false) ?? v
        return plain.lowercased().filter { $0.isASCII && $0.isLetter }
    }
    func key(_ combo: String) async throws { try await oneAtATime { drawChain = false; try await device.send("key \(combo)") } }
    /// Measured on the phone over USB (11-09). A flick up from an app: the Home Screen. A flick up from the Home Screen or
    /// from Search: the app switcher, and the next flick goes back to where it was (the same page, or Search): it never
    /// goes to the first page. "Home twice" therefore always ended in the app switcher, and whatever came next landed on
    /// a card: opening 备忘录, 美团, even 微信 failed. So the screen decides: on a Home Screen nothing is done, Search is
    /// emptied and tapped away, anything else gets the flick, and the result is looked at.
    func goHome() async throws { _ = try await goHomeRows() }
    /// Home, and the Home Screen's text as read to know it is there (nil when it was not read): opening an app reads
    /// the same page next, 0.6–0.8 s more (build 116).
    @discardableResult func goHomeRows() async throws -> [[CandidatePicker.Piece]]? { try await oneAtATime { try await goHomeNow() } }
    private func goHomeNow() async throws -> [[CandidatePicker.Piece]]? {
        drawChain = false
        guard let screen else { try await flickHome(); return nil }
        for attempt in 0..<6 {  // D21: two flicks, then a page swipe and a flick in turn
            if attempt == 5 {  // the last swipe's result is looked at, not followed by one more flick
                if let shown = screen.frame {
                    let rows = await CandidatePicker.rowsOffMain(in: shown, top: 0.02, bottom: 1)
                    if AppPlaces.looksLikeHome(rows) { return rows }
                }
                break
            }
            let shown = screen.frame
            var rows: [[CandidatePicker.Piece]] = []
            if let shown { rows = await CandidatePicker.rowsOffMain(in: shown, top: 0.02, bottom: 1) }
            if rows.isEmpty {  // nothing to read: the flick, as without eyes
                if attempt == 0 { try await flickHome() }
                return nil
            }
            if AppPlaces.inLibrary(rows) {  // past the last page: a flick here only opens the app switcher
                log("home: on the App Library; back to the pages")
                try await swipe(Self.leftMargin, 0.5, 0.85, 0.5, hold: false)
                try await Task.sleep(nanoseconds: 900_000_000)
                continue
            }
            if AppPlaces.looksLikeOpenFolder(rows) {  // user 11-09: an open folder closes with a tap outside it
                log("home: a folder is open; tapping outside it")
                try await tap(0.5, 0.1)
                try await Task.sleep(nanoseconds: 700_000_000)
                continue
            }
            if AppPlaces.looksLikeHome(rows) { return rows }
            if AppPlaces.inSearch(rows) {
                // 124 over the cloud 11-12 (e02): 備忘錄's own search results ("最佳搜尋結果") read as Search. Emptying and
                // tapping away did nothing, five times, twice, with no flick home; the run then said 行事曆 was not on the
                // phone. And with no keyboard up, Cmd+A and Delete could reach a note. Search with its keyboard is emptied
                // once; anything else that reads as Search, or the same again, is left by the flick home.
                if attempt == 0, await keyboardIsUp(rows, shown) {
                    log("home: Search is open; emptying it and tapping away")
                    try await key("cmd+a")
                    try await key("backspace")
                    try await Task.sleep(nanoseconds: 400_000_000)
                    try await tap(Self.searchBlank.x, Self.searchBlank.y)
                } else {
                    // D219, 157 over USB (11-22): six flicks never left Spotlight (its keyboard up), and the run gave up
                    // on 微信 after 31 s; Esc on the board's keyboard left it at once. Esc first, then the flick.
                    log("home: a search screen (Search or an app's own); Esc, then flicking home")
                    try await key("esc")
                    try await Task.sleep(nanoseconds: 300_000_000)
                    try await flickHome()
                }
            } else if await keyboardIsUp(rows, shown) {
                // With a keyboard up the flick opens the app switcher, and the next flick goes back to the app: four
                // flicks ended a WeChat task nowhere. Measured over USB: a tap in the left margin closes it and touches
                // nothing there (a drag only scrolled the chat); where that does not close it, a drag over the content.
                log("home: a keyboard is up; closing it first")
                try await tap(0.02, 0.3)
                try await Task.sleep(nanoseconds: 500_000_000)
                var stillUp = false
                if let after = screen.frame { stillUp = await keyboardIsUp(await CandidatePicker.rowsOffMain(in: after, top: 0.02, bottom: 1), after) }
                if stillUp {
                    try await swipe(0.5, 0.2, 0.5, 0.38, hold: false)
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
                try await flickHome()
            } else if attempt >= 2, attempt % 2 == 0 {
                // D21, 134 over the cloud 11-15 (21:46 on, z4–z6 and the next run): a page swipe went past the first page
                // into the Today View (widgets, no dock, no Search pill). The Home Screen comes back to where it was left,
                // and a flick there never reaches the pages: "no Home Screen seen" 200 times in two hours. Two flicks and
                // still not home: the pages are swiped back toward the first (from the Today View that is page 1; in the
                // app switcher it only moves the cards, and the next flick goes back).
                log("home: two flicks and still no Home Screen (the Today View?); swiping toward the first page")
                try await swipe(0.85, 0.5, 0.15, 0.5, hold: false)
            } else {
                try await flickHome()
            }
            try await Task.sleep(nanoseconds: 800_000_000)
        }
        log("home: no Home Screen seen after six tries")
        return nil
    }

    private func keyboardIsUp(_ rows: [[CandidatePicker.Piece]], _ frame: Data?) async -> Bool {
        if AppPlaces.keyboardShown(rows) { return true }
        guard let frame else { return false }
        return await CandidatePicker.keyboardUpOffMain(in: frame)
    }

    /// Between Search's suggestions and its field, above the keyboard.
    static let searchBlank = CGPoint(x: 0.5, y: 0.42)

    /// The board's consumer-control Home key ("AC Home"), which iOS treats like a keyboard's home key. Boards
    /// without it (older firmware) answer an error: then Cmd+H and the flick up from the home bar (a flick, not
    /// a rest: resting opens the app switcher).
    private func flickHome() async throws {
        // Firmware v14+: the board flicks up from the home bar by itself, press to release with no pause (sent as
        // separate commands, the ~130 ms before `release` read as a rest and opened the app switcher). It moves
        // the pointer, so re-home before the next gesture. Older boards answer an error: fall through.
        if (try? await device.send("flickhome")) != nil { pos = nil; return }
        if (try? await device.send("homescreen")) != nil { return }
        try await key("cmd+h")
        try await Task.sleep(nanoseconds: 350_000_000)
        try await swipe(0.5, 0.995, 0.5, 0.45, hold: false)
    }
    func goBack() async throws { try await oneAtATime { try await goBackNow() } }
    private func goBackNow() async throws {
        try await swipe(0.005, 0.45, 0.6, 0.45, hold: false)
        pos = nil
    }
    /// The swipe right along the home bar: back to the app used before this one (iOS app switching).
    func previousApp() async throws { try await oneAtATime { try await previousAppNow() } }
    private func previousAppNow() async throws {
        // From the very bottom edge: coming down from the top after a re-home, the pointer stopped a little above the
        // home bar and the swipe only slid inside WeChat (logs(15)). An extra move down pins it against the edge.
        drawChain = false
        try await point(0.2, 1)  // looked for once, below, after the move that pins it to the edge
        try await device.send("move 0 80")
        if requiresFeedback { try await aim(0.2, 1, edgeStart: true) }
        try await device.send("press")
        try await device.send("move \(Int(0.65 * Double(span?.w ?? 400))) 0")
        try await device.send("release")
        pos = nil  // the edge clamped the pointer: re-home before the next move
    }

    /// Reverse a previousApp switch along the home bar, returning toward the original target app.
    func nextApp() async throws { try await oneAtATime { try await nextAppNow() } }
    private func nextAppNow() async throws {
        drawChain = false
        defer { pos = nil }
        try await point(0.85, 1)
        try await device.send("move 0 80")
        if requiresFeedback { try await aim(0.85, 1, edgeStart: true) }
        try await device.send("press")
        try await device.send("move \(-Int(0.65 * Double(span?.w ?? 400))) 0")
        try await device.send("release")
    }

    func probeUnits(_ x: Double, _ y: Double) -> (Int, Int) { (dx(x), dy(y)) }
    private func dx(_ x: Double) -> Int {
        maps?["x"]?.units(for: x) ?? Int((min(max(fix(x, "x"), 0), 1) * Double(span?.w ?? 400)).rounded(.toNearestOrEven))
    }
    private func dy(_ y: Double) -> Int {
        maps?["y"]?.units(for: y) ?? Int((min(max(fix(y, "y"), 0), 1) * Double(span?.h ?? 800)).rounded(.toNearestOrEven))
    }
}
