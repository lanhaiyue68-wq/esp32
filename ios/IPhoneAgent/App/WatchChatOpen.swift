import Foundation

/// Local navigation never reads messages or sends text. An uncertain screen stays with the existing navigator.
/// User 11-08/11-09: only a red mark on WeChat's chat list starts work: the unread number, or the small red dot of a
/// muted chat. The listed chats (the owner's account, the chats and groups set for this watch) come first and may get
/// replies and tasks; any other chat with a red mark is opened and read only. A chat already open, its mark gone, is
/// never resumed: the caller goes back to the list.
@MainActor enum WatchChatOpen {
    /// inChat: the screen is already inside a listed chat. opened: the caller decides read-only by the listed names.
    enum Outcome: Equatable { case opened(String), inChat(String), nothing, fallback, deferred, unverified }
    /// Read off the chat list: a listed chat to open, else another chat to read only (its list name, maybe cut with
    /// "…"), nothing with a red mark, or not sure (the model decides).
    enum Unread: Equatable { case row(String, CGPoint), other(String, CGPoint), none, unknown }

    /// List entries that are not conversations, or not anyone's messages (the model's scope leaves them out too).
    static let notChats: Set<String> = ["订阅号消息", "訂閱號消息", "订阅号", "訂閱號", "服务号", "服務號", "服务通知", "服務通知",
                                        "公众号", "公眾號", "文件传输助手", "文件傳輸助手", "微信团队", "微信團隊", "腾讯新闻", "騰訊新聞",
                                        "微信支付", "微信运动", "微信運動", "折叠的群聊", "折疊的群聊", "摺疊的群聊"]

    /// Every list row's title: a name with a smaller preview just below it, so a preview is never taken for a title.
    private static func listTitles(_ rows: [[CandidatePicker.Piece]]) -> [(text: String, box: CGRect)] {
        let body = rows.compactMap { row -> (text: String, box: CGRect)? in
            let pieces = row.filter { $0.box.minX >= 0.19 && $0.box.maxX <= 0.87 && (0.16...0.83).contains($0.box.midY) }
            guard !pieces.isEmpty else { return nil }
            return (pieces.map(\.text).joined().filter { !$0.isWhitespace }, pieces.reduce(CGRect.null) { $0.union($1.box) })
        }
        return body.filter { match in
            !match.text.isEmpty && body.contains(where: { preview in
                (0.018...0.050).contains(preview.box.midY - match.box.midY) &&
                abs(preview.box.minX - match.box.minX) <= 0.06 &&
                preview.box.height >= 0.006 && preview.box.height < match.box.height * 0.92
            })
        }
    }

    /// List rows whose title is exactly `target` (no whitespace).
    private static func titles(_ rows: [[CandidatePicker.Piece]], _ target: String) -> [CGRect] {
        listTitles(rows).filter { $0.text == target }.map(\.box)
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

    /// The topmost listed chat whose avatar carries a red mark, picked on the list itself instead of by an agent run
    /// (logs26: 6–35 s). With none, the topmost other chat with one, to read only. `badge` tells whether the avatar
    /// next to a title box is marked. A duplicate listed name (logs26 had two 蓝海乐) or a truncated one leaves the
    /// choice to the model. A listed chat out of view is not unread: WeChat moves a chat with a new message to the top
    /// (logs 11-06: the model, guessing, opened 主人蓝海乐 four checks in a row with nothing new).
    static func unread(rows: [[CandidatePicker.Piece]], rules: WatchSettings.Rules, badge: (CGRect) -> Bool) -> Unread {
        guard !rules.targets.isEmpty, WatchListReturn.view(rows: rows, chat: "") == .list else { return .unknown }
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
        let listed = Set(rules.targets.map { $0.filter { !$0.isWhitespace } })
        let others = listTitles(rows).filter { !listed.contains($0.text) && !notChats.contains($0.text) && badge($0.box) }
        if let top = others.min(by: { $0.box.midY < $1.box.midY }) { return .other(top.text, CGPoint(x: 0.5, y: top.box.midY)) }
        return .none
    }

    /// Where the red mark sits: on the top-right corner of the avatar, left of the title.
    static func badgeArea(_ title: CGRect) -> CGRect {
        CGRect(x: title.minX - 0.075, y: title.midY - 0.04, width: 0.065, height: 0.04)
    }

    /// Red share that counts as a mark. A muted chat's dot (~9 pt) is 4–9 % of the area on a 1280-high frame, less
    /// after JPEG softens its edge; a number badge is 15 % or more.
    static let badgeShare = 0.02

    static func unread(in frame: Data, rules: WatchSettings.Rules) -> Unread {
        guard let image = Vision.image(frame) else { return .unknown }
        return unread(rows: CandidatePicker.rows(in: frame, top: 0.055, bottom: 1), rules: rules,
                      badge: { Vision.redShare(image, in: badgeArea($0)) >= badgeShare })
    }

    /// The list name (maybe cut short with "…") belongs to the chat titled `title`.
    static func sameChat(_ title: String, listName: String) -> Bool {
        let t = title.filter { !$0.isWhitespace }, n = listName.filter { !$0.isWhitespace }
        guard !t.isEmpty, !n.isEmpty else { return false }
        if t == n { return true }
        let cut = n.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
        return cut != n && cut.count >= 2 && t.hasPrefix(cut)
    }

    /// One tap on the marked row of the list, verified by the destination's title on a fresh frame. Already in a
    /// listed chat: inChat, and the caller goes back to the list first (or reads it, if this watch just opened it).
    /// `title`: the listed chat on screen; `anyTitle`: any chat's title on screen (never the list's).
    static func open(phone: Gestures, screen: ScreenSource, rules: WatchSettings.Rules, canAct: () -> Bool,
                     inspectList: ((Data) -> Unread)? = nil, title: ((Data) -> String?)? = nil,
                     anyTitle: ((Data) -> String?)? = nil) async -> Outcome {
        guard !rules.targets.isEmpty else { return .fallback }
        let title = title ?? { WatchReport.navigationChat(in: $0, targets: rules.targets) }
        let anyTitle = anyTitle ?? { WatchReport.navigationTitle(in: $0) }
        func allowed() -> Bool { !Task.isCancelled && canAct() }
        guard allowed() else { return .deferred }
        var tapped = false
        do {
            try await screen.requireFrame(after: nil)
            guard allowed() else { return .deferred }
            guard let frame = screen.frame else { return .fallback }
            if let chat = title(frame) { return .inChat(chat) }
            let point: CGPoint, landed: (Data) -> String?
            switch inspectList?(frame) ?? unread(in: frame, rules: rules) {
            case .none: return .nothing
            case .unknown: return .fallback
            case .row(let chat, let p):
                point = p
                landed = { title($0) == chat ? chat : nil }
            case .other(let name, let p):
                point = p
                landed = { anyTitle($0).flatMap { sameChat($0, listName: name) ? $0 : nil } }
            }
            tapped = true
            try await phone.tap(point.x, point.y, aim: false)  // firmware v33 lands plain taps; aiming jiggled ~3 s
            let ended = now()
            await screen.afterAction(since: ended)
            guard allowed() else { return .deferred }
            try await screen.requireFrame(after: ended)
            guard allowed(), let after = screen.frame else { return .deferred }
            if let chat = landed(after) { return .opened(chat) }
            // logs27: the title was not up yet on the first frame after the tap. build 64: two looks within ~1 s
            // still missed it, and the next check came 20 s later already in the chat. Up to three more, 0.6 s apart.
            for _ in 0..<3 {
                await screen.afterAction(since: now())
                guard allowed(), let later = screen.frame else { return .deferred }
                if let chat = landed(later) { return .opened(chat) }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            return .unverified
        } catch {
            if !allowed() { return .deferred }
            return tapped ? .unverified : .fallback
        }
    }
}
