import Foundation
import CoreGraphics

/// 188 (user 11-27: 「鏈接點開看…點不開就複製鏈接到瀏覽器打開看，圖片要會看内容，影片要看是什麽還要知道説了什麽，
/// 文件要打開看…語音也要轉文字看到，別人@你，給別人回消息要引用那條消息回復」): what a chat line is (a voice note, a
/// video, a picture, a file, a link), where it sits in its window, and the words around opening, reading and closing
/// it, as measured on the iPad (docs/plan-188-media.md). Pure: no taps here (XiaoLanMediaRead does those), so all of
/// it is tested on its own. Every point is a fraction of the window (the rows read off its crop).
enum XiaoLanMediaFind {
    typealias Piece = CandidatePicker.Piece

    enum Kind: String, CaseIterable { case voice, video, image, file, link }

    /// The words a report starts with, as the chat apps write them.
    static func label(_ k: Kind) -> String {
        switch k {
        case .voice: return "语音"
        case .video: return "视频"
        case .image: return "图片"
        case .file: return "文件"
        case .link: return "链接"
        }
    }

    // MARK: what a line is

    /// A list preview's or a chat line's leading tag, half- or full-width brackets ("[语音] 7\"", "［图片］").
    static func tag(_ text: String) -> Kind? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "［", with: "[").replacingOccurrences(of: "］", with: "]")
        // a group's preview: "张三: [图片]"
        let body: Substring = {
            if let colon = t.firstIndex(where: { $0 == ":" || $0 == "：" }), t.distance(from: t.startIndex, to: colon) <= 20,
               t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                return Substring(t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            }
            return Substring(t)
        }()
        guard body.hasPrefix("["), let close = body.firstIndex(of: "]") else { return nil }
        let name = body[body.index(after: body.startIndex)..<close]
        switch name {
        case "语音", "語音", "Voice": return .voice
        case "视频", "視頻", "影片", "Video": return .video
        case "图片", "圖片", "照片", "Photo", "Image": return .image
        case "文件", "檔案", "File": return .file
        case "链接", "鏈接", "連結", "Link": return .link
        default: return nil
        }
    }

    /// What a chat line or a preview is; nil: plain words (or a sticker, a red packet, …, which are not read).
    static func kind(of text: String) -> Kind? {
        if let k = tag(text) { return k }
        if url(in: text) != nil { return .link }
        if fileName(text) != nil { return .file }
        if voiceSeconds(text) != nil { return .voice }
        return nil
    }

    /// The first web address in the words: http(s)://…, or www.….
    static func url(in text: String) -> String? {
        let t = text.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "／", with: "/")
        guard let r = t.range(of: #"(https?://|www\.)[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let u = String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]'"))
        return u.count >= 10 ? u : nil
    }

    static let fileExtensions = ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "pdf", "txt", "csv", "zip", "rar", "7z",
                                 "md", "rtf", "pages", "numbers", "key", "wps", "et", "dps", "apk", "ipa", "mp3", "wav", "m4a"]

    /// A file's name in the words ("6原生家庭创伤治愈.docx", "伤治愈.docx13K", "治愈.docx 12KB未下载").
    static func fileName(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        let alt = fileExtensions.joined(separator: "|")
        guard let r = t.range(of: #"[^\s/\\:：]{1,60}\.(\#(alt))(?![A-Za-z])"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        return String(t[r])
    }

    /// A voice note's length as read off its bubble (「4"」, 「•））4"」, 「7″」); nil: not one. The icon reads as a few
    /// signs (「（小））」); words around it are not a voice note.
    static func voiceSeconds(_ text: String) -> Int? {
        let t = text.replacingOccurrences(of: "转文字", with: "").filter { !$0.isWhitespace }
        guard (2...9).contains(t.count),
              let r = t.range(of: #"(\d{1,2})["″”“'’]"#, options: .regularExpression) else { return nil }
        let rest = t.replacingCharacters(in: r, with: "")
        guard rest.filter({ $0.isLetter && $0 != "小" }).count <= 1 else { return nil }
        return Int(t[r].filter(\.isNumber))
    }

    /// A video's length label on its thumbnail (「0:09」, 「1:02:03」), in seconds; time labels of the chat (「17:35」
    /// centred, or with a day) are the caller's to tell apart by place.
    static func clockSeconds(_ text: String) -> Int? {
        let t = text.filter { !$0.isWhitespace }
        guard t.range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil else { return nil }
        return t.split(separator: ":").reduce(0) { $0 * 60 + (Int($1) ?? 0) }
    }

    // MARK: where it is

    static func pieces(_ rows: [[Piece]], top: Double = 0.09, bottom: Double = 0.93) -> [Piece] {
        rows.joined().filter { (top...bottom).contains(Double($0.box.midY)) }.sorted { $0.box.midY < $1.box.midY }
    }

    /// The newest (lowest) voice note's bubble.
    static func voiceBubble(_ rows: [[Piece]]) -> CGPoint? {
        pieces(rows).last { voiceSeconds($0.text) != nil }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// WeChat's 「转文字」 button beside a voice note not turned into words yet (OCR 「•转文字」), the lowest; never a
    /// 「取消转换」 (user's rule: it is never clicked).
    static func voiceButton(_ rows: [[Piece]]) -> CGPoint? {
        pieces(rows).last { p in
            let t = p.text.filter { !$0.isWhitespace }
            return t.contains("转文字") && !t.contains("取消") && t.count <= 6
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The newest video's length label, off the window's middle (a chat's own time labels sit centred).
    static func videoLabel(_ rows: [[Piece]]) -> Piece? {
        pieces(rows).last { p in
            guard let s = clockSeconds(p.text), s > 0 else { return false }
            return abs(Double(p.box.midX) - 0.5) > 0.06 && Double(p.box.height) < 0.016
        }
    }

    /// Where to click a video: its thumbnail, up and to the left of the label at its bottom right (measured: label at
    /// 0.30/0.49 of WeCom's window, the click that opened it 0.06 left and 0.06 up).
    static func videoSpot(_ label: Piece) -> CGPoint {
        CGPoint(x: max(0.05, Double(label.box.midX) - 0.07), y: max(0.1, Double(label.box.midY) - 0.06))
    }

    /// A file card's own words: its name, and at most its size and 「未下载」 (「6原生家庭创伤治愈.docx」, 「伤治愈.docx13K」);
    /// a sentence that names a file (the server's 「【模拟服务器】收到：6原生家庭创伤治愈.docx13K」) is none.
    static func cardText(_ text: String) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        guard let name = fileName(t), let r = t.range(of: name) else { return false }
        var rest = t.replacingCharacters(in: r, with: "")
        rest = rest.replacingOccurrences(of: #"\d+(\.\d+)?[KMG]B?"#, with: "", options: [.regularExpression, .caseInsensitive])
        rest = rest.replacingOccurrences(of: "未下载", with: "").replacingOccurrences(of: "已下载", with: "")
        return rest.count <= 2
    }

    /// The newest file card's name; `hint` (the line or preview) picks the card when several show.
    /// 188 night (Echo 188, 11-27 05:49: WeCom's 「文件没有打开」 twice: the server's reply naming the file, lower down, was
    /// clicked, not the card): a card's own words only.
    static func fileCard(_ rows: [[Piece]], hint: String) -> CGPoint? {
        let all = pieces(rows).filter { cardText($0.text) }
        let want = fileName(hint).map { $0.lowercased() }
        let pick = all.last { p in
            guard let want, let name = fileName(p.text)?.lowercased() else { return false }
            return want.hasSuffix(name) || name.hasSuffix(want)
        } ?? all.last
        return pick.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The newest line with a web address, at the address's own line (the click one line lower missed, 11-27).
    static func linkSpot(_ rows: [[Piece]]) -> Piece? {
        pieces(rows).last { url(in: $0.text) != nil }
    }

    /// A word on the window as its own piece (a menu's 「引用」「转文字」, a page's 「关闭」「预览」), the lowest when several.
    static func button(_ rows: [[Piece]], _ word: String, top: Double = 0.0, bottom: Double = 1.0) -> CGPoint? {
        rows.joined().filter { p in
            (top...bottom).contains(Double(p.box.midY)) && p.text.filter({ !$0.isWhitespace && $0 != "•" && $0 != "·" }) == word
        }.max { $0.box.midY < $1.box.midY }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The line to quote: the lowest piece showing the original's words (its first line, or a line of it), never the
    /// input bar's or a quote bar's own text.
    static func quoteSpot(_ rows: [[Piece]], quote: String) -> CGPoint? {
        let want = plain(quote)
        guard want.count >= 2 else { return nil }
        let hit = pieces(rows, top: 0.1, bottom: 0.86).last { p in
            let t = plain(p.text)
            guard t.count >= 2 else { return false }
            if t == want { return true }
            return min(t.count, want.count) >= 4 && (want.hasPrefix(t) || t.hasPrefix(want) || want.contains(t))
        }
        return hit.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The quote bar shown after 「引用」: 「主人蓝海乐：这是什么」 (WeChat, under the field) or 「主人蓝海乐: 这不对」
    /// (WeCom, over it), in the window's bottom part.
    static func quoteBar(_ rows: [[Piece]], quote: String) -> CGPoint? {
        let want = plain(quote)
        guard want.count >= 2 else { return nil }
        let head = String(want.prefix(6))
        return Array(rows.joined()).last { p in
            guard Double(p.box.midY) > 0.5 else { return false }
            let t = p.text
            guard let colon = t.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
            let after = plain(String(t[t.index(after: colon)...]))
            return !after.isEmpty && (after.hasPrefix(head) || head.hasPrefix(after))
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// A bare spot to close a long-press menu: the chat's right edge (where the menu was closed on the iPad, 11-27),
    /// at a height with no words within 0.04 (so no bubble, avatar or menu row); nil: none.
    static func blankSpot(_ rows: [[Piece]]) -> CGPoint? {
        let ys = rows.joined().map { Double($0.box.midY) }
        let free = stride(from: 0.25, through: 0.75, by: 0.025).map { y in (y, ys.map { abs($0 - y) }.min() ?? 1) }
        guard let best = free.max(by: { $0.1 < $1.1 }), best.1 >= 0.04 else { return nil }
        return CGPoint(x: 0.9, y: best.0)
    }

    /// The words of the apps' long-press menus (WeChat's chat menu, WeChat's web page menu, WeCom's menu).
    static let menuWords = ["拷贝", "复制", "搜一搜", "翻译", "查询", "打开链接", "转发", "收藏", "删除", "多选", "引用",
                            "听筒模式", "取消转换", "转文字", "置顶", "提醒", "共享"]

    /// A menu's item: its own piece, or its share of a piece OCR read the menu's row into (11-27: 「拷贝搜一搜翻译打开链接＞」
    /// as one piece): the word's middle by its place among the characters. Only a run of menu words counts, never a
    /// sentence that holds the word (「14天内可以预览和下载」).
    static func menuItem(_ rows: [[Piece]], _ word: String) -> CGPoint? {
        if let p = button(rows, word) { return p }
        for p in rows.joined() {
            let t = p.text.filter { !$0.isWhitespace }
            guard t.count <= 20, let r = t.range(of: word) else { continue }
            let others = menuWords.filter { $0 != word && t.contains($0) }
            guard !others.isEmpty else { continue }
            let start = t.distance(from: t.startIndex, to: r.lowerBound)
            let middle = (Double(start) + Double(word.count) / 2) / Double(t.count)
            return CGPoint(x: Double(p.box.minX) + Double(p.box.width) * middle, y: Double(p.box.midY))
        }
        return nil
    }

    /// WeChat's page for a link it will not open: 「如需浏览，请长按网址复制后使用浏览器访问」 (measured 11-27, a Douyin link).
    static func linkBlocked(_ rows: [[Piece]]) -> Bool {
        rows.joined().contains { p in
            let t = p.text.filter { !$0.isWhitespace }
            return t.contains("如需浏览") || t.contains("用浏览器访问") || t.contains("长按网址复制")
        }
    }

    /// The address on a page, read loosely (11-27 the same line read 「nttps://.douyin.com/…」 and 「https://v.aouyin.com/…」:
    /// it is pressed, never copied off the OCR).
    static func addressLine(_ rows: [[Piece]]) -> Piece? {
        rows.joined().filter { p in
            let t = p.text.lowercased()
            return t.contains("://") || t.range(of: #"[a-z0-9\-]+\.(com|cn|net|org|io|me|tv)(/|$)"#, options: .regularExpression) != nil
        }.max { $0.box.width < $1.box.width }
    }

    /// Safari over the whole screen: its name in the status bar, or an address bar's domain at the top.
    static func safariShown(_ rows: [[Piece]]) -> Bool {
        rows.joined().contains { p in Double(p.box.midY) < 0.08 && p.text.lowercased().contains("safari") }
    }

    // MARK: messages with no words of their own, as lines

    /// 188 (11-27 note: 「沒有文字的訊息（影片、語音、圖片）也要成為一行（例如「[视频] 0:09」），不能只靠列表預覽補最新
    /// 一則」): a window's pieces with its voice notes, videos and pictures as lines of their own: 「[语音] 4"」 (a length on a
    /// bubble, or WeChat's 「转文字」 beside one), 「[视频] 0:09」 (a length label off the middle), 「[图片]」 (a block of picture
    /// beside someone's avatar). The words OCR read off a picture or a video are not lines; neither is a voice note's
    /// speaker read as a stray sign. Read every time the chat is, so the history knows them, a new one is reported and
    /// looked at (paneRead → XiaoLanMediaRead), in an open chat too.
    static func withMedia(_ pieces: [WatchOCR.Piece], _ px: WatchOCR.Pixels, top: Double, bottom: Double) -> [WatchOCR.Piece] {
        var out: [WatchOCR.Piece] = []
        var voiceRows: [Double] = []
        func onVoiceRow(_ y: Double) -> Bool { voiceRows.contains { abs($0 - y) < 0.02 } }
        // voice: lengths first, then WeChat's 转文字 where no length was read on that row
        for p in pieces {
            guard let s = voiceSeconds(p.text) else { continue }
            out.append(WatchOCR.Piece(text: "[语音] \(s)\"", box: p.box, kind: p.kind == .mine ? .mine : .theirs))
            voiceRows.append(Double(p.box.midY))
        }
        for p in pieces {
            let t = p.text.filter { !$0.isWhitespace }
            guard t.contains("转文字"), !t.contains("取消"), t.count <= 6, !onVoiceRow(Double(p.box.midY)) else { continue }
            let note = CGRect(x: 0.16, y: Double(p.box.minY), width: 0.08, height: Double(p.box.height))
            out.append(WatchOCR.Piece(text: "[语音]", box: note, kind: .theirs))
            voiceRows.append(Double(p.box.midY))
        }
        // videos: their length labels; pictures: blocks beside an avatar, with no label in them
        var videos: [CGRect] = []
        for p in pieces {
            guard let s = clockSeconds(p.text), s > 0, abs(Double(p.box.midX) - 0.5) > 0.06, Double(p.box.height) < 0.016 else { continue }
            out.append(WatchOCR.Piece(text: "[视频] \(clock(s))", box: p.box, kind: Double(p.box.midX) < 0.5 ? .theirs : .mine))
            videos.append(p.box)
        }
        let blocks = pictureBlocks(px, pieces: pieces, top: top, bottom: bottom)
        let pictures = blocks.filter { b in !videos.contains { v in b.insetBy(dx: -0.02, dy: -0.02).contains(CGPoint(x: v.midX, y: v.midY)) } }
        for b in pictures {
            out.append(WatchOCR.Piece(text: "[图片]", box: CGRect(x: Double(b.minX), y: Double(b.minY), width: 0.08, height: 0.02), kind: .theirs))
        }
        let covered = blocks  // a video's thumbnail is one of them; words on one not found are .other, never lines anyway
        for p in pieces {
            if voiceSeconds(p.text) != nil { continue }
            let t = p.text.filter { !$0.isWhitespace }
            if t.contains("转文字"), !t.contains("取消"), t.count <= 6 { continue }
            if clockSeconds(p.text) != nil, videos.contains(p.box) { continue }
            let centre = CGPoint(x: p.box.midX, y: p.box.midY)
            if p.kind != .grey, covered.contains(where: { $0.contains(centre) }) { continue }  // words on a picture
            if p.kind != .grey, p.kind != .mine, onVoiceRow(Double(p.box.midY)),
               p.text.filter({ $0.isLetter || $0.isNumber }).count <= 2 { continue }  // a voice note's speaker
            out.append(p)
        }
        return out
    }

    /// A message beside someone's avatar (the window's left strip) that is a block of picture rather than a bubble of
    /// words: at least 0.12 wide and 0.06 tall, under half of it a bubble's plain colour (white, WeChat's green, WeCom's
    /// blue). Its top is level with the avatar's, under the sender's name in a group.
    static func pictureBlocks(_ px: WatchOCR.Pixels, pieces: [WatchOCR.Piece], top: Double, bottom: Double) -> [CGRect] {
        var blocks: [CGRect] = []
        var y = top
        var wasAvatar = avatarAt(px, y)
        while y < bottom - 0.06 {
            y += 0.004
            let isAvatar = avatarAt(px, y)
            defer { wasAvatar = isAvatar }
            guard isAvatar, !wasAvatar else { continue }
            var start = y
            if let name = pieces.first(where: { $0.kind == .grey && Double($0.box.minX) < 0.3 && abs(Double($0.box.minY) - y) < 0.02 }) {
                start = Double(name.box.maxY) + 0.004
            }
            guard let r = block(px, from: start, bottom: bottom), r.width >= 0.12, r.height >= 0.06,
                  bubbleShare(px, r) < 0.5, !blocks.contains(where: { $0.intersects(r) }) else { continue }
            blocks.append(r)
        }
        return blocks
    }

    /// An avatar in the window's left strip at this height: colour, or light and dark side by side.
    static func avatarAt(_ px: WatchOCR.Pixels, _ y: Double) -> Bool {
        var lo = 255, hi = 0
        for i in 0..<12 {
            let (r, g, b) = px.rgb(0.015 + Double(i) * 0.01, y)
            if max(r, g, b) - min(r, g, b) > 40 { return true }
            let l = (r * 3 + g * 6 + b) / 10
            (lo, hi) = (min(lo, l), max(hi, l))
        }
        return hi - lo > 45
    }

    static func isBackground(_ c: (Int, Int, Int)) -> Bool { WatchOCR.kind(of: c) == .grey }

    /// The message's extent from `start`: right of the avatar until the chat's grey, down until three rows of it.
    static func block(_ px: WatchOCR.Pixels, from start: Double, bottom: Double) -> CGRect? {
        let y = start + 0.015
        var x = 0.14
        while x < 0.6, isBackground(px.rgb(x, y)) { x += 0.005 }
        guard x < 0.6 else { return nil }
        let left = x
        var right = x, grey = 0
        while x < 0.86 {
            if isBackground(px.rgb(x, y)) {
                grey += 1
                if grey >= 3 { break }
            } else {
                (grey, right) = (0, x)
            }
            x += 0.005
        }
        let mid = (left + right) / 2
        var yy = start, filled = start
        grey = 0
        while yy < bottom {
            if isBackground(px.rgb(mid, yy)) && isBackground(px.rgb(left + 0.01, yy)) {
                grey += 1
                if grey >= 3 { break }
            } else {
                (grey, filled) = (0, yy)
            }
            yy += 0.004
        }
        return CGRect(x: left, y: start, width: right - left, height: filled - start)
    }

    /// The share of a block in a bubble's plain colour (white, or a bubble of mine): a bubble of words is mostly that.
    static func bubbleShare(_ px: WatchOCR.Pixels, _ r: CGRect) -> Double {
        var n = 0, plainColour = 0
        for i in 1...6 {
            for j in 1...8 {
                let c = px.rgb(Double(r.minX) + Double(r.width) * Double(j) / 9, Double(r.minY) + Double(r.height) * Double(i) / 7)
                n += 1
                if WatchOCR.kind(of: c) == .mine || (c.0 >= 250 && c.1 >= 250 && c.2 >= 250) { plainColour += 1 }
            }
        }
        return Double(plainColour) / Double(n)
    }

    /// Of the same things top to bottom, the one `rank` from the bottom (0: the lowest); fewer, the lowest.
    static func pick<T>(_ items: [T], rank: Int) -> T? {
        guard !items.isEmpty else { return nil }
        return rank < items.count ? items[items.count - 1 - rank] : items.last
    }

    static func voiceSpots(_ rows: [[Piece]]) -> [CGPoint] {
        pieces(rows).filter { voiceSeconds($0.text) != nil }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    static func voiceButtons(_ rows: [[Piece]]) -> [CGPoint] {
        pieces(rows).filter { p in
            let t = p.text.filter { !$0.isWhitespace }
            return t.contains("转文字") && !t.contains("取消") && t.count <= 6
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    static func videoLabels(_ rows: [[Piece]]) -> [Piece] {
        pieces(rows).filter { p in
            guard let s = clockSeconds(p.text), s > 0 else { return false }
            return abs(Double(p.box.midX) - 0.5) > 0.06 && Double(p.box.height) < 0.016
        }
    }

    static func linkSpots(_ rows: [[Piece]]) -> [Piece] { pieces(rows).filter { url(in: $0.text) != nil } }

    /// Where a message a reply quotes is, when it is a voice note, a video, a picture, a file or a link (the quote is
    /// what was reported: 「[语音] 4"\n语音转文字：…」): the newest of that kind on the window.
    static func mediaQuoteSpot(_ rows: [[Piece]], _ px: WatchOCR.Pixels?, quote: String) -> CGPoint? {
        let first = quote.split(separator: "\n").first.map { String($0) } ?? quote
        var found: Kind? = tag(first)
        if found == nil, url(in: first) != nil { found = .link }
        if found == nil, fileName(first) != nil { found = .file }
        guard let kind = found else { return nil }
        switch kind {
        case .voice: return voiceSpots(rows).last ?? voiceButtons(rows).last.map { CGPoint(x: max(0.16, Double($0.x) - 0.12), y: Double($0.y)) }
        case .video: return videoLabels(rows).last.map(videoSpot)
        case .file: return fileCard(rows, hint: first)
        case .link: return linkSpots(rows).last.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
        case .image:
            guard let px else { return nil }
            let words = rows.joined().map { WatchOCR.Piece(text: $0.text, box: $0.box, kind: .other) }
            return pictureBlocks(px, pieces: words, top: 0.09, bottom: 0.93).last.map { CGPoint(x: $0.midX, y: $0.midY) }
        }
    }

    /// 188 (大藍's joinVoiceText): a line that is the words a voice note was turned into here (WeChat puts them under
    /// it as a bubble of their own, WeCom inside the note's) is no new message: it was reported with its voice note.
    static func isEcho(_ text: String, of transcripts: [String]) -> Bool {
        var t = text
        let voice = tag(t) == .voice
        if voice, let close = t.firstIndex(where: { $0 == "]" || $0 == "］" }) { t = String(t[t.index(after: close)...]) }
        let rest = plain(t).filter { !$0.isNumber }
        guard voice ? !rest.isEmpty : rest.count >= 2 else { return false }
        return transcripts.contains { e in
            let p = plain(e).filter { !$0.isNumber }
            return !p.isEmpty && (p.contains(rest) || (rest.count >= 4 && rest.contains(p)))
        }
    }

    /// A window's picture as a 48×96 grey grid, to tell whether it changed since the last read.
    static func signature(_ px: WatchOCR.Pixels) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(48 * 96)
        for j in 0..<96 {
            for i in 0..<48 {
                let (r, g, b) = px.rgb((Double(i) + 0.5) / 48, (Double(j) + 0.5) / 96)
                out.append(UInt8(min(255, (r * 3 + g * 6 + b) / 10)))
            }
        }
        return out
    }

    /// Unchanged: the same size and no cell moved by more than 10 (a red mark coming moves a few by far more).
    static func sameSignature(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        return !zip(a, b).contains { abs(Int($0) - Int($1)) > 10 }
    }

    // MARK: what it said

    /// A video player's time (「00:04/00:09」 WeChat, 「00:00:00:09」 WeCom: now and length run together): its length in
    /// seconds; nil: no player on the window.
    static func playerLength(_ rows: [[Piece]]) -> Int? {
        for p in rows.joined() where Double(p.box.midY) > 0.6 {
            let t = p.text.filter { !$0.isWhitespace }
            if let r = t.range(of: #"^\d{1,2}:\d{2}/(\d{1,2}:\d{2}(:\d{2})?)$"#, options: .regularExpression) {
                let total = t[r].split(separator: "/").last.map { String($0) } ?? ""
                if let s = clockSeconds(total) { return s }
            }
            if t.range(of: #"^\d{2}:\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                let parts = t.split(separator: ":").compactMap { Int($0) }
                if parts.count == 4 { return parts[2] * 60 + parts[3] }
            }
        }
        return nil
    }

    /// The longest a video is watched and listened to (user 11-27: three minutes; longer ones are cut and said so).
    static let videoMost = 180

    /// WeCom's player ✕ (an icon OCR cannot read) at the window's top left: measured at the screen's (0.529, 0.053),
    /// the right window starting at ~0.505 and ~0.495 wide.
    static let weworkPlayerClose = CGPoint(x: 0.05, y: 0.053)
    /// WeChat's file preview sheet: its ∨ at the top left, level with its title 「预览」 (the screen's 0.035 of a left
    /// window ~0.49 wide); clicked once, the sheet becomes the whole page and its words can be read.
    static let wechatSheetGrow = 0.07

    static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// The words that came onto the window after a voice note was turned into words: what is new, below `below`, without
    /// the apps' own marks (「转换完成」, the seconds, 「转文字」).
    /// 189 (N27/N28, Echo 189, 11-27 12:40 首爾: a voice note's words read as 「小））で"多少錢？G+在这」 — its own length
    /// and the input bar with them — and another's as 「我们按套餐收费：基础版」, a line of my older reply that scrolled into
    /// view as the words came in under the note): with the note's length given, only what is new under that note (the
    /// `rank`-th newest of that length), within 0.2 of the window, is its words.
    static func added(before: [Piece], after: [Piece], below: Double = 0.3, seconds: Int? = nil, rank: Int = 0) -> String {
        let known = Set(before.map { plain($0.text) })
        var floor = below, ceiling = 1.0
        if let seconds {
            let notes = after.filter { voiceSeconds($0.text) == seconds }.sorted { $0.box.midY > $1.box.midY }
            if !notes.isEmpty {  // not found: everything new below `below`, as before
                floor = Double(notes[min(rank, notes.count - 1)].box.maxY)
                ceiling = floor + 0.2
            }
        }
        let new = after.filter { p in
            let t = plain(p.text), y = Double(p.box.midY)
            return y > floor && y <= ceiling && !t.isEmpty && !known.contains(t) && !t.contains("转换完成")
                && !t.contains("转文字") && voiceSeconds(p.text) == nil && t != "✓"
        }.sorted { $0.box.midY < $1.box.midY }
        return new.map(\.text).joined()
    }

    /// A voice note's length in its line as reported (「[语音] 9"」 → 9).
    static func noteSeconds(_ line: String) -> Int? {
        guard let r = line.range(of: #"(\d{1,2})["″”“'’]"#, options: .regularExpression) else { return nil }
        return Int(line[r].filter(\.isNumber))
    }

    /// A page's words top to bottom (a file's preview, a link's page), without its bars, at most `most` characters.
    static func pageText(_ rows: [[Piece]], from top: Double = 0.08, to bottom: Double = 0.95, most: Int = 800) -> String {
        let lines = rows.compactMap { row -> String? in
            let inside = row.filter { (top...bottom).contains(Double($0.box.midY)) }.sorted { $0.box.minX < $1.box.minX }
            return inside.isEmpty ? nil : inside.map(\.text).joined(separator: " ")
        }
        let all = lines.joined(separator: "\n")
        return all.count > most ? String(all.prefix(most)) + "…" : all
    }

    /// What the report says: the line as read, then what was seen. Failing, why (so the line is never lost).
    static func report(_ line: String, kind: Kind, seen: String?, failed: String?) -> String {
        let head = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let mark = "[\(label(kind))]"
        let first = tag(head) == kind ? head : (head.isEmpty ? mark : "\(mark) \(head)")
        if let seen, !seen.isEmpty { return "\(first)\n\(seen)" }
        return "\(first)\n（小蓝没能打开看：\(failed ?? "原因不明")）"
    }

    /// For the model looking at pictures and video frames: what it is, briefly, in Chinese; no numbers of a person.
    static let lookSystem = """
    你是聊天助手的眼睛。用户发来的是聊天软件里一张图片、一个视频的几帧截图，或者点开的网页截图。\
    用简体中文简短说明内容（不超过120字）：是什么东西、主要的人和物、画面里写着的重要文字。\
    如果是证件、银行卡、合同等含个人信息的，只说是什么类型，不要抄写姓名以外的号码（身份证号、手机号、卡号等）。\
    只输出说明本身，不要加前缀。
    """

    // MARK: @me

    /// 188 (B29): the owner's names in the words, @ as OCR reads it (full-width 「＠」 on WeChat, a space after it).
    static func atMe(_ text: String, names: [String]) -> Bool {
        let t = text.replacingOccurrences(of: "＠", with: "@").replacingOccurrences(of: "@ ", with: "@")
        return names.contains { !$0.isEmpty && t.contains("@" + $0) }
    }

    static func plain(_ s: String) -> String {
        s.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
    }
}

/// 188: each kind of message can be read or left alone (user 11-27: 「不是所有的都要看」; what is looked at when is the
/// user's to say later), and replies can quote or not. All on until told otherwise (test channel POST /media).
enum MediaSettings {
    static func key(_ k: XiaoLanMediaFind.Kind) -> String { "media_\(k.rawValue)_onV1" }
    static let quoteKey = "media_quote_onV1"

    static func on(_ k: XiaoLanMediaFind.Kind) -> Bool { UserDefaults.standard.object(forKey: key(k)) as? Bool ?? true }
    static func set(_ k: XiaoLanMediaFind.Kind, _ on: Bool) { UserDefaults.standard.set(on, forKey: key(k)) }
    static var quoteOn: Bool {
        get { UserDefaults.standard.object(forKey: quoteKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: quoteKey) }
    }
}
