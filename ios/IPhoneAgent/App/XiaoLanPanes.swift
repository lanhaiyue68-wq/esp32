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
        // 188 night (Echo 188, 11-27 06:58: WeCom on Douyin's web page, a video's still against its left edge, which read
        // sharp on 62% of the rows, under 0.7: no gap, one window; "a window is gone after the back arrow; watch stopped",
        // WeCom left on the page, and every order after found no window): the gap last found, one of its edges still
        // sharp nearly all the way and the other on 40% of the rows, is the gap still (it moves only when dragged)
        if best == nil, let last = lastGap, last.w == w, last.h == h, last.a >= 1, last.b < w {
            let (ea, eb) = (edge(last.a), edge(last.b))
            if max(ea, eb) >= 0.9 && min(ea, eb) >= 0.4 { best = (last.a, last.b, ea + eb) }
        }
        guard let gap = best else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        lastGap = (w, h, gap.a, gap.b)
        // 181: a window moved in from the screen's side has an outer edge too; the wallpaper outside it is no part of
        // it (its taps are fractions of the window). Each window stays at least a fifth of the screen wide.
        let outerLeft = (1..<max(1, gap.a - w / 5)).first { edge($0) >= 0.7 } ?? 0
        let outerRight = stride(from: w - 1, to: min(w - 1, gap.b + w / 5), by: -1).first { edge($0) >= 0.7 } ?? w
        let (l0, l1) = (Double(outerLeft) / Double(w), Double(gap.a) / Double(w))
        let (r0, r1) = (Double(gap.b) / Double(w), Double(outerRight) / Double(w))
        return [CGRect(x: l0, y: 0, width: l1 - l0, height: windowBottom(px, luma, from: outerLeft, to: gap.a)),
                CGRect(x: r0, y: 0, width: r1 - r0, height: windowBottom(px, luma, from: gap.b, to: outerRight))]
    }

    /// 183: a window's bottom measured for sure (the wallpaper or the Dock right under its edge), by where the window is.
    private struct KeptBottom { var w: Int; var h: Int; var from: Int; var to: Int; var bottom: Double }
    private static var keptBottoms: [KeptBottom] = []
    /// 188 night: the gap between the windows last found (frame size, its two edge columns).
    private static var lastGap: (w: Int, h: Int, a: Int, b: Int)?

    /// Where a window ends above the Dock: a row from 0.75 down that changes sharply nearly all the way across, with the
    /// wallpaper or the Dock (coloured or dark, unlike any window) just under it.
    /// 183 (Echo 182 overnight, 11-26: a chat open with its keyboard down ended at 0.829, the bottom of a wide green
    /// bubble, so its input bar was cut off: "微信里没找到输入框" for every second line sent in a row, and the 按住 说话
    /// bar never switched back): an edge with more window under it is no bottom. With none seen (a keyboard over the
    /// bottom), the last bottom measured for sure at that place; never measured, the first sharp row (as before).
    private static func windowBottom(_ px: WatchOCR.Pixels, _ luma: (Int, Int) -> Int, from: Int, to: Int) -> Double {
        let w = px.w, h = px.h, span = to - from
        guard span > 20 else { return 1 }
        let xs = stride(from: from + span / 10, to: to - span / 10, by: max(1, span / 60)).map { $0 }
        let under = max(3, Int(0.008 * Double(h)))
        func notWindow(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            let r = Int(px.bytes[i]), g = Int(px.bytes[i + 1]), b = Int(px.bytes[i + 2])
            return max(r, g, b) - min(r, g, b) >= 40 || (r * 3 + g * 6 + b) / 10 < 170
        }
        func keep(_ bottom: Double) {
            keptBottoms.removeAll { $0.w == w && $0.h == h && abs($0.from - from) <= 6 && abs($0.to - to) <= 6 }
            keptBottoms = Array((keptBottoms + [KeptBottom(w: w, h: h, from: from, to: to, bottom: bottom)]).suffix(8))
        }
        // 188 night (B24 again, Echo 188, 11-27 04:56: Echo's own window open behind the two, its light panel right under
        // their bottoms, so no bottom "for sure" was found after the launch; the first sharp row, 0.788 (a time label over
        // my newest line), was taken: every WeChat send's line was cut off the window's picture, 4 looks in vain and the
        // list's preview, ~8 s a send): the window's side edge by the gap, sharp from the top down, stops at its rounded
        // corner whatever is under it (measured: 0.866–0.884, the corner ~0.03). From 0.86 down it is the bottom (a
        // keyboard's top is higher: 0.744 小藍's, its side edge stops at 0.766).
        var side: Double?
        let column = from > w / 3 ? from : to
        if column >= 1, column < w {
            var yy = Int(0.5 * Double(h)), miss = 0
            var last: Int?
            while yy < h {
                if abs(luma(column, yy) - luma(column - 1, yy)) >= 30 {
                    last = yy
                    miss = 0
                } else {
                    miss += 1
                    if miss >= 12 { break }
                }
                yy += 1
            }
            if let s = last.map({ min(1, Double($0) / Double(h) + 0.03) }), (0.86...0.97).contains(s) { side = s }
        }
        var y = Int(0.75 * Double(h)), first: Int?
        while y < h - under {
            let sharp = xs.filter { abs(luma($0, y) - luma($0, y - 1)) >= 30 }.count
            if Double(sharp) >= 0.7 * Double(xs.count) {
                if first == nil { first = y }
                // 188 night (Echo 188, 11-27 08:39–08:57: the server's wide green replies — coloured, as the Dock is —
                // under a sharp row at 0.76 made it the bottom, my newest line cut at the picture's edge, 4 sends
                // "not sent"): a row well above where the side edge goes on is inside the window
                let inside = side.map { $0 - Double(y) / Double(h) > 0.03 } ?? false
                if !inside, Double(xs.filter { notWindow($0, y + under) }.count) >= 0.7 * Double(xs.count) {
                    let bottom = Double(y) / Double(h)
                    keep(bottom)
                    return bottom
                }
            }
            y += 1
        }
        if let side {
            keep(side)
            return side
        }
        if let kept = keptBottoms.last(where: { $0.w == w && $0.h == h && abs($0.from - from) <= 6 && abs($0.to - to) <= 6 }) {
            return kept.bottom
        }
        return first.map { Double($0) / Double(h) } ?? 1
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
    /// 183 (Echo 182 overnight, 11-26, n=95: WeCom was in 企微测试群 and still sent back to its list): its group line
    /// ("外部群 | 群主: 范兆磊") is never the title, even when the name above it was not read.
    static func titleLine(_ rows: [[Piece]]) -> String {
        let lines = rows.map { $0.filter { (0.035...0.09).contains($0.box.midY) && (0.18...0.82).contains($0.box.midX) } }
            .filter { !$0.isEmpty }
            .filter { row in
                let t = row.map(\.text).joined().filter { !$0.isWhitespace }
                return !(t.contains("群主") || t.hasPrefix("外部群") || t.hasPrefix("内部群") || t.hasPrefix("內部群"))
            }
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

    /// 183: a window's app told by the window alone (its tab bar or list title, WeCom's quick bar, the chosen tab's colour).
    static func toldApp(_ rows: [[Piece]], crop: Data) -> XiaoLanOrders.App? {
        if let a = app(rows) { return a }
        if weworkBar(rows) { return .wework }
        guard view(rows) == .list, let px = WatchOCR.Pixels(crop) else { return nil }
        return tabApp(px)
    }

    /// 180: a chat's app by what only WeCom's chats show: the quick bar over the input (企业名片, 快捷回复, 发起收款).
    static func chatApp(_ rows: [[Piece]]) -> XiaoLanOrders.App { weworkBar(rows) ? .wework : .wechat }

    /// 182 (Echo 181, 11-26: WeCom left in 企微测试群, a title WeChat has too, was nobody's window: "no chat of WeChat or
    /// WeCom; left alone", its list and the owner's private message never looked at): WeCom's quick bar over the input
    /// tells its chats wherever they are.
    static func weworkBar(_ rows: [[Piece]]) -> Bool {
        rows.joined().contains { p in WatchOCR.quickBarWords.contains { p.text.contains($0) } }
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
    /// 183 (Echo 182 overnight, 11-26: the tap went on a time line, "11月26日 星期四 04:08", and the keyboard stayed up;
    /// its grey strokes fell between the 0.035 samples): every second pixel across, over a band 0.012 above and below.
    static func blankSpot(_ px: WatchOCR.Pixels, above bottom: Double) -> CGPoint? {
        let stepX = max(2.0 / Double(px.w), 0.002), stepY = max(2.0 / Double(px.h), 0.002)
        func bare(_ y: Double) -> Bool {
            stride(from: 0.15, through: 0.85, by: stepX).allSatisfy { x in
                let (r, g, b) = px.rgb(x, y)
                return (225...244).contains(r) && (225...244).contains(g) && (225...247).contains(b)
                    && max(r, g, b) - min(r, g, b) <= 8
            }
        }
        var y = bottom - 0.03
        while y > 0.15 {
            if stride(from: y - 0.012, through: y + 0.012, by: stepY).allSatisfy(bare) { return CGPoint(x: 0.5, y: y) }
            y -= 0.006
        }
        return nil
    }

    /// 183: the top of a window where a click goes only on a pointer seen there (its title bar: the back arrow, 取消,
    /// WeChat's ＋; the ••• and close above them).
    /// 184 (Echo 183, 11-26: the band to 0.12 took in the lists' search box, 0.10, and no search ever ran): the title bar
    /// only (0.08).
    static let topBand = 0.08

    /// 183 (Echo 182 overnight, 11-26: a second 取消 after a search, clicked unseen, hit WeChat's ＋ on the list behind
    /// it, and its menu stayed open for three minutes): the ＋ menu, by two of its rows.
    static let plusMenuWords = ["发起群聊", "發起群聊", "添加朋友", "加好友", "扫一扫", "掃一掃", "收付款", "加入企业", "添加客户"]
    static func plusMenu(_ rows: [[Piece]]) -> Bool {
        let texts = rows.joined().map { $0.text.filter { !$0.isWhitespace } }
        return Set(plusMenuWords.filter { w in texts.contains { $0.contains(w) } }).count >= 2
    }
    /// Where a click closes that menu and does nothing else: the title bar's bare left part (the list has no button there).
    static let menuCloseSpot = CGPoint(x: 0.25, y: 0.058)

    /// 183 (user 11-25: "所有紅點都要消失…行业资讯也要點掉"; logs 11-26: its mark stayed all night): the marked rows that
    /// are no one's chat (news, team, tools). Opened after any chat's, read into the notices, never reported.
    static func systemMarked(_ rows: [[Piece]], red: (CGRect) -> Double) -> [(name: String, at: CGPoint)] {
        entries(rows).filter { notChats.contains($0.name) && red(badgeArea($0.box)) >= WatchChatOpen.badgeShare }
            .sorted { $0.box.midY < $1.box.midY }
            .map { (name: $0.name, at: CGPoint(x: 0.5, y: $0.box.midY)) }
    }

    /// 183 (Echo 182, 11-26: 简体拼音 over the chat, its white keys taken for the input field, a key typed; its letters
    /// reported as 测试群's messages): the top of a system keyboard's keys in a window (window fractions), nil when none.
    static func keyboardTop(_ rows: [[Piece]]) -> Double? {
        let lowRows = rows.filter { ($0.map(\.box.minY).min() ?? 0) >= 0.45 }
        let low = lowRows.joined()
        // a key: one Latin letter, with the digit or sign printed over it on 简体拼音 ("1 q", "%z")
        let letters = low.filter { p in
            p.text.count <= 3 && p.text.filter { $0.isASCII && $0.isLetter }.count == 1
        }
        let words = low.filter { CandidatePicker.keyboardWords.contains($0.text.trimmingCharacters(in: .whitespaces)) }
        // 186 (B27, Echo 185, 11-26: 简体拼音 left on its 123 page by the owner — no letters on it — was not seen as a
        // keyboard): a row of six or more one-digit keys is one too (a chat's lines of one digit are on rows of their own).
        let digitRows = lowRows.filter { row in
            row.filter { p in p.text.count <= 3 && p.text.filter(\.isNumber).count == 1 && !p.text.contains(where: \.isLetter) }.count >= 6
        }
        guard letters.count >= 6 || !digitRows.isEmpty || CandidatePicker.keyboardUp(rows: lowRows) else { return nil }
        return (letters + words + Array(digitRows.joined())).map { Double($0.box.minY) }.min()
    }

    /// 186 (B25, Echo 185, 11-26: the bar's 发起收款 was clicked for the field): the bottom of WeCom's quick bar (企业名片
    /// / 发起收款 / 快捷回复 / 推荐客服) in a window, nil when none of it is read.
    static func quickBarBottom(_ rows: [[Piece]]) -> Double? {
        rows.joined().filter { p in WatchOCR.quickBarWords.contains { p.text.contains($0) } }.map { Double($0.box.maxY) }.max()
    }

    /// 186 (user 11-26: a WeCom group is WeCom's to answer): a chat title read with WeCom's logo after it, as an
    /// external group shows on WeChat's side ("企微测试群（7）Q").
    /// 188: a row of WeChat's list whose name has WeCom's logo after it (OCR 「企微测试群Q」, 11-27): a WeCom group.
    static func weComGroupRow(_ rows: [[Piece]], name: String) -> Bool {
        rows.joined().contains { p in
            let raw = WatchChatOpen.withoutTime(p.text.filter { !$0.isWhitespace })
            return WatchOCR.withoutIconTail(raw) != raw && listName(p.text) == name
        }
    }

    static func weComGroupTitle(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespaces)
        return WatchOCR.withoutIconTail(t) != t && WatchOCR.titled(t).group
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
    /// 183: `above`, a system keyboard's top: its white keys are no field (the field sits over the keyboard).
    /// 184 (Echo 183, 11-26: 简体拼音 up, its keys not read as a keyboard, a white key clicked for the field): the field's
    /// white sits under the input bar's light grey (~246); a key's under the keyboard's grey (~226): a white band with no
    /// light bar right over it is a key, and the field is looked for higher up.
    static func inputField(_ px: WatchOCR.Pixels, above: Double = 1) -> CGPoint? {
        let xs = [0.135, 0.50, 0.66]
        func white(_ y: Double) -> Bool {
            xs.filter { x in
                let (r, g, b) = px.rgb(x, y)
                return r >= 250 && g >= 250 && b >= 250
            }.count >= 2
        }
        // 187 (B23, Echo 186, 11-26: 「【第三方测试】185引用」, a white bubble on the chat's 237, passed for the field and was
        // clicked twice; measured that day: WeChat's input bar 245–246 and chat 237, WeCom's bar 246 and chat 237): the
        // light bar over the field is 242 or more, so a bubble on the chat's grey is no field.
        // 189 (N36, Echo 189, 11-27 12:58 首爾: WeChat's bar showed only ~7 px of its 246 over the field, so 0.008 up
        // (9 px of that window) was the chat's 237: the field was refused and the white bubble over it, 「帮我查一下啊…」,
        // taken and clicked; no keyboard came, four replies not sent): looked at 0.005 up, past a bubble's soft edge
        // (1–2 px) and inside the bar's thin top
        func barOver(_ y: Double) -> Bool {
            xs.filter { x in
                let (r, g, b) = px.rgb(x, max(0, y - 0.005))
                return (r * 3 + g * 6 + b) / 10 >= 242
            }.count >= 2
        }
        let step = 1 / Double(px.h)
        var y = min(1, above) - step, bottom: Double?
        while y > 0.3 {  // 180: with the keyboard up the field sits right over it, half way up the window
            if white(y) {
                if bottom == nil { bottom = y }
            } else if let b = bottom {
                if b - y >= 0.015 && barOver(y) { return CGPoint(x: 0.30, y: (b + y) / 2) }
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

    /// 184: a list's lines of text (titles and previews), each joined across its pieces.
    static func listBody(_ rows: [[Piece]]) -> [(text: String, box: CGRect)] {
        rows.compactMap { row -> (text: String, box: CGRect)? in
            let pieces = row.filter { (0.12...0.62).contains($0.box.minX) && (0.12...0.92).contains($0.box.midY) }
            guard !pieces.isEmpty else { return nil }
            return (pieces.map(\.text).joined(), pieces.reduce(CGRect.null) { $0.union($1.box) })
        }
    }

    /// 184 (C12; Echo 183, 11-26: 「主人蓝海乐: 【第三方测试】群消息1」 on WeChat's list, but in the group iPad WeChat
    /// showed no name over the bubble, the sender read as the group's name and the line was dropped): who wrote the
    /// line the row titled `name` previews, nil when it names no one.
    static func previewSender(_ rows: [[Piece]], of name: String) -> String? {
        let body = listBody(rows)
        guard let title = body.first(where: { listName($0.text) == name }),
              let preview = body.filter({ abs($0.box.minX - title.box.minX) <= 0.04 && (0.015...0.045).contains($0.box.midY - title.box.midY) })
                .min(by: { $0.box.midY < $1.box.midY }) else { return nil }
        return senderOf(preview.text)
    }

    /// 186 (B24): the preview under the row of `chat` as read, nil when the row is not in view.
    static func previewText(_ rows: [[Piece]], of chat: String) -> String? {
        let body = listBody(rows)
        guard let title = body.first(where: { WatchChatOpen.sameChat(chat, listName: listName($0.text)) }),
              let preview = body.filter({ abs($0.box.minX - title.box.minX) <= 0.04 && (0.015...0.045).contains($0.box.midY - title.box.midY) })
                .min(by: { $0.box.midY < $1.box.midY }) else { return nil }
        return preview.text
    }

    /// The writer a list preview names: "主人蓝海乐: …" / "主人蓝海乐：…", after any "[2条]" or "[有人@我]"; nil for a
    /// preview with none ("[语音] 2\"", "【模拟服务器】收到：嗨", the owner's own line).
    static func senderOf(_ preview: String) -> String? {
        var t = Substring(preview.trimmingCharacters(in: .whitespaces))
        while t.hasPrefix("["), let close = t.firstIndex(of: "]"), t.distance(from: t.startIndex, to: close) <= 10 {
            t = t[t.index(after: close)...].drop { $0 == " " }
        }
        guard let colon = t.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return nil }
        let who = t[..<colon].trimmingCharacters(in: .whitespaces)
        guard (1...20).contains(who.count), !who.allSatisfy(\.isNumber), !who.contains(where: { "[]【】「」《》\"“”".contains($0) }) else { return nil }
        let name = listName(who)
        return name.isEmpty ? nil : name
    }

    /// The list rows: a title with a smaller preview line just under it.
    static func entries(_ rows: [[Piece]]) -> [(name: String, box: CGRect)] {
        let body = listBody(rows)
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
    /// 183 (Echo 182 overnight, 11-26: after a back click the pointer was found at 0.008 of the screen, by its left
    /// edge): the click a little further in, still on the arrow.
    static let back = CGPoint(x: 0.062, y: 0.058)
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
    /// 187 (B36): a name cut short by the row slid open (「文件传输助」 for 文件传输助手), three characters or more of its
    /// beginning, still counts as the chat.
    static func gone(_ chat: String, _ rows: [[Piece]]) -> Bool {
        let full = chat.filter { !$0.isWhitespace }
        return !rows.joined().contains { p in
            guard (0.1...0.92).contains(p.box.midY) else { return false }
            let n = listName(p.text)
            return WatchChatOpen.sameChat(chat, listName: n) || (n.count >= 3 && n.count < full.count && full.hasPrefix(n))
        }
    }

    // MARK: Search (173, user 11-25: a chat not in view is found by the list's search box, "這不是兩邊都有嗎")

    /// The list's search box.
    static func searchBox(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { p in p.box.midY < 0.25 && ["搜索", "搜尋", "Search"].contains { p.text.contains($0) } }
            .map { CGPoint(x: 0.5, y: $0.box.midY) }
    }

    /// 187 (user 11-27, with a picture of it on the phone: "點那個叉…或者點叉上面那一塊空白，都可以把這個聊天框給它關掉。如果
    /// 是全框的話…你就點返回"; Echo 186, 11-27 00:32 首爾): a WeChat banner clicked opens its chat as a sheet over the chat
    /// that was open, from about a quarter of the window down. The window's own title stays the chat under it (dimmed), so
    /// the sheet's lines were reported as that chat's and three replies typed into the sheet went to the other group.
    /// Measured on the iPad (11-27 00:42): the chat above the sheet dimmed to ~118 from edge to edge, the sheet's header
    /// ~232, its top at 0.253 of the window, its ✕ at (0.077, 0.285); a chat, a chat under a keyboard, a list and a search
    /// (nine frames) have no such edge. Where its ✕ is, nil when there is no sheet.
    static func sheetClose(_ px: WatchOCR.Pixels) -> CGPoint? {
        func lum(_ x: Double, _ y: Double) -> Double { let c = px.rgb(x, y); return Double(c.0 + c.1 + c.2) / 3 }
        func dim(_ y: Double) -> Bool { [0.02, 0.5, 0.98].allSatisfy { lum($0, y) < 170 } }
        func light(_ y: Double) -> Bool { [0.05, 0.95].allSatisfy { lum($0, y) > 200 } }
        var y = 0.15
        while y < 0.85 {
            if dim(y), light(y + 0.03) {
                var top = y
                while top < y + 0.03, lum(0.5, top) < 170 { top += 0.002 }
                return CGPoint(x: 0.077, y: top + 0.032)
            }
            y += 0.005
        }
        return nil
    }

    /// Searching: the 取消 by the search field at the top (no chat has it there).
    static func cancelButton(_ rows: [[Piece]]) -> CGPoint? {
        let top = rows.joined().filter { $0.box.midY < 0.13 }
        if let p = top.first(where: { ["取消", "Cancel"].contains($0.text.trimmingCharacters(in: .whitespaces)) }) {
            return CGPoint(x: p.box.midX, y: p.box.midY)
        }
        // 188 (B37 again, Echo 187, 11-27: WeCom's search for a group not there read its 取消 as 「•取消」, the field's ⊗
        // joined to it: not found, so the search was left open and, its window not told as WeCom's, wxwork:// was
        // opened every 11 s): 取消 ending a short piece counts, and the click goes to the 取消 part, not the ⊗.
        for p in top {
            let t = p.text.trimmingCharacters(in: .whitespaces)
            let word = t.hasSuffix("取消") && t.count <= 4 ? 2 : t.hasSuffix("Cancel") && t.count <= 8 ? 6 : 0
            if word > 0 {
                return CGPoint(x: p.box.maxX - p.box.width * Double(word) / Double(t.count) / 2, y: p.box.midY)
            }
        }
        return nil
    }

    /// The result row named `chat` under the search field, topmost first.
    static func searchResult(_ chat: String, _ rows: [[Piece]]) -> CGPoint? {
        // 187 (Echo 186, 11-27 00:10 首爾: WeCom searched 不存在的群187, found nothing, and took 小藍's own bar under it,
        // "小藍 已填入：不存在的群187", for the row; clicked it twice and left the search open): nothing at or under a
        // keyboard (小藍's bar, or a system one) is a result.
        let bar = rows.joined().filter { p in ["已填入", "输入法", "輸入法"].contains { p.text.contains($0) } }
            .map { Double($0.box.minY) }.min()
        let floor = min(bar ?? 0.9, keyboardTop(rows) ?? 0.9, 0.9)
        return rows.map { row in row.filter { $0.box.minX < 0.75 } }
            .compactMap { row -> (text: String, box: CGRect)? in
                guard !row.isEmpty else { return nil }
                return (listName(row.map(\.text).joined()), row.reduce(CGRect.null) { $0.union($1.box) })
            }
            .filter { Double($0.box.midY) >= 0.12 && Double($0.box.maxY) < floor && WatchChatOpen.sameChat(chat, listName: $0.text) }
            .min { $0.box.midY < $1.box.midY }
            .map { CGPoint(x: 0.5, y: $0.box.midY) }
    }
}

/// 183 (Echo 182, 11-26: after the reinstall the first look at WeCom's 企微测试群 reported an old line, "监海乐: 你好";
/// what had been read lived in memory only): what was read last in each chat ("wechat|测试群"), kept across launches.
@MainActor enum PaneHistory {
    static let key = "xiaolanPaneHistoryV1"

    static func load() -> [String: [WatchReport.Line]] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: [WatchReport.Line]].self, from: data)) ?? [:]
    }

    static func save(_ history: [String: [WatchReport.Line]]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: key)
    }

    /// The new lines of a chat whose history came from an earlier launch. With no overlap (more than a screenful
    /// since, or the lines read differently) nothing is new, but the last line of someone's when a red mark opened it.
    static func newAfterLaunch(_ lines: [WatchReport.Line], history: [WatchReport.Line], fromMark: Bool) -> [WatchReport.Line] {
        let fresh = WatchReport.new(lines, history: history)
        guard !lines.isEmpty, fresh.count == lines.count else { return fresh }
        return fromMark ? Array(lines.filter { !$0.mine }.suffix(1)) : []
    }
}

/// 181 (user 11-25: "兩個號在一個群里…就相當于是同一個人，就不用回復了"; "發了過后，他應該點開把那個紅點給點掉，而不是
/// 應該回復"): WeChat's and WeCom's own accounts are one person. What one of them says in a group both are in is opened on
/// the other side (its red mark goes) and never reported, so it is never answered. Who that is: the owner's names typed in
/// the watch settings, and any sender whose line is what 小藍 just sent there from the other app (learned, kept).
@MainActor enum XiaoLanSelf {
    struct Sent { var app: XiaoLanOrders.App; var chat: String; var text: String; var at: Double }

    // 189 (N22): V2: names learned before 189 dropped (主人蓝海乐, a tester, was learned from a reply quoting their words)
    static let learnedKey = "xiaolanSelvesV2"
    // 183 (11-26: a line sent 33 min before came back on a scrolled-up screen and was reported): 4 hours, was 10 min.
    static let sentWindow = 4 * 3600.0  // seconds a sent line is looked for on the other side

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

    /// 184 (Echo 183, 11-26: after a send the keyboard went down, older lines came in above, and the screen no longer
    /// started where the history ended): what follows the history's last line wherever it is on the screen, the line
    /// before it agreeing too when the history has one; nil when it is not there (or too short to tell: 好, 嗯).
    static func afterAnchor(_ lines: [WatchReport.Line], history: [WatchReport.Line]) -> [WatchReport.Line]? {
        guard let last = history.last else { return nil }
        func key(_ l: WatchReport.Line) -> String { plain(l.text) + (l.mine ? "|me" : "") }
        let lastKey = key(last)
        guard plain(last.text).count >= 3 else { return nil }
        for i in stride(from: lines.count - 1, through: 0, by: -1) where key(lines[i]) == lastKey {
            if history.count >= 2, i >= 1, key(lines[i - 1]) != key(history[history.count - 2]) { continue }
            return Array(lines[(i + 1)...])
        }
        return nil
    }

    /// The line read in `chat` on `app` is one 小藍 sent there from the other app within the window.
    /// `whole` (189, N22): only the owner's whole words, six characters or more, count (to learn an account by).
    static func sentByOther(_ text: String, chat: String, app: XiaoLanOrders.App, sent: [Sent], now: Double, whole: Bool = false) -> Bool {
        let t = plain(text)
        guard t.count >= (whole ? 6 : 2) else { return false }
        return sent.contains { s in
            guard s.app != app, now - s.at <= sentWindow,
                  WatchChatOpen.sameChat(chat, listName: s.chat) || WatchChatOpen.sameChat(s.chat, listName: chat) else { return false }
            let p = plain(s.text)
            if whole { return p == t }
            return p == t || (min(p.count, t.count) >= 4 && (p.contains(t) || t.contains(p)))
        }
    }

    /// The sender is the owner: one of `names` (typed or learned), WeCom's "@微信" tag and spaces left out.
    static func isOwner(_ sender: String, names: [String]) -> Bool {
        let s = XiaoLanPanes.listName(sender)
        return !s.isEmpty && names.contains { n in XiaoLanPanes.listName(n) == s || person(n) == person(s) || readAlike(person(n), person(s)) }
    }

    /// 183 (Echo 182 overnight, 11-26: the owner's other account 蓝海乐 read as "监海乐", its line reported): letters the
    /// reader has been seen to swap for one another. A name is the owner's when it differs from the owner's in one such
    /// letter only; any other letter is another person (范光磊 is not 范兆磊).
    static let alikeLetters: [Set<Character>] = [["蓝", "监", "篮"], ["藍", "監", "籃"]]
    static func readAlike(_ owner: String, _ read: String) -> Bool {
        let a = Array(owner), b = Array(read)
        guard a.count == b.count, a.count >= 2 else { return false }
        let differ = zip(a, b).filter { pair in pair.0 != pair.1 }
        guard differ.count == 1, let pair = differ.first else { return false }
        return alikeLetters.contains { $0.contains(pair.0) && $0.contains(pair.1) }
    }

    /// 183 (Echo 182 overnight, 11-26: "企业名片", "国企业名片", "企微测试群" as the senders of 24 lines reported): a
    /// sender read as the chat's own name or as a button of WeCom's quick bar is no sender read.
    static func noSender(_ sender: String, chat: String) -> Bool {
        let s = XiaoLanPanes.listName(sender)
        guard !s.isEmpty else { return false }
        if WatchChatOpen.sameChat(s, listName: chat) || WatchChatOpen.sameChat(chat, listName: s) { return true }
        return isButton(s)
    }

    /// 185 (B18): every line's words read in this chat, and in the app's other chats (a window's title taken for the
    /// other's put one chat's lines under another's name).
    static func seenInApp(_ seen: [String: Set<String>], app: String, chat key: String) -> Set<String> {
        var all = seen[key] ?? []
        for (k, v) in seen where k != key && k.hasPrefix(app + "|") { all.formUnion(v) }
        return all
    }

    /// 187 (B38, Echo 186, 11-27 00:19 首爾: WeCom's 企微测试群, no overlap with its history, reported 「【第三万测试】185
    /// 企微群分工」 (方 read as 万) and 「二行当成别人的新消息」 (the end of an older line, its start above the window) as
    /// new): a line of six or more characters was read before when it is part of a line read before, or a line read
    /// before with one character in ten read differently. Digits are never "read differently": 0018 is not 0019.
    /// 189 (N21, Echo 189, 11-27 12:55 首爾; user: 「企微多了一個遠好嗎，這是之前的了」): 企微测试群 opened again for a new
    /// line, nothing on its screen going on from the history; 「還好嗎」, answered at 11:37, misread 「遠好嗎」 this time
    /// (three characters: no misread is forgiven so short) counted as new and was answered again. New lines come at the
    /// bottom: of a screen that does not go on from the history only what follows the last line read before, or mine,
    /// can be new (and not read before itself).
    static func unseen(_ lines: [WatchReport.Line], known: Set<String>) -> [WatchReport.Line] {
        let last = lines.lastIndex { $0.mine || readBefore($0.text, known: known) }
        let after = last.map { Array(lines[($0 + 1)...]) } ?? lines
        return after.filter { !readBefore($0.text, known: known) }
    }

    static func readBefore(_ text: String, known: Set<String>) -> Bool {
        let t = plain(text)
        if known.contains(t) { return true }
        guard t.count >= 6 else { return false }
        let x = Array(t)
        return known.contains { k in
            if k.count > t.count { return k.contains(t) }
            let y = Array(k)
            guard y.count == x.count else { return false }
            let differ = zip(x, y).filter { $0 != $1 }
            return differ.count <= max(1, x.count / 10) && !differ.contains { $0.isNumber || $1.isNumber }
        }
    }

    /// 185 (B8): what my newest line must show for a send to count: the text's last 6 characters (no spaces); the
    /// beginning matched older lines (「【小蓝测试】」, a customer's 「您好，」).
    /// 187 (B40, Echo 186, 11-27: 「…（全形）~ 0024」 read back as 「…（全形）～0024」, the preview's emoji as 「③金」: a send
    /// that went out reported failed): letters and digits only (`plain`), so signs, full-width forms and emoji read any
    /// way still match; a text of fewer than four of them keeps its last six characters as they are.
    static func sendSignature(_ text: String) -> String {
        let p = plain(text)
        return p.count >= 4 ? String(p.suffix(6)) : String(text.filter { !$0.isWhitespace }.suffix(6))
    }
    /// 187 (B40): `read` (a line, a preview) shows the signature of `text`, compared the way the signature was taken.
    /// 188 (B40 again, Echo 187, 11-27: 「【小蓝测试】187 符号~😀 0021」 went out, its preview read 「187符号~G」「0021」 — the
    /// emoji as a letter, as 186 read one as 「③金」 — and the send was reported failed): the signature's runs of letters
    /// and digits may also be found in order with up to two characters between them (an emoji or a sign read as one
    /// or two), never more, so 「…0018」 is still not 「…0018 连发2」.
    static func shows(_ read: String, signature: String, of text: String) -> Bool {
        guard plain(text).count >= 4 else { return read.filter { !$0.isWhitespace }.contains(signature) }
        return plain(read).contains(signature) || showsInOrder(read, tailRuns(text))
    }
    /// 188: the text's last six letters and digits (as `plain` keeps them), split where the text had anything else.
    static func tailRuns(_ text: String) -> [String] {
        var runs: [String] = [], cur = ""
        for s in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(s) { cur.unicodeScalars.append(s) } else if !cur.isEmpty { runs.append(cur); cur = "" }
        }
        if !cur.isEmpty { runs.append(cur) }
        var out: [String] = [], n = 0
        for r in runs.reversed() where n < 6 {
            let take = min(r.count, 6 - n)
            out.insert(String(r.suffix(take)), at: 0)
            n += take
        }
        return out
    }
    /// 188: `pieces` found in `read` (letters and digits only) one after another, each within `gap` characters of the last.
    static func showsInOrder(_ read: String, _ pieces: [String], gap: Int = 2) -> Bool {
        let r = Array(plain(read)), ps = pieces.map { Array($0) }.filter { !$0.isEmpty }
        guard let first = ps.first, r.count >= first.count else { return false }
        func at(_ i: Int, _ p: [Character]) -> Bool { i + p.count <= r.count && Array(r[i..<(i + p.count)]) == p }
        for start in 0...(r.count - first.count) where at(start, first) {
            var end = start + first.count, found = true
            for p in ps.dropFirst() {
                guard end <= r.count, let s = (end...min(end + gap, r.count)).first(where: { at($0, p) }) else { found = false; break }
                end = s + p.count
            }
            if found { return true }
        }
        return false
    }

    /// 186 (B24): a list preview shows the line just sent: its end, or (cut short with "…") its beginning, at least six
    /// characters of it, after a "sender:" as a group's or WeCom's preview may put first.
    static func previewShowsSent(_ preview: String, _ text: String) -> Bool {
        let body = WatchReport.previewBody(preview), t = text.filter { !$0.isWhitespace }
        guard !body.isEmpty, !t.isEmpty else { return false }
        var heads = [body]
        if let colon = body.firstIndex(where: { $0 == ":" || $0 == "：" }), body.distance(from: body.startIndex, to: colon) <= 20 {
            heads.append(String(body[body.index(after: colon)...]))
        }
        let tail = sendSignature(text)
        // 187 (B32, Echo 186, 11-26: 「…0018」 before 「…0018 连发2」 was taken as the text shown already, and a send that went
        // out was reported failed): the beginning counts only for a preview cut short with "…".
        let trimmed = preview.trimmingCharacters(in: .whitespaces)
        let cut = trimmed.hasSuffix("…") || trimmed.hasSuffix("...")
        let pt = plain(text)  // 187 (B40): letters and digits on both sides
        return heads.contains { h in
            shows(h, signature: tail, of: text) || (cut && plain(h).count >= min(6, pt.count) && pt.hasPrefix(plain(h)))
        }
    }

    /// 184 (C12): a "sender" that is one of WeCom's quick bar buttons (a line of the bar, not of a person).
    static func isButton(_ sender: String) -> Bool {
        let s = XiaoLanPanes.listName(sender)
        return WatchOCR.quickBarWords.contains { s.contains($0) }
    }

    /// 182 (Echo 181, 11-26: "范兆磊＠某公司" in WeChat, learned as the owner, came back after a restart as a new
    /// sender): a WeCom account seen from WeChat carries "＠company"; the person is the name before it.
    static func person(_ name: String) -> String {
        let s = XiaoLanPanes.listName(name)
        guard let at = s.firstIndex(where: { $0 == "@" || $0 == "＠" }), at > s.startIndex else { return s }
        return String(s[..<at])
    }
}

/// 184 (C15b; user 11-26: the screen left on Settings or on Echo full screen, "不要叫他手動切"): the way back to WeChat
/// and WeCom side by side without pushing an edge (the board's Cmd+H, Cmd+Tab, Esc and a Home key do nothing on this
/// iPad): 辅助触控's floating button (its 轻点一下 set to 主屏幕) shows the home screen and the Dock; WeCom's icon there
/// brings its window back on the right, then WeChat's on the left. Done by hand on the customer's iPad 11-26, 14:50.
@MainActor enum XiaoLanRecall {
    /// 185 (Echo 184, 11-26: the owner had moved the button from over the Dock's Echo icon to the bottom-right corner;
    /// 184's fixed spot, (0.655, 0.956), would have clicked whatever was there): 辅助触控's button found on the screen,
    /// nil when it is not seen (then nothing is clicked). A rounded square ~88 px across at 960 wide, of one grey (its
    /// translucent fill over a plain page), a lighter grey disk in its middle (~20 levels lighter), its sides 36–58 px
    /// from that middle and alike, by an edge of the screen (iOS keeps it there). Looked for where 小藍 needs it: over an
    /// app's page with the Dock hidden. A Python copy found it within 6 px on three frames (Echo; Settings, the pointer
    /// on the button) and nothing in 150 other frames; over the Dock's icons or a coloured square it is not found (the
    /// Dock is clicked straight away there).
    static func assistiveTouchButton(_ px: WatchOCR.Pixels) -> CGPoint? {
        let w = Double(px.w), h = Double(px.h), k = w / 960
        func look(_ x: Double, _ y: Double) -> (l: Double, c: Int)? {
            guard x >= 0, x < w, y >= 0, y < h else { return nil }
            let (r, g, b) = px.rgb(x / w, y / h)
            return (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b), max(r, g, b) - min(r, g, b))
        }
        let band = 0.08, step = max(2.0, 4 * k)
        var disk: [(dx: Double, dy: Double)] = []
        for dx in stride(from: -10.0, through: 10, by: 5) {
            for dy in stride(from: -10.0, through: 10, by: 5) where dx * dx + dy * dy <= 100 { disk.append((dx * k, dy * k)) }
        }
        let ring = (0..<16).map { a -> (Double, Double) in
            let t = Double(a) / 16 * 2 * .pi
            return (33 * k * cos(t), 33 * k * sin(t))
        }
        var best: (s: Double, p: CGPoint)?
        for cy in stride(from: 0.03 * h, to: h, by: step) {
            for cx in stride(from: 0.0, to: w, by: step)
            where cx < band * w || cx > (1 - band) * w || cy > (1 - band) * h || cy < band * h {
                let ds = disk.compactMap { look(cx + $0.dx, cy + $0.dy) }
                guard ds.count == disk.count, let dMax = ds.map({ $0.l }).max(), let dMin = ds.map({ $0.l }).min(),
                      ds.allSatisfy({ $0.c <= 30 }), dMax - dMin <= 24 else { continue }
                let bs = ring.compactMap { look(cx + $0.0, cy + $0.1) }
                guard bs.count == ring.count, let bMax = bs.map({ $0.l }).max(), let bMin = bs.map({ $0.l }).min(),
                      bs.allSatisfy({ $0.c <= 30 }), bMax - bMin <= 22 else { continue }
                let ld = ds.map({ $0.l }).reduce(0, +) / Double(ds.count), lb = bs.map({ $0.l }).reduce(0, +) / Double(bs.count)
                guard ld - lb >= 20 else { continue }
                var dist: [Int] = [], edges = 0
                for (ux, uy) in [(1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)] {
                    var found: (edge: Bool, r: Int)?
                    for r in 36..<58 {
                        guard let v = look(cx + ux * Double(r) * k, cy + uy * Double(r) * k) else { found = (false, r); break }
                        if abs(v.l - lb) > 25 { found = (true, r); break }
                    }
                    guard let f = found else { break }
                    dist.append(f.r)
                    if f.edge { edges += 1 }
                }
                guard dist.count == 4, edges >= 2, let hi = dist.max(), let lo = dist.min(), hi - lo <= 14 else { continue }
                if best == nil || ld - lb > best!.s { best = (ld - lb, CGPoint(x: cx / w, y: cy / h)) }
            }
        }
        return best?.p
    }

    /// An icon's look around a spot (a box ~56 px at 960 wide): the share of it near white, the share strongly
    /// coloured, and the middle hue of the coloured part.
    static func iconLook(_ px: WatchOCR.Pixels, _ cx: Double, _ cy: Double) -> (white: Double, coloured: Double, hue: Double?) {
        var n = 0, white = 0
        var hues: [Double] = []
        let fx = 1 / 960.0, fy = Double(px.w) / 960 / Double(px.h)
        for dy in stride(from: -28, through: 28, by: 4) {
            for dx in stride(from: -28, through: 28, by: 4) {
                let (r, g, b) = px.rgb(cx + Double(dx) * fx, cy + Double(dy) * fy)
                let mx = max(r, g, b), mn = min(r, g, b)
                n += 1
                if mx > 216 && Double(mx - mn) < 0.12 * Double(mx) { white += 1 }
                if mx > 153 && Double(mx - mn) > 0.6 * Double(mx) { hues.append(Vision.hue(r, g, b)) }
            }
        }
        hues.sort()
        return (Double(white) / Double(n), Double(hues.count) / Double(n), hues.isEmpty ? nil : hues[hues.count / 2])
    }

    /// The Dock's WeChat and WeCom icons (screen fractions), when the Dock shows. Measured 11-26 on the customer's iPad
    /// (960 x 1280, icons ~70 px, their middles at y 0.95): WeChat's green over half the icon, hue 148–149 (Messages'
    /// green is 130); WeCom's icon white for three quarters, its blue (hue ~206) in it (Safari and Mail are blue over
    /// half, Photos many hues). Of the spots that look so along a row, the middle of the longest run (at least 0.02).
    /// A Python copy found them at 0.353 and 0.445 on three frames (by hand: 0.351, 0.443), nothing on an iPhone's.
    static func dockIcons(_ px: WatchOCR.Pixels) -> (wechat: CGPoint?, wework: CGPoint?) {
        var best: [Int: (count: Int, x: Double, y: Double)] = [:]
        for y in [0.93, 0.94, 0.95, 0.96] {
            var runs: [Int: [Double]] = [0: [], 1: []]
            for x in stride(from: 0.03, through: 0.97, by: 0.005) {
                let l = iconLook(px, x, y)
                guard let hue = l.hue else { continue }
                if l.coloured >= 0.45 && (140...158).contains(hue) { runs[0]!.append(x) }
                if l.white >= 0.6 && l.coloured >= 0.08 && (195...220).contains(hue) { runs[1]!.append(x) }
            }
            for (app, xs) in runs where !xs.isEmpty {
                var groups: [[Double]] = [[xs[0]]]
                for v in xs.dropFirst() {
                    if v - groups[groups.count - 1].last! <= 0.011 { groups[groups.count - 1].append(v) } else { groups.append([v]) }
                }
                guard let g = groups.max(by: { $0.count < $1.count }), g.count >= 4 else { continue }
                if best[app] == nil || g.count > best[app]!.count { best[app] = (g.count, g.reduce(0, +) / Double(g.count), y) }
            }
        }
        return (best[0].map { CGPoint(x: $0.x, y: $0.y) }, best[1].map { CGPoint(x: $0.x, y: $0.y) })
    }
}
