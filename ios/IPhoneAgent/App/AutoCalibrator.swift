import Foundation
import UIKit

/// Calibrates the pointer like a 3D printer's auto bed levelling, on the calibration board: a white
/// full-screen grid (CalibrationBoard) over the app. The board homes the pointer, clicks at known mouse
/// distances and catches the taps (TouchProbe), then validates a measured per-axis mapping.
/// Missing or inconsistent clicks leave calibration unsuccessful; video guesses cannot bypass the checks.
/// If both fail the board offers Try Again and "Tap the pointer yourself" (manual needs the grid behind it).
/// It never starts by itself: when calibration is needed and the mouse and mirroring are up, the Agent page
/// shows a Calibrate button; a run calibrates first if needed; Settings › Calibration starts it too.
@MainActor final class AutoCalibrator: ObservableObject {
    enum Phase: Equatable {
        case idle, homing, probeA, probeB, verifying, done, needsTap, failed

        /// 1...4 while working.
        var step: Int? {
            switch self {
            case .homing: return 1
            case .probeA: return 2
            case .probeB: return 3
            case .verifying: return 4
            default: return nil
            }
        }
    }

    struct Progress: Equatable { var done: Int, total: Int }

    static let tolerance = 0.015  // fraction of the screen; a bigger miss calibrates again

    @Published var phase = Phase.idle
    @Published var reason = ""  // why the last run started
    @Published var progress: Progress?  // probe clicks
    /// Why the last run failed, in words for the board (e.g. clicks not reaching the screen).
    @Published var problem: String?
    /// The calibration board is up.
    @Published private(set) var boardOpen = false
    /// The small success toast ("Pointer calibrated ±0.6%").
    @Published var toast = false
    unowned let app: AppModel
    var link = -1  // board link the pointer was last calibrated on
    private var hide: Task<Void, Never>?
    private var current: Task<Void, Never>?

    init(app: AppModel) { self.app = app }

    var busy: Bool { phase.step != nil }

    /// The mouse is up (board connected, USB HID mounted).
    var boardReady: Bool { app.board.connected && app.board.status?.usb == "ok" }
    var mirroring: Bool { app.feed.isNative ? app.feed.watchable : app.board.status?.ap == "streaming" }

    /// Calibration is due: never done, an aimed tap found it stale, the screen shape changed, or the learned
    /// correction drifted.
    var needed: Bool {
        let p = app.pointer
        guard p.calibrated, !p.stale else { return true }
        if let aspect = p.aspect, abs(aspect - DeviceScreen.aspect) > 0.02 { return true }
        return p.drift > Self.tolerance
    }

    /// Show the Calibrate button: due, and everything it needs is up.
    var offer: Bool { (needed || MockMode.on && !app.pointer.calibrated) && (MockMode.on || boardReady && mirroring) && !busy && !boardOpen }

    /// Open the board and calibrate automatically (Calibrate button, Settings, debug entry).
    func calibrate(why: String = String(localized: "requested")) {
        guard !busy else { return }
        Task { await run(why: why) }
    }

    /// Before a run: calibrate if needed and wait for it. True when the pointer is calibrated.
    func ensureCalibrated() async -> Bool {
        while busy { try? await Task.sleep(nanoseconds: 200_000_000) }
        if needed && boardReady { await run(why: String(localized: "before a run")) }
        return app.pointer.calibrated && !app.pointer.stale
    }

    /// One automatic calibration, on the board when the app is in front.
    func run(why: String) async {
        reason = why
        problem = nil
        progress = nil
        toast = false
        if DeviceScreen.foreground { openBoard() }
        let job = Task { await runOnce() }
        current = job
        await job.value
        current = nil
    }

    private func openBoard() {
        boardOpen = true
        app.probe.begin()
    }

    private func closeBoard() {
        boardOpen = false
        app.probe.end()
    }

    /// The board's Back button: stop whatever runs and close the board.
    func cancel() {
        current?.cancel()
        if busy || phase == .needsTap { app.say("calibration: cancelled") }
        progress = nil
        phase = app.pointer.calibrated ? .done : .idle
        closeBoard()
        Task { _ = try? await app.pointer.reset() }
    }

    /// The accuracy test (user 11-08: prove the hand with numbers). On the board, 20 spots over the whole screen are
    /// tapped the way a task taps them (from the corner, hops, the right border, the arrival check) and each real touch
    /// is caught, so every miss is measured, not guessed. It changes nothing; the log keeps each spot and a summary.
    static let accuracySpots: [(Double, Double)] = [0.1, 0.3, 0.5, 0.7, 0.9].flatMap { y in [0.12, 0.38, 0.63, 0.9].map { ($0, y) } }

    func testAccuracy() {
        guard !busy, app.pointer.calibrated, DeviceScreen.foreground else { return }
        reason = "accuracy test"
        problem = nil
        openBoard()
        let job = Task { await runAccuracy() }
        current = job
        Task {
            await job.value
            current = nil
            progress = nil
            phase = app.pointer.calibrated ? .done : .idle
            closeBoard()
        }
    }

    private func runAccuracy() async {
        phase = .verifying
        let spots = Self.accuracySpots
        progress = Progress(done: 0, total: spots.count)
        app.say("accuracy test: \(spots.count) spots, tapped like a task")
        try? await app.pointer.reset()
        try? await Task.sleep(nanoseconds: 400_000_000)  // the board painted plain
        // The closed loop sees where the pointer arrived; without a frame the test measures blind taps only
        // (11-08: three runs after a relaunch, sharing off, no frame, nothing said). The reset's move publishes one.
        for _ in 0..<20 where app.feed.frame == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard app.feed.frame != nil else {
            return app.say("accuracy test: no screen frame (share the whole screen on Home first); not measured")
        }
        var misses: [Double] = [], eye: [Pointer.Arrival?] = []
        for (i, (x, y)) in spots.enumerated() {
            if Task.isCancelled { break }
            let sent = now()
            app.pointer.lastArrival = nil
            do { try await app.pointer.tap(x, y) } catch {
                app.say(String(format: "accuracy %ld: (%.2f, %.2f) not tapped: %@", i + 1, x, y, error.localizedDescription))
                continue
            }
            if let p = await app.probe.tap(since: sent, timeout: Self.tapTimeout) {
                let miss = max(abs(Double(p.x) - x), abs(Double(p.y) - y))
                misses.append(miss)
                let saw = app.pointer.lastArrival
                eye.append(saw)
                app.say(String(format: "accuracy %ld: (%.2f, %.2f) landed (%.3f, %.3f), miss %.1f%%, eye %@", i + 1, x, y, p.x, p.y,
                               miss * 100, saw.map { "\($0)" } ?? "none"))
            } else {
                app.say(String(format: "accuracy %ld: (%.2f, %.2f) no touch caught", i + 1, x, y))
            }
            progress = Progress(done: i + 1, total: spots.count)
        }
        guard !misses.isEmpty else { return app.say("accuracy test: no touches caught") }
        let within1 = misses.filter { $0 <= 0.01 }.count, within2 = misses.filter { $0 <= 0.02 }.count
        let mean = misses.reduce(0, +) / Double(misses.count)
        app.say(String(format: "accuracy test: %ld of %ld caught; within 1%%: %ld, within 2%%: %ld; mean %.1f%%, worst %.1f%%; eye on target %ld, off %ld, unseen %ld",
                       misses.count, spots.count, within1, within2, mean * 100, (misses.max() ?? 0) * 100,
                       eye.filter { $0 == .onTarget }.count, eye.filter { $0 == .offTarget }.count,
                       eye.filter { $0 == .unseen || $0 == nil }.count))
    }

    private func runOnce() async {
        if MockMode.on { return await mockRun() }
        app.say("calibration: \(reason)")
        if boardOpen {
            do {
                switch try await touchCalibrate(full: true) {
                case .done(let error): return finished(error)
                case .noTaps: return failed(Self.noTapsText)
                case .failed(let why): return failed(why)
                }
            } catch {
                if Task.isCancelled { return }
                return failed(error.localizedDescription)
            }
        }
        if Task.isCancelled { return }
        progress = nil
        failed("请回到 Lan Agent 的校准页面，完成实测点击校准后再开始任务。")
    }

    static var noTapsText: String {
        String(localized: "Clicks aren't reaching the screen. Check AssistiveTouch and the existing pointer control connection.")
    }

    func finished(_ error: Double) {
        guard error.isFinite, error <= Self.maxCheckError else {
            app.pointer.discardProbe()
            return failed(String(format: "校准验证误差 %.1f%%，超过 1.5%%，没有保存。", error * 100))
        }
        link = app.board.commands.links
        progress = nil
        problem = nil
        phase = .done
        app.say(String(format: "calibration: ±%.1f%%", error * 100))
        closeBoard()
        toast = true
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = false
        }
    }

    /// The board stays up with the problem, Try Again and "Tap the pointer yourself".
    private func failed(_ why: String) {
        app.pointer.discardProbe()
        progress = nil
        problem = why
        phase = .failed
        app.say("calibration failed: \(why)")
    }

    // MARK: - manual, on the board

    /// "Tap the pointer yourself": park the pointer at a known spot, then the next tap on the board is where it is.
    func startManual() {
        guard boardOpen else { return }
        problem = nil
        phase = .needsTap
        current?.cancel()
        current = Task {
            do {
                try await app.pointer.reset()
                try await app.board.commands.send("move \(Pointer.calibrationMove) \(Pointer.calibrationMove)")
            } catch {
                return failed(error.localizedDescription)
            }
            let since = now()
            while !Task.isCancelled && phase == .needsTap {
                if let p = await app.probe.tap(since: since, timeout: 1) {
                    app.say(String(format: "calibration: tapped the pointer at (%.3f, %.3f)", p.x, p.y))
                    app.pointer.finishCalibration(x: p.x, y: p.y)
                    // One human-picked point is only a rough estimate, never a fabricated 1% success.
                    do {
                        switch try await touchCalibrate(full: true) {
                        case .done(let error): return finished(error)
                        case .noTaps: return failed(Self.noTapsText)
                        case .failed(let why): return failed(why)
                        }
                    } catch { return failed(error.localizedDescription) }
                }
            }
        }
    }

    private func mockRun() async {
        for (i, p) in [Phase.homing, .probeA, .probeB, .verifying].enumerated() {
            phase = p
            progress = Progress(done: i * 2, total: 8)
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
        }
        app.pointer.mockCalibrated(quality: 0.006)
        finished(0.006)
    }
}
