#if XIAOLAN
import UIKit

/// 172: 小藍's watch on an iPad: WeChat and WeCom side by side, both looked at on every pass (XiaoLanPanes), no model,
/// as 智微兔 and 智企微行 work (docs/xiaolan-engine-logic.md): a red mark on a chat list opens that chat; its new messages
/// are read on the device and reported to that app's server (type 101 and the QA callback); the server's replies and
/// orders come back as commands and are typed in that app's window; then back to the list.
struct PaneWatchState {
    /// Which app each side holds (0 left, 1 right, 2 the whole screen), from its tab bar when last on a list.
    var apps: [Int: XiaoLanOrders.App] = [:]
    /// What was read last in each chat ("wechat|测试群"), for what is new.
    var history: [String: [WatchReport.Line]] = [:]
    /// Since when each side has been in a chat with nothing new (back to the list after a while).
    var quietSince: [Int: Double] = [:]
    var frontSince: Double?, lastHop = -Double.infinity, hopped = false
}

extension AppModel {
    /// A window seen once: where it is, its picture and words, what it shows.
    struct PaneLook { var side: Int; var rect: CGRect; var crop: Data; var rows: [[CandidatePicker.Piece]]; var view: XiaoLanPanes.View }

    func paneWatchLoop() async {
        var state = PaneWatchState()
        var waitingLogged = false
        DebugLog.write("watch: 小藍 side by side: WeChat and WeCom both watched, either side, no model")
        while watching && !Task.isCancelled {
            if let order = chatTool.nextCommand() ?? weworkTool.nextCommand() {
                await paneOrder(order, &state)
                continue
            }
            guard board.connected, feed.watchable else {
                watchStatus = String(localized: "Waiting for the board and Screen Mirroring…")
                if !waitingLogged { waitingLogged = true; DebugLog.write("watch: waiting for the board and screen sharing") }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }
            waitingLogged = false
            if UIApplication.shared.applicationState == .active {
                await paneLeaveEcho(&state)
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }
            state.frontSince = nil
            watchStatus = "正在同时守候微信和企业微信…"
            for look in await paneLooks() {
                guard watching, !Task.isCancelled else { break }
                await paneHandle(look, &state)
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    /// Echo itself in front while watching (11-25: iOS asked about the local network as the watch started; or the
    /// owner looks at Echo): back to WeChat by its URL, at once the first time, then after 8 s in front.
    private func paneLeaveEcho(_ state: inout PaneWatchState) async {
        let t = now()
        if state.frontSince == nil { state.frontSince = t }
        guard let since = state.frontSince, t - since >= (state.hopped ? 8 : 1), t - state.lastHop >= 5 else { return }
        state.lastHop = t
        let opened = await hopToWeChat(seesWeChat: { false })
        DebugLog.write("watch: Echo in front while watching; WeChat opened by its URL: \(opened ? "yes" : "no")")
        if opened { (state.hopped, state.frontSince) = (true, nil) }
    }

    /// Every window on the screen now, read.
    func paneLooks(after since: Double? = nil) async -> [PaneLook] {
        if let since { await feed.afterAction(since: since) }
        guard let frame = feed.frame, let px = WatchOCR.Pixels(frame) else { return [] }
        let rects = XiaoLanPanes.windows(px)
        var looks: [PaneLook] = []
        for (i, r) in rects.enumerated() {
            guard let crop = XiaoLanPanes.crop(frame, r) else { continue }
            let rows = await CandidatePicker.rowsOffMain(in: crop, top: 0, bottom: 1)
            looks.append(PaneLook(side: rects.count == 1 ? 2 : i, rect: r, crop: crop, rows: rows, view: XiaoLanPanes.view(rows)))
        }
        return looks
    }

    /// The same window again after a gesture, up to `tries` looks 0.5 s apart until `done` says so.
    private func paneLook(_ side: Int, after since: Double, tries: Int = 4, until done: (PaneLook) -> Bool) async -> PaneLook? {
        var last: PaneLook?
        var t = since
        for _ in 0..<tries {
            try? await Task.sleep(nanoseconds: 300_000_000)
            last = await paneLooks(after: t).first { $0.side == side }
            if let l = last, done(l) { return l }
            t = now()
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return last
    }

    private func paneTap(_ p: CGPoint, in r: CGRect, wide: Double = 0.3) async -> Bool {
        let s = XiaoLanPanes.onScreen(p, in: r)
        pointer.aimLoosely(wide * Double(r.width), 0.015)
        do { try await pointer.tap(s.x, s.y, aim: false); return true } catch {
            DebugLog.write("watch: tap at (\(String(format: "%.3f, %.3f", s.x, s.y))) failed: \(error.localizedDescription)")
            return false
        }
    }

    private func paneHandle(_ look: PaneLook, _ state: inout PaneWatchState) async {
        if let app = XiaoLanPanes.app(look.rows) { state.apps[look.side] = app }
        switch look.view {
        case .list:
            state.quietSince[look.side] = nil
            guard let app = state.apps[look.side], let image = UIImage(data: look.crop)?.cgImage else { return }
            guard let hit = XiaoLanPanes.marked(look.rows, red: { Vision.redShare(image, in: $0) }).first else { return }
            DebugLog.write("watch: \(app.rawValue): red mark on \(hit.name); opening it")
            guard await paneTap(hit.at, in: look.rect) else { return }
            let opened = await paneLook(look.side, after: now()) { l in
                if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: hit.name) }
                return false
            }
            guard let chat = opened, case .chat(let title) = chat.view,
                  WatchChatOpen.sameChat(WatchOCR.titled(title).name, listName: hit.name) else {
                DebugLog.write("watch: \(app.rawValue): \(hit.name) did not open (title not seen)")
                return
            }
            paneRead(app, chat, title: title, fromMark: true, &state)
            state.quietSince[look.side] = now()
        case .chat(let title):
            guard let app = state.apps[look.side] else {
                // Not seen on its list yet (the watch started inside a chat): back to the list to tell the app.
                DebugLog.write("watch: a window opens on a chat (\(title)) before its app is known; back to its list")
                _ = await paneTap(XiaoLanPanes.back, in: look.rect, wide: 0.02)
                return
            }
            if paneRead(app, look, title: title, fromMark: false, &state) > 0 || state.quietSince[look.side] == nil {
                state.quietSince[look.side] = now()
            }
            // The engines watch the whole list: a chat that stays quiet 8 s is left for the list (its red marks).
            if let quiet = state.quietSince[look.side], now() - quiet > 8 {
                DebugLog.write("watch: \(app.rawValue): \(title) quiet; back to the list")
                _ = await paneTap(XiaoLanPanes.back, in: look.rect, wide: 0.02)
                state.quietSince[look.side] = nil
            }
        case .unknown:
            // A search left open (a chat found by search, then back): 取消, back to the list.
            if let cancel = XiaoLanPanes.cancelButton(look.rows) {
                DebugLog.write("watch: a window is on a search page; 取消 back to its list")
                _ = await paneTap(cancel, in: look.rect, wide: 0.03)
            }
        }
    }

    /// 173 (user 11-25: "這不是兩邊都有嗎"): a chat not in view on the list: its search box, the name typed with 小藍's
    /// keyboard, the result row with that name. Nil (and the search closed) when it is not found.
    private func paneSearch(_ chat: String, _ look: PaneLook) async -> CGPoint? {
        let box = XiaoLanPanes.searchBox(look.rows) ?? CGPoint(x: 0.5, y: 0.11)
        DebugLog.write("watch: \(chat) is not in view on the list; searching for it")
        guard await paneTap(box, in: look.rect) else { return nil }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard await typeWithLanAgentKeyboard(chat, enter: false) else {
            DebugLog.write("watch: search: 小藍's keyboard did not type the name")
            await paneCloseSearch(look.side)
            return nil
        }
        let found = await paneLook(look.side, after: now(), tries: 5) { XiaoLanPanes.searchResult(chat, $0.rows) != nil }
        if let f = found, let row = XiaoLanPanes.searchResult(chat, f.rows) { return row }
        DebugLog.write("watch: search: \(chat) is not among the results")
        await paneCloseSearch(look.side)
        return nil
    }

    private func paneCloseSearch(_ side: Int) async {
        guard let l = await paneLooks().first(where: { $0.side == side }) else { return }
        if let cancel = XiaoLanPanes.cancelButton(l.rows) { _ = await paneTap(cancel, in: l.rect, wide: 0.03) }
    }

    /// The new messages of the chat in a window, reported to that app's server. Returns how many were new.
    @discardableResult
    private func paneRead(_ app: XiaoLanOrders.App, _ look: PaneLook, title: String, fromMark: Bool,
                          _ state: inout PaneWatchState) -> Int {
        guard let read = WatchOCR.screen(look.crop, title: title) else { return 0 }
        let name = read.title
        let lines = read.lines.map { WatchReport.Line(sender: XiaoLanPanes.listName($0.sender), text: $0.text, mine: $0.mine) }
        let key = "\(app.rawValue)|\(name)"
        let before = state.history[key]
        var fresh = WatchReport.new(lines, history: before)
        if before == nil && fromMark {
            // Opened for its red mark the first time: what came after my last line (at most 5) is the unread.
            let start = (lines.lastIndex { $0.mine }).map { $0 + 1 } ?? 0
            fresh = Array(lines[min(start, lines.count)...].suffix(5))
        }
        state.history[key] = WatchReport.remember(fresh, screen: lines, history: before)
        let names = WatchSettings.myNames
        let messages = fresh.filter { !$0.mine }.map { line in
            ReadMessage(chat: name, group: read.group, sender: line.sender, text: line.text,
                        atMe: names.contains { line.text.contains("@" + $0) })
        }
        if before == nil && !fromMark { DebugLog.write("watch: \(app.rawValue): \(name): history starts here (\(lines.count) line(s))") }
        guard !messages.isEmpty else { return 0 }
        ReadLog.append(messages)
        watchRead += messages.count
        (app == .wework ? weworkTool : chatTool).report(messages)
        DebugLog.write("watch: \(app.rawValue): \(name): \(messages.count) new message(s) reported")
        return messages.count
    }

    /// A server order. Sending a message is done in its app's window; anything else goes the usual way (runOrder).
    private func paneOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async {
        let link = order.app == .wework ? weworkTool : chatTool
        if order.type == ChatToolLink.deleteChat {  // 174
            watchStatus = "删除会话 \(order.chat)…"
            let done = await paneDelete(order.chat, app: order.app, &state)
            link.finish(order, ok: done.ok, reason: done.why)
            return
        }
        guard order.type == ChatToolLink.sendMessage else { await runOrder(order); return }
        if let why = PrivacyGuard.check(order.text, words: WatchSettings.privateWords, numbers: WatchSettings.blockNumbers) {
            DebugLog.write("watch: order withheld: \(why)")
            link.finish(order, ok: false, reason: ChatToolLink.reasonPrivacy)
            return
        }
        watchStatus = "发送到 \(order.chat)…"
        let sent = await paneSend(order.text, to: order.chat, app: order.app, &state)
        link.finish(order, ok: sent.ok, reason: sent.ok ? (order.at.isEmpty ? "" : ChatToolLink.reasonNoAt) : sent.why)
    }

    /// Open `chat` in its app's window (already open, or a row on its list), type `text` and send it.
    private func paneSend(_ text: String, to chat: String, app: XiaoLanOrders.App,
                          _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let appName = app == .wework ? "企业微信" : "微信"
        let sides = state.apps
        var found: PaneLook?
        for l in await paneLooks() {
            if let a = XiaoLanPanes.app(l.rows) { state.apps[l.side] = a }
            if found == nil, (state.apps[l.side] ?? sides[l.side]) == app { found = l }
        }
        guard var look = found else {
            return (false, "屏幕上没有\(appName)的窗口（请把微信和企业微信左右分屏）")
        }
        func isChat(_ l: PaneLook) -> Bool {
            if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: chat) }
            return false
        }
        if !isChat(look) {
            if case .chat = look.view {  // another chat: back to the list first
                _ = await paneTap(XiaoLanPanes.back, in: look.rect, wide: 0.02)
                guard let back = await paneLook(look.side, after: now(), until: { $0.view == .list }) else {
                    return (false, "\(appName)没有回到会话列表")
                }
                look = back
            }
            guard look.view == .list else { return (false, "\(appName)没有回到会话列表") }
            var target = XiaoLanPanes.entries(look.rows).first { WatchChatOpen.sameChat(chat, listName: $0.name) }
                .map { CGPoint(x: 0.5, y: $0.box.midY) }
            if target == nil { target = await paneSearch(chat, look) }  // not in view: the list's search box
            guard let row = target else { return (false, "\(appName)里搜不到「\(chat)」") }
            guard await paneTap(row, in: look.rect),
                  let opened = await paneLook(look.side, after: now(), until: isChat), isChat(opened) else {
                return (false, "\(appName)里没有打开「\(chat)」")
            }
            look = opened
        }
        // The input field: the white box at the bottom of the window (WeCom's row of buttons above it is left alone).
        if !keyboardBridge.onScreen() {
            guard let px = WatchOCR.Pixels(look.crop), let field = XiaoLanPanes.inputField(px) else {
                return (false, "\(appName)里没找到输入框")
            }
            guard await paneTap(field, in: look.rect, wide: 0.15) else { return (false, ChatToolLink.reasonNotSent) }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        do {
            try await pointer.key("cmd+a")
            try await pointer.key("backspace")
        } catch {
            DebugLog.write("watch: clearing the input field failed: \(error.localizedDescription)")
        }
        guard await typeWithLanAgentKeyboard(text, enter: false) else {
            return (false, "小蓝输入法没有打出字（请在\(appName)里把键盘切成小蓝）")
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        let returned = await keyboardBridge.type("", enter: true, within: 4)
        DebugLog.write("watch: \(app.rawValue): typed into \(chat); the keyboard's return \(returned ? "pressed" : "not confirmed")")
        // Sent when my newest line now shows the text.
        let head = String(text.filter { !$0.isWhitespace }.prefix(6))
        let after = await paneLook(look.side, after: now(), tries: 3) { l in
            guard case .chat(let t) = l.view, let r = WatchOCR.screen(l.crop, title: t) else { return false }
            return r.lines.last(where: \.mine).map { $0.text.filter { !$0.isWhitespace }.contains(head) } ?? false
        }
        if let a = after, case .chat(let t) = a.view, let r = WatchOCR.screen(a.crop, title: t),
           r.lines.last(where: \.mine).map({ $0.text.filter { !$0.isWhitespace }.contains(head) }) == true {
            let key = "\(app.rawValue)|\(r.title)"
            state.history[key] = WatchReport.remember([], screen: r.lines, history: nil)
            return (true, "")
        }
        return (false, ChatToolLink.reasonNotSent)
    }

    /// 174 (user 11-25): delete `chat` from its app's chat list in its window: the row's buttons brought out (WeChat by a
    /// drag, WeCom by a sideways scroll), the red 删除, a confirmation's 删除 when one comes, then the row is gone.
    private func paneDelete(_ chat: String, app: XiaoLanOrders.App, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let appName = app == .wework ? "企业微信" : "微信"
        let sides = state.apps
        var found: PaneLook?
        for l in await paneLooks() {
            if let a = XiaoLanPanes.app(l.rows) { state.apps[l.side] = a }
            if found == nil, (state.apps[l.side] ?? sides[l.side]) == app { found = l }
        }
        guard var look = found else { return (false, "屏幕上没有\(appName)的窗口（请把微信和企业微信左右分屏）") }
        if case .chat = look.view {  // in a chat: back to the list first
            _ = await paneTap(XiaoLanPanes.back, in: look.rect, wide: 0.02)
            guard let back = await paneLook(look.side, after: now(), until: { $0.view == .list }) else {
                return (false, "\(appName)没有回到会话列表")
            }
            look = back
        }
        guard look.view == .list else { return (false, "\(appName)没有回到会话列表") }
        guard let title = XiaoLanPanes.entries(look.rows).first(where: { WatchChatOpen.sameChat(chat, listName: $0.name) })?.box else {
            return (false, "\(appName)的会话列表上看不到「\(chat)」")
        }
        let start = XiaoLanPanes.onScreen(CGPoint(x: 0.75, y: title.midY), in: look.rect)
        do {
            try await pointer.revealRowActions(Double(start.x), Double(start.y), room: Double(start.x - look.rect.minX) - 0.03,
                                               scroll: app == .wework)
        } catch {
            return (false, "\(appName)里滑不出「\(chat)」的按钮：\(error.localizedDescription)")
        }
        func button(_ l: PaneLook) -> CGPoint? {
            guard let image = UIImage(data: l.crop)?.cgImage else { return nil }
            return XiaoLanPanes.deleteButton(l.rows, row: title, red: { Vision.redShare(image, in: $0) })
        }
        guard let shown = await paneLook(look.side, after: now(), until: { button($0) != nil }), let red = button(shown) else {
            return (false, "「\(chat)」那一行没有滑出红色的删除（系统账号、公众号可能没有）")
        }
        DebugLog.write("watch: \(app.rawValue): deleting \(chat)")
        guard await paneTap(red, in: look.rect, wide: 0.04) else { return (false, "没点到「\(chat)」的删除") }
        var after = await paneLook(look.side, after: now(), tries: 3) { XiaoLanPanes.gone(chat, $0.rows) }
        if let a = after, !XiaoLanPanes.gone(chat, a.rows), let confirm = XiaoLanPanes.confirmDelete(a.rows) {
            DebugLog.write("watch: \(app.rawValue): the confirmation (\(app == .wework ? "the alert's 删除" : "清空记录同时不显示聊天"))")
            _ = await paneTap(confirm, in: look.rect, wide: 0.04)
            after = await paneLook(look.side, after: now(), tries: 3) { XiaoLanPanes.gone(chat, $0.rows) }
        }
        guard let end = after, XiaoLanPanes.gone(chat, end.rows) else { return (false, "「\(chat)」还在\(appName)的会话列表上") }
        DebugLog.write("watch: \(app.rawValue): \(chat) deleted")
        return (true, "")
    }
}
#endif
