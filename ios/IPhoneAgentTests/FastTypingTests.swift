import XCTest
@testable import IPhoneAgent

@MainActor final class FastTypingTests: XCTestCase {
    func testAReplyKeepsOnlyWhatThePinyinKeyboardCanType() {
        // logs(13): "～" failed every type and the reply never went out.
        XCTAssertEqual(WatchSettings.typeable("抱歉刚才没及时回复你～"), "抱歉刚才没及时回复你")
        XCTAssertEqual(WatchSettings.typeable("好的👌马上来…"), "好的马上来。")
        XCTAssertEqual(WatchSettings.typeable("在的，有什么事吗？"), "在的，有什么事吗？")
        XCTAssertEqual(WatchSettings.typeable("OK 3点见"), "OK 3点见")
        XCTAssertNil(WatchSettings.typeable("👍🎉"))
    }

    func testTheCandidateIsTheExactPieceOnTheLowestRowOfSeveral() {
        func piece(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: 0.06, height: 0.03))
        }
        let bubble = [piece("@蓝", 0.2, 0.42), piece("在的", 0.3, 0.42)]  // a chat line above the keyboard
        let field = [piece("在的zaide", 0.2, 0.5)]                       // the input field: one piece
        let candidates = [piece("在的", 0.05, 0.6), piece("在", 0.2, 0.6), piece("再", 0.3, 0.6)]
        let spot = CandidatePicker.find("在的", rows: [bubble, field, candidates])
        XCTAssertEqual(spot?.y ?? 0, 0.615, accuracy: 0.001)
        XCTAssertNil(CandidatePicker.find("在的话", rows: [bubble, field, candidates]))  // never a near match
    }

    func testTheKeyboardAndThePastePromptAreRecognised() {
        // logs(17): back from Lan Agent the keyboard was up and the box tap hit the space bar; iOS's paste prompt
        // was then tapped back and forth.
        func piece(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: 0.1, height: 0.03))
        }
        let nineKey = [[piece("123", 0.05, 0.67), piece("ABC", 0.45, 0.67), piece("DEF", 0.65, 0.67)],
                       [piece("选拼音", 0.25, 0.88), piece("选定", 0.55, 0.88)]]
        XCTAssertTrue(CandidatePicker.keyboardUp(rows: nineKey))
        let qwerty = [Array("QWERTYUIOP").enumerated().map { piece(String($1), 0.02 + 0.1 * Double($0), 0.7) }]
        XCTAssertTrue(CandidatePicker.keyboardUp(rows: qwerty))
        XCTAssertFalse(CandidatePicker.keyboardUp(rows: [[piece("蓝海乐", 0.2, 0.7), piece("@蓝 你在不在", 0.3, 0.72)]]))
        let prompt = [[piece("“微信”想从“Lan Agent”粘贴", 0.1, 0.45)], [piece("允许粘贴", 0.2, 0.55), piece("不允许粘贴", 0.6, 0.55)]]
        XCTAssertEqual(CandidatePicker.allowPaste(rows: prompt)?.x ?? 0, 0.25, accuracy: 0.001)  // allow, never "不允许"
        XCTAssertNil(CandidatePicker.allowPaste(rows: nineKey))
    }

    func testCharactersSplitIntoCandidatesAtWideGaps() {
        let w = 0.04
        func ch(_ c: Character, _ x: Double) -> (Character, CGRect) { (c, CGRect(x: x, y: 0.6, width: w, height: 0.03)) }
        let pieces = CandidatePicker.split([ch("在", 0.05), ch("的", 0.09), ch("在", 0.2), ch("再", 0.3)])
        XCTAssertEqual(pieces.map(\.text), ["在的", "在", "再"])
    }

    func testAPasteCountsOnlyWhenTheTextNewlyShows() {
        // the reply already in a bubble above does not confirm a paste; a new copy in the field does
        let before = CandidatePicker.count("在的，有什么事吗？", lines: ["我:在的,有什么事吗"])
        let after = CandidatePicker.count("在的，有什么事吗？", lines: ["我:在的,有什么事吗", "在的，有什么事吗？"])
        XCTAssertEqual(before, 1)
        XCTAssertEqual(after, 2)
        XCTAssertEqual(CandidatePicker.count("在的，有什么事吗？", lines: ["ark-2f3e5904-1157"]), 0)  // what the user had copied
        XCTAssertEqual(CandidatePicker.count("好", lines: ["好"]), 0)  // too short to tell: never confirmed
        XCTAssertTrue(Pasteboard.needed("在的") && !Pasteboard.needed("ok 7:00"))
    }
}
