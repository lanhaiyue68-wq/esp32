import Foundation

/// Parsing of the model's replies; a line-for-line port of agent.py (parse_command, parse_actions, parse_plan).
enum Actions {
    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Bookkeeping keys that are not part of the action itself.
    static let meta: Set<String> = ["t", "thought", "thought_zh", "think_s", "act_s", "shot", "_shot", "changed", "by"]

    /// action name -> argument names; numeric arguments are 0-1000 screen coordinates
    static let actions: [String: [String]] = [
        "tap": ["x", "y"], "swipe": ["x1", "y1", "x2", "y2"], "circle": ["x", "y", "r"], "path": ["points"],
        "type": ["text"], "key": ["combo"], "done": ["answer"], "fail": ["reason"],
        "home": [], "back": [], "wait": [], "replan": [], "open": ["app"], "note": ["text"],
    ]
    static let textArgs: Set<String> = ["text", "combo", "answer", "reason", "app"]

    /// One DO line, e.g. "tap 152 362" -> {"action": "tap", "x": 152, "y": 362}.
    static func parseCommand(_ line: String) throws -> JObject {
        let (head, whole) = partition(line.trimmingCharacters(in: .whitespacesAndNewlines))
        let rest = withoutRunOn(whole)
        let name = head.lowercased()
        guard let keys = actions[name] else { throw ParseError(message: "unknown action: \(line.prefix(100))") }
        if let first = keys.first, textArgs.contains(first) {
            let raw = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            // A JSON string keeps code indentation, literal quotes and escaped newlines in one DO line.
            // Plain legacy commands remain literal: a path containing \n must not become a newline.
            let decoded = raw.hasPrefix("\"") ? try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) : nil
            let text = decoded ?? raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return ["action": .str(name), first: .str(text)]
        }
        let tokens = matches(#"[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?"#, in: rest)
        let numbers = try tokens.map { token -> Int in
            guard let value = Double(token), value.isFinite, (0...1000).contains(value) else {
                throw ParseError(message: "coordinates must be finite and in 0...1000")
            }
            return Int(value) // bounded before conversion; huge model values cannot trap
        }
        if keys == ["points"] {
            guard numbers.count >= 4, numbers.count % 2 == 0 else {
                throw ParseError(message: "path needs 2+ x y pairs: \(line.prefix(100))")
            }
            let points = stride(from: 0, to: numbers.count, by: 2).prefix(20)
                .map { JValue.arr([.int(numbers[$0]), .int(numbers[$0 + 1])]) }
            var action: JObject = ["action": .str(name), "points": .arr(Array(points))]
            if rest.lowercased().contains("smooth") { action["smooth"] = .bool(true) }  // a curve through the points
            return action
        }
        guard numbers.count == keys.count else {
            throw ParseError(message: "\(name) needs \(keys.count) numbers: \(line.prefix(100))")
        }
        var action: JObject = ["action": .str(name)]
        for (k, n) in zip(keys, numbers) { action[k] = .int(n) }
        if name == "tap" && rest.lowercased().contains("precise") { action["precise"] = .bool(true) }
        return action
    }

    /// Parse a THINK / DO… reply (an optional ZH line is kept); the thought goes on the first action.
    /// The next label run on in one line is not part of the command: `type 1152"THINK: check the note` typed the thought
    /// into a note, and the digits in `tap 300 132 THINK: the 2nd row` would be taken for coordinates (11-09).
    static func withoutRunOn(_ text: String) -> String {
        guard let label = text.range(of: #""?\s*(?<![A-Za-z])(THINK|DO)\s*[:：]"#, options: .regularExpression) else { return text }
        return String(text[..<label.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    static func parseActions(_ text: String) throws -> [JObject] {
        // Some models join THINK and DO on one line (log24). Accept only that explicit labelled form.
        let normalized = text.replacingOccurrences(of: #"(?m)^(\s*THINK\s*[:：][^\n]*?[。.!?])\s*(DO\s*[:：])"#,
                                                   with: "$1\n$2", options: .regularExpression)
        let thought = firstGroup(#"^\s*THINK\s*[:：]\s*(.*?)\s*$"#, in: normalized, multiline: true)
        let zh = firstGroup(#"^\s*ZH\s*[:：]\s*(.*?)\s*$"#, in: normalized, multiline: true)
        var acts = try allGroups(#"^\s*DO\s*[:：]\s*(.*?)\s*$"#, in: normalized).map(parseCommand).prefix(6).map { $0 }
        guard !acts.isEmpty else { throw ParseError(message: "no DO line in reply: \(text.prefix(200))") }
        acts[0] = JObject([("thought", .str(thought ?? "")), ("thought_zh", .str(zh ?? ""))]).merging(acts[0])
        return acts
    }

    /// Split an optional EN: / ZH: plan reply; a plain reply is used for both.
    static func parsePlan(_ text: String) -> (String, String) {
        let re = try! NSRegularExpression(pattern: #"EN\s*[:：](.*?)ZH\s*[:：](.*)"#,
                                          options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = text as NSString
        if let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            return (trim(ns.substring(with: m.range(at: 1))), trim(ns.substring(with: m.range(at: 2))))
        }
        return (trim(text), trim(text))
    }

    /// The action itself, without thoughts, timings and other bookkeeping.
    static func key(_ step: JObject) -> JObject { step.without(meta) }

    /// Precision changes how a tap is delivered and smoothing how a path is drawn, not the target or the intent.
    static func sameTarget(_ lhs: JObject, _ rhs: JObject) -> Bool {
        key(lhs).without(["precise", "smooth"]) == key(rhs).without(["precise", "smooth"])
    }

    /// x and y use different screen scales; the circle radius is measured against width only.
    static func drawingBounds(_ action: JObject, aspect: Double) -> CGRect? {
        guard aspect.isFinite, aspect > 0, action["action"] == .str("circle"),
              let x = action["x"]?.double, let y = action["y"]?.double, let r = action["r"]?.double else { return nil }
        return CGRect(x: x-r, y: y-r*aspect, width: 2*r, height: 2*r*aspect)
    }

    // MARK: - helpers

    private static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private static func partition(_ s: String) -> (String, String) {
        guard let i = s.firstIndex(of: " ") else { return (s, "") }
        return (String(s[..<i]), String(s[s.index(after: i)...]))
    }

    private static func regex(_ p: String, multiline: Bool) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: multiline ? [.anchorsMatchLines, .caseInsensitive] : [])
    }

    private static func matches(_ p: String, in s: String) -> [String] {
        let ns = s as NSString
        return regex(p, multiline: false).matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    private static func firstGroup(_ p: String, in s: String, multiline: Bool) -> String? {
        let ns = s as NSString
        guard let m = regex(p, multiline: multiline).firstMatch(in: s, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func allGroups(_ p: String, in s: String) -> [String] {
        let ns = s as NSString
        return regex(p, multiline: true).matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }
}

/// Screen points (fractions) the pointer passes through for one action.
func pointerPath(_ act: JObject) -> [CGPoint] {
    func n(_ k: String) -> Double { act[k]?.double ?? 0 }
    func f(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x / 1000, y: y / 1000) }
    switch act["action"]?.str {
    case "tap": return [f(n("x"), n("y"))]
    case "swipe": return [f(n("x1"), n("y1")), f(n("x2"), n("y2"))]
    case "path": return points(act).map { f($0.x, $0.y) }
    case "circle": return [f(n("x") + n("r"), n("y"))]
    case "home": return [CGPoint(x: 0.5, y: 0.995), CGPoint(x: 0.5, y: 0.6)]
    case "back": return [CGPoint(x: 0.005, y: 0.45), CGPoint(x: 0.6, y: 0.45)]
    default: return []
    }
}

/// The [[x, y], …] points of a path action, in 0-1000 units.
func points(_ act: JObject) -> [CGPoint] {
    guard case .arr(let items)? = act["points"] else { return [] }
    return items.compactMap {
        guard case .arr(let p) = $0, p.count == 2, let x = p[0].double, let y = p[1].double else { return nil }
        return CGPoint(x: x, y: y)
    }
}

/// Points around a circle; r is a fraction of the width, aspect = width / height. `extra` goes on past the start
/// by that fraction of a turn, so ends the drawing app loses still overlap.
func circle(_ x: Double, _ y: Double, _ r: Double, aspect: Double, n: Int = 24, extra: Double = 0) -> [CGPoint] {
    (0...(n + Int((Double(n) * max(extra, 0)).rounded()))).map { i in
        let a = 2 * Double.pi * Double(i) / Double(n)
        return CGPoint(x: x + r * cos(a), y: y + r * aspect * sin(a))
    }
}

/// A smooth stroke through every point (Catmull-Rom), in the points' own units. At most about 40 points, so the
/// whole stroke still fits one board command.
func smoothCurve(_ pts: [CGPoint]) -> [CGPoint] {
    guard pts.count > 2 else { return pts }
    let segments = pts.count - 1
    let per = max(2, min(8, 32 / segments))
    var out = [pts[0]]
    for i in 0..<segments {
        let (p0, p1, p2, p3) = (pts[max(i - 1, 0)], pts[i], pts[i + 1], pts[min(i + 2, segments)])
        for s in 1...per {
            let t = Double(s) / Double(per)
            func blend(_ v0: CGFloat, _ v1: CGFloat, _ v2: CGFloat, _ v3: CGFloat) -> CGFloat {
                let (a, b, c, d) = (Double(v0), Double(v1), Double(v2), Double(v3))
                return CGFloat(0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t
                                      + (3 * b - a - 3 * c + d) * t * t * t))
            }
            out.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
        }
    }
    return out
}
