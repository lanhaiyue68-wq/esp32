import XCTest
@testable import IPhoneAgent

/// Recorded failure class: the long curved move has variable gain and the
/// following Y move can change X. This fake is a counterexample to a fixed map,
/// not a numerical model of Apple's acceleration.
@MainActor private final class Logs42Phone: HIDDevice {
    var links = 1
    var connected = true
    var at = CGPoint.zero
    var clicks: [CGPoint] = []
    var sent: [String] = []
    private var homes = 0

    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func send(_ command: String) async throws -> String {
        sent.append(command)
        if command == "curve" { return "on" }
        if command == "home" { at = .zero; homes += 1 }
        if command == "click" { clicks.append(at) }
        let parts = command.split(separator: " ")
        if parts.first == "move" {
            let x = Double(parts[1])!, y = Double(parts[2])!
            at.x += x / 300
            at.y += y / 650
            if abs(x) > 100 { at.x += homes.isMultiple(of: 2) ? 0.016 : -0.017 }
            if abs(y) > 200 { at.x += homes.isMultiple(of: 2) ? 0.016 : -0.030 }
            at.x = min(max(at.x, 0), 1); at.y = min(max(at.y, 0), 1)
        }
        return ""
    }
}

@MainActor final class Logs42RegressionTests: XCTestCase {
    private func candidate(_ phone: Logs42Phone, scatter: Double = 0) throws -> (Pointer, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let mapX: [String: Any] = ["scatter": scatter, "knots": [
            ["units": 0, "fraction": 0], ["units": 75, "fraction": 0.25], ["units": 225, "fraction": 0.75]]]
        let mapY: [String: Any] = ["scatter": scatter, "knots": [
            ["units": 0, "fraction": 0], ["units": 163, "fraction": 163.0 / 650], ["units": 488, "fraction": 488.0 / 650]]]
        let saved: [String: Any] = ["w": 300, "h": 650, "quality": 0.01, "stale": false,
            "motionVersion": ProbeMotion.version, "requiresFeedback": true, "maps": ["x": mapX, "y": mapY]]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        let p = Pointer(device: phone, calibrationFile: file)
        p.finder = { _, _ in phone.at }
        return (p, file)
    }

    func testOrdinaryTapsCorrectChangingCurveLandingsBeforeClicking() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        for _ in 0..<2 { try await p.tap(0.5, 0.62) }
        XCTAssertEqual(phone.clicks.count, 2)
        for hit in phone.clicks {
            XCTAssertEqual(hit.x, 0.5, accuracy: Pointer.aimTolerance)
            XCTAssertEqual(hit.y, 0.62, accuracy: Pointer.aimTolerance)
        }
        XCTAssertFalse(phone.sent.contains("curve off"))
    }

    func testOrdinaryTapWithMissingFeedbackNeverClicks() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        p.finder = { _, _ in nil }
        do { try await p.tap(0.5, 0.62); XCTFail("unobserved curved endpoint must not be clicked") }
        catch is DeviceError { }
        XCTAssertTrue(phone.clicks.isEmpty)
    }

    func testGestureCannotPressWithoutEndpointFeedback() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        p.finder = { _, _ in nil }
        do { try await p.swipe(0.5, 0.62, 0.5, 0.3); XCTFail("unobserved start must not be pressed") }
        catch is DeviceError { }
        XCTAssertFalse(phone.sent.contains("press"))
    }

    func testMeasuredFeedbackQualityRetainsRawScatterAndSurvivesRestart() throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone, scatter: 0.04)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(p.setQuality(0.01), "feedback quality measures final physical clicks; raw scatter is the initial estimate's uncertainty")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(saved["requiresFeedback"] as? Bool, true, "restarting must never silently restore open-loop taps")
        let loaded = Pointer(device: phone, calibrationFile: file)
        XCTAssertEqual(loaded.probeScatter, 0.04, accuracy: 0.0001, "do not erase bad raw samples")
        XCTAssertEqual(try XCTUnwrap(loaded.quality), 0.01, accuracy: 0.0001)
        XCTAssertFalse(loaded.stale)
    }

    func testFeedbackCannotAcceptARealTwoPercentMiss() throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(p.setQuality(0.02))
        XCTAssertTrue(p.stale)
    }
}
