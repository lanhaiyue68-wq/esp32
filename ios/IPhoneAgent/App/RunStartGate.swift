import Foundation

@MainActor final class RunStartGate {
    private var generation = 0
    private(set) var cancelled = false
    func begin() -> Int { generation += 1; cancelled = false; return generation }
    func cancel() { generation += 1; cancelled = true }
    func check(_ ticket: Int) throws {
        try Task.checkCancellation()
        guard ticket == generation else { throw CancellationError() }
    }
}

struct WatchCheckGate {
    private(set) var checked = false
    mutating func beginCheck() { checked = true }
    func shouldPause(foreground: Bool) -> Bool { foreground && checked }
}
