import XCTest
@testable import IPhoneAgent

/// build96 (logs(9) 11-08): a pointer click on the globe key opens the keyboard menu instead of switching, and every
/// tap went back to the corner first, so five globe taps took ~16 s and never brought Lan Agent's keyboard up.
@MainActor final class Build96Tests: XCTestCase {
    private func pointer() -> (Pointer, FakeDevice) {
        let device = FakeDevice()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: device, calibrationFile: file)
        p.finishCalibration(x: 0.5, y: 0.25)  // span 400 x 800
        return (p, device)
    }

    func testTheSameSpotAgainClicksWithoutMoving() async throws {
        let (p, device) = pointer()
        for _ in 0..<3 { try await p.tap(0.122, 0.952) }
        XCTAssertEqual(device.sent.filter { $0 == "home" }.count, 1)
        XCTAssertEqual(device.sent.filter { $0.hasPrefix("move") }.count, 1)
        XCTAssertEqual(device.sent.filter { $0 == "click" }.count, 3)
        XCTAssertEqual(device.sent.last, "click")
    }

    func testAnotherSpotInBetweenMovesAgain() async throws {
        let (p, device) = pointer()
        try await p.tap(0.122, 0.952)
        try await p.tap(0.2, 0.78)
        try await p.tap(0.122, 0.952)
        XCTAssertEqual(device.sent.filter { $0 == "home" }.count, 3)
        XCTAssertEqual(device.sent.filter { $0 == "click" }.count, 3)
    }

    func testANewBoardLinkOrAResetMovesAgain() async throws {
        let (p, device) = pointer()
        try await p.tap(0.5, 0.5)
        device.links += 1
        try await p.tap(0.5, 0.5)
        try await p.reset()
        try await p.tap(0.5, 0.5)
        XCTAssertEqual(device.sent.filter { $0.hasPrefix("move") }.count, 3)
    }

    func testClickAgainOnlyInPlaceAndRecently() {
        let last = Pointer.LastClick(x: 0.122, y: 0.952, ux: 49, uy: 762, link: 1, time: 100)
        XCTAssertTrue(Pointer.clickAgain(last, 0.122, 0.952, units: (49, 762), link: 1, at: 105))
        XCTAssertTrue(Pointer.clickAgain(last, 0.124, 0.950, units: (49, 762), link: 1, at: 105))
        XCTAssertFalse(Pointer.clickAgain(last, 0.2, 0.952, units: (49, 762), link: 1, at: 105))   // another spot
        XCTAssertFalse(Pointer.clickAgain(last, 0.122, 0.952, units: (50, 762), link: 1, at: 105))  // pointer moved since
        XCTAssertFalse(Pointer.clickAgain(last, 0.122, 0.952, units: (49, 762), link: 2, at: 105))  // board reconnected
        XCTAssertFalse(Pointer.clickAgain(last, 0.122, 0.952, units: (49, 762), link: 1, at: 200))  // too long ago
    }

    private func piece(_ text: String, _ x: Double, _ y: Double, _ w: Double = 0.2) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: text, box: CGRect(x: x, y: y, width: w, height: 0.025))
    }

    /// The menu in logs(9) frame 20261108-023903/016.jpg (592x1280).
    private var menu: [[CandidatePicker.Piece]] {
        [[piece("鍵盤設定…", 0.084, 0.415, 0.23)], [piece("繁體手寫", 0.084, 0.475)], [piece("简体拼音", 0.084, 0.537)],
         [piece("English", 0.084, 0.598, 0.17), piece("(US)", 0.27, 0.598, 0.06)], [piece("表情符號", 0.084, 0.66)],
         [piece("繁體拼音", 0.084, 0.72)], [piece("Lan", 0.084, 0.772, 0.06), piece("Agent", 0.155, 0.772, 0.13)],
         [piece("中文", 0.084, 0.8, 0.06)], [piece("DEF", 0.65, 0.66, 0.1), piece("MNO", 0.65, 0.73, 0.1)]]
    }

    func testFindsLanAgentInTheKeyboardMenu() throws {
        let spot = try XCTUnwrap(CandidatePicker.keyboardMenuEntry(rows: menu))
        XCTAssertEqual(spot.x, 0.1845, accuracy: 0.01)
        XCTAssertEqual(spot.y, 0.7845, accuracy: 0.01)
    }

    func testMenuOpenOnlyWithMenuRows() {
        XCTAssertTrue(CandidatePicker.keyboardMenuOpen(rows: menu))
        XCTAssertFalse(CandidatePicker.keyboardMenuOpen(rows: [[piece("拼音", 0.1, 0.9), piece("空格", 0.4, 0.9)],
                                                               [piece("DEF", 0.65, 0.66, 0.1)]]))
    }

    func testNoMenuNoEntry() {
        // A chat line that reads "Lan Agent" over an ordinary keyboard: no menu rows, nothing to click.
        let chat: [[CandidatePicker.Piece]] = [[piece("Lan", 0.084, 0.4, 0.06), piece("Agent", 0.155, 0.4, 0.13)],
                                               [piece("拼音", 0.1, 0.9), piece("空格", 0.4, 0.9)]]
        XCTAssertNil(CandidatePicker.keyboardMenuEntry(rows: chat))
        // A longer bubble mentioning it beside an open menu is not the menu row.
        var rows = menu.filter { !$0.contains { $0.text == "Lan" } }
        rows.append([piece("Lan", 0.084, 0.3, 0.06), piece("Agent", 0.155, 0.3, 0.13), piece("輸入法測試", 0.3, 0.3)])
        XCTAssertNil(CandidatePicker.keyboardMenuEntry(rows: rows))
        // Right-hand text is not in the menu's column.
        rows.append([piece("Lan", 0.8, 0.2, 0.06), piece("Agent", 0.87, 0.2, 0.1)])
        XCTAssertNil(CandidatePicker.keyboardMenuEntry(rows: rows))
    }
}
