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
    static func keyTokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).flatMap { part -> [String] in
            part.count > 1 && part.allSatisfy({ $0.isASCII && $0.isLetter }) ? [String(part)] : part.map(String.init)
        }
    }

    /// One spelling for what a key shows and what the model calls it (OCR reads − as 一 or -, × as x).
    static func keyLabel(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces).uppercased()
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
        for token in keyTokens(text) {
            let want = keyLabel(token)
            guard let key = pieces.filter({ keyLabel($0.text) == want }).max(by: { $0.box.midY < $1.box.midY }) else {
                missing.append(token)
                continue
            }
            spots.append(CGPoint(x: key.box.midX, y: key.box.midY))
        }
        return (spots, missing)
    }

    /// What a keypad's keys type on the keyboard (digits, . + - × ÷ = %, AC/C as esc), in runs; nil when a key has no
    /// key of its own (a word, ±, a letter), and the keys are then tapped.
    static func typedKeys(_ tokens: [String]) -> [String]? {
        var out: [String] = []
        var run = ""
        for token in tokens {
            let key = keyLabel(token)
            switch key {
            case "AC", "C", "CE":
                if !run.isEmpty { out.append(run); run = "" }
                out.append("esc")
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

    /// The short labels read on screen, with their spots in 0-1000, for a press that could not find all its keys.
    static func keysSeen(_ pieces: [CandidatePicker.Piece]) -> String {
        pieces.filter { (1...3).contains($0.text.count) }
            .sorted { ($0.box.midY, $0.box.midX) < ($1.box.midY, $1.box.midX) }
            .prefix(30)
            .map { String(format: "%@ (%.0f,%.0f)", $0.text, $0.box.midX * 1000, $0.box.midY * 1000) }
            .joined(separator: ", ")
    }
}
