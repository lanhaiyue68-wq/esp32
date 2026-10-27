import Foundation

/// A return must finish before the next conversation is read.
@MainActor final class WatchListReturn {
    var pending: String?

    enum View: Equatable {
        case list
        case chat(CGPoint)
        case unknown
    }

    enum Outcome { case arrived, deferred, failed }

    func attempt(phone: Gestures, screen: ScreenSource, canAct: () -> Bool,
                 inspect: ((Data, String) -> View)? = nil, fallback: () async -> Bool) async -> Outcome {
        guard pending != nil else { return .arrived }
        guard !Task.isCancelled, canAct() else { return .deferred }
        if await resume(phone: phone, screen: screen, canAct: canAct, inspect: inspect, fallback: fallback) { return .arrived }
        return Task.isCancelled || !canAct() ? .deferred : .failed
    }

    static func view(rows: [[CandidatePicker.Piece]], chat: String) -> View {
        let titles = ["微信", "WeChat", "Chats", "聊天"]
        let footer = rows.flatMap { $0 }.filter { $0.box.midY > 0.85 }
        let tabs = [["微信", "WeChat", "Chats", "聊天"], ["通讯录", "通訊錄", "Contacts"],
                    ["发现", "發現", "Discover"], ["我", "Me"]]
        let found = tabs.enumerated().filter { index, labels in
            let center = (Double(index) + 0.5) / 4
            return footer.contains { piece in
                abs(piece.box.midX - center) <= 0.10 && labels.contains(piece.text.filter { !$0.isWhitespace })
            }
        }.count
        // Independent title + tab layout evidence; tolerate one unreadable label, never a bag of words in a message.
        if WatchReport.navigationChat(rows: rows, targets: titles) != nil,
           found >= 3 { return .list }

        let headers = rows.filter { WatchReport.navigationChat(rows: [$0], targets: [chat]) != nil }
        guard headers.count == 1 else { return .unknown }
        let title = headers[0].filter { (0.055...0.135).contains($0.box.midY) && (0.25...0.75).contains($0.box.midX) }
        guard !title.isEmpty else { return .unknown }
        // The native back chevron sits at the left of this verified conversation's navigation bar.
        return .chat(CGPoint(x: 0.06, y: title.map { $0.box.midY }.reduce(0, +) / Double(title.count)))
    }

    static func view(in frame: Data, chat: String) -> View {
        view(rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1), chat: chat)
    }

    func resume(phone: Gestures, screen: ScreenSource, canAct: () -> Bool,
                inspect: ((Data, String) -> View)? = nil,
                fallback: () async -> Bool) async -> Bool {
        guard let chat = pending else { return true }
        func allowed() -> Bool { !Task.isCancelled && canAct() && pending == chat }
        func look(after boundary: Double? = nil) async throws -> View {
            try Task.checkCancellation()
            try await screen.requireFrame(after: boundary)
            guard allowed(), let frame = screen.frame else { throw CancellationError() }
            return inspect?(frame, chat) ?? Self.view(in: frame, chat: chat)
        }
        guard allowed() else { return false }
        do {
            let current = try await look()
            if current == .list { pending = nil; return true }
            // A middle-edge back gesture avoids the screen-sharing indicator above the back chevron.
            // Wait for a fresh verified list before reading the next chat.
            var view = current
            for _ in 0..<2 {
                guard case .chat = view, allowed() else { break }
                try await phone.goBack()
                let ended = now()
                await screen.afterAction(since: ended)
                view = try await look(after: ended)
                if view == .list { pending = nil; return true }
                if view == .unknown {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    view = try await look()
                    if view == .list { pending = nil; return true }
                }
            }
            // One bounded navigation run, never another message read/send. A model's "done" alone is insufficient.
            guard allowed() else { return false }
            let began = now()
            guard await fallback(), allowed(), try await look(after: began) == .list else { return false }
            pending = nil
            return true
        } catch {
            DebugLog.write("watch: return to list not verified: \(error.localizedDescription)")
            return false
        }
    }
}
