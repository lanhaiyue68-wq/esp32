import XCTest
@testable import IPhoneAgent

/// A model whose first answers fail as if the phone had no network.
@MainActor private final class OfflineFirst: ChatModel {
    let model = "offline-first"
    private var calls = 0
    private let downFor: Int
    private let reply: (Int) -> String
    init(downFor: Int, _ reply: @escaping (Int) -> String) { (self.downFor, self.reply) = (downFor, reply) }
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        calls += 1
        if calls <= downFor { throw URLError(.cannotConnectToHost) }
        return ChatResult(text: reply(calls - downFor), firstToken: nil, total: 0)
    }
}

/// What 17 tasks on build 113 found (11-10).
@MainActor final class Build114Tests: XCTestCase {
    func testAThoughtRunOnAfterAKeyIsNotSentToTheBoard() throws {
        XCTAssertEqual(try Actions.parseCommand("key enterTHINK: 已輸入搜尋詞並提交")["combo"]?.str, "enter")
        XCTAssertEqual(try Actions.parseCommand("type TODO: buy milk")["text"]?.str, "TODO: buy milk", "still text")
    }

    func testWhatCountsAsNoNetwork() {
        XCTAssertTrue(ModelRequestFailure.isNetworkDown(URLError(.cannotConnectToHost)))
        XCTAssertTrue(ModelRequestFailure.isNetworkDown(URLError(.networkConnectionLost)))
        XCTAssertFalse(ModelRequestFailure.isNetworkDown(URLError(.timedOut)), "a slow model is not a missing network")
        XCTAssertFalse(ModelRequestFailure.isNetworkDown(LLMError(message: "LLM HTTP 500")))
        let wrapped = NSError(domain: "x", code: 1, userInfo: [NSUnderlyingErrorKey: URLError(.notConnectedToInternet) as NSError])
        XCTAssertTrue(ModelRequestFailure.isNetworkDown(wrapped))
    }

    func testANetworkDropDoesNotPutCodexToRestForLong() {
        let rest = PlusRest()
        XCTAssertEqual(rest.failed("网络连接已中断。", networkDown: true), PlusRest.offlineRest)
        XCTAssertEqual(rest.failures, 0, "the next real failure is still a first")
        XCTAssertTrue(rest.resting)
        XCTAssertEqual(rest.failed("请求超时。"), 120)
    }

    func testARunWaitsForTheNetworkInsteadOfEnding() async {
        let actor = OfflineFirst(downFor: 2) { _ in "THINK: finished\nDO: done 好了" }
        let planner = FakeModel { _ in "1. look" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "查", plan: "", steps: [], running: false)
        await agent.run()
        let kinds = agent.steps.map { $0["action"]?.str ?? "?" }
        XCTAssertEqual(kinds.last, "done", "\(kinds)")
        XCTAssertFalse(kinds.contains("error"), "\(kinds)")
    }

    func testTheBorderLiftIsLearnedFromWhereThePointerIsSeen() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: FakeDevice(), calibrationFile: file)
        let start = Pointer.borderLiftStart  // build 129: no longer 0
        p.learnBorderLift(missedBy: 0.010)
        XCTAssertEqual(p.borderLiftY, start + 0.0025, accuracy: 1e-9)  // a quarter of the way (129)
        p.learnBorderLift(missedBy: -0.010)
        XCTAssertEqual(p.borderLiftY, start, accuracy: 1e-9)
        p.learnBorderLift(missedBy: 0.3)
        XCTAssertEqual(p.borderLiftY, start, accuracy: 1e-9, "a misreading is not learned")
        p.learnBorderLift(missedBy: -0.073)  // 129 (g1): another thing taken for the pointer
        XCTAssertEqual(p.borderLiftY, start, accuracy: 1e-9, "0.05 off or more is not learned")
        for _ in 0..<20 { p.learnBorderLift(missedBy: 0.045) }
        XCTAssertEqual(p.borderLiftY, Pointer.borderLiftLimit, accuracy: 1e-9)
    }
}
