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
        "home": [], "back": [], "wait": [], "replan": [], "open": ["app"], "note": ["text"], "press": ["text"],
        "listen": ["seconds"], "hold": ["x", "y"],
        "readup": ["until"],  // D27: read back up a chat by itself (爬楼), to the words given or the top
        "verify": ["app"],  // D59: a security check (滑块, 拼图) is on screen: the owner does it by hand
    ]
    /// Build 121 over the cloud 11-11: asked to copy a WeChat message, both models wrote a long press their own way
    /// (touch_and_hold, a swipe that stays put) and the run failed on "no valid action" three times.
    static let aliases = ["touch_and_hold": "hold", "long_press": "hold", "longpress": "hold", "long-press": "hold",
                          "press_and_hold": "hold", "hold_press": "hold"]
    static let textArgs: Set<String> = ["text", "combo", "answer", "reason", "app", "until"]

    /// One DO line, e.g. "tap 152 362" -> {"action": "tap", "x": 152, "y": 362}.
    static func parseCommand(_ line: String) throws -> JObject {
        let (head, whole) = partition(line.trimmingCharacters(in: .whitespacesAndNewlines))
        let rest = withoutRunOn(whole)
        let name = aliases[head.lowercased()] ?? head.lowercased()
        guard let keys = actions[name] else { throw ParseError(message: "unknown action: \(line.prefix(100))") }
        if let first = keys.first, textArgs.contains(first) {
            let raw = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            // A JSON string keeps code indentation, literal quotes and escaped newlines in one DO line.
            // Plain legacy commands remain literal: a path containing \n must not become a newline.
            let decoded = raw.hasPrefix("\"") ? try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) : nil
            var text = decoded ?? raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            // D57, s2 on 137: Codex's answer of ten restaurants came as one DO line with "\n\n" written out, and the owner's
            // answer showed the backslashes. An answer or a reason is prose, never a path: written-out line breaks are breaks.
            if decoded == nil, ["answer", "reason"].contains(first) {
                text = text.replacingOccurrences(of: "\\r\\n", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
            }
            return ["action": .str(name), first: .str(text)]
        }
        // D188, x4 on 150 (item 19): "DO: wait 5" came back "wait needs 0 numbers"; the hiccup became a stuck replan.
        // "wait 2/3/5" was refused 89 times in the traces of 140–150. An action without numbers takes none: they are dropped.
        if keys.isEmpty { return ["action": .str(name)] }
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
        if name == "listen" && numbers.isEmpty { return ["action": .str(name), "seconds": .int(60)] }
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
        // THINK even right after a word (over USB 11-09 "key enterTHINK: 已輸入…" went to the board as one key name);
        // DO only on its own, so "TODO:" stays text.
        guard let label = text.range(of: #""?\s*(THINK|(?<![A-Za-z])DO)\s*[:：]"#, options: .regularExpression) else { return text }
        return String(text[..<label.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    /// A done whose answer runs on over several lines (a forecast, a list): the lines under it that start no label are
    /// part of it. Build 116 over the cloud 11-10: "我的位置（龙岗区）的預報：" reached the cloud alone, the three days under
    /// it were dropped. They are joined into the one DO line, after a colon by a space, otherwise by "；".
    /// D77, y2 on 138: the last answer was "已完成全部49项任务的整理与汇报，结果如下：", an empty line, then the 49 results;
    /// the empty line ended the answer, the 49 were dropped and the owner got the run's raw notes instead. Only the next
    /// label ends an answer: an empty line or a ``` fence inside it is left out.
    static func joinedAnswers(_ text: String) -> String {
        var out: [String] = []
        var inDone = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if inDone, t.isEmpty || t.hasPrefix("```") { continue }
            if t.range(of: #"^(THINK|ZH|DO)\s*[:：]"#, options: .regularExpression) != nil {
                inDone = t.range(of: #"^DO\s*[:：]\s*done(\s|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
                out.append(line)
            } else if inDone, !t.isEmpty, !t.hasPrefix("```"), let last = out.last {
                let head = last.trimmingCharacters(in: .whitespaces)
                let glue = head.hasSuffix("：") || head.hasSuffix(":") || head.lowercased().hasSuffix("done") ? " " : "；"
                out[out.count - 1] = head + glue + t
            } else {
                inDone = false
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    /// 123 over the cloud 11-12: "note 广州今天最高温26°; tap 857 938" on one DO line kept the tap in the note (the answer
    /// read "广州今天最高温26°; tap 857 938") and the tap never happened. An action run on after a note is its own; so is
    /// a done after its full stop ("…体感11°。done 已完成九项…", the same day).
    static func splitNote(_ line: String) -> [String] {
        guard line.range(of: #"^\s*note\s"#, options: [.regularExpression, .caseInsensitive]) != nil,
              let cut = line.range(of: #"\s*[;；。]\s*(?=(tap|swipe|type|open|key|press|hold|back|home|wait|listen|done|fail|replan|path|circle)\b)"#,
                                   options: [.regularExpression, .caseInsensitive]) else { return [line] }
        return [String(line[..<cut.lowerBound]), String(line[cut.upperBound...])]
    }

    static func parseActions(_ text: String) throws -> [JObject] {
        // Some models join THINK and DO on one line (log24). Accept only that explicit labelled form.
        let normalized = firstCopy(joinedAnswers(text.replacingOccurrences(of: #"(?m)^(\s*THINK\s*[:：][^\n]*?[。.!?])\s*(DO\s*[:：])"#,
                                                                           with: "$1\n$2", options: .regularExpression)))
        let thought = firstGroup(#"^\s*THINK\s*[:：]\s*(.*?)\s*$"#, in: normalized, multiline: true)
        let zh = firstGroup(#"^\s*ZH\s*[:：]\s*(.*?)\s*$"#, in: normalized, multiline: true)
        var acts = try allGroups(#"^\s*DO\s*[:：]\s*(.*?)\s*$"#, in: normalized).flatMap(splitNote).map(parseCommand).prefix(6).map { $0 }
        guard !acts.isEmpty else { throw ParseError(message: "no DO line in reply: \(text.prefix(200))") }
        acts[0] = JObject([("thought", .str(thought ?? "")), ("thought_zh", .str(zh ?? ""))]).merging(acts[0])
        return acts
    }

    /// D179, x1 over the cloud 11-19 (148): a reply came back twice over ("THINK: 页面显示加购成功，接下来打开购物车… DO: tap
    /// 842 89THINK: 页面显示加购成功… DO: tap 842 89"); both taps went, and the answer later read the thought twice as "第二次
    /// 加购成功提示，最终数量未能确认". A reply whose first thought comes again is taken up to there: the rest is a copy.
    static func firstCopy(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"THINK\s*[:：]\s*"#) else { return text }
        let ns = text as NSString
        let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard found.count >= 2 else { return text }
        let start = found[0].range.location + found[0].range.length
        let end = ns.range(of: "\n", options: [], range: NSRange(location: start, length: ns.length - start)).location
        let first = ns.substring(with: NSRange(location: start, length: (end == NSNotFound ? ns.length : end) - start))
            .trimmingCharacters(in: .whitespaces)
        guard first.count >= 6 else { return text }
        for m in found.dropFirst() where ns.substring(from: m.range.location + m.range.length).hasPrefix(first) {
            return ns.substring(to: m.range.location)
        }
        return text
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
