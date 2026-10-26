import XCTest
@testable import IPhoneAgent

final class KeyboardRecognitionTests: XCTestCase {
    private func piece(_ text: String, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: 0.05, y: y, width: 0.9, height: 0.04))
    }

    func testOCRJoinedQwertyKeysStillMeanTheKeyboardIsVisible() {
        for label in ["qwertyuiop", "asdfghjkl", "zxcvbnm", "QWERTYUIOP"] {
            XCTAssertTrue(CandidatePicker.keyboardUp(rows: [[piece(label, 0.68)]]), label)
        }
    }

    func testOrdinaryWordsAndChatTextCannotStandInForKeyboardKeys() {
        for label in ["hello world", "CLAUDE", "这里有六个汉字", "你好"] {
            XCTAssertFalse(CandidatePicker.keyboardUp(rows: [[piece(label, 0.68)]]), label)
        }
    }
    func testOCRFragmentsOnTheSameKeyboardRowAreCombined() {
        let keys = ["qwer", "tyuiop"].enumerated().map { i, text in
            CandidatePicker.Piece(text: text, box: CGRect(x: Double(i) * 0.45, y: 0.65, width: 0.4, height: 0.035))
        }
        XCTAssertTrue(CandidatePicker.keyboardUp(rows: keys.map { [$0] }))
    }

}
