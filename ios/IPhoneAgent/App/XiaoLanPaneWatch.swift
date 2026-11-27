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
    /// 186: when a system keyboard over a side's chat was last switched to 小藍 to be put down.
    var keyboardDown: [Int: Double] = [:]
    /// 183: the chats whose history came from an earlier launch (PaneHistory), not read since.
    var loaded: Set<String> = []
    /// 183: every line's words read in each chat since the launch (XiaoLanSelf.plain), for a screen that does not go on
    /// from the history (scrolled up).
    var seen: [String: Set<String>] = [:]
    /// 183: since when no window of WeChat or WeCom has been on the screen, and whether the owner was told.
    var noAppsSince: Double?, noAppsTold = false
    /// 184 (C15b): how often 小藍 tried to bring the two windows back itself since they went, and when last.
    var recallTries = 0, lastRecall = -Double.infinity
    /// 184 (C13): when a red mark's row was clicked on each side and the chat was not seen open then.
    var markTapped: [Int: Double] = [:]
    /// 185 (B17): the 取消 of a search page clicked in vain on each side in a row, and until when it is left alone.
    var cancelFails: [Int: Int] = [:], cancelPause: [Int: Double] = [:]
    /// 184: the windows left on a news or team account's page (its back missed): back again on the next look.
    var systemOpen: Set<Int> = []
    /// 188: voice notes, videos, pictures, files and links read and not reported yet: opened, looked at and reported
    /// right after the read (XiaoLanMediaRead), the other window waiting meanwhile.
    var media: [MediaJob] = []
    /// 188 (user 11-27): what WeCom's window shows this pass (its marked chats, the chat it has open), and when WeChat
    /// first saw each WeCom group's mark: WeChat leaves such a mark to WeCom first.
    var weworkMarked: Set<String> = [], weworkOpen: String?
    var leftToWeCom: [String: Double] = [:]
    /// 188 (user 11-27: 「先收到的消息先回」): when each chat's red mark was first seen ("wechat|测试群"), so the one that
    /// came first is opened first, whichever window it is in; looked at during the waits for a reply too.
    var markSeen: [String: Double] = [:]
    var lastMarkNote = -Double.infinity
    /// 188 (大藍's joinVoiceText): per chat, the words its voice notes were turned into here: their lines are no news.
    var echoes: [String: [String]] = [:]
    /// 188 (大藍's missedLine): when each chat was left for the list, and the list preview already opened again for.
    var leftAt: [String: Double] = [:]
    var missedOpened: [String: String] = [:]
    /// 189 (N16): texts typed by 小藍 so far (an order failed with this unchanged typed nothing), and the orders
    /// already sent once more.
    var typed = 0
    var retried: Set<String> = []
    /// 189 (speed): where the input field is in the window whose line waits for its QA reply (the pointer goes there
    /// meanwhile, no click).
    var replyField: (side: Int, at: CGPoint)?
    /// 189 (speed): the window as it showed my line just sent, while the next order is for the same chat (no new look).
    var lastShown: (app: XiaoLanOrders.App, chat: String, look: AppModel.PaneLook, at: Double)?
    /// 189 (N20): the title of the chat each side was last read in with no banner over its top.
    var openChat: [Int: String] = [:]
}

@MainActor private var paneHeldTurn = 0
/// 188: each window's last full read and its grey grid, for a window unchanged since then (paneLooks(reuse:)).
@MainActor private var paneLookCache: [Int: (sig: [UInt8], look: AppModel.PaneLook, at: Double)] = [:]

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
            if let order = paneNextOrder() {  // 188: in the order the messages came, both apps together
                await paneOrder(order, &state)
                continue
            }
            // 187 (user 11-27: "各位先收到一個消息…點進去了，正在要回呢，然後啟微又收到了一個消息。那這個時候呢先把各位的
            // 回了，然後再去點啟微的…反過來也是一樣的"): while a line just read waits for its QA reply (15 s at most), nothing
            // else is looked at; its chat stays open and the reply, an order, goes in first.
            if repliesComing {
                // 189 (speed; user 11-27 「還有辦法壓縮時間嗎」): while the server thinks, the pointer goes to the field the
                // reply is typed in (no click): the send's own move is then a few units, ~1 s off each reply
                if let f = state.replyField {
                    state.replyField = nil
                    do {
                        try await pointer.point(Double(f.at.x), Double(f.at.y), aim: false, rehome: false)
                        DebugLog.write(String(format: "watch: a reply on its way; the pointer at the field (%.3f, %.3f) meanwhile", f.at.x, f.at.y))
                    } catch {
                        DebugLog.write("watch: the pointer not moved to the field: \(error.localizedDescription)")
                    }
                    continue
                }
                // 188: the marks that come meanwhile are noted (not opened), so they go in the order they came
                if now() - state.lastMarkNote > 1.0, board.connected, feed.watchable {
                    state.lastMarkNote = now()
                    let seen = await paneLooks(reuse: true)  // an order coming meanwhile waits for no reading
                    paneNoteMarks(seen, &state)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
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
            let looks = await paneLooks(reuse: true)  // 188: a window unchanged since the last pass is not read again
            paneTell(looks, &state)
            paneNoteWeCom(looks, &state)  // 188
            paneNoteMarks(looks, &state)  // 188
            await paneNoAppsCheck(looks, &state)
            for look in paneByTurn(looks, state) {
                guard watching, !Task.isCancelled else { break }
                // 183 (Echo 182 overnight, 11-26: an order waited 13–25 s for the other window's back to its list): an
                // order first; the rest of the pass waits.
                if ordersWaiting || repliesComing { break }  // 187: a reply on its way goes before the other window
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
        let looks = await paneLooks()
        let told = Set(looks.compactMap { XiaoLanPanes.toldApp($0.rows, crop: $0.crop) })
        if told.contains(.wechat) && told.contains(.wework) { state.frontSince = nil; return true }
        // 185 (B9, Echo 184, 11-26: WeChat left in a chat with the keyboard up was not told, and weixin:// was opened
        // every 11 s for minutes): two windows of the apps' own (told, or a chat of theirs) are both in view.
        // 187 (Echo 186, 11-27: WeCom left in its search, "Echo in front… opened by URL: wxwork://" every 11 s for minutes,
        // the search never closed): a window with 取消 at its top (a search) is one of theirs; the watch closes it.
        let theirs = looks.filter { l in
            XiaoLanPanes.toldApp(l.rows, crop: l.crop) != nil || XiaoLanPanes.weworkBar(l.rows)
                || XiaoLanPanes.cancelButton(l.rows) != nil
                || (WatchOCR.Pixels(l.crop).map { XiaoLanPanes.chatBackground($0) } ?? false)
        }
        if theirs.count >= 2 { state.frontSince = nil; return true }
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
    /// 184 (C15b; user 11-26: "不要叫他手動切"): first 小藍 brings them back itself (paneRecall), up to three times 20 s
    /// apart; the owner is told only when that did not work.
    private func paneNoAppsCheck(_ looks: [PaneLook], _ state: inout PaneWatchState) async {
        let appShown = looks.contains { l in
            XiaoLanPanes.toldApp(l.rows, crop: l.crop) != nil || (WatchOCR.Pixels(l.crop).map { XiaoLanPanes.chatBackground($0) } ?? false)
        }
        guard !appShown else { (state.noAppsSince, state.noAppsTold, state.recallTries) = (nil, false, 0); return }
        // 185 (B2, Echo 184, 11-26: iOS's local network question over Echo made it inactive; 30 s later 小藍 went for
        // 辅助触控's button): a system question over Echo is no app over the windows; nothing is clicked for it.
        if UIApplication.shared.applicationState == .inactive { return }
        let t = now()
        if state.noAppsSince == nil { state.noAppsSince = t }
        guard let since = state.noAppsSince, t - since > 30 else { return }
        if state.recallTries < 3, t - state.lastRecall >= 20 {
            state.recallTries += 1
            if await paneRecall(attempt: state.recallTries) {
                (state.noAppsSince, state.noAppsTold, state.recallTries) = (nil, false, 0)
                return
            }
            state.lastRecall = now()
            if state.recallTries < 3 { return }
        }
        watchStatus = "看不到微信和企业微信的窗口：小蓝自己切回没成功，请手动切回微信＋企业微信左右分屏"
        guard !state.noAppsTold else { return }
        state.noAppsTold = true
        DebugLog.write("watch: no window of WeChat or WeCom on the screen for 30 s; brought back itself: no; the owner is asked")
        notifier.post(.failed, title: "小蓝看不到微信和企业微信",
                      body: "屏幕被别的 App 盖住了，小蓝用辅助触控自己切回试了 3 次没成功。请手动切回微信和企业微信左右分屏。", run: "xiaolan-watch")
    }

    /// 184 (C15b): the two windows brought back as by hand (XiaoLanRecall): 辅助触控's button when the Dock is not in
    /// view, then the Dock's WeCom, then WeChat; every click only on the pointer seen there (paneSeenTap). True when both
    /// apps' windows are in view after.
    func paneRecall(attempt n: Int) async -> Bool {
        func dock() async -> (wechat: CGPoint?, wework: CGPoint?) {
            await feed.settled(quiet: 0.3, least: 0.2, most: 2)
            guard let frame = feed.frame, let px = WatchOCR.Pixels(frame) else { return (nil, nil) }
            return XiaoLanRecall.dockIcons(px)
        }
        func log(_ s: String) { DebugLog.write("watch: bringing WeChat and WeCom back (\(n)): \(s)") }
        var icons = await dock()
        if icons.wechat == nil || icons.wework == nil {
            // 185: the button where it is seen now (the owner may move it); not seen, nothing is clicked.
            guard let frame = feed.frame, let px = WatchOCR.Pixels(frame), let at = XiaoLanRecall.assistiveTouchButton(px) else {
                log("辅助触控's button not seen on the screen; nothing clicked")
                return false
            }
            log(String(format: "辅助触控's button seen at (%.3f, %.3f)", at.x, at.y))
            guard await paneSeenTap(at, half: (0.035, 0.025)) else { log("its button not clicked"); return false }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            icons = await dock()
        }
        guard let wework = icons.wework else { log("WeCom's icon not seen in the Dock"); return false }
        log(String(format: "the Dock's WeCom at (%.3f, %.3f)", wework.x, wework.y))
        guard await paneSeenTap(wework, half: (0.03, 0.025)) else { log("WeCom's icon not clicked"); return false }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard let wechat = await dock().wechat ?? icons.wechat else { log("WeChat's icon not seen in the Dock"); return false }
        log(String(format: "the Dock's WeChat at (%.3f, %.3f)", wechat.x, wechat.y))
        guard await paneSeenTap(wechat, half: (0.03, 0.025)) else { log("WeChat's icon not clicked"); return false }
        // 189 (N14): the pointer off the Dock (no click), so it does not stay up over the windows' bottoms
        try? await pointer.point(0.5, 0.45, aim: false, rehome: false)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let told = Set(await paneLooks(after: now()).compactMap { XiaoLanPanes.toldApp($0.rows, crop: $0.crop) })
        let back = told.contains(.wechat) && told.contains(.wework)
        log(back ? "both back" : "after: \(told.map { "\($0)" }.sorted().joined(separator: ", "))")
        return back
    }

    /// 183: an order is waiting (it goes before the rest of a pass).
    private var ordersWaiting: Bool { !chatTool.pending.isEmpty || !weworkTool.pending.isEmpty }
    /// 187: a QA reply on its way to one of the apps.
    private var repliesComing: Bool { chatTool.qaWaiting > 0 || weworkTool.qaWaiting > 0 }

    /// Every window on the screen now, read. 182 (user 11-26: "速度太慢了"): `side` reads that window only (each
    /// window's words cost a text recognition; a check after a tap needs only the window tapped).
    /// 183 (Echo 182 overnight, 11-26: each look read the whole window, ~1 s, two or three per line sent): `band`
    /// reads that part of it only (the title band tells a chat or the list).
    func paneLooks(after since: Double? = nil, side only: Int? = nil, band: (top: Double, bottom: Double)? = nil,
                   reuse: Bool = false) async -> [PaneLook] {
        // 184 (Echo 183, 11-26: every look after a tap waited for 0.5 s of a still screen): 0.25 s; a look taken while
        // the window still moves is looked at again by paneLook anyway.
        if since != nil { await feed.settled(quiet: 0.25, least: 0.15, most: 2.5) }
        guard let frame = feed.frame, let px = WatchOCR.Pixels(frame) else { return [] }
        let rects = XiaoLanPanes.windows(px)
        var looks: [PaneLook] = []
        for (i, r) in rects.enumerated() {
            if let only, only != (rects.count == 1 ? 2 : i) { continue }
            guard let crop = XiaoLanPanes.crop(frame, r) else { continue }
            let side = rects.count == 1 ? 2 : i
            // 188 (大藍's watch compares the screen before it reads it): the main loop's window that has not changed
            // since its last read (no point of a 48×96 grey grid moved by more than 10) is not read again, at most for 3 s
            let sig = WatchOCR.Pixels(crop).map { XiaoLanMediaFind.signature($0) } ?? []
            if reuse, band == nil, let kept = paneLookCache[side], kept.look.rect == r, now() - kept.at < 3,
               XiaoLanMediaFind.sameSignature(kept.sig, sig) {
                looks.append(kept.look)
                continue
            }
            let rows = await CandidatePicker.rowsOffMain(in: crop, top: band?.top ?? 0, bottom: band?.bottom ?? 1)
            var view = XiaoLanPanes.view(rows)
            // 181: a list whose words were not read (title nor tab bar) is still told by its tab's colour, at any width.
            if view == .unknown, XiaoLanPanes.cancelButton(rows) == nil, let px = WatchOCR.Pixels(crop), XiaoLanPanes.tabApp(px) != nil {
                view = .list
            }
            let look = PaneLook(side: side, rect: r, crop: crop, rows: rows, view: view)
            if band == nil { paneLookCache[side] = (sig, look, now()) }
            looks.append(look)
        }
        return looks
    }

    /// The same window again after a gesture, up to `tries` looks 0.5 s apart until `done` says so.
    /// 182: only that window is read, and the waits are shorter (0.3 + 0.2 s were 0.15 + 0.1 s): the wait for a new
    /// frame after the action is already in `paneLooks(after:)`.
    func paneLook(_ side: Int, after since: Double, tries: Int = 4, band: (top: Double, bottom: Double)? = nil,
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
    /// 188 (B44, Echo 187, 11-27: a red mark's row seen 0.021 below its name was corrected, though on the row): a
    /// list row is ~0.078 tall and the spot is its name, 0.027 below the row's top: within 0.025 is on the row.
    static let rowTall = 0.025
    /// 188 (B46): how far over or under an input field's middle still counts as on it.
    static let fieldTall = 0.010
    func paneTap(_ p: CGPoint, in r: CGRect, wide: Double = 0.3, tall: Double = 0.015) async -> Bool {
        let s = XiaoLanPanes.onScreen(p, in: r)
        if Double(p.y) < XiaoLanPanes.topBand { return await paneSeenTap(s, half: (wide * Double(r.width), tall)) }
        pointer.aimLoosely(wide * Double(r.width), tall)
        do { try await pointer.tap(s.x, s.y, aim: false); return true } catch {
            DebugLog.write("watch: tap at (\(String(format: "%.3f, %.3f", s.x, s.y))) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// 183: a click only on a pointer seen on the spot (screen fractions).
    /// 184 (Echo 183, 11-26: the pointer seen 0.007 off the menu's bare spot, and 0.026 off in a search box 0.44 wide,
    /// counted as unseen; nothing was ever clicked): seen anywhere within `half` of the spot (the button's own size) is
    /// enough.
    func paneSeenTap(_ s: CGPoint, half: (x: Double, y: Double)) async -> Bool {
        let at = String(format: "%.3f, %.3f", s.x, s.y)
        pointer.aimHalf = half  // 188 (B44): a first stop on the button is clicked, not corrected toward its middle
        defer { pointer.aimHalf = nil }
        do { try await pointer.point(Double(s.x), Double(s.y), aim: true, rehome: false) } catch {
            DebugLog.write("watch: tap at (\(at)) by a window's top: \(error.localizedDescription); nothing clicked")
            return false
        }
        var seen = pointer.aimSaw
        if !seen, pointer.seenOff != nil { return false }  // 189 (N12): the caller hops from where it was seen
        if !seen, let p = try? await pointer.lookFor(Double(s.x), Double(s.y)),
           abs(Double(p.x - s.x)) <= max(half.x, 0.008), abs(Double(p.y - s.y)) <= max(half.y, 0.008) {
            DebugLog.write(String(format: "watch: tap at (%@) by a window's top: pointer seen at (%.3f, %.3f), on the button", at, p.x, p.y))
            seen = true
        }
        guard seen else {
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
        // 188 night (Echo 188, 11-27: 1.5 s from an order to the pointer's first move, the window read again though it
        // had not changed since the watch read it a moment before): unchanged, the watch's own read is used
        if let side = state.apps.first(where: { $0.value == app })?.key,
           let l = await paneLooks(side: side, reuse: true).first(where: { $0.side == side }) {
            let told = XiaoLanPanes.toldApp(l.rows, crop: l.crop)
            if told == app || (told == nil && app == .wechat && l.view != .list && !XiaoLanPanes.weworkBar(l.rows)) { return l }
        }
        let looks = await paneLooks(reuse: true)
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
    /// 187 (Echo 186, 11-27 00:32 首爾; user: "給啟微群發消息的時候…彈出來一個框，你點返回的時候，正好點到那個框，然後
    /// 他就進去了。這時候你就以為你現在還在這個各位的群里面"): WeChat in 测试群, the owner wrote to 企微测试群, its banner
    /// came down over the title bar just as the back arrow was clicked: the banner opened 企微测试群, whose lines were
    /// reported as 测试群's and answered into 企微测试群 three times. A banner over the window's top is waited out (5 s
    /// at most) before the back; after it, on a still screen, another chat open where the list should be is a click
    /// gone wrong: back once more, nothing there read.
    private func paneBack(_ look: PaneLook, _ who: String, refound: Bool = false) async -> Bool {
        var look = look
        var waited = 0.0
        while WatchOCR.bannerShown(Array(look.rows.joined()), px: WatchOCR.Pixels(look.crop)), waited < 5 {
            // 188 (B45): what was taken for the banner is said (187: ten of these on WeChat, none on WeCom, two with nothing coming in)
            if waited == 0 {
                let p = WatchOCR.bannerPiece(Array(look.rows.joined()), px: WatchOCR.Pixels(look.crop))
                DebugLog.write("watch: \(who): a banner over the window's top; back after it goes (「\(p?.text ?? "")」 at y \(String(format: "%.3f", Double(p?.box.midY ?? 0))))")
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 0.5
            guard let l = await paneLooks(side: look.side).first(where: { $0.side == look.side }) else { break }
            look = l
        }
        var left: String?
        if case .chat(let t) = look.view { left = WatchOCR.titled(t).name }
        guard await paneBackClick(look, who, refound: refound) else { return false }
        guard let left, !refound else { return true }
        await feed.settled(quiet: 0.3, least: 0.3, most: 1.5)
        guard let after = await paneLooks(side: look.side).first(where: { $0.side == look.side }),
              case .chat(let t) = after.view, !WatchReport.sameName(WatchOCR.titled(t).name, left) else { return true }
        DebugLog.write("watch: \(who): back opened \(t), not the list (a banner clicked?); back once more, nothing read there")
        return await paneBackClick(after, who)
    }

    func paneBackClick(_ look: PaneLook, _ who: String, refound: Bool = false) async -> Bool {
        let arrow = XiaoLanPanes.onScreen(XiaoLanPanes.back, in: look.rect)
        // 187 (user 11-26: "從A點到B點，停頓一下，然後再到C點…中間為什麼要停頓，而不是直接就點過去"; B33, Echo 186, 11-26:
        // the blind hop up from the stop below the arrow fell short with 辅助触控's speed-up and clicked the top message's
        // avatar, its 客户详情 opened twice): straight to the arrow, clicked only with the pointer seen on it (every click by
        // a window's top is); not seen there, the stop below it as before.
        if !refound {
            let windows = await paneWindowCount()
            let t = now()
            // 188 (B44): the arrow's own size; 187's first stops at 0.014 and 0.035 for 0.029 were on it (the user saw)
            // 189 (N12): a first stop seen near the arrow (within 0.1) is the short hop's start, as the stop below it is
            pointer.seenOff = nil
            pointer.hopFromSeen = 0.1
            let direct = await paneSeenTap(arrow, half: (0.02, 0.012))
            pointer.hopFromSeen = nil
            if direct {
                DebugLog.write("watch: \(who): back: " + String(format: "straight to the arrow (%.3f, %.3f), seen on it", Double(arrow.x), Double(arrow.y)))
                if windows == 2, await paneWindowCount(after: t) == 1 {
                    DebugLog.write("watch: a window is gone after the back arrow; watch stopped")
                    stopWatch("有一个窗口不见了：请点 Dock 上它的图标叫回来，再开守候")
                    return false
                }
                return true
            }
            if let s = pointer.seenOff {
                pointer.seenOff = nil
                do { try await pointer.clickBy(Double(arrow.x - s.x), Double(arrow.y - s.y)) } catch {
                    DebugLog.write("watch: \(who): back: the click failed: \(error.localizedDescription)")
                    return false
                }
                DebugLog.write("watch: \(who): back: " + String(format: "the first stop seen at (%.3f, %.3f), then the short hop to the arrow (%.3f, %.3f)",
                                                                Double(s.x), Double(s.y), Double(arrow.x), Double(arrow.y)))
                if windows == 2, await paneWindowCount(after: t) == 1 {
                    DebugLog.write("watch: a window is gone after the back arrow; watch stopped")
                    stopWatch("有一个窗口不见了：请点 Dock 上它的图标叫回来，再开守候")
                    return false
                }
                return true
            }
        }
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
            // 185 (B20, Echo 184, 11-26: the first back had gone through; the second's search for the pointer under the
            // arrow clicked a list row, 蓝海乐 opened and its new 你好 became history): on its list already, done.
            if let l = await paneLooks(side: look.side).first(where: { $0.side == look.side }), l.view == .list {
                DebugLog.write("watch: \(who): back: the window is on its list already; nothing more clicked")
                return true
            }
            DebugLog.write("watch: \(who): back: pointer not seen below the arrow; finding it first, then once more")
            pointer.forgetPosition()
            return await paneBackClick(look, who, refound: true)
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
            state.openChat[look.side] = nil  // 189 (N20)
            state.systemOpen.remove(look.side)  // 184
            guard let app = state.apps[look.side], let image = UIImage(data: look.crop)?.cgImage else { return }
            let marks = XiaoLanPanes.marked(look.rows, red: { Vision.redShare(image, in: $0) })
            let hits = app == .wechat ? paneLeaveToWeCom(marks, look.rows, &state) : marks  // 188
            var next = PaneTurns.first(hits, seen: { state.markSeen["\(app.rawValue)|\($0)"] ?? now() })
            if next == nil, hits.count == marks.count { next = paneMissedLine(look, app, &state) }  // 188
            guard let hit = next else {
                if hits.count < marks.count { return }  // 188: only WeCom groups marked, left to WeCom for now
                // 183 (user 11-25: "所有紅點都要消失"): no chat marked: a news or team account's mark is opened, read
                // into the notices (never reported), and the window goes back to its list.
                if let news = XiaoLanPanes.systemMarked(look.rows, red: { Vision.redShare(image, in: $0) }).first {
                    await paneOpenSystem(news, look, app, &state)
                }
                return
            }
            DebugLog.write("watch: \(app.rawValue): red mark on \(hit.name); opening it")
            guard await paneTap(hit.at, in: look.rect, tall: Self.rowTall) else { return }
            let opened = await paneLook(look.side, after: now()) { l in
                if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: hit.name) }
                return false
            }
            guard let chat = opened, case .chat(let title) = chat.view else {
                DebugLog.write("watch: \(app.rawValue): \(hit.name) did not open (title not seen)")
                state.markTapped[look.side] = now()  // 184 (C13): a chat seen there next counts as opened by its mark
                return
            }
            let same = WatchChatOpen.sameChat(WatchOCR.titled(title).name, listName: hit.name)
            if !same {
                // 184 (C13; Echo 183, 11-26: WeCom's list moved as a private line came in; 企微测试群's row opened 蓝海乐's
                // chat, "did not open", and on the next pass its line was "history starts here", never reported): the
                // chat that did open is read as opened by a mark (its last lines), if it is a chat of the app at all.
                guard let px = WatchOCR.Pixels(chat.crop), XiaoLanPanes.chatBackground(px) || XiaoLanPanes.weworkBar(chat.rows) else {
                    DebugLog.write("watch: \(app.rawValue): \(hit.name) did not open (\(title) shows, no chat)")
                    return
                }
                DebugLog.write("watch: \(app.rawValue): \(hit.name)'s row opened \(title) (the list moved); read as opened by its mark")
            }
            let markSender = same ? XiaoLanPanes.previewSender(look.rows, of: hit.name) : nil
            let markPreview = same ? XiaoLanPanes.previewText(look.rows, of: hit.name) : nil
            if same && markPreview == nil { DebugLog.write("watch: \(app.rawValue): \(hit.name): its preview was not read on the list") }
            // 188 (B45): a window not read (a banner over its top) is looked at again, a second apart, for up to 6 s (a
            // banner stays ~5 s); the other window waits meanwhile, so the line that came first is answered first. The
            // last try takes the mark's preview if the window still cannot be read.
            var current = (look: chat, title: title)
            for attempt in 0..<7 {
                let done = paneRead(app, current.look, title: current.title, fromMark: true, markSender: markSender,
                                    markPreview: markPreview, lastTry: attempt == 6, &state)
                if done >= 0 { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let name = WatchOCR.titled(title).name
                guard let again = await paneLook(look.side, after: now(), until: { l in
                    if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: name) }
                    return false
                }), case .chat(let t) = again.view, WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: name) else {
                    DebugLog.write("watch: \(app.rawValue): \(name) is no longer in its window; its preview's line taken")
                    _ = paneRead(app, current.look, title: current.title, fromMark: true, markSender: markSender,
                                 markPreview: markPreview, lastTry: true, &state)
                    break
                }
                current = (again, t)
            }
            paneNoteReplyField(current.look, &state)  // 189 (speed)
            await paneMediaRun(&state)  // 188
            state.quietSince[look.side] = now()
        case .chat(let title):
            // 187 (user 11-27: a sheet over the chat — "點那個叉…都可以把這個聊天框給它關掉"): another chat open over this one
            // as a sheet (a banner clicked) is closed by its ✕ first; nothing under it or in it is read.
            if let px = WatchOCR.Pixels(look.crop), let close = XiaoLanPanes.sheetClose(px) {
                DebugLog.write("watch: \(title): another chat open over it as a sheet (a banner clicked?); closed by its ✕, nothing read")
                _ = await paneSeenTap(XiaoLanPanes.onScreen(close, in: look.rect), half: (0.015, 0.012))
                return
            }
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
                // 186 (Echo 185, 11-26: 测试群 and 主人蓝海乐, opened from their marks under the 简体拼音 the owner had
                // left, were not read, and their back was clicked twice, the first only putting the keyboard down): the
                // keyboard is switched to 小藍, which puts itself down (once in 20 s a side); the chat is read next pass.
                if !ordersWaiting, now() - (state.keyboardDown[look.side] ?? -Double.infinity) > 20 {
                    state.keyboardDown[look.side] = now()
                    if await showLanAgentKeyboard(), await keyboardBridge.type("", enter: false, within: 2, dismiss: true),
                       await smallKeyboard(up: false, within: 1.5) {
                        DebugLog.write("watch: \(title): the system keyboard switched to 小藍 and put down; read on the next pass")
                        state.notChat[look.side] = nil
                        return
                    }
                    DebugLog.write("watch: \(title): the system keyboard was not put down")
                }
                // 184 (Echo 183, 11-26: 测试群 under 简体拼音 was left there, its keyboard up over WeCom too): not read,
                // but back to the list after 5 s all the same (the back puts the keyboard down).
                if state.quietSince[look.side] == nil { state.quietSince[look.side] = now() }
                if let quiet = state.quietSince[look.side], now() - quiet > 5, !ordersWaiting {
                    let who = (state.apps[look.side] ?? XiaoLanPanes.chatApp(look.rows)).rawValue
                    DebugLog.write("watch: \(who): \(title) under a system keyboard; back to the list")
                    _ = await paneBack(look, who)
                    state.quietSince[look.side] = nil
                }
                return
            }
            state.notChat[look.side] = nil
            // 180: the app told by the chat itself (WeCom's quick bar), not by going back to its list (the back arrow of
            // the left window sits by the screen's top-left corner).
            if state.apps[look.side] == nil { state.apps[look.side] = XiaoLanPanes.chatApp(look.rows) }
            guard let app = state.apps[look.side] else { return }
            // 184 (C13): a mark's row clicked on this side within 10 s, the chat not seen open then: opened by its mark.
            let fromMark = state.markTapped.removeValue(forKey: look.side).map { now() - $0 < 10 } ?? false
            // 189 (N20, Echo 189, 11-27 12:55 首爾: WeChat in 测试群, a banner of 企微测试群 came down over its title; the
            // banner's chat name was read as the window's title, 测试群's 「您在干嘛」 went to the server as a private line of
            // 「企微测试群」): under a banner the chat is the one last read on this side without one
            var chatTitle = title
            if WatchOCR.bannerShown(Array(look.rows.joined()), px: WatchOCR.Pixels(look.crop)) {
                if let known = state.openChat[look.side], !WatchReport.sameName(WatchOCR.titled(title).name, WatchOCR.titled(known).name) {
                    DebugLog.write("watch: \(app.rawValue): 「\(title)」 read at the window's top under a banner; still \(known) under it")
                    chatTitle = known
                }
            } else {
                state.openChat[look.side] = title
            }
            let reported = paneRead(app, look, title: chatTitle, fromMark: fromMark, &state)
            if reported > 0 || state.quietSince[look.side] == nil {
                state.quietSince[look.side] = now()
            }
            if reported > 0 { paneNoteReplyField(look, &state) }  // 189 (speed)
            if !state.media.isEmpty {  // 188
                await paneMediaRun(&state)
                state.quietSince[look.side] = now()
            }
            // The engines watch the whole list: a chat that stays quiet is left for the list (its red marks). 182 (user
            // 11-26: "速度太慢了"): 5 s, was 8 s (other chats' messages waited that long first).
            // 183: not while an order waits (it may be for this chat, and it goes first).
            // 189 (speed; user 11-27 「還有辦法壓縮時間嗎」): another chat of this app marked on its list when it was last seen
            // waits for this one: 1 s, then back to it.
            let othersMarked = state.markSeen.keys.contains { k in
                k.hasPrefix("\(app.rawValue)|") && !WatchChatOpen.sameChat(WatchOCR.titled(chatTitle).name, listName: String(k.dropFirst(app.rawValue.count + 1)))
            }
            if let quiet = state.quietSince[look.side], now() - quiet > (othersMarked ? 1 : 5), !ordersWaiting {
                DebugLog.write("watch: \(app.rawValue): \(chatTitle) quiet; back to the list")
                _ = await paneBack(look, app.rawValue)
                state.quietSince[look.side] = nil
                state.openChat[look.side] = nil
                state.leftAt["\(app.rawValue)|\(WatchOCR.titled(chatTitle).name)"] = now()  // 188 (missedLine)
            }
        case .unknown:
            // 188 night: WeChat's 「如需浏览」 page left open (a link's trip to Safari cut short) is closed by its ✕; WeChat
            // cannot be told by it, so its orders would find no window
            if XiaoLanMediaFind.linkBlocked(look.rows),
               let at = XiaoLanSpots.point(.pageClose, app: .wechat, width: Double(look.rect.width)) {
                DebugLog.write("watch: a window is on WeChat's 「如需浏览」 page; closed by its ✕")
                _ = await paneTap(at, in: look.rect, wide: 0.03, tall: 0.012)
                return
            }
            // 184: a news or team account's page left open (its back missed): back again.
            if XiaoLanPanes.cancelButton(look.rows) == nil, state.systemOpen.contains(look.side) {
                DebugLog.write("watch: a window is still on a news or team account's page; back to its list")
                if await paneBack(look, state.apps[look.side]?.rawValue ?? "window") { state.systemOpen.remove(look.side) }
                return
            }
            // A search left open (a chat found by search, then back): 取消, back to the list.
            // 183 (Echo 182 overnight, 11-26: this look was taken while the search page was closing after its own 取消;
            // the second 取消, clicked unseen, hit the ＋ on the list): looked at again at rest first.
            guard XiaoLanPanes.cancelButton(look.rows) != nil else { return }
            await feed.settled(quiet: 0.3, least: 0.3, most: 1.5)
            guard let again = await paneLooks(side: look.side).first(where: { $0.side == look.side }),
                  again.view == .unknown, let cancel = XiaoLanPanes.cancelButton(again.rows) else { return }
            // 185 (B17, Echo 184, 11-26: WeCom's 取消 clicked in vain every 3–6 s for 50 s, the pointer turned into
            // the button's frame by 指针动画): three in a row and it is left for 60 s.
            let t = now()
            if let until = state.cancelPause[look.side], t < until { return }
            DebugLog.write("watch: a window is on a search page; 取消 back to its list")
            if await paneTap(cancel, in: again.rect, wide: 0.03) {
                state.cancelFails[look.side] = 0
            } else {
                let n = (state.cancelFails[look.side] ?? 0) + 1
                state.cancelFails[look.side] = n
                if n >= 3 {
                    (state.cancelFails[look.side], state.cancelPause[look.side]) = (0, t + 60)
                    DebugLog.write("watch: 取消 not clicked three times in a row; the search page left for 60 s")
                }
            }
        }
    }

    /// 188 (user 11-27: 「假如第一條是企微，第二條來的是個微的，第三條來的又是企微的，那麽回復順序就是先企微，然後接第二個
    /// 個微，最後再回去做第三條企微的…都要按收到的順序依次回復」): the next order in turn, both apps together (a QA reply
    /// keeps the turn its message was read in); none while a message read earlier still waits for its reply.
    private func paneNextOrder() -> ChatToolLink.Command? {
        let tools = [chatTool, weworkTool]
        guard let next = PaneTurns.next(firsts: tools.map { $0.firstTurn }, asking: tools.map { $0.askingTurn }) else {
            if tools.allSatisfy({ $0.firstTurn == nil }) { return chatTool.nextCommand() ?? weworkTool.nextCommand() }
            if let held = tools.compactMap({ $0.firstTurn }).min(), held != paneHeldTurn {
                paneHeldTurn = held
                DebugLog.write("watch: a reply (turn \(held)) waits: a message read before it still waits for its own reply")
            }
            return nil
        }
        return tools[next.index].take(turn: next.turn)
    }

    /// 188 (大藍's missedLine; 126 on the phone 11-12: a message that comes in while its chat is open has no red mark):
    /// in the two minutes after a chat was left for the list, its list line showing something other than the last line
    /// read there opens it again, once per such line, as a red mark would.
    private func paneMissedLine(_ look: PaneLook, _ app: XiaoLanOrders.App, _ state: inout PaneWatchState) -> (name: String, at: CGPoint)? {
        let t = now()
        state.leftAt = state.leftAt.filter { t - $0.value < 120 }
        for (key, _) in state.leftAt.sorted(by: { $0.value < $1.value }) where key.hasPrefix("\(app.rawValue)|") {
            let name = String(key.dropFirst(app.rawValue.count + 1))
            guard let preview = XiaoLanPanes.previewText(look.rows, of: name), let last = state.history[key]?.last else { continue }
            let body = WatchReport.previewBody(preview)
            // 189 (N16, Echo 188, 11-27 11:36: 「主人蓝海乐：你們好嗎」, read and asked of the server moments before, was not
            // known by its words with the group's 「sender：」 before them: 测试群 opened again and the line asked twice): the
            // words after the sender count too
            let said = body.firstIndex(where: { $0 == ":" || $0 == "：" }).flatMap { i -> String? in
                body.distance(from: body.startIndex, to: i) <= 20 ? String(body[body.index(after: i)...]) : nil
            }
            if let said, said.count >= 2, XiaoLanSelf.readBefore(said, known: state.seen[key] ?? []) { continue }
            // 188 night (Echo 188, 11-27 05:06/05:11/05:13: 企微测试群 and 测试群 opened again three times for a list line
            // that was the owner's own send, its line not read back after the send): what was sent there is no news
            let mine = state.sent.contains { $0.app == app && WatchChatOpen.sameChat($0.chat, listName: name)
                && XiaoLanSelf.previewShowsSent(preview, $0.text) }
            guard body.count >= 2, !mine, state.missedOpened[key] != body, !WatchReport.previewShows(body, last),
                  !XiaoLanSelf.readBefore(body, known: state.seen[key] ?? []),
                  let row = XiaoLanPanes.entries(look.rows).first(where: { $0.name == name }) else { continue }
            state.missedOpened[key] = body
            DebugLog.write("watch: \(app.rawValue): \(name)'s list line 「\(body.prefix(20))」 is not the last line read there (no red mark): opened again")
            return (name: name, at: CGPoint(x: 0.5, y: row.box.midY))
        }
        return nil
    }

    /// 189 (speed): the input field of a chat whose line now waits for its QA reply (screen fractions), for the pointer
    /// meanwhile; only the bar's field (at the window's bottom, or over a keyboard), never a bubble.
    private func paneNoteReplyField(_ look: PaneLook, _ state: inout PaneWatchState) {
        guard repliesComing, let px = WatchOCR.Pixels(look.crop) else { return }
        let keys = XiaoLanPanes.keyboardTop(look.rows)
        guard let field = XiaoLanPanes.inputField(px, above: keys.map { $0 - 0.005 } ?? 1),
              keys != nil || Double(field.y) >= 0.8 else { return }
        state.replyField = (side: look.side, at: XiaoLanPanes.onScreen(field, in: look.rect))
    }

    /// 188: each chat's red mark noted when first seen; marks gone are forgotten (WeCom's groups on WeChat's side are
    /// WeCom's: not counted there).
    private func paneNoteMarks(_ looks: [PaneLook], _ state: inout PaneWatchState) {
        let t = now()
        for look in looks where look.view == .list {
            guard let app = state.apps[look.side], let image = UIImage(data: look.crop)?.cgImage else { continue }
            var marks = XiaoLanPanes.marked(look.rows, red: { Vision.redShare(image, in: $0) }).map { $0.name }
            if app == .wechat, WatchSettings.weworkOn, state.apps.values.contains(.wework) {
                marks = marks.filter { !XiaoLanPanes.weComGroupRow(look.rows, name: $0) }
            }
            let keys = Set(marks.map { "\(app.rawValue)|\($0)" })
            for k in keys where state.markSeen[k] == nil { state.markSeen[k] = t }
            state.markSeen = state.markSeen.filter { !$0.key.hasPrefix("\(app.rawValue)|") || keys.contains($0.key) }
        }
    }

    /// 188: the windows in the order their oldest mark came (a window with no mark, or in a chat, after them).
    private func paneByTurn(_ looks: [PaneLook], _ state: PaneWatchState) -> [PaneLook] {
        func oldest(_ l: PaneLook) -> Double {
            guard l.view == .list, let app = state.apps[l.side] else { return .infinity }
            let mine = state.markSeen.filter { $0.key.hasPrefix("\(app.rawValue)|") }.map { $0.value }
            return mine.min() ?? .infinity
        }
        return looks.enumerated().sorted { a, b in
            let (oa, ob) = (oldest(a.element), oldest(b.element))
            return oa != ob ? oa < ob : a.offset < b.offset
        }.map { $0.element }
    }

    /// 188: what WeCom's window shows this pass, for WeChat to leave WeCom's groups to it (paneLeaveToWeCom).
    private func paneNoteWeCom(_ looks: [PaneLook], _ state: inout PaneWatchState) {
        state.weworkMarked = []
        state.weworkOpen = nil
        guard let look = looks.first(where: { state.apps[$0.side] == .wework }) else { return }
        switch look.view {
        case .list:
            guard let image = UIImage(data: look.crop)?.cgImage else { return }
            state.weworkMarked = Set(XiaoLanPanes.marked(look.rows, red: { Vision.redShare(image, in: $0) }).map { $0.name })
        case .chat(let t):
            state.weworkOpen = WatchOCR.titled(t).name
        case .unknown:
            break
        }
    }

    /// 188 (user 11-27: 「發送給企微的消息，應該優先從企微這邊打開，爲什麽每次都從個微這邊先打開…企微這邊的消息由企微
    /// 優先回答，反之也是一樣」): each pass went left to right, so WeChat, on the left, opened a WeCom group's mark first
    /// (186 opens it only to clear the mark; its lines are WeCom's). Now a WeCom group's mark on WeChat's list (its logo
    /// after the name) waits while WeCom's window shows it marked or open, and for 8 s after WeChat first saw it
    /// (WeCom's own mark may come a moment later); WeChat's own chats go on as before, then WeChat clears the group's
    /// mark once WeCom is done. WeChat's groups never show in WeCom, and two private chats of one name are two people's
    /// talks: each side answers its own.
    private func paneLeaveToWeCom(_ marks: [(name: String, at: CGPoint)], _ rows: [[CandidatePicker.Piece]],
                                  _ state: inout PaneWatchState) -> [(name: String, at: CGPoint)] {
        guard WatchSettings.weworkOn, state.apps.values.contains(.wework) else { return marks }
        let t = now()
        let groups = Set(marks.map { $0.name }.filter { XiaoLanPanes.weComGroupRow(rows, name: $0) })
        state.leftToWeCom = state.leftToWeCom.filter { groups.contains($0.key) }
        var kept: [(name: String, at: CGPoint)] = []
        for m in marks {
            guard groups.contains(m.name) else { kept.append(m); continue }
            let since = state.leftToWeCom[m.name] ?? t
            state.leftToWeCom[m.name] = since
            let open = state.weworkOpen.map { WatchChatOpen.sameChat($0, listName: m.name) } ?? false
            if state.weworkMarked.contains(m.name) || open || t - since < 8 {
                if since == t { DebugLog.write("watch: wechat: \(m.name) is a WeCom group: its mark left to WeCom first") }
                continue
            }
            DebugLog.write("watch: wechat: \(m.name) is a WeCom group, WeCom done with it: opened to clear its mark")
            kept.append(m)
        }
        return kept
    }

    /// 183: WeChat's ＋ menu open (发起群聊, 添加朋友, 扫一扫, 收付款): closed by a click on the title bar's bare left part,
    /// on a pointer seen there; none of its rows is ever clicked.
    /// 184 (Echo 183, 11-26: the title bar's bare spot was never clicked, the pointer unseen there, and the menu stayed
    /// open, tried every 2 s): the list's bare part under its rows (wide, low, an ordinary click), the title bar only
    /// when the list is full.
    private func paneCloseMenu(_ look: PaneLook) async {
        DebugLog.write("watch: a window shows the ＋ menu; closing it (none of its rows clicked)")
        let below = (XiaoLanPanes.entries(look.rows).map { Double($0.box.maxY) }.max() ?? 0.2) + 0.08
        if below < 0.8 {
            _ = await paneTap(CGPoint(x: 0.2, y: below), in: look.rect, wide: 0.1)
        } else {
            _ = await paneTap(XiaoLanPanes.menuCloseSpot, in: look.rect, wide: 0.05)
        }
    }

    /// 183 (user 11-25: "只要有東西發過來，就去看一看，有用的都學下來，沒用的就棄掉"; "所有紅點都要消失"): a news or
    /// team account's red mark: opened, its lines kept in the notices (Documents/notices), never reported or answered,
    /// and back to the list.
    private func paneOpenSystem(_ hit: (name: String, at: CGPoint), _ look: PaneLook, _ app: XiaoLanOrders.App,
                                _ state: inout PaneWatchState) async {
        DebugLog.write("watch: \(app.rawValue): red mark on \(hit.name) (no one's chat); opening it to read")
        guard await paneTap(hit.at, in: look.rect, tall: Self.rowTall) else { return }
        // 184 (Echo 183, 11-26: 行业资讯 opened a news page with a picture for a title; waiting for a chat's title, the
        // watch said "did not open" and left WeCom there, unwatched): opened once the window no longer shows its list;
        // its lines kept when there is a title to read them by; back to the list every time.
        guard let opened = await paneLook(look.side, after: now(), until: { $0.view != .list }), opened.view != .list else {
            DebugLog.write("watch: \(app.rawValue): \(hit.name) did not open")
            return
        }
        if case .chat(let title) = opened.view, let read = WatchOCR.screen(opened.crop, title: title, rows: opened.rows) {
            let lines = read.lines.filter { !$0.mine }.suffix(8)
            ReadLog.append(lines.map { ReadMessage(chat: hit.name, group: false, sender: $0.sender.isEmpty ? hit.name : $0.sender,
                                                   text: $0.text, atMe: false) }, in: ReadLog.noticeFolder)
            DebugLog.write("watch: \(app.rawValue): \(hit.name): \(lines.count) line(s) kept in the notices, not reported")
        } else {
            DebugLog.write("watch: \(app.rawValue): \(hit.name) opened (no title to read it by); back to the list")
        }
        if await paneBack(opened, app.rawValue) { state.systemOpen.remove(look.side) } else { state.systemOpen.insert(look.side) }
        state.quietSince[look.side] = nil
    }

    /// 173 (user 11-25: "這不是兩邊都有嗎"): a chat not in view on the list: its search box, the name typed with 小藍's
    /// keyboard, the result row with that name. Nil (and the search closed) when it is not found.
    /// 184 (Echo 183, 11-26: the box was never clicked and the answer said "搜不到"): `why`, when no search ran.
    private func paneSearch(_ chat: String, _ look: PaneLook) async -> (row: CGPoint?, why: String?) {
        let box = XiaoLanPanes.searchBox(look.rows) ?? CGPoint(x: 0.5, y: 0.11)
        DebugLog.write("watch: \(chat) is not in view on the list; searching for it")
        guard await paneTap(box, in: look.rect) else { return (nil, "没点到搜索框") }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard await typeWithLanAgentKeyboard(chat, enter: false) else {
            DebugLog.write("watch: search: 小藍's keyboard did not type the name")
            await paneCloseSearch(look.side)
            return (nil, "搜索框里小蓝输入法没有打出字")
        }
        let found = await paneLook(look.side, after: now(), tries: 5) { XiaoLanPanes.searchResult(chat, $0.rows) != nil }
        if let f = found, let row = XiaoLanPanes.searchResult(chat, f.rows) { return (row, nil) }
        DebugLog.write("watch: search: \(chat) is not among the results")
        await paneCloseSearch(look.side)
        return (nil, nil)
    }

    private func paneCloseSearch(_ side: Int) async {
        guard let l = await paneLooks().first(where: { $0.side == side }) else { return }
        if let cancel = XiaoLanPanes.cancelButton(l.rows) { _ = await paneTap(cancel, in: l.rect, wide: 0.03) }
    }

    /// The new messages of the chat in a window, reported to that app's server. Returns how many were new.
    @discardableResult
    /// 184 (C12): `markSender`, who the list's preview said wrote the line its red mark was for.
    /// 187: `markPreview`, that preview as read (what the mark was for, when nothing new is read).
    /// Returns how many messages were reported; -1 when the window could not be read (188: the caller looks again).
    /// `lastTry` (188, B45): a window opened by its red mark that still cannot be read reports its preview's line.
    private func paneRead(_ app: XiaoLanOrders.App, _ look: PaneLook, title: String, fromMark: Bool, markSender: String? = nil,
                          markPreview: String? = nil, lastTry: Bool = true, _ state: inout PaneWatchState) -> Int {
        // 187: under a sheet of another chat the title is this chat's, the lines are the other's: not read.
        if let px = WatchOCR.Pixels(look.crop), XiaoLanPanes.sheetClose(px) != nil {
            DebugLog.write("watch: \(app.rawValue): \(title): another chat open over it as a sheet; not read")
            return 0
        }
        // 188 (B45, Echo 187, 11-27: 测试群's mark opened, the owner's 「11」 and then 「1」 at the bottom in plain view, a
        // banner of 企微测试群 coming in over the top; nothing read, nothing logged, the mark gone, the line lost, and
        // WeCom's later 「12」 answered first): a window not read is said, kept, and looked at again; opened by its mark
        // and still not read on the last try, the mark's preview is its line.
        let screenRead = WatchOCR.screen(look.crop, title: title, rows: look.rows)  // 182: read once
        if screenRead != nil, let bp = WatchOCR.bannerPiece(Array(look.rows.joined()), px: WatchOCR.Pixels(look.crop)) {
            DebugLog.write("watch: \(app.rawValue): \(title): a banner over its top (「\(bp.text)」); read under its band")
        }
        if screenRead == nil {
            WatchChatOpen.keepFrame(look.crop)
            let bp = WatchOCR.bannerPiece(Array(look.rows.joined()), px: WatchOCR.Pixels(look.crop))
            let why = bp.map { "a banner over its top: 「\($0.text)」 at y \(String(format: "%.3f", Double($0.box.midY)))" } ?? "no picture"
            guard fromMark, lastTry, markPreview != nil else {
                DebugLog.write("watch: \(app.rawValue): \(title): the window could not be read (\(why))\(fromMark && !lastTry ? "; looking again" : "")")
                return -1
            }
            DebugLog.write("watch: \(app.rawValue): \(title): the window still could not be read; its red mark's preview is taken")
        }
        let read = screenRead ?? WatchReport.Screen(title: WatchOCR.titled(title).name, group: markSender != nil, lines: [])
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
        // 184 (Echo 183, 11-26: "no overlap … left out" every pass: after a send the keyboard went down and older lines
        // came in at the top, so the history's end was no longer where the screen starts): the history's last lines
        // are looked for anywhere on the screen first (what follows them is new); either way the history becomes this
        // screen, so the next look goes on from it.
        var rebase = false
        if let before, !before.isEmpty, !lines.isEmpty, fresh.count == lines.count {
            rebase = true
            if let after = XiaoLanSelf.afterAnchor(lines, history: before) {
                fresh = after
            } else if case let known = XiaoLanSelf.seenInApp(state.seen, app: app.rawValue, chat: key), !known.isEmpty {
                // 185 (B18, Echo 184, 11-26: 「【第三方测试】群消息1」, read in 测试群, came again under 企微测试群 when one
                // window's title was taken for the other's): what was read in any chat of this app counts.
                let unseen = XiaoLanSelf.unseen(lines, known: known)  // 187 (B38); 189 (N21): only after the last known or mine
                if unseen.count < lines.count {
                    DebugLog.write("watch: \(app.rawValue): \(name): no overlap with what was read; \(lines.count - unseen.count) line(s) read before left out")
                    fresh = unseen
                }
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
        // 187: a red mark with nothing of anyone's new read: the line its preview shows (WatchReport.markedLine); what
        // was read is logged and the window kept in diagnostics, so the cause can be seen.
        if fromMark, let marked = WatchReport.markedLine(lines, fresh: fresh, preview: markPreview, sender: markSender) {
            let tail = lines.suffix(3).map { "\($0.mine ? "mine" : $0.sender)「\($0.text)」" }.joined(separator: " ")
            DebugLog.write("watch: \(app.rawValue): \(name): nothing of anyone's new under its red mark (\(fresh.count) new, \(before == nil ? "no" : "a") history, last read \(tail)); the preview's line taken: \(marked.text)")
            WatchChatOpen.keepFrame(look.crop)
            fresh.append(marked)
        }
        if screenRead != nil {  // 188: a window not read leaves the history as it was
            state.history[key] = rebase ? Array(lines.suffix(20)) : WatchReport.remember(fresh, screen: lines, history: before)
            if state.history[key] != before { PaneHistory.save(state.history) }  // 183
        }
        let names = WatchSettings.myNames
        // 181 (user 11-25: "兩個號在一個群里…就相當于是同一個人，就不用回復了"; "應該點開把那個紅點給點掉，而不是應該回復"):
        // the owner's own lines here are what this side's other account can see; a line on this side that is one of the
        // owner's on the other (sent by 小藍 or read there as mine) is from the owner's other account: opened, never
        // reported, and its sender learned.
        let t = now()
        state.sent.removeAll { t - $0.at > XiaoLanSelf.sentWindow }
        for line in fresh where line.mine { state.sent.append(XiaoLanSelf.Sent(app: app, chat: name, text: line.text, at: t)) }
        if state.sent.count > 200 { state.sent.removeFirst(state.sent.count - 200) }  // 183: was 60
        // 184 (C12; Echo 183, 11-26: a group line from a third account dropped, "no sender read", as iPad WeChat showed
        // no name over it): a group line whose sender reads as the group's name is not dropped: the newest such line is
        // the preview's writer when its mark opened the chat, the others go without a name. Lines of the quick bar's
        // buttons are still no one's (and C14 drops the bar itself).
        var nameless = 0
        if read.group {
            let unnamed = fresh.indices.filter { !fresh[$0].mine && XiaoLanSelf.noSender(fresh[$0].sender, chat: name) && !XiaoLanSelf.isButton(fresh[$0].sender) }
            for i in unnamed { fresh[i].sender = (i == unnamed.last ? markSender : nil) ?? "" }
            nameless = unnamed.filter { fresh[$0].sender.isEmpty }.count
            if !unnamed.isEmpty, let s = markSender {
                DebugLog.write("watch: \(app.rawValue): \(name): sender not read over the line; the list's preview says \(s)")
            }
        }
        var own: [String] = [], unread: [String] = []
        let echoes = state.echoes[key] ?? []
        var echoed = 0
        let others = fresh.filter { line in
            guard !line.mine else { return false }
            if XiaoLanMediaFind.isEcho(line.text, of: echoes) { echoed += 1; return false }  // 188
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
            DebugLog.write("watch: \(app.rawValue): \(name): \(unread.count) line(s) of the app's buttons: not reported")
        }
        if echoed > 0 { DebugLog.write("watch: \(app.rawValue): \(name): \(echoed) line(s) of a voice note's words, reported with it: not again") }
        if nameless > 0 { DebugLog.write("watch: \(app.rawValue): \(name): \(nameless) line(s) with no sender read: reported without a name") }
        if !own.isEmpty {
            DebugLog.write("watch: \(app.rawValue): \(name): \(own.count) line(s) from the owner's other account (\(Set(own).sorted().joined(separator: "、"))): opened, not reported")
        }
        var messages = others.map { line in
            ReadMessage(chat: name, group: read.group, sender: line.sender, text: line.text,
                        atMe: XiaoLanMediaFind.atMe(line.text, names: names))  // 188 (B29): 「＠」 as OCR reads it on WeChat
        }
        if before == nil && !fromMark { DebugLog.write("watch: \(app.rawValue): \(name): history starts here (\(lines.count) line(s))") }
        // 186 (user 11-26: "企微群就以企微來回…個微在企微群裡面，看一下就行了，主要還是面向企微"): a WeCom group — its
        // logo after the title on WeChat's side — is WeCom's to report and answer while WeCom is watched too; WeChat only
        // opens it (its mark cleared, its lines kept as read).
        if app == .wechat, WatchSettings.weworkOn, read.group, XiaoLanPanes.weComGroupTitle(title), !messages.isEmpty {
            DebugLog.write("watch: wechat: \(name) is a WeCom group: \(messages.count) line(s) left to WeCom; opened, not reported")
            return 0
        }
        // 188 (user 11-27: links, pictures, videos, files and voice notes opened and looked at): a line that is one of
        // them (its kind on) is reported after it is looked at (paneMediaRun, right after this read); one shown only by
        // the red mark's preview (「[语音] 7"」: a voice note or a video has no words of its own to read) too.
        var jobs: [MediaJob] = []
        let kinds = messages.map { XiaoLanMediaFind.kind(of: $0.text) }
        var plain: [ReadMessage] = []
        for (i, m) in messages.enumerated() {
            guard let kind = kinds[i], MediaSettings.on(kind) else { plain.append(m); continue }
            let rank = kinds[(i + 1)...].filter { $0 == kind }.count  // the newest of its kind is 0
            jobs.append(MediaJob(app: app, side: look.side, chat: name, group: read.group, sender: m.sender, kind: kind,
                                 text: m.text, atMe: m.atMe, rank: rank))
        }
        messages = plain
        let weComGroup = app == .wechat && WatchSettings.weworkOn && read.group && XiaoLanPanes.weComGroupTitle(title)
        if fromMark, own.isEmpty, !weComGroup, let preview = markPreview, let kind = XiaoLanMediaFind.tag(preview), MediaSettings.on(kind),
           !jobs.contains(where: { $0.kind == kind }),
           !(read.group && (markSender.map { XiaoLanSelf.isOwner($0, names: names + XiaoLanSelf.learned) } ?? false)) {
            jobs.append(MediaJob(app: app, side: look.side, chat: name, group: read.group, sender: markSender ?? "", kind: kind,
                                 text: preview, atMe: false))
        }
        if !jobs.isEmpty {
            state.media += jobs
            DebugLog.write("watch: \(app.rawValue): \(name): \(jobs.map { $0.kind.rawValue }.joined(separator: ", ")) to open and look at")
        }
        guard !messages.isEmpty else {
            // 188 (B45): a red mark that gave nothing to report, and no line said why above, is said and kept
            if fromMark && own.isEmpty && unread.isEmpty && jobs.isEmpty {
                let tail = lines.suffix(3).map { "\($0.mine ? "mine" : $0.sender)「\($0.text)」" }.joined(separator: " ")
                DebugLog.write("watch: \(app.rawValue): \(name): opened by its red mark, nothing to report (preview \(markPreview.map { "「\($0)」" } ?? "not read"), last read \(tail))")
                WatchChatOpen.keepFrame(look.crop)
            }
            return jobs.count
        }
        ReadLog.append(messages)
        watchRead += messages.count
        (app == .wework ? weworkTool : chatTool).report(messages)
        DebugLog.write("watch: \(app.rawValue): \(name): \(messages.count) new message(s) reported")
        return messages.count + jobs.count
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
        let typedBefore = state.typed
        let sent = await paneSend(order.text, to: order.chat, app: order.app, quote: order.quote, &state)
        if !sent.ok {
            DebugLog.write("watch: \(order.app.rawValue): the message to \(order.chat) not sent: \(sent.why)")  // 189 (N16)
            // 189 (N16, Echo 188, 11-27 11:36: 测试群's QA reply failed before a word was typed and was dropped; the line was
            // asked again 14 s later): a QA reply not sent with nothing typed goes once more, first (nothing can go twice)
            if ChatToolLink.isQA(order.messageId), state.typed == typedBefore, state.retried.insert(order.key).inserted {
                DebugLog.write("watch: nothing was typed for it; the reply to \(order.chat) goes once more, first")
                try? await Task.sleep(nanoseconds: 800_000_000)
                link.retry(order)
                return
            }
        }
        state.retried.remove(order.key)
        link.finish(order, ok: sent.ok, reason: sent.ok ? (order.at.isEmpty ? "" : ChatToolLink.reasonNoAt) : sent.why)
        // 189 (speed; user 11-27: the second of two replies to 企微测试群 began 4 s after the first was sent): the next order
        // for the same chat starts from the window as it showed this line sent, no new look of both windows
        if sent.ok, let shown = sent.shown, link.pending.contains(where: { $0.app == order.app && $0.chat == order.chat }) {
            state.lastShown = (app: order.app, chat: order.chat, look: shown, at: now())
        }
        // 183 (Echo 182 overnight, 11-26: the answer waited 1.5–2.5 s for the keyboard to go down): answered first.
        if let shown = sent.shown { await paneDismissKeyboard(shown) }
    }

    /// Open `chat` in its app's window (already open, or a row on its list), type `text` and send it. `shown`: the
    /// window showing the line sent (its keyboard is put down after the answer).
    private func paneSend(_ text: String, to chat: String, app: XiaoLanOrders.App, quote: String = "",
                          _ state: inout PaneWatchState) async -> (ok: Bool, why: String, shown: PaneLook?) {
        let appName = app == .wework ? "企业微信" : "微信"
        // 189 (speed): the window just seen showing my line in this chat, the order before being for it too (the field
        // is still found and checked on a new look below)
        var found: PaneLook?
        if let s = state.lastShown, s.app == app, s.chat == chat, now() - s.at < 4 {
            found = s.look
        } else {
            found = await paneFind(app, &state)
        }
        state.lastShown = nil
        guard var look = found else {
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
        let openHere = state.openChat  // 189 (N20)
        func isChat(_ l: PaneLook) -> Bool {
            guard case .chat(let t) = l.view else { return false }
            if WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: chat) { return true }
            // 189 (N20): a banner over the window's top: the chat under it is the one last read there without one
            if let known = openHere[l.side], WatchChatOpen.sameChat(WatchOCR.titled(known).name, listName: chat),
               WatchOCR.bannerShown(Array(l.rows.joined()), px: WatchOCR.Pixels(l.crop)) { return true }
            return false
        }
        var openedHere = false, banded = false
        // 186 (B24): whether the list's preview of this chat already showed the text before it was sent (an older line
        // alike), nil when the chat was not opened from its list here.
        var shownBefore: Bool?
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
            shownBefore = XiaoLanPanes.previewText(look.rows, of: chat).map { XiaoLanSelf.previewShowsSent($0, text) }
            var target = XiaoLanPanes.entries(look.rows).first { WatchChatOpen.sameChat(chat, listName: $0.name) }
                .map { CGPoint(x: 0.5, y: $0.box.midY) }
            var searchWhy: String?
            let inList = target != nil
            if target == nil { (target, searchWhy) = await paneSearch(chat, look) }  // not in view: the list's search box
            if target == nil, let why = searchWhy { return (false, "\(appName)\(why)，没有搜「\(chat)」", nil) }
            guard var row = target else { return (false, "\(appName)里搜不到「\(chat)」", nil) }
            let keyboardBefore = keyboardBridge.onScreen()
            // 183 (Echo 182 overnight, 11-26: each look whole, ~1 s): the chat told by its title band alone.
            // 183 (11-26: a click right after the pointer arrived did nothing, twice; 182's 5j: the list moved between
            // the look and the click, and another chat opened): not open, the row once more: still the list, the same
            // spot; another chat, back to the list and its row again.
            var opened: PaneLook?
            for attempt in 0..<2 {
                guard await paneTap(row, in: look.rect, tall: Self.rowTall) else { return (false, ChatToolLink.reasonNotSent, nil) }
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
            guard let open = opened, isChat(open) else {
                // 187 (Echo 186, 11-27: WeCom's search for 不存在的群187 was left open, 小藍 up over both windows, and
                // the watch stood still for minutes): a row found by the search that did not open closes the search.
                if !inList { await paneCloseSearch(look.side) }
                return (false, "\(appName)里没有打开「\(chat)」", nil)
            }
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
        // 187 (Echo 186, 11-27 00:33 首爾: three replies for 测试群 typed into 企微测试群's sheet over it, sent from WeChat):
        // a sheet of another chat over this one: its field is the other chat's. Closed by its ✕; nothing typed.
        if let spx = WatchOCR.Pixels(look.crop), let close = XiaoLanPanes.sheetClose(spx) {
            DebugLog.write("watch: \(app.rawValue): another chat open over \(chat) as a sheet; closed by its ✕, not sent")
            _ = await paneSeenTap(XiaoLanPanes.onScreen(close, in: look.rect), half: (0.015, 0.012))
            return (false, "\(appName)里另一个聊天浮在「\(chat)」上面（点到了横幅），已关掉，这次没有发", nil)
        }
        // 183 (Echo 182 overnight, 11-26: 小藍's keyboard came up with the chat, and its field was tapped anyway, ~2.3 s,
        // often at an estimate): the keyboard down before the row's tap and up after it opened its chat here belongs to
        // this window's field (180's case, the keyboard up from the other window, is still tapped).
        // 188 night (Echo 187–188, 11-26/27 logs: WeCom raised no keyboard on opening a chat in 83 sends of 83, WeChat in 15
        // of 17): WeCom's field is tapped at once, no 0.6 s wait for a keyboard that does not come.
        if !focused, openedHere, app == .wechat, await smallKeyboard(up: true, within: 0.6) {
            DebugLog.write("watch: \(app.rawValue): the keyboard came up with \(chat); its field not tapped")
            focused = true
        }
        // 188 (user 11-27: 「給別人回消息要引用那條消息回復」): the line answered (the order's originalContent) quoted first;
        // 引用 puts the caret in the field (WeChat: 小藍's keyboard up; WeCom: 简体拼音, switched to 小藍 below). Not
        // quoted (the line not on the window, no 引用 in its menu): the reply goes plain, as before.
        var quoted = false
        if !quote.isEmpty, MediaSettings.quoteOn {
            quoted = await paneQuote(quote, look, app.rawValue)
            if quoted {
                focused = true
                if let again = await paneLooks(after: now(), side: look.side).first(where: { $0.side == look.side }) {
                    (look, low) = (again, again.rows)
                }
            }
        }
        // The input field: the white box at the bottom of the window (WeCom's row of buttons above it is left alone).
        // 180 (Echo 178, 11-25): always tapped, keyboard up or not. The keyboard is the whole screen's: up from a send in
        // WeCom, a reply meant for WeChat was typed into WeCom's field and went out there, as the WeCom account.
        if !focused {
            // 183 (Echo 182, 11-26: 简体拼音 over the chat, a white key taken for the field and a letter typed): with a
            // system keyboard up the field is looked for above it.
            var keys = XiaoLanPanes.keyboardTop(low)
            // 185 (B22, Echo 184, 11-26: on the iPad the system keyboard covers the windows' bottoms, the input bar under
            // it; "the field above the keyboard" was a message bubble, clicked twice; a voice note, a picture or a link
            // there would have played or opened): a system keyboard over this window is put down first (switched to
            // 小藍, which puts itself down), then the field at the bottom is clicked as ever. Not down: nothing clicked.
            if keys != nil, !CandidatePicker.ourKeyboardShown(rows: low) {
                DebugLog.write("watch: \(app.rawValue): a system keyboard over \(chat); switched to 小藍 and put down first")
                if await showLanAgentKeyboard(), await keyboardBridge.type("", enter: false, within: 2, dismiss: true),
                   await smallKeyboard(up: false, within: 1.5),
                   let again = await paneLooks(after: now(), side: look.side).first(where: { $0.side == look.side }) {
                    (look, low) = (again, again.rows)
                    keys = XiaoLanPanes.keyboardTop(low)
                }
                guard keys == nil else { return (false, "\(appName)的系统键盘盖住了输入框，没能收起来（没有点）", nil) }
            }
            guard let px = WatchOCR.Pixels(look.crop), var field = XiaoLanPanes.inputField(px, above: keys.map { $0 - 0.005 } ?? 1) else {
                return (false, "\(appName)里没找到输入框", nil)
            }
            // 186 (B23, Echo 185, 11-26: the field was found on a look taken while a keyboard was still going down —
            // after 小藍 put the system keyboard down, and right after a send — and clicked where it had been: a message
            // bubble twice, then a voice note and a .docx above the bar, which opened): found again on a new look before
            // the click, at the same height; moved, the new place is checked once more; never still, nothing is clicked.
            var still = false
            for _ in 0..<3 {
                // 188 night: only the window's lower half is read (the field, the quick bar and any keyboard are there;
                // its picture is whole): the check stays, at about half the reading (0 moves found in 83 WeCom sends)
                guard let again = await paneLook(look.side, after: now(), tries: 2, band: (0.45, 1), until: { _ in true }),
                      let px2 = WatchOCR.Pixels(again.crop) else { break }
                let keys2 = XiaoLanPanes.keyboardTop(again.rows)
                if keys2 != nil, !CandidatePicker.ourKeyboardShown(rows: again.rows) {
                    DebugLog.write("watch: \(app.rawValue): a system keyboard over \(chat) again before the field's click; not clicked")
                    return (false, "\(appName)的系统键盘又盖住了输入框，没有点", nil)
                }
                guard let f2 = XiaoLanPanes.inputField(px2, above: keys2.map { $0 - 0.005 } ?? 1) else { break }
                if abs(Double(f2.y - field.y)) <= 0.01 { still = true; break }
                DebugLog.write("watch: \(app.rawValue): the field moved (\(String(format: "%.3f", Double(field.y))) → \(String(format: "%.3f", Double(f2.y)))); looked at again")
                (field, look, low, keys) = (f2, again, again.rows, keys2)
            }
            guard still else { return (false, "\(appName)的输入框位置还在变（键盘在收起或弹出），没有点", nil) }
            // 187 (B23, Echo 186, 11-26: with no keyboard up, a "field" half way up the chat — a white bubble — was
            // clicked twice): with no keyboard of any kind seen, the field is at the window's bottom; higher up, not clicked.
            if keys == nil, !CandidatePicker.ourKeyboardShown(rows: low), !keyboardBridge.onScreen(), Double(field.y) < 0.8 {
                DebugLog.write("watch: \(app.rawValue): a \"field\" at \(String(format: "%.3f", Double(field.y))) with no keyboard up is not the bar's; not clicked")
                return (false, "\(appName)的输入框没找准（找到的在聊天中间），没有点", nil)
            }
            // 186 (B25, Echo 185, 11-26: WeCom's quick bar was taken for the field and 发起收款 clicked, its 对外收款 page
            // opened; the second click landed just under 申请开通对外收款): the field is under the quick bar; a "field" on
            // the bar or over it is not clicked.
            if let bar = XiaoLanPanes.quickBarBottom(low), Double(field.y) <= bar + 0.004 {
                DebugLog.write("watch: \(app.rawValue): the field found at \(String(format: "%.3f", Double(field.y))) is on or over the quick bar (bottom \(String(format: "%.3f", bar))); not clicked")
                return (false, "\(appName)的输入框没找准（找到的是快捷栏），没有点", nil)
            }
            // 183 (Echo 182 overnight, 11-26: WeCom's field is ~0.03 tall; the pointer 0.015 low counted as on it, the
            // click missed and the keyboard was waited for 5 s): within 0.007; no keyboard after it, once more.
            // 188 (B46, Echo 187, 11-27: twice the first stop 0.008 over the field's middle was corrected, the pointer, an
            // I-beam over the field, never moved up or down, "does not move", found again and clicked there: the keyboard
            // came and the reply went): within 0.010 (the field ~0.03 tall; 183's miss was 0.015 low).
            guard await paneTap(field, in: look.rect, wide: 0.15, tall: Self.fieldTall) else { return (false, ChatToolLink.reasonNotSent, nil) }
            // 187 (B34, Echo 186, 11-26: WeCom's 简体拼音 came up after 0.8 s, unseen by the check, and the second click
            // landed on its keys): 1.5 s for 小藍; then a new look, and a keyboard of any kind on it (the iPad's pinyin
            // keys read "1 q") means up: no second click.
            if keys == nil, !(await smallKeyboard(up: true, within: 1.5)),
               let frame = feed.frame, !(await CandidatePicker.keyboardUpOffMain(in: frame)) {
                if let again = await paneLook(look.side, after: now(), tries: 1, until: { _ in true }),
                   XiaoLanPanes.keyboardTop(again.rows) != nil || CandidatePicker.ourKeyboardShown(rows: again.rows) {
                    DebugLog.write("watch: \(app.rawValue): a keyboard came up late after the field's tap; not clicked again")
                } else {
                    DebugLog.write("watch: \(app.rawValue): no keyboard after the field's tap; once more")
                    _ = await paneTap(field, in: look.rect, wide: 0.15, tall: Self.fieldTall)
                }
            }
        }
        try? await Task.sleep(nanoseconds: 250_000_000)  // 182: was 0.4 s
        // 188: quoted on WeChat the field is empty, and a backspace in an empty field takes the quote off (WeCom's 「@名字」
        // is cleared as any text: its quote stays until a second backspace, measured 11-27).
        if !(quoted && app == .wechat) {
            do {
                try await pointer.key("cmd+a")
                try await pointer.key("backspace")
            } catch {
                DebugLog.write("watch: clearing the input field failed: \(error.localizedDescription)")
            }
        }
        // 184 (Echo 183, 11-26: the text, a 0.6 s wait, 0.2 s more, then the return as a job of its own, ~1 s): the
        // text and its return in one job of 小藍's keyboard, which puts them into the field in order (the wait was for
        // the board's Return key, a separate path, 11-08).
        guard await showLanAgentKeyboard() else {
            return (false, "小蓝输入法没有打出字（请在\(appName)里把键盘切成小蓝）", nil)
        }
        // 185 (B7/B8/B11): true only when the field held exactly this text and emptied after the return (小藍's own
        // check); then 小藍 puts itself down (B10). Not sent: the field is emptied here, no draft is left (B21).
        state.typed += 1  // 189 (N16): from here a failed order may have typed something; it is not sent again
        let returned = await keyboardBridge.type(text, enter: true, within: 5, dismiss: true)
        guard returned else {
            // 188 (B41, Echo 187, 11-27: a WeCom private reply went out — its list preview showed it — but was reported
            // not sent): my newest line showing the text counts as sent before anything is cleared.
            let sig = XiaoLanSelf.sendSignature(text)
            if let l = await paneLook(look.side, after: now(), tries: 2, until: { _ in true }), case .chat(let t) = l.view,
               let r = WatchOCR.screen(l.crop, title: t, rows: l.rows, banner: false),
               r.lines.last(where: \.mine).map({ XiaoLanSelf.shows($0.text, signature: sig, of: text) }) == true {
                DebugLog.write("watch: \(app.rawValue): \(chat): 小藍 said not sent, but my newest line shows it: sent")
                state.sent.append(XiaoLanSelf.Sent(app: app, chat: chat, text: text, at: now()))
                return (true, "", l)
            }
            DebugLog.write("watch: \(app.rawValue): \(chat): not sent (the field held other words, or the return made a new line); emptying the field")
            try? await pointer.key("cmd+a")
            try? await pointer.key("backspace")
            return (false, "小蓝输入法没有发送成功（输入框里有别的字，或发送键变成换行），已清空输入框", nil)
        }
        DebugLog.write("watch: \(app.rawValue): typed into \(chat); sent (the field emptied after the return)")
        // Sent when my newest line now shows the text (182: read from the words already read for the check).
        // 185 (B8, Echo 184, 11-26: the first 6 characters, 「【小蓝测试】」, matched 183's lines and nothing sent was
        // "sent" three times; a customer's replies often begin alike): the text's end, not its beginning.
        let tail = XiaoLanSelf.sendSignature(text)
        // 185 (B13, Echo 184, 11-26: a screen read with the keyboard over its bottom became the chat's history, and the
        // line under the keyboard was "new" later): the keyboard (put down by 小藍 after the send) gone first.
        _ = await smallKeyboard(up: false, within: 1.0)
        func sentShown(_ l: PaneLook) -> WatchReport.Screen? {
            guard case .chat(let t) = l.view, let r = WatchOCR.screen(l.crop, title: t, rows: l.rows, banner: false),
                  r.lines.last(where: \.mine).map({ XiaoLanSelf.shows($0.text, signature: tail, of: text) }) == true else { return nil }
            return r
        }
        let after = await paneLook(look.side, after: now(), tries: 4) { sentShown($0) != nil }
        if after.flatMap(sentShown) == nil {
            // 186 (B24, Echo 185, 11-26: six of nine sends went out — on the screen and in the list's preview — but were
            // reported failed, every one a one-line text; the only one read was a long one): what was read is logged, and
            // back on the list the chat's preview showing the text counts as seen on the screen (an older line alike,
            // shown there before the send, does not).
            let readLast: String = {
                guard let a = after else { return "no look" }
                guard case .chat(let t) = a.view, let r = WatchOCR.screen(a.crop, title: t, rows: a.rows, banner: false) else { return "\(a.view)" }
                return r.lines.suffix(2).map { "\($0.mine ? "mine" : "not mine")「\($0.text)」" }.joined(separator: ", ")
            }()
            DebugLog.write("watch: \(app.rawValue): \(chat): sent per the keyboard; the new line not read on the screen (wanted …\(tail); read \(readLast))")
            // 187 (Echo 186, 11-26: the newest line was never read, though a still frame taken later showed it over the
            // bar): the window as it was read is kept in Documents/diagnostics, to be looked at.
            WatchChatOpen.keepFrame(after?.crop)
            // 188 (Echo 187, 11-27: a send that went out was reported failed with nothing logged after the back arrow):
            // which step did not show it is logged.
            var previewRead = "not looked at (shown before, or too short)"
            if shownBefore != true, shownBefore == false || text.filter({ !$0.isWhitespace }).count >= 6 {
                if await paneBack(after ?? look, app.rawValue) {
                    if let list = await paneLook(look.side, after: now(), tries: 6, until: { $0.view == .list }), list.view == .list {
                        let preview = XiaoLanPanes.previewText(list.rows, of: chat)
                        if let preview, XiaoLanSelf.previewShowsSent(preview, text) {
                            DebugLog.write("watch: \(app.rawValue): \(chat): sent; the list's preview shows it (\(preview))")
                            state.sent.append(XiaoLanSelf.Sent(app: app, chat: chat, text: text, at: now()))  // 181
                            return (true, "", nil)
                        }
                        previewRead = preview.map { "read 「\($0)」" } ?? "has no row of it"
                    } else { previewRead = "not seen (no list after the back arrow)" }
                } else { previewRead = "not seen (the back arrow failed)" }
            }
            DebugLog.write("watch: \(app.rawValue): \(chat): not counted as sent: the list's preview \(previewRead)")
        }
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
        // 185 (B10, Echo 184, 11-26: two taps on WeChat's chat background, the keyboard still up, "no bare chat
        // background to tap"): 小藍's own keyboard puts itself down first; the taps only for another keyboard.
        if keyboardBridge.onScreen() {
            if await keyboardBridge.type("", enter: false, within: 1.5, dismiss: true), await smallKeyboard(up: false, within: 1.0) {
                return
            }
            DebugLog.write("watch: 小藍's keyboard did not put itself down; a tap on the chat instead")
        }
        // 186 (O2, Echo 185, 11-26: after each WeCom send, 小藍's keyboard already down, a "bare" spot by the bubbles was
        // clicked all the same; a picture or a video there would open): with no keyboard seen, nothing is tapped.
        if XiaoLanPanes.keyboardTop(l.rows) == nil, !CandidatePicker.ourKeyboardShown(rows: l.rows),
           let frame = feed.frame, !(await CandidatePicker.keyboardUpOffMain(in: frame)) { return }
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
        // 186 (B31, Echo 185, 11-26: the drag opened 腾讯新闻 and a red picture on its page was taken for 删除): the red
        // button counts only on the list.
        guard let shown = await paneLook(look.side, after: now(), until: { $0.view == .list && button($0) != nil }),
              shown.view == .list, let red = button(shown) else {
            await paneRetract(look.side)  // 183
            return (false, "「\(chat)」那一行没有滑出红色的删除（系统账号、公众号可能没有，或滑到别的行；已收回）")
        }
        DebugLog.write("watch: \(app.rawValue): deleting \(chat)")
        guard await paneTap(red, in: look.rect, wide: 0.04) else { return (false, "没点到「\(chat)」的删除") }
        // 187 (B36, Echo 186, 11-26: 删除并清空记录 was up, the slid row's name cut to 「文件传输助」, and "deleted" was said
        // without it): the confirmation is looked for first, whatever the row shows.
        var after = await paneLook(look.side, after: now(), tries: 3) {
            XiaoLanPanes.confirmDelete($0.rows) != nil || XiaoLanPanes.gone(chat, $0.rows)
        }
        if let a = after, let confirm = XiaoLanPanes.confirmDelete(a.rows) {
            DebugLog.write("watch: \(app.rawValue): the confirmation (\(app == .wework ? "the alert's 删除" : "清空记录同时不显示聊天"))")
            _ = await paneTap(confirm, in: look.rect, wide: 0.04)
            after = await paneLook(look.side, after: now(), tries: 3) { XiaoLanPanes.gone(chat, $0.rows) }
        }
        // 186 (B31: "deleted" was said with 腾讯新闻's own page open, its name nowhere on a list): gone from the list, the
        // list itself on the screen.
        guard let end = after, end.view == .list, XiaoLanPanes.gone(chat, end.rows) else {
            if let end = after, end.view != .list {
                DebugLog.write("watch: \(app.rawValue): delete \(chat): no list on the screen after it; not taken as deleted")
                return (false, "删「\(chat)」后\(appName)不在会话列表上，没当作删掉")
            }
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
