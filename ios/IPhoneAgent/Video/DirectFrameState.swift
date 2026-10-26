import Foundation

/// Validity of whole-display pixels; independent of BLE/AirPlay clocks.
struct DirectFrameState {
    private(set) var generation: UUID?
    private(set) var fullDisplay = false
    private(set) var hasFrame = false
    private(set) var capturedAt = 0.0
    private(set) var confirmedAt = 0.0
    private(set) var sequence: UInt64 = 0

    mutating func begin(_ generation: UUID, fullDisplay: Bool) {
        self = DirectFrameState()
        self.generation = generation
        self.fullDisplay = fullDisplay
    }

    mutating func complete(_ generation: UUID, sequence: UInt64, capturedAt: Double, at: Double) -> Bool {
        guard accepts(generation, sequence), Self.fresh(capturedAt, at: at) else { return false }
        self.sequence = sequence
        self.capturedAt = capturedAt
        confirmedAt = capturedAt
        hasFrame = true
        return true
    }

    mutating func idle(_ generation: UUID, sequence: UInt64, confirmedAt: Double, at: Double) -> Bool {
        guard accepts(generation, sequence), hasFrame, confirmedAt >= self.confirmedAt,
              Self.fresh(confirmedAt, at: at) else { return false }
        self.sequence = sequence
        self.confirmedAt = confirmedAt
        return true
    }

    mutating func invalidate(_ generation: UUID, sequence: UInt64) {
        guard self.generation == generation, sequence > self.sequence else { return }
        self.sequence = sequence
        hasFrame = false
    }

    mutating func stop() { self = DirectFrameState() }

    func usable(at: Double, after: Double? = nil) -> Bool {
        guard fullDisplay, generation != nil, hasFrame, Self.fresh(confirmedAt, at: at) else { return false }
        return after.map { $0.isFinite && confirmedAt >= $0 } ?? true
    }

    private func accepts(_ id: UUID, _ sequence: UInt64) -> Bool {
        generation == id && fullDisplay && sequence > self.sequence
    }

    private static func fresh(_ timestamp: Double, at: Double) -> Bool {
        timestamp.isFinite && at.isFinite && timestamp > 0 && timestamp <= at + 0.05 && at - timestamp <= 2
    }
}
