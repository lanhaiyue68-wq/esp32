import Foundation
import UIKit

/// The board did not answer in time; the link is still up (a disconnect throws DeviceError instead).
struct BoardTimeout: LocalizedError {
    let command: String
    let seconds: Double
    var errorDescription: String? { String(format: "the board did not answer '%@' within %.0f s", command, seconds) }
}

struct DeviceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Where command lines go: the BLE link, or a fake board in tests.
@MainActor protocol BoardTransport: AnyObject {
    var isConnected: Bool { get }
    func write(_ line: String) throws
    /// Fire-and-forget: write only if the link can take it right now; false = dropped.
    func writeIfIdle(_ line: String) -> Bool
    /// Bytes one write can carry without a response.
    var maxWrite: Int { get }
    /// Drop the link after a timeout; the transport reconnects on its own (like the old TCP close).
    func dropLink()
}

extension BoardTransport {
    func writeIfIdle(_ line: String) -> Bool { (try? write(line)) != nil }
    var maxWrite: Int { 180 }
}

/// What gestures need from the board (CommandChannel, or a fake in tests).
@MainActor protocol HIDDevice: AnyObject {
    var links: Int { get }
    var connected: Bool { get }
    @discardableResult func send(_ command: String) async throws -> String
    func waitConnected(_ timeout: TimeInterval) async -> Bool
    func abort() async throws
}

extension HIDDevice {
    func abort() async throws { try await send("abort") }
}

/// A FIFO async mutex for main-actor code.
@MainActor final class AsyncLock {
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

/// Sends the board commands one at a time and matches replies by request id. Port of device.py.
@MainActor final class CommandChannel: HIDDevice {
    weak var transport: BoardTransport?
    private(set) var links = 0  // bumped on every (re)connect, so gestures know to release and re-home
    private let lock = AsyncLock()
    /// The board serves two centrals (this app and a Mac harness) and notifies replies to both: start our ids
    /// far from the harness's small ones, and drop replies to ids we did not send.
    private var nextID = Int.random(in: 100_000...800_000)
    private var logTimes: [Double] = []
    /// "app <command>" lines relayed from the Mac harness.
    var onAppCommand: ((String) -> Void)?
    private var pending: [Int: CheckedContinuation<BoardReply, Error>] = [:]
    private var epoch = 0  // bumped by a stop: what was queued before it never runs
    /// D97, z6 on 139: bumped by a dropped link. The link dropped for 2.5 s (CBError 6) while a ping held the line; the
    /// run's next command, queued behind it, was failed as a stop (CancellationError) and the 48-item run ended as
    /// "任务被停止了" at 10 minutes. A command queued before a dropped link fails as a lost link, which a run gets over.
    private var linkEpoch = 0
    private var stopping = false
    private var last = 0.0, beat = 0.0
    var onTiming: ((String, Double) -> Void)?  // command name, ms

    init(transport: BoardTransport? = nil) { self.transport = transport }

    var connected: Bool { transport?.isConnected ?? false }

    /// The transport (re)connected and subscribed.
    func linkUp() {
        links += 1
        last = now(); beat = last  // fresh link: nothing to keep awake yet
    }

    /// The link dropped: fail everything in flight.
    func linkDown() {
        linkEpoch += 1
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: DeviceError(message: "board disconnected")) }
    }

    func handleReply(_ line: String) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("app ") {
            onAppCommand?(String(text.dropFirst(4)))  // AppModel acts on it only with Send Logs to Computer on
            return
        }
        if text.hasPrefix("log ") { return }  // our own log lines, relayed to the harness
        guard let reply = BoardReply.parse(line), let c = pending.removeValue(forKey: reply.id) else { return }
        c.resume(returning: reply)
    }

    func waitConnected(_ timeout: TimeInterval) async -> Bool {
        let deadline = now() + timeout
        while !connected && now() < deadline { try? await Task.sleep(nanoseconds: 200_000_000) }
        return connected
    }

    /// Seconds the board may take: replies need up to ~2 s at p99, moves are paced (10 units per 8 ms),
    /// typing is per character.
    nonisolated static func timeout(_ command: String) -> Double {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        let name = parts.first ?? "", arg = parts.count > 1 ? parts[1] : ""
        switch name {
        case "move": return 5 + Double(arg.split(separator: " ").compactMap { Int($0) }.map(abs).max() ?? 0) / 10 * 0.012
        case "stroke":  // the whole stroke runs on the board: allow for every segment, like a move each
            let v: [Int] = arg.split(separator: " ").compactMap { Int($0) }.map(abs)
            var units = 0  // the longer axis of each segment, summed
            for i in stride(from: 0, to: v.count - 1, by: 2) { units += max(v[i], v[i + 1]) }
            return 5 + Double(units) / 10 * 0.012
        case "type": return 5 + 0.1 * Double(arg.count)
        case "ping": return 8  // an idle check: tolerate a hiccup rather than drop a healthy board
        case "snap": return 15  // a whole GOP over BLE
        case "bench": return 5 + (Double(arg) ?? 0) / 10  // KB at >= 80 kbps
        default: return 5
        }
    }

    /// Called once when a command times out (e.g. video starving control traffic): the app turns the
    /// stream off. The outcome is uncertain: never replay the command automatically.
    var onTimeout: ((String) async -> Void)?

    // MARK: iPad home (162)
    // The firmware's `home` throws the pointer into the top-left corner in six fast reports. On an iPad a push past the
    // top edge pulls Notification Center down, and one past the bottom goes to the Home Screen: 小藍 161's calibration
    // homed, the app was covered and its probe clicks never arrived (11-25). Measured that day on the customer's iPad 9
    // over the test channel (pointer seen in the shared screen): the screen is ~3900 x 5270 app units; pushing left is
    // always harmless; a single paced push 150, 400 or 800 units past the top did nothing, but the fast `home`, a push
    // ~2000 past it, five 700-unit pushes in a row at the top, and 6000 down past the bottom all did. So on an iPad a
    // home pushes left, then up only `padMargin` past the top, from where the pointer is known to be.

    /// App units across the iPad (Pointer sets the calibrated span; these are the measured values before one).
    static var padSpan = (w: 1750, h: 2330)  // the customer's iPad 9 at 60 counts / 30 ms (11-25; 3900 x 5300 at 10 / 20 ms)
    /// How far past the left and top edges a home pushes: ~5.7% of the screen's height (300 units on the customer's iPad
    /// at its pointer speed of 11-25; 800 there tested harmless), so it stays as small a push if the speed changes.
    static func margin(_ span: (w: Int, h: Int)) -> Int { max(80, span.h * 57 / 1000) }
    static var padMargin: Int { margin(padSpan) }
    /// 171: one pace for every move on an iPad, counts a report (v35 boards; older ones keep their own 10). 170 moved at
    /// 40 and pushed edges at 10: iPadOS speeds a fast pointer up, so a fast count went ~1.5x as far as a slow one, the
    /// slow home stopped short of the corner (fit offset 0.15 / 0.20, 11-25 14:16) and calibration failed at ±7–9%.
    /// Every move at 10, as 168 was (±0.5%). Speed comes from the iPad's own 跟踪速度 (twice as fast, same pace).
    /// `padStepV1` (test channel /padstep) tries another pace on the device.
    /// 174 (user 11-25 on 173's step 10: "还是慢", wanted 170's speed; measured on the customer's iPad 9, 跟踪速度 at its
    /// fastest, v38 boards with `round on`): moves go at 60 counts every 30 ms, where a long move goes as far as it is long
    /// times one gain, a short one starts slower (padShort), and a push past an edge must be slow (padPushParts).
    /// `padStepV2` / `padPaceV1` (test channel /padstep) try another pace on the device.
    static let padStepKey = "padStepV2"
    static let defaultPadStep = 60  // with defaultPadPace 30: as fast as 40 every 20 ms, without its extra jumps
    static var padStep: Int {
        let n = UserDefaults.standard.integer(forKey: padStepKey)
        return n == 0 ? defaultPadStep : min(max(n, 2), 127)
    }
    /// ms between Bluetooth move reports (v37 boards' `pace`; older boards keep 20).
    static let padPaceKey = "padPaceV1"
    static let defaultPadPace = 30
    static var padPaceMs: Int {
        let n = UserDefaults.standard.integer(forKey: padPaceKey)
        return n == 0 ? defaultPadPace : min(max(n, 10), 60)
    }

    /// 174: the slow pace (counts a report) for a push past an edge and for a move from an unknown place: every edge
    /// test of 11-25 was made at 10. Fast, a push left past the edge brought up Stage Manager's recent apps (11-25, at 25
    /// and above: the calibration's clicks landed on it and it failed), up opens Notification Center, down goes Home.
    /// 174: the same speed as 10 counts every 20 ms at any report interval.
    static var padSlowStep: Int { max(2, 10 * padPaceMs / 20) }
    /// How many slow units go as far as one app (fast) unit. Calibration corrects it (correctSlowRatio): its locating
    /// moves go slow, its probes fast, and both measure the screen.
    static let padSlowRatioKey = "padSlowRatioV1"
    static let defaultSlowRatio = 2.35  // 60 counts / 30 ms at ~0.55 px a unit, 10 / 20 ms at 0.2345 (960-wide frames, 11-25)
    static var padSlowRatio: Double {
        get {
            let r = UserDefaults.standard.double(forKey: padSlowRatioKey)
            return r == 0 ? defaultSlowRatio : r
        }
        set { UserDefaults.standard.set(min(max(newValue, 0.8), 4), forKey: padSlowRatioKey) }
    }
    /// The screen as the calibration's (slow) locating moves measured it, in app units; compared with the probes' span.
    static var padLocatedSpan: (w: Int, h: Int)?
    /// After a calibration: a slow ratio that was off measured the screen bigger or smaller than the fast probes did.
    static func correctedSlowRatio(_ ratio: Double, located: (w: Int, h: Int), probed: (w: Int, h: Int)) -> Double? {
        guard probed.w > 0, probed.h > 0 else { return nil }
        let k = (Double(located.w) / Double(probed.w) + Double(located.h) / Double(probed.h)) / 2
        guard (0.5...2).contains(k) else { return nil }  // a locating click that missed: keep the ratio
        return ratio * k
    }

    /// 178 (user 11-25, twice: "不要放角落", "右上角、右下角都不要有"): the one gate every iPad move passes. Where the
    /// pointer's place is known, no move ends in the band along the screen's edges and corners (2% at the sides, 3% at
    /// the top, under the status bar, 4% at the bottom, over the Dock and the Home bar); it stops at the band. So no
    /// feature, calibration or home can take the pointer into an edge or a corner. A move from inside the band out of
    /// it is let through.
    static let padSafe = (left: 0.02, right: 0.98, top: 0.03, bottom: 0.96)
    static func padKeptClear(_ command: String, from pos: (x: Int, y: Int)?, span: (w: Int, h: Int)) -> String? {
        let parts = command.split(separator: " ")
        guard let p = pos, parts.count == 3, parts[0] == "move", let dx = Int(parts[1]), let dy = Int(parts[2]) else { return nil }
        let w = Double(span.w), h = Double(span.h)
        let tx = min(max(Double(p.x + dx), padSafe.left * w), padSafe.right * w)
        let ty = min(max(Double(p.y + dy), padSafe.top * h), padSafe.bottom * h)
        let nx = Int(tx.rounded()) - p.x, ny = Int(ty.rounded()) - p.y
        return nx == dx && ny == dy ? nil : "move \(nx) \(ny)"
    }

    /// 174: the fast and the slow part of a `move` (app units) on an iPad. Inside the screen it goes fast; the part past
    /// an edge goes slow; all of it slow when the pointer's place is not known (it may be at an edge). nil: not a move,
    /// or one that stays inside the screen.
    static func padPushParts(_ command: String, from pos: (x: Int, y: Int)?,
                             span: (w: Int, h: Int)) -> (fast: (x: Int, y: Int), slow: (x: Int, y: Int))? {
        let parts = command.split(separator: " ")
        guard parts.count == 3, parts[0] == "move", let dx = Int(parts[1]), let dy = Int(parts[2]), dx != 0 || dy != 0 else {
            return nil
        }
        guard let p = pos else { return ((0, 0), (dx, dy)) }
        if (0...span.w).contains(p.x + dx), (0...span.h).contains(p.y + dy) { return nil }
        func reach(_ from: Int, _ d: Int, _ end: Int) -> Double {
            d > 0 ? Double(max(0, end - from)) / Double(d) : d < 0 ? Double(max(0, from)) / Double(-d) : 1
        }
        let k = min(1, reach(p.x, dx, span.w), reach(p.y, dy, span.h))
        let fast = (x: Int((Double(dx) * k).rounded(.towardZero)), y: Int((Double(dy) * k).rounded(.towardZero)))
        return (fast, (dx - fast.x, dy - fast.y))
    }

    /// 174: a short fast move starts slower than a long one (iPadOS speeds the pointer up over its first reports).
    /// Measured at 60 counts / 30 ms on v38 (11-25, every round trip the same each way): 160 units went 42 px, 320 → 101,
    /// 480 → 183, 640 → 312, and longer moves (curves from 640 on, PadCurve.shortest) ~0.55 px a unit. As app units
    /// (px / 0.55): what a move should go → what to send. Only for that pace; other paces send as they are.
    static let padShortTable: [(want: Double, send: Double)] = [(0, 0), (76, 160), (184, 320), (332, 480), (568, 640), (640, 700)]
    static let padShortStep = 60, padShortPace = 30
    static func padShort(_ command: String, step: Int? = nil, pace: Int? = nil) -> String? {
        guard (step ?? padStep) == padShortStep, (pace ?? padPaceMs) == padShortPace else { return nil }
        let parts = command.split(separator: " ")
        guard parts.count == 3, parts[0] == "move", let dx = Int(parts[1]), let dy = Int(parts[2]) else { return nil }
        let len = hypot(Double(dx), Double(dy))
        guard len > 0, let i = padShortTable.firstIndex(where: { $0.want >= len }), i > 0 else { return nil }
        let (a, b) = (padShortTable[i - 1], padShortTable[i])
        let sendLen = a.send + (b.send - a.send) * (len - a.want) / (b.want - a.want)
        let k = sendLen / len
        return "move \(Int((Double(dx) * k).rounded())) \(Int((Double(dy) * k).rounded()))"
    }
    static let padPosKey = "padPointerPosV1"
    /// Where the pointer is on the iPad, in app units from the top-left corner; nil when not known. Kept across launches
    /// (the iPad keeps its pointer where it was), forgotten after anything that can move it unseen.
    static var padPos: (x: Int, y: Int)? {
        get {
            guard let a = UserDefaults.standard.array(forKey: padPosKey) as? [Int], a.count == 2 else { return nil }
            return (a[0], a[1])
        }
        set {
            if let p = newValue { UserDefaults.standard.set([p.x, p.y], forKey: padPosKey) }
            else { UserDefaults.standard.removeObject(forKey: padPosKey) }
        }
    }
    /// Finds the pointer's height on screen (0 top … 1 bottom) when padPos is not known (Pointer, from the frames).
    static var padLocateY: (() async -> Double?)?
    /// 174: an iPad's home, by looking (Pointer.padHome): the middle of the screen, never a corner.
    static var padHomeVisual: (() async -> String?)?  // why it failed; nil: home
    static func onPad() -> Bool { UIDevice.current.model.hasPrefix("iPad") }  // also an iPhone app run on an iPad

    /// An iPad home's commands: `abort` first (the firmware forgets its corner, so its curves never bow up or left),
    /// then one move up and left, `padMargin` past each edge. nil when the pointer's height is not known.
    /// 174 (user 11-25 on 173: "贝塞尔曲线做得还不是很好"): one move, not left and then up: two straight lines into the
    /// corner every home (five in one calibration) were the user's "别拆成两段直线". The board curves it inside its box.
    static func padHome(from pos: (x: Int, y: Int)?, span: (w: Int, h: Int), locatedY: Double?) -> [String]? {
        let y: Int
        if let pos { y = pos.y } else if let f = locatedY { y = Int((f * Double(span.h)).rounded()) } else { return nil }
        let x = pos?.x ?? span.w  // pushing left is harmless however far
        let m = margin(span)
        return ["abort", "move -\(max(0, x) + m) -\(max(0, y) + m)"]
    }

    /// Where the pointer is after a command (it stops at the edges); nil for anything that may move it unseen.
    static func padTrack(_ command: String, from pos: (x: Int, y: Int)?, span: (w: Int, h: Int)) -> (x: Int, y: Int)? {
        let parts = command.split(separator: " ").map(String.init)
        switch parts.first ?? "" {
        case "move", "stroke":
            guard var p = pos else { return nil }
            let v = parts.dropFirst().compactMap { Int($0) }
            for i in stride(from: 0, to: v.count - 1, by: 2) {
                p = (min(max(p.x + v[i], 0), span.w), min(max(p.y + v[i + 1], 0), span.h))
            }
            return p
        case "click", "press", "release", "scroll", "type", "key", "ping", "curve", "status", "snap", "stream", "fps",
             "res", "log", "bench", "phy", "coex", "hid", "app", "step", "round", "pace": return pos
        default: return nil  // abort, flickhome, homescreen, unpair, …
        }
    }

    /// Send one command; returns the text after "ok" (e.g. bench's ms). Throws DeviceError on err/timeout.
    @discardableResult
    func send(_ command: String) async throws -> String {
        guard Self.onPad() else { return try await sendWatched(command) }
        if command == "home" { return try await padHomeNow() }
        await padPace()
        var command = command
        if !padHeld, let clear = Self.padKeptClear(command, from: Self.padPos, span: Self.padSpan) {
            DebugLog.write("ipad: \(command) would end at the screen's edge; \(clear) instead (kept clear)")
            command = clear
        }
        if !padHeld, let push = Self.padPushParts(command, from: Self.padPos, span: Self.padSpan) {
            return try await padPush(command, push)
        }
        let sent = Self.padCurved(command, from: Self.padPos, span: Self.padSpan, held: padHeld)
            ?? (padHeld ? nil : Self.padShort(command)) ?? command
        do {
            let reply = try await sendWatched(sent)
            Self.padPos = Self.padTrack(command, from: Self.padPos, span: Self.padSpan)  // app units, as asked
            padHeld = Self.heldAfter(sent, was: padHeld)
            return reply
        } catch {
            Self.padPos = nil  // a command that failed may have moved part of the way
            throw error
        }
    }

    /// 174: a move past an edge (or from an unknown place): fast up to the edge, then the rest at the slow pace, its
    /// units scaled so it goes as far as asked; then back to the fast pace.
    private func padPush(_ command: String, _ push: (fast: (x: Int, y: Int), slow: (x: Int, y: Int))) async throws -> String {
        let from = Self.padPos
        do {
            if push.fast.x != 0 || push.fast.y != 0 {
                let fast = "move \(push.fast.x) \(push.fast.y)"
                _ = try await sendWatched(Self.padCurved(fast, from: from, span: Self.padSpan, held: false)
                                          ?? Self.padShort(fast) ?? fast)
            }
            let r = Self.padSlowRatio
            _ = try await sendWatched("step \(Self.padSlowStep)")
            _ = try await sendWatched("move \(Int((Double(push.slow.x) * r).rounded())) \(Int((Double(push.slow.y) * r).rounded()))")
            _ = try await sendWatched("step \(Self.padStep)")
        } catch {
            Self.padPos = nil
            _ = try? await sendWatched("step \(Self.padStep)")
            throw error
        }
        Self.padPos = Self.padTrack(command, from: from, span: Self.padSpan)
        return ""
    }

    /// 171: a `move` on an iPad goes as a curve (PadCurve) when the pointer's place is known, no button is down (a drag
    /// keeps its line) and the move is long enough to show one; otherwise nil (sent as it is).
    static func padCurved(_ command: String, from pos: (x: Int, y: Int)?, span: (w: Int, h: Int), held: Bool,
                          random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> String? {
        let parts = command.split(separator: " ")
        guard !held, let pos, parts.count == 3, parts[0] == "move", let dx = Int(parts[1]), let dy = Int(parts[2]) else {
            return nil
        }
        return PadCurve.stroke(from: pos, by: (dx, dy), span: span, random: random)
    }

    static func heldAfter(_ command: String, was held: Bool) -> Bool {
        switch command.split(separator: " ").first ?? "" {
        case "press": return true
        case "release", "click", "abort": return false
        default: return held
        }
    }

    private func sendWatched(_ command: String) async throws -> String {
        do {
            return try await send(command, timeout: nil)
        } catch let e as BoardTimeout {
            if command != "ping", !command.hasPrefix("stream"), let onTimeout { await onTimeout(command) }
            throw e
        }
    }

    /// 171: the board starts at 40 counts a report (v35): set the one iPad pace (padStep) once per link, before anything
    /// moves. Every push past an edge of 11-25 was tested at 10. Older boards answer "unknown command": asked once a link.
    private var pacedLink = -1, pacedStep = 0, pacedMs = 0
    private var padHeld = false
    func padPace() async {
        let step = Self.padStep, ms = Self.padPaceMs
        guard pacedLink != links || pacedStep != step || pacedMs != ms else { return }
        (pacedLink, pacedStep, pacedMs) = (links, step, ms)
        _ = try? await send("step \(step)", timeout: nil)
        // 174: v37 boards' report interval; Bluetooth before Wi-Fi on the board's radio (11-25: at 40 counts a move went
        // ~3.5% too far one time in 7, one in 26 with `coex bt`: a missed connection event carried two reports).
        _ = try? await send("pace \(ms)", timeout: nil)
        _ = try? await send("coex bt", timeout: nil)
        // 174: v36 boards send every report `step` long along the move (not up to `step` on each axis): one speed in
        // every direction, so iPadOS's pointer acceleration is the same for every piece of a curve. 173's square
        // reports drew curves as stairs and landed them 4–7% off. Older boards answer "unknown command".
        _ = try? await send("round on", timeout: nil)
    }

    private func padHomeNow() async throws -> String {
        if let visual = Self.padHomeVisual {  // 174
            Self.padPos = nil
            await padPace()
            _ = try await sendWatched("abort")
            padHeld = false
            if let why = await visual() { throw DeviceError(message: why) }  // 175: what really went wrong
            return ""
        }
        var located: Double?
        if Self.padPos == nil, let locate = Self.padLocateY { located = await locate() }
        guard let steps = Self.padHome(from: Self.padPos, span: Self.padSpan, locatedY: located) else {
            DebugLog.write("ipad home: pointer position unknown and not seen; refused (a blind push could open Notification Center)")
            throw DeviceError(message: "iPad 上不知道指针在哪里：请先在小藍打开「共享整个屏幕」让它看得到指针，再校准。")
        }
        DebugLog.write("ipad home: " + steps.joined(separator: " · "))
        let from = Self.padPos
        Self.padPos = nil
        await padPace()
        _ = try await sendWatched(steps[0])  // abort
        padHeld = false
        // 174: to the corner fast (a curve) when the place is known, the push past the edges slow (padPush)
        Self.padPos = from
        if let push = Self.padPushParts(steps[1], from: from, span: Self.padSpan) {
            _ = try await padPush(steps[1], push)
        } else {
            _ = try await sendWatched(steps[1])
        }
        Self.padPos = (0, 0)
        return ""
    }

    /// A timeout is the board being slow (e.g. a snap while it also streams), not a lost link: it throws
    /// BoardTimeout and keeps the connection; only a real CoreBluetooth disconnect fails as link lost.
    @discardableResult
    func send(_ command: String, timeout custom: Double?) async throws -> String {
        let queuedAt = epoch, linkAt = linkEpoch
        await lock.lock()
        defer { lock.unlock() }
        try Task.checkCancellation()
        guard queuedAt == epoch, !stopping else { throw CancellationError() }
        guard linkAt == linkEpoch else { throw DeviceError(message: "board disconnected") }
        return try await exchange(command, timeout: custom)
    }

    /// Stop must reach the board while an earlier command is still executing.
    func abort() async throws {
        guard !stopping else { return }
        stopping = true
        epoch += 1
        let waiting = pending; pending = [:]
        waiting.values.forEach { $0.resume(throwing: CancellationError()) }
        defer { stopping = false }
        do { _ = try await exchange("abort", timeout: 3) }
        catch { transport?.dropLink(); throw error }
    }

    private func exchange(_ command: String, timeout custom: Double?) async throws -> String {
        try Task.checkCancellation()
        guard connected, let transport else { throw DeviceError(message: "board not connected") }
        let timeout = custom ?? Self.timeout(command)
        let name = String(command.split(separator: " ").first ?? "")
        guard command.utf8.count <= 480, !command.contains("\n"), !command.contains("\r"), !command.contains("\0") else {
            throw DeviceError(message: "command exceeds board limit or contains a line break")
        }
        let started = now()
        let id = nextID
        nextID += 1
        let reply: BoardReply
        do {
            reply = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<BoardReply, Error>) in
                    guard !Task.isCancelled else { c.resume(throwing: CancellationError()); return }
                    pending[id] = c
                    do { try transport.write("\(id) \(command)") } catch {
                        pending[id] = nil
                        c.resume(throwing: error)
                        return
                    }
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: UInt64(timeout * 1e9))
                        self?.fail(id, DeviceError(message: "timeout"))
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in self?.fail(id, CancellationError()) }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let ms = (now() - started) * 1000
            if (error as? DeviceError)?.message == "timeout" {
                if name != "ping" { DebugLog.write(String(format: "cmd #%d %@ → timeout after %.0f ms", id, String(command.prefix(40)), ms)) }
                throw BoardTimeout(command: String(command.prefix(30)), seconds: timeout)
            }
            DebugLog.write(String(format: "cmd #%d %@ → link lost after %.0f ms: %@", id, String(command.prefix(40)), ms,
                                  error.localizedDescription))
            throw DeviceError(message: "board link lost during '\(command.prefix(30))': \(error.localizedDescription)")
        }
        beat = now()  // last reply of any kind
        if command != "ping" {
            last = beat  // last real command: the phone's idle time
            onTiming?(String(command.split(separator: " ").first ?? ""), (now() - started) * 1000)
        }
        if name != "ping" {
            DebugLog.write(String(format: "cmd #%d %@ → %@ %@ (%.0f ms)", id, String(command.prefix(40)),
                                  reply.ok ? "ok" : "err", String(reply.text.prefix(60)), (now() - started) * 1000))
        }
        guard reply.ok else { throw DeviceError(message: "err " + reply.text) }
        return reply.text
    }

    /// Send a debug-log line to the Mac harness through the board (`log <text>`): fire-and-forget, at most
    /// 10 a second, truncated to one write, dropped when the link is busy.
    @discardableResult
    func relayLog(_ text: String) -> Bool {
        guard connected, let transport else { return false }
        let t = now()
        logTimes = logTimes.filter { t - $0 < 1 }
        guard logTimes.count < 10 else { return false }
        let prefix = "\(nextID) log "
        nextID += 1
        var body = text.replacingOccurrences(of: "\n", with: " ")
        while prefix.utf8.count + body.utf8.count > transport.maxWrite && !body.isEmpty { body.removeLast() }
        guard transport.writeIfIdle(prefix + body) else { return false }
        logTimes.append(t)
        return true
    }

    private func fail(_ id: Int, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    /// While idle: ping every few seconds, so a board that went away shows as gone within seconds, and nudge
    /// the pointer now and then so the phone does not auto-lock. Runs until cancelled.
    func keepAwake(idle: Double = 25, heartbeat: Double = 2, screenLive: @escaping () -> Bool) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(heartbeat * 1e9))
            if !connected || now() - beat < heartbeat { continue }
            do {
                // nudge only a phone that is awake and mirroring: there is nothing to keep awake otherwise
                if now() - last > idle && screenLive() {
                    // held a moment: there and back within one display frame changes no pixel, and the watch needs a
                    // frame now and then on a still screen (VideoFeed.watchable)
                    try await send("move 8 0")  // 4 can send nothing: the board keeps a remainder (4 units a count)
                    try await Task.sleep(nanoseconds: 120_000_000)
                    try await send("move -8 0")
                } else {
                    try await send("ping")
                }
            } catch {
                log("board gone: \(error.localizedDescription)")
            }
        }
    }

    var log: (String) -> Void = { print($0) }
}

func now() -> Double { Date().timeIntervalSince1970 }
