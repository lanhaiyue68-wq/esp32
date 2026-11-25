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
        let t = title.trimmingCharacters(in: .whitespaces)
        guard let open = t.lastIndex(where: { $0 == "(" || $0 == "（" }), t.hasSuffix(")") || t.hasSuffix("）") else { return (t, false) }
        let inside = t[t.index(after: open)..<t.index(before: t.endIndex)]
        guard !inside.isEmpty, inside.allSatisfy(\.isNumber) else { return (t, false) }
        return (String(t[..<open]).trimmingCharacters(in: .whitespaces), true)
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
                let text = o.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    if sameRow || nextRow {
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

    /// The chat on screen (its title already read and checked by the caller), or nil when the frame cannot be read.
    static func screen(_ jpeg: Data, title: String) -> WatchReport.Screen? {
        guard let px = Pixels(jpeg) else { return nil }
        let bottom = px.inputTop(from: 0.12) ?? 0.95
        let pieces = CandidatePicker.rows(in: jpeg, top: 0.08, bottom: bottom).joined()
            .filter { Double($0.box.minY) > 0.085 && Double($0.box.maxY) < bottom }
            .map { Piece(text: $0.text, box: $0.box, kind: kind($0.box, px)) }
        return lines(pieces, title: title)
    }
}
