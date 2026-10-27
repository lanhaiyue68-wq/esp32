import Foundation

/// Measured mouse units from home -> screen fraction. The origin is a real home,
/// not the intercept extrapolated from interior calibration points.
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
        knots = [Knot(units: 0, fraction: 0)] + pools.map {
            Knot(units: $0.map(\.units).reduce(0, +) / Double($0.count), fraction: mean($0))
        }
        guard knots.count >= 3 else { return nil }
        scatter = 0
        scatter = valid.map { abs(landed(at: $0.0) - $0.1) }.max() ?? 1
    }

    func units(for fraction: Double) -> Int {
        Int(interpolate(min(max(fraction, 0), 1), inverse: true).rounded())
    }

    func landed(at units: Double) -> Double { interpolate(units, inverse: false) }

    private func interpolate(_ t: Double, inverse: Bool) -> Double {
        func x(_ k: Knot) -> Double { inverse ? k.fraction : k.units }
        func y(_ k: Knot) -> Double { inverse ? k.units : k.fraction }
        let hi = knots.indices.dropFirst().first { x(knots[$0]) >= t } ?? (knots.count - 1)
        let a = knots[hi - 1], b = knots[hi]
        return y(a) + (t - x(a)) * (y(b) - y(a)) / (x(b) - x(a))
    }
}

/// Use the same settled straight reports in calibration and runtime. v34's `move`
/// otherwise defaults to random Bezier paths, even for single-axis commands.
@MainActor enum ProbeMotion {
    static let version = 2

    static func home(_ device: HIDDevice) async throws {
        try Task.checkCancellation()
        try await confirmStraightMotion(device)
        try await device.send("home")
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    private static func confirmStraightMotion(_ device: HIDDevice) async throws {
        let mode: String
        do { mode = try await device.send("curve").trimmingCharacters(in: .whitespacesAndNewlines) }
        catch let error as DeviceError where error.message.lowercased().contains("unknown command") {
            // Firmware predating curve support always emits straight steps.
            return
        }
        if mode == "off" { return }  // query only: do not rewrite board NVS on every gesture
        guard mode == "on" else {
            throw DeviceError(message: "无法确认开发板的直线移动模式，未执行定位。请检查连接后重试。")
        }
        let changed = try await device.send("curve off").trimmingCharacters(in: .whitespacesAndNewlines)
        guard changed == "off" else {
            throw DeviceError(message: "开发板未确认关闭随机曲线移动，未执行定位。请检查连接后重试。")
        }
    }

    static func move(_ device: HIDDevice, _ x: Int, _ y: Int) async throws {
        if x != 0 { try await device.send("move \(x) 0") }
        if x != 0 && y != 0 { try await Task.sleep(nanoseconds: 100_000_000) }
        if y != 0 { try await device.send("move 0 \(y)") }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}
