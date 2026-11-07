import Network
import XCTest
@testable import IPhoneAgent

/// specs/004 phase A: the keyboard's line protocol, the app's 127.0.0.1 bridge, and the ChatGPT Plus parsing.
@MainActor final class KeyboardLinkTests: XCTestCase {
    func testRequestsRoundTrip() {
        for request: KeyboardLink.Request in [.hello(fullAccess: true), .hello(fullAccess: false), .next, .done(id: "ab12", ok: true)] {
            XCTAssertEqual(KeyboardLink.request(KeyboardLink.line(request)), request)
        }
        XCTAssertNil(KeyboardLink.request("PASTE everything"))
    }

    func testAJobKeepsChineseAndNewlinesOnOneLine() throws {
        let job = KeyboardLink.Job(id: "x1", text: "收到，我去处理。\n第二行 ✅", enter: true)
        let line = KeyboardLink.line(job)
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1, "one line on the wire")
        XCTAssertEqual(KeyboardLink.job(line), job)
        XCTAssertNil(KeyboardLink.job(KeyboardLink.line(nil)))
    }

    /// The bridge over a real loopback connection: a fake keyboard asks NEXT, gets the text once, confirms DONE.
    func testTheBridgeHandsTheTextToTheKeyboardOnceAndHearsItWasTyped() async throws {
        let bridge = KeyboardBridge(port: 47_831)  // the app this test runs in listens on the real port
        bridge.start()
        try await Task.sleep(nanoseconds: 300_000_000)
        async let typed = bridge.type("你好，Lan Agent", enter: false, within: 5)
        try await Task.sleep(nanoseconds: 200_000_000)
        let first = await Self.exchange(KeyboardLink.line(.next), port: 47_831)
        let job = try XCTUnwrap(first.flatMap(KeyboardLink.job))
        XCTAssertEqual(job.text, "你好，Lan Agent")
        let again = await Self.exchange(KeyboardLink.line(.next), port: 47_831)
        XCTAssertNil(again.flatMap(KeyboardLink.job), "handed out once: never typed twice")
        _ = await Self.exchange(KeyboardLink.line(.done(id: job.id, ok: true)), port: 47_831)
        let ok = await typed
        XCTAssertTrue(ok)
        XCTAssertNotNil(bridge.lastSeen)
    }

    func testTextNobodyPicksUpTimesOut() async {
        let bridge = KeyboardBridge(port: 47_832)
        bridge.start()
        let ok = await bridge.type("没人来拿", enter: false, within: 0.5)
        XCTAssertFalse(ok)
    }

    /// What the keyboard does: one line out, one line back.
    nonisolated static func exchange(_ line: String, port: UInt16) async -> String? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "fake-keyboard")
            let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            var done = false
            func finish(_ text: String?) {
                guard !done else { return }
                done = true
                connection.cancel()
                continuation.resume(returning: text)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data(line.utf8), completion: .contentProcessed { _ in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                            finish(data.flatMap { String(data: $0, encoding: .utf8) })
                        }
                    })
                case .failed, .waiting: finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 2) { finish(nil) }
        }
    }
}

final class ChatGPTPlusParsingTests: XCTestCase {
    func testTheDeviceCodeReplyWithItsIntervalAsText() throws {
        let data = Data(#"{"device_auth_id":"dev_1","usercode":"ABCD-1234","interval":"5"}"#.utf8)
        let parsed = try XCTUnwrap(ChatGPTPlus.parseUserCode(data))
        XCTAssertEqual(parsed.id, "dev_1")
        XCTAssertEqual(parsed.code, "ABCD-1234")
        XCTAssertEqual(parsed.interval, 5)
        XCTAssertNil(ChatGPTPlus.parseUserCode(Data("{}".utf8)))
    }

    func testTheAccountIdComesFromTheIdTokenClaims() {
        let claims = #"{"https://api.openai.com/auth":{"chatgpt_account_id":"acct-42"}}"#
        let payload = Data(claims.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(ChatGPTPlus.accountID(idToken: "e30.\(payload).sig"), "acct-42")
        XCTAssertNil(ChatGPTPlus.accountID(idToken: "not-a-jwt"))
    }

    func testListedModelsComeBeforeHiddenOnes() {
        let data = Data(#"{"models":[{"slug":"hidden-x","visibility":"hide"},{"slug":"gpt-5.6-sol","visibility":"list"}]}"#.utf8)
        XCTAssertEqual(ChatGPTPlus.modelSlugs(data), ["gpt-5.6-sol", "hidden-x"])
    }

    func testTheStreamCollectsTextUntilCompleted() {
        var sse = ChatGPTPlus.SSE()
        for line in ["event: response.output_text.delta",
                     #"data: {"type":"response.output_text.delta","delta":"这是"}"#,
                     #"data: {"type":"response.output_text.delta","delta":"微信聊天"}"#,
                     #"data: {"type":"response.completed","response":{}}"#] { sse.feed(line) }
        XCTAssertEqual(sse.text, "这是微信聊天")
        XCTAssertTrue(sse.done)
        XCTAssertNil(sse.error)
    }

    func testAFailedStreamReportsItsMessage() {
        var sse = ChatGPTPlus.SSE()
        sse.feed(#"data: {"type":"response.failed","response":{"error":{"message":"usage limit reached"}}}"#)
        XCTAssertEqual(sse.error, "usage limit reached")
    }

    func testTheTokenFormIsPercentEncoded() {
        let body = String(data: ChatGPTPlus.formBody([("redirect_uri", "https://auth.openai.com/deviceauth/callback"), ("code", "a b")]), encoding: .utf8)
        XCTAssertEqual(body, "redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback&code=a%20b")
    }
}
