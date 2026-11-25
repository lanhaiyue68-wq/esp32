import Foundation

/// 171 (user 11-25 on 170's calibration: "全是直線，速度是很快，但是確實都是直線"): an iPad move as one Bezier curve, sent
/// as one `stroke` (the board runs it at its pace, no round trip between the pieces).
///
/// 170 sent one `move` and left the curve to the board, but an iPad home never uses the board's corner (`abort`), so
/// the board kept its curve inside the move's own box: a thin box for most moves, so a straight line. The app knows
/// where the pointer is (CommandChannel.padPos) and how big the screen is (padSpan), so it draws the curve itself:
/// a cubic Bezier bowed to one side by 10–18% of its length, the side and the bow random each time. All four control
/// points stay on the screen, so the whole curve does (a Bezier stays inside its control points): no push past an
/// edge (Notification Center, Home). The pieces add up exactly to the move, so where it lands is where a `move` lands.
enum PadCurve {
    /// Shorter moves stay one `move` (a bow of a few units shows nothing and only slows the pointer). 174: 640, the
    /// shortest fast move iPadOS takes at full gain; a shorter one goes straight, lengthened by CommandChannel.padShort.
    static let shortest = 640.0
    static let maxPieces = 30  // the board takes 40 pieces a stroke

    static func stroke(from p: (x: Int, y: Int), by d: (x: Int, y: Int), span: (w: Int, h: Int),
                       random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) -> String? {
        let len = hypot(Double(d.x), Double(d.y))
        guard len >= shortest else { return nil }
        let w = Double(span.w), h = Double(span.h)
        let p0 = (x: Double(p.x), y: Double(p.y))
        let p3 = (x: p0.x + Double(d.x), y: p0.y + Double(d.y))
        func onScreen(_ q: (x: Double, y: Double)) -> Bool { q.x >= 0 && q.x <= w && q.y >= 0 && q.y <= h }
        guard onScreen(p0), onScreen(p3) else { return nil }  // a push past an edge stays straight
        let ux = Double(d.x) / len, uy = Double(d.y) / len
        let a = random(0.25...0.38), z = random(0.62...0.75)
        let k1 = random(0.85...1.15), k2 = random(0.85...1.15)
        var bow = len * random(0.10...0.18)
        let first: Double = random(0...1) < 0.5 ? -1 : 1
        var controls: ((x: Double, y: Double), (x: Double, y: Double))?
        for _ in 0..<4 where controls == nil {  // near an edge: the other side, then a smaller bow
            for side in [first, -first] where controls == nil {
                let nx = -uy * side * bow, ny = ux * side * bow
                let c1 = (x: p0.x + Double(d.x) * a + nx * k1, y: p0.y + Double(d.y) * a + ny * k1)
                let c2 = (x: p0.x + Double(d.x) * z + nx * k2, y: p0.y + Double(d.y) * z + ny * k2)
                if onScreen(c1), onScreen(c2) { controls = (c1, c2) }
            }
            bow /= 2
        }
        guard let found = controls else { return nil }
        let (c1, c2) = found
        let n = min(maxPieces, max(8, Int(len / 80)))
        var pieces: [String] = []
        var last = (x: 0, y: 0)
        for i in 1...n {
            let t = Double(i) / Double(n), u = 1 - t
            let bx = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x
            let by = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y
            let q = i == n ? (x: d.x, y: d.y) : (x: Int((bx - p0.x).rounded()), y: Int((by - p0.y).rounded()))
            if q.x != last.x || q.y != last.y { pieces.append("\(q.x - last.x) \(q.y - last.y)") }
            last = q
        }
        return "stroke " + pieces.joined(separator: " ")
    }

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
