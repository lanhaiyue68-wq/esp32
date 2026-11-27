import Foundation
import UIKit
import Vision
import ImageIO

/// Reads text on this phone (on-device text recognition) so typing needs no model look per phrase: the pinyin
/// candidate to tap, and whether a paste really put the reply in the field. Asking the model for each candidate took
/// seconds a phrase, and it picked wrong ones it then had to delete (build 31). Anything not found here is left to the
/// model as before.
enum CandidatePicker {
    /// Text on one line of the screen, split where the gap between two characters is wide (two candidates).
    struct Piece: Equatable { var text: String; var box: CGRect }  // box: 0-1 of the screen, origin top-left

    /// Keys of the Chinese keyboards that look like candidates.
    static let keyLabels: Set<String> = ["选拼音", "选定", "确认", "分隔", "换行", "发送", "空格", "重输", "拼音", "中", "英"]

    /// Where the candidate `phrase` is, in 0-1 screen coordinates: an exact piece on a row of several (the candidate
    /// row; a field holds one), the lowest such row (chat bubbles are above the keyboard and its candidates).
    static func find(_ phrase: String, in jpeg: Data) -> CGPoint? {
        guard !phrase.isEmpty, !keyLabels.contains(phrase) else { return nil }
        return find(phrase, rows: rows(in: jpeg, top: 0.4, bottom: 1))
    }

    /// The longest candidate that starts `phrase`, on the lowest row of several pieces that has one (the candidate
    /// row sits right above the keyboard; chat bubbles are higher up), in 0-1 screen coordinates.
    static func longestStart(of phrase: String, in jpeg: Data) -> (text: String, spot: CGPoint)? {
        longestStart(of: phrase, rows: rows(in: jpeg, top: 0.4, bottom: 1))
    }

    static func longestStart(of phrase: String, rows: [[Piece]]) -> (text: String, spot: CGPoint)? {
        let starts = { (row: [Piece]) in row.filter { !$0.text.isEmpty && phrase.hasPrefix($0.text) && !keyLabels.contains($0.text) } }
        guard let row = rows.filter({ $0.count >= 2 && !starts($0).isEmpty }).max(by: { $0[0].box.midY < $1[0].box.midY }),
              let best = starts(row).max(by: { $0.text.count < $1.text.count }) else { return nil }
        return (best.text, CGPoint(x: best.box.midX, y: best.box.midY))
    }

    static func find(_ phrase: String, rows: [[Piece]]) -> CGPoint? {
        let hits = rows.filter { $0.count >= 2 }.flatMap { $0 }.filter { $0.text == phrase }
        guard let hit = hits.max(by: { $0.box.midY < $1.box.midY }) else { return nil }
        return CGPoint(x: hit.box.midX, y: hit.box.midY)
    }

    /// Rows of the keyboard menu a pointer click on the globe key opens; any one shows the menu is up.
    /// Menu-only labels: not keyboard keys (拼音 is one), so a chat line next to the keyboard never counts.
    static let keyboardMenuWords = ["englishus", "englishuk", "表情符号", "表情符號", "emoji", "键盘设置", "鍵盤設定",
                                    "鍵盤設置", "键盘设定", "keyboardsettings"]

    /// The keyboard menu is open: one of its menu-only rows shows.
    /// D84, y5 on 138 (item 43): Lan Agent's own keyboard, known by its status line ("Lan Agent 輸入法…", "連不上 Lan
    /// Agent…", "Lan Agent 已填入…") and its 空格 key, both in the lower part of the screen.
    static func ourKeyboardShown(rows: [[Piece]]) -> Bool {
        let low = rows.filter { ($0.map(\.box.minY).min() ?? 0) >= 0.55 }.map { bare($0.map(\.text).joined()).lowercased() }
        // Without Full Access it says so and never asks: not waited for.
        return low.contains { line in ourKeyboardMarks.contains { line.contains($0) } } && low.contains { $0.contains("空格") }
            && !low.contains { $0.contains("完整取用") }
    }

    /// The keyboard's status line, bare and lowercased: its old name (Lan Agent), or Pilot's own words (156: the
    /// keyboard is called Pilot now; a phone still on an older build shows the old line).
    /// 182 (Echo 181, 11-26: after the iPad restarted, WeChat's keyboard was 简体拼音 again; the globe menu opened but
    /// "has no Lan Agent row": 小藍's keyboard is listed as 小藍 — Echo): 小藍's names and status words too.
    static let ourKeyboardMarks = ["lanagent", "pilot輸入法", "pilot输入法", "pilot已填入", "連不上pilot", "连不上pilot",
                                   "小藍輸入法", "小蓝输入法", "小藍已填入", "小蓝已填入"]
    /// The keyboard's name in the globe key's menu, bare and lowercased (Pilot from 156, Lan Agent before, 小藍 — Echo).
    static let ourKeyboardNames: Set<String> = ["pilot", "lanagent", "小藍echo", "小蓝echo", "小藍", "小蓝"]

    /// 183 (Echo 182, 11-26: on the iPad the menu row 小藍 — Echo read as "小藍-Echo" or "小藍一Echo": "一" is a letter
    /// and stayed in, so the row was not ours and 简体拼音 stayed): a bare, lowercased menu line that names 小藍's keyboard.
    static func ourKeyboardName(_ line: String) -> Bool {
        let l = line.replacingOccurrences(of: "一", with: "")
        if ourKeyboardNames.contains(l) { return true }
        return l.count <= 12 && l.contains("echo") && (l.contains("小藍") || l.contains("小蓝"))
    }

    static func keyboardMenuOpen(rows: [[Piece]]) -> Bool {
        rows.contains { row in keyboardMenuWords.contains { bare(row.map(\.text).joined()).lowercased().hasPrefix($0) } }
    }

    /// Where "Lan Agent" is in the open keyboard menu, 0-1 screen coordinates. The row must read exactly "Lan Agent"
    /// (a chat bubble mentioning it has more text) and sit in one left-aligned column with another menu row.
    static func keyboardMenuEntry(rows: [[Piece]]) -> CGPoint? {
        func plain(_ s: String) -> String { bare(s).lowercased() }
        func line(_ row: [Piece]) -> String { plain(row.map(\.text).joined()) }
        func left(_ row: [Piece]) -> Double { Double(row.map(\.box.minX).min() ?? 1) }
        let markers = rows.filter { row in keyboardMenuWords.contains { line(row).hasPrefix($0) } }.map(left)
        guard !markers.isEmpty else { return nil }
        for row in rows where !row.isEmpty && ourKeyboardName(line(row)) {
            let box = row.dropFirst().reduce(row[0].box) { $0.union($1.box) }
            guard box.midX < 0.7, markers.contains(where: { abs($0 - Double(box.minX)) < 0.08 }) else { continue }
            return CGPoint(x: box.midX, y: box.midY)
        }
        return nil
    }

    /// Key labels of the iPhone keyboards (9-key and full pinyin, English).
    static let keyboardWords: Set<String> = ["ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ", "空格", "space",
                                             "return", "确认", "发送", "分隔", "选拼音", "选定", "换行", "123", "拼"]

    /// True when the on-screen keyboard is up: its key labels in the lower part of the screen. Back from Lan Agent the
    /// box often still has the keyboard, and a tap where the box sits without it hit the space bar (logs(17)).
    /// The text label a tap at `point` (0-1) was meant for, for a learned route: a piece under the point, else the
    /// nearest one around it (an app's name sits under its icon). Short names are preferred over message previews and
    /// times, which change from one visit to the next.
    static func label(_ jpeg: Data, _ point: CGPoint) -> (text: String, centre: CGPoint)? {
        func cost(_ p: Piece) -> Double {
            let under = p.box.insetBy(dx: -0.01, dy: -0.01).contains(point)
            let distance: Double = under ? 0 : Double(hypot(p.box.midX - point.x, p.box.midY - point.y))
            let long: Double = p.text.count > 8 ? 0.05 : 0
            let changing: Double = p.text.contains(where: \.isNumber) ? 0.05 : 0
            return distance + long + changing
        }
        func around(_ p: Piece) -> Bool {
            let named = !p.text.trimmingCharacters(in: .whitespaces).isEmpty && p.text.count <= 20
            let dx: Double = abs(Double(p.box.midX - point.x)), dy: Double = abs(Double(p.box.midY - point.y))
            return named && dx <= 0.1 && dy <= 0.08
        }
        // D154: the status bar's clock is no control's label ("tap “5:25”" was a back arrow, 147's s7).
        let pieces: [Piece] = rows(in: jpeg, top: Vision.topMask, bottom: 1).flatMap { $0 }
        guard let best = pieces.filter(around).min(by: { cost($0) < cost($1) }) else { return nil }
        return (best.text, CGPoint(x: best.box.midX, y: best.box.midY))
    }

    static func keyboardUp(in jpeg: Data) -> Bool {
        Vision.letterKeyboard(jpeg) || keyboardUp(rows: rows(in: jpeg, top: 0.6, bottom: 1))
    }

    static func keyboardUp(rows: [[Piece]]) -> Bool {
        if rows.flatMap({ $0 }).filter({ keyboardWords.contains($0.text) }).count >= 2 { return true }
        return aligned(rows).contains(where: letterKeys)
    }

    /// Vision can return each key, several keys, or a whole row as separate observations.
    private static func aligned(_ rows: [[Piece]]) -> [[Piece]] {
        var result: [[Piece]] = []
        for p in rows.flatMap({ $0 }).sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = result.last, let first = last.first,
               abs(first.box.midY - p.box.midY) < max(first.box.height, p.box.height) * 0.6 {
                result[result.count - 1].append(p)
            } else { result.append([p]) }
        }
        return result.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    private static func letterKeys(_ row: [Piece]) -> Bool {
        let labels = row.map(\.text).joined().lowercased().filter { !$0.isWhitespace }
        guard labels.count >= 6 else { return false }
        return ["qwertyuiop", "asdfghjkl", "zxcvbnm"].contains { keys in
            if keys.contains(labels) { return true }
            // OCR may omit a key. Keep the ordering and require keys spread across the screen, rather than
            // rejecting the whole keyboard because one letter was missed (also broke candidate-strip removal).
            guard keys.count - labels.count >= 0, keys.count - labels.count <= 2, row.count >= 4,
                  let left = row.map(\.box.minX).min(), let right = row.map(\.box.maxX).max(), right - left > 0.5 else { return false }
            var cursor = keys.startIndex
            for letter in labels {
                guard let index = keys[cursor...].firstIndex(of: letter) else { return false }
                cursor = keys.index(after: index)
            }
            return true
        }
    }

    /// A send tap hit a letter key: the same pre-send field now contains the requested text plus a short suffix.
    /// Only this positive evidence can undo send protection. Empty/unreadable fields or a new matching bubble
    /// cannot authorize another send. Geometry comes from the observed draft, not a particular app layout.
    static func mistypedDraft(_ text: String, before: Data, after: Data) -> String? {
        let expected = bare(text)
        guard expected.count >= 2 else { return nil }
        let old = aligned(aboveKeyboard(rows(in: before, top: 0.3, bottom: 1)))
        let currentRows = rows(in: after, top: 0.3, bottom: 1)
        guard keyboardUp(rows: currentRows), let field = old.last(where: { row in
            bare(row.map(\.text).joined()) == expected && (row.first?.box.midY ?? 0) >= 0.35
        }) else { return nil }
        let box = field.map(\.box).reduce(CGRect.null) { $0.union($1) }
        let current = aligned(aboveKeyboard(currentRows))
        func sameLine(_ row: [Piece]) -> Bool {
            guard let first = row.first else { return false }
            return abs(first.box.midY - box.midY) < max(0.015, box.height)
                && abs(first.box.minX - box.minX) < 0.05
        }
        guard let row = current.first(where: sameLine) else { return nil }
        let actual = bare(row.map(\.text).joined())
        guard actual.hasPrefix(expected) else { return nil }
        let suffix = actual.dropFirst(expected.count)
        guard (1...3).contains(suffix.count), suffix.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let previousBubbles = shows(text, lines: old.filter { !sameLine($0) }.map { $0.map(\.text).joined() })
        let currentBubbles = shows(text, lines: current.filter { !sameLine($0) }.map { $0.map(\.text).joined() })
        guard currentBubbles <= previousBubbles else { return nil }
        return row.map(\.text).joined()
    }

    /// Positive evidence of an unsent draft, including wrapped text. A missing field is uncertainty.
    /// Require the same lowest text field above a visible keyboard and no newly matching message elsewhere.
    static func unchangedDraft(_ text: String, before: Data, after: Data) -> Bool {
        let oldRows = rows(in: before, top: 0.3, bottom: 1)
        let newRows = rows(in: after, top: 0.3, bottom: 1)
        guard keyboardUp(rows: oldRows), keyboardUp(rows: newRows) else { return false }
        let old = aligned(aboveKeyboard(oldRows)), current = aligned(aboveKeyboard(newRows))
        guard let last = old.last, let lastBox = last.first?.box, lastBox.midY >= 0.35 else { return false }
        let nine: Set<String> = ["ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"]
        guard let keys = aligned(oldRows).first(where: { letterKeys($0) || $0.filter { nine.contains($0.text) }.count >= 2 }),
              let keyboardTop = keys.map(\.box.minY).min(),
              keyboardTop - lastBox.maxY < 0.2 else { return false }
        guard let start = old.indices.reversed().first(where: { index in
            shows(text, lines: [old[index...].flatMap { $0.map(\.text) }.joined()]) == 1
        }) else { return false }
        let field = Array(old[start...])
        let box = field.flatMap { $0.map(\.box) }.reduce(CGRect.null) { $0.union($1) }
        func inField(_ row: [Piece]) -> Bool {
            guard let first = row.first else { return false }
            return first.box.midY >= box.minY - 0.015 && first.box.midY <= box.maxY + 0.015
                && abs(first.box.minX - box.minX) < 0.05
        }
        let draft = current.filter(inField).flatMap { $0.map(\.text) }.joined()
        guard shows(text, lines: [draft]) == 1 else { return false }
        let previousBubbles = shows(text, lines: old.filter { !inField($0) }.map { $0.map(\.text).joined() })
        let currentBubbles = shows(text, lines: current.filter { !inField($0) }.map { $0.map(\.text).joined() })
        return currentBubbles <= previousBubbles
    }

    /// Exclude the keyboard and its suggestion strip. A disappearing suggestion must not cancel out a new copy
    /// in the field (logs34), nor can a suggestion confirm text that never reached the field.
    private static func aboveKeyboard(_ rows: [[Piece]]) -> [[Piece]] {
        let lines = aligned(rows)
        let nineKeyLabels: Set<String> = ["ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"]
        guard let first = lines.first(where: { letterKeys($0) || $0.filter { nineKeyLabels.contains($0.text) }.count >= 2 }),
              let top = first.map(\.box.minY).min(), let height = first.map(\.box.height).max() else { return rows }
        // The candidate strip is immediately above the first key row. Account for its height even when OCR
        // misses the candidates; when readable, exclude the nearest strip explicitly.
        var boundary = top - max(0.045, height * 2.5)
        if let strip = lines.last(where: { row in
            guard let bottom = row.map(\.box.maxY).max() else { return false }
            return bottom < top && top - bottom < 0.08
        }), let stripTop = strip.map(\.box.minY).min() {
            boundary = min(boundary, stripTop)
        }
        return rows.filter { $0.allSatisfy { $0.box.maxY < boundary } }
    }

    /// The "允许粘贴" button of iOS's paste prompt ("微信" wants to paste from "Lan Agent"), if it is up. iOS asks at every
    /// paste from another app unless the app is set to allow it (Settings › 微信 › 从其他App粘贴).
    static func allowPaste(in jpeg: Data) -> CGPoint? { allowPaste(rows: rows(in: jpeg, top: 0.25, bottom: 0.85)) }

    static func allowPaste(rows: [[Piece]]) -> CGPoint? {
        guard let p = rows.flatMap({ $0 }).first(where: { $0.text == "允许粘贴" || $0.text == "AllowPaste" }) else { return nil }
        return CGPoint(x: p.box.midX, y: p.box.midY)
    }

    /// How often the whole `text` shows above the keyboard. A paste must add the whole text, not just its prefix.
    static func count(_ text: String, in jpeg: Data) -> Int {
        shows(text, in: jpeg)
    }

    /// How often the whole of `text` shows above the keyboard, the rows joined so a
    /// wrapped input box counts: typed text is confirmed when this goes up.
    static func shows(_ text: String, in jpeg: Data) -> Int {
        shows(text, rows: rows(in: jpeg, top: 0.3, bottom: 1))
    }

    static func shows(_ text: String, rows: [[Piece]]) -> Int {
        shows(text, lines: aligned(aboveKeyboard(rows)).map { $0.map(\.text).joined() })
    }

    static func shows(_ text: String, lines: [String]) -> Int {
        func visibleText(_ value: String) -> String {
            // OCR may split a wrapped field or use half-width punctuation. Operators, punctuation and
            // letter case still carry meaning; removing them would verify "!=" as "==" or "Send!" as "Send?".
            let folded = value.precomposedStringWithCanonicalMapping
                .folding(options: .widthInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            return String(folded.filter { !$0.isWhitespace })
        }
        let probe = visibleText(text)
        guard probe.count >= 2 else { return 0 }
        let words = lines.map(visibleText).filter { !$0.isEmpty }
        var count = 0
        for start in words.indices {
            var joined = ""
            for word in words[start...] {
                joined += word
                if joined == probe { count += 1; break }
                if !probe.hasPrefix(joined) { break }
            }
        }
        return count  // whole OCR lines, including wrapped fields; “你好p” is not “你好”
    }

    /// The 9-key pinyin keyboard, by its key labels: it turns the board's letter keys into digit keys.
    static func nineKey(in jpeg: Data) -> Bool { nineKey(rows: rows(in: jpeg, top: 0.6, bottom: 1)) }

    static func nineKey(rows: [[Piece]]) -> Bool {
        let labels: Set<String> = ["ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"]
        return rows.flatMap { $0 }.filter { labels.contains($0.text) }.count >= 3
    }

    static func count(_ text: String, lines: [String]) -> Int {
        let probe = String(bare(text).prefix(6))
        guard probe.count >= 2 else { return 0 }  // too short to tell apart: not confirmed
        return lines.reduce(0) { $0 + bare($1).components(separatedBy: probe).count - 1 }
    }

    static func bare(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.letters.union(.decimalDigits).contains($0) }))
    }

    /// Splits recognized characters into pieces where the gap is wider than 0.6 of a typical character.
    static func split(_ chars: [(Character, CGRect)]) -> [Piece] {
        guard let first = chars.first else { return [] }
        let widths = chars.map { $0.1.width }.sorted()
        let gap = widths[widths.count / 2] * 0.6
        var pieces: [Piece] = [], current = Piece(text: "", box: first.1)
        for (k, c) in chars.enumerated() {
            if k > 0, c.1.minX - chars[k - 1].1.maxX > gap {
                pieces.append(current)
                current = Piece(text: "", box: c.1)
            }
            current.text.append(c.0)
            current.box = current.box.union(c.1)
        }
        pieces.append(current)
        return pieces
    }

    /// rows(in:) away from the main thread. Recognition can take seconds, and while it ran on the main thread the whole
    /// app stood still: no frames, no answers from the board, no model replies (5-20 s at a time over USB 11-09).
    static func rowsOffMain(in jpeg: Data, top: Double, bottom: Double) async -> [[Piece]] {
        await Task.detached(priority: .userInitiated) { CandidatePicker.rows(in: jpeg, top: top, bottom: bottom) }.value
    }

    static func keyboardUpOffMain(in jpeg: Data) async -> Bool {
        await Task.detached(priority: .userInitiated) { CandidatePicker.keyboardUp(in: jpeg) }.value
    }

    /// The text lines in a band of the screen (top and bottom 0-1 from the top), each split into pieces.
    static func rows(in jpeg: Data, top: Double, bottom: Double) -> [[Piece]] {
        let onMain = Thread.isMainThread
        if onMain { StallWatch.doing = "text recognition" }
        defer { if onMain { StallWatch.doing = "" } }
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let h = Double(image.height)
        let band = CGRect(x: 0, y: top * h, width: Double(image.width), height: (bottom - top) * h).integral
        guard let crop = image.cropping(to: band) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: crop, options: [:]).perform([request]) } catch { return [] }
        func onScreen(_ r: CGRect) -> CGRect {  // Vision: 0-1 of the crop, origin bottom-left
            CGRect(x: r.minX, y: top + (1 - r.maxY) * (bottom - top), width: r.width, height: r.height * (bottom - top))
        }
        return (request.results ?? []).compactMap { observation -> [Piece]? in
            guard let best = observation.topCandidates(1).first else { return nil }
            let s = best.string
            var chars: [(Character, CGRect)] = []
            var i = s.startIndex
            while i < s.endIndex {
                let next = s.index(after: i)
                if !s[i].isWhitespace, let box = try? best.boundingBox(for: i..<next)?.boundingBox {
                    chars.append((s[i], onScreen(box)))
                }
                i = next
            }
            let pieces = split(chars)
            // 189 (N17): one piece of Chinese narrower in words than in width is read once more on its own
            if pieces.count == 1, let again = reread(crop, box: observation.boundingBox, read: s) {
                return [Piece(text: again, box: pieces[0].box)]
            }
            return pieces.isEmpty ? nil : pieces
        }
    }

    /// 189 (N17, Echo 188, 11-27 11:37 首爾: 「好的嗎」 in plain view, its box three characters wide, was read 「好嗎」 and
    /// answered so; its list preview read 「好昀嗎」): a line of Chinese characters (no space in it) whose box is wider
    /// than what was read by most of a character is read again on its own at twice the size, Traditional Chinese allowed
    /// too. The new reading is taken only when it keeps every character read, in order, adds what was missing, and fits
    /// the box; otherwise nil (the first reading stands). A Chinese character is about as wide as its line is tall
    /// (measured 11-27: 0.90–0.96 of the box's height per character).
    static func reread(_ crop: CGImage, box: CGRect, read s: String) -> String? {
        let chars = Array(s.filter { !$0.isWhitespace })
        guard (1...16).contains(chars.count), chars.count == s.count, chars.allSatisfy(isWide) else { return nil }
        let cw = Double(crop.width), ch = Double(crop.height)
        let w = Double(box.width) * cw, h = Double(box.height) * ch
        guard h >= 6 else { return nil }
        let fits = w / (h * 0.92)
        guard fits - Double(chars.count) >= 0.75 else { return nil }
        let pad = h * 0.4, padUp = h * 0.25  // little above and under: no part of the lines around it
        let rect = CGRect(x: Double(box.minX) * cw - pad, y: (1 - Double(box.maxY)) * ch - padUp, width: w + 2 * pad, height: h + 2 * padUp)
            .integral.intersection(CGRect(x: 0, y: 0, width: cw, height: ch))
        guard rect.width > 4, rect.height > 4, let piece = crop.cropping(to: rect), let big = twice(piece) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = rereadLanguages
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: big, options: [:]).perform([request]) } catch { return nil }
        // the line itself: the biggest text found there (a sliver of a line around it reads as a small one)
        let line = (request.results ?? []).max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
        guard let text = line?.topCandidates(1).first?.string else { return nil }
        let again = Array(text.filter { !$0.isWhitespace })
        guard again.count > chars.count, Double(again.count) <= fits + 0.6, keepsInOrder(chars, again) else { return nil }
        return String(again)
    }

    /// Simplified first (the customers' and the apps' words), Traditional too, then English; only what this iOS reads.
    static let rereadLanguages: [String] = {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let have = Set((try? request.supportedRecognitionLanguages()) ?? [])
        let want = ["zh-Hans", "zh-Hant", "en-US"].filter { have.contains($0) }
        return want.isEmpty ? ["zh-Hans", "en-US"] : want
    }()

    /// A Chinese character or full-width punctuation (as wide as the line is tall).
    static func isWide(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { u in
            (0x4E00...0x9FFF).contains(u.value) || (0x3400...0x4DBF).contains(u.value) || (0xF900...0xFAFF).contains(u.value)
                || (0x3000...0x303F).contains(u.value) || (0xFF01...0xFF5E).contains(u.value)
        }
    }

    /// Every character of `a`, in order, in `b`.
    static func keepsInOrder(_ a: [Character], _ b: [Character]) -> Bool {
        var i = 0
        for c in b where i < a.count && c == a[i] { i += 1 }
        return i == a.count
    }

    static func twice(_ image: CGImage) -> CGImage? {
        let w = image.width * 2, h = image.height * 2
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }
}

/// How putting text on the pasteboard went: filled, refused, or lost (the original target was not verified).
enum PasteHopResult { case filled, refused, lost }

/// The general pasteboard, for pasting a reply.
enum Pasteboard {
    /// Choose by keyboard capability, for every task. Enter/Tab can submit or move focus rather than insert
    /// code whitespace; unsupported scripts must never be dropped or transliterated into different content.
    @MainActor static func prefersExact(_ text: String) -> Bool {
        requiresPaste(text) || (needed(text) && text.count > 6)
    }

    /// These characters cannot safely fall back to keyboard input if exact paste is unavailable.
    /// Long Chinese may still use verified pinyin, but Enter/Tab and unsupported scripts cannot.
    @MainActor static func requiresPaste(_ text: String) -> Bool {
        if text.contains("\n") || text.contains("\r") || text.contains("\t") { return true }
        return Pointer.typingRuns(text).contains { run in
            run.kind != .chinese && (try? Pointer.keyboardChunks(run.text)) == nil
        }
    }

    /// True when some character is not on a US keyboard (Chinese, full-width punctuation, emoji).
    static func needed(_ text: String) -> Bool {
        !text.unicodeScalars.allSatisfy { (32...126).contains($0.value) || $0 == "\n" || $0 == "\t" }
    }

    /// Puts `text` on it; false when iOS did not take it (it refuses an app in the background, and Cmd+V then pasted
    /// what the user had copied: an API key, build 25).
    @MainActor static func put(_ text: String) -> Bool {
        let board = UIPasteboard.general, before = board.changeCount
        board.string = text
        return board.changeCount != before
    }
}
