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
    /// Shorter moves stay one `move` (a bow of a few units shows nothing and only slows the pointer).
    static let shortest = 300.0
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
}
