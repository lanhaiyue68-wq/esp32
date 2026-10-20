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
    static let maxMiss = 0.06               // bigger misses are still corrected, but not learned from

    struct Span: Codable, Equatable { var w: Int, h: Int }
    private struct Saved: Codable { var w: Int, h: Int, seen: [String: [[Double]]]?, quality: Double?, aspect: Double? }

    let device: HIDDevice
    weak var screen: ScreenSource?
    private let file: URL
    @Published private(set) var span: Span?  // mouse units needed to cross the full screen width / height
    private var pos: (Int, Int)?  // pointer position in mouse units; nil = unknown
    private var moves = 0
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
    var log: (String) -> Void = { print($0) }
    /// The device screen's width / height (iPhone or iPad), stored with a calibration.
    var screenAspect: () -> Double = { 9 / 19.5 }
    /// Last-resort pointer finder on a frame (the vision model), when the pixel diff finds nothing.
    var locate: ((Data) async -> CGPoint?)?

    init(device: HIDDevice, calibrationFile: URL, screen: ScreenSource? = nil) {
        self.device = device
        self.file = calibrationFile
        self.screen = screen
        if let data = try? Data(contentsOf: calibrationFile), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            span = Span(w: saved.w, h: saved.h)
            (quality, aspect) = (saved.quality, saved.aspect)
            for axis in ["x", "y"] {
                seen[axis] = (saved.seen?[axis] ?? []).filter { $0.count == 2 }.map { ($0[0], $0[1]) }.suffix(12)
            }
        }
    }

    var calibrated: Bool { span != nil }

    private func remember(_ axis: String, _ sample: (Double, Double)) {
        seen[axis] = Array((seen[axis, default: []] + [sample]).suffix(12))  // deque(maxlen=12)
    }

    /// Find the pointer on screen at two known distances from the corner and fit the mapping from both.
    /// Returns true when it calibrated itself; otherwise the user taps the pointer (finishCalibration).
    /// `progress` gets 0 (homing), then 1, 2 (each probe).
    func startCalibration(progress: ((Int) -> Void)? = nil) async throws -> Bool {
        pos = nil
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
        (quality, aspect) = (nil, screenAspect())
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
        (quality, aspect) = (nil, screenAspect())
        span = Span(w: Int((Double(Self.calibrationMove) / x).rounded(.toNearestOrEven)), h: Int((Double(Self.calibrationMove) / y).rounded(.toNearestOrEven)))
        seen = ["x": [], "y": []]
        save()
    }

    /// Touch-probe result: per-axis lines landed = a * units + b fitted from taps the app caught itself.
    /// The span is 1/a; every probe becomes a landing sample, so `fix` also corrects the offset b.
    func applyProbe(x: ProbeFit.Line, y: ProbeFit.Line, samples: [(ux: Double, uy: Double, fx: Double, fy: Double)]) {
        let s = Span(w: Int((1 / x.a).rounded()), h: Int((1 / y.a).rounded()))
        span = s
        (quality, aspect) = (max(x.rms, y.rms), screenAspect())
        seen = ["x": [], "y": []]
        for p in samples {
            remember("x", (p.ux / Double(s.w), p.fx))
            remember("y", (p.uy / Double(s.h), p.fy))
        }
        pos = nil
        save()
        log(String(format: "calibration: touch probe span %d x %d, offset %.3f / %.3f, residual %.2f%%",
                   s.w, s.h, x.b, y.b, max(x.rms, y.rms) * 100))
    }

    /// A measured check (e.g. a probe tap) as the current accuracy.
    func setQuality(_ q: Double) {
        quality = q
        save()
    }

    /// Calibration plus the observed landings, so the correction survives a restart.
    private func save() {
        guard let span else { return }
        let saved = Saved(w: span.w, h: span.h, seen: seen.mapValues { $0.map { [$0.0, $0.1] } }, quality: quality,
                          aspect: aspect)
        try? JSONEncoder().encode(saved).write(to: file)
    }

    func point(_ x: Double, _ y: Double, aim: Bool = false, rehome: Bool = true) async throws {
        guard calibrated else { throw DeviceError(message: "pointer not calibrated") }
        try await moveTo(dx(x), dy(y), rehome: rehome)
        if aim && screen != nil { try await self.aim(x, y) }
    }

    /// Closed loop: find the real pointer on screen, fix a miss, and learn the error for later moves.
    private func aim(_ x: Double, _ y: Double) async throws {
        guard let span, let found = try await measure(x, y, model: false) else {
            log(String(format: "aim (%.3f, %.3f): pointer not found", x, y))
            return
        }
        let fx = Double(found.x), fy = Double(found.y)
        if max(abs(fx - x), abs(fy - y)) <= Self.maxMiss {  // learn from normal drift only, never a stray reading
            remember("x", (fix(x, "x"), fx))
            remember("y", (fix(y, "y"), fy))
            save()
        }
        if abs(fx - x) <= Self.aimTolerance && abs(fy - y) <= Self.aimTolerance { return }
        let mx = Int(((x - fx) * Double(span.w)).rounded(.toNearestOrEven)), my = Int(((y - fy) * Double(span.h)).rounded(.toNearestOrEven))
        try await device.send("move \(mx) \(my)")  // fix this miss right away
        if let p = pos { pos = (p.0 + mx, p.1 + my) }
    }

    /// Wiggle the pointer and find it on screen, near the target first, then anywhere. model: ask the vision
    /// model when the pixels don't show it (~20 s, rarely right); a tap's aim never waits for that.
    private func measure(_ x: Double, _ y: Double, model: Bool = true) async throws -> CGPoint? {
        guard let screen, let span else { return nil }
        let nudge = x < 0.9 ? Self.nudge : -Self.nudge  // stay clear of the screen edge
        await screen.settled(quiet: 0.15, least: 0.1, most: 0.6)  // pointer at rest
        let before = screen.frame, sent = now()
        try await device.send("move \(nudge) 0")
        var after = await screen.fresh(since: sent, timeout: 1.2)
        if after != nil {
            await screen.settled(quiet: 0.1, least: 0.05, most: 0.4)
            after = screen.frame
        }
        try await device.send("move \(-nudge) 0")
        let shift = Double(nudge) / Double(span.w)
        guard let before, let after else { return nil }
        if let p = Vision.pointer(before, after, near: CGPoint(x: x, y: y), shift: shift)
            ?? Vision.pointer(before, after, near: CGPoint(x: 0.5, y: 0.5), shift: shift, reach: CGPoint(x: 0.5, y: 0.5)) {
            return p
        }
        return model ? await locate?(after) : nil
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
        [0.2, 0.8].flatMap { t in ["x", "y"].map { abs(fix(t, $0) - t) } }.max() ?? 0
    }

    /// Demo data: pretend a calibration with this quality.
    func mockCalibrated(quality: Double) {
        span = span ?? Span(w: 400, h: 860)
        self.quality = quality
    }

    /// The fraction to aim at so the pointer lands on t, from the line through the observed landings.
    func fix(_ t: Double, _ axis: String) -> Double {
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

    private func moveTo(_ tx: Int, _ ty: Int, rehome: Bool = true) async throws {
        if link != device.links {  // new link: a dropped gesture may have left the button down
            try await device.send("release")
            (pos, link) = (nil, device.links)
        }
        if pos == nil || (rehome && moves >= Self.rehomeEvery) {
            try await device.send("home")
            (pos, moves) = ((0, 0), 0)
        }
        let (x, y) = pos!
        pos = nil  // unknown until the move succeeds
        try await device.send("move \(tx - x) \(ty - y)")
        (pos, moves) = ((tx, ty), moves + 1)
    }

    /// Let go of the button and re-home the pointer, whatever state a gesture left.
    func reset() async throws {
        pos = nil
        drawChain = false
        unitsSinceDrawHome = 0
        try await device.send("release")
        try await device.send("home")
        (pos, moves) = ((0, 0), 0)
    }

    /// aim: find the pointer on screen first (slower); worth it when a tap just missed.
    func tap(_ x: Double, _ y: Double, aim: Bool = false) async throws {
        drawChain = false  // a tap ends a drawing run: its drift must not carry into the next stroke
        try await point(x, y, aim: aim)
        try await device.send("click")
        try await Task.sleep(nanoseconds: UInt64(Self.tapGap * 1e9))
    }

    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool = true) async throws {
        try await drag([CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)], hold: hold)
    }

    /// Press at the first point, move through the rest, release: one continuous stroke. hold rests at the end
    /// first, so lists and pickers stop exactly there; system gestures (home, back) need the flick.
    func drag(_ points: [CGPoint], hold: Bool = true) async throws {
        guard points.count >= 2, points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw DeviceError(message: "drag needs at least two finite points")
        }
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
        try await point(Double(points[0].x), Double(points[0].y), rehome: startFromHome)
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
            if strokeCommand != true || points.count <= 2 {
                for p in points.dropFirst() {
                    try await moveTo(dx(Double(p.x)), dy(Double(p.y)), rehome: false)  // never home mid-drag
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

    func scroll(_ x: Double, _ y: Double, lines: Int) async throws {
        drawChain = false
        try await point(x, y)
        try await device.send("scroll \(lines) 0")
    }

    /// The board only has US keys. Chinese (simplified or traditional: whichever pinyin keyboard the phone has on)
    /// goes in as toneless pinyin left open for the actor to inspect and select the exact candidate. A run with
    /// Latin letters goes in between two Caps Lock presses, which switch the pinyin keyboard to English and back.
    /// Assumes the phone's keyboard is a pinyin keyboard in Chinese mode, and leaves it that way.
    func type(_ text: String) async throws {
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
                let phrase = String(run.text.prefix(12))
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
    func key(_ combo: String) async throws { drawChain = false; try await device.send("key \(combo)") }
    /// The board's consumer-control Home key ("AC Home"), which iOS treats like a keyboard's home key. Boards
    /// without it (older firmware) answer an error: then Cmd+H and the flick up from the home bar (a flick, not
    /// a rest: resting opens the app switcher).
    func goHome() async throws {
        // Firmware v14+: the board flicks up from the home bar by itself, press to release with no pause (sent as
        // separate commands, the ~130 ms before `release` read as a rest and opened the app switcher). It moves
        // the pointer, so re-home before the next gesture. Older boards answer an error: fall through.
        drawChain = false
        if (try? await device.send("flickhome")) != nil { pos = nil; return }
        if (try? await device.send("homescreen")) != nil { return }
        try await key("cmd+h")
        try await Task.sleep(nanoseconds: 350_000_000)
        try await swipe(0.5, 0.995, 0.5, 0.45, hold: false)
        pos = nil  // starting at the screen's edge may have clamped the pointer: re-home before the next move
    }
    func goBack() async throws {
        try await swipe(0.005, 0.45, 0.6, 0.45, hold: false)
        pos = nil
    }

    private func dx(_ x: Double) -> Int { Int((min(max(fix(x, "x"), 0), 1) * Double(span!.w)).rounded(.toNearestOrEven)) }
    private func dy(_ y: Double) -> Int { Int((min(max(fix(y, "y"), 0), 1) * Double(span!.h)).rounded(.toNearestOrEven)) }
}
