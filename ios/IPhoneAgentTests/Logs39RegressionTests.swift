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

    func testUnverifiedProbeCannotOverwriteTheSavedCalibration() {
        let (_, _, file) = calibration()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testTwoPercentErrorCannotBeReportedAsCalibrated() {
        XCTAssertLessThanOrEqual(AutoCalibrator.maxCheckError, 0.015)
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

@MainActor private final class Logs39Screen: ScreenSource {
    var live = true
    var frame: Data? = Data([1])
    var updated = 0.0
    var capturedAt = 0.0
    var aspect = 0.46
    func afterAction(since: Double) async { frame = Data([2]) }
    func requireFrame(after: Double?) async throws {}
}
