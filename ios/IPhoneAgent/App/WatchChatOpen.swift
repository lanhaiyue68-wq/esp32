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

    /// Several listed chats ("only these chats"): the topmost listed chat whose avatar carries WeChat's red unread
    /// badge, picked on the list itself instead of by an agent run (logs26: 6–35 s). `badge` tells whether the avatar
    /// next to a title box is badged. "Nothing unread" only when every listed chat shows exactly once; a duplicate
    /// name (logs26 had two 蓝海乐), a truncated one or a chat out of view leaves the choice to the model.
    static func unread(rows: [[CandidatePicker.Piece]], rules: WatchSettings.Rules, badge: (CGRect) -> Bool) -> Unread {
        guard rules.onlyListed, rules.targets.count > 1, WatchListReturn.view(rows: rows, chat: "") == .list else { return .unknown }
        var hits: [(chat: String, box: CGRect)] = [], missing = false
        for chat in rules.targets {
            let name = chat.filter { !$0.isWhitespace }
            guard !name.isEmpty, !name.contains("…"), !name.contains("...") else { return .unknown }
            let found = titles(rows, name)
            if found.count > 1 { return .unknown }
            guard let box = found.first else { missing = true; continue }
            if badge(box) { hits.append((chat, box)) }
        }
        if let top = hits.min(by: { $0.box.midY < $1.box.midY }) { return .row(top.chat, CGPoint(x: 0.5, y: top.box.midY)) }
        return missing ? .unknown : .none
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
                try await phone.tap(point.x, point.y, aim: true)
                let ended = now()
                await screen.afterAction(since: ended)
                guard allowed() else { return .deferred }
                try await screen.requireFrame(after: ended)
                guard allowed(), let after = screen.frame else { return .deferred }
                return title(after) == chat ? .opened(chat) : .unverified
            }
        } catch {
            if !allowed() { return .deferred }
            return tapped ? .unverified : .fallback
        }
    }
}
