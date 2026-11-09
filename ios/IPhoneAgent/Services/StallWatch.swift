import Foundation
import os

/// Tells apart what "resumed after N s suspended" cannot: the main thread stuck on something, or the whole app frozen by
/// iOS. On 11-09 a run's every part stood still for 5-20 s at a time and the cause could not be read from the log: this
/// thread keeps beating while the main thread is stuck, and stops too only if the whole app is held.
final class StallWatch: @unchecked Sendable {
    static let shared = StallWatch()

    private let queue = DispatchQueue(label: "LanAgent.stall-watch", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var lastMain = 0.0
    private var lastBeat = 0.0
    private var stuckSince: Double?
    private var stuckDoing = ""
    private var label = ""

    /// What the main thread is known to be busy with.
    static var doing: String {
        get { shared.lock.lock(); defer { shared.lock.unlock() }; return shared.label }
        set { shared.lock.lock(); shared.label = newValue; shared.lock.unlock() }
    }

    /// Heat and memory, the two things iOS slows an app down for.
    static var snapshot: String {
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return "thermal \(thermal), \(os_proc_available_memory() / 1_048_576) MB free"
    }

    /// From the main thread's clock; a second call does nothing.
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 1, repeating: 1)
            source.setEventHandler { [weak self] in self?.beat() }
            source.resume()
            timer = source
        }
    }

    private func beat() {
        let t = ProcessInfo.processInfo.systemUptime
        if lastBeat > 0, t - lastBeat > Self.frozenAfter {
            DebugLog.write(String(format: "stall: the whole app was held for %.0f s (this thread stopped too); %@", t - lastBeat, Self.snapshot))
        }
        lastBeat = t
        lock.lock(); let main = lastMain; lock.unlock()
        let verdict = Self.verdict(now: t, lastMain: main, stuckSince: stuckSince)
        switch verdict {
        case .began:
            stuckSince = main
            stuckDoing = Self.doing
        case .ended(let seconds):
            DebugLog.write(String(format: "stall: the main thread was stuck for %.0f s (%@); %@", seconds,
                                  stuckDoing.isEmpty ? "doing nothing known" : stuckDoing, Self.snapshot))
            stuckSince = nil
        case .none:
            break
        }
        DispatchQueue.main.async { [self] in
            lock.lock(); lastMain = ProcessInfo.processInfo.systemUptime; lock.unlock()
        }
    }

    static let frozenAfter = 4.0
    static let stuckAfter = 3.0

    enum Verdict: Equatable { case none, began, ended(Double) }

    /// What a beat of this thread says about the main thread.
    static func verdict(now: Double, lastMain: Double, stuckSince: Double?) -> Verdict {
        guard lastMain > 0 else { return .none }
        let silent = now - lastMain > stuckAfter
        if silent { return stuckSince == nil ? .began : .none }
        if let stuckSince { return .ended(now - stuckSince) }
        return .none
    }
}
