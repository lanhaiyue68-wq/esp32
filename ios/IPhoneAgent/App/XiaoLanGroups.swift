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
@MainActor enum XiaoLanGroups {
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
    /// 198 (218): a file's name without its extension, bare (the picker's grid shows 「EchoTest218」 for 「EchoTest218.pdf」).
    static func fileStem(_ name: String) -> String {
        let s = (name as NSString).deletingPathExtension
        return bare(s.isEmpty ? name : s)
    }

    /// 198 (218): the ＋ panel under the input bar (WeChat 照片 拍摄 视频通话 位置…, WeCom 照片 拍摄 收藏 语音通话…; page 2
    /// 个人名片 文件 / 发起收款 文件 应用): two of its words in the window's lower half.
    static func plusPanel(_ rows: [[Piece]]) -> Bool {
        ["照片", "拍摄", "位置", "文件", "个人名片", "收藏"].filter { find(rows, [$0], exact: true, band: 0.5...0.97) != nil }.count >= 2
    }

    /// 198 (218): iOS's file picker (its tabs 最近项目 and 浏览 at its foot on every page).
    static func filePicker(_ rows: [[Piece]]) -> Bool {
        find(rows, ["最近项目", "最近項目"], exact: true) != nil && find(rows, ["浏览", "瀏覽"], exact: true) != nil
    }

    /// 198 (218): the file in the picker by its name (a long one may show cut).
    static func pickerFile(_ rows: [[Piece]], _ stem: String) -> CGPoint? {
        rows.joined().first { p in
            let t = bare(p.text)
            guard Double(p.box.midY) > 0.1, Double(p.box.midY) < 0.9, t.count >= 3 else { return false }
            let cut = t.replacingOccurrences(of: "…", with: "")
            return t == stem || (stem.count >= 6 && (t.hasPrefix(stem) || (cut.count >= 6 && stem.hasPrefix(cut))))
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// 198 (218): the picker's next step down to Documents/orders: by its title, Echo's orders folder, Echo in 我的 iPad,
    /// 我的 iPad among the places; anywhere else, its 浏览 tab.
    static func pickerNext(_ rows: [[Piece]]) -> (at: CGPoint, what: String)? {
        // a title may read with its ⌄ glued on (「Echov」, 「ordersv」)
        func title(_ w: [String]) -> Bool { find(rows, w, band: 0...0.09) != nil }
        func item(_ w: [String]) -> CGPoint? { find(rows, w, exact: true, band: 0.1...0.9) }
        if title(["Echo"]), let at = item(["orders"]) { return (at, "orders") }
        if title(["我的iPad"]), let at = item(["Echo"]) { return (at, "Echo") }
        if title(["浏览", "瀏覽"]), let at = item(["我的iPad"]) { return (at, "我的 iPad") }
        if let tab = find(rows, ["浏览", "瀏覽"], exact: true, band: 0.75...0.99) { return (tab, "浏览") }
        return nil
    }

    /// 198 (218 pictures): an app's album opened from ＋ › 照片 (WeChat's foot: 预览 原图 发送).
    static func photoAlbum(_ rows: [[Piece]]) -> Bool {
        find(rows, ["原图", "原圖"], band: 0.8...1) != nil && find(rows, ["预览", "預覽"], band: 0.8...1) != nil
    }

    /// 198 (218 pictures): the album's 「发送(1)」 — one chosen, no other count — at its foot; nil otherwise.
    static func photoSend(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { p in
            Double(p.box.midY) > 0.8 && bare(p.text).range(of: #"^(发送|發送|完成)[(（]1[)）]$"#, options: .regularExpression) != nil
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// 198 (218 pictures): the album's title row (「最近项目」 by its ✕), window fractions; measured WeChat 0.057.
    static func albumHeaderY(_ rows: [[Piece]]) -> Double {
        find(rows, ["最近项目", "最近項目", "所有照片", "相机胶卷", "相機膠卷", "Recents"], band: 0...0.12).map { Double($0.y) } ?? 0.057
    }

    /// 198 (218 pictures): the newest photo's ring — the first cell's top right, four cells a row (measured on WeChat's
    /// window 11-28: (0.199, 0.109) with its title at 0.057).
    static func newestRing(_ rows: [[Piece]]) -> CGPoint {
        CGPoint(x: 0.199, y: albumHeaderY(rows) + 0.052)
    }

    /// 198 (205): 「选择聊天」, the page 转发 opens (both apps).
    static func forwardPage(_ rows: [[Piece]]) -> Bool {
        find(rows, ["选择聊天", "選擇聊天", "选择一个聊天", "選擇一個聊天"], band: 0...0.09) != nil
    }

    /// 198 (205): a chat's name as 「选择聊天」 shows it, bare: its tags (@微信, 外部), a head count 「(6人)」 「(7)」 off.
    static func forwardName(_ text: String) -> String {
        var t = XiaoLanPanes.listName(text)
        if let r = t.range(of: #"[（(]\d+人?[）)]$"#, options: .regularExpression) { t.removeSubrange(r) }
        return bare(t)
    }

    /// 198 (205): a chat's row on 「选择聊天」 by its exact name, never one it only resembles (WeCom's list there holds a
    /// 150-member real group).
    static func forwardRow(_ rows: [[Piece]], _ name: String) -> CGPoint? {
        let want = bare(name)
        return rows.joined().first { p in
            Double(p.box.midY) > 0.12 && Double(p.box.midY) < 0.95 && p.box.midX < 0.75 && forwardName(p.text) == want
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// 198 (205): the 「发送给」 sheet's 发送 (WeChat's green button, WeCom's blue word); nil when no such sheet is up.
    static func sendSheet(_ rows: [[Piece]]) -> CGPoint? {
        guard find(rows, ["发送给", "發送給"], band: 0.1...0.9) != nil else { return nil }
        return find(rows, ["发送", "發送"], exact: true, band: 0.25...0.95)
    }

    /// 198 (226): my own line reading `want` (plain words), the lowest of them: a piece on the right half whose words
    /// start it or start with it (a long line wraps over pieces), above any keyboard.
    static func mineLine(_ rows: [[Piece]], _ want: String) -> CGPoint? {
        let floor = keyboardFloor(rows)
        return rows.joined().filter { p in
            let t = XiaoLanSelf.plain(p.text)
            guard p.box.midX > 0.5, Double(p.box.midY) > 0.1, Double(p.box.maxY) < floor, t.count >= 2 else { return false }
            return want.hasPrefix(t) || t.hasPrefix(want) || (want.count >= 6 && t.contains(want.prefix(6)))
        }
        .max { $0.box.midY < $1.box.midY }
        .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// 198 (226): the grey 「你撤回了一条消息」 lines on the window (WeChat's, WeCom's, Traditional too), counted.
    static func recalledCount(_ rows: [[Piece]]) -> Int {
        rows.joined().filter { p in
            let t = bare(p.text)
            return t.hasPrefix("你撤回了") || t.hasPrefix("你已撤回") || t.hasPrefix("你撤回")
        }.count
    }

    /// 198 (226): an alert asking before taking it back (取消 beside 撤回 / 确定), its yes; nil when there is none.
    static func recallConfirm(_ rows: [[Piece]]) -> CGPoint? {
        let ps = Array(rows.joined())
        guard ps.contains(where: { ["取消", "Cancel"].contains(bare($0.text)) && Double($0.box.midY) > 0.25 }) else { return nil }
        return ps.first { p in ["撤回", "确定", "确认", "確定", "確認"].contains(bare(p.text)) && Double(p.box.midY) > 0.25 }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

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

    // MARK: 跟圈 (260, WeChat only: WeCom shows no one's 朋友圈) and 爬楼 (515), user 11-28: 「跟圈也做成固定程序…還有爬樓」

    /// One post on a friend's 朋友圈 page (WeChat's album, m03 11-28: a date at the left, 「13 8月」 read 「138月」, then a
    /// picture with its words beside it, or the words alone in a grey box).
    struct Post: Equatable {
        var date: String
        var top: Double, bottom: Double
        var text: String
        var picture: CGRect?
    }

    /// A post's date as the album shows it (spaces dropped): 「138月」 (13 8月), 「今天」, 「昨天」.
    static func postDate(_ text: String) -> Bool {
        let t = bare(text)
        return ["今天", "昨天"].contains(t) || t.range(of: #"^\d{2,4}月$"#, options: .regularExpression) != nil
    }

    /// The share of a rect that is neither white nor the album's grey text box (a picture's is ~0.9, a text post's
    /// box with its words ~0.15; m03).
    static func busy(_ px: WatchOCR.Pixels, _ r: CGRect) -> Double {
        var n = 0, hit = 0
        for y in stride(from: Double(r.minY), to: Double(min(r.maxY, 0.995)), by: 0.004) {
            for x in stride(from: Double(r.minX), to: Double(min(r.maxX, 0.995)), by: 0.006) {
                let (cr, cg, cb) = px.rgb(x, y)
                n += 1
                if !(min(cr, cg, cb) >= 236 && max(cr, cg, cb) - min(cr, cg, cb) <= 10) { hit += 1 }
            }
        }
        return n == 0 ? 0 : Double(hit) / Double(n)
    }

    /// The posts on an album screen, top first: each from its date to the next one's; the words right of the date
    /// column (a picture's own words, read inside it, left out); a picture when the place right of the date is busy.
    static func posts(_ rows: [[Piece]], _ px: WatchOCR.Pixels?) -> [Post] {
        let floor = min(keyboardFloor(rows), 0.97), all = Array(rows.joined())
        // 198: a date at the window's very foot (its post's top under the floor) is a cut post, left for the next
        // screen; kept, its top...floor would be no range and stop the app
        let anchors = rows.compactMap { row -> (text: String, y: Double)? in
            let left = row.filter { $0.box.minX < 0.16 }
            guard !left.isEmpty, Double(left[0].box.midY) > 0.08 else { return nil }
            let text = left.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined()
            return postDate(text) ? (bare(text), Double(left.map(\.box.midY).min() ?? 0)) : nil
        }.filter { $0.y - 0.012 < floor }.sorted { $0.y < $1.y }
        return anchors.enumerated().map { i, d in
            let top = d.y - 0.012, bottom = i + 1 < anchors.count ? anchors[i + 1].y - 0.012 : floor
            var picture: CGRect?
            if let px {
                let r = CGRect(x: 0.21, y: d.y - 0.02, width: 0.22, height: 0.085)
                if busy(px, r) > 0.5 { picture = r }
            }
            let words = all.filter { p in
                let c = CGPoint(x: p.box.midX, y: p.box.midY)
                return Double(p.box.minX) > 0.18 && (top...bottom).contains(Double(c.y)) && !(picture?.contains(c) ?? false)
            }
            .sorted { abs($0.box.midY - $1.box.midY) < 0.008 ? $0.box.minX < $1.box.minX : $0.box.midY < $1.box.midY }
            .map(\.text).joined()
            return Post(date: d.text, top: top, bottom: bottom, text: words, picture: picture)
        }
    }

    /// A year header on the album (「2025年」), for the posts under it.
    static func yearHeader(_ rows: [[Piece]]) -> [(year: Int, y: Double)] {
        rows.joined().compactMap { p in
            let t = bare(p.text)
            guard p.box.minX < 0.2, t.range(of: #"^\d{4}年$"#, options: .regularExpression) != nil, let n = Int(t.dropLast()) else { return nil }
            return (n, Double(p.box.midY))
        }
    }

    /// The day a post's date stands for: 「138月」 is 13 August (two digits of day, then the month), of `year` or else
    /// this year (last year when that would be ahead of today).
    static func postDay(_ date: String, year: Int?, now: Date = Date()) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now), t = bare(date)
        if t == "今天" { return today }
        if t == "昨天" { return cal.date(byAdding: .day, value: -1, to: today) }
        let digits = t.dropLast()
        guard t.hasSuffix("月"), digits.count >= 3, digits.allSatisfy(\.isNumber),
              let day = Int(digits.prefix(2)), let month = Int(digits.dropFirst(2)), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var c = DateComponents()
        c.year = year ?? cal.component(.year, from: today)
        c.month = month
        c.day = day
        guard var d = cal.date(from: c) else { return nil }
        if year == nil, d > today, let back = cal.date(byAdding: .year, value: -1, to: d) { d = back }
        return d
    }

    /// When a chat's time line stands for: 「01:20」 today, 「昨天12:10」, 「星期一 10:08」, 「11月20日 10:08」,
    /// 「2025年6月25日 10:08」, with 上午 / 下午 / 晚上 … for a 12-hour clock; nil for anything else.
    static func chatTime(_ label: String, now: Date = Date()) -> Date? {
        let t = bare(label)
        guard AgentLoop.isChatTimeLine(t), let r = t.range(of: #"\d{1,2}:\d{2}$"#, options: .regularExpression) else { return nil }
        let hm = t[r].split(separator: ":").compactMap { Int($0) }
        guard hm.count == 2 else { return nil }
        var hour = hm[0]
        if ["下午", "晚上", "傍晚"].contains(where: { t.contains($0) }), hour < 12 { hour += 12 }
        if t.contains("中午"), hour < 11 { hour += 12 }
        if ["凌晨", "半夜"].contains(where: { t.contains($0) }), hour == 12 { hour = 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let today = cal.startOfDay(for: now)
        var day = today
        if t.contains("前天") {
            day = cal.date(byAdding: .day, value: -2, to: today) ?? today
        } else if t.contains("昨天") {
            day = cal.date(byAdding: .day, value: -1, to: today) ?? today
        } else if let w = t.range(of: #"(星期|周)[一二三四五六日天]"#, options: .regularExpression), let last = t[w].last {
            let names: [Character] = ["日", "一", "二", "三", "四", "五", "六"]
            if let want = names.firstIndex(of: last == "天" ? "日" : last) {
                var back = (cal.component(.weekday, from: today) - 1 - want + 7) % 7
                if back == 0 { back = 7 }
                day = cal.date(byAdding: .day, value: -back, to: today) ?? today
            }
        } else if let md = t.range(of: #"\d{1,2}月\d{1,2}日"#, options: .regularExpression) {
            let nums = t[md].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard nums.count == 2 else { return nil }
            var c = DateComponents()
            let y = t.range(of: #"\d{4}年"#, options: .regularExpression).flatMap { Int(t[$0].dropLast()) }
            c.year = y ?? cal.component(.year, from: today)
            c.month = nums[0]
            c.day = nums[1]
            guard var d = cal.date(from: c) else { return nil }
            if y == nil, d > today, let back = cal.date(byAdding: .year, value: -1, to: d) { d = back }
            day = d
        }
        return cal.date(bySettingHour: min(hour, 23), minute: hm[1], second: 0, of: day)
    }

    /// A post's own page (详情, m06 11-28): the words between the writer's name and the post's time (「2026年8月8日22:40」,
    /// 「昨天 22:40」, 「3小时前」), and that time; nil when no time line is read.
    static func postDetail(_ rows: [[Piece]], friend: String) -> (text: String, time: String)? {
        let all = rows.joined().filter { (0.07...0.95).contains(Double($0.box.midY)) }
        func isTime(_ s: String) -> Bool {
            let t = bare(s)
            return t.range(of: #"^\d{4}年\d{1,2}月\d{1,2}日\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
                || AgentLoop.isChatTimeLine(t) || t.range(of: #"^\d{1,2}(分钟|小时|分鐘|小時)前$"#, options: .regularExpression) != nil
        }
        guard let time = all.filter({ isTime($0.text) }).min(by: { $0.box.midY < $1.box.midY }) else { return nil }
        let name = all.filter { sameMember($0.text, friend) && $0.box.midY < time.box.midY }.min { $0.box.midY < $1.box.midY }
        let top = Double(name?.box.maxY ?? 0.07)
        let body = all.filter { Double($0.box.midY) > top && $0.box.midY < time.box.minY }
            .sorted { abs($0.box.midY - $1.box.midY) < 0.008 ? $0.box.minX < $1.box.minX : $0.box.midY < $1.box.midY }
        return (body.map(\.text).joined(), bare(time.text))
    }

    /// A picture opened from the album (m04): its title is the post's time; its words sit just over the 赞 / 评论 bar.
    static func viewerTitle(_ rows: [[Piece]]) -> String? {
        rows.joined().first { Double($0.box.midY) < 0.09 && $0.text.contains(":") && $0.text.contains(where: \.isNumber) }.map { bare($0.text) }
    }
    static func viewerCaption(_ rows: [[Piece]]) -> String {
        let all = Array(rows.joined())
        guard let bar = all.filter({ Double($0.box.midY) > 0.85 && ($0.text.contains("评论") || $0.text.contains("評論")) }).map({ Double($0.box.minY) }).min()
        else { return "" }
        return all.filter { Double($0.box.maxY) <= bar && Double($0.box.midY) > bar - 0.09 && $0.box.minX < 0.5 }
            .sorted { $0.box.midY < $1.box.midY }.map(\.text).joined()
    }

    /// A read up a chat, oldest first: each screen's lines not on the screens below it go before them (screens in the
    /// order read, newest first; AgentLoop.readUpMerge's way, the sender kept).
    static func climbMerge(_ screens: [[WatchReport.Line]]) -> [WatchReport.Line] {
        var seen = Set<String>(), out: [WatchReport.Line] = []
        for lines in screens {
            let fresh = lines.filter { l in
                !l.text.isEmpty && seen.insert((l.mine ? "\u{1}" : l.sender) + "\u{2}" + bare(l.text)).inserted
            }
            out = fresh + out
        }
        return out
    }
}

/// 198 (user 11-28: 「自動通過好友…加一個頻率和開關…一分鐘通過幾個…時間不要有槼律…從最下面的開始往上加…企微和個微各
/// 一個」): friend requests accepted while watching, each app by its own switch, at most `perMinute` a minute, the gaps
/// random, the oldest (lowest on the list) first. Screens of Echo 197, 11-28 04:55–05:00 (docs/shots-2026-11-28-group f20–f34):
/// WeChat: 通讯录's tab mark → 新的朋友 → a row's 「查看」 → 「前往验证」 → 通过朋友验证 → 「完成」 (its page then has 发消息);
/// WeCom: 通讯录's tab mark → 添加客户 (its own mark) → 新的客户, a row's blue 「查看」 → 「通过验证」 → 为对方添加备注 →
/// 「完成」 (客户详情, 发消息). Done rows read 「已添加」.
@MainActor enum AutoAccept {
    // read by the settings' @AppStorage as it is made: no actor needed for constants
    nonisolated static let wechatKey = "xiaolanAcceptWeChatV1", weworkKey = "xiaolanAcceptWeComV1", perMinuteKey = "xiaolanAcceptPerMinuteV1"
    nonisolated static let defaultPerMinute = 5
    static func on(_ app: XiaoLanOrders.App) -> Bool { UserDefaults.standard.bool(forKey: app == .wework ? weworkKey : wechatKey) }
    static var perMinute: Int {
        let n = UserDefaults.standard.integer(forKey: perMinuteKey)
        return n == 0 ? defaultPerMinute : min(max(n, 1), 30)
    }

    /// The red share of a rect of a window (a mark is ~0.11–0.14 of the place over the tab's word; none, 0; the pointer's
    /// red ring beside it ~0.04).
    static func redShare(_ px: WatchOCR.Pixels, _ r: CGRect) -> Double {
        var n = 0, red = 0
        for y in stride(from: Double(max(r.minY, 0)), to: Double(min(r.maxY, 1)), by: 0.002) {
            for x in stride(from: Double(max(r.minX, 0)), to: Double(min(r.maxX, 1)), by: 0.003) {
                let (cr, cg, cb) = px.rgb(x, y)
                n += 1
                if cr > 200 && cg < 110 && cb < 110 { red += 1 }
            }
        }
        return n == 0 ? 0 : Double(red) / Double(n)
    }

    /// The tab bar's word (通讯录, 微信, 消息), window fractions.
    static func tab(_ rows: [[CandidatePicker.Piece]], _ words: [String]) -> CGPoint? {
        XiaoLanGroups.find(rows, words, exact: true, band: 0.85...1)
    }

    /// A red mark over 通讯录 on the tab bar (WeChat ~(+0.033, −0.040) from the word, WeCom ~(+0.036, −0.034); f20).
    static func contactsMarked(_ rows: [[CandidatePicker.Piece]], _ px: WatchOCR.Pixels) -> Bool {
        guard let w = tab(rows, ["通讯录", "通訊錄"]) else { return false }
        return redShare(px, CGRect(x: Double(w.x) - 0.01, y: Double(w.y) - 0.07, width: 0.09, height: 0.055)) >= 0.06
    }

    /// The requests' page: 新的朋友 (WeChat) or 新的客户 (WeCom) at its top.
    static func requestsPage(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        XiaoLanGroups.find(rows, ["新的朋友", "新朋友", "新的客户", "新的客戶"], band: 0...0.09) != nil
    }

    /// The waiting requests' buttons (「查看」, 「接受」 at a row's right end), top first; done rows read 「已添加」.
    static func waiting(_ rows: [[CandidatePicker.Piece]]) -> [CGPoint] {
        let floor = XiaoLanGroups.keyboardFloor(rows)
        return rows.joined().filter { p in
            ["查看", "接受"].contains(XiaoLanGroups.bare(p.text)) && p.box.midX > 0.75 && Double(p.box.midY) > 0.1 && Double(p.box.maxY) < floor
        }
        .sorted { $0.box.midY < $1.box.midY }
        .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// Who a request's row is from: the name left of its button, on its line.
    static func requester(_ rows: [[CandidatePicker.Piece]], at y: Double) -> String {
        rows.joined().filter { abs(Double($0.box.midY) - y) < 0.03 && $0.box.midX < 0.7 && $0.box.minX > 0.12 }
            .min { $0.box.midY < $1.box.midY }.map { XiaoLanPanes.listName($0.text) } ?? "?"
    }

    /// The gap before the next one: random around 60 / perMinute (a quarter to one and three quarters of it), never
    /// under 3 s; no rhythm to see.
    static func gap(_ perMinute: Int, random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> Double {
        max(3, 60 / Double(max(perMinute, 1)) * random(0.25...1.75))
    }

    /// Whether one more may go now: under `perMinute` in the last 60 s and the random gap gone by.
    static func due(_ times: [Double], next: Double, at t: Double, perMinute: Int) -> Bool {
        t >= next && times.filter { t - $0 < 60 }.count < perMinute
    }

    /// Whether older requests may be under the window's end: the lowest waiting button near its bottom (an iPad window
    /// shows ~7–9 rows; user 11-28: 10 at once, the lowest first).
    static func maybeBelow(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        guard let low = waiting(rows).last else { return false }
        return Double(low.y) > 0.75
    }

    // the watch's clock per app: when they went, when the next may, when to look again after nothing was waiting
    static var accepted: [XiaoLanOrders.App: [Double]] = [:]
    static var nextAt: [XiaoLanOrders.App: Double] = [:]
    static var idleUntil: [XiaoLanOrders.App: Double] = [:]
    /// Apps whose requests' page was opened and may still have some waiting: opening it takes 通讯录's mark away, so
    /// the rest go on by this until the page shows none (else 10 at once would stop after the first).
    static var more: Set<XiaoLanOrders.App> = []
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
        let words = Set(l.rows.joined().map { XiaoLanGroups.bare($0.text) })
        for attempt in 0..<2 {
            guard await paneTap(p, in: l.rect, wide: wide, tall: tall) else {
                DebugLog.write("watch: group: \(what): not clicked")
                return nil
            }
            if let n = await paneLook(l.side, after: now(), tries: 6, until: done), done(n) {
                DebugLog.write("watch: group: \(what)")
                // 197 (N94, Echo 197 11-28: the page read while it slid in, 群公告 not yet on it, a tile where a row moved
                // to): the window once more when it has stopped, kept when it still shows what was waited for
                let settled = await groupSettled(n)
                return done(settled) ? settled : n
            }
            // 197 (N92, Echo 197 11-28: WeCom's new group's page took no click 1.5 s after it showed): the same page
            // still there, nothing else read, the spot is clicked once more
            guard attempt == 0, let still = await paneLooks(side: l.side).first(where: { $0.side == l.side }),
                  XiaoLanPanes.titleLine(still.rows) == XiaoLanPanes.titleLine(l.rows) else { break }
            let readNow = Set(still.rows.joined().map { XiaoLanGroups.bare($0.text) })
            guard !words.isEmpty, Double(words.intersection(readNow).count) / Double(words.count) >= 0.8 else { break }
            DebugLog.write("watch: group: \(what): the window did not change; clicked once more (N92)")
        }
        DebugLog.write("watch: group: \(what): the window did not show what should follow")
        return nil
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
        // 197 (N93, Echo 197 11-28: WeChat's ＋ clicked 0.012 off its middle, beside the icon): these icons ±0.0095 across
        await groupStep(chat, XiaoLanGroups.more(app), "the group's page (•••)", wide: 0.02, tall: 0.008, until: { XiaoLanGroups.infoPage($0.rows) })
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
        guard let menu = await groupStep(list, XiaoLanGroups.plus(app), "＋", wide: 0.02, tall: 0.008, until: { XiaoLanGroups.find($0.rows, XiaoLanGroups.createTitles) != nil }),
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
        let created = XiaoLanGroups.titleName(chat.view) ?? ""
        DebugLog.write("watch: group: created (「\(created)」)")
        let name = f.s("groupName"), notice = f.s("groupAnnouncement")
        guard !name.isEmpty || !notice.isEmpty else { return (true, "") }
        await groupPause()
        // 198 (B5, user 11-28 chose 「立刻解散重來」: WeCom's new group left unnamed — its list line the members' names, its
        // chat titled 「群聊」 — could never be found by a name again): not named, the new group is dissolved and deleted
        // at once, and the order fails for the server to send again
        func undone(_ why: String) async -> (ok: Bool, why: String) {
            let undo = await groupUndoCreate(app, chat, created: created, &state)
            return (false, "群建好了，但\(why)；" + (undo ? "已把这个新群解散并从列表删掉，请重发" : "这个新群没能解散，请手动处理（列表上显示成员名）"))
        }
        guard var info = await groupInfo(chat, app) else { return await undone("群信息页没有打开") }
        if !name.isEmpty {
            let r = await groupRename(info, app, to: name)
            guard let l = r.look else { return await undone(r.why) }
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
        return await groupDissolveOpened(info, app, name, listName: name, &state)
    }

    /// 198 (B5): a new group left unnamed undone: the window back on its page (its chat's title the one it had when made,
    /// nothing else), dissolved, its line deleted. True when it went.
    private func groupUndoCreate(_ app: XiaoLanOrders.App, _ chat: PaneLook, created: String, _ state: inout PaneWatchState) async -> Bool {
        guard !created.isEmpty else { return false }
        DebugLog.write("watch: group: 「\(created)」 not named; dissolved again (B5)")
        var l = await paneLooks(side: chat.side).first(where: { $0.side == chat.side }) ?? chat
        for _ in 0..<2 where XiaoLanGroups.find(l.rows, ["群管理"], exact: true) == nil {
            if case .chat = l.view {
                guard XiaoLanGroups.titleName(l.view) == created, let i = await groupInfo(l, app) else { return false }
                l = i
            } else {
                guard await paneBackClick(l, app.rawValue) else { return false }
                l = await groupSettled(l)
            }
        }
        guard XiaoLanGroups.find(l.rows, ["群管理"], exact: true) != nil else { return false }
        return await groupDissolveOpened(l, app, created, listName: created, &state).ok
    }

    /// 219 from the group's page on: 群管理 → 解散该群聊 → 解散, then its line deleted from the list (`listName`).
    private func groupDissolveOpened(_ info: PaneLook, _ app: XiaoLanOrders.App, _ name: String, listName: String,
                                     _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
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
        // 198 (user 11-28: 「你解散的群要給他從聊天列表中刪除掉」): its chat deleted from the list too, as order 290 does
        // (back to the list, the row swiped, its red 删除, confirmed); dissolved all the same when that does not go
        let gone = await paneDelete(listName, app: app, &state)
        DebugLog.write("watch: group: 「\(name)」 dissolved; its chat " + (gone.ok ? "deleted from the list" : "not deleted from the list: \(gone.why)"))
        return (true, "")
    }

    // MARK: 226 撤回 by fixed steps (198, user 11-28: 「撤回轉發發文件…大概步驟要做成固定程序」; Echo 197's model run for
    // it flicked home twice, slid a row of WeCom's list open and did nothing in 78 s)

    /// 226: my own line reading `originalContent` (the newest of them, right side) long-pressed, 「撤回」 in its menu, and
    /// 「你撤回了一条消息」 seen. No 撤回 in the menu (past the apps' time for it, or not mine): the menu closed, failed.
    func paneRecallOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let app = order.app, want = XiaoLanSelf.plain(order.quote)
        guard !want.isEmpty else { return (false, "缺少要撤回的消息（originalContent）") }
        watchStatus = "撤回 \(order.chat) 的消息…"
        let opened = await groupOpen(app, order.chat, exact: true, &state)
        guard var chat = opened.look else { return (false, opened.why) }
        // 小藍's keyboard down first (198 N72's lesson: a press on a line read before it came up lands on its keys)
        if keyboardBridge.onScreen() || CandidatePicker.ourKeyboardShown(rows: chat.rows) {
            _ = await keyboardBridge.type("", enter: false, within: 1.5, dismiss: true)
            _ = await smallKeyboard(up: false, within: 1.0)
            chat = await groupSettled(chat)
        }
        let before = XiaoLanGroups.recalledCount(chat.rows)  // older 「你撤回了」 lines may show already
        guard let line = XiaoLanGroups.mineLine(chat.rows, want) else {
            return (false, "聊天里没看到我发的这条（「\(order.quote.prefix(20))」），没有撤回")
        }
        let s = XiaoLanPanes.onScreen(line, in: chat.rect)
        pointer.aimLoosely(0.04 * Double(chat.rect.width), 0.012)
        do { try await pointer.longPress(Double(s.x), Double(s.y), seconds: 0.8) } catch {
            return (false, "长按没有成功：\(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let menu = await paneLooks(after: now(), side: chat.side).first(where: { $0.side == chat.side }) else {
            return (false, "长按后没看到窗口")
        }
        let item = XiaoLanMediaFind.menuBand(menu.rows).flatMap { XiaoLanMediaFind.menuItem(menu.rows, "撤回", in: $0) }
        guard let item else {
            // the menu closed by a click on the chat's title bar (nothing there opens)
            _ = await paneTap(CGPoint(x: 0.5, y: 0.055), in: menu.rect, wide: 0.1, tall: 0.01)
            return (false, "长按菜单里没有「撤回」（超过撤回时间，或不是我发的），没有撤回")
        }
        guard let after = await groupStep(menu, item, "撤回", wide: 0.04, tall: 0.01, until: { l in
            XiaoLanGroups.recalledCount(l.rows) > before || XiaoLanGroups.recallConfirm(l.rows) != nil
        }) else { return (false, "点了「撤回」，没看到已撤回") }
        if let yes = XiaoLanGroups.recallConfirm(after.rows), XiaoLanGroups.recalledCount(after.rows) <= before {
            guard await groupStep(after, yes, "撤回 confirmed", wide: 0.06, tall: 0.012, until: { XiaoLanGroups.recalledCount($0.rows) > before }) != nil else {
                return (false, "确认撤回后没看到「你撤回了一条消息」")
            }
        }
        DebugLog.write("watch: \(app.rawValue): \(order.chat): 「\(order.quote.prefix(20))」 recalled")
        return (true, "")
    }

    // MARK: 205 转发 by fixed steps (198; walked on the iPad 11-28 06:26–06:29, docs/shots-2026-11-28-forward: both apps
    // the same — long press → 转发 → 「选择聊天」 (关闭, 多选, 搜索, 最近聊天) → a chat → 「发送给」 sheet (留言, 取消 发送) →
    // 发送 → back on the chat. WeCom's list holds a 150-member real group: a target is taken only by its exact name)

    /// 205: `originalContent` in the chat `titleList` names, forwarded to every name of `nameList` (one: its row; more:
    /// 多选, each row, 完成), with `extraText` as its note. A name not found exactly (on the list, then by its search):
    /// the page closed, nothing sent.
    func paneForwardOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let app = order.app, f = XiaoLanOrders.Fields(order.raw)
        let targets = f.list("nameList").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let note = f.s("extraText")
        guard !targets.isEmpty, !order.quote.isEmpty else { return (false, "缺少转发对象（nameList）或要转发的消息（originalContent）") }
        if PrivacyGuard.check(note, words: WatchSettings.privateWords, numbers: WatchSettings.blockNumbers) != nil {
            return (false, ChatToolLink.reasonPrivacy)
        }
        watchStatus = "转发 \(order.chat) 的消息…"
        let opened = await groupOpen(app, order.chat, exact: true, &state)
        guard var chat = opened.look else { return (false, opened.why) }
        if keyboardBridge.onScreen() || CandidatePicker.ourKeyboardShown(rows: chat.rows) {
            _ = await keyboardBridge.type("", enter: false, within: 1.5, dismiss: true)
            _ = await smallKeyboard(up: false, within: 1.0)
            chat = await groupSettled(chat)
        }
        guard let line = XiaoLanMediaFind.quoteSpot(chat.rows, quote: order.quote)
                ?? XiaoLanGroups.mineLine(chat.rows, XiaoLanSelf.plain(order.quote)) else {
            return (false, "聊天里没看到要转发的这条（「\(order.quote.prefix(20))」）")
        }
        let s = XiaoLanPanes.onScreen(line, in: chat.rect)
        pointer.aimLoosely(0.04 * Double(chat.rect.width), 0.012)
        do { try await pointer.longPress(Double(s.x), Double(s.y), seconds: 0.8) } catch {
            return (false, "长按没有成功：\(error.localizedDescription)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let menu = await paneLooks(after: now(), side: chat.side).first(where: { $0.side == chat.side }) else {
            return (false, "长按后没看到窗口")
        }
        guard let item = XiaoLanMediaFind.menuBand(menu.rows).flatMap({ XiaoLanMediaFind.menuItem(menu.rows, "转发", in: $0) }) else {
            _ = await paneTap(CGPoint(x: 0.5, y: 0.055), in: menu.rect, wide: 0.1, tall: 0.01)
            return (false, "长按菜单里没有「转发」")
        }
        guard var page = await groupStep(menu, item, "转发", wide: 0.04, tall: 0.01, until: { XiaoLanGroups.forwardPage($0.rows) }) else {
            return (false, "点了「转发」，没打开选择聊天")
        }
        let many = targets.count > 1
        if many {
            guard let multi = XiaoLanGroups.find(page.rows, ["多选", "多選"], exact: true, band: 0...0.09),
                  let m = await groupStep(page, multi, "多选", wide: 0.03, tall: 0.01, until: { XiaoLanGroups.find($0.rows, ["多选", "多選"], exact: true, band: 0...0.09) == nil })
            else { return await forwardClose(page, "选择聊天里没点到「多选」") }
            page = m
        }
        var sheet: PaneLook?
        for name in targets {
            var row = XiaoLanGroups.forwardRow(page.rows, name)
            if row == nil {  // not among the recent chats: by its search (an exact name only)
                let found = await paneSearch(name, page)
                if let r = found.row, let l = await paneLooks(side: page.side).first(where: { $0.side == page.side }) {
                    page = l
                    row = r
                }
            }
            guard let at = row else { return await forwardClose(page, "转发对象「\(name)」没找到（只按完整名字选），没有转发") }
            if many {
                _ = await paneTap(at, in: page.rect, wide: 0.15, tall: 0.012)
                page = await groupSettled(page)
            } else {
                sheet = await groupStep(page, at, "转发给 \(name)", wide: 0.15, tall: 0.012, until: { XiaoLanGroups.sendSheet($0.rows) != nil })
            }
        }
        if many, let done = XiaoLanGroups.doneButton(page.rows) {
            sheet = await groupStep(page, done.at, "完成(\(done.count))", wide: 0.03, tall: 0.01, until: { XiaoLanGroups.sendSheet($0.rows) != nil })
        }
        guard var ask = sheet, XiaoLanGroups.sendSheet(ask.rows) != nil else { return await forwardClose(page, "没出现「发送给」确认") }
        if !note.isEmpty, let field = XiaoLanGroups.find(ask.rows, ["发消息", "留言", "给朋友留言", "給朋友留言"], band: 0.2...0.95) {
            if await paneTap(field, in: ask.rect, wide: 0.15, tall: 0.01) {
                try? await Task.sleep(nanoseconds: 600_000_000)
                if !(await typeWithLanAgentKeyboard(note, enter: false)) { DebugLog.write("watch: forward: its note not typed") }
                ask = await groupSettled(ask)
            }
        }
        guard let send = XiaoLanGroups.sendSheet(ask.rows) else { return await forwardClose(ask, "「发送给」确认里没有「发送」") }
        guard await groupStep(ask, send, "发送 (forward)", wide: 0.05, tall: 0.012, until: { l in
            XiaoLanGroups.sendSheet(l.rows) == nil && !XiaoLanGroups.forwardPage(l.rows)
        }) != nil else { return (false, "点了「发送」，确认框没有消失") }
        DebugLog.write("watch: \(app.rawValue): \(order.chat): 「\(order.quote.prefix(20))」 forwarded to \(targets.joined(separator: ", "))")
        return (true, "")
    }

    /// 205: 「选择聊天」 closed by its 关闭 (a 「发送给」 sheet over it cancelled first), nothing sent.
    private func forwardClose(_ page: PaneLook, _ why: String) async -> (ok: Bool, why: String) {
        var l = page
        if XiaoLanGroups.sendSheet(l.rows) != nil, let no = XiaoLanGroups.find(l.rows, ["取消"], exact: true, band: 0.2...0.95) {
            _ = await paneTap(no, in: l.rect, wide: 0.05, tall: 0.012)
            l = await groupSettled(l)
        }
        if let x = XiaoLanGroups.find(l.rows, ["关闭", "關閉"], exact: true, band: 0...0.09) {
            _ = await paneTap(x, in: l.rect, wide: 0.03, tall: 0.01)
        }
        DebugLog.write("watch: forward: \(why)")
        return (false, why)
    }

    // MARK: 218 发文件 by fixed steps (198; walked on the iPad 11-28 13:30–13:37, docs/shots-2026-11-28-file. WeChat: ＋ →
    // its panel's page 2 → 文件 → 选择文件's 手机文件 → 选取 → the picker; WeCom: ＋ → page 2 → 文件 (beside 发起收款) →
    // 从本地文件选择 → the picker. The picker opened on 最近项目: 浏览 → 我的 iPad → Echo → orders → the file; WeChat's
    // then 打开 → 「已选中1个文件」 发送, WeCom's sends on the file's click. Page 1 holds 红包 and 转账, page 2 发起收款: only
    // the exact words asked for are ever clicked)

    /// 218: the file at `fileUrl` fetched into Documents/orders (Files: 我的 iPad › Echo › orders) and sent in the chat
    /// `titleList` names; its card seen there. Nil: no file (a picture or a video goes the model's way through 照片).
    func paneSendFileOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async -> (ok: Bool, why: String)? {
        let app = order.app, f = XiaoLanOrders.Fields(order.raw)
        let url = f.s("fileUrl"), kind = XiaoLanOrders.mediaKind(fileType: f.s("fileType"), url: url)
        guard kind != .none else { return nil }
        let name = XiaoLanOrders.fileName(f), stem = XiaoLanGroups.fileStem(name)
        watchStatus = "发文件到 \(order.chat)…"
        do { try await XiaoLanMedia.fetch([url], kind: kind, names: [name]) } catch {
            return (false, "文件没下载下来：\(error.localizedDescription)")
        }
        let opened = await groupOpen(app, order.chat, exact: true, &state)
        guard var chat = opened.look else { return (false, opened.why) }
        // a keyboard over the input bar first (WeChat opens a chat with 简体拼音 up): a system one switched to 小藍,
        // which puts itself down
        if XiaoLanPanes.keyboardTop(chat.rows) != nil || keyboardBridge.onScreen() {
            if !keyboardBridge.onScreen(), !CandidatePicker.ourKeyboardShown(rows: chat.rows) { _ = await showLanAgentKeyboard() }
            _ = await keyboardBridge.type("", enter: false, within: 2, dismiss: true)
            _ = await smallKeyboard(up: false, within: 1.5)
            chat = await groupSettled(chat)
            guard XiaoLanPanes.keyboardTop(chat.rows) == nil else { return (false, "键盘盖住了输入栏，没能收起来") }
        }
        guard let px = WatchOCR.Pixels(chat.crop), let field = XiaoLanPanes.inputField(px) else { return (false, "没找到输入栏") }
        // ＋ at the bar's right end (measured: WeChat 0.925, WeCom 0.935 of the window); its panel must show, else nothing more
        let plusAt = CGPoint(x: app == .wework ? 0.935 : 0.925, y: field.y)
        guard var panel = await groupStep(chat, plusAt, "＋ (input bar)", wide: 0.025, tall: 0.012, until: { XiaoLanGroups.plusPanel($0.rows) }) else {
            return (false, "输入栏的＋没点开")
        }
        if kind == .photos {  // a picture or a video: 照片, page 1
            let r = await sendNewestPhoto(panel, app)
            if r.ok { DebugLog.write("watch: \(app.rawValue): \(order.chat): 「\(name)」 sent from the album (its newest)") }
            return r
        }
        if XiaoLanGroups.find(panel.rows, ["文件"], exact: true, band: 0.5...0.97) == nil,
           let row = XiaoLanGroups.find(panel.rows, ["照片", "拍摄"], exact: true, band: 0.5...0.97) {
            await groupDrag(panel, from: CGPoint(x: 0.8, y: row.y), to: CGPoint(x: 0.25, y: row.y))
            panel = await groupSettled(panel)
        }
        guard let fileItem = XiaoLanGroups.find(panel.rows, ["文件"], exact: true, band: 0.5...0.97) else { return (false, "＋面板里没找到「文件」") }
        var picker: PaneLook
        if app == .wework {
            guard let sheet = await groupStep(panel, fileItem, "文件", wide: 0.035, tall: 0.012, until: { XiaoLanGroups.find($0.rows, ["从本地文件选择"]) != nil }),
                  let local = XiaoLanGroups.find(sheet.rows, ["从本地文件选择"]),
                  let p = await groupStep(sheet, local, "从本地文件选择", wide: 0.2, tall: 0.012, until: { XiaoLanGroups.filePicker($0.rows) })
            else { return (false, "企业微信的「文件 › 从本地文件选择」没打开") }
            picker = p
        } else {
            guard let page = await groupStep(panel, fileItem, "文件", wide: 0.035, tall: 0.012, until: { XiaoLanGroups.find($0.rows, ["手机文件"], exact: true) != nil }),
                  let tab = XiaoLanGroups.find(page.rows, ["手机文件"], exact: true),
                  let tabbed = await groupStep(page, tab, "手机文件", wide: 0.05, tall: 0.01, until: { XiaoLanGroups.find($0.rows, ["选取"], exact: true, band: 0.2...0.9) != nil }),
                  let choose = XiaoLanGroups.find(tabbed.rows, ["选取"], exact: true, band: 0.2...0.9),
                  let p = await groupStep(tabbed, choose, "选取", wide: 0.08, tall: 0.012, until: { XiaoLanGroups.filePicker($0.rows) })
            else { return (false, "微信的「文件 › 手机文件 › 选取」没打开") }
            picker = p
        }
        // the picker, wherever it opened (it may keep its last place): down to orders, then the file
        var chosen: PaneLook?
        for _ in 0..<6 {
            if let file = XiaoLanGroups.pickerFile(picker.rows, stem) {
                chosen = await groupStep(picker, file, "the file \(name)", wide: 0.04, tall: 0.012, until: { l in
                    !XiaoLanGroups.filePicker(l.rows) || XiaoLanGroups.find(l.rows, ["打开", "打開"], exact: true, band: 0...0.09) != nil
                })
                break
            }
            guard let next = XiaoLanGroups.pickerNext(picker.rows),
                  let l = await groupStep(picker, next.at, "picker: \(next.what)", wide: 0.04, tall: 0.012, until: { _ in true }) else { break }
            picker = await groupSettled(l)
        }
        guard var sent = chosen else { return (false, "文件选择器里没找到「\(name)」（我的 iPad › Echo › orders）") }
        if let open = XiaoLanGroups.find(sent.rows, ["打开", "打開"], exact: true, band: 0...0.09) {  // WeChat's picker
            guard let s = await groupStep(sent, open, "打开", wide: 0.03, tall: 0.01, until: { XiaoLanGroups.find($0.rows, ["已选中"]) != nil }) else {
                return (false, "点了「打开」，没回到微信")
            }
            sent = s
        }
        if XiaoLanGroups.find(sent.rows, ["已选中"]) != nil, let go = XiaoLanGroups.find(sent.rows, ["发送"], exact: true, band: 0.1...0.9) {
            guard let s = await groupStep(sent, go, "发送 (file)", wide: 0.03, tall: 0.01, until: { XiaoLanGroups.find($0.rows, ["已选中"]) == nil }) else {
                return (false, "点了「发送」，文件还在「已选中」里")
            }
            sent = s
        }
        let card = await paneLook(sent.side, after: now(), tries: 6) { XiaoLanGroups.find($0.rows, [stem], band: 0.1...0.95) != nil }
        guard let card, XiaoLanGroups.find(card.rows, [stem], band: 0.1...0.95) != nil else {
            return (false, "选了文件，但聊天里没看到「\(name)」")
        }
        DebugLog.write("watch: \(app.rawValue): \(order.chat): 「\(name)」 sent")
        return (true, "")
    }

    /// 198 (218, a picture or a video; WeChat walked 11-28 14:57–14:59 — ＋ → 照片 → its album 「最近项目」 (✕ at its
    /// left; 预览 原图 发送 at its foot), the newest first at the top left, its ring at the cell's top right → 「发送(1)」;
    /// WeCom's taken to be alike, not yet walked): the newest — just saved, dated now — chosen by its ring and sent only
    /// when the foot says one is chosen; else the album closed and nothing sent (the owner's own photos are never sent).
    private func sendNewestPhoto(_ panel: PaneLook, _ app: XiaoLanOrders.App) async -> (ok: Bool, why: String) {
        var p = panel
        if XiaoLanGroups.find(p.rows, ["照片"], exact: true, band: 0.5...0.97) == nil,
           let row = XiaoLanGroups.find(p.rows, ["文件", "个人名片"], exact: true, band: 0.5...0.97) {
            await groupDrag(p, from: CGPoint(x: 0.25, y: row.y), to: CGPoint(x: 0.8, y: row.y))
            p = await groupSettled(p)
        }
        guard let photos = XiaoLanGroups.find(p.rows, ["照片"], exact: true, band: 0.5...0.97),
              let album = await groupStep(p, photos, "照片", wide: 0.035, tall: 0.012, until: { XiaoLanGroups.photoAlbum($0.rows) })
        else { return (false, "＋面板的「照片」没打开相册") }
        let ring = XiaoLanGroups.newestRing(album.rows)
        guard let chosen = await groupStep(album, ring, "the newest photo's ring", wide: 0.015, tall: 0.008, until: { XiaoLanGroups.photoSend($0.rows) != nil }),
              let send = XiaoLanGroups.photoSend(chosen.rows) else {
            if let l = await paneLooks(side: album.side).first(where: { $0.side == album.side }), XiaoLanGroups.photoAlbum(l.rows) {
                _ = await paneTap(CGPoint(x: 0.06, y: XiaoLanGroups.albumHeaderY(l.rows)), in: l.rect, wide: 0.02, tall: 0.01)
            }
            return (false, "相册里没选上最新那张（没看到「发送(1)」），没有发送")
        }
        guard await groupStep(chosen, send, "发送(1)", wide: 0.03, tall: 0.01, until: { !XiaoLanGroups.photoAlbum($0.rows) }) != nil else {
            return (false, "点了「发送(1)」，相册没有关")
        }
        return (true, "")
    }

    // MARK: 跟圈 260 and 爬楼 515 by fixed steps (user 11-28: 「讀完所有朋友圈的内容…要會看日期」「今天群裏發的…過去兩小時…
    // 要記住每次爬樓和跟圈都看到哪裏了，下次再讓看好知道到哪裏結束」)

    /// N94: the window again once it has stopped moving (a page sliding in reads half old, half new).
    private func groupSettled(_ l: PaneLook) async -> PaneLook {
        await feed.settled(quiet: 0.4, least: 0.3, most: 2.0)
        return await paneLooks(side: l.side).first(where: { $0.side == l.side }) ?? l
    }

    private func groupSignature(_ l: PaneLook) -> [UInt8] { WatchOCR.Pixels(l.crop).map(XiaoLanMediaFind.signature) ?? [] }

    /// A slow drag in a window (window fractions), its pointer's curve as every move's.
    private func groupDrag(_ l: PaneLook, from a: CGPoint, to b: CGPoint) async {
        let s = XiaoLanPanes.onScreen(a, in: l.rect), e = XiaoLanPanes.onScreen(b, in: l.rect)
        try? await pointer.swipe(Double(s.x), Double(s.y), Double(e.x), Double(e.y), hold: true)
    }

    /// 260: a friend's 朋友圈 read post by post (each opened: a picture's viewer, kept and counted; any other post's own
    /// page, its words in full), newest first, down to `days` back, else to where the last read began, else `screens`.
    func paneFollowOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let f = XiaoLanOrders.Fields(order.raw)
        let friend = XiaoLanOrders.followFriend(f)
        guard !friend.isEmpty else { return (false, "缺少好友名字（friendName）") }
        let m = XiaoLanOrders.job(type: 260, app: .wechat, f: f, chat: friend)?.moments
        let backend = m.map { !$0.runId.isEmpty && $0.resultURL != nil } ?? false
        let p = f.meta.params
        let days = Int(p.s("days")) ?? Int(f.s("days"))
        let screens = max(1, min(Int(p.s("maxScreens")) ?? Int(f.s("maxScreens")) ?? (days == nil ? 6 : 30), 40))
        watchStatus = "看「\(friend)」的朋友圈…"
        let r = await followRead(friend, days: days, screens: screens, upload: backend ? m : nil, &state)
        _ = await groupList(.wechat, &state)
        if backend, let m {
            _ = await XiaoLanMedia.postMoments(m, ok: r.entries != nil, entries: r.entries, reason: r.why, host: chatTool.host)
        } else if let e = r.entries {
            chatTool.deliver(["type": 260, "friend": friend, "entries": e, "stoppedAt": r.why], for: order)
        }
        return (r.entries != nil, r.entries == nil ? r.why : "")
    }

    private func followRead(_ friend: String, days: Int?, screens: Int, upload m: XiaoLanOrders.Moments?,
                            _ state: inout PaneWatchState) async -> (entries: [[String: Any]]?, why: String) {
        let opened = await groupOpen(.wechat, friend, exact: false, &state)
        guard let chat = opened.look else { return (nil, opened.why) }
        guard let details = await groupStep(chat, XiaoLanGroups.more(.wechat), "聊天详情 (•••)", wide: 0.02, tall: 0.008,
                                            until: { XiaoLanGroups.find($0.rows, ["聊天详情", "聊天詳情"], band: 0...0.09) != nil }) else {
            return (nil, "「\(friend)」的聊天详情没有打开")
        }
        guard let name = details.rows.joined().first(where: { (0.1...0.3).contains(Double($0.box.midY)) && XiaoLanGroups.sameMember($0.text, friend) }) else {
            return (nil, "聊天详情里找不到「\(friend)」的头像")
        }
        guard let profile = await groupStep(details, CGPoint(x: name.box.midX, y: name.box.midY - 0.048), "「\(friend)」's profile",
                                            wide: 0.04, tall: 0.015, until: { l in
            XiaoLanGroups.find(l.rows, ["朋友圈"]) != nil && XiaoLanGroups.find(l.rows, ["发消息", "發消息", "音视频通话", "音視頻通話"]) != nil
        }), let row = XiaoLanGroups.find(profile.rows, ["朋友圈"]) else { return (nil, "「\(friend)」的资料页没有打开（或没有朋友圈入口）") }
        guard var album = await groupStep(profile, CGPoint(x: 0.25, y: row.y), "朋友圈", wide: 0.2, until: { l in
            !XiaoLanGroups.posts(l.rows, WatchOCR.Pixels(l.crop)).isEmpty
                || XiaoLanGroups.find(l.rows, ["仅展示", "僅展示", "暂无", "未开启朋友圈", "没有更多"]) != nil
        }) else { return (nil, "「\(friend)」的朋友圈没有打开") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let since = days.flatMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
        let mark = PaneMarks.follow(friend)
        var entries: [[String: Any]] = [], seen = Set<String>(), year: Int?, why = "", shots = 0, newest: [String] = []
        screensLoop: for screen in 0..<screens {
            album = await groupSettled(album)
            if let y = XiaoLanGroups.yearHeader(album.rows).first { year = y.year }
            var posts = XiaoLanGroups.posts(album.rows, WatchOCR.Pixels(album.crop))
            let last = screen == screens - 1
            if !last, posts.count > 1 { posts.removeLast() }  // the bottom one may be cut: read whole on the next screen
            for p in posts {
                let rough = p.date + "\u{1}" + p.text
                guard seen.insert(rough).inserted else { continue }
                let day = XiaoLanGroups.postDay(p.date, year: year)
                if let since, let day, day < since { why = "读到\(days ?? 0)天前为止"; break screensLoop }
                // the post opened: a picture's viewer, or its own page
                let tapAt = p.picture.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 0.5, y: p.top + 0.03)
                guard let open = await groupStep(album, tapAt, "post 「\(p.date)」 opened", wide: 0.06, tall: 0.02, until: { l in
                    XiaoLanGroups.viewerTitle(l.rows) != nil || XiaoLanGroups.postDetail(l.rows, friend: friend) != nil
                }) else {
                    // neither a picture's viewer nor a post's page (a video playing, a link's page): back, kept as seen
                    if let here = await paneLooks(side: album.side).first(where: { $0.side == album.side }),
                       XiaoLanGroups.posts(here.rows, nil).isEmpty { _ = await paneBackClick(here, "wechat") }
                    entries.append(["fp": XiaoLanOrders.fingerprint(friend + "\n" + p.date + "\n" + p.text), "text": p.text,
                                    "summary": p.picture == nil ? "打不开（\(p.date)）" : "视频或打不开的图片（\(p.date)）",
                                    "time": p.date, "locateText": p.text.isEmpty ? p.date : p.text, "isVideo": p.picture != nil,
                                    "isLink": false, "imageCount": 0, "imageUrls": [String]()])
                    if let back = await paneLook(album.side, after: now(), tries: 5, until: { !XiaoLanGroups.posts($0.rows, nil).isEmpty }) { album = back }
                    continue
                }
                var text = p.text, time = p.date, count = 0, urls: [String] = []
                if let title = XiaoLanGroups.viewerTitle(open.rows) {
                    time = title
                    let caption = XiaoLanGroups.viewerCaption(open.rows)
                    if !caption.isEmpty { text = caption }
                    let pics = await followPictures(open, title: title, upload: shots < 9 ? m : nil)
                    (count, urls) = (pics.count, pics.urls)
                    shots += 1
                } else if let d = XiaoLanGroups.postDetail(open.rows, friend: friend) {
                    (text, time) = (d.text.isEmpty ? text : d.text, d.time)
                    _ = await paneBackClick(open, "wechat")
                }
                let key = XiaoLanOrders.fingerprint(friend + "\n" + time + "\n" + text)
                if newest.count < 3 { newest.append(key) }
                if mark.contains(key), days == nil {
                    why = "读到上次读过的地方为止"
                    if let back = await paneLook(album.side, after: now(), tries: 5, until: { !XiaoLanGroups.posts($0.rows, nil).isEmpty }) { album = back }
                    break screensLoop
                }
                let isLink = XiaoLanMediaFind.url(in: text) != nil
                var e: [String: Any] = ["fp": key, "text": text, "summary": text.isEmpty ? "图片（\(time)）" : "", "time": time,
                                        "locateText": text.isEmpty ? time : text, "isVideo": false, "isLink": isLink,
                                        "imageCount": count, "imageUrls": urls]
                if count > 0 { e["imagesComplete"] = urls.count == count }
                entries.append(e)
                if let back = await paneLook(album.side, after: now(), tries: 5, until: { !XiaoLanGroups.posts($0.rows, nil).isEmpty }) { album = back }
                await groupPause()
            }
            guard !last else { why = why.isEmpty ? "读了\(screens)屏" : why; break }
            let before = groupSignature(album)
            await groupDrag(album, from: CGPoint(x: 0.6, y: 0.8), to: CGPoint(x: 0.6, y: 0.4))
            guard let next = await paneLooks(after: now(), side: album.side).first(where: { $0.side == album.side }) else { break }
            if XiaoLanMediaFind.sameSignature(before, groupSignature(next)) { why = "读到最早一条"; break }
            album = next
        }
        if !newest.isEmpty { PaneMarks.setFollow(friend, newest) }
        DebugLog.write("watch: 跟圈: \(entries.count) post(s) of \(friend); \(why)")
        return (entries, why)
    }

    /// A picture post's viewer: each picture kept as the window shows it (uploaded when the run wants them), the next one
    /// by a swipe, until the title (the post's time) changes or nothing moves; then back to the album. A video's player
    /// has no such title: zero pictures.
    private func followPictures(_ viewer: PaneLook, title: String, upload m: XiaoLanOrders.Moments?) async -> (count: Int, urls: [String]) {
        var look = viewer, count = 0, urls: [String] = []
        for k in 0..<9 {
            if k > 0 {
                let before = groupSignature(look)
                await groupDrag(look, from: CGPoint(x: 0.85, y: 0.5), to: CGPoint(x: 0.15, y: 0.5))
                guard let n = await paneLook(look.side, after: now(), tries: 4, until: { XiaoLanGroups.viewerTitle($0.rows) != nil }),
                      XiaoLanGroups.viewerTitle(n.rows) == title, !XiaoLanMediaFind.sameSignature(before, groupSignature(n)) else { break }
                look = n
            }
            count += 1
            guard let m else { continue }
            try? await Task.sleep(nanoseconds: 1_200_000_000)  // the picture settles
            guard let fresh = await paneLooks(after: now(), side: look.side).first(where: { $0.side == look.side }) else { continue }
            let crop = fresh.crop
            if let jpeg = await Task.detached(operation: { XiaoLanMedia.trimmed(crop) }).value,
               let url = await XiaoLanMedia.upload(jpeg, moments: m, host: chatTool.host) { urls.append(url) }
        }
        _ = await paneBackClick(look, "wechat")
        return (count, urls)
    }

    /// 515 爬楼: a chat read up screen by screen, each line with the time of the time line over it, down to `minutes` back
    /// or today's start, else to where the last read began, or the words asked for, or `screens`.
    func paneClimbOrder(_ order: ChatToolLink.Command, _ state: inout PaneWatchState) async -> (ok: Bool, why: String) {
        let f = XiaoLanOrders.Fields(order.raw), app = order.app
        guard let chat = f.list("titleList").first else { return (false, "缺少会话名称（titleList）") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let until = f.s("untilText")
        var since: Date?
        if let minutes = Int(f.s("minutes")), minutes > 0 { since = Date().addingTimeInterval(-Double(minutes) * 60) }
        if f.bool("today") == true || f.s("today") == "true" { since = cal.startOfDay(for: Date()) }
        let screens = max(1, min(Int(f.s("maxScreens")) ?? (since == nil ? 10 : 40), 60))
        watchStatus = "爬楼 \(chat)…"
        let opened = await groupOpen(app, chat, exact: false, &state)
        guard var look = opened.look else { return (false, opened.why) }
        if keyboardBridge.onScreen() { _ = await keyboardBridge.type("", enter: false, within: 1.5, dismiss: true) }
        let mark = PaneMarks.climb(app, chat)
        var pages: [[WatchReport.Line]] = [], times: [String: String] = [:], why = "", newest: [String] = []
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm"
        climb: for i in 0..<screens {
            look = await groupSettled(look)
            guard let t = XiaoLanGroups.titleName(look.view), WatchChatOpen.sameChat(t, listName: chat), case .chat(let title) = look.view else {
                why = "离开了「\(chat)」（打开了别的页面），停下"
                break
            }
            let labels = look.rows.joined().compactMap { p -> (Date, Double)? in
                guard (0.3...0.7).contains(Double(p.box.midX)), let d = XiaoLanGroups.chatTime(p.text) else { return nil }
                return (d, Double(p.box.midY))
            }.sorted { $0.1 < $1.1 }
            var lines = WatchOCR.screen(look.crop, title: title, rows: look.rows)?.lines ?? []
            func when(_ l: WatchReport.Line) -> Date? { l.y.flatMap { y in labels.last(where: { $0.1 < y })?.0 } }
            if i == 0 { newest = lines.suffix(3).map { $0.sender + "\u{2}" + $0.text } }
            var stop = false
            if let since {
                let kept = lines.filter { l in (when(l).map { $0 >= since }) ?? true }
                if kept.count < lines.count || (labels.first.map { $0.0 < since } ?? false) { stop = true; why = "读到要求的时间为止" }
                lines = kept
            }
            if since == nil, until.isEmpty, let at = lines.lastIndex(where: { mark.contains($0.sender + "\u{2}" + $0.text) }) {
                lines = Array(lines[(at + 1)...])
                stop = true
                why = "读到上次读过的地方为止"
            }
            for l in lines { if let d = when(l) { times[l.sender + "\u{2}" + l.text] = stamp.string(from: d) } }
            pages.append(lines)
            if !until.isEmpty, lines.contains(where: { XiaoLanGroups.bare($0.text).contains(XiaoLanGroups.bare(until)) }) { why = "读到「\(until)」为止"; break }
            if stop || i == screens - 1 { if why.isEmpty { why = "读了\(i + 1)屏" }; break }
            let before = groupSignature(look)
            await groupDrag(look, from: CGPoint(x: 0.5, y: 0.3), to: CGPoint(x: 0.5, y: 0.66))
            guard var next = await paneLooks(after: now(), side: look.side).first(where: { $0.side == look.side }) else { break }
            if XiaoLanMediaFind.sameSignature(before, groupSignature(next)) {  // older ones may still be loading: once more
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await groupDrag(next, from: CGPoint(x: 0.5, y: 0.3), to: CGPoint(x: 0.5, y: 0.66))
                guard let again = await paneLooks(after: now(), side: look.side).first(where: { $0.side == look.side }) else { break }
                if XiaoLanMediaFind.sameSignature(before, groupSignature(again)) { why = "已经到最上面"; break climb }
                next = again
            }
            look = next
        }
        if !newest.isEmpty { PaneMarks.setClimb(app, chat, newest) }
        let lines = XiaoLanGroups.climbMerge(pages)
        let bean: [String: Any] = ["type": 515, "titleList": [chat], "screens": pages.count, "stoppedAt": why,
                                   "messageList": lines.map { l -> [String: Any] in
                                       ["sender": l.mine ? "我" : l.sender, "text": l.text, "mine": l.mine,
                                        "time": times[l.sender + "\u{2}" + l.text] ?? ""]
                                   }]
        (app == .wework ? weworkTool : chatTool).deliver(bean, for: order)
        DebugLog.write("watch: 爬楼 \(chat) (\(app.rawValue)): \(lines.count) line(s), \(pages.count) screen(s); \(why)")
        _ = await groupList(app, &state)
        return (true, "")
    }

    // MARK: 198 friend requests accepted by themselves (AutoAccept)

    /// After a pass: a window on its chat list whose 通讯录 is marked, its app's switch on and its time come, has one
    /// request accepted (the oldest), then goes back to its chats; the next one later, after a random gap.
    func paneAutoAccept(_ looks: [PaneLook], _ state: inout PaneWatchState) async {
        for side in looks.map(\.side) {
            guard let app = state.apps[side], AutoAccept.on(app) else { continue }
            let t = now()
            guard t >= AutoAccept.idleUntil[app, default: 0],
                  AutoAccept.due(AutoAccept.accepted[app, default: []], next: AutoAccept.nextAt[app, default: 0], at: t, perMinute: AutoAccept.perMinute)
            else { continue }
            // the pass's own read first (no new look on every pass), then the window as it is now (the pass may have
            // left it in a chat): on its chat list, its 通讯录 marked (or some left from the last time, the mark gone)
            let more = AutoAccept.more.contains(app)
            guard let seen = looks.first(where: { $0.side == side }), let seenPx = WatchOCR.Pixels(seen.crop),
                  more || AutoAccept.contactsMarked(seen.rows, seenPx) else { continue }
            guard let look = await paneLooks(side: side).first(where: { $0.side == side }), look.view == .list,
                  XiaoLanPanes.listTitles.contains(WatchOCR.titled(XiaoLanPanes.titleLine(look.rows)).name),
                  let px = WatchOCR.Pixels(look.crop), more || AutoAccept.contactsMarked(look.rows, px) else { continue }
            if ordersWaiting || repliesComing { return }
            watchStatus = "通过好友申请…"
            let name = await acceptOne(app, look)
            if let name {
                AutoAccept.accepted[app, default: []].append(now())
                AutoAccept.accepted[app] = AutoAccept.accepted[app]?.filter { now() - $0 < 120 }
                let g = AutoAccept.gap(AutoAccept.perMinute)
                AutoAccept.nextAt[app] = now() + g
                DebugLog.write(String(format: "watch: auto-accept: %@ %@ accepted; the next not before %.0f s", app.rawValue, name, g))
            } else {
                AutoAccept.idleUntil[app] = now() + 60  // nothing waiting after all (another mark), or it did not go: a minute
            }
            await acceptBackToChats(app, &state)
        }
    }

    /// One request, the lowest waiting on the requests' page (the first one made); its name, nil when none went.
    private func acceptOne(_ app: XiaoLanOrders.App, _ list: PaneLook) async -> String? {
        guard let tab = AutoAccept.tab(list.rows, ["通讯录", "通訊錄"]) else { return nil }
        let entry = app == .wework ? ["添加客户", "添加客戶"] : ["新的朋友", "新朋友"]
        let landmarks = entry + ["企业通讯录", "标签与朋友权限", "群聊"]
        guard var contacts = await groupStep(list, tab, "通讯录 (\(app.rawValue))", wide: 0.05, tall: 0.012,
                                             until: { XiaoLanGroups.find($0.rows, landmarks) != nil }) else { return nil }
        if XiaoLanGroups.find(contacts.rows, entry) == nil {  // the contacts scrolled down: back to their top
            await groupDrag(contacts, from: CGPoint(x: 0.5, y: 0.3), to: CGPoint(x: 0.5, y: 0.85))
            contacts = await groupSettled(contacts)
        }
        guard let row = XiaoLanGroups.find(contacts.rows, entry) else {
            DebugLog.write("watch: auto-accept: \(app.rawValue): no 「\(entry[0])」 on its contacts")
            return nil
        }
        guard var page = await groupStep(contacts, CGPoint(x: 0.4, y: row.y), entry[0], wide: 0.2,
                                         until: { AutoAccept.requestsPage($0.rows) }) else { return nil }
        for _ in 0..<4 where AutoAccept.maybeBelow(page.rows) {  // the oldest may be under the window's end: down to it
            let before = page.rows.joined().map(\.text)
            await groupDrag(page, from: CGPoint(x: 0.5, y: 0.75), to: CGPoint(x: 0.5, y: 0.35))
            let next = await groupSettled(page)
            if next.rows.joined().map(\.text) == before { break }  // the list's end
            page = next
        }
        guard let button = AutoAccept.waiting(page.rows).last else {
            AutoAccept.more.remove(app)
            DebugLog.write("watch: auto-accept: \(app.rawValue): nothing waiting on 「\(entry[0])」")
            return nil
        }
        AutoAccept.more.insert(app)  // the page is open now: its mark is gone, the rest go on by this
        let name = AutoAccept.requester(page.rows, at: Double(button.y))
        let go = ["前往验证", "通过验证", "前往驗證", "通過驗證"], verify = ["通过朋友验证", "通過朋友驗證", "为对方添加备注", "為對方添加備註"]
        guard var at = await groupStep(page, button, "查看 「\(name)」", wide: 0.04, tall: 0.012, until: { l in
            XiaoLanGroups.find(l.rows, go) != nil || XiaoLanGroups.find(l.rows, verify, band: 0...0.09) != nil
        }) else { return nil }
        if XiaoLanGroups.find(at.rows, verify, band: 0...0.09) == nil, let g = XiaoLanGroups.find(at.rows, go) {
            guard let v = await groupStep(at, g, "前往验证 「\(name)」", wide: 0.12, tall: 0.012,
                                          until: { XiaoLanGroups.find($0.rows, verify, band: 0...0.09) != nil }) else { return nil }
            at = v
        }
        guard let done = XiaoLanGroups.find(at.rows, ["完成"], exact: true) else { return nil }
        guard await groupStep(at, done, "完成 「\(name)」", wide: 0.06, tall: 0.012,
                              until: { XiaoLanGroups.find($0.rows, ["发消息", "發消息"]) != nil }) != nil else { return nil }
        return name
    }

    /// Back from the requests to the app's chat list: backs to its contacts, then its first tab (微信 / 消息).
    private func acceptBackToChats(_ app: XiaoLanOrders.App, _ state: inout PaneWatchState) async {
        guard let l = await groupList(app, &state) else { return }
        let chats = app == .wework ? ["消息"] : ["微信"]
        if XiaoLanPanes.listTitles.contains(WatchOCR.titled(XiaoLanPanes.titleLine(l.rows)).name) { return }
        guard let tab = AutoAccept.tab(l.rows, chats) else { return }
        _ = await groupStep(l, tab, "back to \(chats[0])", wide: 0.05, tall: 0.012,
                            until: { XiaoLanPanes.listTitles.contains(WatchOCR.titled(XiaoLanPanes.titleLine($0.rows)).name) })
    }
}

/// 197 (user 11-28: 「要記住每次爬樓和跟圈都看到哪裏了，下次再讓看好知道到哪裏結束」): the newest posts / lines each read
/// began with, per friend and per chat, kept across launches; the next read with no time asked stops there.
@MainActor enum PaneMarks {
    static let key = "xiaolanReadMarksV1"
    private static func all() -> [String: [String]] { UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:] }
    private static func set(_ k: String, _ v: [String]) {
        var d = all()
        d[k] = v
        UserDefaults.standard.set(d, forKey: key)
    }
    static func follow(_ friend: String) -> Set<String> { Set(all()["follow|" + friend] ?? []) }
    static func setFollow(_ friend: String, _ keys: [String]) { set("follow|" + friend, keys) }
    static func climb(_ app: XiaoLanOrders.App, _ chat: String) -> Set<String> { Set(all()["climb|\(app.rawValue)|" + chat] ?? []) }
    static func setClimb(_ app: XiaoLanOrders.App, _ chat: String, _ keys: [String]) { set("climb|\(app.rawValue)|" + chat, keys) }
}
#endif
