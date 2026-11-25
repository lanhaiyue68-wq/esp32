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
    /// 180: what each side showed that is no chat of WeChat or WeCom (logged once, left alone).
    var notChat: [Int: String] = [:]
    /// 181: what 小藍 sent lately, to know the owner's other account when its line shows up on the other side.
    var sent: [XiaoLanSelf.Sent] = []
    /// 181: the windows whose app could not be told, logged once each.
    var untold: Set<String> = []
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
            let looks = await paneLooks()
            paneTell(looks, &state)
            for look in looks {
                guard watching, !Task.isCancelled else { break }
                await paneHandle(look, &state)
            }
            // 182 (user 11-26: "速度太慢了…跟安卓機比差遠了"): a shorter rest between passes (was 0.7 s).
            try? await Task.sleep(nanoseconds: 350_000_000)
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

    /// Every window on the screen now, read. 182 (user 11-26: "速度太慢了"): `side` reads that window only (each
    /// window's words cost a text recognition; a check after a tap needs only the window tapped).
    func paneLooks(after since: Double? = nil, side only: Int? = nil) async -> [PaneLook] {
        if let since { await feed.afterAction(since: since) }
        guard let frame = feed.frame, let px = WatchOCR.Pixels(frame) else { return [] }
        let rects = XiaoLanPanes.windows(px)
        var looks: [PaneLook] = []
        for (i, r) in rects.enumerated() {
            if let only, only != (rects.count == 1 ? 2 : i) { continue }
            guard let crop = XiaoLanPanes.crop(frame, r) else { continue }
            let rows = await CandidatePicker.rowsOffMain(in: crop, top: 0, bottom: 1)
            var view = XiaoLanPanes.view(rows)
            // 181: a list whose words were not read (title nor tab bar) is still told by its tab's colour, at any width.
            if view == .unknown, XiaoLanPanes.cancelButton(rows) == nil, let px = WatchOCR.Pixels(crop), XiaoLanPanes.tabApp(px) != nil {
                view = .list
            }
            looks.append(PaneLook(side: rects.count == 1 ? 2 : i, rect: r, crop: crop, rows: rows, view: view))
        }
        return looks
    }

    /// The same window again after a gesture, up to `tries` looks 0.5 s apart until `done` says so.
    /// 182: only that window is read, and the waits are shorter (0.3 + 0.2 s were 0.15 + 0.1 s): the wait for a new
    /// frame after the action is already in `paneLooks(after:)`.
    private func paneLook(_ side: Int, after since: Double, tries: Int = 4, until done: (PaneLook) -> Bool) async -> PaneLook? {
        var last: PaneLook?
        var t = since
        for _ in 0..<tries {
            try? await Task.sleep(nanoseconds: 150_000_000)
            last = await paneLooks(after: t, side: side).first { $0.side == side }
            if let l = last, done(l) { return l }
            t = now()
            try? await Task.sleep(nanoseconds: 100_000_000)
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

    /// 181 (Echo 180, 11-25: after the owner changed the windows' widths WeChat's window was nobody's: nothing was sent
    /// there, its red marks were left): each window's app by its tab bar or list title; of two windows, one told and
    /// the other showing a WeChat/WeCom chat, that one is the other app. A window still untold is logged (and its screen
    /// kept in diagnostics) once.
    func paneTell(_ looks: [PaneLook], _ state: inout PaneWatchState) {
        let told: [XiaoLanOrders.App?] = looks.map { l in
            if let a = XiaoLanPanes.app(l.rows) { return a }
            if XiaoLanPanes.weworkBar(l.rows) { return .wework }  // 182: a WeCom chat, by its quick bar
            guard l.view == .list, let px = WatchOCR.Pixels(l.crop) else { return nil }
            return XiaoLanPanes.tabApp(px)  // 181: the chosen tab's colour, when no word was read
        }
        for (i, l) in looks.enumerated() {
            if let a = told[i] { state.apps[l.side] = a; continue }
            if looks.count == 2, let o = told[1 - i] ?? state.apps[looks[1 - i].side],
               state.apps[l.side] == nil || state.apps[l.side] == o,
               let px = WatchOCR.Pixels(l.crop), XiaoLanPanes.chatBackground(px) {
                state.apps[l.side] = o == .wework ? .wechat : .wework
            }
            guard state.apps[l.side] == nil, state.untold.count < 20 else { continue }
            let note = String(format: "side %ld x %.3f-%.3f h %.3f", l.side, Double(l.rect.minX), Double(l.rect.maxX), Double(l.rect.height))
                + " title「\(XiaoLanPanes.titleLine(l.rows))」 bottom「\(XiaoLanPanes.bottomText(l.rows))」"
            if state.untold.insert(note).inserted {
                DebugLog.write("watch: a window's app not told: \(note)")
                if state.untold.count <= 3 { WatchChatOpen.keepFrame(feed.frame) }
            }
        }
    }

    /// 181: the window of `app` now, told as paneTell does.
    private func paneFind(_ app: XiaoLanOrders.App, _ state: inout PaneWatchState) async -> PaneLook? {
        let looks = await paneLooks()
        paneTell(looks, &state)
        return looks.first { state.apps[$0.side] == app }
    }

    /// 181: how many windows the screen shows (after `since`, and the animation of a window going away); -1 unknown.
    private func paneWindowCount(after since: Double? = nil) async -> Int {
        if let since {
            await feed.afterAction(since: since)
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        guard let frame = feed.frame, let px = WatchOCR.Pixels(frame) else { return -1 }
        return XiaoLanPanes.windows(px).count
    }

    /// 181 (Echo 180, 11-25: the left window's back arrow was clicked with the pointer unseen, then again in place, and
    /// the second click hit the window's close: WeChat was gone. User: "你為什么要把它點叉掉呢…記住你這個錯誤"): the
    /// pointer is first found on the chat below the arrow, then hops the short way up and clicks; not seen there, nothing
    /// is clicked by the window's top. A window gone after the click stops the watch: the owner brings it back by its
    /// Dock icon.
    /// 182 (Echo 181, 11-26: half the backs failed, "pointer not seen below the arrow", and a window stayed in a chat for
    /// minutes, its list and red marks unseen): not seen at either spot, the kept position is forgotten (the next move
    /// finds the arrow first, ~1.7 s) and the two spots are tried once more. Still nothing is clicked unseen.
    private func paneBack(_ look: PaneLook, _ who: String, refound: Bool = false) async -> Bool {
        let arrow = XiaoLanPanes.onScreen(XiaoLanPanes.back, in: look.rect)
        for stage in XiaoLanPanes.backStages {
            let s = XiaoLanPanes.onScreen(stage, in: look.rect)
            do { try await pointer.point(Double(s.x), Double(s.y), aim: true, rehome: false) } catch {
                DebugLog.write("watch: \(who): back: pointer not placed below the arrow: \(error.localizedDescription)")
                continue
            }
            guard pointer.aimSaw else { continue }
            let windows = await paneWindowCount()
            let t = now()
            do { try await pointer.clickBy(Double(arrow.x - s.x), Double(arrow.y - s.y)) } catch {
                DebugLog.write("watch: \(who): back: the click failed: \(error.localizedDescription)")
                return false
            }
            DebugLog.write("watch: \(who): back: pointer seen at "
                + String(format: "(%.3f, %.3f), then up to the arrow (%.3f, %.3f)", Double(s.x), Double(s.y), Double(arrow.x), Double(arrow.y)))
            if windows == 2, await paneWindowCount(after: t) == 1 {
                DebugLog.write("watch: a window is gone after the back arrow; watch stopped")
                stopWatch("有一个窗口不见了：请点 Dock 上它的图标叫回来，再开守候")
                return false
            }
            return true
        }
        if !refound {
            DebugLog.write("watch: \(who): back: pointer not seen below the arrow; finding it first, then once more")
            pointer.forgetPosition()
            return await paneBack(look, who, refound: true)
        }
        DebugLog.write("watch: \(who): back: pointer not seen below the arrow; nothing clicked by the window's top")
        return false
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
            // 180 (Echo 178, 11-25): a chat of WeChat or WeCom has their grey background; the Settings app's 键盘 page
            // was taken for a chat and its back arrow tapped. Any other window is left alone.
            // 182: WeCom's quick bar tells its chats too (11-26: WeCom in 企微测试群 was left alone for minutes).
            guard let px = WatchOCR.Pixels(look.crop), XiaoLanPanes.chatBackground(px) || XiaoLanPanes.weworkBar(look.rows) else {
                if state.notChat[look.side] != title {
                    state.notChat[look.side] = title
                    DebugLog.write("watch: a window shows \(title), no chat of WeChat or WeCom; left alone")
                }
                return
            }
            state.notChat[look.side] = nil
            // 180: the app told by the chat itself (WeCom's quick bar), not by going back to its list (the back arrow of
            // the left window sits by the screen's top-left corner).
            if state.apps[look.side] == nil { state.apps[look.side] = XiaoLanPanes.chatApp(look.rows) }
            guard let app = state.apps[look.side] else { return }
            if paneRead(app, look, title: title, fromMark: false, &state) > 0 || state.quietSince[look.side] == nil {
                state.quietSince[look.side] = now()
            }
            // The engines watch the whole list: a chat that stays quiet is left for the list (its red marks). 182 (user
            // 11-26: "速度太慢了"): 5 s, was 8 s (other chats' messages waited that long first).
            if let quiet = state.quietSince[look.side], now() - quiet > 5 {
                DebugLog.write("watch: \(app.rawValue): \(title) quiet; back to the list")
                _ = await paneBack(look, app.rawValue)
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
        guard let read = WatchOCR.screen(look.crop, title: title, rows: look.rows) else { return 0 }  // 182: read once
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
        // 181 (user 11-25: "兩個號在一個群里…就相當于是同一個人，就不用回復了"; "應該點開把那個紅點給點掉，而不是應該回復"):
        // the owner's own lines here are what this side's other account can see; a line on this side that is one of the
        // owner's on the other (sent by 小藍 or read there as mine) is from the owner's other account: opened, never
        // reported, and its sender learned.
        let t = now()
        state.sent.removeAll { t - $0.at > XiaoLanSelf.sentWindow }
        for line in fresh where line.mine { state.sent.append(XiaoLanSelf.Sent(app: app, chat: name, text: line.text, at: t)) }
        if state.sent.count > 60 { state.sent.removeFirst(state.sent.count - 60) }
        var own: [String] = []
        let others = fresh.filter { line in
            guard !line.mine else { return false }
            let owners = names + XiaoLanSelf.learned
            if XiaoLanSelf.sentByOther(line.text, chat: name, app: app, sent: state.sent, now: t) {
                if !line.sender.isEmpty && !XiaoLanSelf.isOwner(line.sender, names: owners) {
                    XiaoLanSelf.learn(XiaoLanPanes.listName(line.sender))
                    DebugLog.write("watch: \(app.rawValue): \(name): \(line.sender) said what the owner said on the other app: the owner's other account, learned")
                }
                own.append(line.sender)
                return false
            }
            if XiaoLanSelf.isOwner(line.sender, names: owners) { own.append(line.sender); return false }
            return true
        }
        if !own.isEmpty {
            DebugLog.write("watch: \(app.rawValue): \(name): \(own.count) line(s) from the owner's other account (\(Set(own).sorted().joined(separator: "、"))): opened, not reported")
        }
        let messages = others.map { line in
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
        guard var look = await paneFind(app, &state) else {
            return (false, "屏幕上没有\(appName)的窗口（请把微信和企业微信左右分屏）")
        }
        // 180: a list's title is no chat to send to (178 replied "into 微信", the WeChat list read as a chat).
        guard !XiaoLanPanes.listTitles.contains(WatchOCR.titled(chat).name) else { return (false, "「\(chat)」不是会话") }
        func isChat(_ l: PaneLook) -> Bool {
            if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: chat) }
            return false
        }
        if !isChat(look) {
            if case .chat = look.view {  // another chat: back to the list first
                guard await paneBack(look, app.rawValue) else { return (false, "\(appName)没有回到会话列表（返回键旁看不到鼠标，没有点）") }
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
        // 182 (Echo 181, 11-26): a chat left on its 按住 说话 bar is switched back to typing first; the switch puts the
        // field of this window in focus with the keyboard up, so it needs no second tap.
        var focused = false
        if let toggle = XiaoLanPanes.voiceToggle(look.rows) {
            DebugLog.write("watch: \(app.rawValue): \(chat) shows 按住 说话; switching to typing")
            guard await paneTap(toggle, in: look.rect, wide: 0.03),
                  let typing = await paneLook(look.side, after: now(), until: { XiaoLanPanes.voiceToggle($0.rows) == nil }),
                  XiaoLanPanes.voiceToggle(typing.rows) == nil else {
                return (false, "\(appName)的「\(chat)」停在「按住 说话」，没切回打字")
            }
            look = typing
            focused = true
        }
        // The input field: the white box at the bottom of the window (WeCom's row of buttons above it is left alone).
        // 180 (Echo 178, 11-25): always tapped, keyboard up or not. The keyboard is the whole screen's: up from a send in
        // WeCom, a reply meant for WeChat was typed into WeCom's field and went out there, as the WeCom account.
        if !focused {
            guard let px = WatchOCR.Pixels(look.crop), let field = XiaoLanPanes.inputField(px) else {
                return (false, "\(appName)里没找到输入框")
            }
            guard await paneTap(field, in: look.rect, wide: 0.15) else { return (false, ChatToolLink.reasonNotSent) }
        }
        try? await Task.sleep(nanoseconds: 250_000_000)  // 182: was 0.4 s
        do {
            try await pointer.key("cmd+a")
            try await pointer.key("backspace")
        } catch {
            DebugLog.write("watch: clearing the input field failed: \(error.localizedDescription)")
        }
        guard await typeWithLanAgentKeyboard(text, enter: false) else {
            return (false, "小蓝输入法没有打出字（请在\(appName)里把键盘切成小蓝）")
        }
        try? await Task.sleep(nanoseconds: 200_000_000)  // 182: was 0.4 s
        let returned = await keyboardBridge.type("", enter: true, within: 4)
        DebugLog.write("watch: \(app.rawValue): typed into \(chat); the keyboard's return \(returned ? "pressed" : "not confirmed")")
        // Sent when my newest line now shows the text (182: read from the words already read for the check).
        let head = String(text.filter { !$0.isWhitespace }.prefix(6))
        func sentShown(_ l: PaneLook) -> WatchReport.Screen? {
            guard case .chat(let t) = l.view, let r = WatchOCR.screen(l.crop, title: t, rows: l.rows, banner: false),
                  r.lines.last(where: \.mine).map({ $0.text.filter { !$0.isWhitespace }.contains(head) }) == true else { return nil }
            return r
        }
        let after = await paneLook(look.side, after: now(), tries: 3) { sentShown($0) != nil }
        // 180 (Echo 178, 11-25): the keyboard left up covered the windows' tab bars and the list was read as a chat.
        // 182 (user 11-26: "點聊天空白處收鍵盤"; Esc left 小藍's keyboard up): a tap on bare chat background puts it down.
        if let a = after { await paneDismissKeyboard(a) }
        if let a = after, let r = sentShown(a) {
            let key = "\(app.rawValue)|\(r.title)"
            state.history[key] = WatchReport.remember([], screen: r.lines, history: nil)
            state.sent.append(XiaoLanSelf.Sent(app: app, chat: chat, text: text, at: now()))  // 181
            return (true, "")
        }
        return (false, ChatToolLink.reasonNotSent)
    }

    /// 182: the keyboard down by a tap on the chat's bare background above the input bar (nothing there to open or play).
    private func paneDismissKeyboard(_ l: PaneLook) async {
        guard case .chat = l.view, let px = WatchOCR.Pixels(l.crop) else { return }
        let bar = px.inputTop(from: 0.3) ?? 0.85
        guard let spot = XiaoLanPanes.blankSpot(px, above: bar) else {
            DebugLog.write("watch: no bare chat background to tap; the keyboard left up")
            return
        }
        _ = await paneTap(spot, in: l.rect, wide: 0.1)
    }

    /// 174 (user 11-25): delete `chat` from its app's chat list in its window: the row's buttons brought out (WeChat by a
    /// drag, WeCom by a sideways scroll), the red 删除, a confirmation's 删除 when one comes, then the row is gone.
    private func paneDelete(_ chat: String, app: XiaoLanOrders.App, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let appName = app == .wework ? "企业微信" : "微信"
        guard var look = await paneFind(app, &state) else { return (false, "屏幕上没有\(appName)的窗口（请把微信和企业微信左右分屏）") }
        if case .chat = look.view {  // in a chat: back to the list first
            guard await paneBack(look, app.rawValue) else { return (false, "\(appName)没有回到会话列表（返回键旁看不到鼠标，没有点）") }
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
        // 182: the pointer is seen on the row before the drag; not seen, it is found first and tried once more.
        for attempt in 0..<2 {
            do {
                try await pointer.revealRowActions(Double(start.x), Double(start.y), room: Double(start.x - look.rect.minX) - 0.03,
                                                   scroll: app == .wework)
                break
            } catch {
                if attempt == 0 {
                    DebugLog.write("watch: \(app.rawValue): delete \(chat): \(error.localizedDescription); finding the pointer, once more")
                    pointer.forgetPosition()
                    continue
                }
                return (false, "\(appName)里滑不出「\(chat)」的按钮：\(error.localizedDescription)")
            }
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
