import UIKit

/// 172 (user 11-25: "我要的是個微和企微都要守候…而且還是要同時兩個都守候"): on the iPad 小藍 watches WeChat and WeCom
/// side by side (iPadOS windowed apps, two tiles), the whole screen shared, both looked at on every pass.
///
/// Which side holds which app, and how wide each is, is read off every frame (user: "不是說每次都固定個人微信就是左邊";
/// "有時候可能左邊寬一些…中間都會有個縫"): the two windows are split at the gap between them, where the wallpaper shows,
/// and each window is told by its tab bar (WeChat: 通讯录 + 发现; WeCom: 工作台, or 邮件 + 文档). A window then reads like
/// a phone screen: everything here works on the window's own picture (its fractions 0–1), and taps are mapped back.
/// Measured on the customer's iPad 9 (11-25, 960 x 1280 frames): the gap 0.494–0.503 wide, the windows from the top to
/// 0.898 (the Dock below); the list title band ~0.058 of the window, row titles from 0.18–0.21 across, the red mark on
/// the avatar's top-right corner ~0.03–0.04 left of and ~0.01 above the title's middle.
@MainActor enum XiaoLanPanes {
    typealias Piece = CandidatePicker.Piece
    enum View: Equatable { case list, chat(String), unknown }

    // MARK: Windows

    /// The windows on the screen, left to right (fractions of the frame): two when a gap splits it, else the whole.
    static func windows(_ px: WatchOCR.Pixels) -> [CGRect] {
        let w = px.w, h = px.h
        guard w > 40, h > 40 else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        func luma(_ x: Int, _ y: Int) -> Int {
            let i = (y * w + x) * 4
            return (Int(px.bytes[i]) * 3 + Int(px.bytes[i + 1]) * 6 + Int(px.bytes[i + 2])) / 10
        }
        // A window's side edge: a sharp change at the same column all the way down (text and avatars never are).
        let ys = stride(from: 0.12, through: 0.85, by: 0.01).map { Int($0 * Double(h)) }
        func edge(_ x: Int) -> Double {
            Double(ys.filter { abs(luma(x, $0) - luma(x - 1, $0)) >= 30 }.count) / Double(ys.count)
        }
        let lo = Int(0.12 * Double(w)), hi = Int(0.88 * Double(w))
        let scored = (lo..<hi).map { (x: $0, s: edge($0)) }.filter { $0.s >= 0.7 }
        // The gap: two such edges close together (the wallpaper between them, 0.3–4% of the width).
        var best: (a: Int, b: Int, s: Double)?
        for e in scored {
            // 181 (user 11-25: "寬度他可能會自由調整…有時候左邊寬一些，有時候右邊寬一些"): the owner drags the windows;
            // the gap is wherever it is and may be wider than 180's 4% (now up to 10%).
            for f in scored where f.x - e.x >= max(2, w * 3 / 1000) && f.x - e.x <= w / 10 {
                let s = e.s + f.s
                if best == nil || s > best!.s { best = (e.x, f.x, s) }
            }
        }
        guard let gap = best else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        // 181: a window moved in from the screen's side has an outer edge too; the wallpaper outside it is no part of
        // it (its taps are fractions of the window). Each window stays at least a fifth of the screen wide.
        let outerLeft = (1..<max(1, gap.a - w / 5)).first { edge($0) >= 0.7 } ?? 0
        let outerRight = stride(from: w - 1, to: min(w - 1, gap.b + w / 5), by: -1).first { edge($0) >= 0.7 } ?? w
        let (l0, l1) = (Double(outerLeft) / Double(w), Double(gap.a) / Double(w))
        let (r0, r1) = (Double(gap.b) / Double(w), Double(outerRight) / Double(w))
        return [CGRect(x: l0, y: 0, width: l1 - l0, height: windowBottom(luma, w: w, h: h, from: outerLeft, to: gap.a)),
                CGRect(x: r0, y: 0, width: r1 - r0, height: windowBottom(luma, w: w, h: h, from: gap.b, to: outerRight))]
    }

    /// Where a window ends above the Dock: the first row from 0.75 down that changes sharply nearly all the way across.
    private static func windowBottom(_ luma: (Int, Int) -> Int, w: Int, h: Int, from: Int, to: Int) -> Double {
        let span = to - from
        guard span > 20 else { return 1 }
        let xs = stride(from: from + span / 10, to: to - span / 10, by: max(1, span / 60)).map { $0 }
        var y = Int(0.75 * Double(h))
        while y < h {
            let sharp = xs.filter { abs(luma($0, y) - luma($0, y - 1)) >= 30 }.count
            if Double(sharp) >= 0.7 * Double(xs.count) { return Double(y) / Double(h) }
            y += 1
        }
        return 1
    }

    /// One window's picture, as its own frame.
    static func crop(_ jpeg: Data, _ r: CGRect) -> Data? {
        guard let image = UIImage(data: jpeg)?.cgImage else { return nil }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: r.minX * full.width, y: r.minY * full.height, width: r.width * full.width,
                          height: r.height * full.height).integral.intersection(full)
        guard !rect.isEmpty, let part = image.cropping(to: rect) else { return nil }
        return UIImage(cgImage: part).jpegData(compressionQuality: 0.92)
    }

    /// A point in a window (its fractions) on the whole screen.
    static func onScreen(_ p: CGPoint, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
    }

    // MARK: What a window shows

    /// The app in a window, by its tab bar (shown on the chat list only).
    static func app(_ rows: [[Piece]]) -> XiaoLanOrders.App? {
        let bar = rows.joined().filter { $0.box.midY > 0.85 }.map(\.text).joined()
        if bar.contains("工作台") || (bar.contains("邮件") && bar.contains("文档")) || (bar.contains("郵件") && bar.contains("文檔")) {
            return .wework
        }
        if (bar.contains("通讯录") || bar.contains("通訊錄")) && (bar.contains("发现") || bar.contains("發現")) { return .wechat }
        // 181 (Echo 180, 11-25, after the owner changed the windows' widths): WeChat's tab bar was not read in its window,
        // its list title 微信 was; the window was nobody's, so nothing was sent there and its red marks were left.
        return listApp(WatchOCR.titled(titleLine(rows)).name)
    }

    /// 181 (user 11-25: "它兩邊不論怎么多寬，它自由的寬度都可以看到"): a chat list told without reading a word: the chosen
    /// tab at the bottom left is WeChat's green or WeCom's blue. Measured on the customer's iPad at four widths (11-25):
    /// WeChat 41–54 green samples and no blue, WeCom 28–30 blue and no green.
    static func tabApp(_ px: WatchOCR.Pixels) -> XiaoLanOrders.App? {
        var green = 0, blue = 0
        for fy in stride(from: 0.90, through: 0.995, by: 0.005) {
            for fx in stride(from: 0.02, through: 0.35, by: 0.005) {
                let (r, g, b) = px.rgb(fx, fy)
                if g > 150 && r < 90 && b < 150 && g - r > 80 { green += 1 }
                if b > 190 && r < 110 && b - r > 100 && g < 190 { blue += 1 }
            }
        }
        if green >= 12 && blue <= 3 { return .wechat }
        if blue >= 12 && green <= 3 { return .wework }
        return nil
    }

    /// 181: the app whose chat list carries this title (WeChat's 微信, WeCom's 消息).
    static func listApp(_ title: String) -> XiaoLanOrders.App? {
        switch title {
        case "微信", "WeChat", "Chats": return .wechat
        case "消息", "Messages": return .wework
        default: return nil
        }
    }

    /// The first line in a window's title band: WeCom puts "外部群 | 群主: …" under a group's name (0.071 vs 0.050).
    static func titleLine(_ rows: [[Piece]]) -> String {
        let lines = rows.map { $0.filter { (0.035...0.09).contains($0.box.midY) && (0.18...0.82).contains($0.box.midX) } }
            .filter { !$0.isEmpty }
            .sorted { ($0.map(\.box.midY).min() ?? 1) < ($1.map(\.box.midY).min() ?? 1) }
        return (lines.first ?? []).sorted { $0.box.minX < $1.box.minX }.map(\.text).joined()
            .trimmingCharacters(in: .whitespaces)
    }

    /// 181: what a window's bottom band reads (its tab bar on a list), for the log when its app is not told.
    static func bottomText(_ rows: [[Piece]]) -> String {
        rows.joined().filter { $0.box.midY > 0.85 }.map(\.text).joined(separator: " ")
    }

    /// The chat list (its tab bar), a chat (its centred title, no tab bar), or neither.
    static func view(_ rows: [[Piece]]) -> View {
        if app(rows) != nil { return .list }
        if cancelButton(rows) != nil { return .unknown }  // searching: the field's words are no chat's title
        let title = titleLine(rows)
        // 180 (Echo 178, 11-25): with 小藍's keyboard up the tab bar is covered, and the WeChat list was read as a chat
        // called 微信 (every row reported as a message), WeCom's as one called 消息. Their titles say they are lists.
        if listTitles.contains(WatchOCR.titled(title).name) { return .list }
        return title.isEmpty ? .unknown : .chat(title)
    }

    /// 180: a chat's app by what only WeCom's chats show: the quick bar over the input (企业名片, 快捷回复, 发起收款).
    static func chatApp(_ rows: [[Piece]]) -> XiaoLanOrders.App { weworkBar(rows) ? .wework : .wechat }

    /// 182 (Echo 181, 11-26: WeCom left in 企微测试群, a title WeChat has too, was nobody's window: "no chat of WeChat or
    /// WeCom; left alone", its list and the owner's private message never looked at): WeCom's quick bar over the input
    /// tells its chats wherever they are.
    static func weworkBar(_ rows: [[Piece]]) -> Bool {
        let words = ["企业名片", "企業名片", "快捷回复", "快捷回覆", "发起收款", "發起收款", "推荐客服", "推薦客服"]
        return rows.joined().contains { p in words.contains { p.text.contains($0) } }
    }

    /// 182 (Echo 181, 11-26: a chat left on its 按住 说话 bar, the white button taken for the input field: "小蓝输入法没有
    /// 打出字"): the voice bar's button reads 按住 说话; the switch back to typing is the round button at the bar's left.
    /// WeCom's typing field reads 发消息或按住…, which does not start with 按住.
    static func voiceToggle(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { p in
            let t = p.text.filter { !$0.isWhitespace }
            return p.box.midY > 0.55 && (t.hasPrefix("按住说") || t.hasPrefix("按住說") || t.hasPrefix("按住讲") || t.hasPrefix("按住講"))
        }.map { CGPoint(x: 0.055, y: $0.box.midY) }
    }

    /// 182 (user 11-26: "點聊天空白處收鍵盤"; Esc did not put 小藍's keyboard down, and it covered the other window's
    /// tab bar): a spot of bare chat background above the input bar, clear across the middle (no bubble, no time line;
    /// avatars stay outside 0.15–0.85), lowest first. Nil when there is none.
    static func blankSpot(_ px: WatchOCR.Pixels, above bottom: Double) -> CGPoint? {
        func bare(_ y: Double) -> Bool {
            stride(from: 0.15, through: 0.85, by: 0.035).allSatisfy { x in
                let (r, g, b) = px.rgb(x, y)
                return (225...244).contains(r) && (225...244).contains(g) && (225...247).contains(b)
                    && max(r, g, b) - min(r, g, b) <= 8
            }
        }
        var y = bottom - 0.03
        while y > 0.15 {
            if bare(y), bare(y - 0.012), bare(y + 0.012) { return CGPoint(x: 0.5, y: y) }
            y -= 0.006
        }
        return nil
    }

    /// 180: a chat of WeChat or WeCom by its background down the window's left margin: WeChat (237, 237, 237), WeCom
    /// (236, 237, 241), measured 11-25; the Settings app's grouped background (242, 242, 247) or white is neither.
    static func chatBackground(_ px: WatchOCR.Pixels) -> Bool {
        let ys = Array(stride(from: 0.3, through: 0.7, by: 0.05))
        let hits = ys.filter { y in
            let (r, g, b) = px.rgb(0.015, y)
            return (230...240).contains(r) && (230...240).contains(g) && (230...244).contains(b) && b - r <= 6
        }.count
        return hits * 2 > ys.count
    }

    /// The chat lists' own titles (WeChat's carries the unread count: 微信(3)).
    static let listTitles: Set<String> = ["微信", "消息", "WeChat", "Chats", "Messages"]

    /// Where to tap to type: the white field at the bottom of a chat window, found from the bottom up (WeCom's row of
    /// buttons above it, 企业名片 / 快捷回复, is grey-white and left alone). Three columns, two of them white: the hint
    /// text (轻触说话转文字, 发消息或按住…) and WeChat's microphone cover one at most. Tapped left of the middle, on the
    /// hint, clear of the microphone.
    static func inputField(_ px: WatchOCR.Pixels) -> CGPoint? {
        func white(_ y: Double) -> Bool {
            [0.135, 0.50, 0.66].filter { x in
                let (r, g, b) = px.rgb(x, y)
                return r >= 250 && g >= 250 && b >= 250
            }.count >= 2
        }
        let step = 1 / Double(px.h)
        var y = 1 - step, bottom: Double?
        while y > 0.3 {  // 180: with the keyboard up the field sits right over it, half way up the window
            if white(y) {
                if bottom == nil { bottom = y }
            } else if let b = bottom {
                if b - y >= 0.015 { return CGPoint(x: 0.30, y: (b + y) / 2) }
                bottom = nil
            }
            y -= step
        }
        return nil
    }

    /// List entries that are no one's chat (WeChat's, and WeCom's own news, team and tools).
    static let notChats: Set<String> = WatchChatOpen.notChats.union(
        ["行业资讯", "行業資訊", "企业微信团队", "企業微信團隊", "企业微信", "通知", "审批", "審批", "打卡", "日程", "会议", "會議",
         "微盘", "微盤", "邮件", "郵件", "汇报", "匯報", "公告", "待办", "待辦"])

    /// A list title as a chat's name: no time read with it, no WeCom tag after it ("外部", "@微信").
    static func listName(_ text: String) -> String {
        var t = WatchOCR.withoutIconTail(WatchChatOpen.withoutTime(text.filter { !$0.isWhitespace }))
        for tag in ["外部", "@微信", "＠微信"] where t.hasSuffix(tag) && t.count > tag.count { t = String(t.dropLast(tag.count)) }
        return t
    }

    /// The list rows: a title with a smaller preview line just under it.
    static func entries(_ rows: [[Piece]]) -> [(name: String, box: CGRect)] {
        let body = rows.compactMap { row -> (text: String, box: CGRect)? in
            let pieces = row.filter { (0.12...0.62).contains($0.box.minX) && (0.12...0.92).contains($0.box.midY) }
            guard !pieces.isEmpty else { return nil }
            return (pieces.map(\.text).joined(), pieces.reduce(CGRect.null) { $0.union($1.box) })
        }
        return body.compactMap { t in
            let gaps: [CGFloat] = body.filter { p in abs(p.box.minX - t.box.minX) <= 0.04 }.map { p in p.box.midY - t.box.midY }
            guard let below = gaps.filter({ d in (0.015...0.045).contains(d) }).min() else { return nil }
            // 181 (Echo 180, 11-25: "同事们在看《安克被告…》", 行业资讯's preview, was opened as a chat once the window's
            // scale changed): a line with a title right above it, closer than 1.5 times the line under it, is a preview.
            if gaps.contains(where: { d in (0.005...(below * 1.5)).contains(-d) }) { return nil }
            let name = listName(t.text)
            return name.isEmpty ? nil : (name: name, box: t.box)
        }
    }

    /// Where a row's red mark sits: the avatar's top-right corner, just left of and above the title.
    static func badgeArea(_ title: CGRect) -> CGRect {
        CGRect(x: title.minX - 0.075, y: title.midY - 0.045, width: 0.07, height: 0.05)
    }

    /// The chats with a red mark, top first (fractions of the window): the row to tap.
    static func marked(_ rows: [[Piece]], red: (CGRect) -> Double) -> [(name: String, at: CGPoint)] {
        entries(rows).filter { !notChats.contains($0.name) && red(badgeArea($0.box)) >= WatchChatOpen.badgeShare }
            .sorted { $0.box.midY < $1.box.midY }
            .map { (name: $0.name, at: CGPoint(x: 0.5, y: $0.box.midY)) }
    }

    /// Back from a chat to the list: the arrow at the window's top-left.
    static let back = CGPoint(x: 0.055, y: 0.058)
    /// 181 (Echo 180, 11-25: the left window's back arrow was clicked unseen, then again in place, and the second click
    /// closed WeChat; its ••• and close sit ~50 px above the arrow): where the pointer is found first, on the chat below
    /// the arrow (hovering there does nothing), before the short hop up to the arrow. A second spot if not seen there.
    static let backStages = [CGPoint(x: 0.16, y: 0.14), CGPoint(x: 0.30, y: 0.22)]

    // MARK: Delete (174, user 11-25: "苹果设备删除聊天窗口长按删不了，要横滑，有一个红色的删除")

    /// The red 删除 a swipe brought out on the row titled `row` (window fractions): the word read there, or else the
    /// red block at the row's right end (WeChat ~(243, 84, 81), WeCom ~(227, 77, 69); system accounts have none).
    static func deleteButton(_ rows: [[Piece]], row: CGRect, red: (CGRect) -> Double) -> CGPoint? {
        if let p = rows.joined().first(where: { deleteWords.contains($0.text.trimmingCharacters(in: .whitespaces))
            && $0.box.midX > 0.5 && abs($0.box.midY - row.midY) < 0.05 }) {
            return CGPoint(x: p.box.midX, y: p.box.midY)
        }
        let band = CGRect(x: 0.8, y: row.midY - 0.02, width: 0.18, height: 0.04)
        return red(band) >= 0.4 ? CGPoint(x: band.midX, y: band.midY) : nil
    }
    static let deleteWords: Set<String> = ["删除", "刪除", "Delete"]

    /// After the red 删除 (seen 11-25, the user tapping it): WeChat widens the row's red button into
    /// 「清空记录同时不显示聊天」, tapped again to delete; WeCom asks in an alert 「此聊天及其聊天记录将从你所有设备中删除。」
    /// with 取消 | 删除, the row's own buttons still showing dimmed behind it. The confirming button: the widened red one,
    /// or the 删除 on the line of a 取消 to its left (not the row's).
    static func confirmDelete(_ rows: [[Piece]]) -> CGPoint? {
        let pieces = Array(rows.joined())
        if let wide = pieces.first(where: { $0.text.contains("清空记录") || $0.text.contains("不显示聊天") }) {
            return CGPoint(x: wide.box.midX, y: wide.box.midY)
        }
        let cancels = pieces.filter { ["取消", "Cancel"].contains($0.text.trimmingCharacters(in: .whitespaces)) }
        return pieces.first { p in
            deleteWords.contains(p.text.trimmingCharacters(in: .whitespaces))
                && cancels.contains { abs($0.box.midY - p.box.midY) < 0.02 && $0.box.midX < p.box.midX }
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// No piece on the window reads as `chat`'s name any more (a row still swiped open still shows it).
    static func gone(_ chat: String, _ rows: [[Piece]]) -> Bool {
        !rows.joined().contains { (0.1...0.92).contains($0.box.midY) && WatchChatOpen.sameChat(chat, listName: listName($0.text)) }
    }

    // MARK: Search (173, user 11-25: a chat not in view is found by the list's search box, "這不是兩邊都有嗎")

    /// The list's search box.
    static func searchBox(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { p in p.box.midY < 0.25 && ["搜索", "搜尋", "Search"].contains { p.text.contains($0) } }
            .map { CGPoint(x: 0.5, y: $0.box.midY) }
    }

    /// Searching: the 取消 by the search field at the top (no chat has it there).
    static func cancelButton(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { $0.box.midY < 0.13 && ["取消", "Cancel"].contains($0.text.trimmingCharacters(in: .whitespaces)) }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The result row named `chat` under the search field, topmost first.
    static func searchResult(_ chat: String, _ rows: [[Piece]]) -> CGPoint? {
        rows.map { row in row.filter { $0.box.minX < 0.75 } }
            .compactMap { row -> (text: String, box: CGRect)? in
                guard !row.isEmpty else { return nil }
                return (listName(row.map(\.text).joined()), row.reduce(CGRect.null) { $0.union($1.box) })
            }
            .filter { (0.12...0.9).contains($0.box.midY) && WatchChatOpen.sameChat(chat, listName: $0.text) }
            .min { $0.box.midY < $1.box.midY }
            .map { CGPoint(x: 0.5, y: $0.box.midY) }
    }
}

/// 181 (user 11-25: "兩個號在一個群里…就相當于是同一個人，就不用回復了"; "發了過后，他應該點開把那個紅點給點掉，而不是
/// 應該回復"): WeChat's and WeCom's own accounts are one person. What one of them says in a group both are in is opened on
/// the other side (its red mark goes) and never reported, so it is never answered. Who that is: the owner's names typed in
/// the watch settings, and any sender whose line is what 小藍 just sent there from the other app (learned, kept).
@MainActor enum XiaoLanSelf {
    struct Sent { var app: XiaoLanOrders.App; var chat: String; var text: String; var at: Double }

    static let learnedKey = "xiaolanSelvesV1"
    static let sentWindow = 600.0  // seconds a sent line is looked for on the other side

    /// The names learned so far (newest last, ten at most).
    static var learned: [String] { UserDefaults.standard.stringArray(forKey: learnedKey) ?? [] }

    static func learn(_ name: String) {
        let n = name.filter { !$0.isWhitespace }
        guard !n.isEmpty, !learned.contains(n) else { return }
        UserDefaults.standard.set(Array((learned + [n]).suffix(10)), forKey: learnedKey)
    }

    /// A line's words without spaces and punctuation (【】 and full-width signs too: the reader often gets those wrong),
    /// for matching what was sent with what is read. Letters include Chinese.
    static func plain(_ s: String) -> String {
        String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map { Character($0) })
    }

    /// The line read in `chat` on `app` is one 小藍 sent there from the other app within the window.
    static func sentByOther(_ text: String, chat: String, app: XiaoLanOrders.App, sent: [Sent], now: Double) -> Bool {
        let t = plain(text)
        guard t.count >= 2 else { return false }
        return sent.contains { s in
            guard s.app != app, now - s.at <= sentWindow,
                  WatchChatOpen.sameChat(chat, listName: s.chat) || WatchChatOpen.sameChat(s.chat, listName: chat) else { return false }
            let p = plain(s.text)
            return p == t || (min(p.count, t.count) >= 4 && (p.contains(t) || t.contains(p)))
        }
    }

    /// The sender is the owner: one of `names` (typed or learned), WeCom's "@微信" tag and spaces left out.
    static func isOwner(_ sender: String, names: [String]) -> Bool {
        let s = XiaoLanPanes.listName(sender)
        return !s.isEmpty && names.contains { n in XiaoLanPanes.listName(n) == s || person(n) == person(s) }
    }

    /// 182 (Echo 181, 11-26: "范兆磊＠某公司" in WeChat, learned as the owner, came back after a restart as a new
    /// sender): a WeCom account seen from WeChat carries "＠company"; the person is the name before it.
    static func person(_ name: String) -> String {
        let s = XiaoLanPanes.listName(name)
        guard let at = s.firstIndex(where: { $0 == "@" || $0 == "＠" }), at > s.startIndex else { return s }
        return String(s[..<at])
    }
}
