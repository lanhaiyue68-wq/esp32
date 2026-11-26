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
    /// 183: the chats whose history came from an earlier launch (PaneHistory), not read since.
    var loaded: Set<String> = []
    /// 183: every line's words read in each chat since the launch (XiaoLanSelf.plain), for a screen that does not go on
    /// from the history (scrolled up).
    var seen: [String: Set<String>] = [:]
    /// 183: since when no window of WeChat or WeCom has been on the screen, and whether the owner was told.
    var noAppsSince: Double?, noAppsTold = false
}

extension AppModel {
    /// A window seen once: where it is, its picture and words, what it shows.
    struct PaneLook { var side: Int; var rect: CGRect; var crop: Data; var rows: [[CandidatePicker.Piece]]; var view: XiaoLanPanes.View }

    func paneWatchLoop() async {
        var state = PaneWatchState()
        state.history = PaneHistory.load()  // 183: what was read before a restart is not new again
        state.loaded = Set(state.history.keys)
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
                // 183: on the iPad Echo shows beside or behind the two windows; with both in view the watch goes on.
                guard await paneLeaveEcho(&state) else {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    continue
                }
            } else {
                state.frontSince = nil
            }
            watchStatus = "正在同时守候微信和企业微信…"
            // 183 (Echo 182 overnight, 11-26: "【小益心山』104上1VULO" read off a window still scrolling): read at rest.
            await feed.settled(quiet: 0.2, least: 0, most: 0.8)
            let looks = await paneLooks()
            paneTell(looks, &state)
            paneNoAppsCheck(looks, &state)
            for look in looks {
                guard watching, !Task.isCancelled else { break }
                // 183 (Echo 182 overnight, 11-26: an order waited 13–25 s for the other window's back to its list): an
                // order first; the rest of the pass waits.
                if ordersWaiting { break }
                await paneHandle(look, &state)
            }
            // 182 (user 11-26: "速度太慢了…跟安卓機比差遠了"): a shorter rest between passes (was 0.7 s).
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    /// Echo itself in front while watching (11-25: iOS asked about the local network as the watch started; or the
    /// owner looks at Echo): back to WeChat by its URL, at once the first time, then after 8 s in front.
    /// Returns true when both apps' windows are in view anyway (the watch goes on).
    /// 183 (Echo 182, 11-26: after iOS asked about the local network Echo stayed full screen behind WeChat's window,
    /// "WeChat opened by its URL: no" every 5 s for minutes: in iPadOS's windows Echo showing at all is .active, so
    /// the wait for .background never ended, and WeCom stayed behind Echo): the apps not in view are opened by their
    /// URLs (WeCom first, then WeChat), no wait for Echo to leave.
    private func paneLeaveEcho(_ state: inout PaneWatchState) async -> Bool {
        let told = Set(await paneLooks().compactMap { XiaoLanPanes.toldApp($0.rows, crop: $0.crop) })
        if told.contains(.wechat) && told.contains(.wework) { state.frontSince = nil; return true }
        let t = now()
        if state.frontSince == nil { state.frontSince = t }
        guard let since = state.frontSince, t - since >= (state.hopped ? 8 : 1), t - state.lastHop >= 5 else { return false }
        state.lastHop = t
        var opened: [String] = []
        for (app, link) in [(XiaoLanOrders.App.wework, "wxwork://"), (.wechat, "weixin://")] where !told.contains(app) {
            guard let url = URL(string: link) else { continue }
            let ok = await UIApplication.shared.open(url)
            opened.append("\(link) \(ok ? "yes" : "no")")
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        DebugLog.write("watch: Echo in front while watching; opened by URL: \(opened.joined(separator: ", "))")
        (state.hopped, state.frontSince) = (true, nil)
        return false
    }

    /// 183 (Echo 181, 11-26: the iPad left on Settings full screen; the board's Cmd+H, Cmd+Tab, Esc do nothing on this
    /// iPad, and Echo may not push the screen's edges to go home or switch apps): no window of WeChat or WeCom for 30 s,
    /// the owner is told once (a notification and the watch's status) to bring them back side by side.
    private func paneNoAppsCheck(_ looks: [PaneLook], _ state: inout PaneWatchState) {
        let appShown = looks.contains { l in
            XiaoLanPanes.toldApp(l.rows, crop: l.crop) != nil || (WatchOCR.Pixels(l.crop).map { XiaoLanPanes.chatBackground($0) } ?? false)
        }
        guard !appShown else { (state.noAppsSince, state.noAppsTold) = (nil, false); return }
        let t = now()
        if state.noAppsSince == nil { state.noAppsSince = t }
        guard let since = state.noAppsSince, t - since > 30 else { return }
        watchStatus = "看不到微信和企业微信的窗口：请手动切回微信＋企业微信左右分屏"
        guard !state.noAppsTold else { return }
        state.noAppsTold = true
        DebugLog.write("watch: no window of WeChat or WeCom on the screen for 30 s; the owner is asked to bring them back")
        notifier.post(.failed, title: "小蓝看不到微信和企业微信",
                      body: "屏幕被别的 App 盖住了。请手动切回微信和企业微信左右分屏（Echo 不会推屏幕边）。", run: "xiaolan-watch")
    }

    /// 183: an order is waiting (it goes before the rest of a pass).
    private var ordersWaiting: Bool { !chatTool.pending.isEmpty || !weworkTool.pending.isEmpty }

    /// Every window on the screen now, read. 182 (user 11-26: "速度太慢了"): `side` reads that window only (each
    /// window's words cost a text recognition; a check after a tap needs only the window tapped).
    /// 183 (Echo 182 overnight, 11-26: each look read the whole window, ~1 s, two or three per line sent): `band`
    /// reads that part of it only (the title band tells a chat or the list).
    func paneLooks(after since: Double? = nil, side only: Int? = nil, band: (top: Double, bottom: Double)? = nil) async -> [PaneLook] {
        if let since { await feed.afterAction(since: since) }
        guard let frame = feed.frame, let px = WatchOCR.Pixels(frame) else { return [] }
        let rects = XiaoLanPanes.windows(px)
        var looks: [PaneLook] = []
        for (i, r) in rects.enumerated() {
            if let only, only != (rects.count == 1 ? 2 : i) { continue }
            guard let crop = XiaoLanPanes.crop(frame, r) else { continue }
            let rows = await CandidatePicker.rowsOffMain(in: crop, top: band?.top ?? 0, bottom: band?.bottom ?? 1)
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
    private func paneLook(_ side: Int, after since: Double, tries: Int = 4, band: (top: Double, bottom: Double)? = nil,
                          until done: (PaneLook) -> Bool) async -> PaneLook? {
        var last: PaneLook?
        var t = since
        for _ in 0..<tries {
            try? await Task.sleep(nanoseconds: 150_000_000)
            last = await paneLooks(after: t, side: side, band: band).first { $0.side == side }
            if let l = last, done(l) { return l }
            t = now()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return last
    }

    /// `tall`: how far off the spot (screen fraction, up or down) still counts as on it.
    /// 183 (user's rule "視窗頂端看不到游標一律不點"; Echo 182 overnight, 11-26: a 取消 clicked unseen opened WeChat's ＋
    /// menu): by a window's top a click goes only where the pointer is seen on the spot; unseen, nothing is clicked.
    private func paneTap(_ p: CGPoint, in r: CGRect, wide: Double = 0.3, tall: Double = 0.015) async -> Bool {
        let s = XiaoLanPanes.onScreen(p, in: r)
        if Double(p.y) < XiaoLanPanes.topBand { return await paneSeenTap(s) }
        pointer.aimLoosely(wide * Double(r.width), tall)
        do { try await pointer.tap(s.x, s.y, aim: false); return true } catch {
            DebugLog.write("watch: tap at (\(String(format: "%.3f, %.3f", s.x, s.y))) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// 183: a click only on a pointer seen on the spot (screen fractions).
    private func paneSeenTap(_ s: CGPoint) async -> Bool {
        let at = String(format: "%.3f, %.3f", s.x, s.y)
        do { try await pointer.point(Double(s.x), Double(s.y), aim: true, rehome: false) } catch {
            DebugLog.write("watch: tap at (\(at)) by a window's top: \(error.localizedDescription); nothing clicked")
            return false
        }
        guard pointer.aimSaw else {
            DebugLog.write("watch: tap at (\(at)) by a window's top: pointer not seen there; nothing clicked")
            return false
        }
        do { try await pointer.clickInPlace(); return true } catch {
            DebugLog.write("watch: tap at (\(at)) failed: \(error.localizedDescription)")
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
    /// 183 (Echo 182 overnight, 11-26: an order's first look read both windows, ~1.5 s): the window known to hold `app`
    /// is read alone when it still shows that app (its tab bar or WeCom's quick bar; a WeChat chat has neither, so a
    /// chat without WeCom's bar); otherwise both, as before.
    private func paneFind(_ app: XiaoLanOrders.App, _ state: inout PaneWatchState) async -> PaneLook? {
        if let side = state.apps.first(where: { $0.value == app })?.key,
           let l = await paneLooks(side: side).first(where: { $0.side == side }) {
            let told = XiaoLanPanes.toldApp(l.rows, crop: l.crop)
            if told == app || (told == nil && app == .wechat && l.view != .list && !XiaoLanPanes.weworkBar(l.rows)) { return l }
        }
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
        if XiaoLanPanes.plusMenu(look.rows) { await paneCloseMenu(look); return }  // 183
        switch look.view {
        case .list:
            state.quietSince[look.side] = nil
            guard let app = state.apps[look.side], let image = UIImage(data: look.crop)?.cgImage else { return }
            guard let hit = XiaoLanPanes.marked(look.rows, red: { Vision.redShare(image, in: $0) }).first else {
                // 183 (user 11-25: "所有紅點都要消失"): no chat marked: a news or team account's mark is opened, read
                // into the notices (never reported), and the window goes back to its list.
                if let news = XiaoLanPanes.systemMarked(look.rows, red: { Vision.redShare(image, in: $0) }).first {
                    await paneOpenSystem(news, look, app, &state)
                }
                return
            }
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
            // 183 (Echo 182, 11-26: 简体拼音's keys over 测试群 were reported as its messages, "9 W e", "#"): a system
            // keyboard over the chat: it is not read until the keyboard goes.
            if XiaoLanPanes.keyboardTop(look.rows) != nil, !CandidatePicker.ourKeyboardShown(rows: look.rows) {
                if state.notChat[look.side] != "keyboard" {
                    state.notChat[look.side] = "keyboard"
                    DebugLog.write("watch: \(title) has a system keyboard over it; not read")
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
            // 183: not while an order waits (it may be for this chat, and it goes first).
            if let quiet = state.quietSince[look.side], now() - quiet > 5, !ordersWaiting {
                DebugLog.write("watch: \(app.rawValue): \(title) quiet; back to the list")
                _ = await paneBack(look, app.rawValue)
                state.quietSince[look.side] = nil
            }
        case .unknown:
            // A search left open (a chat found by search, then back): 取消, back to the list.
            // 183 (Echo 182 overnight, 11-26: this look was taken while the search page was closing after its own 取消;
            // the second 取消, clicked unseen, hit the ＋ on the list): looked at again at rest first.
            guard XiaoLanPanes.cancelButton(look.rows) != nil else { return }
            await feed.settled(quiet: 0.3, least: 0.3, most: 1.5)
            guard let again = await paneLooks(side: look.side).first(where: { $0.side == look.side }),
                  again.view == .unknown, let cancel = XiaoLanPanes.cancelButton(again.rows) else { return }
            DebugLog.write("watch: a window is on a search page; 取消 back to its list")
            _ = await paneTap(cancel, in: again.rect, wide: 0.03)
        }
    }

    /// 183: WeChat's ＋ menu open (发起群聊, 添加朋友, 扫一扫, 收付款): closed by a click on the title bar's bare left part,
    /// on a pointer seen there; none of its rows is ever clicked.
    private func paneCloseMenu(_ look: PaneLook) async {
        DebugLog.write("watch: a window shows the ＋ menu; closing it (none of its rows clicked)")
        _ = await paneTap(XiaoLanPanes.menuCloseSpot, in: look.rect)
    }

    /// 183 (user 11-25: "只要有東西發過來，就去看一看，有用的都學下來，沒用的就棄掉"; "所有紅點都要消失"): a news or
    /// team account's red mark: opened, its lines kept in the notices (Documents/notices), never reported or answered,
    /// and back to the list.
    private func paneOpenSystem(_ hit: (name: String, at: CGPoint), _ look: PaneLook, _ app: XiaoLanOrders.App,
                                _ state: inout PaneWatchState) async {
        DebugLog.write("watch: \(app.rawValue): red mark on \(hit.name) (no one's chat); opening it to read")
        guard await paneTap(hit.at, in: look.rect) else { return }
        guard let opened = await paneLook(look.side, after: now(), until: { l in
            if case .chat = l.view { return true }
            return false
        }), case .chat(let title) = opened.view else {
            DebugLog.write("watch: \(app.rawValue): \(hit.name) did not open")
            return
        }
        if let read = WatchOCR.screen(opened.crop, title: title, rows: opened.rows) {
            let lines = read.lines.filter { !$0.mine }.suffix(8)
            ReadLog.append(lines.map { ReadMessage(chat: hit.name, group: false, sender: $0.sender.isEmpty ? hit.name : $0.sender,
                                                   text: $0.text, atMe: false) }, in: ReadLog.noticeFolder)
            DebugLog.write("watch: \(app.rawValue): \(hit.name): \(lines.count) line(s) kept in the notices, not reported")
        }
        _ = await paneBack(opened, app.rawValue)
        state.quietSince[look.side] = nil
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
        // 183: a news or team account's chat (left open) is no one's: never reported.
        if XiaoLanPanes.notChats.contains(XiaoLanPanes.listName(name)) { return 0 }
        let lines = read.lines.map { WatchReport.Line(sender: XiaoLanPanes.listName($0.sender), text: $0.text, mine: $0.mine) }
        let key = "\(app.rawValue)|\(name)"
        let before = state.history[key]
        var fresh = WatchReport.new(lines, history: before)
        if let before, state.loaded.remove(key) != nil {  // 183: the first look since a restart
            fresh = PaneHistory.newAfterLaunch(lines, history: before, fromMark: fromMark)
        }
        // 183 (Echo 182 overnight, 11-26 21:11: WeCom showed 企微测试群 scrolled up; nothing on it went on from the
        // history, so all of it counted as new, and 0040, which 小藍 had sent from WeChat 33 minutes before and which
        // was known then as the owner's, was reported): with no overlap, lines read here before are not new.
        if let before, !before.isEmpty, !lines.isEmpty, fresh.count == lines.count, let known = state.seen[key] {
            let unseen = lines.filter { !known.contains(XiaoLanSelf.plain($0.text)) }
            if unseen.count < lines.count {
                DebugLog.write("watch: \(app.rawValue): \(name): no overlap with what was read; \(lines.count - unseen.count) line(s) read before left out")
                fresh = unseen
            }
        }
        var known = state.seen[key] ?? []
        known.formUnion(lines.map { XiaoLanSelf.plain($0.text) })
        state.seen[key] = known.count > 600 ? Set(lines.map { XiaoLanSelf.plain($0.text) }) : known
        if before == nil && fromMark {
            // Opened for its red mark the first time: what came after my last line (at most 5) is the unread.
            let start = (lines.lastIndex { $0.mine }).map { $0 + 1 } ?? 0
            fresh = Array(lines[min(start, lines.count)...].suffix(5))
        }
        state.history[key] = WatchReport.remember(fresh, screen: lines, history: before)
        if state.history[key] != before { PaneHistory.save(state.history) }  // 183
        let names = WatchSettings.myNames
        // 181 (user 11-25: "兩個號在一個群里…就相當于是同一個人，就不用回復了"; "應該點開把那個紅點給點掉，而不是應該回復"):
        // the owner's own lines here are what this side's other account can see; a line on this side that is one of the
        // owner's on the other (sent by 小藍 or read there as mine) is from the owner's other account: opened, never
        // reported, and its sender learned.
        let t = now()
        state.sent.removeAll { t - $0.at > XiaoLanSelf.sentWindow }
        for line in fresh where line.mine { state.sent.append(XiaoLanSelf.Sent(app: app, chat: name, text: line.text, at: t)) }
        if state.sent.count > 200 { state.sent.removeFirst(state.sent.count - 200) }  // 183: was 60
        var own: [String] = [], unread: [String] = []
        let others = fresh.filter { line in
            guard !line.mine else { return false }
            let owners = names + XiaoLanSelf.learned
            if XiaoLanSelf.sentByOther(line.text, chat: name, app: app, sent: state.sent, now: t) {
                if !line.sender.isEmpty && !XiaoLanSelf.isOwner(line.sender, names: owners)
                    && !XiaoLanSelf.noSender(line.sender, chat: name) {
                    XiaoLanSelf.learn(XiaoLanPanes.listName(line.sender))
                    DebugLog.write("watch: \(app.rawValue): \(name): \(line.sender) said what the owner said on the other app: the owner's other account, learned")
                }
                own.append(line.sender)
                return false
            }
            // 183 (Echo 182 overnight, 11-26: 24 lines "企业名片: 发起收款 •推荐客服" and "企微测试群: …" reported): in a
            // group, a line whose sender reads as the group's own name or as a button of the app was not read right.
            if read.group && XiaoLanSelf.noSender(line.sender, chat: name) { unread.append(line.text); return false }
            if XiaoLanSelf.isOwner(line.sender, names: owners) {
                // 183 (11-26: a tester called 蓝海乐 wrote privately to WeCom and was never answered, the owner's name):
                // in a group both accounts are in, the name is enough; in a private chat only what the owner said on
                // the other side is the owner's.
                if read.group { own.append(line.sender); return false }
                DebugLog.write("watch: \(app.rawValue): \(name): \(line.sender) has the owner's name in a private chat, not a line the owner sent: reported")
            }
            return true
        }
        if !unread.isEmpty {
            DebugLog.write("watch: \(app.rawValue): \(name): \(unread.count) line(s) with no sender read (the group's name or the app's buttons): not reported")
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
        // 183 (Echo 182 overnight, 11-26: the answer waited 1.5–2.5 s for the keyboard to go down): answered first.
        if let shown = sent.shown { await paneDismissKeyboard(shown) }
    }

    /// Open `chat` in its app's window (already open, or a row on its list), type `text` and send it. `shown`: the
    /// window showing the line sent (its keyboard is put down after the answer).
    private func paneSend(_ text: String, to chat: String, app: XiaoLanOrders.App,
                          _ state: inout PaneWatchState) async -> (ok: Bool, why: String, shown: PaneLook?) {
        let appName = app == .wework ? "企业微信" : "微信"
        guard var look = await paneFind(app, &state) else {
            return (false, "屏幕上没有\(appName)的窗口（请把微信和企业微信左右分屏）", nil)
        }
        // 183: WeChat's ＋ menu over the list: closed first (none of its rows clicked).
        if XiaoLanPanes.plusMenu(look.rows) {
            await paneCloseMenu(look)
            guard let closed = await paneLook(look.side, after: now(), until: { !XiaoLanPanes.plusMenu($0.rows) }),
                  !XiaoLanPanes.plusMenu(closed.rows) else { return (false, "\(appName)的＋菜单没有关掉", nil) }
            look = closed
        }
        // 180: a list's title is no chat to send to (178 replied "into 微信", the WeChat list read as a chat).
        guard !XiaoLanPanes.listTitles.contains(WatchOCR.titled(chat).name) else { return (false, "「\(chat)」不是会话", nil) }
        func isChat(_ l: PaneLook) -> Bool {
            if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: chat) }
            return false
        }
        var openedHere = false, banded = false
        // 183 (Echo 182 overnight, 11-26, n=95: WeCom already in 企微测试群 was sent back to its list, 20 s, and the
        // order failed): another title read is looked at once more, on a fresh frame (a chat scrolling as a line comes
        // in reads wrong), before the window leaves its chat; what was read is logged.
        if !isChat(look), case .chat(let seen) = look.view {
            if let again = await paneLook(look.side, after: now(), tries: 2, band: (0, XiaoLanPanes.topBand), until: isChat),
               isChat(again) {
                DebugLog.write("watch: \(app.rawValue): \(chat) is open after all (read as \(seen) first)")
                (look, banded) = (again, true)
            } else {
                DebugLog.write("watch: \(app.rawValue): \(chat) wanted, \(seen) open; back to the list")
            }
        }
        if !isChat(look) {
            if case .chat = look.view {  // another chat: back to the list first
                guard await paneBack(look, app.rawValue) else { return (false, "\(appName)没有回到会话列表（返回键旁看不到鼠标，没有点）", nil) }
                guard let back = await paneLook(look.side, after: now(), tries: 6, until: { $0.view == .list }) else {
                    return (false, "\(appName)没有回到会话列表", nil)
                }
                look = back
            }
            guard look.view == .list else { return (false, "\(appName)没有回到会话列表", nil) }
            var target = XiaoLanPanes.entries(look.rows).first { WatchChatOpen.sameChat(chat, listName: $0.name) }
                .map { CGPoint(x: 0.5, y: $0.box.midY) }
            if target == nil { target = await paneSearch(chat, look) }  // not in view: the list's search box
            guard var row = target else { return (false, "\(appName)里搜不到「\(chat)」", nil) }
            let keyboardBefore = keyboardBridge.onScreen()
            // 183 (Echo 182 overnight, 11-26: each look whole, ~1 s): the chat told by its title band alone.
            // 183 (11-26: a click right after the pointer arrived did nothing, twice; 182's 5j: the list moved between
            // the look and the click, and another chat opened): not open, the row once more: still the list, the same
            // spot; another chat, back to the list and its row again.
            var opened: PaneLook?
            for attempt in 0..<2 {
                guard await paneTap(row, in: look.rect) else { return (false, ChatToolLink.reasonNotSent, nil) }
                opened = await paneLook(look.side, after: now(), band: (0, XiaoLanPanes.topBand), until: isChat)
                if let o = opened, isChat(o) { break }
                guard attempt == 0 else { break }
                if let o = opened, case .chat(let other) = o.view {
                    DebugLog.write("watch: \(app.rawValue): \(other) opened, not \(chat) (the list moved); back and once more")
                    guard await paneBack(o, app.rawValue),
                          let list = await paneLook(look.side, after: now(), tries: 6, until: { $0.view == .list }),
                          let again = XiaoLanPanes.entries(list.rows).first(where: { WatchChatOpen.sameChat(chat, listName: $0.name) })
                    else { break }
                    (look, row) = (list, CGPoint(x: 0.5, y: again.box.midY))
                } else {
                    DebugLog.write("watch: \(app.rawValue): \(chat) did not open; its row clicked once more")
                }
            }
            guard let open = opened, isChat(open) else { return (false, "\(appName)里没有打开「\(chat)」", nil) }
            look = open
            (openedHere, banded) = (!keyboardBefore, true)
        }
        // 183: the lower part read once when only the title band was (the voice bar, a system keyboard).
        var low = look.rows
        if banded { low = await CandidatePicker.rowsOffMain(in: look.crop, top: 0.45, bottom: 1) }
        // 182 (Echo 181, 11-26): a chat left on its 按住 说话 bar is switched back to typing first; the switch puts the
        // field of this window in focus with the keyboard up, so it needs no second tap.
        var focused = false
        if let toggle = XiaoLanPanes.voiceToggle(low) {
            DebugLog.write("watch: \(app.rawValue): \(chat) shows 按住 说话; switching to typing")
            // 183 (11-26: the first click on the toggle, right after the pointer arrived, did nothing; a second in place
            // switched it): still the voice bar, clicked once more.
            var typing: PaneLook?
            for attempt in 0..<2 {
                guard await paneTap(toggle, in: look.rect, wide: 0.03) else { break }
                typing = await paneLook(look.side, after: now(), band: (0.45, 1), until: { XiaoLanPanes.voiceToggle($0.rows) == nil })
                if let t = typing, XiaoLanPanes.voiceToggle(t.rows) == nil { break }
                if attempt == 0 { DebugLog.write("watch: \(app.rawValue): still 按住 说话; the toggle clicked once more") }
            }
            guard let t = typing, XiaoLanPanes.voiceToggle(t.rows) == nil else {
                return (false, "\(appName)的「\(chat)」停在「按住 说话」，没切回打字", nil)
            }
            (look, low, focused) = (t, t.rows, true)
        }
        // 183 (Echo 182 overnight, 11-26: 小藍's keyboard came up with the chat, and its field was tapped anyway, ~2.3 s,
        // often at an estimate): the keyboard down before the row's tap and up after it opened its chat here belongs to
        // this window's field (180's case, the keyboard up from the other window, is still tapped).
        if !focused, openedHere, await smallKeyboard(up: true, within: 0.6) {
            DebugLog.write("watch: \(app.rawValue): the keyboard came up with \(chat); its field not tapped")
            focused = true
        }
        // The input field: the white box at the bottom of the window (WeCom's row of buttons above it is left alone).
        // 180 (Echo 178, 11-25): always tapped, keyboard up or not. The keyboard is the whole screen's: up from a send in
        // WeCom, a reply meant for WeChat was typed into WeCom's field and went out there, as the WeCom account.
        if !focused {
            // 183 (Echo 182, 11-26: 简体拼音 over the chat, a white key taken for the field and a letter typed): with a
            // system keyboard up the field is looked for above it.
            let keys = XiaoLanPanes.keyboardTop(low)
            guard let px = WatchOCR.Pixels(look.crop), let field = XiaoLanPanes.inputField(px, above: keys.map { $0 - 0.005 } ?? 1) else {
                return (false, "\(appName)里没找到输入框", nil)
            }
            // 183 (Echo 182 overnight, 11-26: WeCom's field is ~0.03 tall; the pointer 0.015 low counted as on it, the
            // click missed and the keyboard was waited for 5 s): within 0.007; no keyboard after it, once more.
            guard await paneTap(field, in: look.rect, wide: 0.15, tall: 0.007) else { return (false, ChatToolLink.reasonNotSent, nil) }
            if keys == nil, !(await smallKeyboard(up: true, within: 0.8)),
               let frame = feed.frame, !(await CandidatePicker.keyboardUpOffMain(in: frame)) {
                DebugLog.write("watch: \(app.rawValue): no keyboard after the field's tap; once more")
                _ = await paneTap(field, in: look.rect, wide: 0.15, tall: 0.007)
            }
        }
        try? await Task.sleep(nanoseconds: 250_000_000)  // 182: was 0.4 s
        do {
            try await pointer.key("cmd+a")
            try await pointer.key("backspace")
        } catch {
            DebugLog.write("watch: clearing the input field failed: \(error.localizedDescription)")
        }
        guard await typeWithLanAgentKeyboard(text, enter: false) else {
            return (false, "小蓝输入法没有打出字（请在\(appName)里把键盘切成小蓝）", nil)
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
        if let a = after, let r = sentShown(a) {
            let key = "\(app.rawValue)|\(r.title)"
            state.history[key] = WatchReport.remember([], screen: r.lines, history: nil)
            state.loaded.remove(key)
            PaneHistory.save(state.history)  // 183
            state.sent.append(XiaoLanSelf.Sent(app: app, chat: chat, text: text, at: now()))  // 181
            return (true, "", a)
        }
        return (false, ChatToolLink.reasonNotSent, after)
    }

    /// 183: 小藍's keyboard up (or down, `up` false) within `seconds`.
    private func smallKeyboard(up: Bool, within seconds: Double) async -> Bool {
        let end = now() + seconds
        while now() < end {
            if keyboardBridge.onScreen() == up { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return keyboardBridge.onScreen() == up
    }

    /// 182: the keyboard down by a tap on the chat's bare background above the input bar (nothing there to open or play).
    /// 180 (Echo 178, 11-25): the keyboard left up covered the windows' tab bars and the list was read as a chat.
    /// 183 (Echo 182 overnight, 11-26: after 4 lines of 12 the keyboard was still up, the tap on a time line): the
    /// keyboard is seen to go; still up, another bare spot higher up, once.
    private func paneDismissKeyboard(_ l: PaneLook) async {
        guard case .chat = l.view, let px = WatchOCR.Pixels(l.crop) else { return }
        var above = px.inputTop(from: 0.3) ?? 0.85
        for attempt in 1...2 {
            guard let spot = XiaoLanPanes.blankSpot(px, above: above) else {
                DebugLog.write("watch: no bare chat background to tap; the keyboard left up")
                return
            }
            _ = await paneTap(spot, in: l.rect, wide: 0.1)
            if await smallKeyboard(up: false, within: 0.8) { return }
            DebugLog.write(String(format: "watch: the keyboard still up after a tap at %.3f (try %ld)", Double(spot.y), attempt))
            above = Double(spot.y) - 0.05
        }
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
            await paneRetract(look.side)  // 183
            return (false, "「\(chat)」那一行没有滑出红色的删除（系统账号、公众号可能没有，或滑到别的行；已收回）")
        }
        DebugLog.write("watch: \(app.rawValue): deleting \(chat)")
        guard await paneTap(red, in: look.rect, wide: 0.04) else { return (false, "没点到「\(chat)」的删除") }
        var after = await paneLook(look.side, after: now(), tries: 3) { XiaoLanPanes.gone(chat, $0.rows) }
        if let a = after, !XiaoLanPanes.gone(chat, a.rows), let confirm = XiaoLanPanes.confirmDelete(a.rows) {
            DebugLog.write("watch: \(app.rawValue): the confirmation (\(app == .wework ? "the alert's 删除" : "清空记录同时不显示聊天"))")
            _ = await paneTap(confirm, in: look.rect, wide: 0.04)
            after = await paneLook(look.side, after: now(), tries: 3) { XiaoLanPanes.gone(chat, $0.rows) }
        }
        guard let end = after, XiaoLanPanes.gone(chat, end.rows) else {
            await paneRetract(look.side)  // 183
            return (false, "「\(chat)」还在\(appName)的会话列表上")
        }
        DebugLog.write("watch: \(app.rawValue): \(chat) deleted")
        return (true, "")
    }

    /// 183 (Echo 181, 11-26: a swipe brought out the next row's 标为未读 / 不显示 / 删除 and left them out; the user put
    /// them back by hand): row buttons left out go back with a click on the list's bare part under its rows.
    private func paneRetract(_ side: Int) async {
        guard let l = await paneLooks(side: side).first(where: { $0.side == side }) else { return }
        let rowButtons = ["标为未读", "標為未讀", "标记未读", "不显示", "不顯示", "删除", "刪除", "置顶", "置頂"]
        guard l.rows.joined().contains(where: { p in p.box.midX > 0.5 && rowButtons.contains { p.text.contains($0) } }) else { return }
        let below = (XiaoLanPanes.entries(l.rows).map { Double($0.box.maxY) }.max() ?? 0.2) + 0.08
        guard below < 0.82 else {
            DebugLog.write("watch: row buttons left out; no bare list under the rows to click")
            return
        }
        DebugLog.write("watch: row buttons left out; a click under the rows puts them back")
        _ = await paneTap(CGPoint(x: 0.5, y: below), in: l.rect)
    }
}
#endif
