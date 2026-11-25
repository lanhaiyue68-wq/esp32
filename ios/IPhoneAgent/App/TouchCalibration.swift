import UIKit

/// Catch real HID clicks on our overlay to estimate scale. Correct fresh curved
/// endpoints visually, then confirm each with a real click before saving.
extension AutoCalibrator {
    enum TouchResult { case done(Double), noTaps, failed(String) }
    static let roughStops = [75, 150]
    static let targets: [(Double, Double)] = [
        (0.06, 0.5), (0.5, 0.12), (0.25, 0.25), (0.75, 0.75), (0.9, 0.9)]
    // Test each low axis separately, away from the top-left system indicator.
    static let checks: [(Double, Double)] = [(0.06, 0.5), (0.5, 0.09), (0.5, 0.62), (0.85, 0.87)]
    static let check = (x: 0.5, y: 0.62)
    static let tapTimeout = 3.0
    static let maxCheckError = Pointer.calibrationTolerance
    static let landingCorrections = 2  // re-clicks per check, each moved by the last real landing's miss

    /// 163 (iPad): before the first home the pointer's place (CommandChannel.padPos) may be unknown, and a blind push up
    /// can open Notification Center. 162 looked for it in the shared screen, which failed under calibration's own screen
    /// (11-25 log: "pointer position unknown and not seen; refused", every try). Calibration's overlay catches clicks, so
    /// ask it: left all the way (harmless), right 300 (off the AssistiveTouch button at the edge), up 300 (past the top at
    /// most 300, tested harmless; and never at the bottom, so no Dock or Home bar under the click), click. A click in
    /// the status bar is not caught: Esc (an AssistiveTouch menu), down 500, click again.
    func locatePadPointer(probe: TouchProbe, device: HIDDevice) async {
        guard CommandChannel.onPad(), CommandChannel.padPos == nil else { return }
        do {
            try await device.send("abort")  // also releases; the firmware forgets its corner, so no curve bows up or left
            try await device.send("move -\(CommandChannel.padSpan.w + CommandChannel.padMargin) 0")
            try await device.send("move 300 -300")
            for attempt in 0..<2 {
                if attempt > 0 {
                    _ = try? await device.send("key esc")
                    try await device.send("move 0 500")
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                let sent = now()
                try await device.send("click")
                if let p = await probe.tap(since: sent, timeout: Self.tapTimeout) {
                    CommandChannel.padPos = (300, Int((Double(p.y) * Double(CommandChannel.padSpan.h)).rounded()))
                    app.say(String(format: "ipad: pointer found by a click at (%.3f, %.3f)", p.x, p.y))
                    return
                }
                app.say("ipad: locating click \(attempt + 1) not caught")
            }
        } catch {
            app.say("ipad: locating the pointer failed: \(error.localizedDescription)")
        }
    }

    func touchCalibrate(full: Bool) async throws -> TouchResult {
        let probe = app.probe, device = app.board.commands, pointer = app.pointer
        var accepted = false
        defer { if !accepted { pointer.discardProbe() } }
        var clicks = 0, hits = 0
        // Show the planned pass, not the maximum number including a possible retry.
        let total = Self.roughStops.count + Self.targets.count + Self.checks.count
        progress = Progress(done: 0, total: total)
        var samples: [(ux: Double, uy: Double, fx: Double, fy: Double)] = []
        phase = .homing
        await locatePadPointer(probe: probe, device: device)
        try await pointer.reset()

        func record(_ ux: Int, _ uy: Int, _ p: CGPoint) {
            samples.append((Double(ux), Double(uy), p.x, p.y))
        }
        func caught(since sent: Double, ux: Int, uy: Int) async -> CGPoint? {
            let p = await probe.tap(since: sent, timeout: Self.tapTimeout)
            clicks += 1
            progress = Progress(done: min(clicks, total), total: total)  // landing corrections add clicks
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
        guard samples.count >= 6, let (lx, ly) = lines() else {
            return .failed("有效校准点不足，未保存参数。")
        }
        guard pointer.applyProbe(x: lx, y: ly, samples: samples, feedback: true) else {
            return .failed("校准落点无法建立有效映射，未保存参数。")
        }
        app.say(String(format: "calibration: curved initial estimate scatter %.2f%%; endpoint feedback required", pointer.probeScatter * 100))

        phase = .verifying
        try await Task.sleep(nanoseconds: 400_000_000)  // let the board repaint plain before the first pixel search
        var worst = 0.0
        for (x, y) in Self.checks {
            try Task.checkCancellation()
            let (ux, uy) = pointer.probeUnits(x, y)
            var sent = now()
            do {
                try await pointer.tap(x, y)
            } catch let error as DeviceError {
                // The pixel finder is only a shortcut on this board: it catches the real click, so click and correct from that.
                app.say("calibration: endpoint feedback failed: " + error.message + " Correcting from the real click.")
                sent = now()
                try await device.send("click")
            }
            guard var p = await caught(since: sent, ux: ux, uy: uy) else {
                return .failed("验证点击未到达，未保存参数。")
            }
            var error = max(abs(p.x - x), abs(p.y - y))
            app.say(String(format: "probe feedback check (%.2f, %.2f): landed (%.3f, %.3f), error %.1f%%", x, y, p.x, p.y, error * 100))
            // Curved moves scatter one command by up to 5% (logs44: move 140 75 landed at x 0.480 and 0.530) and the
            // pixel finder sometimes misses the pointer (logs44: unseen, the check landed 3.0% off and calibration failed).
            // The pointer rests where the real click landed: move it by that measured miss and click again.
            for _ in 0..<Self.landingCorrections where error > Pointer.aimTolerance {
                sent = now()
                try await pointer.clickBy(x - p.x, y - p.y)
                guard let q = await caught(since: sent, ux: ux, uy: uy) else {
                    return .failed("验证点击未到达，未保存参数。")
                }
                p = q
                error = max(abs(p.x - x), abs(p.y - y))
                app.say(String(format: "probe landing correction (%.2f, %.2f): landed (%.3f, %.3f), error %.1f%%", x, y, p.x, p.y, error * 100))
            }
            worst = max(worst, error)
            guard error <= Self.maxCheckError else { return .failed("曲线终点实测误差超过 1.5%，未保存参数。") }
        }
        if pointer.setQuality(worst) {
            accepted = true
            return .done(pointer.quality ?? worst)
        }
        return .failed("曲线终点实测误差超过 1.5%，未保存参数。")
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
