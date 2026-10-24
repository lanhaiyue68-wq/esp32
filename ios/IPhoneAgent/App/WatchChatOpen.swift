import Foundation

/// Local navigation never reads messages or sends text. An uncertain screen stays with the existing navigator.
@MainActor enum WatchChatOpen {
    enum View: Equatable { case chat(String), row(CGPoint), unknown }
    enum Outcome: Equatable { case opened(String), fallback, deferred, unverified }

    static func view(rows: [[CandidatePicker.Piece]], rules: WatchSettings.Rules) -> View { .unknown }

    static func view(in frame: Data, rules: WatchSettings.Rules) -> View {
        view(rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1), rules: rules)
    }

    static func open(phone: Gestures, screen: ScreenSource, rules: WatchSettings.Rules, canAct: () -> Bool,
                     inspect: ((Data) -> View)? = nil) async -> Outcome { .fallback }
}
