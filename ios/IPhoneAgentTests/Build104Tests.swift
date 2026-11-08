import XCTest
@testable import IPhoneAgent

/// Accuracy test 11-08 (three runs after a relaunch): screen sharing was off, no frame reached the pointer, and the
/// closed loop skipped every tap without a word. A tap with no frame must say so and report the eye as unseen.
@MainActor final class Build104Tests: XCTestCase {
    func testATapWithNoScreenFrameSaysTheEyeWasBlind() async throws {
        let screen = FakeScreen(); screen.frame = nil
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: FakeDevice(), calibrationFile: file, screen: screen)
        p.finishCalibration(x: 0.5, y: 0.25)
        var lines: [String] = []
        p.log = { lines.append($0) }
        try await p.tap(0.4, 0.6)
        XCTAssertEqual(p.lastArrival, .unseen)
        XCTAssertTrue(lines.contains { $0.contains("no screen frame") }, lines.joined(separator: "\n"))
    }
}
