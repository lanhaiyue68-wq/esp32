import UIKit

/// 197 (user 11-28: group orders 「寫成固定步驟」; N90: the model's own clicks in a split window fell ~2 % low, on the
/// next button, and 206 never got past WeChat's ＋): create (206), change (207) and dissolve (219) a group by fixed
/// steps in its app's window, as the user's screens were walked by hand on Echo 195, 11-28 02:03–02:35 (docs/
/// shots-2026-11-28-group, w = WeChat, q = WeCom, b = WeChat with curves):
/// - ＋ → 发起群聊 → each member searched by name (小藍's keyboard), the first result named exactly so that the 完成
///   count then counts (same names: WeChat lists 蓝海乐 twice; one already picked is grey and does not count) → 完成
///   (WeChat's at the top right, WeCom's over the keyboard) → the new group's chat opens.
/// - ··· → the group's page: WeChat's rows 群聊名称 / 群公告 / 群管理, WeCom's name line at the top (✎) and 群公告 /
///   群管理; the member grid ends with a ＋ and a − tile that have no words (`tiles`).
/// - 群聊名称 → its page, the field focused → 确定. 群公告 → the editor (an announcement already there: its page, 编辑) →
///   完成 / 发布 → 「发布」 in the alert; WeChat then shows the chat, WeCom the announcement (back once).
/// - − → 移出成员 → the member searched and picked → 完成 / 确定 (WeChat asks 「移出」 again; WeCom does not).
/// - ＋ → 选择联系人 / 添加群成员 → as when creating → 完成 / 确定 (neither asks).
/// - 群管理 → 解散该群聊 (WeChat: 「解散」 in the sheet under it; the chat then says 你已解散此群) / 解散群聊 (WeCom: 「解散」
///   in the alert; back on the list with 你已经解散群聊).
enum XiaoLanGroups {
    typealias Piece = CandidatePicker.Piece

    /// The list's ＋ and a chat's ••• (window fractions, measured on the iPad 11-28).
    static func plus(_ app: XiaoLanOrders.App) -> CGPoint { app == .wework ? CGPoint(x: 0.924, y: 0.059) : CGPoint(x: 0.927, y: 0.064) }
    static func more(_ app: XiaoLanOrders.App) -> CGPoint { app == .wework ? CGPoint(x: 0.922, y: 0.059) : CGPoint(x: 0.933, y: 0.059) }

    static func bare(_ s: String) -> String { s.filter { !$0.isWhitespace } }

    /// The topmost piece within `band` whose words (spaces dropped) contain one of `words` (are one, `exact`).
    static func find(_ rows: [[Piece]], _ words: [String], exact: Bool = false, band: ClosedRange<Double> = 0...1) -> CGPoint? {
        rows.joined()
            .filter { p in
                let t = bare(p.text)
                return band.contains(Double(p.box.midY)) && words.contains { exact ? t == $0 : t.contains($0) }
            }
            .min { $0.box.midY < $1.box.midY }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// Where 小藍's bar or a keyboard starts (1: none): nothing at or under it is the page's.
    static func keyboardFloor(_ rows: [[Piece]]) -> Double {
        let bar = rows.joined().filter { p in ["已填入", "输入法", "輸入法"].contains { p.text.contains($0) } }.map { Double($0.box.minY) }.min()
        return min(bar ?? 1, XiaoLanPanes.keyboardTop(rows) ?? 1, 1)
    }

    /// A picker's 完成 / 确定 and the number on it (「完成（2）」「完成(2)」「完成·2」「完成・2」「确定·1」; 0 bare), above any
    /// keyboard (小藍's own keys read 完成 too).
    static func doneButton(_ rows: [[Piece]]) -> (at: CGPoint, count: Int)? {
        let floor = keyboardFloor(rows)
        let marks: Set<Character> = ["（", "(", ")", "）", "·", "・", "•", ".", "-", "‧"]
        return rows.joined().compactMap { p -> (at: CGPoint, count: Int, y: Double)? in
            let t = bare(p.text)
            guard Double(p.box.maxY) <= floor, let word = ["完成", "确定", "確定"].first(where: { t.hasPrefix($0) }) else { return nil }
            let rest = t.dropFirst(word.count)
            let digits = rest.filter { $0.isASCII && $0.isNumber }
            guard rest.count <= 6, rest.allSatisfy({ ($0.isASCII && $0.isNumber) || marks.contains($0) }) else { return nil }
            return (CGPoint(x: p.box.midX, y: p.box.midY), Int(String(digits)) ?? 0, Double(p.box.midY))
        }
        .min { $0.y < $1.y }
        .map { (at: $0.at, count: $0.count) }
    }

    /// One name as a picker shows it: spaces, 「@微信」 and 「外部」 dropped (XiaoLanPanes.listName).
    static func sameMember(_ shown: String, _ name: String) -> Bool {
        let a = XiaoLanPanes.listName(shown), b = bare(name)
        return !a.isEmpty && WatchReport.sameName(a, b)
    }

    /// The rows named `name` under a picker's search field (under its 联系人 header when there is one), above the
    /// keyboard, top first.
    static func results(_ name: String, _ rows: [[Piece]]) -> [CGPoint] {
        let header = rows.joined().filter { p in
            let t = bare(p.text)
            return (0.1...0.5).contains(Double(p.box.midY)) && t.count <= 4 && (t.hasSuffix("联系人") || t.hasSuffix("聯絡人") || t.hasSuffix("聯繫人"))
        }.map { Double($0.box.maxY) }.min()
        let top = header ?? 0.15, floor = keyboardFloor(rows)
        return rows.compactMap { row -> (text: String, box: CGRect)? in
            let left = row.filter { $0.box.minX < 0.85 }
            guard !left.isEmpty else { return nil }
            return (left.map(\.text).joined(), left.reduce(CGRect.null) { $0.union($1.box) })
        }
        .filter { Double($0.box.midY) > top && Double($0.box.maxY) < floor && sameMember($0.text, name) }
        .sorted { $0.box.midY < $1.box.midY }
        .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The group's own page (WeChat's 聊天信息, WeCom's 群信息).
    static func infoPage(_ rows: [[Piece]]) -> Bool {
        find(rows, ["群聊名称", "群聊名稱", "查看全部群成员", "查看全部群成員"]) != nil
            || (find(rows, ["群公告"]) != nil && find(rows, ["群管理"]) != nil)
    }

    /// A member picker: its title (发起群聊, 选择联系人, 添加群成员, 移出成员, 移出群成员) and its search field.
    static func picker(_ rows: [[Piece]], titles: [String]) -> Bool {
        find(rows, titles, band: 0...0.09) != nil && find(rows, ["搜索", "搜尋"], band: 0.07...0.3) != nil
    }
    static let createTitles = ["发起群聊", "發起群聊"]
    static let addTitles = ["选择联系人", "選擇聯絡人", "添加群成员", "添加群成員", "添加成员", "邀请成员"]
    static let removeTitles = ["移出成员", "移出群成员", "移出成員", "移出群成員", "删除成员"]

    /// The ＋ and − tiles at the end of a group's member grid (window fractions): neither has a word, each a thin grey
    /// glyph (~175) on white inside a dashed square. Measured 11-28 (960-wide frames): arms 21–27 px (0.043–0.059 of
    /// the window), the square's dashes ≤ 7 px (0.015); found in the band from under the title to the first row of the
    /// page under the grid. A glyph inside a word read (十, 一) is no tile.
    static func tiles(_ px: WatchOCR.Pixels, _ rows: [[Piece]]) -> (plus: CGPoint?, minus: CGPoint?) {
        let under = ["群聊名称", "群聊名稱", "查看全部群成员", "查看全部群成員", "查看更多", "群公告", "群二维码"]
        let stop = rows.joined().filter { p in under.contains { bare(p.text).hasPrefix($0) } }
            .map { Double($0.box.minY) }.filter { $0 > 0.1 }.min()
        let bottom = min((stop ?? 0.56) - 0.005, 0.9)
        let w = px.w, h = px.h
        let y0 = Int(0.075 * Double(h)), y1 = min(h - 1, Int(bottom * Double(h)))
        guard y1 > y0, w > 20 else { return (nil, nil) }
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * w + x) * 4
            return (Int(px.bytes[i]), Int(px.bytes[i + 1]), Int(px.bytes[i + 2]))
        }
        func glyph(_ x: Int, _ y: Int) -> Bool {
            let c = at(x, y)
            return max(c.0, c.1, c.2) - min(c.0, c.1, c.2) <= 14 && (390...615).contains(c.0 + c.1 + c.2)
        }
        func white(_ x: Int, _ y: Int) -> Bool { let c = at(x, y); return min(c.0, c.1, c.2) >= 236 }
        let minL = max(4, Int(0.03 * Double(w))), maxL = Int(0.085 * Double(w))
        var plus: [CGPoint] = [], minus: [CGPoint] = []
        func near(_ p: CGPoint, _ list: [CGPoint]) -> Bool { list.contains { abs($0.x - p.x) < 0.02 && abs($0.y - p.y) < 0.02 } }
        for y in y0...y1 {
            var x = 4
            while x < w - 4 {
                guard glyph(x, y) else { x += 1; continue }
                let s = x
                while x < w - 1, glyph(x, y) { x += 1 }
                let len = x - s
                if (minL...maxL).contains(len), s >= 4, x + 3 < w, white(s - 4, y), white(x + 3, y) {
                    let cx = (s + x - 1) / 2
                    var t = y, b = y
                    while t > 0, glyph(cx, t - 1) { t -= 1 }
                    while b < h - 1, glyph(cx, b + 1) { b += 1 }
                    let v = b - t + 1
                    if Double(v) >= 0.6 * Double(len), Double(v) <= 1.4 * Double(len) {
                        let p = CGPoint(x: Double(cx) / Double(w), y: Double(t + b) / 2 / Double(h))
                        if !near(p, plus) { plus.append(p) }
                    } else if v <= 5, white(cx, max(0, y - 6)), white(cx, min(h - 1, y + 6)) {
                        let p = CGPoint(x: Double(cx) / Double(w), y: Double(y) / Double(h))
                        if !near(p, minus) { minus.append(p) }
                    }
                }
                x += 1
            }
        }
        let words = rows.joined().map { $0.box.insetBy(dx: -0.005, dy: -0.005) }
        func free(_ p: CGPoint) -> Bool { !words.contains { $0.contains(p) } }
        return (plus.first(where: free), minus.first(where: free))
    }

    /// The chat's title as a group's name (its count dropped), to be compared exactly before anything is dissolved.
    static func titleName(_ view: XiaoLanPanes.View) -> String? {
        guard case .chat(let t) = view else { return nil }
        return WatchReport.fullTitle(WatchOCR.titled(t).name)
    }
}

#if XIAOLAN
extension AppModel {
    /// 197: a group order (206 / 207 / 219) by fixed steps in its app's window; nothing is left to the model (N90).
    func paneGroupOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let f = XiaoLanOrders.Fields(order.raw), app = order.app
        if let why = XiaoLanOrders.problem(order.type, app, f) { return (false, why) }
        let typed = [f.s("groupName"), f.s("groupAnnouncement"), f.s("newGroupName"), f.s("newGroupAnnouncement")].filter { !$0.isEmpty }
        if typed.contains(where: { PrivacyGuard.check($0, words: WatchSettings.privateWords, numbers: WatchSettings.blockNumbers) != nil }) {
            return (false, ChatToolLink.reasonPrivacy)
        }
        var skipped: [String] = []
        if !f.s("groupRemark").isEmpty { skipped.append("群备注") }
        if !f.s("groupTemplate").isEmpty { skipped.append("群模板") }
        let note = skipped.isEmpty ? "" : "（\(skipped.joined(separator: "、"))还没有固定步骤，没有设置）"
        var result: (ok: Bool, why: String)
        switch order.type {
        case 206: result = await groupCreate(app, f, &state)
        case 207: result = await groupChange(app, f, &state)
        default: result = await groupDissolve(app, f.s("groupName"), &state)
        }
        _ = await groupList(app, &state)  // back to the list whatever happened
        if result.ok { result.why = note }
        DebugLog.write("watch: group: order \(order.type) (\(app.rawValue)) " + (result.ok ? "done" : "failed: \(result.why)"))
        return result
    }

    private func groupAppName(_ app: XiaoLanOrders.App) -> String { app == .wework ? "企业微信" : "微信" }

    /// 197: a moment between the group's changes (WeChat asked for a new login once, 11-28 02:09, after five of them
    /// in six minutes).
    private func groupPause() async {
        try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 0.8...1.5) * 1_000_000_000))
    }

    /// Tap `p` in `l`'s window, then look at it again until `done` (six looks); nil when it never does.
    private func groupStep(_ l: PaneLook, _ p: CGPoint, _ what: String, wide: Double = 0.1, tall: Double = 0.012,
                           until done: (PaneLook) -> Bool) async -> PaneLook? {
        guard await paneTap(p, in: l.rect, wide: wide, tall: tall) else {
            DebugLog.write("watch: group: \(what): not clicked")
            return nil
        }
        guard let n = await paneLook(l.side, after: now(), tries: 6, until: done), done(n) else {
            DebugLog.write("watch: group: \(what): the window did not show what should follow")
            return nil
        }
        DebugLog.write("watch: group: \(what)")
        return n
    }

    /// The app's window back on its chat list (from a chat, a group's page, a picker), at most four backs.
    @discardableResult
    private func groupList(_ app: XiaoLanOrders.App, _ state: inout PaneWatchState) async -> PaneLook? {
        for _ in 0..<5 {
            guard let l = await paneFind(app, &state) else { return nil }
            if XiaoLanPanes.plusMenu(l.rows) { await paneCloseMenu(l); continue }  // the ＋ menu: closed, none of its rows
            if let c = XiaoLanPanes.cancelButton(l.rows), Double(c.x) > 0.5 { await paneCloseSearch(l.side); continue }  // a search
            if l.view == .list { return l }
            // a chat, a group's page, a picker: its back, 取消 or ✕ at the top left
            guard await paneBackClick(l, app.rawValue) else { return nil }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }

    /// A group's chat opened by its name: its row on the list, else the list's search. `exact`: its title must read
    /// the name exactly (before a dissolve), not with OCR's one slipped character.
    private func groupOpen(_ app: XiaoLanOrders.App, _ name: String, exact: Bool, _ state: inout PaneWatchState) async -> (look: PaneLook?, why: String) {
        let appName = groupAppName(app)
        func isIt(_ l: PaneLook) -> Bool {
            guard let t = XiaoLanGroups.titleName(l.view) else { return false }
            return exact ? XiaoLanGroups.bare(t) == XiaoLanGroups.bare(name) : WatchChatOpen.sameChat(t, listName: name)
        }
        if let l = await paneFind(app, &state), isIt(l) { return (l, "") }
        guard let list = await groupList(app, &state) else { return (nil, "\(appName)没有回到会话列表") }
        var row = XiaoLanPanes.entries(list.rows).first { WatchChatOpen.sameChat(name, listName: $0.name) }.map { CGPoint(x: 0.5, y: $0.box.midY) }
        if row == nil {
            let found = await paneSearch(name, list)
            if let why = found.why { return (nil, "\(appName)\(why)") }
            row = found.row
        }
        guard let at = row else { return (nil, "\(appName)里找不到群「\(name)」") }
        guard let open = await groupStep(list, at, "open 「\(name)」", wide: 0.3, tall: Self.rowTall, until: { $0.view != .list }) else {
            return (nil, "\(appName)里没有打开群「\(name)」")
        }
        guard isIt(open) else {
            DebugLog.write("watch: group: 「\(XiaoLanGroups.titleName(open.view) ?? "?")」 opened, not 「\(name)」")
            return (nil, "\(appName)打开的不是群「\(name)」（标题对不上），没有动它")
        }
        return (open, "")
    }

    /// From a group's chat to its page (•••).
    private func groupInfo(_ chat: PaneLook, _ app: XiaoLanOrders.App) async -> PaneLook? {
        await groupStep(chat, XiaoLanGroups.more(app), "the group's page (•••)", wide: 0.04, until: { XiaoLanGroups.infoPage($0.rows) })
    }

    /// Each of `names` searched in a picker and picked: the first result named so whose pick the 完成 count then counts.
    private func groupPick(_ names: [String], _ start: PaneLook, _ app: XiaoLanOrders.App) async -> (look: PaneLook?, why: String) {
        var l = start
        for (i, name) in names.enumerated() {
            // the first always by its box (a keyboard up may be another field's); after a pick the field keeps it
            if i == 0 || !keyboardBridge.onScreen() {
                guard let box = XiaoLanGroups.find(l.rows, ["搜索", "搜尋"], band: 0.07...0.3) else { return (nil, "成员选择页上找不到搜索框") }
                guard await paneTap(box, in: l.rect, wide: 0.3, tall: 0.012) else { return (nil, "没点到成员选择页的搜索框") }
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            guard await typeWithLanAgentKeyboard(name, enter: false) else { return (nil, "小蓝输入法没有打出「\(name)」（请在\(groupAppName(app))里把键盘切成小蓝）") }
            guard let shown = await paneLook(l.side, after: now(), tries: 6, until: { !XiaoLanGroups.results(name, $0.rows).isEmpty }) else {
                return (nil, "搜不到成员「\(name)」")
            }
            let hits = XiaoLanGroups.results(name, shown.rows)
            guard !hits.isEmpty else { return (nil, "搜不到成员「\(name)」") }
            let before = XiaoLanGroups.doneButton(shown.rows)?.count ?? 0
            var picked: PaneLook?
            for hit in hits.prefix(3) {
                let after = await groupStep(shown, hit, "picked 「\(name)」", wide: 0.3, tall: 0.015,
                                            until: { (XiaoLanGroups.doneButton($0.rows)?.count ?? 0) > before })
                if let a = after { picked = a; break }
                DebugLog.write("watch: group: 「\(name)」 there, the count did not go up (grey: picked or in the group already); the next one")
            }
            guard let p = picked else { return (nil, "「\(name)」选不上（可能已经在群里）") }
            l = p
            await groupPause()
        }
        return (l, "")
    }

    /// A picker's 完成 / 确定, then `done`; an alert asking again (WeChat's 移出) answered with `confirm`.
    private func groupDone(_ l: PaneLook, confirm: [String], until done: (PaneLook) -> Bool) async -> PaneLook? {
        guard let button = XiaoLanGroups.doneButton(l.rows) else { return nil }
        let next = await groupStep(l, button.at, "完成 (\(button.count))", wide: 0.06, until: { n in
            done(n) || XiaoLanGroups.find(n.rows, confirm, exact: true, band: 0.25...0.95) != nil
        })
        guard let n = next else { return nil }
        if done(n) { return n }
        guard let ok = XiaoLanGroups.find(n.rows, confirm, exact: true, band: 0.25...0.95) else { return nil }
        return await groupStep(n, ok, "confirmed (\(confirm.first ?? ""))", wide: 0.1, until: done)
    }

    /// The field focused on a page: emptied, `text` typed with 小藍's keyboard.
    private func groupType(_ text: String, _ app: XiaoLanOrders.App) async -> String? {
        do {
            try await pointer.key("cmd+a")
            try await pointer.key("backspace")
        } catch {
            DebugLog.write("watch: group: clearing the field failed: \(error.localizedDescription)")
        }
        return await typeWithLanAgentKeyboard(text, enter: false) ? nil : "小蓝输入法没有打出字（请在\(groupAppName(app))里把键盘切成小蓝）"
    }

    private func groupRename(_ info: PaneLook, _ app: XiaoLanOrders.App, to name: String) async -> (look: PaneLook?, why: String) {
        let row = app == .wework
            ? info.rows.joined().filter { (0.08...0.16).contains(Double($0.box.midY)) && $0.box.minX < 0.6 }
                .min { $0.box.midY < $1.box.midY }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
            : XiaoLanGroups.find(info.rows, ["群聊名称", "群聊名稱"]).map { CGPoint(x: 0.3, y: $0.y) }
        guard let at = row else { return (nil, "群信息页上找不到群名") }
        let titles = app == .wework ? ["群聊名称", "群聊名稱"] : ["修改群聊名称", "修改群聊名稱"]
        guard let page = await groupStep(info, at, "the name's page", wide: 0.2, until: { XiaoLanGroups.find($0.rows, titles, band: 0...0.2) != nil }) else {
            return (nil, "群名的修改页没有打开")
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        if let why = await groupType(name, app) { return (nil, why) }
        guard let shown = await paneLook(page.side, after: now(), tries: 4, until: { XiaoLanGroups.find($0.rows, ["确定", "確定"], exact: true) != nil }),
              let ok = XiaoLanGroups.find(shown.rows, ["确定", "確定"], exact: true) else { return (nil, "群名修改页上找不到「确定」") }
        guard let back = await groupStep(shown, ok, "renamed 「\(name)」", wide: 0.08, until: { XiaoLanGroups.infoPage($0.rows) }) else {
            return (nil, "点「确定」后没有回到群信息页")
        }
        if XiaoLanGroups.find(back.rows, [XiaoLanGroups.bare(name)]) == nil { DebugLog.write("watch: group: the new name not read on the group's page") }
        return (back, "")
    }

    /// The announcement written and published; WeChat goes on to the chat, WeCom to the announcement (back to the page).
    private func groupAnnounce(_ info: PaneLook, _ app: XiaoLanOrders.App, _ text: String) async -> (look: PaneLook?, why: String) {
        guard let row = XiaoLanGroups.find(info.rows, ["群公告"]) else { return (nil, "群信息页上找不到「群公告」") }
        let publish = app == .wework ? ["发布", "發布"] : ["完成"]
        func editor(_ l: PaneLook) -> Bool { XiaoLanGroups.find(l.rows, publish, exact: true, band: 0...0.09) != nil }
        func viewer(_ l: PaneLook) -> Bool { XiaoLanGroups.find(l.rows, ["编辑", "編輯"], exact: true, band: 0...0.09) != nil }
        guard var page = await groupStep(info, CGPoint(x: 0.3, y: row.y), "群公告", wide: 0.2, until: { editor($0) || viewer($0) }) else {
            return (nil, "群公告没有打开")
        }
        if !editor(page), let edit = XiaoLanGroups.find(page.rows, ["编辑", "編輯"], exact: true, band: 0...0.09) {
            guard let e = await groupStep(page, edit, "编辑 the announcement", wide: 0.05, until: editor) else { return (nil, "群公告的「编辑」没有打开") }
            page = e
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        if let why = await groupType(text, app) { return (nil, why) }
        guard let shown = await paneLook(page.side, after: now(), tries: 3, until: editor),
              let go = XiaoLanGroups.find(shown.rows, publish, exact: true, band: 0...0.09) else { return (nil, "群公告页上找不到「\(publish[0])」") }
        let ask = ["发布", "發布"]
        guard let alert = await groupStep(shown, go, publish[0], wide: 0.05, until: { XiaoLanGroups.find($0.rows, ask, exact: true, band: 0.25...0.8) != nil }),
              let yes = XiaoLanGroups.find(alert.rows, ask, exact: true, band: 0.25...0.8) else { return (nil, "没有出现「发布」确认") }
        guard let after = await groupStep(alert, yes, "announcement published", wide: 0.1, until: { l in
            XiaoLanGroups.find(l.rows, ask, exact: true, band: 0.25...0.8) == nil && (viewer(l) || XiaoLanGroups.titleName(l.view) != nil)
        }) else { return (nil, "点「发布」后页面没有变") }
        if viewer(after) {  // WeCom: the announcement as published; back to the group's page
            guard await paneBackClick(after, app.rawValue),
                  let back = await paneLook(after.side, after: now(), tries: 5, until: { XiaoLanGroups.infoPage($0.rows) }) else {
                return (nil, "发布后没有回到群信息页")
            }
            return (back, "")
        }
        return (after, "")
    }

    private func groupAdd(_ info: PaneLook, _ app: XiaoLanOrders.App, _ names: [String]) async -> (look: PaneLook?, why: String) {
        guard let px = WatchOCR.Pixels(info.crop), let plus = XiaoLanGroups.tiles(px, info.rows).plus else { return (nil, "群信息页上找不到成员格的「+」") }
        guard let page = await groupStep(info, plus, "＋ (add)", wide: 0.04, tall: 0.015, until: { XiaoLanGroups.picker($0.rows, titles: XiaoLanGroups.addTitles) }) else {
            return (nil, "拉人的选择页没有打开")
        }
        let picked = await groupPick(names, page, app)
        guard let p = picked.look else { return (nil, picked.why) }
        guard let back = await groupDone(p, confirm: ["确定", "確定", "邀请", "邀請", "发送", "發送"], until: { XiaoLanGroups.infoPage($0.rows) }) else {
            return (nil, "拉人点「完成」后没有回到群信息页")
        }
        return (back, "")
    }

    private func groupRemove(_ info: PaneLook, _ app: XiaoLanOrders.App, _ names: [String]) async -> (look: PaneLook?, why: String) {
        guard let px = WatchOCR.Pixels(info.crop), let minus = XiaoLanGroups.tiles(px, info.rows).minus else { return (nil, "群信息页上找不到成员格的「−」（不是群主或群管理员？）") }
        guard let page = await groupStep(info, minus, "− (remove)", wide: 0.04, tall: 0.015, until: { XiaoLanGroups.picker($0.rows, titles: XiaoLanGroups.removeTitles) }) else {
            return (nil, "踢人的选择页没有打开")
        }
        let picked = await groupPick(names, page, app)
        guard let p = picked.look else { return (nil, picked.why) }
        guard let back = await groupDone(p, confirm: ["移出", "删除", "刪除"], until: { XiaoLanGroups.infoPage($0.rows) }) else {
            return (nil, "踢人点「完成」后没有回到群信息页")
        }
        return (back, "")
    }

    private func groupCreate(_ app: XiaoLanOrders.App, _ f: XiaoLanOrders.Fields, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let appName = groupAppName(app)
        watchStatus = "创建群…"
        guard let list = await groupList(app, &state) else { return (false, "\(appName)没有回到会话列表") }
        guard let menu = await groupStep(list, XiaoLanGroups.plus(app), "＋", wide: 0.04, until: { XiaoLanGroups.find($0.rows, XiaoLanGroups.createTitles) != nil }),
              let item = XiaoLanGroups.find(menu.rows, XiaoLanGroups.createTitles) else { return (false, "\(appName)的＋菜单没有打开") }
        guard let page = await groupStep(menu, item, "发起群聊", wide: 0.08, tall: 0.010, until: { XiaoLanGroups.picker($0.rows, titles: XiaoLanGroups.createTitles) }) else {
            return (false, "\(appName)的发起群聊页没有打开")
        }
        let picked = await groupPick(f.list("selectList"), page, app)
        guard let p = picked.look else { return (false, picked.why) }
        guard var chat = await groupDone(p, confirm: ["确定", "確定"], until: { l in
            XiaoLanGroups.titleName(l.view) != nil && !XiaoLanGroups.picker(l.rows, titles: XiaoLanGroups.createTitles)
        }) else {
            return (false, "点「完成」后没有进到新群")
        }
        DebugLog.write("watch: group: created (「\(XiaoLanGroups.titleName(chat.view) ?? "")」)")
        let name = f.s("groupName"), notice = f.s("groupAnnouncement")
        guard !name.isEmpty || !notice.isEmpty else { return (true, "") }
        await groupPause()
        guard var info = await groupInfo(chat, app) else { return (false, "群建好了，但群信息页没有打开（群名、公告没设）") }
        if !name.isEmpty {
            let r = await groupRename(info, app, to: name)
            guard let l = r.look else { return (false, "群建好了，但" + r.why) }
            info = l
            await groupPause()
        }
        if !notice.isEmpty {
            let r = await groupAnnounce(info, app, notice)
            guard let l = r.look else { return (false, "群建好了，但" + r.why) }
            chat = l
        }
        return (true, "")
    }

    private func groupChange(_ app: XiaoLanOrders.App, _ f: XiaoLanOrders.Fields, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        watchStatus = "修改群 \(f.s("groupName"))…"
        let opened = await groupOpen(app, f.s("groupName"), exact: false, &state)
        guard let chat = opened.look else { return (false, opened.why) }
        guard var info = await groupInfo(chat, app) else { return (false, "群信息页没有打开") }
        var done: [String] = []
        func failed(_ why: String) -> (ok: Bool, why: String) { (false, (done.isEmpty ? "" : "已做完：\(done.joined(separator: "、"))；") + why) }
        if !f.s("newGroupName").isEmpty {
            let r = await groupRename(info, app, to: f.s("newGroupName"))
            guard let l = r.look else { return failed(r.why) }
            (info, done) = (l, done + ["改群名"])
            await groupPause()
        }
        if !f.list("removeList").isEmpty {
            let r = await groupRemove(info, app, f.list("removeList"))
            guard let l = r.look else { return failed(r.why) }
            (info, done) = (l, done + ["踢人"])
            await groupPause()
        }
        if !f.list("selectList").isEmpty {
            let r = await groupAdd(info, app, f.list("selectList"))
            guard let l = r.look else { return failed(r.why) }
            (info, done) = (l, done + ["拉人"])
            await groupPause()
        }
        if !f.s("newGroupAnnouncement").isEmpty {  // last: WeChat leaves the group's page for its chat after it
            let r = await groupAnnounce(info, app, f.s("newGroupAnnouncement"))
            guard r.look != nil else { return failed(r.why) }
            done.append("改公告")
        }
        return (true, "")
    }

    /// 219: only the group whose chat title reads the name exactly; only by its owner (no 解散 for anyone else).
    private func groupDissolve(_ app: XiaoLanOrders.App, _ name: String, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        watchStatus = "解散群 \(name)…"
        let opened = await groupOpen(app, name, exact: true, &state)
        guard let chat = opened.look else { return (false, opened.why) }
        guard let info = await groupInfo(chat, app) else { return (false, "群信息页没有打开") }
        guard let manage = XiaoLanGroups.find(info.rows, ["群管理"], exact: true) else { return (false, "群信息页上没有「群管理」（不是群主？），没有解散") }
        let words = ["解散该群聊", "解散該群聊", "解散群聊"]
        guard let page = await groupStep(info, CGPoint(x: 0.3, y: manage.y), "群管理", wide: 0.2, until: { XiaoLanGroups.find($0.rows, words) != nil || XiaoLanGroups.find($0.rows, ["转让群主", "群主管理权转让", "群管理员"]) != nil }) else {
            return (false, "群管理页没有打开")
        }
        guard let item = XiaoLanGroups.find(page.rows, words) else { return (false, "群管理里没有「解散群聊」（不是群主），没有解散") }
        let yes = ["解散"]
        guard let ask = await groupStep(page, item, "解散群聊", wide: 0.2, until: { XiaoLanGroups.find($0.rows, yes, exact: true, band: 0.25...0.97) != nil }),
              let go = XiaoLanGroups.find(ask.rows, yes, exact: true, band: 0.25...0.97) else { return (false, "没有出现解散的确认") }
        DebugLog.write("watch: group: dissolving 「\(name)」 (\(app.rawValue))")
        guard await groupStep(ask, go, "dissolved", wide: 0.15, until: { l in
            l.view == .list || XiaoLanGroups.find(l.rows, ["已解散", "已经解散", "已經解散"]) != nil
        }) != nil else { return (false, "点了「解散」，但没有看到已解散") }
        return (true, "")
    }
}
#endif
