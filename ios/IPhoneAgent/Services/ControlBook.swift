import CoreGraphics
import Foundation

/// Learned buttons: what a control that worked looks like, so the next run finds it by its look instead of guessing.
/// A send that went out keeps a small gray patch around the spot that was tapped (any app: Claude's 发送 above the
/// keyboard, logs 11-06); a back button that worked after the back swipe did nothing keeps one too (WeChat's chevron:
/// 13 of 13 swipes failed, the same way every time). Later, the patch is searched for on the current screen; found,
/// the model is told where the control is and a tap for it lands on it. A learned spot that does nothing is counted,
/// and one that failed twice and more often than it worked is forgotten.
/// Local only: 24×24 gray patches of controls, never screenshots of content.
@MainActor final class ControlBook: ObservableObject {
    struct Control: Codable, Equatable, Identifiable {
        var id: String
        var role: String            // "send" or "back"
        var patch: [UInt8]          // side × side gray, cut from the frame scaled to `width` pixels across
        var x: Double, y: Double    // 0-1, where it worked
        var aspect: Double
        var worked: Int
        var failed: Int
        var updated: Date
    }
    struct Hit: Equatable { let id: String; let point: CGPoint; let score: Double }

    static let width = 180         // frames are compared at this width
    static let side = 24           // patch size in those pixels, about 0.13 of the screen width
    static let limit = 32
    static let minScore = 0.88     // normalized correlation a match needs
    static let margin = 0.03       // ...and by how much it beats any other spot on the screen
    static let minContrast = 14.0  // a flat patch (plain background) is not a control's look

    @Published private(set) var controls: [Control] = []
    var enabled = true
    var clock: () -> Date = Date.init
    private let file: URL?

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), data.count <= 512_000,
           let saved = try? JSONDecoder().decode([Control].self, from: data) {
            controls = saved.filter { $0.patch.count == Self.side * Self.side }
        }
        prune()
    }

    var count: Int { controls.count }
    func clear() { controls = []; save() }
    /// Forget every learned control of one role ("send" or "back").
    func forget(role: String) {
        let before = controls.count
        controls.removeAll { $0.role == role }
        if controls.count != before {
            DebugLog.write("learned \(role): \(before - controls.count) forgotten")
            save()
        }
    }

    /// The learned `role` control on this frame, the best match among those that worked before.
    func find(_ role: String, in frame: Data) -> Hit? {
        guard enabled, let img = Vision.image(frame), img.width > 0, img.height > 0 else { return nil }
        let aspect = Double(img.width) / Double(img.height)
        let known = controls.filter { $0.role == role && $0.worked > 0 && abs($0.aspect - aspect) <= 0.03 }
        guard !known.isEmpty else { return nil }
        let g = Self.gray(img)
        var best: Hit?
        for c in known {
            guard let m = Self.match(c.patch, in: g, nearY: c.y), m.1 > (best?.score ?? 0) else { continue }
            best = Hit(id: c.id, point: m.0, score: m.1)
        }
        return best
    }

    /// `role` worked when tapped at `point` on `frame` (the screen before the tap): remember how that spot looks.
    func learn(_ role: String, at point: CGPoint, on frame: Data) {
        guard enabled, let img = Vision.image(frame), img.width > 0, img.height > 0,
              (0...1).contains(point.x), (0...1).contains(point.y) else { return }
        let g = Self.gray(img)
        guard let patch = Self.patch(g, at: point) else {
            return DebugLog.write("learned \(role): the spot looks too plain to find again")
        }
        if let i = controls.firstIndex(where: { $0.role == role && abs($0.x - Double(point.x)) <= 0.04
                && abs($0.y - Double(point.y)) <= 0.04 && Self.ncc($0.patch, patch) >= Self.minScore }) {
            var c = controls.remove(at: i)
            c.worked += 1; c.updated = clock()
            controls.insert(c, at: 0)
            DebugLog.write(String(format: "learned %@: confirmed at (%.3f, %.3f), worked %d time(s)", role, point.x, point.y, c.worked))
        } else {
            controls.insert(Control(id: UUID().uuidString, role: role, patch: patch, x: Double(point.x), y: Double(point.y),
                                    aspect: Double(img.width) / Double(img.height), worked: 1, failed: 0, updated: clock()), at: 0)
            DebugLog.write(String(format: "learned %@: a new button at (%.3f, %.3f)", role, point.x, point.y))
        }
        prune()
        save()
    }

    func worked(_ id: String) {
        guard let i = controls.firstIndex(where: { $0.id == id }) else { return }
        controls[i].worked += 1
        controls[i].updated = clock()
        save()
    }

    /// The learned spot did nothing. Twice, and more often than it worked: forget it.
    func failed(_ id: String) {
        guard let i = controls.firstIndex(where: { $0.id == id }) else { return }
        controls[i].failed += 1
        let c = controls[i]
        if c.failed >= 2 && c.failed > c.worked {
            controls.remove(at: i)
            DebugLog.write(String(format: "learned %@ at (%.3f, %.3f) forgotten: it did nothing %d time(s)", c.role, c.x, c.y, c.failed))
        }
        save()
    }

    // MARK: - looks

    static func gray(_ img: CGImage) -> Vision.Gray {
        let h = max(side, Int((Double(width) * Double(img.height) / Double(img.width)).rounded()))
        return Vision.gray(img, width, h)
    }

    /// The side × side patch centred on `point`, kept inside the frame; nil when it is too plain to recognise.
    static func patch(_ g: Vision.Gray, at point: CGPoint) -> [UInt8]? {
        guard g.w >= side, g.h >= side else { return nil }
        let x0 = min(max(Int((Double(point.x) * Double(g.w)).rounded()) - side / 2, 0), g.w - side)
        let y0 = min(max(Int((Double(point.y) * Double(g.h)).rounded()) - side / 2, 0), g.h - side)
        var out = [UInt8](repeating: 0, count: side * side)
        for r in 0..<side { for c in 0..<side { out[r * side + c] = g.px[(y0 + r) * g.w + x0 + c] } }
        let n = Double(out.count), mean = out.reduce(0.0) { $0 + Double($1) } / n
        let sd = (out.reduce(0.0) { $0 + (Double($1) - mean) * (Double($1) - mean) } / n).squareRoot()
        return sd >= minContrast ? out : nil
    }

    /// Normalized correlation of two equal patches, -1...1.
    static func ncc(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        let n = Double(a.count)
        let ma = a.reduce(0.0) { $0 + Double($1) } / n, mb = b.reduce(0.0) { $0 + Double($1) } / n
        var ab = 0.0, aa = 0.0, bb = 0.0
        for i in 0..<a.count {
            let x = Double(a[i]) - ma, y = Double(b[i]) - mb
            ab += x * y; aa += x * x; bb += y * y
        }
        return aa > 0 && bb > 0 ? ab / (aa * bb).squareRoot() : -1
    }

    /// Where `patch` best matches on `g`, searched across the width and within a quarter of the screen of the row it
    /// was learned on (the keyboard and a growing input box move it up and down). The centre (0-1) and its score, when
    /// it clears minScore and beats every spot away from it by `margin`.
    static func match(_ patch: [UInt8], in g: Vision.Gray, nearY y: Double) -> (CGPoint, Double)? {
        guard patch.count == side * side, g.w >= side, g.h >= side else { return nil }
        let n = Double(side * side)
        let pm = patch.reduce(0.0) { $0 + Double($1) } / n
        let pz = patch.map { Double($0) - pm }
        let pn = pz.reduce(0.0) { $0 + $1 * $1 }.squareRoot()
        guard pn > 0 else { return nil }
        // Integral images of the frame and its squares give each window's mean and spread in constant time.
        let w = g.w, iw = w + 1
        var s = [Double](repeating: 0, count: iw * (g.h + 1)), q = s
        for r in 0..<g.h {
            var rs = 0.0, rq = 0.0
            for c in 0..<w {
                let v = Double(g.px[r * w + c])
                rs += v; rq += v * v
                s[(r + 1) * iw + c + 1] = s[r * iw + c + 1] + rs
                q[(r + 1) * iw + c + 1] = q[r * iw + c + 1] + rq
            }
        }
        func box(_ t: [Double], _ x: Int, _ y: Int) -> Double {
            t[(y + side) * iw + x + side] - t[y * iw + x + side] - t[(y + side) * iw + x] + t[y * iw + x]
        }
        let centre = Int((y * Double(g.h)).rounded()) - side / 2, reach = g.h / 4
        let top = max(0, centre - reach), bottom = min(g.h - side, centre + reach)
        guard top <= bottom else { return nil }
        var best = (score: -1.0, x: 0, y: 0), second = -1.0
        g.px.withUnsafeBufferPointer { px in
            pz.withUnsafeBufferPointer { pzp in
                for wy in top...bottom {
                    for wx in 0...(w - side) {
                        let sum = box(s, wx, wy), sq = box(q, wx, wy)
                        let spread = sq - sum * sum / n
                        guard spread > 1 else { continue }
                        var cross = 0.0
                        for r in 0..<side {
                            let row = (wy + r) * w + wx, prow = r * side
                            for c in 0..<side { cross += pzp[prow + c] * Double(px[row + c]) }
                        }
                        let score = cross / (pn * spread.squareRoot())
                        let far = abs(wx - best.x) > side / 2 || abs(wy - best.y) > side / 2
                        if score > best.score {
                            if far { second = max(second, best.score) }
                            best = (score, wx, wy)
                        } else if far, score > second {
                            second = score
                        }
                    }
                }
            }
        }
        guard best.score >= minScore, best.score - second >= margin else { return nil }
        return (CGPoint(x: (Double(best.x) + Double(side) / 2) / Double(w),
                        y: (Double(best.y) + Double(side) / 2) / Double(g.h)), best.score)
    }

    private func prune() {
        let cutoff = clock().addingTimeInterval(-60 * 86400)
        controls = Array(controls.filter { $0.updated >= cutoff }.prefix(Self.limit))
    }

    private func save() {
        guard let file else { return }
        do { try JSONEncoder().encode(controls).write(to: file, options: .atomic) }
        catch { DebugLog.write("learned buttons could not be saved: \(error.localizedDescription)") }
    }
}
