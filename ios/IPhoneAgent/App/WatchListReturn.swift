import Foundation

/// A return must finish before the next conversation is read.
@MainActor final class WatchListReturn {
    var pending: String?

    enum View: Equatable {
        case list
        case chat(CGPoint)
        case unknown
    }

    static func view(rows: [[CandidatePicker.Piece]], chat: String) -> View { .unknown }

    func resume(phone: Gestures, screen: ScreenSource, canAct: () -> Bool,
                inspect: (Data, String) -> View = { _, _ in .unknown },
                fallback: () async -> Bool) async -> Bool {
        guard pending != nil else { return true }
        // Extracted build49 behavior: one edge swipe, no result verification.
        try? await phone.goBack()
        pending = nil
        return true
    }
}
