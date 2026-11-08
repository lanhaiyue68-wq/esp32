import XCTest
@testable import IPhoneAgent

/// The USB test channel: only a request with the token on the phone gets anything, and requests are read whole.
@MainActor final class TestChannelTests: XCTestCase {
    private func request(_ text: String) -> Data { Data(text.utf8) }

    func testARequestIsReadWhole() throws {
        let raw = "POST /run?from=3&a=b%20c HTTP/1.1\r\nHost: x\r\nX-Token: abc\r\nContent-Length: 13\r\n\r\n{\"task\":\"hi\"}"
        let r = try XCTUnwrap(TestChannel.parse(request(raw)))
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.path, "/run")
        XCTAssertEqual(r.query, ["from": "3", "a": "b c"])
        XCTAssertEqual(r.token, "abc")
        XCTAssertEqual(String(data: r.body, encoding: .utf8), "{\"task\":\"hi\"}")
    }

    func testAPartOfARequestWaitsForTheRest() {
        XCTAssertNil(TestChannel.parse(request("GET /status HTTP/1.1\r\nX-Token: a")))
        XCTAssertNil(TestChannel.parse(request("POST /run HTTP/1.1\r\nContent-Length: 13\r\n\r\n{\"task\"")))
    }

    func testOnlyTheTokenOnThePhoneIsLetIn() throws {
        let with = try XCTUnwrap(TestChannel.parse(request("GET /status HTTP/1.1\r\nX-Token: 0123456789abcdef\r\n\r\n")))
        let without = try XCTUnwrap(TestChannel.parse(request("GET /status HTTP/1.1\r\n\r\n")))
        XCTAssertTrue(TestChannel.authorized(with, token: "0123456789abcdef"))
        XCTAssertFalse(TestChannel.authorized(with, token: "fedcba9876543210"))
        XCTAssertFalse(TestChannel.authorized(with, token: nil), "no file on the phone: nothing is let in")
        XCTAssertFalse(TestChannel.authorized(without, token: "0123456789abcdef"))
    }
}

/// Measured over USB 11-09: a flick on the Home Screen opens the app switcher, so Home must look first.
@MainActor final class HomeByTheScreenTests: XCTestCase {
    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x - 0.05, y: y - 0.01, width: 0.1, height: 0.02))
    }

    func testSearchIsKnownByItsHeadersAndIsNotAHomeScreen() {
        let search = [[piece("Siri 建議", 0.15, 0.09)], [piece("顯示較多", 0.85, 0.09)], [piece("搜尋", 0.2, 0.54)]]
        XCTAssertTrue(AppPlaces.inSearch(search))
        XCTAssertFalse(AppPlaces.looksLikeHome(search))
    }

    func testAnAppsManyLabelsAreNotAHomeScreen() {
        // The app switcher's card of Lan Agent, read: short words, not in the icon columns.
        let card = ["開發板", "直接取屏", "滑鼠", "指標", "模型", "任務", "示例", "自主學習", "開始", "服務"].enumerated().map { i, text in
            [piece(text, 0.3 + Double(i % 3) * 0.14, 0.3 + Double(i) * 0.05)]
        }
        XCTAssertFalse(AppPlaces.looksLikeHome(card))
    }

    func testSearchsAppResultIsAboveItsWebSuggestion() {
        let results = [[piece("最佳搜尋結果", 0.2, 0.09)], [piece("備忘錄", 0.15, 0.22)], [piece("建議", 0.1, 0.3)], [piece("備忘錄", 0.25, 0.34)]]
        XCTAssertEqual(AppPlaces.searchResult("備忘錄", in: results)?.y ?? 0, 0.22, accuracy: 0.001)
        let webOnly = [[piece("建議", 0.1, 0.15)], [piece("備忘錄", 0.25, 0.2)]]
        XCTAssertNil(AppPlaces.searchResult("備忘錄", in: webOnly), "only Safari's row: the app is not there")
    }

    func testAHomeWithAFlickableScreenGoesHomeOnce() async throws {
        // Without eyes, as before: one flick.
        let device = FakeDevice()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: device, calibrationFile: file)
        try await p.goHome()
        XCTAssertEqual(device.sent, ["flickhome"])
    }
}
