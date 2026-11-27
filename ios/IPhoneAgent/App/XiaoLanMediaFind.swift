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
        case "视频号", "視頻號", "Channels": return .image  // 191 (N37): its card is a picture; clicked, its player
        case "文件", "檔案", "File": return .file
        case "链接", "鏈接", "連結", "Link": return .link
        default: return nil
        }
    }

    /// What a chat line or a preview is; nil: plain words (or a sticker, a red packet, …, which are not read).
    static func kind(of text: String) -> Kind? {
        if let k = tag(text) { return k }
        if url(in: text) != nil || shareText(text) { return .link }  // 191 (N37): a share with its address folded away
        if fileName(text) != nil { return .file }
        if voiceSeconds(text) != nil { return .voice }
        return nil
    }

    /// The first web address in the words: http(s)://…, or www.….
    static func url(in text: String) -> String? {
        var t = text.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "／", with: "/")
        // 192 (N38, the iPad read Douyin's 「https://v.douyin.com/fv63」 as 「.nttps://v.aouyin.com/fv63」, 11-27 16:43):
        // a misread scheme is still one
        if t.range(of: #"https?://"#, options: [.regularExpression, .caseInsensitive]) == nil {
            t = t.replacingOccurrences(of: #"[A-Za-z]{0,2}t{1,2}ps?://"#, with: "https://", options: .regularExpression)
        }
        guard let r = t.range(of: #"(https?://|www\.)[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        let u = String(t[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]'"))
        return u.count >= 10 ? u : nil
    }

    static let fileExtensions = ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "pdf", "txt", "csv", "zip", "rar", "7z",
                                 "md", "rtf", "pages", "numbers", "key", "wps", "et", "dps", "apk", "ipa", "mp3", "wav", "m4a"]

    /// A file's name in the words ("6原生家庭创伤治愈.docx", "伤治愈.docx13K", "治愈.docx 12KB未下载").
    /// 193 (N60, WeCom on the iPad 11-27 18:25: 「账户交易明细（1）.xls」 read 「账户交易明细（1）.xIs」, not known for a
    /// file: its 「21K」 became a message of its own, took a place among the newest, and the file's job opened another
    /// card): an extension misread the usual ways (I, 1 or | for l; 0 for o) is still one.
    static func fileName(_ text: String) -> String? {
        let t = Array(text.trimmingCharacters(in: .whitespaces))
        func extChar(_ c: Character) -> Bool { (c.isASCII && (c.isLetter || c.isNumber)) || c == "|" }
        for i in t.indices where t[i] == "." && i > 0 {
            var run: [Character] = []
            var j = i + 1
            while j < t.count, run.count < 8, extChar(t[j]) { run.append(t[j]); j += 1 }
            // the longest start of the run that is an extension, no letter right after it (a size may follow: 「.docx13K」)
            var length: Int?
            for n in stride(from: min(run.count, 7), through: 2, by: -1) {
                let next: Character? = i + 1 + n < t.count ? t[i + 1 + n] : nil
                if let next, next.isASCII, next.isLetter { continue }
                if fileExtension(String(run[..<n])) != nil { length = n; break }
            }
            guard let n = length else { continue }
            var s = i
            while s > 0, i - s < 60, !" \t/\\:：".contains(t[s - 1]) { s -= 1 }
            guard s < i else { continue }
            return String(t[s..<(i + 1 + n)])
        }
        return nil
    }

    /// An extension as read, as it is meant ("xIs" → "xls"); nil when it is no file's.
    static func fileExtension(_ read: String) -> String? {
        let e = read.lowercased()
        if fileExtensions.contains(e) { return e }
        let mapped = String(e.map { c -> Character in
            switch c { case "i", "1", "|": return "l"; case "0": return "o"; default: return c }
        })
        return fileExtensions.contains(mapped) ? mapped : nil
    }

    /// A file's name as compared: its extension as meant, no spaces, brackets or other signs, lowercased.
    static func fileKey(_ name: String) -> String {
        guard let dot = name.lastIndex(of: ".") else { return plain(name.lowercased()) }
        let ext = fileExtension(String(name[name.index(after: dot)...])) ?? String(name[name.index(after: dot)...]).lowercased()
        return plain(String(name[..<dot]).lowercased()) + "." + ext
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

    /// 192 (B30): who took a message back, from the chat's grey line (WeChat 「"主人蓝海乐" 撤回了一条消息」, WeCom
    /// 「主人蓝海乐撤回了一条消息」); nil for my own (「你撤回了一条消息 重新编辑」) and any other line.
    /// 193 (N62, iPad WeChat 11-27 18:27: 「「蓝海乐」已回收一則訊息」 — its own wording, traditional characters): that too.
    static let recallWords = ["撤回了一条消息", "撤回了一條消息", "撤回了一條訊息", "已回收一則訊息", "已回收一条消息", "已回收一條訊息",
                              "收回了一条消息", "收回了一則訊息", "已撤回一条消息", "已撤回一則訊息"]
    static func recaller(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let r = recallWords.lazy.compactMap({ t.range(of: $0) }).first else { return nil }
        let who = t[..<r.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " \"“”「」『』'‘’"))
        guard !who.isEmpty, who != "你", who != "我", who.count <= 30 else { return nil }
        return who
    }

    /// The line a recall is reported as.
    static func recallLine(_ who: String) -> String { "[撤回] \(who) 撤回了一条消息" }

    /// 192 (B28): a file card's size line alone — 「12KB未下载」, 「486KB 未下载」, 「15K」, 「1.2MB 已下载」.
    static func fileSizeLine(_ text: String) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        return t.range(of: #"^\d+(\.\d+)?[KMG]B?(未下载|已下载|已过期|未下載|已下載)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
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
    /// 193 (N60, Echo 192 18:28: the xls's name not known, the newest card — an old 「太上老君…docx」 — was opened): with
    /// a name to look for, only a card of that name (read loosely); none such, nothing is clicked.
    /// 193 (measured 11-27 19:55, WeCom after its quote was clicked: the card read 「账户交易明细（7）.xIs」 for (1), and the
    /// quote's own line 「｜账户交易明细（1）.xIs」 lower down looked like a card too): `exclude` leaves out lines on a quote
    /// box (onQuote); a name of digits misread is still the name, when nothing matches closer.
    static func fileCard(_ rows: [[Piece]], hint: String, exclude: ((CGRect) -> Bool)? = nil) -> CGPoint? {
        let all = pieces(rows).filter { cardText($0.text) && !(exclude?($0.box) ?? false) }
        guard let wanted = fileName(hint) else { return all.last.map { CGPoint(x: $0.box.midX, y: $0.box.midY) } }
        let want = fileKey(wanted)
        func digitless(_ s: String) -> String { s.filter { !$0.isNumber } }
        // the extensions alike, then the names before them (CI 45996849595: 「感.docx」 was taken for 「6原生家庭创伤治愈.docx」,
        // its few pairs of letters mostly the extension's)
        func parts(_ key: String) -> (base: String, ext: String) {
            guard let dot = key.lastIndex(of: ".") else { return (key, "") }
            return (String(key[..<dot]), String(key[key.index(after: dot)...]))
        }
        let w = parts(want)
        func alike(_ key: String) -> Bool {
            let k = parts(key)
            guard k.ext == w.ext, !k.base.isEmpty, !w.base.isEmpty else { return false }
            return w.base.hasSuffix(k.base) || k.base.hasSuffix(w.base) || likeness(w.base, k.base) >= 0.8
        }
        let named = all.compactMap { p in fileName(p.text).map { (piece: p, key: fileKey($0)) } }
        let pick = named.last { alike($0.key) }
            ?? named.last { digitless($0.key) == digitless(want) && $0.key.count == want.count }
        return pick.map { CGPoint(x: $0.piece.box.midX, y: $0.piece.box.midY) }
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
        guard !want.isEmpty else { return nil }
        let hit = pieces(rows, top: 0.1, bottom: 0.86).last { p in
            let t = plain(p.text)
            // 193 (N59): 「1」 is quoted too — by a piece that is that one character alone
            guard t.count >= 2 || want.count == 1 else { return false }
            if t == want { return true }
            return min(t.count, want.count) >= 4 && (want.hasPrefix(t) || t.hasPrefix(want) || want.contains(t))
        }
        return hit.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The quote bar shown after 「引用」: 「主人蓝海乐：这是什么」 (WeChat, under the field) or 「主人蓝海乐: 这不对」
    /// (WeCom, over it), in the window's bottom part.
    static func quoteBar(_ rows: [[Piece]], quote: String) -> CGPoint? {
        let want = plain(quote)
        guard !want.isEmpty else { return nil }  // 193 (N59): one character too
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

    /// 193 (N47, Echo 192 18:05: the long press landed on the voice note, but 「转文字」 was taken as the lowest piece of
    /// that word on the window — the small button beside the bubble — and clicked again, nothing came): a long-press
    /// menu is up when two of its other words show (引用, 删除, 收藏, 多选, 提醒, 背景播放, 连续朗读…); its band (heights).
    static let pressMenuWords = ["引用", "删除", "收藏", "多选", "提醒", "背景播放", "连续朗读", "转发", "复制", "拷贝", "听筒模式"]
    static func menuBand(_ rows: [[Piece]]) -> ClosedRange<Double>? {
        var ys: [Double] = []
        var words = Set<String>()
        for p in rows.joined() {
            let t = p.text.filter { !$0.isWhitespace }
            guard t.count <= 24 else { continue }
            let hit = pressMenuWords.filter { t.contains($0) }
            guard !hit.isEmpty else { continue }
            words.formUnion(hit)
            ys.append(Double(p.box.midY))
        }
        guard words.count >= 2, let lo = ys.min(), let hi = ys.max(), hi - lo < 0.2 else { return nil }
        return (lo - 0.04)...(hi + 0.04)
    }

    /// A menu's item within its band, never where `avoid` was (a button of the same word read before the press).
    static func menuItem(_ rows: [[Piece]], _ word: String, in band: ClosedRange<Double>, avoid: CGPoint? = nil) -> CGPoint? {
        let inBand = rows.map { row in row.filter { band.contains(Double($0.box.midY)) } }
        guard let at = menuItem(inBand, word) else { return nil }
        if let avoid, abs(Double(at.x - avoid.x)) < 0.03, abs(Double(at.y - avoid.y)) < 0.015 {
            let rest = inBand.map { row in row.filter { abs(Double($0.box.midX - avoid.x)) >= 0.03 || abs(Double($0.box.midY - avoid.y)) >= 0.015 } }
            return menuItem(rest, word)
        }
        return at
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
    /// 190 (N29): with `link` (the address Echo opened), its domain in the address bar counts too (「baidu.com」 for
    /// 「www.baidu.com」, a letter misread or 「m.」 before it allowed).
    static func safariShown(_ rows: [[Piece]], link: String? = nil) -> Bool {
        // a domain as compared: no scheme, no 「www.」, nothing from its first 「/」, letters and digits only
        func host(_ s: String) -> String {
            var t = s.lowercased()
            for head in ["https://", "http://", "www."] where t.hasPrefix(head) { t.removeFirst(head.count) }
            return String(t.prefix { $0 != "/" }).filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        let key = link.flatMap { url(in: $0) }.map(host) ?? ""
        return rows.joined().contains { p in
            guard Double(p.box.midY) < 0.08 else { return false }
            if p.text.lowercased().contains("safari") { return true }
            let seen = host(p.text.trimmingCharacters(in: .whitespaces))
            guard key.count >= 4, seen.count >= 4 else { return false }
            return seen.contains(key) || key.hasSuffix(seen) || sameLink(key, seen)
        }
    }

    /// 190 (N29): a copy in a long-press menu: the bubble's 「复制」, a link's own 「复制链接」/「复制网址」, or iOS's 「拷贝」.
    static func copyItem(_ rows: [[Piece]]) -> CGPoint? {
        button(rows, "复制链接") ?? button(rows, "复制网址") ?? menuItem(rows, "复制") ?? menuItem(rows, "拷贝")
    }

    /// 190 (N29): the address as read, opened by Echo in Safari (x-safari-, whatever the default browser): only a place
    /// to start, the copied address is pasted over it. 「www.…」 gets https://.
    static func safariURL(_ address: String) -> URL? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty, !a.contains(" ") else { return nil }
        let full = a.lowercased().hasPrefix("http://") || a.lowercased().hasPrefix("https://") ? a : "https://" + a
        return URL(string: "x-safari-" + full)
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
            let label = channelsAuthor(pieces, in: b).map { "[视频号] \($0)" } ?? "[图片]"  // 192 (N43)
            out.append(WatchOCR.Piece(text: label, box: CGRect(x: Double(b.minX), y: Double(b.minY), width: 0.08, height: 0.02), kind: .theirs))
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
        func consider(_ start: Double, cut: Bool) {
            guard let r = block(px, from: start, bottom: bottom), r.width >= 0.12, r.height >= 0.06,
                  !cut || (Double(r.minX) < 0.25 && Double(r.maxX) < 0.78),
                  isPicture(px, r, pieces: pieces), !blocks.contains(where: { $0.intersects(r) }) else { return }
            blocks.append(r)
        }
        // 192 (N43, Echo 191 11-27 15:45: the 视频号 card at the window's top, its avatar scrolled off, was never found):
        // a message cut by the top is looked at too — someone else's (left, short of the right side where mine end)
        consider(top, cut: true)
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
            consider(start, cut: false)
        }
        return blocks.sorted { $0.minY < $1.minY }
    }

    /// A block of picture, not a bubble of words: under half of it a bubble's plain colour; or (192, N48, Echo 191
    /// 11-27 16:23: a photo of a white form — a portrait, a barcode, small print — taken for a white bubble, so the
    /// chat itself went to the model) mostly white and tall, with next to no chat-sized words in it (a link's card, white
    /// too, has its title in them).
    static func isPicture(_ px: WatchOCR.Pixels, _ r: CGRect, pieces: [WatchOCR.Piece]) -> Bool {
        if bubbleShare(px, r) < 0.5 { return true }
        return Double(r.height) >= 0.1 && chatWordsShare(pieces, in: r) < 0.1
    }

    /// The share of a block's height under words of a chat's size (0.013 of the window tall or more; a page's print in
    /// a photo is half that): a bubble of words is most of it.
    static func chatWordsShare(_ pieces: [WatchOCR.Piece], in r: CGRect) -> Double {
        let spans = pieces.filter { r.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) && Double($0.box.height) >= 0.013 }
            .map { (Double($0.box.minY), Double($0.box.maxY)) }.sorted { $0.0 < $1.0 }
        var covered = 0.0, end = Double(r.minY)
        for (a, b) in spans {
            let s = max(a, end)
            if b > s { covered += b - s; end = b }
        }
        return r.height > 0 ? covered / Double(r.height) : 0
    }

    /// 192 (N43, a 视频号 card, 11-27 15:45: a photo, its author over its bottom left — 「凶露露Iulu0517」, the icon read as
    /// a sign — nothing else written on it): the author, a name with a handle's letters or digits; else nil.
    static func channelsAuthor(_ pieces: [WatchOCR.Piece], in block: CGRect) -> String? {
        let inside = pieces.filter { block.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) && !plain($0.text).isEmpty }
        guard (1...2).contains(inside.count), let p = inside.max(by: { $0.box.midY < $1.box.midY }),
              Double(block.maxY) - Double(p.box.midY) < 0.05, Double(p.box.minX) - Double(block.minX) < 0.06 else { return nil }
        let name = String(p.text.drop(while: { !($0.isLetter || $0.isNumber) }))
        let n = plain(name)
        guard (3...24).contains(n.count), n.contains(where: { $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return name
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
        // 192 (N48/N43, Echo 191 11-27 16:23: on the iPad's WeChat window the avatar ends right at 0.14, so the block
        // began on its edge, 0 wide, and no picture was ever found): past the avatar, then the gap, to the message
        var x = 0.06
        while x < 0.3, !isBackground(px.rgb(x, y)) { x += 0.005 }
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

    /// 192 (N47, Echo 191 11-27 16:21: two notes, only the older had 「转文字」 beside it, and the newer's job clicked
    /// it): this note's own 「转文字」, right of its bubble at its height; nil when it has none.
    static func voiceButton(_ rows: [[Piece]], beside bubble: CGPoint) -> CGPoint? {
        let y = Double(bubble.y)
        return voiceButtons(rows).filter { abs(Double($0.y) - y) < 0.02 && Double($0.x) > Double(bubble.x) }
            .min { abs(Double($0.y) - y) < abs(Double($1.y) - y) }
    }

    static func videoLabels(_ rows: [[Piece]]) -> [Piece] {
        pieces(rows).filter { p in
            guard let s = clockSeconds(p.text), s > 0 else { return false }
            return abs(Double(p.box.midX) - 0.5) > 0.06 && Double(p.box.height) < 0.016
        }
    }

    /// A line of a link: its address, or (191, N37) a share's own words with no address shown (Douyin's folded share).
    static func linkSpots(_ rows: [[Piece]]) -> [Piece] { pieces(rows).filter { url(in: $0.text) != nil || shareText($0.text) } }

    // MARK: 191 shares (N37, N38)

    /// 191 (N37, Echo 190 11-27 首爾 15:06: Douyin's and Kuaishou's shares came folded, 「…更多」, Douyin's address not
    /// shown at all, so neither was a link): a share's own words, its address shown or not.
    static let shareMarks = ["复制打开抖音", "复制打开快手", "打开【快手】", "去【小红书】", "打开【小红书】", "复制打开小红书",
                             "v.douyin.com", "kuaishou.com", "xhslink", "xiaohongshu.com"]
    static func shareText(_ text: String) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        return shareMarks.contains { t.contains($0) }
    }

    /// WeChat's fold: a long message cut, 「…更多」 at its end (OCR: 「聊赚钱.更多」, 「LENRb...更多」).
    static func folded(_ text: String) -> Bool { text.filter { !$0.isWhitespace }.hasSuffix("更多") }

    /// The lines of the bubble whose line `p` is: `p` and those just under it (a line's gap, measured 0.022 apart; the
    /// next bubble 0.05 lower).
    static func bubbleLines(_ rows: [[Piece]], from p: Piece) -> [Piece] {
        var lines = [p]
        for q in pieces(rows) where Double(q.box.minY) > Double(lines.last!.box.minY) + 0.005 {
            guard Double(q.box.minY) - Double(lines.last!.box.maxY) < 0.03,
                  abs(Double(q.box.minX) - Double(p.box.minX)) < 0.12 else { continue }
            lines.append(q)
        }
        return lines
    }

    /// The 「更多」 of a folded message whose line `p` is: the middle of the last two characters of the bubble's line
    /// that ends with it.
    static func moreSpot(_ rows: [[Piece]], from p: Piece) -> CGPoint? {
        guard let q = bubbleLines(rows, from: p).first(where: { folded($0.text) }) else { return nil }
        let n = Double(max(q.text.count, 2))
        return CGPoint(x: Double(q.box.minX) + Double(q.box.width) * (n - 1) / n, y: Double(q.box.midY))
    }

    /// 191 (N38, Echo 190 11-27: the report said Kuaishou's address, Xiaohongshu's line was clicked): the line of this
    /// job's link — its address read alike (or the start of it, cut by a fold), else its words' start — else the rank's.
    /// 192 (N38 still, N49): the line of this job's link message, chosen among messages, not lines (a share is two to
    /// four lines, each looking like a link, so a rank counted in lines landed on another share: Douyin's job clicked
    /// Kuaishou's 「打开【快手】」, 11-27 15:38; WeCom's Xiaohongshu job clicked the line under the address, 16:24):
    /// its address read alike, else its words most alike, else the rank's message. The line given is the one holding
    /// the address's own characters (an address wrapped after 「https://」 is on the next line), else the message's first.
    static func linkLine(_ rows: [[Piece]], text: String, rank: Int) -> Piece? {
        let bubbles = linkBubbles(rows)
        if let key = linkKey(text), let b = bubbles.last(where: { b in
            guard let k = b.url.flatMap(linkKey) else { return false }
            return sameLink(k, key) || (k.count >= 8 && key.hasPrefix(k)) || (key.count >= 8 && k.hasPrefix(key))
        }) { return b.line }
        let want = plain(text.replacingOccurrences(of: "[链接]", with: ""))
        if want.count >= 4 {
            let scored = bubbles.map { ($0, likeness(want, plain($0.words))) }
            if let top = scored.map({ $0.1 }).max(), top >= 0.5, let b = scored.last(where: { $0.1 == top }) { return b.0.line }
        }
        return pick(bubbles, rank: rank)?.line
    }

    /// 192: a link message on the window: its lines, its words (lines joined, ends trimmed: an address wrapped across
    /// them is whole again), its address, and the line holding the address's own characters (else its first).
    struct LinkBubble { let lines: [Piece]; let words: String; let url: String?; let line: Piece }

    static func linkBubbles(_ rows: [[Piece]]) -> [LinkBubble] {
        let all = pieces(rows)
        var taken = Set<Int>()
        var out: [LinkBubble] = []
        for (i, p) in all.enumerated() where !taken.contains(i) {
            let lines = bubbleLines(rows, from: p)
            for q in lines { if let j = all.firstIndex(where: { $0.box == q.box && $0.text == q.text }) { taken.insert(j) } }
            let words = lines.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined()
            let u = url(in: words)
            guard u != nil || lines.contains(where: { shareText($0.text) || url(in: $0.text) != nil }) else { continue }
            // a share with no address: its own words' line, never a group's name line over the bubble
            let line = addressHolder(lines) ?? lines.first(where: { shareText($0.text) }) ?? lines[0]
            out.append(LinkBubble(lines: lines, words: words, url: u, line: line))
        }
        return out
    }

    /// Of a message's lines, the one the address's own characters are on: a line with a whole address; the line after
    /// one ending in a cut 「https://」 or 「www.」 (WeCom, 11-27: 「粉粉嫩嫩的，阳光也偏爱～ https://」 /
    /// 「xhslink.cn/o/gLh9ko7VJj 把这段复」); a line starting with a host and path.
    static func addressHolder(_ lines: [Piece]) -> Piece? {
        if let p = lines.first(where: { url(in: $0.text) != nil }) { return p }
        for (i, p) in lines.enumerated() where i + 1 < lines.count {
            let t = p.text.trimmingCharacters(in: .whitespaces).lowercased()
            if t.hasSuffix("://") || t.hasSuffix("http") || t.hasSuffix("https") || t.hasSuffix("https:") || t.hasSuffix("www.") {
                return lines[i + 1]
            }
        }
        return lines.first { hostRun($0.text) != nil }
    }

    /// The run of an address's characters on a line: from 「http」/「www.」, else a host and path at the line's start
    /// (「xhslink.cn/o/gLh9ko7VJj 把这段复」); in characters.
    static func hostRun(_ text: String) -> Range<Int>? {
        let chars = Array(text)
        let isAddress: (Character) -> Bool = { c in
            c.isASCII && (c.isLetter || c.isNumber || "-._~:/?#[]@!$&'()*+,;=%".contains(c))
        }
        let lower = text.lowercased()
        var start: Int?
        if let r = lower.range(of: "http") ?? lower.range(of: "www.") {
            start = lower.distance(from: lower.startIndex, to: r.lowerBound)
        } else if let first = chars.firstIndex(where: { !$0.isWhitespace }), isAddress(chars[first]) {
            start = first
        }
        guard let s = start else { return nil }
        var e = s
        while e < chars.count, isAddress(chars[e]) { e += 1 }
        let run = String(chars[s..<e])
        guard e - s >= 6, run.contains("."), run.contains("/") || run.lowercased().hasPrefix("http") || run.lowercased().hasPrefix("www.") else {
            return nil
        }
        return s..<e
    }

    /// Where the `at`th character of a line sits across it, wide (Chinese) characters counted whole and narrow ones
    /// (letters, digits, marks) a little over half (an address is half the width its count says beside Chinese).
    static func characterX(_ p: Piece, at: Double) -> Double {
        let chars = Array(p.text)
        guard !chars.isEmpty else { return Double(p.box.midX) }
        let widths = chars.map { CandidatePicker.isWide($0) ? 1.0 : 0.55 }
        let total = widths.reduce(0, +)
        let whole = min(max(0, Int(at)), chars.count)
        var before = widths[0..<whole].reduce(0, +)
        if whole < chars.count { before += widths[whole] * (at - Double(whole)) }
        return Double(p.box.minX) + Double(p.box.width) * min(before / total, 0.97)
    }

    /// Where an address starts on its line (a full text's 「最... https://v.douyin.com/」): its 「h」's place, a little in;
    /// 192: also a wrapped address's rest at a line's start (「xhslink.cn/o/…」).
    static func addressStart(_ p: Piece) -> CGPoint {
        guard let r = hostRun(p.text) else { return CGPoint(x: Double(p.box.midX), y: Double(p.box.midY)) }
        return CGPoint(x: characterX(p, at: Double(r.lowerBound) + 2), y: Double(p.box.midY))
    }

    /// 192 (N49): the middle of an address's characters on its line (the first click), else the line's middle.
    static func addressMiddle(_ p: Piece) -> CGPoint {
        guard let r = hostRun(p.text) else { return CGPoint(x: Double(p.box.midX), y: Double(p.box.midY)) }
        return CGPoint(x: characterX(p, at: Double(r.lowerBound + r.upperBound) / 2), y: Double(p.box.midY))
    }

    /// How alike two lines' words are (0–1): the share of the shorter's character pairs (its first 40 characters)
    /// found in the other; OCR's misreads (「1.07」 read 「107」) cost a pair or two, not the match.
    static func likeness(_ a: String, _ b: String) -> Double {
        func pairs(_ s: String) -> [String] {
            let c = Array(s.prefix(40))
            return c.count < 2 ? [s] : (0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) }
        }
        let (x, y) = (pairs(a), Set(pairs(b)))
        let (short, long) = x.count <= y.count ? (x, y) : (pairs(b), Set(x))
        guard !short.isEmpty else { return 0 }
        return Double(short.filter { long.contains($0) }.count) / Double(short.count)
    }

    /// 191 (measured 11-27 15:12: Douyin's page in WeChat 「抱歉出错了 / 请尝试在抖音内观看 / 打开抖音」): a page that only
    /// sends you to the app.
    static func appOnlyPage(_ rows: [[Piece]]) -> Bool {
        rows.joined().contains { p in
            let t = p.text.filter { !$0.isWhitespace }
            // 192 (N39, Echo 191 15:36: Kuaishou's playable page had a 「打开快手」 button and went to ··· for it): only an
            // error page counts, never an app's button
            return t.contains("抱歉出错") || t.contains("请尝试在") || t.contains("内观看")
        }
    }

    /// 192 (N41, measured 11-27 15:37; user: 「可能離開微信打開第三方這種啊，你都要點取消…不點取消的話，你返回不了」):
    /// WeChat's 「可能离开微信，打开第三方应用」 sheet (取消 / 继续), raised by a page's video at its end or by its app
    /// button. Its 取消, where it shows.
    static func leaveSheet(_ rows: [[Piece]]) -> CGPoint? {
        let all = Array(rows.joined())
        guard all.contains(where: { leaveWords($0.text) }) else { return nil }
        return button(rows, "取消")
    }
    /// 193 (N56, WeCom 11-27 18:30: 「即将离开，打开"小红书"」 (取消 / 允许) not known, the video waited out its 180 s): WeCom's
    /// wording too.
    static func leaveWords(_ text: String) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        return t.contains("离开微信") || t.contains("打开第三方应用") || t.contains("第三方应用")
            || t.contains("即将离开") || t.contains("即將離開") || t.contains("离开企业微信") || t.contains("離開企業微信")
    }

    /// 192 (measured 11-27 15:45: Douyin's video in WeChat ran its 3:01 to 「去抖音重播」; Kuaishou's and Xiaohongshu's end
    /// on the 「离开微信」 sheet): a line that says the video is over.
    static func videoOver(_ line: String) -> Bool {
        let t = line.filter { !$0.isWhitespace }
        return t.contains("重播") || leaveWords(t)
    }

    /// 191: 「用默认浏览器打开」 in a page's ··· menu (measured 11-27: the first row's last item, its label cut by the
    /// window's edge, read 「用默认」 / 「用默认浏览器打开」).
    static func defaultBrowserItem(_ rows: [[Piece]]) -> Piece? {
        rows.joined().first { p in
            let t = p.text.filter { !$0.isWhitespace }
            return t.hasPrefix("用默认") || t.contains("默认浏览器") || t.contains("浏览器打开")
        }
    }

    /// 191 (measured 11-27 15:11: Xiaohongshu's note in WeChat, its video paused under a faint ▶, the author's 「关注」,
    /// 「发弹幕」, 「App内打开」): a page with a video to start by a click on its middle; where (the window's share).
    static func pageVideoSpot(_ rows: [[Piece]]) -> CGPoint? {
        let all = Array(rows.joined())
        // 192 (N39, measured 11-27 15:36–15:41: Kuaishou's 「打开快手，看更多精彩视频」 「分享」, Douyin's 「打开抖音看精彩视频」
        // 「打开App」 「展开」): any of these pages, its video started by a click between its top bar and its first mark
        let marks = all.filter { p in
            let t = p.text.filter { !$0.isWhitespace }
            return t == "关注" || t == "+关注" || t == "分享" || t == "展开" || t.contains("发弹幕") || t.contains("App内打开")
                || t.contains("打开App") || t.contains("看更多精彩视频") || t.contains("看精彩视频") || t == "打开快手"
                || t.contains("xiaohongshu") || t.contains("kuaishou") || t.contains("chenzhongtech") || t.contains("douyin")
        }
        guard marks.count >= 2 else { return nil }
        let below = marks.map { Double($0.box.minY) }.filter { $0 > 0.3 }.min() ?? 0.6
        return CGPoint(x: 0.45, y: min(0.6, max(0.25, (0.15 + below) / 2)))
    }

    /// 191 (measured 11-27 15:18: a 视频号 card in the chat, a picture with a ▶ and its author at the bottom, 「♥露露lulu0517」;
    /// clicked, its player over the window, playing, the author again at its bottom): the author's name on a block.
    static func cardAuthor(_ rows: [[Piece]], in block: CGRect) -> String? {
        let inside = rows.joined().filter { block.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
        guard let p = inside.max(by: { $0.box.midY < $1.box.midY }), Double(p.box.midY) > Double(block.midY) else { return nil }
        let name = String(p.text.drop(while: { !($0.isLetter || $0.isNumber) }))
        return plain(name).count >= 3 ? name : nil
    }

    /// The same author at the bottom of what opened: a 视频号 player (its last six letters, the icon before it read as
    /// anything).
    static func channelsPlayer(_ rows: [[Piece]], author: String) -> Bool {
        let want = String(plain(author).suffix(6))
        guard want.count >= 3 else { return false }
        return rows.joined().contains { Double($0.box.midY) > 0.7 && plain($0.text).contains(want) }
    }

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
    /// 191: a video on a page or a 视频号 player, its length not shown: watched and listened to this long (s).
    static let pageVideoMost = 30

    /// 191: a model's answer that it could not see (then the other model is asked): too short, or its own words of
    /// doubt.
    static let unsureMarks = ["看不清", "看不出", "无法看清", "无法识别", "无法判断", "无法确定", "不能确定", "不确定", "不清楚",
                              "模糊不清", "抱歉"]
    static func unsure(_ answer: String) -> Bool {
        let t = answer.filter { !$0.isWhitespace }
        return t.count < 8 || unsureMarks.contains { t.contains($0) }
    }

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

    /// 189 (N30, Echo 189, 11-27 12:40 首爾: WeCom's voice note from 蓝海乐 was already turned into words — 「有优惠吗？」 and
    /// 「转換完成」 under it — so its menu had no 转文字, and it was reported 「没能打开看」): the words under the note (the
    /// `rank`-th newest of its length) up to that 「…完成」 mark; nil when there is no such mark.
    static func convertedWords(_ pieces: [Piece], seconds: Int?, rank: Int = 0, px: WatchOCR.Pixels? = nil) -> String? {
        guard let seconds else { return nil }
        let notes = pieces.filter { voiceSeconds($0.text) == seconds }.sorted { $0.box.midY > $1.box.midY }
        guard !notes.isEmpty else { return nil }
        let note = notes[min(rank, notes.count - 1)]
        let bottom = Double(note.box.maxY)
        let under = pieces.filter { Double($0.box.midY) > bottom && Double($0.box.midY) <= bottom + 0.2 }
            .sorted { $0.box.midY < $1.box.midY }
        func done(_ t: String) -> Bool {
            let p = t.filter { !$0.isWhitespace }
            return p.count <= 6 && p.contains("完成") && (p.contains("转") || p.contains("轉"))
        }
        guard let end = under.firstIndex(where: { done($0.text) }), end > 0 else {
            // 193 (N47, Echo 192 18:05: WeChat's note turned into words before, its words not known, its menu tried again):
            // WeChat puts them in a box of their own under the note with no mark — the lines right under it, starting at
            // its left, with no avatar beside them (the next message has one), never a bubble of mine
            guard let px else { return nil }
            var words: [String] = []
            var last = bottom
            for p in under {
                if Double(p.box.minY) - last > 0.035 { break }
                // on a white box (the chat's grey under the note — 「「蓝海乐」已回收一則訊息」, a time — is none)
                guard abs(Double(p.box.minX) - Double(note.box.minX)) < 0.06, !avatarAt(px, Double(p.box.midY)),
                      WatchOCR.kind(p.box, px) == .theirs, recaller(p.text) == nil, voiceSeconds(p.text) == nil,
                      !p.text.contains("转文字") else { break }
                words.append(p.text)
                last = Double(p.box.maxY)
            }
            let w = words.joined()
            return w.isEmpty ? nil : w
        }
        let words = under[..<end].map(\.text).joined()
        return words.isEmpty ? nil : words
    }

    /// 189 (N32): a link's address as compared: lowercased, no scheme, no 「www.」, letters and digits only; nil when
    /// the line holds no address.
    static func linkKey(_ line: String) -> String? {
        guard var u = url(in: line)?.lowercased() else { return nil }
        for head in ["https://", "http://", "www."] where u.hasPrefix(head) { u.removeFirst(head.count) }
        if u.hasPrefix("www.") { u.removeFirst(4) }
        let key = u.filter { $0.isLetter || $0.isNumber }
        return key.count >= 4 ? key : nil
    }

    /// Two link keys alike but for a misread letter (as the iPad reads 「baidu」: 「baiau」, 「bardu」), two in a long one
    /// (16+ letters); a short link's code differing by more is another link.
    static func sameLink(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        let most = min(x.count, y.count) >= 16 ? 2 : 1
        guard abs(x.count - y.count) <= most, !x.isEmpty, !y.isEmpty else { return a == b }
        var row = Array(0...y.count)
        for i in 1...x.count {
            var next = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                next[j] = min(row[j] + 1, next[j - 1] + 1, row[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            row = next
        }
        return row[y.count] <= most
    }

    /// A voice note's length in its line as reported (「[语音] 9"」 → 9).
    static func noteSeconds(_ line: String) -> Int? {
        guard let r = line.range(of: #"(\d{1,2})["″”“'’]"#, options: .regularExpression) else { return nil }
        return Int(line[r].filter(\.isNumber))
    }

    // MARK: 192 a page wider than its window (N50)

    /// 192 (N50, Echo 191 11-27 16:26: WeCom's preview of a .docx in the half-screen window is wider than it, every line
    /// cut at the window's right edge, 「…大赤天中、黄」; dragged left, the rest showed, 「黄金殿内，召」): three lines or
    /// more reaching the right edge.
    static func cutOnRight(_ rows: [[Piece]], from top: Double = 0.08) -> Bool {
        pieces(rows, top: top, bottom: 0.97).filter { Double($0.box.maxX) >= 0.96 && $0.text.count >= 4 }.count >= 3
    }

    /// The lines of a wide page read in parts (each dragged further left), each part's line joined to the line at its
    /// height so far by the characters they share; a line only in a later part is added at its height.
    static func joinWide(_ parts: [[Piece]]) -> [String] {
        var lines: [(y: Double, text: String)] = []
        for part in parts {
            for p in part.sorted(by: { $0.box.midY < $1.box.midY }) {
                let y = Double(p.box.midY)
                if let i = lines.indices.min(by: { abs(lines[$0].y - y) < abs(lines[$1].y - y) }), abs(lines[i].y - y) < 0.012 {
                    lines[i].text = overlapJoin(lines[i].text, p.text)
                } else {
                    lines.append((y: y, text: p.text))
                    lines.sort { $0.y < $1.y }
                }
            }
        }
        return lines.map { $0.text }
    }

    /// Two reads of one line, the second further right: joined where the first's end is the second's start (OCR may
    /// misread a character there, so the second's first four are looked for near the first's end); the second alone
    /// when it holds the first; the first when the second adds nothing.
    static func overlapJoin(_ a: String, _ b: String) -> String {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty else { return b }
        guard !y.isEmpty else { return a }
        if b.contains(a) { return b }
        if a.contains(b) { return a }
        for k in stride(from: min(x.count, y.count), through: 2, by: -1) where Array(x.suffix(k)) == Array(y.prefix(k)) {
            return a + String(y.dropFirst(k))
        }
        // 193 (N50b, Echo 192 18:31: one passage read 「九天财库禄库君、九享籍掌算君」 in one part and 「…九亨籍掌算君」 in the
        // next: no seam found, the passage came twice): the seam with a misread character in it (two in ten or more)
        for k in stride(from: min(x.count, y.count), through: 5, by: -1) {
            let differ = zip(x.suffix(k), y.prefix(k)).filter { $0 != $1 }.count
            if differ <= (k >= 10 ? 2 : 1) { return a + String(y.dropFirst(k)) }
        }
        let head = Array(y.prefix(6))
        if head.count >= 4 {
            for start in stride(from: x.count - head.count, through: max(0, x.count - 40), by: -1) where start >= 0 {
                let differ = zip(x[start..<(start + head.count)], head).filter { $0 != $1 }.count
                if differ <= (head.count >= 6 ? 1 : 0) { return String(x[..<start]) + b }
            }
        }
        return a + b
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
    // MARK: 192 a question quoting a message (N45)

    /// 192 (N45; user 11-27: 「我引用這個抖音鏈接：『這裡面是什麼？』…你就會點開它去看…然後你再引用我這句話回我」;
    /// measured 15:58: under 「这里面讲了什么」 a grey box 「蓝海乐：9.20复制打开抖音，看 / 看【爱折腾的JOE的作品】赢了…」, or
    /// 「蓝海乐：📄中国经济今明两 / 年深度研判，pdf」 with a PDF mark at its right): the quote under the line of others whose
    /// words are `line` — its words without 「name：」, and its first line's middle (a click there opens what it quotes:
    /// a link's message to its full text, a file to its page). `isBox`: off a bubble (the quote's grey).
    /// `rank`: which of the lines with these words, from the bottom (two 「这里面讲了什么」 asked about two messages).
    static func quoteUnder(_ rows: [[Piece]], line: String, rank: Int = 0, isBox: (CGRect) -> Bool) -> (text: String, at: CGPoint)? {
        let ps = pieces(rows)
        let want = plain(line)
        guard want.count >= 2, let top = pick(ps.filter({ p in
            let t = plain(p.text)
            return t.count >= 2 && !isBox(p.box) && (want.hasPrefix(t) || t.hasPrefix(want))
        }), rank: rank) else { return nil }
        var bottom = Double(top.box.maxY)
        var head: Piece?
        for p in ps where Double(p.box.minY) > Double(top.box.minY) + 0.005 && abs(Double(p.box.minX) - Double(top.box.minX)) < 0.06 {
            if Double(p.box.minY) - bottom > 0.05 { break }
            if isBox(p.box) {
                if quoteHead(p.text) { head = p }
                break
            }
            bottom = Double(p.box.maxY)  // another line of the bubble
        }
        guard let head else { return quoteAbove(ps, line: top, isBox: isBox) }
        var text = head.text, last = head
        for p in ps where Double(p.box.minY) > Double(head.box.maxY) - 0.004 {
            if Double(p.box.minY) - Double(last.box.maxY) > 0.012 { break }
            guard abs(Double(p.box.minX) - Double(head.box.minX)) < 0.04, isBox(p.box) else { continue }  // 「PDF」 beside it
            text += p.text
            last = p
        }
        guard let colon = text.firstIndex(where: { $0 == "：" || $0 == ":" }) else { return nil }
        let body = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : (body, CGPoint(x: Double(head.box.midX), y: Double(head.box.midY)))
    }

    /// 193 (N60, WeCom on the iPad 11-27 18:25: 「这里面是什么东西」 quoting 「账户交易明细(1).xls」 — WeCom puts the quote in
    /// the question's own bubble, a grey box over its words: 「蓝海乐：」 / 「Ⓧ 账户交易明细（1）.xIs」 / 「这里面是什么东西」): the
    /// quote over the line, the grey box's lines up to its 「name：」, and where to click it (its line under the name).
    static func quoteAbove(_ ps: [Piece], line top: Piece, isBox: (CGRect) -> Bool) -> (text: String, at: CGPoint)? {
        let above = ps.filter { p in
            Double(p.box.maxY) <= Double(top.box.minY) + 0.004 && Double(top.box.minY) - Double(p.box.minY) < 0.12
                && Double(p.box.minX) >= Double(top.box.minX) - 0.015 && Double(p.box.minX) - Double(top.box.minX) < 0.09
        }.sorted { $0.box.midY > $1.box.midY }
        var box: [Piece] = []
        var lowest = Double(top.box.minY)
        for p in above {
            if lowest - Double(p.box.maxY) > 0.03 { break }
            guard isBox(p.box) else { break }
            box.insert(p, at: 0)
            lowest = Double(p.box.minY)
            if quoteHead(p.text) { break }
        }
        guard let head = box.first, quoteHead(head.text) else { return nil }
        let text = box.map(\.text).joined()
        guard let colon = text.firstIndex(where: { $0 == "：" || $0 == ":" }) else { return nil }
        let body = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        let click = box.count > 1 ? box[1] : head
        return body.isEmpty ? nil : (body, CGPoint(x: Double(click.box.midX), y: Double(click.box.midY)))
    }

    /// 193 (measured on the iPad 11-27 19:54, normal light: a bubble of theirs is white, 254–255, on WeChat and WeCom
    /// alike; WeCom's quote box in the question's bubble is 248, WeChat's quote box under it 224 — WatchOCR.kind took
    /// WeCom's 248 for a bubble, 247 and up, so its quotes were never found): a line sits on a quote's box (or on the
    /// chat's grey), not on a bubble — what is just left of its first letter is a neutral grey, not 252+ white, and
    /// no bubble of mine.
    static func onQuote(_ box: CGRect, _ px: WatchOCR.Pixels) -> Bool {
        for dx in [0.006, 0.010, 0.004] {
            let c = px.rgb(Double(box.minX) - dx, Double(box.midY))
            if WatchOCR.kind(of: c) == .mine { return false }
            let lo = min(c.0, c.1, c.2), hi = max(c.0, c.1, c.2)
            guard hi - lo <= 8 else { continue }
            if lo >= 252 { return false }
            if lo >= 215 { return true }
        }
        return false
    }

    /// 193 (measured 11-27 19:55): WeCom's quote clicked takes the chat to the message it quotes and shows
    /// 「回到引用位置」 at its right (read 「♥回到引用位置」); where to click to go back down.
    static func backToQuote(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { $0.text.filter { !$0.isWhitespace }.contains("回到引用位置") }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// 193 (N54): a line's words on the window — all of it, or a piece of it (or it of a piece) four characters or more.
    static func shows(_ rows: [[Piece]], _ line: String) -> Bool {
        let want = plain(line)
        guard !want.isEmpty else { return true }
        return rows.joined().contains { p in
            let t = plain(p.text)
            guard !t.isEmpty else { return false }
            return t == want || (min(t.count, want.count) >= 4 && (want.contains(t) || t.contains(want)))
        }
    }

    /// The newest line read with words of its own (not a 「[图片]」 made for a message with none), for `shows`.
    static func newestWords(_ lines: [String]) -> String {
        lines.last { !$0.hasPrefix("[") && plain($0).count >= 2 } ?? ""
    }

    /// A quote's first line: 「name：…」, the name 1–20 long.
    static func quoteHead(_ text: String) -> Bool {
        guard let i = text.firstIndex(where: { $0 == "：" || $0 == ":" }) else { return false }
        return (1...20).contains(text.distance(from: text.startIndex, to: i)) && !text.hasPrefix("http")
    }

    /// What a quote quotes: a kind of message read by opening it; a file's name read loosely (「研判，pdf」, 「研判 .pdf」).
    static func quotedKind(_ text: String) -> Kind? {
        if let k = kind(of: text) { return k }
        let t = text.lowercased().filter { !$0.isWhitespace }
        for ext in fileExtensions where t.count > ext.count + 1 && t.hasSuffix(ext) {
            if let c = t.dropLast(ext.count).last, ".，,。".contains(c) { return .file }
        }
        return nil
    }

    /// 192 (user 11-27: 「別人發了一個…我一時半會兒沒問你…過一段時間我會問你，你也能知道」): what a message is known by
    /// in a chat's memory of what was seen — its address, its file's name, else its first words.
    static func memoryKey(_ text: String) -> String {
        if let k = linkKey(text) { return k }
        if let f = fileName(text) { return plain(f.lowercased()) }
        return String(plain(text.lowercased()).prefix(12))
    }
    static func sameMemory(_ a: String, _ b: String) -> Bool {
        a == b || (a.count >= 8 && b.count >= 8 && (a.hasPrefix(b) || b.hasPrefix(a) || sameLink(a, b)))
    }

    /// The question reported with what it quotes and what was seen in it (or why not).
    static func quotedReport(question: String, quoted: String, kind: Kind, seen: String?, failed: String?) -> String {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = "引用的\(label(kind))：\(quoted)"
        if let seen, !seen.isEmpty { return "\(q)\n（\(what)；小蓝看了：\(seen)）" }
        return "\(q)\n（\(what)；小蓝没能打开看：\(failed ?? "原因不明")）"
    }

    static func report(_ line: String, kind: Kind, seen: String?, failed: String?) -> String {
        let head = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let mark = "[\(label(kind))]"
        let first = tag(head) == kind ? head : (head.isEmpty ? mark : "\(mark) \(head)")
        if let seen, !seen.isEmpty { return "\(first)\n\(seen)" }
        return "\(first)\n（小蓝没能打开看：\(failed ?? "原因不明")）"
    }

    /// 193 (N53, Echo 192 18:08: a photo of an ID card reported with its holder's name and visa details, and every word
    /// read off it sent along; the owner's bank statement .xls tried too): an ID, a bank card, a statement and the like —
    /// said what it is; the words read off a picture of one are not sent, and runs of digits are masked.
    static let sensitiveWords = ["身份证", "身份證", "居民身份", "护照", "護照", "签证", "簽證", "居留", "外国人登录", "外國人登錄",
                                 "驾驶证", "駕駛證", "驾照", "銀行卡", "银行卡", "借记卡", "信用卡", "卡号", "卡號", "对账单", "对帐单",
                                 "對帳單", "交易明细", "交易明細", "账户", "帳戶", "流水", "余额", "餘額", "社保", "户口", "证件", "證件",
                                 "passport", "visa", "residence card", "bank", "statement", "id card", "identity card", "iban"]
    static func sensitive(_ text: String) -> Bool {
        let t = text.lowercased()
        return sensitiveWords.contains { t.contains($0) }
    }

    /// Runs of four digits or more (spaces, dashes, dots, commas, slashes or colons inside them) as 「****」.
    static func masked(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d \-.,/:]*\d"#) else { return text }
        let ns = text as NSString
        var out = text
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let run = ns.substring(with: m.range)
            guard run.filter(\.isNumber).count >= 4, let r = Range(m.range, in: out) else { continue }
            out.replaceSubrange(r, with: "****")
        }
        return out
    }

    /// For the model looking at pictures and video frames: what it is, briefly, in Chinese; no numbers of a person.
    /// 192: which app a look is made in, said before the ask (the window's bar names both).
    static func appSaid(_ app: XiaoLanOrders.App) -> String {
        app == .wework ? "（这是在企业微信里。）" : "（这是在微信里，不是企业微信。）"
    }

    static let lookSystem = """
    你是聊天助手的眼睛。用户发来的是聊天软件里一张图片、一个视频的几帧截图，或者点开的网页截图。\
    用简体中文简短说明内容（不超过120字）：是什么东西、主要的人和物、画面里写着的重要文字。\
    如果是证件、银行卡、合同等含个人信息的，只说是什么类型，不要抄写姓名以外的号码（身份证号、手机号、卡号等）。\
    截图顶部的状态栏可能同时写着「微信」「企业微信」等几个 App 的名字，不要据此说是在哪个 App 里；问题里说了是哪个 App 才照说。\
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
