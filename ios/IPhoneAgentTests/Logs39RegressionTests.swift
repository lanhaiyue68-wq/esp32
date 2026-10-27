import XCTest
@testable import IPhoneAgent

@MainActor final class Logs39RegressionTests: XCTestCase {
    private func calibration() -> (Pointer, FakeDevice, URL) {
        let device = FakeDevice()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let pointer = Pointer(device: device, calibrationFile: file)
        // Recorded interior offsets from logs39. Extrapolating these lines to a back button
        // produced move 4 22, directly beside the red screen-sharing indicator.
        pointer.applyProbe(x: .init(a: 0.00345, b: 0.048, rms: 0.0304),
                           y: .init(a: 0.00152, b: 0.057, rms: 0.0191),
                           samples: [(70, 130, 0.252, 0.234), (211, 130, 0.744, 0.234),
                                     (70, 423, 0.252, 0.706), (211, 423, 0.744, 0.706),
                                     (141, 277, 0.545, 0.489), (141, 511, 0.545, 0.859)])
        return (pointer, device, file)
    }

    func testNearOriginDoesNotExtrapolateAnInteriorOffsetIntoTheStatusBar() async throws {
        let (pointer, device, _) = calibration()
        try await pointer.point(0.06, 0.09)
        let moves = device.sent.filter { $0.hasPrefix("move ") }.map { $0.split(separator: " ").dropFirst().map { Int($0)! } }
        XCTAssertGreaterThan(moves.map { $0[0] }.reduce(0, +), 12)
        XCTAssertGreaterThan(moves.map { $0[1] }.reduce(0, +), 40)
    }

    func testProbePositioningSeparatesAxesToAvoidDiagonalAcceleration() async throws {
        let (pointer, device, _) = calibration()
        try await pointer.point(0.5, 0.62)
        let moves = device.sent.filter { $0.hasPrefix("move ") }.map { $0.split(separator: " ") }
        XCTAssertGreaterThanOrEqual(moves.count, 2)
        XCTAssertTrue(moves.allSatisfy { $0[1] == "0" || $0[2] == "0" })
    }

    func testPositioningLandsWhenDiagonalMotionHasADifferentGain() async throws {
        let device = AxisCoupledPhone()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let pointer = Pointer(device: device, calibrationFile: file)
        pointer.applyProbe(x: .init(a: 1 / 300, b: 0, rms: 0), y: .init(a: 1 / 650, b: 0, rms: 0),
            samples: [(75, 163, 0.25, 163.0 / 650), (225, 488, 0.75, 488.0 / 650)])
        try await pointer.tap(0.5, 0.62)
        XCTAssertEqual(device.at.x, 0.5, accuracy: 0.005)
        XCTAssertEqual(device.at.y, 0.62, accuracy: 0.005)
        XCTAssertEqual(device.clicks, 1)
    }

    func testUnverifiedProbeCannotOverwriteTheSavedCalibration() {
        let (_, _, file) = calibration()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTwoPercentErrorCannotBeReportedAsCalibrated() {
        XCTAssertLessThanOrEqual(AutoCalibrator.maxCheckError, 0.015)
    }

    func testFailedValidationDoesNotPersistTheCandidate() {
        let (pointer, _, file) = calibration()
        pointer.setQuality(0.02)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(pointer.calibrated)
    }

    func testOneGoodCheckCannotHideTheObservedScatter() {
        let device = FakeDevice()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let pointer = Pointer(device: device, calibrationFile: file)
        pointer.applyProbe(x: .init(a: 0.0035, b: 0.04, rms: 0.03), y: .init(a: 0.0015, b: 0.05, rms: 0.01),
            samples: [(70, 130, 0.252, 0.234), (70, 433, 0.306, 0.706),
                      (211, 130, 0.744, 0.234), (211, 433, 0.777, 0.706)])
        pointer.setQuality(0.01)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(pointer.calibrated)
    }

    func testValidatedEdgeMappingSurvivesRestart() async throws {
        let (pointer, device, file) = calibration()
        pointer.setQuality(0.01)
        let loaded = Pointer(device: device, calibrationFile: file)
        try await loaded.point(0.06, 0.09)
        let moves = device.sent.filter { $0.hasPrefix("move ") }.map { $0.split(separator: " ").dropFirst().map { Int($0)! } }
        XCTAssertGreaterThan(moves.map { $0[0] }.reduce(0, +), 12)
        XCTAssertGreaterThan(moves.map { $0[1] }.reduce(0, +), 40)
        XCTAssertTrue(moves.allSatisfy { $0[0] == 0 || $0[1] == 0 })
    }

    func testReturningFromChatDoesNotTapBesideScreenSharingIndicator() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures(), screen = Logs39Screen()
        let ok = await state.resume(phone: phone, screen: screen, canAct: { true },
            inspect: { frame, _ in frame == Data([1]) ? .chat(CGPoint(x: 0.06, y: 0.09)) : .list },
            fallback: { false })
        XCTAssertTrue(ok)
        XCTAssertFalse(phone.calls.contains("tap"))
        XCTAssertEqual(phone.calls.count, 1)
    }
}

/// A counterexample to independent linear diagonal movement, not a claim to emulate iOS acceleration exactly.
@MainActor private final class AxisCoupledPhone: HIDDevice {
    var links = 1
    var connected = true
    var at = CGPoint.zero
    var clicks = 0
    func send(_ command: String) async throws -> String {
        let p = command.split(separator: " ")
        if p.first == "home" { at = .zero }
        if p.first == "click" { clicks += 1 }
        if p.first == "move" {
            let x = Double(p[1])!, y = Double(p[2])!
            let gain = x != 0 && y != 0 ? 1.14 : 1.0
            at.x += x / 300 * gain; at.y += y / 650 * gain
        }
        return "ok"
    }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func abort() async throws {}
}

@MainActor private final class Logs39Screen: ScreenSource {
    var live = true
    var frame: Data? = Data([1])
    var updated = 0.0
    var capturedAt = 0.0
    var aspect = 0.46
    func afterAction(since: Double) async { frame = Data([2]) }
    func requireFrame(after: Double?) async throws {}
}
