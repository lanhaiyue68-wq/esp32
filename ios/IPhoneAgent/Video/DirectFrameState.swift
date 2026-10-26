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
        false
    }

    mutating func idle(_ generation: UUID, sequence: UInt64, confirmedAt: Double, at: Double) -> Bool {
        false
    }

    mutating func invalidate(_ generation: UUID, sequence: UInt64) {
        guard self.generation == generation, sequence > self.sequence else { return }
        self.sequence = sequence
        hasFrame = false
    }

    mutating func stop() { self = DirectFrameState() }

    func usable(at: Double, after: Double? = nil) -> Bool { false }
}
