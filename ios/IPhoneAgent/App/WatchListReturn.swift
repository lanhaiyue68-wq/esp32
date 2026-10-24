import Foundation

/// A return must finish before the next conversation is read.
@MainActor final class WatchListReturn {
    var pending: String?

    enum View: Equatable {
        case list
        case chat(CGPoint)
        case unknown
    }

    static func view(rows: [[CandidatePicker.Piece]], chat: String) -> View {
        let titles = ["微信", "WeChat", "Chats", "聊天"]
        let footer = Set(rows.flatMap { $0 }.filter { $0.box.midY > 0.85 }.map { $0.text.filter { !$0.isWhitespace } })
        let tabs = [["微信", "WeChat", "Chats", "聊天"], ["通讯录", "通訊錄", "Contacts"],
                    ["发现", "發現", "Discover"], ["我", "Me"]]
        if WatchReport.navigationChat(rows: rows, targets: titles) != nil,
           tabs.allSatisfy({ labels in labels.contains { footer.contains($0) } }) { return .list }

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
            if case .chat(let point) = current {
                guard allowed() else { return false }
                try await phone.tap(point.x, point.y, aim: true)
                let ended = now()
                await screen.afterAction(since: ended)
                if try await look(after: ended) == .list { pending = nil; return true }
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
