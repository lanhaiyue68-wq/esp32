import CoreGraphics
import Foundation
import ImageIO

/// Small image checks on screen frames: did the screen change, and where is the pointer. Port of vision.py.
enum Vision {
    /// A coarse local page signature. Keep neither screenshots nor readable text in case memory.
    static func experienceScene(_ data: Data) -> [UInt8]? {
        guard let image = image(data) else { return nil }
        return gray(image, 8, 8).px.map { $0 / 16 }
    }

    /// Top share of the frame never compared: the status bar, where the Dynamic Island shows our Live Activity.
    static let topMask = 0.06

    /// A grayscale bitmap (PIL "L" weights), row-major.
    struct Gray {
        let w: Int, h: Int
        let px: [UInt8]
    }

    static func image(_ jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Share of WeChat-red pixels (the unread badge, about #FA5151) in `rect`, fractions of the image (top-left origin).
    static func redShare(_ img: CGImage, in rect: CGRect) -> Double {
        let full = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        let r = CGRect(x: rect.minX * full.width, y: rect.minY * full.height,
                       width: rect.width * full.width, height: rect.height * full.height).integral.intersection(full)
        guard !r.isEmpty, let crop = img.cropping(to: r) else { return 0 }
        let w = crop.width, h = crop.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var red = 0
        for i in 0..<(w * h) {
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            if r > 200 && g < 130 && b < 130 && r - g > 100 { red += 1 }
        }
        return Double(red) / Double(w * h)
    }

    /// The image drawn at w x h (bilinear-ish scaling), converted to gray like PIL's convert("L").
    static func gray(_ img: CGImage, _ w: Int, _ h: Int) -> Gray {
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        var px = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let r = Int(rgba[i * 4]), g = Int(rgba[i * 4 + 1]), b = Int(rgba[i * 4 + 2])
            px[i] = UInt8((r * 299 + g * 587 + b * 114 + 500) / 1000)
        }
        return Gray(w: w, h: h, px: px)
    }

    /// A letter keyboard by its layout, light or dark: a row of ten even keys with a row of nine one key pitch below.
    /// Text recognition did not read the dark keyboard's single letters at night (logs46), so typing was refused
    /// with the keyboard up. Keys are brighter than the tray in both appearances.
    static func letterKeyboard(_ jpeg: Data) -> Bool {
        guard let img = image(jpeg), img.width > 0, img.height > img.width else { return false }
        let w = 296, h = Int((Double(w) * Double(img.height) / Double(img.width)).rounded())
        let g = gray(img, w, h)
        var tens: [Int] = [], nines: [Int] = []
        for y in Int(0.5 * Double(h))..<Int(0.97 * Double(h)) {
            let keys = brightRuns(g.px[(y * w)..<((y + 1) * w)], w)
            if evenKeys(keys, w, 10) { tens.append(y) }
            if evenKeys(keys, w, 9) { nines.append(y) }
        }
        // A key row is a band of matching scan lines, not a stray one.
        func bands(_ ys: [Int]) -> [Double] {
            var out: [(Int, Int)] = []
            for y in ys {
                if let last = out.last, y - last.1 <= 2 { out[out.count - 1].1 = y } else { out.append((y, y)) }
            }
            return out.filter { Double($0.1 - $0.0 + 1) >= 0.008 * Double(h) }.map { Double($0.0 + $0.1) / 2 }
        }
        let nineRows = bands(nines)
        return bands(tens).contains { top in nineRows.contains { (0.04...0.11).contains(($0 - top) / Double(h)) } }
    }

    /// The runs brighter than the middle of the line's 10th and 90th percentiles; none when the line is flat.
    private static func brightRuns(_ line: ArraySlice<UInt8>, _ w: Int) -> [(Int, Int)] {
        let sorted = line.sorted()
        let lo = Int(sorted[w / 10]), hi = Int(sorted[w * 9 / 10])
        guard hi - lo >= 15 else { return [] }
        let middle = (lo + hi) / 2
        var runs: [(Int, Int)] = [], start: Int?
        for (x, v) in line.enumerated() {
            if Int(v) > middle { if start == nil { start = x } } else if let s = start { runs.append((s, x)); start = nil }
        }
        if let s = start { runs.append((s, w)) }
        return runs
    }

    /// Exactly n key-sized runs of even width and pitch across most of the line, and nothing wider.
    private static func evenKeys(_ runs: [(Int, Int)], _ w: Int, _ n: Int) -> Bool {
        let small = 0.05 * Double(w), large = 0.12 * Double(w)
        guard !runs.contains(where: { Double($0.1 - $0.0) > large }) else { return false }
        let keys = runs.filter { Double($0.1 - $0.0) >= small }
        guard keys.count == n else { return false }
        func spread(_ v: [Double]) -> Double {
            let mean = v.reduce(0, +) / Double(v.count)
            return sqrt(v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count)) / mean
        }
        let widths = keys.map { Double($0.1 - $0.0) }, centres = keys.map { Double($0.0 + $0.1) / 2 }
        let pitch = zip(centres.dropFirst(), centres).map { $0 - $1 }
        return spread(widths) < 0.15 && spread(pitch) < 0.12 && centres.last! - centres.first! > 0.6 * Double(w)
    }

    /// True when the screen content changed, including small things such as a checkmark.
    ///
    /// `ignore` lists screen points (fractions) where the pointer was or went: those spots are masked, so pointer
    /// moves never count. The status bar (clock) is ignored too.
    /// caret: a change that is only one thin upright stroke (a blinking text cursor) is no change. Off for the result of
    /// an action: a tap that only placed the cursor did something.
    static func changed(_ before: Data?, _ after: Data?, ignore: [CGPoint] = [], threshold: Double = 1.0,
                        caret: Bool = false) -> Bool {
        guard let before, let after, let a = image(before), let b = image(after) else { return true }
        if a.width != b.width || a.height != b.height { return true }
        let sa = gray(a, 32, 64), sb = gray(b, 32, 64)
        let total = zip(sa.px, sb.px).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        if Double(total) / Double(sa.px.count) > threshold { return true }  // a big change: new screen, scrolled list
        let w = a.width / 2, h = a.height / 2  // fine pass for small changes, at half resolution
        let fa = gray(a, w, h), fb = gray(b, w, h)
        let masks = ignore.map { (Double($0.x) * Double(w), Double($0.y) * Double(h)) }
        let r2 = pow(0.05 * Double(w), 2)
        var hits = 0, minX = w, maxX = -1, minY = h, maxY = -1
        for i in 0..<(w * h) where abs(Int(fa.px[i]) - Int(fb.px[i])) > 25 {
            let x = Double(i % w), y = Double(i / w)
            if y > topMask * Double(h) && masks.allSatisfy({ pow(x - $0.0, 2) + pow(y - $0.1, 2) > r2 }) {
                hits += 1
                (minX, maxX, minY, maxY) = (min(minX, i % w), max(maxX, i % w), min(minY, i / w), max(maxY, i / w))
            }
        }
        // logs 11-06: the cursor blinking in a focused box dropped 11 plans as "the screen changed while the model
        // was responding", each one more model call.
        if caret, hits >= 6 {
            if Double(maxX - minX) <= 0.012 * Double(w), Double(maxY - minY) <= 0.05 * Double(h) { return false }
            // The device's JPEG spreads a thin cursor wider than the strip above: the coarse look decides then.
            if let la = look(before), let lb = look(after), !visiblyChanged(la, lb) { return false }
        }
        return hits >= 6
    }

    /// A 24×48 gray look of a frame, decoded small (ImageIO thumbnail), for telling visible changes from noise.
    static func look(_ jpeg: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let small = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128,
              ] as CFDictionary) else { return nil }
        return gray(small, 24, 48).px
    }

    /// Whether two looks differ below the status bar by more than a blinking text cursor can: a cursor covers about a
    /// twentieth of one cell (a change of ~5–7 levels); a typed character, a new bubble, a sheet or a scroll moves
    /// at least one cell by more than 16.
    static func visiblyChanged(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, a.count == 24 * 48 else { return true }
        for i in (3 * 24)..<a.count where abs(Int(a[i]) - Int(b[i])) > 16 { return true }
        return false
    }

    /// True when the screen changed near `points` (fractions): where an action would land. Changes elsewhere (a
    /// clock, an animation, a banner) do not count; a missing frame does.
    static func changedNear(_ before: Data?, _ after: Data?, around points: [CGPoint], radius: Double = 0.08) -> Bool {
        guard let before, let after, let a = image(before), let b = image(after) else { return true }
        if a.width != b.width || a.height != b.height { return true }
        let w = a.width / 2, h = a.height / 2
        let fa = gray(a, w, h), fb = gray(b, w, h)
        let centers = points.map { (Double($0.x) * Double(w), Double($0.y) * Double(h)) }
        let r2 = pow(radius * Double(w), 2)
        var hits = 0
        for i in 0..<(w * h) where abs(Int(fa.px[i]) - Int(fb.px[i])) > 25 {
            let x = Double(i % w), y = Double(i / w)
            if y > topMask * Double(h) && centers.contains(where: { pow(x - $0.0, 2) + pow(y - $0.1, 2) <= r2 }) {
                hits += 1
            }
        }
        return hits >= 6
    }

    /// Where the pointer arrived after a move: the frame before the move against the first frame after it.
    /// The translucent pointer (a disk of `radius`, a fraction of the width) changes every pixel under it, whatever is
    /// beneath, and nothing just outside it; the spot it left changes too, so of the disks found the one nearest `near`
    /// wins, and its centre is the centroid of its changed pixels (nothing pulls it toward `near`). Checked on the live
    /// test's frames (11-08): the alarm's ✓ tap seen at (0.890, 0.135), and a hop at (0.544, 0.236), both matching the
    /// pointer drawn in the frame; where the screen itself changed around the spot, nothing is returned.
    static func arrival(_ before: Data, _ after: Data, near: CGPoint, radius: Double = 0.0253, window: Double = 0.2) -> CGPoint? {
        guard let ia = image(before), let ib = image(after), ia.width == ib.width, ia.height == ib.height else { return nil }
        let w = ia.width, h = ia.height
        let a = rgba(ia, w, h), b = rgba(ib, w, h)
        let r = radius * Double(w)
        guard r >= 3 else { return nil }
        let x0 = max(0, Int(Double(near.x) * Double(w) - window * Double(w))), x1 = min(w - 1, Int(Double(near.x) * Double(w) + window * Double(w)))
        let y0 = max(0, Int(Double(near.y) * Double(h) - window * Double(h))), y1 = min(h - 1, Int(Double(near.y) * Double(h) + window * Double(h)))
        guard x1 > x0, y1 > y0 else { return nil }
        // the changed mask over the search area, padded by the outer ring
        let pad = Int(r * 1.5) + 1
        let mx0 = max(0, x0 - pad), mx1 = min(w - 1, x1 + pad), my0 = max(0, y0 - pad), my1 = min(h - 1, y1 + pad)
        let mw = mx1 - mx0 + 1, mh = my1 - my0 + 1
        var mask = [Bool](repeating: false, count: mw * mh)
        for y in my0...my1 {
            for x in mx0...mx1 {
                let i = (y * w + x) * 4
                let d = max(abs(Int(a[i]) - Int(b[i])), abs(Int(a[i + 1]) - Int(b[i + 1])), abs(Int(a[i + 2]) - Int(b[i + 2])))
                mask[(y - my0) * mw + (x - mx0)] = d > 7
            }
        }
        func offsets(_ r0: Double, _ r1: Double, step: Int) -> [(Int, Int)] {
            let ri = Int(r1) + 1
            var out: [(Int, Int)] = []
            for dy in stride(from: -ri, through: ri, by: step) {
                for dx in stride(from: -ri, through: ri, by: step) where (r0 * r0...r1 * r1).contains(Double(dx * dx + dy * dy)) {
                    out.append((dx, dy))
                }
            }
            return out
        }
        let inner = offsets(0, r * 0.75, step: 2), outer = offsets(r * 1.2, r * 1.45, step: 2), body = offsets(0, r * 1.3, step: 1)
        func share(_ cx: Int, _ cy: Int, _ ring: [(Int, Int)], changed: Bool) -> (Double, Int) {
            var hit = 0, n = 0
            for (dx, dy) in ring {
                let x = cx + dx, y = cy + dy
                guard x >= mx0, x <= mx1, y >= my0, y <= my1, x >= 0, x < w, y >= 0, y < h else { continue }
                n += 1
                if mask[(y - my0) * mw + (x - mx0)] == changed { hit += 1 }
            }
            return (n == 0 ? 0 : Double(hit) / Double(n), n)
        }
        var found: [(score: Double, x: Int, y: Int)] = []
        for cy in stride(from: y0, through: y1, by: 2) {
            for cx in stride(from: x0, through: x1, by: 2) {
                let (fin, nin) = share(cx, cy, inner, changed: true)
                guard nin >= inner.count * 55 / 100, fin >= 0.95 else { continue }  // a real disk: 1.0; an icon's hover lift, a clock's digits: 0.75-0.94 (frames, 11-09)
                let (fout, nout) = share(cx, cy, outer, changed: false)
                guard nout >= outer.count * 4 / 10, fout >= 0.88 else { continue }  // a real disk: 0.98-1.0; those: 0.71-0.82
                found.append((fin * fout, cx, cy))
            }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.score > $1.score }
        var disks: [(score: Double, x: Int, y: Int)] = []
        for f in found where disks.allSatisfy({ Double((f.x - $0.x) * (f.x - $0.x) + (f.y - $0.y) * (f.y - $0.y)) > 4 * r * r }) {
            disks.append(f)
        }
        let centres: [CGPoint] = disks.compactMap { d in
            var sx = 0, sy = 0, n = 0
            for (dx, dy) in body {
                let x = d.x + dx, y = d.y + dy
                guard x >= mx0, x <= mx1, y >= my0, y <= my1, mask[(y - my0) * mw + (x - mx0)] else { continue }
                sx += x; sy += y; n += 1
            }
            return n == 0 ? nil : CGPoint(x: Double(sx) / Double(n) / Double(w), y: Double(sy) / Double(n) / Double(h))
        }
        return centres.min { hypot($0.x - near.x, $0.y - near.y) < hypot($1.x - near.x, $1.y - near.y) }
    }

    /// The image's RGBA bytes at w x h.
    static func rgba(_ img: CGImage, _ w: Int, _ h: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    /// Where the pointer is in `before`, given it moved right by `shift` (fraction of width) in `after`.
    ///
    /// Only the pointer moved between the two frames, so the changed pixels within `reach` of `near` are the
    /// pointer at both spots. `shift` bounds the search; the observed translation
    /// determines the actual centre, without trusting the calibrated mouse scale.
    static func pointer(_ before: Data, _ after: Data, near: CGPoint, shift: Double,
                        reach: CGPoint = CGPoint(x: 0.12, y: 0.08)) -> CGPoint? {
        guard let ia = image(before), let ib = image(after), ia.width == ib.width, ia.height == ib.height else {
            return nil
        }
        let w = ia.width, h = ia.height
        let a = gray(ia, w, h), b = gray(ib, w, h)
        let nx = Double(near.x), ny = Double(near.y), rx = Double(reach.x), ry = Double(reach.y)
        let left = max(0, Int((nx - rx) * Double(w)))
        let top = max(Int(0.05 * Double(h)), Int((ny - ry) * Double(h)))  // skip the status bar
        let right = min(w, Int((nx + rx) * Double(w))), bottom = min(h, Int((ny + ry) * Double(h)))
        guard right > left, bottom > top else { return nil }
        var hits: [(Int, Int)] = []
        for y in top..<bottom {
            for x in left..<right where abs(Int(a.px[y * w + x]) - Int(b.px[y * w + x])) > 30 {
                hits.append((x - left, y - top))
            }
        }
        let area = (right - left) * (bottom - top)
        guard hits.count >= 15, hits.count <= area / 4 else { return nil }  // nothing moved, or more than a pointer
        let xs = hits.map(\.0), ys = hits.map(\.1)
        if Double(xs.max()! - xs.min()!) > 0.15 * Double(w) || Double(ys.max()! - ys.min()!) > 0.07 * Double(h) {
            return nil  // not one compact spot
        }
        // A blinking text caret is compact too (logs36). Movement must have both a departure and an arrival,
        // and transport the same pixels horizontally. One disappearing shape must never steer the mouse.
        let deltas = hits.map { x, y in Int(b.px[(y + top) * w + x + left]) - Int(a.px[(y + top) * w + x + left]) }
        let minimum = max(8, hits.count / 10)
        guard deltas.filter({ $0 > 30 }).count >= minimum,
              deltas.filter({ $0 < -30 }).count >= minimum else { return nil }
        let distance = abs(shift * Double(w)), direction = shift < 0 ? -1 : 1
        guard distance >= 1 else { return nil }
        var best: (dx: Int, matches: Int)?
        // The saved mouse scale may be slightly wrong: allow that drift while requiring the commanded direction.
        for length in max(1, Int(distance * 0.5))...max(1, Int(ceil(distance * 1.5))) {
            let dx = direction * length
            let matches = hits.filter { x, y in
                let px = x + left, py = y + top
                guard px + dx >= 0, px + dx < w, px - dx >= 0, px - dx < w else { return false }
                return abs(Int(a.px[py * w + px]) - Int(b.px[py * w + px + dx])) <= 30
                    && abs(Int(b.px[py * w + px]) - Int(a.px[py * w + px - dx])) <= 30
            }.count
            if matches * 3 >= hits.count * 2,
               best == nil || matches > best!.matches {
                best = (dx, matches)
            }
        }
        guard let best else { return nil }
        let cx = Double(xs.reduce(0, +)) / Double(hits.count) + Double(left)
        let cy = Double(ys.reduce(0, +)) / Double(hits.count) + Double(top)
        return CGPoint(x: (cx - Double(best.dx) / 2) / Double(w), y: cy / Double(h))
    }
}
