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
