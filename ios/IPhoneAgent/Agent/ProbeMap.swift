import Foundation

/// Measured mouse units from home -> screen fraction. Flat responses retain both
/// ends of their measured unit range; the physical pointer centre can be inset at home.
struct ProbeMap: Codable {
    struct Knot: Codable { var units: Double; var fraction: Double }
    var knots: [Knot]
    var scatter: Double

    init?(_ samples: [(Double, Double)]) {
        let valid = samples.filter { $0.0.isFinite && $0.0 > 0 && $0.0 <= 100_000 && $0.1.isFinite && ProbeFit.usable($0.1) }
        let groups = Dictionary(grouping: valid, by: { Int($0.0.rounded()) })
        guard groups.count >= 2 else { return nil }
        let points = groups.keys.sorted().map { u in
            Knot(units: Double(u), fraction: groups[u]!.map(\.1).reduce(0, +) / Double(groups[u]!.count))
        }
        // Small neighbouring measurement reversals are pooled, never turned into a negative movement gain.
        var pools: [[Knot]] = []
        func mean(_ pool: [Knot]) -> Double { pool.map(\.fraction).reduce(0, +) / Double(pool.count) }
        for p in points {
            pools.append([p])
            while pools.count > 1 && mean(pools[pools.count - 2]) >= mean(pools.last!) {
                let last = pools.removeLast()
                pools[pools.count - 1] += last
            }
        }
        guard pools.count >= 2 else { return nil }  // a flat response has no measured gain
        knots = [Knot(units: 0, fraction: 0)] + pools.flatMap { pool in
            // A plateau is an interval, not one averaged unit value. Collapsing it
            // creates false residuals and repeatedly selects a unit value inside it.
            pool.map { Knot(units: $0.units, fraction: mean(pool)) }
        }
        guard knots.count >= 3 else { return nil }
        scatter = 0
        scatter = valid.map { abs(landed(at: $0.0) - $0.1) }.max() ?? 1
    }

    func units(for fraction: Double) -> Int {
        let target = min(max(fraction, 0), 1)
        guard target > 0 else { return 0 }
        let measured = Array(knots.dropFirst())
        let a: Knot, b: Knot
        if target < measured[0].fraction {
            // Below the first real landing, use the measured low-end gain rather
            // than inventing a slope from the logical (0,0) corner to the pointer inset.
            a = measured[0]
            b = measured.first { $0.fraction > a.fraction }!
        } else if let hi = measured.firstIndex(where: { $0.fraction >= target }) {
            if hi == 0 { return Int(measured[0].units.rounded()) }
            a = measured[hi - 1]
            b = measured[hi]
        } else {
            b = measured.last!
            a = measured.last { $0.fraction < b.fraction }!
        }
        let units = a.units + (target - a.fraction) * (b.units - a.units) / (b.fraction - a.fraction)
        return Int(min(max(units, 0), 100_000).rounded())
    }

    /// The farthest measured landing: past it, units(for:) only extrapolates.
    var reach: Double { knots.last?.fraction ?? 1 }

    /// Where the pointer rests at home, as a screen fraction: the first two measured landings extended back to zero
    /// units (the pointer's centre sits a little inside the corner). 0 when they do not say.
    var inset: Double {
        let measured = Array(knots.dropFirst())
        guard let a = measured.first, let b = measured.first(where: { $0.fraction > a.fraction }), b.units > a.units else { return 0 }
        let rest = a.fraction - a.units * (b.fraction - a.fraction) / (b.units - a.units)
        return min(max(rest, 0), 0.05)
    }

    /// Mouse units for a hop of `distance` (screen fraction, signed) from anywhere: the same move from home lands at
    /// the inset plus that distance, since the board's motion and iOS's acceleration do not depend on where it starts.
    func hop(_ distance: Double) -> Int {
        guard abs(distance) > 0.0005 else { return 0 }
        let units = self.units(for: min(inset + abs(distance), 1))
        return distance < 0 ? -units : units
    }

    func landed(at units: Double) -> Double {
        let hi = knots.indices.dropFirst().first { knots[$0].units >= units } ?? (knots.count - 1)
        let a = knots[hi - 1], b = knots[hi]
        return a.fraction + (units - a.units) * (b.fraction - a.fraction) / (b.units - a.units)
    }
}

/// Keep the user's Bezier motion enabled in calibration and runtime. Build79
/// incorrectly persisted curve=off; recover that state before measured positioning.
@MainActor enum ProbeMotion {
    static let version = 4
    /// 169: moves go as one curved move rather than x then y (set on an iPad by AppModel; this file also builds alone
    /// in the pointer-motion harness, so it names no app type).
    static var onePiece = false

    static func home(_ device: HIDDevice) async throws {
        try Task.checkCancellation()
        try await confirmBezierMotion(device)
        try await device.send("home")
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    private static func confirmBezierMotion(_ device: HIDDevice) async throws {
        let mode: String
        do { mode = try await device.send("curve").trimmingCharacters(in: .whitespacesAndNewlines) }
        catch let error as DeviceError where error.message.lowercased().contains("unknown command") {
            // Firmware predating curve support always emits straight steps.
            return
        }
        if mode == "on" { return }  // query only: do not rewrite board NVS on every gesture
        guard mode == "off" else {
            throw DeviceError(message: "无法确认开发板的贝塞尔曲线模式，未执行定位。请检查连接后重试。")
        }
        let changed = try await device.send("curve on").trimmingCharacters(in: .whitespacesAndNewlines)
        guard changed == "on" else {
            throw DeviceError(message: "开发板未确认恢复贝塞尔曲线移动，未执行定位。请检查连接后重试。")
        }
    }

    static func move(_ device: HIDDevice, _ x: Int, _ y: Int) async throws {
        // 169 (user 11-25, iPad: "還是直線去點，不是貝塞爾曲線"): split into x then y, each a straight line (the board
        // only curves a move with both), the pointer drew an L. On an iPad it is one move, which the board curves; the
        // firmware's corridor keeps the curve inside the move's own box once a home has forgotten the corner (abort).
        if onePiece, x != 0, y != 0 {
            try await device.send("move \(x) \(y)")
            try await Task.sleep(nanoseconds: 100_000_000)
            return
        }
        if x != 0 { try await device.send("move \(x) 0") }
        if x != 0 && y != 0 { try await Task.sleep(nanoseconds: 100_000_000) }
        if y != 0 { try await device.send("move 0 \(y)") }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}
