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
    var presses: [CGPoint] = []
    var minimum = CGPoint.zero
    var maximum = CGPoint(x: 1, y: 1)
    var sent: [String] = []
    private var homes = 0

    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func send(_ command: String) async throws -> String {
        sent.append(command)
        if command == "curve" { return "on" }
        if command == "home" { at = minimum; homes += 1 }
        if command == "click" { clicks.append(at) }
        if command == "press" { presses.append(at) }
        let parts = command.split(separator: " ")
        if parts.first == "move" {
            let x = Double(parts[1])!, y = Double(parts[2])!
            at.x += x / 300
            at.y += y / 650
            if abs(x) > 100 { at.x += homes.isMultiple(of: 2) ? 0.016 : -0.017 }
            if abs(y) > 200 { at.x += homes.isMultiple(of: 2) ? 0.016 : -0.030 }
            at.x = min(max(at.x, minimum.x), maximum.x)
            at.y = min(max(at.y, minimum.y), maximum.y)
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

    func testBackGestureCanStartAtTheVisiblePointerInset() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        phone.minimum = CGPoint(x: 0.02, y: 0.012)
        try await p.goBack()
        let start = try XCTUnwrap(phone.presses.first)
        XCTAssertEqual(start.x, 0.02, accuracy: 0.001)
        XCTAssertEqual(start.y, 0.45, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(phone.sent.last, "release")
    }

    func testAppSwitchCanStartAtTheVisibleBottomInset() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        phone.maximum.y = 0.987
        try await p.previousApp()
        try await p.nextApp()
        XCTAssertEqual(phone.presses.count, 2)
        for start in phone.presses { XCTAssertEqual(start.y, 0.987, accuracy: 0.001) }
        XCTAssertEqual(phone.presses[0].x, 0.2, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(phone.presses[1].x, 0.85, accuracy: Pointer.aimTolerance)
    }

    func testOrdinaryEdgeTapStillRequiresExactEndpoint() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        phone.minimum.x = 0.02
        do { try await p.tap(0.005, 0.45); XCTFail("a border gesture allowance must never relax ordinary taps") }
        catch is DeviceError { }
        XCTAssertTrue(phone.clicks.isEmpty)
    }

    func testBackGestureCannotPressAwayFromTheBorder() async throws {
        let phone = Logs42Phone(), (p, file) = try candidate(phone)
        defer { try? FileManager.default.removeItem(at: file) }
        phone.minimum.x = 0.04
        do { try await p.goBack(); XCTFail("an observed pointer away from the border cannot start a system gesture") }
        catch is DeviceError { }
        XCTAssertTrue(phone.presses.isEmpty)
    }
}
