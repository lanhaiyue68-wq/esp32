import Foundation

/// 171 (user 11-25 on 170's calibration: "全是直線，速度是很快，但是確實都是直線"): an iPad move as one Bezier curve, sent
/// as one `stroke` (the board runs it at its pace, no round trip between the pieces).
///
/// 170 sent one `move` and left the curve to the board, but an iPad home never uses the board's corner (`abort`), so
/// the board kept its curve inside the move's own box: a thin box for most moves, so a straight line. The app knows
/// where the pointer is (CommandChannel.padPos) and how big the screen is (padSpan), so it draws the curve itself:
/// a cubic Bezier bowed to one side, the side and the bow random each time. All four control points stay on the
/// screen, so the whole curve does (a Bezier stays inside its control points): no push past an edge (Notification
/// Center, Home).
///
/// 187 (user 11-26: "不論你點什么，都一次性點好…每次點目標地方的時候，都是會在中間停頓一下"): a curve whose pieces add up
/// to the move does not land where the move does. Measured on the customer's iPad 9 (辅助触控 on, v41, 60 / 30 ms),
/// the same move again and again to ±1 px: straight it lands exactly; bowed it lands toward the bow by ~0.22 of the
/// bow (control points `b` off the line: 14 px of a 0.14 bow, 4 px of a 0.05 one, either side) and short by ~0.8 of
/// the length the bow adds (2 % at 0.12). So the bow is 6–12 % (was 10–18 %, k1 ≠ k2 made it worse: 17 px at 0.18) and
/// the end aimed at is moved against both: 10 hops between blank spots then landed within 8 px but two long ones (17).
///
/// 188 (B42, user 11-27 on 187: "你到那個位置的時候，還要稍微微調一下，然后才點。你這也叫一次到位嗎？"): 187 still
/// corrected 3 of 4 diagonal taps. Raw strokes sent from the computer (moves only, Echo's home page, 11-27) landed the
/// same twice to 1–6 px, and the bow's share was half of 187's: ~0.10 of the offset toward the bow (6 %: ~4 px, 12 %:
/// ~10 px, either side, either way), and a 6 % bow comes no shorter (12 % came 0–11 px short by direction). With a
/// 5–8 % bow, 0.10 across and nothing along, 40 hops to random spots landed 31 inside the 0.008 tolerance (187's
/// constants ~1 in 4); the rest is ±1 % that no per-direction gain removed. The user: "弧度還是要隨機，包括每一次的長度
/// 都要隨機…可以小一點，但是不能固定": the bow, its side, where it bulges and the number of pieces are all random.
enum PadCurve {
    /// 174–196: shorter moves went as one straight `move`. 197 (N91; user 11-28: 「你的貝塞爾曲綫怎麽沒用上」「必須强制走！
    /// 不要設立門檻！」; Echo 195: every hop inside one window was a straight line, the board keeping its curve inside the
    /// move's own box): every move is a curve, however short. Under `shortest` the bow is 8–16 % (5–8 % of a short move
    /// shows nothing) and the whole curve is lengthened by `scale` (CommandChannel.padShort's ratio: iPadOS starts a short
    /// move slower). Measured from the computer on Echo 195 (11-28 02:31, bz.py): 10 such curves, the shortest ~380
    /// units, all on their buttons at the first stop (within 0.010).
    static let shortest = 640.0
    static let maxPieces = 30  // the board takes 40 pieces a stroke

    static func stroke(from p: (x: Int, y: Int), by d: (x: Int, y: Int), span: (w: Int, h: Int), scale: Double = 1,
                       random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> String? {
        let len = hypot(Double(d.x), Double(d.y))
        guard len > 0 else { return nil }
        let w = Double(span.w), h = Double(span.h)
        let p0 = (x: Double(p.x), y: Double(p.y))
        let p3 = (x: p0.x + Double(d.x), y: p0.y + Double(d.y))
        func onScreen(_ q: (x: Double, y: Double)) -> Bool { q.x >= 0 && q.x <= w && q.y >= 0 && q.y <= h }
        guard onScreen(p0), onScreen(p3) else { return nil }  // a push past an edge: padPushParts
        let ux = Double(d.x) / len, uy = Double(d.y) / len
        let a = random(0.25...0.38), z = 1 - a  // the same either end: the bow goes out and comes back alike
        var bow = len * (len < shortest ? random(0.08...0.16) : random(0.05...0.08))  // 188: was 0.06–0.12
        let first: Double = random(0...1) < 0.5 ? -1 : 1
        var found: (c1: (x: Double, y: Double), c2: (x: Double, y: Double), off: (x: Double, y: Double))?
        // near an edge: the other side, then a smaller bow; never straight (both ends are on the screen, so a small
        // enough bow always is: a Bezier stays inside its control points)
        for _ in 0..<10 where found == nil {
            for side in [first, -first] where found == nil {
                let off = (x: -uy * side * bow, y: ux * side * bow)
                let c1 = (x: p0.x + Double(d.x) * a + off.x, y: p0.y + Double(d.y) * a + off.y)
                let c2 = (x: p0.x + Double(d.x) * z + off.x, y: p0.y + Double(d.y) * z + off.y)
                if onScreen(c1), onScreen(c2) { found = (c1, c2, off) }
            }
            bow /= 2
        }
        guard let picked = found else { return nil }
        let (c1, c2, off) = (picked.c1, picked.c2, picked.off)
        func point(_ t: Double, _ c1: (x: Double, y: Double), _ c2: (x: Double, y: Double),
                   _ p3: (x: Double, y: Double)) -> (x: Double, y: Double) {
            let u = 1 - t
            return (x: u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x,
                    y: u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y)
        }
        // The end aimed at: further by what the bow's extra length loses, back against the bow by what of it stays.
        var arc = 0.0, at = p0
        for i in 1...60 { let q = point(Double(i) / 60, c1, c2, p3); arc += hypot(q.x - at.x, q.y - at.y); at = q }
        let further = 1 + alongLoss * max(0, arc / len - 1)
        let aim = (x: min(max(p0.x + Double(d.x) * further - acrossKept * off.x, 0), w),
                   y: min(max(p0.y + Double(d.y) * further - acrossKept * off.y, 0), h))
        let e = (x: aim.x - p0.x, y: aim.y - p0.y)
        let a1 = (x: p0.x + e.x * a + off.x, y: p0.y + e.y * a + off.y)
        let a2 = (x: p0.x + e.x * z + off.x, y: p0.y + e.y * z + off.y)
        let k = max(1, scale)  // 197 (N91): a short curve sent longer, as padShort sends a short move
        let end = (x: Int((e.x * k).rounded()), y: Int((e.y * k).rounded()))
        let n = min(maxPieces, max(8, Int(len * k / 80 * random(0.9...1.1))))  // 188: how long it takes varies too
        var pieces: [String] = []
        var last = (x: 0, y: 0)
        for i in 1...n {
            let b = point(Double(i) / Double(n), a1, a2, aim)
            let q = i == n ? end : (x: Int(((b.x - p0.x) * k).rounded()), y: Int(((b.y - p0.y) * k).rounded()))
            if q.x != last.x || q.y != last.y { pieces.append("\(q.x - last.x) \(q.y - last.y)") }
            last = q
        }
        return "stroke " + pieces.joined(separator: " ")
    }
    /// 199 (user 11-28, Echo 198: 「全程，不論干什么，都要用貝塞爾曲線」; the pointer's search nudged and stepped by straight
    /// `move`s while its place was not known — ±141 sideways, 1434 down — four times in an hour): a move from a place not
    /// known as a curve all the same, drawn as if from the middle of a screen big enough to hold it (its bow is the
    /// move's own; only its staying on the screen needed the place).
    static func strokeAnywhere(by d: (x: Int, y: Int), span: (w: Int, h: Int), scale: Double = 1,
                               random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> String? {
        let big = (w: max(span.w, 2 * abs(d.x) + 2), h: max(span.h, 2 * abs(d.y) + 2))
        return stroke(from: (big.w / 2, big.h / 2), by: d, span: big, scale: scale, random: random)
    }

    /// 187: of the bow's offset (control points off the line), the share a curved move lands off toward it.
    /// 188: 0.10 measured (was 0.22, which pushed every curve ~as far the other way).
    static let acrossKept = 0.10
    /// 187: of the length a bow adds to the path, the share a curved move comes short by.
    /// 188: a bow of 5–8 % comes no shorter (was 0.8).
    static let alongLoss = 0.0

    // 174 (user 11-25: "滑屏幕左边的时候，贝塞尔曲线往左滑，就像我们的大拇指滑屏幕一样；右边的时候用右滑"): an iPad swipe
    // goes as a thumb's does. It sets off the way it was asked (so a list locks onto that direction, and a row is
    // never pushed sideways into its 删除 buttons) and bends toward the hand, as a thumb turns about its base: on the
    // left half to the left, on the right half to the right (a sideways swipe bends down). Up and down a swipe goes
    // exactly as far as asked; only its end moves sideways, 6–12 % of its length, and stays inside the screen and on
    // its own half (one pane of a split screen).

    /// Where a thumb's swipe from `a` toward `b` (screen fractions) ends; nil when too short to show a bend.
    static func thumbEnd(from a: (x: Double, y: Double), to b: (x: Double, y: Double), span: (w: Int, h: Int),
                         random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> (x: Double, y: Double)? {
        let w = Double(span.w), h = Double(span.h)
        let ux = (b.x - a.x) * w, uy = (b.y - a.y) * h
        let len = hypot(ux, uy)
        guard len >= shortest, w > 0, h > 0 else { return nil }
        let bend = len * random(0.06...0.12)
        if abs(uy) >= abs(ux) {
            let right = (a.x + b.x) / 2 >= 0.5
            let x = right ? min(b.x + bend / w, 0.97) : max(b.x - bend / w, 0.03)
            return (right ? max(x, b.x) : min(x, b.x), b.y)
        }
        return (b.x, max(b.y, min(b.y + bend / h, 0.9)))  // sideways: down, toward the hand, never into the home bar
    }

    /// The stroke's pieces (units) from `a` to the bent end `e`: it leaves toward `b` and turns as it goes.
    static func thumbPieces(from a: (Int, Int), toward b: (Int, Int), end e: (Int, Int), step: Int) -> [(Int, Int)] {
        let p0 = (x: Double(a.0), y: Double(a.1)), asked = (x: Double(b.0 - a.0), y: Double(b.1 - a.1))
        let side = (x: Double(e.0 - b.0), y: Double(e.1 - b.1))
        let c1 = (x: p0.x + asked.x * 0.4, y: p0.y + asked.y * 0.4)
        let c2 = (x: p0.x + asked.x * 0.8 + side.x * 0.35, y: p0.y + asked.y * 0.8 + side.y * 0.35)
        let p3 = (x: Double(e.0), y: Double(e.1))
        let n = min(38, max(4, Int((hypot(asked.x, asked.y) / Double(max(1, step))).rounded(.up))))
        var out: [(Int, Int)] = []
        var last = (0, 0)
        for i in 1...n {
            let t = Double(i) / Double(n), u = 1 - t
            let bx = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x
            let by = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y
            let q = i == n ? (e.0 - a.0, e.1 - a.1) : (Int((bx - p0.x).rounded()), Int((by - p0.y).rounded()))
            if q != last { out.append((q.0 - last.0, q.1 - last.1)) }
            last = q
        }
        return out
    }
}
