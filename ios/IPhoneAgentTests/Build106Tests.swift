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

/// Over USB 11-09: a timer's wheel took Doubao 14 wrong swipes before Codex came at step 20 and did it with one tap.
@MainActor final class CodexComesEarlierTests: XCTestCase {
    func testAStepThatPlainlyFailedIsTrouble() {
        XCTAssertTrue(AgentLoop.isTrouble(["action": .str("tap"), "changed": .bool(false)]))
        XCTAssertTrue(AgentLoop.isTrouble(["action": .str("no ink")]))
        XCTAssertTrue(AgentLoop.isTrouble(["action": .str("blocked")]))
        XCTAssertFalse(AgentLoop.isTrouble(["action": .str("tap"), "changed": .bool(true)]))
        XCTAssertFalse(AgentLoop.isTrouble(["action": .str("stale plan")]), "the screen moved: not the executor's failure")
    }

    func testFiveSwipesInARowBringCodex() async {
        let planner = FakeModel { n in n <= 2 ? "1. The timer is set" : "THINK: tap the value\nDO: done set" }
        var n = 0
        let actor = FakeModel { _ in n += 1; return "THINK: turn the wheel\nDO: swipe 500 500 500 \(400 - n * 10)" }
        let phone = FakeGestures()
        let screen = FakeScreen()
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "把計時器設成一分鐘", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertTrue(agent.steps.contains { $0["action"] == .str("planner drives") })
        XCTAssertLessThanOrEqual(actor.prompts.count, 6, "Codex comes after the fifth swipe")
        XCTAssertEqual(agent.steps.last?["by"]?.str, "planner")
    }
}

/// User 11-09: what the phone has not done before, Codex does and it is remembered; Doubao follows it from then on.
@MainActor final class CodexTeachesDoubaoTests: XCTestCase {
    func testAnUnknownTaskIsDrivenByThePlanner() async {
        let planner = FakeModel { n in n == 1 ? "1. Settings is open" : "THINK: there\nDO: done ok" }
        let actor = FakeModel { _ in "THINK: not me\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.plannerLeadsUnknown = true
        agent.routes = RouteBook(file: nil)
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actor.prompts.count, 0, "the executor did nothing")
        XCTAssertEqual(agent.steps.last?["by"]?.str, "planner")
    }

    func testAKnownTaskIsFollowedByTheExecutor() async {
        let routes = RouteBook(file: nil)
        routes.storeRecipe(task: "打开设置", lines: ["open 设置"])
        let planner = FakeModel { _ in "1. should not be asked" }
        let actor = FakeModel { _ in "THINK: as before\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.plannerLeadsUnknown = true
        agent.routes = routes
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(planner.prompts.count, 0)
        XCTAssertEqual(agent.steps.last?["by"]?.str, "actor")
    }

    func testAPlannerThatAnswersNoActionHandsOver() async {
        let planner = FakeModel { _ in "1. only a plan" }
        let actor = FakeModel { _ in "THINK: mine now\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.plannerLeadsUnknown = true
        agent.routes = RouteBook(file: nil)
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.last?["by"]?.str, "actor")
    }

    func testWithoutPlusTheTaskStillRuns() async {
        let actor = FakeModel { n in n == 1 ? "1. Settings is open" : "THINK: there\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.plannerLeadsUnknown = true
        agent.routes = RouteBook(file: nil)
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.last?["action"]?.str, "done")
    }
}
