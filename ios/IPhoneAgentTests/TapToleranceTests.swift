import XCTest
@testable import IPhoneAgent

/// Test build 122.1 (user 11-12): a first stop already inside the target is clicked without correcting. 476 taps on the
/// phone: 95% corrected at 2.0 s each, while 88% of first stops were inside a target the size of an input box.
@MainActor final class TapToleranceTests: XCTestCase {

    func testATapOnReadTextIsAsBigAsThatText() throws {
        let row = [CandidatePicker.Piece(text: "测试群", box: CGRect(x: 0.2, y: 0.38, width: 0.3, height: 0.04))]
        let half = try XCTUnwrap(AgentLoop.textHalf(at: CGPoint(x: 0.3, y: 0.4), in: [row]))
        XCTAssertEqual(half.x, 0.12, accuracy: 0.0001)
        XCTAssertEqual(half.y, 0.016, accuracy: 0.0001)
        XCTAssertNil(AgentLoop.textHalf(at: CGPoint(x: 0.9, y: 0.9), in: [row]), "no text there: corrected as before")
        let tiny = [CandidatePicker.Piece(text: "×", box: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01))]
        XCTAssertNil(AgentLoop.textHalf(at: CGPoint(x: 0.505, y: 0.505), in: [tiny]), "a small mark keeps the strict check")
    }
}
