import Foundation

@MainActor final class RunStartGate {
    private var generation = 0
    func begin() -> Int { generation += 1; return generation }
    func cancel() {}
    func check(_ ticket: Int) throws { try Task.checkCancellation() }
}

struct WatchCheckGate {
    private(set) var checked = false
    mutating func beginCheck() { checked = true }
    func shouldPause(foreground: Bool) -> Bool { foreground }
}
