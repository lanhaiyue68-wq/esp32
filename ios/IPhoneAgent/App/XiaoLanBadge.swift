import UIKit

/// 193 (N46, Echo 192 11-27 18:24 and 18:28 首爾: 「蓝海乐's red mark read alone: no number ()」 twice — Vision read
/// nothing at all off the corner made four times larger, the white digit on the red disc — and 「only the newest N」
/// fell back to the old guess, which answered lines read long before): the number on a chat's red mark read off its
/// pixels, no OCR. The disc is the largest red patch in the badge area; its digits are the light pixels inside it,
/// each compared, at its own size, with the system font's digits drawn here (the apps draw their marks in it), a
/// digit with a closed loop never taken for one without (holes).
/// Checked off the device on the iPad's own marks (11-27 evening, the watch off: WeChat 3, 6, 9, 20; WeCom 2, 5, 8, 17 —
/// all read right; by shape alone WeChat's 6 was read 5) and on drawn marks, 1–99.
enum XiaoLanBadge {
    /// A digit's picture: light 0–1 per pixel, its width over its height.
    struct Glyph { let w: Int; let h: Int; let v: [Double]; var aspect: Double { Double(w) / Double(h) } }

    /// The mark's red: WeChat ~(243, 84, 81), WeCom ~(227, 77, 69).
    static func red(_ r: Int, _ g: Int, _ b: Int) -> Bool { r >= 170 && g <= 140 && b <= 140 && r - g >= 80 && r - b >= 70 }

    /// The number on the mark in `area` (fractions of the picture); nil: no mark there, a bare dot, or digits not told
    /// apart surely enough (the caller then takes only what came after the last line read). 「99+」 reads 99.
    static func number(_ px: WatchOCR.Pixels, in area: CGRect) -> Int? {
        guard let found = Self.glyphs(px, in: area), !found.isEmpty, found.count <= 3 else { return nil }
        var digits = ""
        for g in found {
            // 0.25: the iPad's own marks scored 0.06–0.19 against another font's digits (WeCom's 「5」 0.189), drawn
            // ones under 0.14
            guard let d = classify(g), d.distance < 0.25 else { return nil }
            digits += String(d.digit)
        }
        guard let n = Int(digits), n > 0 else { return nil }
        return min(n, 99)
    }

    /// The digits on the mark in `area`, left to right, as light 0–1; nil: no mark (no disc of red there).
    static func glyphs(_ px: WatchOCR.Pixels, in area: CGRect) -> [Glyph]? {
        let x0 = max(0, Int(Double(area.minX) * Double(px.w))), x1 = min(px.w, Int(Double(area.maxX) * Double(px.w)))
        let y0 = max(0, Int(Double(area.minY) * Double(px.h))), y1 = min(px.h, Int(Double(area.maxY) * Double(px.h)))
        let w = x1 - x0, h = y1 - y0
        guard w > 6, h > 6 else { return nil }
        func rgb(_ i: Int, _ j: Int) -> (Int, Int, Int) {
            let k = ((y0 + j) * px.w + x0 + i) * 4
            return (Int(px.bytes[k]), Int(px.bytes[k + 1]), Int(px.bytes[k + 2]))
        }
        var isRed = [Bool](repeating: false, count: w * h)
        for j in 0..<h { for i in 0..<w { let c = rgb(i, j); isRed[j * w + i] = red(c.0, c.1, c.2) } }
        // the largest red patch (4-connected)
        var seen = [Bool](repeating: false, count: w * h)
        var best: [Int] = []
        for start in 0..<(w * h) where isRed[start] && !seen[start] {
            var stack = [start], patch: [Int] = []
            seen[start] = true
            while let k = stack.popLast() {
                patch.append(k)
                let i = k % w, j = k / w
                for (a, b) in [(i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)] where a >= 0 && a < w && b >= 0 && b < h {
                    let n = b * w + a
                    if isRed[n] && !seen[n] { seen[n] = true; stack.append(n) }
                }
            }
            if patch.count > best.count { best = patch }
        }
        guard best.count >= 20 else { return nil }
        let bx0 = best.map { $0 % w }.min()!, bx1 = best.map { $0 % w }.max()!
        let by0 = best.map { $0 / w }.min()!, by1 = best.map { $0 / w }.max()!
        let bw = bx1 - bx0 + 1, bh = by1 - by0 + 1
        // a disc (or 「99+」's pill) with its digits: most of its box red (measured 0.65 for 「2」), never an avatar's
        // red scrap
        guard bh >= 8, Double(bw) >= 0.7 * Double(bh), Double(bw) <= 3.2 * Double(bh),
              Double(best.count) >= 0.45 * Double(bw * bh) else { return nil }
        let greens = best.map { k in rgb(k % w, k / w).1 }.sorted()
        let redGreen = Double(greens[greens.count / 2])
        // light inside the disc: between the row's first and last red pixel, how far from the red toward white
        var light = [Double](repeating: 0, count: bw * bh)
        for j in 0..<bh {
            let row = (0..<bw).map { isRed[(by0 + j) * w + bx0 + $0] }
            guard let l = row.firstIndex(of: true), let r = row.lastIndex(of: true), r - l > 1 else { continue }
            for i in (l + 1)..<r {
                let c = rgb(bx0 + i, by0 + j)
                light[j * bw + i] = min(1, max(0, (Double(min(c.1, c.2)) - redGreen) / (255 - redGreen)))
            }
        }
        return split(light, w: bw, h: bh)
    }

    /// The digits of a disc's light pixels, left to right: runs of columns with light in them, a run as wide as it is
    /// tall cut in two at its faintest column (two digits touching), specks left out.
    static func split(_ light: [Double], w: Int, h: Int) -> [Glyph] {
        let on = 0.45
        func lit(_ i: Int, _ rows: Range<Int>) -> Bool { rows.contains { light[$0 * w + i] >= on } }
        func rowsOf(_ cols: Range<Int>) -> Range<Int>? {
            let rs = (0..<h).filter { j in cols.contains { light[j * w + $0] >= on } }
            guard let a = rs.first, let b = rs.last else { return nil }
            return a..<(b + 1)
        }
        var runs: [Range<Int>] = []
        var i = 0
        while i < w {
            if lit(i, 0..<h) {
                var k = i
                while k < w && lit(k, 0..<h) { k += 1 }
                runs.append(i..<k)
                i = k
            } else { i += 1 }
        }
        var parts: [(cols: Range<Int>, rows: Range<Int>)] = []
        for run in runs {
            guard let rows = rowsOf(run), Double(rows.count) >= 0.33 * Double(h) else { continue }
            if Double(run.count) > 1.05 * Double(rows.count), run.count >= 4 {
                let third = run.count / 3
                let middle = (run.lowerBound + third)..<(run.upperBound - third)
                let cut = middle.min { a, b in
                    rows.reduce(0.0) { $0 + light[$1 * w + a] } < rows.reduce(0.0) { $0 + light[$1 * w + b] }
                } ?? run.lowerBound + run.count / 2
                for half in [run.lowerBound..<cut, (cut + 1)..<run.upperBound] where !half.isEmpty {
                    if let r = rowsOf(half) { parts.append((half, r)) }
                }
            } else {
                parts.append((run, rows))
            }
        }
        return parts.map { p in
            Glyph(w: p.cols.count, h: p.rows.count, v: p.rows.flatMap { j in p.cols.map { light[j * w + $0] } })
        }
    }

    /// The digit a glyph is most like: each template shrunk to the glyph's size (box filter), the mean squared
    /// difference, and their widths over heights compared.
    /// 193 (Echo 192's marks read on the iPad 11-27 evening: WeChat's 「6」 was taken for 5 by shape alone, 0.093 to
    /// 0.098): a glyph with a closed loop is never 1, 2, 3, 5 or 7; with two, only 8. No loop seen says nothing (a thin
    /// font's loops may close up at this size).
    static func classify(_ g: Glyph) -> (digit: Character, distance: Double)? {
        let loops = holes(g)
        let allowed: Set<Character> = loops >= 2 ? ["8"] : (loops == 1 ? ["0", "4", "6", "8", "9"] : Set("0123456789"))
        var best: (Character, Double)?
        for (digit, big) in templates where allowed.contains(digit) {
            let t = shrink(big, w: g.w, h: g.h)
            var ssd = 0.0
            for k in 0..<g.v.count { let d = g.v[k] - t[k]; ssd += d * d }
            let score = ssd / Double(g.v.count) + 0.3 * pow(g.aspect - big.aspect, 2)
            if best == nil || score < best!.1 { best = (digit, score) }
        }
        return best.map { (digit: $0.0, distance: $0.1) }
    }

    /// The closed loops in a glyph (0, 4, 6 and 9 one, 8 two): the glyph made three times larger (bilinear), ink at half
    /// light; a patch of no ink, two pixels or more, touching none of its edges is a loop. Measured on the iPad's marks:
    /// 「6」 one (its middle at 0.64 of the height), 「9」 one (0.29), 「8」 two, 「20」's 0 one; 「3」「2」「5」「1」「7」 none.
    static func holes(_ g: Glyph, scale k: Int = 3) -> Int {
        let W = g.w * k, H = g.h * k
        guard W > 2, H > 2 else { return 0 }
        func v(_ y: Int, _ x: Int) -> Double { g.v[y * g.w + x] }
        func at(_ y: Int, _ x: Int) -> Double {
            let fy = min(max((Double(y) + 0.5) / Double(k) - 0.5, 0), Double(g.h - 1))
            let fx = min(max((Double(x) + 0.5) / Double(k) - 0.5, 0), Double(g.w - 1))
            let y0 = Int(fy), x0 = Int(fx), y1 = min(y0 + 1, g.h - 1), x1 = min(x0 + 1, g.w - 1)
            let dy = fy - Double(y0), dx = fx - Double(x0)
            let top = v(y0, x0) * (1 - dx) + v(y0, x1) * dx
            let bottom = v(y1, x0) * (1 - dx) + v(y1, x1) * dx
            return top * (1 - dy) + bottom * dy
        }
        var ink = [Bool](repeating: false, count: W * H)
        for y in 0..<H { for x in 0..<W { ink[y * W + x] = at(y, x) >= 0.5 } }
        var seen = [Bool](repeating: false, count: W * H)
        var loops = 0
        for start in 0..<(W * H) where !ink[start] && !seen[start] {
            var stack = [start], size = 0, edge = false
            seen[start] = true
            while let n = stack.popLast() {
                size += 1
                let x = n % W, y = n / W
                if x == 0 || y == 0 || x == W - 1 || y == H - 1 { edge = true }
                for (a, b) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where a >= 0 && a < W && b >= 0 && b < H {
                    let m = b * W + a
                    if !ink[m] && !seen[m] { seen[m] = true; stack.append(m) }
                }
            }
            if !edge && size >= 2 { loops += 1 }
        }
        return loops
    }

    /// `big` made `w`×`h` by averaging the pixels each new one covers.
    static func shrink(_ big: Glyph, w: Int, h: Int) -> [Double] {
        var out = [Double](repeating: 0, count: w * h)
        for j in 0..<h {
            let a0 = Double(j) * Double(big.h) / Double(h), a1 = Double(j + 1) * Double(big.h) / Double(h)
            let ys = Int(a0)..<max(Int(a0) + 1, Int(a1))
            for i in 0..<w {
                let b0 = Double(i) * Double(big.w) / Double(w), b1 = Double(i + 1) * Double(big.w) / Double(w)
                let xs = Int(b0)..<max(Int(b0) + 1, Int(b1))
                var s = 0.0, n = 0.0
                for y in ys { for x in xs { s += big.v[min(y, big.h - 1) * big.w + min(x, big.w - 1)]; n += 1 } }
                out[j * w + i] = s / n
            }
        }
        return out
    }

    /// The system font's digits, white on black, cut to their ink, drawn once.
    static let templates: [(Character, Glyph)] = "0123456789".compactMap { d in drawn(d).map { (d, $0) } }

    static func drawn(_ digit: Character, size: CGFloat = 96, weight: UIFont.Weight = .semibold) -> Glyph? {
        let side = Int(size * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            (String(digit) as NSString).draw(at: CGPoint(x: size / 4, y: size / 4),
                                             withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight),
                                                              .foregroundColor: UIColor.white])
        }
        guard let data = image.pngData(), let px = WatchOCR.Pixels(data) else { return nil }
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<px.h { for x in 0..<px.w where px.bytes[(y * px.w + x) * 4 + 1] > 127 { xs.append(x); ys.append(y) } }
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        var v = [Double](repeating: 0, count: w * h)
        for j in 0..<h { for i in 0..<w { v[j * w + i] = Double(px.bytes[((y0 + j) * px.w + x0 + i) * 4 + 1]) / 255 } }
        return Glyph(w: w, h: h, v: v)
    }
}
