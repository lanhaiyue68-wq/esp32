import UIKit

/// 小藍 (164): a WeChat chat read like 智微兔 reads it, without a model (docs/xiaolan-engine-logic.md). 智微兔 reads the
/// text of WeChat's controls; iOS lets no app read another app's, so here the text comes from the system's own
/// recognizer (CandidatePicker.rows: Apple Vision, on the device, free and offline) and who wrote a line from the
/// colour just left of it. Measured on the customer's iPad 9, light mode, 11-25: the chat background (237, 237, 237),
/// their bubble white (254), my bubble green (~150, 235, 106). Grey left beside the avatars = a sender's name (groups);
/// grey elsewhere = a time or a system line (left out). Lines of one bubble that follow each other are one message.
enum WatchOCR {
    enum Kind: Equatable { case mine, theirs, grey, other }

    /// The frame's pixels, RGBA, top row first.
    struct Pixels {
        let w: Int, h: Int
        let bytes: [UInt8]

        init?(_ jpeg: Data) {
            guard let image = UIImage(data: jpeg)?.cgImage else { return nil }
            let w = image.width, h = image.height
            guard w > 10, h > 10 else { return nil }
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
                guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn else { return nil }
            self.w = w
            self.h = h
            self.bytes = bytes
        }

        func rgb(_ x: Double, _ y: Double) -> (Int, Int, Int) {
            let px = min(max(Int(x * Double(w)), 0), w - 1), py = min(max(Int(y * Double(h)), 0), h - 1)
            let i = (py * w + px) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }

        /// The top of the input bar or the keyboard: the first row below `from` that is white nearly edge to edge (the
        /// chat's own rows are grey at the sides).
        func inputTop(from: Double) -> Double? {
            let step = max(1, h / 400), across = max(1, w / 60)
            var y = Int(from * Double(h))
            while y < h {
                var white = 0, n = 0
                for x in stride(from: 0, to: w, by: across) {
                    n += 1
                    let i = (y * w + x) * 4
                    if bytes[i] >= 243 && bytes[i + 1] >= 243 && bytes[i + 2] >= 243 { white += 1 }  // the bar is 246, the chat 237
                }
                if white * 10 >= n * 9 { return Double(y) / Double(h) }
                y += step
            }
            return nil
        }
    }

    static func kind(of c: (Int, Int, Int)) -> Kind {
        let (r, g, b) = c
        if g > r + 40 && g > b + 60 { return .mine }
        // 172: WeCom's own bubble is light blue; its chat background (236, 237, 241) is only a little blue.
        if b >= 230 && b - r >= 20 && g >= 200 && r >= 150 { return .mine }
        if r >= 247 && g >= 247 && b >= 247 { return .theirs }
        if abs(r - g) < 10 && abs(g - b) < 10 && (222...246).contains(r) { return .grey }
        return .other
    }

    /// What a line of text sits on: a few points left of its first letter, past the anti-aliasing, still inside a
    /// bubble's padding.
    static func kind(_ box: CGRect, _ px: Pixels) -> Kind {
        for dx in [0.006, 0.010, 0.004] {
            let k = kind(of: px.rgb(Double(box.minX) - dx, Double(box.midY)))
            if k != .other { return k }
        }
        return .other
    }

    /// "测试群(6)" → ("测试群", group); a private chat has no head count.
    static func titled(_ title: String) -> (name: String, group: Bool) {
        let t = withoutIconTail(title.trimmingCharacters(in: .whitespaces))
        guard let open = t.lastIndex(where: { $0 == "(" || $0 == "（" }), t.hasSuffix(")") || t.hasSuffix("）") else { return (t, false) }
        let inside = t[t.index(after: open)..<t.index(before: t.endIndex)]
        guard !inside.isEmpty, inside.allSatisfy(\.isNumber) else { return (t, false) }
        return (String(t[..<open]).trimmingCharacters(in: .whitespaces), true)
    }

    /// 180 (Echo 178 on the iPad, 11-25: "企微测试群（7）Q", list "企微测试群Q"): the WeCom logo after an external group's
    /// name is read as a "Q"; one Q right after a CJK character or a bracket is that icon, not the name.
    /// 181 (Echo 180 on the iPad, 11-25: "企微测试群（7）0", the chat not taken for 企微测试群 and its new line kept as
    /// history): right after the head count the logo is read as a 0 or an O too. The（7）is the head count, no name.
    /// 182 (Echo 181, 11-26: "企微测试群（7）9", the chat not taken for 企微测试群: the reply order failed, and its old
    /// lines were reported as new under a chat of that name): after the head count nothing of the name follows, so any
    /// one character there is the logo, whatever it is read as.
    static func withoutIconTail(_ s: String) -> String {
        guard let last = s.last, s.count >= 2 else { return s }
        let before = s[s.index(before: s.index(before: s.endIndex))]
        let afterCount = before == ")" || before == "）"
        let logo = "QqＱ".contains(last) && before.unicodeScalars.contains(where: { $0.value >= 0x2E80 })
            || afterCount && last != ")" && last != "）" && !last.isWhitespace
        return logo ? String(s.dropLast()).trimmingCharacters(in: .whitespaces) : s
    }

    /// 182 (Echo 181, 11-26): words of the apps' own controls read as messages and reported: 文件传输助手's
    /// "按住说话" (the voice bar, while recording), WeCom's "哦。•转换完成" (a voice note's transcript and its label).
    /// A line that is only such words is dropped; the label after a transcript is cut off.
    static let uiPhrases = ["按住说话", "按住說話", "松开发送", "鬆開發送", "松开取消", "鬆開取消", "滑到这里转文字",
                            "滑到這裡轉文字", "上滑取消"]
    static let uiTails = ["转换完成", "轉換完成", "转文字完成", "轉文字完成"]
    /// WeCom's quick bar over a chat's input (180, 182: it tells WeCom's chats).
    /// 184 (C14; Echo 183, 11-26: "企业名片 ¥发起收款 客户转账" reported from a private chat): a private chat's bar
    /// has 服务总结 and 客户转账 too.
    static let quickBarWords = ["企业名片", "企業名片", "快捷回复", "快捷回覆", "发起收款", "發起收款", "推荐客服", "推薦客服",
                                "服务总结", "服務總結", "客户转账", "客戶轉賬", "客户转帐", "客戶轉帳"]

    /// 183 (Echo 182 overnight, 11-26: "¥发起收款 •推荐客服", "发起收款 ●推荐客服" reported 24 times): a line that is
    /// WeCom's quick bar (its buttons read with their icons as ¥ • ●, a stray character at most) is dropped too.
    static func withoutUIWords(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = t.filter { !$0.isWhitespace }
        if uiPhrases.contains(bare) { return "" }
        // 185 (B19, Echo 184, 11-26: WeChat's voice notes 2" and 6" were reported as 「小）2"」「小）6"」): a line that is
        // a voice note's length (its speaker read as a stray character or two) is no text.
        if bare.range(of: #"^[^0-9]{0,2}[0-9]{1,2}["”″＂']$"#, options: .regularExpression) != nil { return "" }
        let squeezed = bare.filter { !"¥￥•·・●○◎".contains($0) }
        // 189 (N24, Echo 189, 11-27 12:29 首爾: WeCom's private chat with 蓝海乐: the quick bar's ¥ of 「¥发起收款」, read on
        // a line of its own, was reported as a message 「¥」 and answered): a line of the bar's icons alone is no text
        if squeezed.isEmpty && !bare.isEmpty { return "" }
        var rest = squeezed
        for w in quickBarWords { rest = rest.replacingOccurrences(of: w, with: "") }
        if rest.count < squeezed.count && rest.count <= 1 { return "" }
        // 184 (C14): two of the bar's buttons on one line is the bar, whatever else was read with it.
        if quickBarWords.filter({ squeezed.contains($0) }).count >= 2 { return "" }
        for tail in uiTails where bare.hasSuffix(tail) {
            if let r = t.range(of: tail, options: .backwards) { t = String(t[..<r.lowerBound]) }
            t = t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "•·・●")))
        }
        return t
    }

    /// 182 (Echo 181, 11-26: WeCom's line to 企微测试群 dropped in over WeChat's 测试群 as a banner, and was reported as
    /// 测试群's): an in-app banner sits in the title bar's band, left-aligned, "name: message". The chat's own title is
    /// centred and has no colon there. While one shows, the chat is not read (it goes in a few seconds).
    static func bannerShown(_ pieces: [CandidatePicker.Piece], px: Pixels? = nil) -> Bool { bannerPiece(pieces, px: px) != nil }
    /// 188 (B45, Echo 187, 11-27: twice the owner's line in 测试群 was lost under its red mark, nothing logged): a
    /// window's words are read from its very top, so WeChat's window had the iPad's status bar in them, 「◀企业微信 01:00
    /// 11月27日周五 微信」 at y ~0.016 with its time's colon, on the band's top edge (0.02): a box a little lower made every
    /// read of the chat "under a banner", so not read at all. A banner's line with a colon is its message, under its
    /// title (~0.05–0.10): from 0.03 down; the status bar and a chat's own time labels are never one.
    /// 188 (B45 again, Echo 187, 11-27 17:35: WeCom's 企微测试群 opened for a quote and a video, nothing read, nothing
    /// logged: 小藍's own blue line 「【模拟服务器】收到：［图片］」 sat at the window's top, from 0.26 across, a colon in
    /// it): a banner is two lines, its title and right under it its message, starting at the same place; one line with
    /// a colon is none.
    /// 188 night (Echo 188, 11-27 08:00: my own long green bubble 「…长消息：这一条故意写得比较长，」, two lines from the same
    /// place at the window's top, was taken for a banner: the back waited 5 s and WeCom's order with it, 25.5 s): a line
    /// on a bubble of mine (green, WeCom's blue) is no banner's, with the window's picture at hand.
    static func bannerPiece(_ pieces: [CandidatePicker.Piece], px: Pixels? = nil) -> CandidatePicker.Piece? {
        pieces.first { p in
            if let px, kind(p.box, px) == .mine { return false }
            return (0.03...0.14).contains(Double(p.box.midY)) && Double(p.box.minX) < 0.3 && p.text.count >= 4
                && (p.text.contains(":") || p.text.contains("："))
                && !(Double(p.box.midY) < 0.045 && statusBar(p.text)) && !WatchReport.timeLabel(p.text)
                && pieces.contains { t in
                    !(t.box == p.box && t.text == p.text) && (0.012...0.05).contains(Double(p.box.midY - t.box.midY))
                        && abs(Double(t.box.minX - p.box.minX)) <= 0.04
                }
        }
    }
    /// 188 (B45): under a banner the window is still read, its top (the banner's band) left out: the new lines are at
    /// the bottom, and nothing is lost when the banner was not one.
    static let bannerBand = 0.15
    /// 188: the iPad's status bar as read: a time with a date or weekday, or the ◀ back to the app before.
    static func statusBar(_ text: String) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        return t.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
            && (t.contains("月") || t.contains("周") || t.contains("星期") || t.hasPrefix("◀") || t.hasPrefix("<"))
    }

    /// A read line: what the recognizer found and what it sits on.
    struct Piece: Equatable { var text: String; var box: CGRect; var kind: Kind }

    /// The chat's messages, oldest first, from the pieces between the title bar and the input bar.
    static func lines(_ pieces: [Piece], title: String) -> WatchReport.Screen {
        let (name, group) = titled(title)
        var lines: [WatchReport.Line] = []
        var sender = group ? "" : name
        var open: (kind: Kind, text: String, top: Double, bottom: Double, height: Double)?
        func close() {
            if let o = open {
                let text = withoutUIWords(o.text)
                if !text.isEmpty {
                    lines.append(WatchReport.Line(sender: o.kind == .mine ? "我" : (sender.isEmpty ? name : sender), text: text,
                                                  mine: o.kind == .mine))
                }
            }
            open = nil
        }
        let sorted = pieces.sorted { abs($0.box.midY - $1.box.midY) < min($0.box.height, $1.box.height) / 2
            ? $0.box.minX < $1.box.minX : $0.box.midY < $1.box.midY }
        for p in sorted {
            let top = Double(p.box.minY), bottom = Double(p.box.maxY), height = Double(p.box.height)
            switch p.kind {
            case .mine, .theirs:
                if var o = open, o.kind == p.kind {
                    let sameRow = abs((top + bottom) / 2 - (o.top + o.bottom) / 2) < min(height, o.height) / 2
                    let nextRow = top - o.bottom < 0.7 * max(height, o.height)
                    // 192 (B28, Echo 185 11-26: 「6原生家庭创伤治愈.docx」 and 「12KB未下载」 reported as two messages): a file
                    // card's size, smaller and lower under its name, is the card's
                    let cardSize = XiaoLanMediaFind.fileSizeLine(p.text) && XiaoLanMediaFind.fileName(o.text) != nil && top - o.bottom < 0.05
                    if sameRow || nextRow || cardSize {
                        o.text += sameRow ? " " + p.text : p.text
                        o.bottom = max(o.bottom, bottom)
                        open = o
                        continue
                    }
                }
                close()
                open = (p.kind, p.text, top, bottom, height)
            case .grey:
                close()
                // 192 (B30, Echo 185 11-26: 测试群's 「185要撤回」 recalled, the chat's grey 「"主人蓝海乐" 撤回了一条消息」 not
                // reported, the server keeping what was taken back): someone's recall is a line of its own
                if let who = XiaoLanMediaFind.recaller(p.text) {
                    lines.append(WatchReport.Line(sender: who, text: XiaoLanMediaFind.recallLine(who), mine: false))
                    continue
                }
                // A name sits just right of the avatars, short; times and system lines are centred and wide.
                if group, p.box.minX < 0.2, p.box.maxX < 0.6 { sender = p.text.trimmingCharacters(in: .whitespaces) }
            case .other:
                continue
            }
        }
        close()
        return WatchReport.Screen(title: name, group: group, lines: lines)
    }

    /// 165: where to tap to type in a chat, with no model: in the white field just under the input bar's top (iPad
    /// WeChat 11-25: bar from 0.645, field centre ~0.672 with the keyboard up; at the bottom without it).
    static func inputBox(_ jpeg: Data) -> CGPoint? {
        guard let px = Pixels(jpeg), let top = px.inputTop(from: 0.3) else { return nil }
        let y = min(top + 0.027, 0.985)
        let (r, g, b) = px.rgb(0.45, y)
        return r >= 250 && g >= 250 && b >= 250 ? CGPoint(x: 0.45, y: y) : nil
    }

    /// The chat on screen (its title already read and checked by the caller), or nil when the frame cannot be read or
    /// a banner covers its top. 182 (user 11-26: "速度太慢了"): `rows`, the window's words already read for this very
    /// frame, are used as they are instead of reading the picture a second time.
    /// `banner` false: read even under a banner (checking my own newest line after a send; a banner is never mine).
    static func screen(_ jpeg: Data, title: String, rows: [[CandidatePicker.Piece]]? = nil, banner: Bool = true) -> WatchReport.Screen? {
        guard let px = Pixels(jpeg) else { return nil }
        let bottom = px.inputTop(from: 0.12) ?? 0.95
        let read = Array((rows ?? CandidatePicker.rows(in: jpeg, top: 0.08, bottom: bottom)).joined())
        let top = banner && bannerShown(read, px: px) ? bannerBand : 0.085  // 188 (B45): the banner's band left out, not the window
        let pieces = read
            .filter { Double($0.box.minY) > top && Double($0.box.maxY) < bottom }
            .map { Piece(text: $0.text, box: $0.box, kind: kind($0.box, px)) }
        // 188: voice notes, videos and pictures as lines of their own; words read off a picture are none
        return lines(bySide(XiaoLanMediaFind.withMedia(pieces, px, top: top, bottom: bottom), px), title: title)
    }

    /// 173 (user 11-25 on WeCom: "我發的那個泡泡…他就還是白色嘛"): who wrote a bubble is the side its avatar is on, not
    /// its colour alone (WeCom's bubbles can be white both ways). A bubble's first line sits beside its avatar: an avatar
    /// on the left only = theirs, on the right only = mine. The lines under it (past the avatar) keep that bubble's
    /// side. Grey (names, times) stays as it is.
    /// 182 (Echo 181, 11-26: the owner's wide green bubble "【小蓝测试】181 个微发消息 / 0001" had its second line
    /// reported five times as someone else's): a green (WeChat) or blue (WeCom) bubble is always mine, whatever the
    /// strips beside it show (a wide bubble's own edge reaches into the left avatar strip). Only a white line is told by
    /// the side of its avatar.
    static func bySide(_ pieces: [Piece], _ px: Pixels) -> [Piece] {
        let sorted = pieces.sorted { $0.box.midY < $1.box.midY }
        var out: [Piece] = []
        var last: Piece?
        for var p in sorted {
            if p.kind == .theirs {
                switch avatarSide(p.box, px) {
                case .some(.theirs): p.kind = .theirs
                case .some(.mine): p.kind = .mine
                default:
                    // No avatar beside it: a later line of the bubble above, if it follows on closely in the same colour.
                    if let l = last, l.kind == .mine || l.kind == .theirs,
                       Double(p.box.minY - l.box.maxY) < 0.8 * Double(max(p.box.height, l.box.height)),
                       kind(p.box, px) == kind(l.box, px) {
                        p.kind = l.kind
                    }
                }
            }
            if p.kind != .other { last = p }
            out.append(p)
        }
        return out
    }

    /// Which side has an avatar level with the top of this line: a picture in the left strip (0.01–0.14 across) or the
    /// right one (0.86–0.99), told by its contrast or colour. A window's own shading by the gap between split windows
    /// (11-25: 222 fading to 205 over the right strip) is neither.
    static func avatarSide(_ box: CGRect, _ px: Pixels) -> Kind? {
        let y = Double(box.minY) + 0.004
        func avatar(_ from: Double) -> Bool {
            var lo = 255, hi = 0
            for i in 0..<14 {
                let (r, g, b) = px.rgb(from + Double(i) * 0.01, y)
                if max(r, g, b) - min(r, g, b) > 40 { return true }
                let l = (r * 3 + g * 6 + b) / 10
                (lo, hi) = (min(lo, l), max(hi, l))
            }
            return hi - lo > 45
        }
        let left = avatar(0.01), right = avatar(0.86)
        if left && !right { return .theirs }
        if right && !left { return .mine }
        return nil
    }
}
