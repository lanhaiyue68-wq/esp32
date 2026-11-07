import Foundation

/// Local navigation never reads messages or sends text. An uncertain screen stays with the existing navigator.
@MainActor enum WatchChatOpen {
    enum View: Equatable { case chat(String), row(CGPoint), unknown }
    enum Outcome: Equatable { case opened(String), nothing, fallback, deferred, unverified }
    /// Several listed chats, read off the chat list: the one to open, nothing unread, or not sure (the model decides).
    enum Unread: Equatable { case row(String, CGPoint), none, unknown }

    static func view(rows: [[CandidatePicker.Piece]], rules: WatchSettings.Rules) -> View {
        guard rules.single else { return .unknown }
        let target = rules.targets[0].filter { !$0.isWhitespace }
        guard !target.isEmpty, !target.contains("…"), !target.contains("...") else { return .unknown }
        guard WatchListReturn.view(rows: rows, chat: "") == .list else {
            return WatchReport.navigationChat(rows: rows, targets: rules.targets).map(View.chat) ?? .unknown
        }
        let rows = titles(rows, target)
        guard rows.count == 1, let match = rows.first else { return .unknown }
        return .row(CGPoint(x: 0.5, y: match.midY))
    }

    /// List rows whose title is exactly `target` (no whitespace): one exact name with a smaller preview below it, so
    /// a preview mentioning the chat is not taken for its title.
    private static func titles(_ rows: [[CandidatePicker.Piece]], _ target: String) -> [CGRect] {
        let body = rows.compactMap { row -> (text: String, box: CGRect)? in
            let pieces = row.filter { $0.box.minX >= 0.19 && $0.box.maxX <= 0.87 && (0.16...0.83).contains($0.box.midY) }
            guard !pieces.isEmpty else { return nil }
            return (pieces.map(\.text).joined().filter { !$0.isWhitespace }, pieces.reduce(CGRect.null) { $0.union($1.box) })
        }
        return body.filter { match in
            match.text == target && body.contains(where: { preview in
                (0.018...0.050).contains(preview.box.midY - match.box.midY) &&
                abs(preview.box.minX - match.box.minX) <= 0.06 &&
                preview.box.height >= 0.006 && preview.box.height < match.box.height * 0.92
            })
        }.map(\.box)
    }

    /// The row of `chat` on the chat list: one exact title with its preview (the report's way back to the owner's
    /// chat). Nil off the list, for a name shown twice, or one not in view.
    static func row(of chat: String, rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        guard WatchListReturn.view(rows: rows, chat: "") == .list else { return nil }
        let name = chat.filter { !$0.isWhitespace }
        guard !name.isEmpty else { return nil }
        let found = titles(rows, name)
        return found.count == 1 ? CGPoint(x: 0.5, y: found[0].midY) : nil
    }

    static func row(of chat: String, in frame: Data) -> CGPoint? {
        row(of: chat, rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1))
    }

    /// Several listed chats ("only these chats"): the topmost listed chat whose avatar carries WeChat's red unread
    /// badge, picked on the list itself instead of by an agent run (logs26: 6–35 s). `badge` tells whether the avatar
    /// next to a title box is badged. A duplicate name (logs26 had two 蓝海乐) or a truncated one leaves the choice to
    /// the model. A listed chat out of view is not unread: WeChat moves a chat with a new message to the top, and the
    /// model, shown this same screen, only guessed — it opened 主人蓝海乐 four checks in a row with nothing new and once
    /// a group that is not listed, 2 model calls and 7–11 s a check, because 蓝海乐 was rarely in view (logs 11-06).
    static func unread(rows: [[CandidatePicker.Piece]], rules: WatchSettings.Rules, badge: (CGRect) -> Bool) -> Unread {
        guard rules.onlyListed, rules.targets.count > 1, WatchListReturn.view(rows: rows, chat: "") == .list else { return .unknown }
        var hits: [(chat: String, box: CGRect)] = []
        for chat in rules.targets {
            let name = chat.filter { !$0.isWhitespace }
            guard !name.isEmpty, !name.contains("…"), !name.contains("...") else { return .unknown }
            let found = titles(rows, name)
            if found.count > 1 { return .unknown }
            guard let box = found.first else { continue }
            if badge(box) { hits.append((chat, box)) }
        }
        if let top = hits.min(by: { $0.box.midY < $1.box.midY }) { return .row(top.chat, CGPoint(x: 0.5, y: top.box.midY)) }
        return .none
    }

    /// Where the unread badge sits: on the top-right corner of the avatar, left of the title.
    static func badgeArea(_ title: CGRect) -> CGRect {
        CGRect(x: title.minX - 0.075, y: title.midY - 0.04, width: 0.065, height: 0.04)
    }

    static func unread(in frame: Data, rules: WatchSettings.Rules) -> Unread {
        guard let image = Vision.image(frame) else { return .unknown }
        return unread(rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1), rules: rules,
                      badge: { Vision.redShare(image, in: badgeArea($0)) >= 0.04 })
    }

    static func view(in frame: Data, rules: WatchSettings.Rules) -> View {
        view(rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1), rules: rules)
    }

    static func open(phone: Gestures, screen: ScreenSource, rules: WatchSettings.Rules, canAct: () -> Bool,
                     inspect: ((Data) -> View)? = nil, inspectList: ((Data) -> Unread)? = nil,
                     title: ((Data) -> String?)? = nil) async -> Outcome {
        if !rules.single {
            return await openUnread(phone: phone, screen: screen, rules: rules, canAct: canAct, inspect: inspectList,
                                    title: title ?? { WatchReport.navigationChat(in: $0, targets: rules.targets) })
        }
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
                try await phone.tap(point.x, point.y, aim: false)  // firmware v33 lands plain taps; aiming jiggled ~3 s
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

    /// The multi-chat open: already in a listed chat (keep it, as the open task says), or one tap on the badged row of
    /// the list, verified by the destination's title on a fresh frame.
    private static func openUnread(phone: Gestures, screen: ScreenSource, rules: WatchSettings.Rules, canAct: () -> Bool,
                                   inspect: ((Data) -> Unread)?, title: (Data) -> String?) async -> Outcome {
        guard rules.onlyListed, rules.targets.count > 1 else { return .fallback }
        func allowed() -> Bool { !Task.isCancelled && canAct() }
        guard allowed() else { return .deferred }
        var tapped = false
        do {
            try await screen.requireFrame(after: nil)
            guard allowed() else { return .deferred }
            guard let frame = screen.frame else { return .fallback }
            if let chat = title(frame) { return .opened(chat) }
            switch inspect?(frame) ?? unread(in: frame, rules: rules) {
            case .none: return .nothing
            case .unknown: return .fallback
            case .row(let chat, let point):
                tapped = true
                try await phone.tap(point.x, point.y, aim: false)  // firmware v33 lands plain taps; aiming jiggled ~3 s
                let ended = now()
                await screen.afterAction(since: ended)
                guard allowed() else { return .deferred }
                try await screen.requireFrame(after: ended)
                guard allowed(), let after = screen.frame else { return .deferred }
                if title(after) == chat { return .opened(chat) }
                // logs27: the title was not up yet on the first frame after the tap. build 64: two looks within ~1 s
                // still missed it, and the next check came 20 s later already in the chat. Up to three more, 0.6 s apart.
                for _ in 0..<3 {
                    await screen.afterAction(since: now())
                    guard allowed(), let later = screen.frame else { return .deferred }
                    if title(later) == chat { return .opened(chat) }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
                return .unverified
            }
        } catch {
            if !allowed() { return .deferred }
            return tapped ? .unverified : .fallback
        }
    }
}
