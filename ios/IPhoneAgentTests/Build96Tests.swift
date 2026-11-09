import XCTest
@testable import IPhoneAgent

/// build96 (logs(9) 11-08): a pointer click on the globe key opens the keyboard menu instead of switching, and every
/// tap went back to the corner first, so five globe taps took ~16 s and never brought Lan Agent's keyboard up.
@MainActor private final class HopPhone: HIDDevice {
    var links = 1
    var connected = true
    var at = CGPoint.zero
    var clicks: [CGPoint] = []
    var homes = 0
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func send(_ command: String) async throws -> String {
        if command == "curve" { return "on" }
        if command == "home" { at = .zero; homes += 1 }
        if command == "click" { clicks.append(at) }
        let parts = command.split(separator: " ")
        if parts.first == "move", parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) {
            at.x = min(max(at.x + x / 300, 0), 1)
            at.y = min(max(at.y + y / 650, 0), 1)
        }
        return ""
    }
}

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
        XCTAssertEqual(device.sent.filter { $0 == "home" }.count, 1)  // build97: hops from where it rests
        XCTAssertEqual(device.sent.filter { $0.hasPrefix("move") }.count, 3)
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

    func testLongPressHoldsThenLetsGoAndRepeatsInPlace() async throws {
        let (p, device) = pointer()
        try await p.longPress(0.122, 0.952, seconds: 0.05)
        try await p.longPress(0.122, 0.952, seconds: 0.05)
        XCTAssertEqual(device.sent.filter { $0.hasPrefix("move") }.count, 1)
        XCTAssertEqual(device.sent.filter { $0 == "press" }.count, 2)
        XCTAssertEqual(device.sent.filter { $0 == "release" }.count, 3)  // + the new link's release first
        XCTAssertEqual(device.sent.last, "release")
        XCTAssertFalse(device.sent.contains("click"))
    }

    // build97 (user 11-08): taps go from where the pointer rests, on the measured probe maps, and land where asked.
    func testNearbyHopsLandOnTheProbeMapsAndReHomeEverySixHops() async throws {
        let phone = HopPhone()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let mapX: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 75, "fraction": 0.25],
                                                           ["units": 225, "fraction": 0.75], ["units": 300, "fraction": 1]]]
        let mapY: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 130, "fraction": 0.2],
                                                           ["units": 520, "fraction": 0.8], ["units": 650, "fraction": 1]]]
        let saved: [String: Any] = ["w": 300, "h": 650, "quality": 0.01, "stale": false,
            "motionVersion": ProbeMotion.version, "requiresFeedback": false, "maps": ["x": mapX, "y": mapY]]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        let p = Pointer(device: phone, calibrationFile: file)
        let spots = [(0.2, 0.3), (0.6, 0.7), (0.25, 0.9), (0.8, 0.1), (0.5, 0.5), (0.1, 0.6), (0.9, 0.95), (0.3, 0.2)]
        for (x, y) in spots { try await p.tap(x, y) }
        XCTAssertEqual(phone.clicks.count, spots.count)
        for (hit, spot) in zip(phone.clicks, spots) {
            XCTAssertEqual(hit.x, spot.0, accuracy: 0.01)
            XCTAssertEqual(hit.y, spot.1, accuracy: 0.01)
        }
        XCTAssertEqual(phone.homes, 2, "the first tap and the one at the top (build 112) start from the corner")
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
