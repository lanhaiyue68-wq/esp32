import CoreGraphics
import Foundation

/// Keys named in a `press` action that are not on the screen: nothing was tapped. Says which keys it did read, and where,
/// so the next look can tap the rest itself.
struct KeysNotOnScreen: LocalizedError {
    let missing: [String]
    let seen: String
    var errorDescription: String? {
        "Nothing pressed: no key labelled " + missing.map { "\"\($0)\"" }.joined(separator: ", ")
            + " was read on the screen. Keys read: " + (seen.isEmpty ? "none" : seen)
            + ". Tap the missing keys yourself, or press only keys that are listed."
    }
}

/// `press 4 0 . 7 4 − 3 2 . 9 =`: the on-screen buttons with these labels, found by reading the screen, tapped in order
/// (build 116). Over USB 11-10 Doubao tapped 8 for the point and × for 4 on Calculator, 45 taps for one subtraction: it
/// knew the labels but not where the keys were. A number pad, a dial pad, any keypad works the same way.
extension AgentLoop {
    /// "AC 40.74-32.9=" → AC 4 0 . 7 4 - 3 2 . 9 =: a word of letters is one key, anything else one key per character.
    /// D64, y3 on 137 (item 9): "AC 30 2x" for the 2ˣ key went in as 3 0 2 × and the display showed 302×. A part with a
    /// raised letter or digit (xʸ, 2ˣ, x²) is one key, and so is one mixing letters and digits that is a key read on the
    /// screen (`keys`, as keyLabel spells them: "2x", "x2", "2nd").
    static func keyTokens(_ text: String, keys: Set<String> = []) -> [String] {
        text.split(whereSeparator: \.isWhitespace).flatMap { part -> [String] in
            let p = String(part)
            guard p.count > 1 else { return [p] }
            if p.allSatisfy({ $0.isASCII && $0.isLetter }) || p.contains(where: { raised[$0] != nil }) { return [p] }
            if rootUnder[keyLabel(p)] != nil { return [p] }  // D90: √x is one key, not √ and ×
            if p.contains(where: \.isLetter), p.contains(where: \.isNumber), keys.contains(keyLabel(p)) { return [p] }
            return p.map(String.init)
        }
    }

    /// Raised letters and digits on function keys, as the screen reading gives them (xʸ as xY, 2ˣ as 2x, x² as x2).
    static let raised: [Character: String] = ["ʸ": "y", "ˣ": "x", "ⁿ": "n", "²": "2", "³": "3", "⁻": "-", "¹": "1", "⁰": "0"]

    /// A press naming a part of letters and digits ("2x", "x2", "2nd"): the keys on the screen are read first, to tell
    /// the 2ˣ key from 2 ×.
    static func namesFunctionKey(_ text: String) -> Bool {
        text.split(whereSeparator: \.isWhitespace).contains { p in
            p.count > 1 && p.contains(where: \.isLetter) && p.contains(where: \.isNumber)
        }
    }

    /// One spelling for what a key shows and what the model calls it (OCR reads − as 一 or -, × as x, xʸ as xY).
    static func keyLabel(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).map { raised[$0] ?? String($0) }.joined().uppercased()
        switch t {
        case "−", "–", "—", "一", "_": return "-"
        case "X", "*", "✕", "✖": return "×"
        case "/": return "÷"
        case "。", "·", "•", "．": return "."
        case "＝": return "="
        case "＋": return "+"
        default: return t
        }
    }

    /// Where each key is (0-1 of the screen), and the labels not found. Among several pieces with the same label the
    /// lowest wins: a keypad sits below the display that may show the same digit.
    static func keySpots(_ text: String, in pieces: [CandidatePicker.Piece]) -> (spots: [CGPoint], missing: [String]) {
        var spots: [CGPoint] = []
        var missing: [String] = []
        for token in keyTokens(text, keys: Set(pieces.map { keyLabel($0.text) })) {
            guard let spot = keySpot(keyLabel(token), in: pieces) else {
                missing.append(token)
                continue
            }
            spots.append(spot)
        }
        return (spots, missing)
    }

    /// The key with this label (as keyLabel spells it), the lowest of several; a root key not read, under its power key.
    static func keySpot(_ want: String, in pieces: [CandidatePicker.Piece]) -> CGPoint? {
        if let key = pieces.filter({ keyLabel($0.text) == want }).max(by: { $0.box.midY < $1.box.midY }) {
            return CGPoint(x: key.box.midX, y: key.box.midY)
        }
        return rootKeySpot(want, in: pieces)
    }

    /// Scientific Calculator's root keys, as keyLabel spells what the model calls them, and the power key each sits under.
    static let rootUnder: [String: String] = ["√": "X2", "√X": "X2", "2√X": "X2", "SQRT": "X2", "根号": "X2", "根號": "X2",
                                              "平方根": "X2", "3√X": "X3", "Y√X": "XY"]

    /// D90, z3 on 138 (item 5): "√2 × 1000" pressed nothing, twice: scientific Calculator's ²√x key was read as "⅔x" or
    /// not at all (³√x as "マx", ʸ√x as "V/x"), and the item was given up: "根号键多次无法识别". Its power keys (x², x³,
    /// xʸ) were read each time, with 2nd beside them: a root key not read by its label is the key right under its power
    /// key, in the next row read below it, or (none read) as far below as the power key's row is from the row above.
    static func rootKeySpot(_ want: String, in pieces: [CandidatePicker.Piece]) -> CGPoint? {
        guard let power = rootUnder[want],
              pieces.contains(where: { keyLabel($0.text) == "2ND" }),
              let key = pieces.filter({ keyLabel($0.text) == power }).min(by: { $0.box.midY < $1.box.midY }) else { return nil }
        let y = key.box.midY
        let below = pieces.map(\.box.midY).filter { $0 > y + 0.04 && $0 < y + 0.1 }.sorted()
        if !below.isEmpty { return CGPoint(x: key.box.midX, y: below[below.count / 2]) }
        guard let above = pieces.map(\.box.midY).filter({ $0 < y - 0.04 && $0 > y - 0.1 }).max() else { return nil }
        return CGPoint(x: key.box.midX, y: y + (y - above))
    }

    /// What a keypad's keys type on the keyboard (digits, . + - × ÷ = %, AC/C as esc), in runs; nil when a key has no
    /// key of its own (a word, ±, a letter), and the keys are then tapped. D64, y3 on 137: esc is Calculator's C, which
    /// clears only the number being typed (C then 2 left 302×2 on the screen, four times); AC and C are esc twice, all clear.
    static func typedKeys(_ tokens: [String]) -> [String]? {
        var out: [String] = []
        var run = ""
        for token in tokens {
            let key = keyLabel(token)
            switch key {
            case "AC", "C", "CE":
                if !run.isEmpty { out.append(run); run = "" }
                out += key == "CE" ? ["esc"] : ["esc", "esc"]
            case "×": run += "*"
            case "÷": run += "/"
            case "-", "+", "=", ".", "%": run += key
            default:
                guard key.count == 1, let c = key.first, c.isASCII, c.isNumber else { return nil }
                run += key
            }
        }
        if !run.isEmpty { out.append(run) }
        return out.isEmpty ? nil : out
    }

    enum KeyStep: Equatable {
        case type(String)  // keyboard keys, or "esc"
        case tap(CGPoint)  // a key read on the screen, 0-1 of it
    }

    /// D64, y3 on 137 (item 9): scientific Calculator's 0, = and operators were not read, its xʸ and 2ˣ keys were, and
    /// "2 xʸ 30 =" pressed nothing, three times; the thing was skipped. What the keyboard types is typed, the rest tapped
    /// where it was read. Nil when a key the keyboard has not was not read either, or when nothing is to be tapped.
    static func mixedKeys(_ text: String, in pieces: [CandidatePicker.Piece]) -> [KeyStep]? {
        var out: [KeyStep] = []
        for token in keyTokens(text, keys: Set(pieces.map { keyLabel($0.text) })) {
            if let typed = typedKeys([token]) {
                for piece in typed {
                    if piece != "esc", case .type(let run)? = out.last, run != "esc" {
                        out[out.count - 1] = .type(run + piece)
                    } else {
                        out.append(.type(piece))
                    }
                }
                continue
            }
            guard let spot = keySpot(keyLabel(token), in: pieces) else { return nil }
            out.append(.tap(spot))
        }
        return out.contains { if case .tap = $0 { return true } else { return false } } ? out : nil
    }

    /// The short labels read on screen, with their spots in 0-1000, for a press that could not find all its keys.
    static func keysSeen(_ pieces: [CandidatePicker.Piece]) -> String {
        pieces.filter { (1...3).contains($0.text.count) }
            .sorted { ($0.box.midY, $0.box.midX) < ($1.box.midY, $1.box.midX) }
            .prefix(30)
            .map { String(format: "%@ (%.0f,%.0f)", $0.text, $0.box.midX * 1000, $0.box.midY * 1000) }
            .joined(separator: ", ")
    }
}
