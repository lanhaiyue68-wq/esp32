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

    /// Whether two looks show the same screen: the pointer, a pressed key or a number in a display may differ, a new
    /// page, a sheet or a scrolled list differs far more (a calculator's key is ~20 cells of the 1080 below the status bar).
    static func sameScreen(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, a.count == 24 * 48 else { return false }
        var different = 0
        for i in (3 * 24)..<a.count where abs(Int(a[i]) - Int(b[i])) > 16 { different += 1 }
        return different <= 64
    }

    /// B6 (122 on the phone 11-11): the same screen, darker all over by about one factor, as under a system question's
    /// dimming. A new page differs part by part; a question's own box may cover up to a quarter of the screen.
    static func dimmed(_ before: Data, _ after: Data) -> Bool {
        guard let a = look(before), let b = look(after), a.count == b.count, a.count == 24 * 48 else { return false }
        let cells = Array((3 * 24)..<a.count)
        let ma = cells.reduce(0.0) { $0 + Double(a[$1]) }, mb = cells.reduce(0.0) { $0 + Double(b[$1]) }
        guard ma >= Double(cells.count) * 60 else { return false }  // a dark screen does not show it
        let k = mb / ma
        guard (0.3...0.8).contains(k) else { return false }
        let fits = cells.filter { abs(Double(b[$0]) - k * Double(a[$0])) <= 14 }.count
        return Double(fits) >= 0.75 * Double(cells.count)
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
        // Not in the status bar: the signal bars and the clock change on their own, and were read as the pointer (a tap
        // pulled away from its target, over USB 11-09).
        let y0 = max(Int(topMask * Double(h)), Int(Double(near.y) * Double(h) - window * Double(h))), y1 = min(h - 1, Int(Double(near.y) * Double(h) + window * Double(h)))
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
                guard nin >= inner.count * 55 / 100, fin >= 0.8 else { continue }  // over text some pixels keep their shade under the disk, so not much stricter
                let (fout, nout) = share(cx, cy, outer, changed: false)
                guard nout >= outer.count * 4 / 10, fout >= 0.9 else { continue }  // what tells a disk: real ones 0.98-1.0, an icon's hover lift or a clock's digits 0.71-0.82 (frames over USB, 11-09)
                found.append((fin * fout, cx, cy))
            }
        }
        guard !found.isEmpty else { return nil }
        found.sort { $0.score > $1.score }
        var disks: [(score: Double, x: Int, y: Int)] = []
        for f in found where disks.allSatisfy({ d in
            // Split up: Xcode 26's type checker gave up on the one-line form (the stopgap 小藍 build, 11-25).
            let dx: Int = f.x - d.x, dy: Int = f.y - d.y
            return Double(dx * dx + dy * dy) > 4 * r * r
        }) {
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

    /// 174 (iPadOS 26+): an iPad's pointer is a grey arrow, tip at its top-left, ~20 px tall in a 960-wide frame; not
    /// arrival's translucent disk, so arrival never saw it ("pointer not seen" on every iPad tap and calibration check,
    /// 11-25). Where it is now: the compact patches of pixels that changed by more than `threshold` between the frames
    /// (the arrow at its new spot and at the one it left), the one nearest `near` (where it was sent), and of that patch
    /// the tip, the pixel farthest up and left, which is where it clicks. Checked on 18 frames of 11-25 (960 x 1280):
    /// 161-176 changed pixels a patch, the tip 4 px left of and 10 px above the patch's centre every time.
    static func arrow(_ before: Data, _ after: Data, near: CGPoint, window: Double = 0.25, threshold: Int = 40,
                      top: Double = topMask) -> CGPoint? {
        arrows(before, after, near: near, window: window, threshold: threshold, top: top)
            .min { hypot($0.x - near.x, $0.y - near.y) < hypot($1.x - near.x, $1.y - near.y) }
    }

    /// 184 (user 11-26: the iPad's pointer made big and red, 辅助功能 › 指针控制 › 颜色): the pointer in one frame, no
    /// nudge: a hollow patch of the pointer's red (its outline ~40 x 52 px at 960 wide, 750 red px, the fill grey), its
    /// tip the outline's top-left, moved in a little. Checked on the customer's iPad 11-26: found in the frame with it,
    /// nothing in six without it (badges ~20 px, red icons 38 x 14, the Dock's band, the recording pill in the status
    /// bar). Nil when there is none near `near` (another colour set, or hidden): the caller falls back to a nudge.
    static func redPointer(_ jpeg: Data, near: CGPoint? = nil, window: Double = 1, top: Double = 0.03) -> CGPoint? {
        guard let img = image(jpeg) else { return nil }
        let w = img.width, h = img.height
        return redPointer(rgba(img, w, h), w, h, near: near, window: window, top: top)
    }

    /// 184 (C15a): the pointer in one frame, whichever it is: the red arrow (指针控制 › 颜色) or the disk 辅助触控 turns it
    /// into (ringPointer). The frame is decoded once. Nil: neither near `near`; the caller falls back to a nudge.
    static func seenPointer(_ jpeg: Data, near: CGPoint? = nil, window: Double = 1, top: Double = 0.03) -> CGPoint? {
        guard let img = image(jpeg) else { return nil }
        let w = img.width, h = img.height
        let px = rgba(img, w, h)
        return redPointer(px, w, h, near: near, window: window, top: top)
            ?? ringPointer(px, w, h, near: near, window: window, top: top)
    }

    /// 184 (C15a; user 11-26: 辅助功能 › 触控 › 辅助触控 turned on, and the iPad's pointer became a disk, a translucent grey
    /// fill in a coloured ring, ~34 px across at 960 wide, blue (14, 125, 234) that day; it clicks at its centre; 183
    /// never saw it: "eye: unseen" on every aim): the pointer in one frame, its colour not assumed: a ring of one
    /// saturated hue (within 25° of where it starts; brightest channel > 120 and 100 over the dimmest), round (24–48 px
    /// across, width and height within 15 %, 97 % of it 0.5–1.15 radii out, all eight eighths of the way
    /// round), nothing of its hue inside, and its inside the grey fill: darker than a white page (luminance < 190) or
    /// than around it. Checked 11-26 on the customer's iPad (a Python copy of this): the centre within 2 px in four
    /// frames (on the Dock's WeChat icon, both lists); nothing in 450 other frames (a camera's lens, a smiley, Google's
    /// O were taken before the inside had to be dark, white inside; a % sign's o and a map pin, 18 x 24, before it had
    /// to be this round).
    static func ringPointer(_ jpeg: Data, near: CGPoint? = nil, window: Double = 1, top: Double = 0.03) -> CGPoint? {
        guard let img = image(jpeg) else { return nil }
        let w = img.width, h = img.height
        return ringPointer(rgba(img, w, h), w, h, near: near, window: window, top: top)
    }

    /// A colour's hue in degrees (0 for a grey).
    static func hue(_ r: Int, _ g: Int, _ b: Int) -> Double {
        let mx = max(r, g, b), mn = min(r, g, b), d = Double(mx - mn)
        guard d > 0 else { return 0 }
        let h: Double
        if mx == r { h = (Double(g - b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == g { h = Double(b - r) / d + 2 }
        else { h = Double(r - g) / d + 4 }
        return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
    }

    static func ringPointer(_ px: [UInt8], _ w: Int, _ h: Int, near: CGPoint?, window: Double, top: Double) -> CGPoint? {
        let s = 2, gw = w / s, gh = h / s
        guard gw > 10, gh > 10 else { return nil }
        let k = Double(w) / 960
        var sat = [Bool](repeating: false, count: gw * gh)
        var hues = [Double](repeating: 0, count: gw * gh)
        var strong = [Bool](repeating: false, count: gw * gh)  // a ring starts only at its full colour, not a blend at its edge
        for gy in Int(top * Double(gh))..<gh {
            for gx in 0..<gw {
                let i = ((gy * s) * w + gx * s) * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                let mx = max(r, g, b), mn = min(r, g, b)
                guard mx > 120, mx - mn > 100 else { continue }
                sat[gy * gw + gx] = true
                hues[gy * gw + gx] = hue(r, g, b)
                strong[gy * gw + gx] = mx - mn > 150
            }
        }
        func apart(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }
        func lum(_ x: Double, _ y: Double) -> Double {
            let i = (min(h - 1, max(0, Int(y))) * w + min(w - 1, max(0, Int(x)))) * 4
            return 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2])
        }
        var seen = [Bool](repeating: false, count: gw * gh)
        var best: (p: CGPoint, d: Double)?
        for start in 0..<(gw * gh) where strong[start] && !seen[start] {
            let seed = hues[start]
            var stack = [start], cells: [Int] = []
            seen[start] = true
            var minX = Int.max, maxX = 0, minY = Int.max, maxY = 0
            while let c = stack.popLast() {
                cells.append(c)
                let cx = c % gw, cy = c / gw
                minX = min(minX, cx); maxX = max(maxX, cx); minY = min(minY, cy); maxY = max(maxY, cy)
                for n in [cx > 0 ? c - 1 : -1, cx < gw - 1 ? c + 1 : -1, c - gw, c + gw]
                where n >= 0 && n < gw * gh && sat[n] && !seen[n] && apart(hues[n], seed) < 25 {
                    seen[n] = true
                    stack.append(n)
                }
            }
            let bw = Double((maxX - minX + 1) * s), bh = Double((maxY - minY + 1) * s)
            guard (24 * k...48 * k).contains(bw), (24 * k...48 * k).contains(bh), abs(bw - bh) <= 0.15 * max(bw, bh) else { continue }
            let cx = Double(minX + maxX + 1) / 2 * Double(s), cy = Double(minY + maxY + 1) / 2 * Double(s), r = max(bw, bh) / 2
            var band = 0, eighths = Set<Int>()
            for c in cells {
                let dx = Double((c % gw) * s + 1) - cx, dy = Double((c / gw) * s + 1) - cy, d = hypot(dx, dy)
                if d >= 0.5 * r && d <= 1.15 * r { band += 1 }
                eighths.insert(Int((atan2(dy, dx) + .pi) / (2 * .pi) * 8) % 8)
            }
            let n = Double(cells.count * s * s), area = Double.pi * r * r
            guard Double(band) >= 0.97 * Double(cells.count), eighths.count == 8, n >= 0.15 * area, n <= 0.7 * area else { continue }
            var inner = 0, innerOfIt = 0
            let r4 = 0.4 * r
            for gy in max(0, Int((cy - r4) / Double(s)))...min(gh - 1, Int((cy + r4) / Double(s))) {
                for gx in max(0, Int((cx - r4) / Double(s)))...min(gw - 1, Int((cx + r4) / Double(s)))
                where hypot(Double(gx * s + 1) - cx, Double(gy * s + 1) - cy) < r4 {
                    inner += 1
                    if sat[gy * gw + gx] && apart(hues[gy * gw + gx], seed) < 25 { innerOfIt += 1 }
                }
            }
            guard inner > 0, Double(innerOfIt) < 0.1 * Double(inner) else { continue }
            var inside: [Double] = []
            let ri = Int(r4)
            for dx in stride(from: -ri, through: ri, by: 2) {
                for dy in stride(from: -ri, through: ri, by: 2) where Double(dx * dx + dy * dy) < r4 * r4 {
                    inside.append(lum(cx + Double(dx), cy + Double(dy)))
                }
            }
            let around = (0..<16).map { a -> Double in
                let t = Double(a) / 16 * 2 * .pi
                return lum(cx + 1.4 * r * cos(t), cy + 1.4 * r * sin(t))
            }
            guard !inside.isEmpty else { continue }
            let li = inside.reduce(0, +) / Double(inside.count), lo = around.reduce(0, +) / Double(around.count)
            guard li < 190 || li < 0.85 * lo else { continue }  // the grey fill: a white-inside ring (a lens, an O) is not it
            let p = CGPoint(x: cx / Double(w), y: cy / Double(h))
            if let near, abs(Double(p.x - near.x)) > window || abs(Double(p.y - near.y)) > window { continue }
            let d = near.map { hypot(Double(p.x - $0.x), Double(p.y - $0.y)) } ?? 0
            if best == nil || d < best!.d { best = (p, d) }
        }
        return best?.p
    }

    static func redPointer(_ px: [UInt8], _ w: Int, _ h: Int, near: CGPoint?, window: Double, top: Double) -> CGPoint? {
        let s = 2, gw = w / s, gh = h / s
        guard gw > 10, gh > 10 else { return nil }
        var mask = [Bool](repeating: false, count: gw * gh)
        for gy in Int(top * Double(gh))..<gh {
            for gx in 0..<gw {
                let i = ((gy * s) * w + gx * s) * 4
                let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
                if r > 180 && g < 120 && b < 130 && r - g > 90 { mask[gy * gw + gx] = true }
            }
        }
        let k = Double(w) / 960
        var seen = [Bool](repeating: false, count: gw * gh)
        var best: (tip: CGPoint, d: Double)?
        for start in 0..<(gw * gh) where mask[start] && !seen[start] {
            var stack = [start]
            seen[start] = true
            var count = 0, minX = Int.max, maxX = 0, minY = Int.max, maxY = 0, tip = start, tipSum = Int.max
            while let c = stack.popLast() {
                count += 1
                let cx = c % gw, cy = c / gw
                minX = min(minX, cx); maxX = max(maxX, cx); minY = min(minY, cy); maxY = max(maxY, cy)
                if cx + cy < tipSum { (tipSum, tip) = (cx + cy, c) }
                for n in [cx > 0 ? c - 1 : -1, cx < gw - 1 ? c + 1 : -1, c - gw, c + gw]
                where n >= 0 && n < gw * gh && mask[n] && !seen[n] {
                    seen[n] = true
                    stack.append(n)
                }
            }
            let bw = Double((maxX - minX + 1) * s), bh = Double((maxY - minY + 1) * s), n = Double(count * s * s)
            guard (22 * k...80 * k).contains(bw), (28 * k...95 * k).contains(bh), (250 * k * k...2000 * k * k).contains(n),
                  !mask[((minY + maxY) / 2) * gw + (minX + maxX) / 2] else { continue }  // hollow: the grey fill inside
            let p = CGPoint(x: (Double((tip % gw) * s) + 2 * k) / Double(w), y: (Double((tip / gw) * s) + 2 * k) / Double(h))
            let d = near.map { hypot(Double(p.x - $0.x), Double(p.y - $0.y)) } ?? 0
            if let near, abs(Double(p.x - near.x)) > window || abs(Double(p.y - near.y)) > window { continue }
            if best == nil || d < best!.d { best = (p, d) }
        }
        return best?.tip
    }

    /// Every arrow tip seen changed within `window` of `near` (at most four).
    /// 184 (Echo 183, 11-26: by an iPad window's top, its back arrow, 取消 and ＋ at ~0.05, the pointer was never seen:
    /// the top 6 % (an iPhone's status bar) was left out): `top`, the band left out (an iPad's status bar is ~3 %).
    static func arrows(_ before: Data, _ after: Data, near: CGPoint, window: Double = 0.25, threshold: Int = 40,
                       top: Double = topMask) -> [CGPoint] {
        guard let ia = image(before), let ib = image(after), ia.width == ib.width, ia.height == ib.height else { return [] }
        let w = ia.width, h = ia.height
        let a = gray(ia, w, h), b = gray(ib, w, h)
        let x0 = max(0, Int((Double(near.x) - window) * Double(w))), x1 = min(w - 1, Int((Double(near.x) + window) * Double(w)))
        let y0 = max(Int(top * Double(h)), Int((Double(near.y) - window) * Double(h)))
        let y1 = min(h - 1, Int((Double(near.y) + window) * Double(h)))
        guard x1 > x0, y1 > y0 else { return [] }
        var changed: [(x: Int, y: Int)] = []
        for y in y0...y1 {
            for x in x0...x1 where abs(Int(a.px[y * w + x]) - Int(b.px[y * w + x])) > threshold {
                changed.append((x, y))
            }
        }
        guard !changed.isEmpty, changed.count < w * h / 50 else { return [] }  // much of the screen changed: no pointer move
        let cell = max(4, w / 40)  // about the arrow's size: 24 px at 960
        let scale = Double(w * w) / (960.0 * 960.0)
        // A patch: the changed pixels near the densest cell, centred on their own centroid, then all within 0.75 cell
        // of it (an arrow reaches ~13 px from its centroid at 960): two spots a nudge apart (~33 px) stay two.
        let look = 1.2 * Double(cell), reach = 0.75 * Double(cell), most = 1.2 * Double(cell)
        var remaining = changed
        var tips: [CGPoint] = []
        /// The patch around a cell: the changed pixels near it, centred on their own centroid; its tip when it is a pointer's.
        func cut(_ densest: Int, _ remaining: [(x: Int, y: Int)]) -> (rest: [(x: Int, y: Int)], tip: (x: Int, y: Int)?) {
            let gx = Double(x0 + (densest % 100_000) * cell) + Double(cell) / 2
            let gy = Double(y0 + (densest / 100_000) * cell) + Double(cell) / 2
            var sx = 0.0, sy = 0.0, sn = 0.0
            for p in remaining {
                let dx = Double(p.x) - gx, dy = Double(p.y) - gy
                if dx * dx + dy * dy <= look * look { sx += Double(p.x); sy += Double(p.y); sn += 1 }
            }
            let cx = sn > 0 ? sx / sn : gx, cy = sn > 0 ? sy / sn : gy
            var patch: [(x: Int, y: Int)] = [], rest: [(x: Int, y: Int)] = []
            for p in remaining {
                let dx = Double(p.x) - cx, dy = Double(p.y) - cy
                if dx * dx + dy * dy <= reach * reach { patch.append(p) } else { rest.append(p) }
            }
            guard let minX = patch.map(\.x).min(), let maxX = patch.map(\.x).max(),
                  let minY = patch.map(\.y).min(), let maxY = patch.map(\.y).max() else { return (rest, nil) }
            let n = Double(patch.count)
            guard n >= 60 * scale, n <= 600 * scale, Double(maxX - minX) <= most, Double(maxY - minY) <= most else { return (rest, nil) }
            return (rest, patch.min(by: { $0.x + $0.y < $1.x + $1.y }))
        }
        for _ in 0..<4 where !remaining.isEmpty {
            var counts: [Int: Int] = [:]
            for p in remaining { counts[((p.y - y0) / cell) * 100_000 + (p.x - x0) / cell, default: 0] += 1 }
            guard let densestCount = counts.values.max() else { break }
            // 192 (CI 45970277047: Build184Tests' pointer in a window's title bar, passed on 190 and 191, found nothing):
            // two cells as dense, the one taken was the Dictionary's order — another each run — and from one of them
            // the patch took in both spots and neither was a pointer. The tied cells are tried in order; the first whose
            // patch is a pointer's is kept, else the first, as before.
            var taken: (rest: [(x: Int, y: Int)], tip: (x: Int, y: Int)?)?
            for densest in counts.filter({ $0.value == densestCount }).map({ $0.key }).sorted() {
                let c = cut(densest, remaining)
                if taken == nil || c.tip != nil { taken = c }
                if c.tip != nil { break }
            }
            guard let t = taken else { break }
            remaining = t.rest
            if let tip = t.tip { tips.append(CGPoint(x: Double(tip.x) / Double(w), y: Double(tip.y) / Double(h))) }
        }
        return tips
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
