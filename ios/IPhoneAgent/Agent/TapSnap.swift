import CoreGraphics
import Foundation

/// 197 (N90, Echo 195 11-28 17:53: on the iPad's split screen the planner's own taps fell 16–29 of 1000 low and hit the
/// next button — WeChat's ＋ opened the search bar, 发起群聊 opened 记录面聊): a model's tap whose thought names a
/// label read on the screen close to it (0.05 up or down, 0.25 across) goes to that label's middle.
enum TapSnap {
    /// The labels a thought names: words in quotes (「」 “” "" ‘’ 『』), and the Chinese words right after 点 / 點 / 选 /
    /// 選 / 打开 / 打開 / tap / click (two to eight characters).
    static func labels(_ thought: String) -> [String] {
        var out: [String] = []
        let pairs: [(Character, Character)] = [("「", "」"), ("“", "”"), ("\"", "\""), ("‘", "’"), ("『", "』")]
        for (open, close) in pairs {
            var rest = Substring(thought)
            while let a = rest.firstIndex(of: open) {
                let after = rest[rest.index(after: a)...]
                guard let b = after.firstIndex(of: close) else { break }
                let word = String(after[..<b]).trimmingCharacters(in: .whitespaces)
                if (2...12).contains(word.count) { out.append(word) }
                rest = after[after.index(after: b)...]
            }
        }
        if let re = try? NSRegularExpression(pattern: #"(?:点击|點擊|点|點|选择|選擇|选|選|打开|打開|tap|click)\s*([\p{Han}]{2,8})"#,
                                              options: [.caseInsensitive]) {
            let ns = thought as NSString
            for m in re.matches(in: thought, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges > 1 {
                out.append(ns.substring(with: m.range(at: 1)))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Where the tap at (x, y) (screen fractions) should go: the middle of the nearest piece read that holds a label the
    /// thought names, near it; nil when there is none or the tap is on that piece already.
    static func spot(x: Double, y: Double, thought: String, pieces: [CandidatePicker.Piece]) -> CGPoint? {
        let names = labels(thought)
        guard !names.isEmpty else { return nil }
        let p = CGPoint(x: x, y: y)
        let hits = pieces.filter { piece in
            let t = piece.text.filter { !$0.isWhitespace }
            return names.contains { t.contains($0.filter { !$0.isWhitespace }) }
                && abs(Double(piece.box.midY) - y) <= 0.05 && abs(Double(piece.box.midX) - x) <= 0.25
        }
        guard let best = hits.min(by: { hypot($0.box.midX - p.x, $0.box.midY - p.y) < hypot($1.box.midX - p.x, $1.box.midY - p.y) }),
              !best.box.insetBy(dx: 0, dy: best.box.height * 0.2).contains(p) else { return nil }
        return CGPoint(x: best.box.midX, y: best.box.midY)
    }
}
