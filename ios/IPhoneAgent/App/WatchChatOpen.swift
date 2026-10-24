import Foundation

/// Local navigation never reads messages or sends text. An uncertain screen stays with the existing navigator.
@MainActor enum WatchChatOpen {
    enum View: Equatable { case chat(String), row(CGPoint), unknown }
    enum Outcome: Equatable { case opened(String), fallback, deferred, unverified }

    static func view(rows: [[CandidatePicker.Piece]], rules: WatchSettings.Rules) -> View {
        guard rules.single else { return .unknown }
        let target = rules.targets[0].filter { !$0.isWhitespace }
        guard !target.isEmpty, !target.contains("…"), !target.contains("...") else { return .unknown }
        guard WatchListReturn.view(rows: rows, chat: "") == .list else {
            return WatchReport.navigationChat(rows: rows, targets: rules.targets).map(View.chat) ?? .unknown
        }
        // A preview mentioning the chat is not its title. Require one exact name and a smaller preview below it.
        let body = rows.compactMap { row -> (text: String, box: CGRect)? in
            let pieces = row.filter { $0.box.minX >= 0.19 && $0.box.maxX <= 0.87 && (0.16...0.83).contains($0.box.midY) }
            guard !pieces.isEmpty else { return nil }
            return (pieces.map(\.text).joined().filter { !$0.isWhitespace }, pieces.reduce(CGRect.null) { $0.union($1.box) })
        }
        let matches = body.filter { $0.text == target }
        guard matches.count == 1, let match = matches.first,
              body.contains(where: { preview in
                  (0.018...0.050).contains(preview.box.midY - match.box.midY) &&
                  abs(preview.box.minX - match.box.minX) <= 0.06 &&
                  preview.box.height >= 0.006 && preview.box.height < match.box.height * 0.92
              }) else { return .unknown }
        return .row(CGPoint(x: 0.5, y: match.box.midY))
    }

    static func view(in frame: Data, rules: WatchSettings.Rules) -> View {
        view(rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1), rules: rules)
    }

    static func open(phone: Gestures, screen: ScreenSource, rules: WatchSettings.Rules, canAct: () -> Bool,
                     inspect: ((Data) -> View)? = nil) async -> Outcome {
        guard rules.single else { return .fallback }
        func allowed() -> Bool { !Task.isCancelled && canAct() }
        guard allowed() else { return .deferred }
        var tapped = false
        func look() -> View {
            guard let frame = screen.frame else { return .unknown }
            return inspect?(frame) ?? view(in: frame, rules: rules)
        }
        do {
            try await screen.requireFrame(after: nil)
            guard allowed() else { return .deferred }
            switch look() {
            case .chat(let chat):
                return chat == rules.targets[0] ? .opened(chat) : .fallback
            case .row(let point):
                guard allowed() else { return .deferred }
                tapped = true
                try await phone.tap(point.x, point.y, aim: true)
                let ended = now()
                await screen.afterAction(since: ended)
                guard allowed() else { return .deferred }
                try await screen.requireFrame(after: ended)
                guard allowed() else { return .deferred }
                guard case .chat(let chat) = look(), chat == rules.targets[0] else { return .unverified }
                return .opened(chat)
            case .unknown: return .fallback
            }
        } catch {
            if !allowed() { return .deferred }
            return tapped ? .unverified : .fallback
        }
    }
}
