import UIKit

/// Catch real HID clicks on our overlay, measure a monotone map, then validate fresh
/// clicks with the exact positioning path used by the agent. Nothing is saved early.
extension AutoCalibrator {
    enum TouchResult { case done(Double), noTaps, failed(String) }
    static let roughStops = [75, 150]
    static let targets: [(Double, Double)] = [
        (0.06, 0.5), (0.5, 0.12), (0.25, 0.25), (0.75, 0.25), (0.5, 0.5),
        (0.25, 0.75), (0.75, 0.75), (0.5, 0.9), (0.9, 0.5)]
    // Test each low axis separately, away from the top-left system indicator.
    static let checks: [(Double, Double)] = [(0.06, 0.5), (0.5, 0.09), (0.5, 0.62), (0.85, 0.87)]
    static let check = (x: 0.5, y: 0.62)
    static let tapTimeout = 3.0
    static let maxCheckError = Pointer.calibrationTolerance

    func touchCalibrate(full: Bool) async throws -> TouchResult {
        let probe = app.probe, device = app.board.commands, pointer = app.pointer
        var accepted = false
        defer { if !accepted { pointer.discardProbe() } }
        var clicks = 0, hits = 0
        let total = Self.roughStops.count + Self.targets.count + 2 * Self.checks.count
        var samples: [(ux: Double, uy: Double, fx: Double, fy: Double)] = []
        phase = .homing
        try await pointer.reset()

        func record(_ ux: Int, _ uy: Int, _ p: CGPoint) {
            samples.append((Double(ux), Double(uy), p.x, p.y))
        }
        func caught(since sent: Double, ux: Int, uy: Int) async -> CGPoint? {
            let p = await probe.tap(since: sent, timeout: Self.tapTimeout)
            clicks += 1
            progress = Progress(done: clicks, total: total)
            if let p {
                hits += 1
                app.say(String(format: "probe %d: axis move %d %d → (%.3f, %.3f)", clicks, ux, uy, p.x, p.y))
            } else { app.say("probe \(clicks): no confirmed click") }
            return p
        }
        func click(_ ux: Int, _ uy: Int) async throws -> CGPoint? {
            try await ProbeMotion.home(device)
            try await ProbeMotion.move(device, ux, uy)
            let sent = now()
            try await device.send("click")
            return await caught(since: sent, ux: ux, uy: uy)
        }
        func lines() -> (ProbeFit.Line, ProbeFit.Line)? {
            let xs = samples.filter { ProbeFit.usable($0.fx) }.map { ($0.ux, $0.fx) }
            let ys = samples.filter { ProbeFit.usable($0.fy) }.map { ($0.uy, $0.fy) }
            guard let x = ProbeFit.line(xs), let y = ProbeFit.line(ys) else { return nil }
            return (x, y)
        }

        phase = .probeA
        for u in Self.roughStops {
            guard let p = try await click(u, u) else {
                return hits == 0 ? .noTaps : .failed("粗校准点击未到达，未保存参数。")
            }
            record(u, u, p)
        }
        guard let rough = lines() else { return .failed("粗校准落点无有效跨度，未保存参数。") }
        phase = .probeB
        for (x, y) in Self.targets {
            let ux = max(1, rough.0.units(for: x)), uy = max(1, rough.1.units(for: y))
            if let p = try await click(ux, uy) { record(ux, uy, p) }
            else {
                // A missed probe can be the floating AssistiveTouch control. Do not invent a location.
                AssistiveTouchSpots.remember(x: x, y: y)
                _ = try? await device.send("key esc")
            }
        }
        guard samples.count >= 8, let (lx, ly) = lines() else {
            return .failed("有效校准点不足，未保存参数。")
        }
        guard pointer.applyProbe(x: lx, y: ly, samples: samples) else { return .failed("校准落点无法建立有效映射，未保存参数。") }
        guard pointer.probeScatter <= Self.maxCheckError else {
            return .failed(String(format: "同距离落点波动 %.1f%%，超过 1.5%%，未保存参数。", pointer.probeScatter * 100))
        }

        phase = .verifying
        // One bounded refinement followed by fresh validation; the final result includes all point errors.
        for pass in 0..<2 {
            var worst = pointer.probeScatter
            var measured: [(Int, Int, CGPoint)] = []
            for (x, y) in Self.checks {
                try Task.checkCancellation()
                let (ux, uy) = pointer.probeUnits(x, y), sent = now()
                try await pointer.tap(x, y)
                guard let p = await caught(since: sent, ux: ux, uy: uy) else {
                    return .failed("验证点击未到达，未保存参数。")
                }
                let error = max(abs(p.x - x), abs(p.y - y))
                worst = max(worst, error)
                measured.append((ux, uy, p))
                app.say(String(format: "probe check %d (%.2f, %.2f): landed (%.3f, %.3f), error %.1f%%", pass + 1, x, y, p.x, p.y, error * 100))
            }
            if worst <= Self.maxCheckError, pointer.setQuality(worst) {
                accepted = true
                return .done(pointer.quality ?? worst)
            }
            if pass == 0 {
                for (ux, uy, p) in measured { record(ux, uy, p) }
                guard pointer.applyProbe(x: lx, y: ly, samples: samples) else { break }
                guard pointer.probeScatter <= Self.maxCheckError else { break }
            }
        }
        return .failed("多点验证误差超过 1.5%，未保存参数。")
    }
}

extension AppModel {
    /// Ask the vision model where the pointer is on a mirrored frame (fallback for calibration).
    func locatePointer(_ jpeg: Data) async -> CGPoint? {
        guard !MockMode.on, settings.isConfigured, let client = try? await settings.client("actor") else { return nil }
        let system = "You find the mouse pointer on iPhone/iPad screenshots. The AssistiveTouch pointer is a small "
            + "round dark grey translucent dot. During calibration the screen is white with a grid: thin lines every "
            + "10% labelled 100-900 along the top and left edges, and coloured squares in the corners. Reply with JSON only: {\"x\": <0-1000>, \"y\": <0-1000>} for its centre, "
            + "relative to the screenshot (x left->right, y top->bottom), or {\"x\": null, \"y\": null} if there is none."
        guard let r = try? await client.chat(system: system, text: "Where is the pointer?", image: jpeg, maxTokens: 200,
                                             temperature: 0),
              let start = r.text.firstIndex(of: "{"), let end = r.text.lastIndex(of: "}"),
              let json = try? JSONSerialization.jsonObject(with: Data(r.text[start...end].utf8)) as? [String: Any],
              let x = (json["x"] as? NSNumber)?.doubleValue, let y = (json["y"] as? NSNumber)?.doubleValue,
              (0...1000).contains(x), (0...1000).contains(y) else {
            say("calibration: vision model did not find the pointer")
            return nil
        }
        return CGPoint(x: x / 1000, y: y / 1000)
    }
}
