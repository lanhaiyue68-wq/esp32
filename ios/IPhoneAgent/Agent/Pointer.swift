import Foundation

/// Touch-like gestures on the phone, built from relative mouse moves. Port of phone.py.
///
/// The pointer is relative, so the app tracks where it is (in mouse units) and moves from there; every few
/// gestures it slams it into the top-left corner (`home`) again to cancel drift. Coordinates are fractions of
/// the screen (0..1, origin top-left), so they work for any frame size.
@MainActor final class Pointer: ObservableObject {
    static let calibrationMove = 200        // mouse units moved diagonally for a manual (one point) calibration
    static let calibrationStops = [150, 350]  // automatic calibration finds the pointer at these distances
    static let rehomeEvery = 10             // gestures between re-homing
    static let hold = 0.25                  // s to rest before lifting, so iOS adds no momentum
    static let tapGap = 0.15                // s to stay still after a click, so iOS sees a finished tap
    static let nudge = 12                   // mouse units the pointer is wiggled by to find it on screen
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
    }
    static let calibrationTolerance = 0.015
    private var maps: [String: ProbeMap]?
    private var provisional = false
    private var backup: Saved?
    private var requiresFeedback = false

    let device: HIDDevice
    weak var screen: ScreenSource?
    private let file: URL
    @Published private(set) var span: Span?  // mouse units needed to cross the full screen width / height
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
            (quality, aspect, stale) = (saved.quality, saved.aspect, saved.stale ?? false)
            maps = saved.maps
            requiresFeedback = saved.requiresFeedback ?? false
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
        let pixel = Vision.pointer(before, after, near: CGPoint(x: 0.5, y: 0.5), shift: 0.025, reach: CGPoint(x: 0.5, y: 0.5))
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
                     requiresFeedback: requiresFeedback ? true : nil)
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
    }

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
        if let p = Vision.pointer(restored, after, near: CGPoint(x: x, y: y), shift: shift)
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
        if pos == nil || (rehome && (maps != nil || moves >= Self.rehomeEvery)) {
            let homing = now()
            if maps != nil { try await ProbeMotion.home(device) } else { try await device.send("home") }
            (pos, moves, hops) = ((0, 0), 0, 0)
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
    func viaBorders(_ x: Double, _ y: Double) -> Bool { beyondReach(x) || belowReach(y) }

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
        if right {
            // y last: after the 400+ unit push it landed 0.027 low (live test 11-08, the alarm's ✓), against 0.012 after an
            // ordinary move; after the short way back it follows a move like the calibrated ones.
            try await ProbeMotion.move(device, max(mx.units(for: 1) * 3 / 2, 400), 0)
            try await Task.sleep(nanoseconds: 150_000_000)
            try await ProbeMotion.move(device, -back, 0)
            try await Task.sleep(nanoseconds: 150_000_000)
        } else {
            try await ProbeMotion.move(device, dx(x), 0)
        }
        if bottom {
            let up = my.units(for: 1 - y)
            try await ProbeMotion.move(device, 0, max(my.units(for: 1) * 3 / 2, 600))
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
        (pos, moves) = ((0, 0), 0)
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
        var before = screen?.frame, began = now()  // the screen before the move: where the pointer arrives is what changes
        defer { lastSpot = CGPoint(x: x, y: y) }
        if !aim, let last = lastClick, let p = pos, Self.clickAgain(last, x, y, units: p, link: device.links, at: Date().timeIntervalSince1970) {
            if clicksInPlace < Self.clicksInPlaceLimit {
                clicksInPlace += 1
                log(String(format: "tap (%.3f, %.3f): same spot as the last click; clicking again without moving", x, y))
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
        if !aim, !stale, !viaBorders(x, y), y >= Self.topBand, let last = lastClick, let p = pos, hops < Self.nearbyHops,
           Self.canHop(last, units: p, link: device.links, at: Date().timeIntervalSince1970) {
            // User 11-08: go straight to the next spot from where the pointer rests (the board still curves the
            // move), not back to the top-left corner first. A re-home every few hops keeps the error from adding up;
            // an aimed tap (after one that changed nothing) always starts from the corner.
            let (ux, uy) = hopUnits(from: last, to: x, y, units: p)
            lastClick = nil
            pos = nil
            if maps != nil { try await ProbeMotion.move(device, ux, uy) } else { try await device.send("move \(ux) \(uy)") }
            (pos, hops, moves) = ((p.0 + ux, p.1 + uy), hops + 1, moves + 1)
            log(String(format: "tap (%.3f, %.3f): hop %ld from (%.3f, %.3f)", x, y, hops, last.x, last.y))
            try await arrive(x, y, before: before, began: began)
            let clickedAt = now()
            try await device.send("click")
            if let q = pos { lastClick = LastClick(x: x, y: y, ux: q.0, uy: q.1, link: device.links, time: Date().timeIntervalSince1970) }
            try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
            try await answerIfAsked(x, y, clickedAt: clickedAt, before: before)
            return
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
            try await arrive(x, y, before: before, began: began)
        }
        if viaBorder, let first = firstSeen { learnBorderLift(missedBy: Double(first.y) - y) }
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
    private(set) var borderLiftY = 0.0

    func learnBorderLift(missedBy error: Double) {
        guard abs(error) < Self.borderMisreading else { return }  // too far to be the same pointer
        borderLiftY = min(max(borderLiftY + error / 2, -Self.borderLiftLimit), Self.borderLiftLimit)
        log(String(format: "border landing %.3f off in y; lift now %.3f", error, borderLiftY))
    }

    static let borderMisreading = 0.08
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
        guard var seen = Vision.arrival(before, first, near: target) else {
            log(String(format: "arrive (%.3f, %.3f): pointer not seen; clicking at the estimate", x, y))
            return .unseen
        }
        firstSeen = seen
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
            guard max(abs(ex), abs(ey)) <= 0.15 else {
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
            guard let next = Vision.arrival(before, after, near: target) else {
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
    private func longPressNow(_ x: Double, _ y: Double, seconds: Double) async throws {
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
            try await arrive(x, y, before: before, began: began)
        }
        try await device.send("press")
        do { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) } catch {
            _ = try? await device.send("release")
            throw error
        }
        try await device.send("release")
        if let p = pos { lastClick = LastClick(x: x, y: y, ux: p.0, uy: p.1, link: device.links, time: Date().timeIntervalSince1970) }
        try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
    }

    static let nearbyHops = 6      // taps from where the pointer rests before one re-homes again
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

    struct LastClick: Equatable { var x: Double, y: Double, ux: Int, uy: Int, link: Int, time: Double }
    static let sameSpot = 0.004       // screen fraction: model coordinates on a 0-1000 grid repeat exactly
    static let clickAgainWindow = 60.0  // seconds; after longer the user may have touched or moved things

    /// Click again in place only when nothing has moved the pointer since the last click (its tracked position is
    /// unchanged and the board link is the same) and the target is that same spot.
    static func clickAgain(_ last: LastClick, _ x: Double, _ y: Double, units: (Int, Int), link: Int, at now: Double) -> Bool {
        abs(last.x - x) <= sameSpot && abs(last.y - y) <= sameSpot && units == (last.ux, last.uy)
            && link == last.link && now - last.time >= 0 && now - last.time <= clickAgainWindow
    }

    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool = true) async throws {
        try await drag([CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)], hold: hold)
    }

    /// Press at the first point, move through the rest, release: one continuous stroke. hold rests at the end
    /// first, so lists and pickers stop exactly there; system gestures (home, back) need the flick.
    func drag(_ points: [CGPoint], hold: Bool = true) async throws { try await oneAtATime { try await dragNow(points, hold: hold) } }
    private func dragNow(_ points: [CGPoint], hold: Bool) async throws {
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
        try await point(Double(points[0].x), Double(points[0].y), rehome: startFromHome, edgeStart: !hold && !drawing)
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
            // A list scrolls by the stroke only when it goes slowly; a sideways page turn still needs the quick flick.
            if points.count == 2 && hold && abs(points[1].y - points[0].y) > abs(points[1].x - points[0].x) {
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
        for attempt in 0..<5 {
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
                    log("home: a search screen (Search or an app's own); flicking home")
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
            } else {
                try await flickHome()
            }
            try await Task.sleep(nanoseconds: 800_000_000)
        }
        log("home: no Home Screen seen after five tries")
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
