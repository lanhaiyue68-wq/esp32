import Foundation

/// The app-switching boundary of a paste. A paste is allowed only after the original screen is restored.
@MainActor enum PasteRoundTrip {
    static func perform(_ text: String, isActive: () -> Bool,
                        previousApp: () async throws -> Void, nextApp: () async throws -> Void,
                        waitForAgent: () async -> Bool, put: (String) -> Bool,
                        verifySource: () async -> Bool) async -> PasteHopResult {
        .lost
    }

    static func matchesSource(_ before: Data, _ after: Data) -> Bool { false }
}
