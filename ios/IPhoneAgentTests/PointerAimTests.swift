import XCTest
@testable import IPhoneAgent

/// A phone whose pointer really moves: `home` puts it in the top-left corner, moves are scaled by the phone's
/// true mouse units per screen and stop at the screen border, like iOS does. Finding it reports the dot's centre,
/// which stays a little inside the border (log25: the corner read as 0.958 / 0.987).
@MainActor final class SimPhone: HIDDevice {
    var links = 1
    var connected = true
    var sent: [String] = []
    var at = CGPoint.zero
    var clicks: [CGPoint] = []
    let units: (w: Double, h: Double)
    init(w: Double, h: Double) { units = (w, h) }

    func send(_ command: String) async throws -> String {
        sent.append(command)
        let parts = command.split(separator: " ")
        switch parts.first {
        case "home": at = .zero
        case "click": clicks.append(at)
        case "move":
            let mx = Double(parts[1])!, my = Double(parts[2])!
            at = CGPoint(x: min(max(at.x + mx / units.w, 0), 1), y: min(max(at.y + my / units.h, 0), 1))
        default: break
        }
        return ""
    }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { connected }
    func abort() async throws {}
    func seen() -> CGPoint { CGPoint(x: min(max(at.x, 0.02), 0.958), y: min(max(at.y, 0.012), 0.987)) }
}

@MainActor final class PointerAimTests: XCTestCase {
    private func pointer(_ phone: SimPhone, span: (Double, Double) = (494, 1110)) -> Pointer {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: phone, calibrationFile: file)
        p.finishCalibration(x: 200 / span.0, y: 200 / span.1)
        p.finder = { _, _ in phone.seen() }
        return p
    }

    /// log25: the saved span (494 x 1110) is far from the phone's (445 x 620). The tap on WeChat (0.85, 0.59)
    /// stopped in the corner; the one correction from there landed on Watch (y 0.24). The aim must home, measure
    /// the real scale and land on the target.
    func testPinnedPointerRehomesMeasuresAndLandsOnTarget() async throws {
        let phone = SimPhone(w: 445, h: 620)
        let p = pointer(phone)
        try await p.tap(0.85, 0.59, aim: true)
        let hit = try XCTUnwrap(phone.clicks.last)
        XCTAssertEqual(hit.x, 0.85, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(hit.y, 0.59, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(phone.sent.filter { $0 == "home" }.count, 2, "pinned in the corner: home again before correcting")
        XCTAssertTrue(p.stale)
        XCTAssertTrue(p.calibrated)
    }

    /// A wrong scale that never reaches the border is corrected by measuring each move, not by one guess.
    func testRepeatedCorrectionsLearnTheRealScale() async throws {
        let phone = SimPhone(w: 600, h: 1400)
        let p = pointer(phone)
        try await p.tap(0.85, 0.59, aim: true)
        let hit = try XCTUnwrap(phone.clicks.last)
        XCTAssertEqual(hit.x, 0.85, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(hit.y, 0.59, accuracy: Pointer.aimTolerance)
        XCTAssertTrue(p.stale, "a miss beyond maxMiss means the calibration no longer fits")
    }

    /// A good calibration keeps the old path: one move, one look, click.
    func testAccurateCalibrationMovesOnceAndStaysTrusted() async throws {
        let phone = SimPhone(w: 494, h: 1110)
        let p = pointer(phone)
        try await p.tap(0.85, 0.59, aim: true)
        XCTAssertEqual(phone.sent, ["release", "home", "move 420 655", "click"])
        XCTAssertFalse(p.stale)
    }

    /// Being stopped by the border hides how far the pointer overshot: stale even when the reading looks close.
    func testPinnedAtBorderNearTargetStillMarksStale() async throws {
        let phone = SimPhone(w: 445, h: 620)
        let p = pointer(phone)
        try await p.tap(0.30, 0.95, aim: true)
        let hit = try XCTUnwrap(phone.clicks.last)
        XCTAssertEqual(hit.y, 0.95, accuracy: Pointer.aimTolerance)
        XCTAssertTrue(p.stale)
    }

    /// Stale: every later tap aims (log25's first tap was a plain one and clicked the corner), the app asks to
    /// calibrate, the flag survives a restart, and a new calibration clears it.
    func testStaleCalibrationAimsPlainTapsUntilRecalibrated() async throws {
        let phone = SimPhone(w: 445, h: 620)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: phone, calibrationFile: file)
        p.finishCalibration(x: 200 / 494, y: 200 / 1110)
        p.finder = { _, _ in phone.seen() }
        try await p.tap(0.85, 0.59, aim: true)
        XCTAssertTrue(p.stale)
        try await p.tap(0.30, 0.40)  // no aim asked
        let hit = try XCTUnwrap(phone.clicks.last)
        XCTAssertEqual(hit.x, 0.30, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(hit.y, 0.40, accuracy: Pointer.aimTolerance)
        XCTAssertTrue(Pointer(device: phone, calibrationFile: file).stale)
        p.finishCalibration(x: 0.45, y: 0.32)
        XCTAssertFalse(p.stale)
        XCTAssertFalse(Pointer(device: phone, calibrationFile: file).stale)
    }
}
