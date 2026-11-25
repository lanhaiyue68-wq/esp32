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
    static var padSpan = (w: 3900, h: 5300)  // measured on the customer's iPad 9 (11-25)
    /// How far past the left and top edges a home pushes: ~5.7% of the screen's height (300 units on the customer's iPad
    /// at its pointer speed of 11-25; 800 there tested harmless), so it stays as small a push if the speed changes.
    static func margin(_ span: (w: Int, h: Int)) -> Int { max(80, span.h * 57 / 1000) }
    static var padMargin: Int { margin(padSpan) }
    /// 171: one pace for every move on an iPad, counts a report (v35 boards; older ones keep their own 10). 170 moved at
    /// 40 and pushed edges at 10: iPadOS speeds a fast pointer up, so a fast count went ~1.5x as far as a slow one, the
    /// slow home stopped short of the corner (fit offset 0.15 / 0.20, 11-25 14:16) and calibration failed at ±7–9%.
    /// Every move at 10, as 168 was (±0.5%). Speed comes from the iPad's own 跟踪速度 (twice as fast, same pace).
    /// `padStepV1` (test channel /padstep) tries another pace on the device.
    static let padStepKey = "padStepV1"
    static var padStep: Int {
        let n = UserDefaults.standard.integer(forKey: padStepKey)
        return n == 0 ? 10 : min(max(n, 2), 40)
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
    static func onPad() -> Bool { UIDevice.current.model.hasPrefix("iPad") }  // also an iPhone app run on an iPad

    /// An iPad home's commands: `abort` first (the firmware forgets its corner, so its curves never bow up or left),
    /// then left and up, each `padMargin` past the edge. nil when the pointer's height is not known.
    static func padHome(from pos: (x: Int, y: Int)?, span: (w: Int, h: Int), locatedY: Double?) -> [String]? {
        let y: Int
        if let pos { y = pos.y } else if let f = locatedY { y = Int((f * Double(span.h)).rounded()) } else { return nil }
        let x = pos?.x ?? span.w  // pushing left is harmless however far
        let m = margin(span)
        return ["abort", "move -\(max(0, x) + m) 0", "move 0 -\(max(0, y) + m)"]
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
             "res", "log", "bench", "phy", "coex", "hid", "app", "step": return pos
        default: return nil  // abort, flickhome, homescreen, unpair, …
        }
    }

    /// Send one command; returns the text after "ok" (e.g. bench's ms). Throws DeviceError on err/timeout.
    @discardableResult
    func send(_ command: String) async throws -> String {
        guard Self.onPad() else { return try await sendWatched(command) }
        if command == "home" { return try await padHomeNow() }
        await padPace()
        let sent = Self.padCurved(command, from: Self.padPos, span: Self.padSpan, held: padHeld) ?? command
        do {
            let reply = try await sendWatched(sent)
            Self.padPos = Self.padTrack(sent, from: Self.padPos, span: Self.padSpan)
            padHeld = Self.heldAfter(sent, was: padHeld)
            return reply
        } catch {
            Self.padPos = nil  // a command that failed may have moved part of the way
            throw error
        }
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
    private var pacedLink = -1, pacedStep = 0
    private var padHeld = false
    func padPace() async {
        let step = Self.padStep
        guard pacedLink != links || pacedStep != step else { return }
        (pacedLink, pacedStep) = (links, step)
        _ = try? await send("step \(step)", timeout: nil)
    }

    private func padHomeNow() async throws -> String {
        var located: Double?
        if Self.padPos == nil, let locate = Self.padLocateY { located = await locate() }
        guard let steps = Self.padHome(from: Self.padPos, span: Self.padSpan, locatedY: located) else {
            DebugLog.write("ipad home: pointer position unknown and not seen; refused (a blind push could open Notification Center)")
            throw DeviceError(message: "iPad 上不知道指针在哪里：请先在小藍打开「共享整个屏幕」让它看得到指针，再校准。")
        }
        DebugLog.write("ipad home: " + steps.joined(separator: " · "))
        Self.padPos = nil
        await padPace()
        for step in steps { _ = try await sendWatched(step) }  // straight pushes, never curved
        padHeld = false
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
