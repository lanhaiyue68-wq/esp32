import XCTest
@testable import IPhoneAgent

/// A board that answers slowly, the way the real one does: gestures that overlap get in each other's way here.
@MainActor private final class SlowBoard: HIDDevice {
    var links = 1
    var connected = true
    var log: [String] = []
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func abort() async throws {}
    func send(_ command: String) async throws -> String {
        log.append(command)
        try await Task.sleep(nanoseconds: 2_000_000)
        return command == "curve" ? "on" : ""
    }
}

/// What the day of tests on build 110 found (11-09): a crash, a lost screen, an app standing still, answers nobody checked.
@MainActor final class Build111Tests: XCTestCase {
    private func pointer(_ board: HIDDevice) -> Pointer {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: board, calibrationFile: file)
        p.finishCalibration(x: 0.5, y: 0.25)
        return p
    }

    func testGesturesThatOverlapTakeTurns() async throws {
        let board = SlowBoard()
        let p = pointer(board)
        async let first: Void = p.tap(0.2, 0.2)
        async let second: Void = p.tap(0.8, 0.8)
        try await first
        try await second
        // One after the other, whichever came first: the second hops from where the first one left the pointer.
        let shape = board.log.filter { $0 != "curve" }.map { String($0.split(separator: " ")[0]) }
        XCTAssertEqual(shape, ["home", "move", "click", "move", "click"], "\(board.log)")
    }

    func testASpotThatDidNothingIsAimedAtAgainFromTheCorner() async throws {
        let board = SlowBoard()
        let p = pointer(board)
        for _ in 0...Pointer.clicksInPlaceLimit { try await p.tap(0.5, 0.5) }
        XCTAssertEqual(board.log.filter { $0 == "home" }.count, 1, "clicks again on the spot, up to the limit")
        try await p.tap(0.5, 0.5)
        XCTAssertEqual(board.log.filter { $0 == "home" }.count, 2, "then it goes back and looks")
    }

    func testAThoughtRunOnIsNotTyped() throws {
        XCTAssertEqual(try Actions.parseCommand("type 1152\"THINK: 請檢查筆記中的結果")["text"]?.str, "1152")
        XCTAssertEqual(try Actions.parseCommand("type 雨傘 DO: key enter")["text"]?.str, "雨傘")
        XCTAssertEqual(try Actions.parseCommand("tap 300 132 THINK: 第2個")["y"]?.int, 132)
        XCTAssertEqual(try Actions.parseCommand("type TODO: buy milk")["text"]?.str, "TODO: buy milk")
    }

    func testAListIsScrolledFromTheMargin() {
        let swipe: JObject = ["action": .str("swipe"), "x1": .int(500), "y1": .int(850), "x2": .int(500), "y2": .int(450)]
        let safe = AgentLoop.safeSwipe(swipe, after: [])
        XCTAssertEqual(safe["x1"]?.int, 40)
        XCTAssertEqual(safe["x2"]?.int, 40)
        XCTAssertEqual(safe["y1"]?.int, 800, "not from the bars at the bottom")
        XCTAssertEqual(safe["y2"]?.int, 400)
        let across: JObject = ["action": .str("swipe"), "x1": .int(800), "y1": .int(500), "x2": .int(200), "y2": .int(500)]
        XCTAssertEqual(AgentLoop.safeSwipe(across, after: [])["x1"]?.int, 800, "only a list scrolling up or down")
        var unmoved = safe
        unmoved["changed"] = .bool(false)
        XCTAssertEqual(AgentLoop.safeSwipe(swipe, after: [unmoved])["x1"]?.int, 500, "what the margin does not move gets the model's spot")
    }

    func testPlusRestsLongerEachTimeAcrossRuns() async throws {
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: "timed out"), 120)
        XCTAssertEqual(PlusRest.restSeconds(failures: 2, message: "timed out"), 600)
        XCTAssertEqual(PlusRest.restSeconds(failures: 9, message: "timed out"), 1800)
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: "HTTP 429：limit"), 1800)

        let rest = PlusRest()
        var calls = 0, said: [String] = []
        rest.onFailure = { said.append($0) }
        func run() -> PlusChat {  // a new one for every run, as RunSession makes them
            PlusChat(model: "m", fallback: FakeModel { _ in "doubao" }, tokens: { ChatGPTPlus.Tokens(idToken: "i", accessToken: "a", refreshToken: "r", accountID: "x") },
                     save: { _ in }, ask: { _, _, _, _, _ in calls += 1; throw ChatGPTPlus.Failure(message: "請求超時") }, rest: rest)
        }
        let first = try await run().chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        let second = try await run().chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(first.text, "doubao")
        XCTAssertEqual(second.text, "doubao")
        XCTAssertEqual(calls, 1, "the next run does not wait for Plus again")
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].contains("豆包"), "the user is told")
        rest.succeeded()
        XCTAssertFalse(rest.resting)
        XCTAssertEqual(rest.summary, "ok")
    }

    private func checkedRun(answers: [String], checks: [String]) async -> (AgentLoop, FakeModel) {
        var turn = 0, check = 0
        let actor = FakeModel { _ in defer { turn += 1 }; return "THINK: finished\nDO: done \(answers[min(turn, answers.count - 1)])" }
        let planner = FakeModel { _ in defer { check += 1 }; return check == 0 ? "1. look it up" : checks[min(check - 1, checks.count - 1)] }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.verifiesDone = true
        agent.showMock(task: "查日期", plan: "", steps: [], running: false)
        await agent.run()
        return (agent, planner)
    }

    func testAFinishedTaskIsCheckedBeforeItIsReported() async {
        let (agent, planner) = await checkedRun(answers: ["17 號", "16 號"], checks: ["NO: 畫面寫的是 16 號", "OK"])
        XCTAssertEqual(agent.steps.last?["action"]?.str, "done")
        XCTAssertEqual(agent.steps.last?["answer"]?.str, "16 號")
        let rejected = agent.steps.first { $0["action"]?.str == "done rejected" }
        XCTAssertTrue(rejected?["reason"]?.str?.contains("16 號") == true, "the model is told what is wrong")
        XCTAssertTrue(planner.prompts.contains { $0.contains("Its answer: 17 號") })
    }

    func testAnAnswerThatKeepsFailingIsNotReportedAsChecked() async {
        let (agent, _) = await checkedRun(answers: ["17 號"], checks: ["NO: 不對"])
        XCTAssertEqual(agent.steps.last?["action"]?.str, "done")
        XCTAssertEqual(agent.steps.last?["answer"]?.str, "（未能核實）17 號")
    }

    func testWhatCountsAsARejection() {
        XCTAssertNotNil(AgentLoop.wrongness("NO: 拼多多沒有打開"))
        XCTAssertNotNil(AgentLoop.wrongness("no"))
        XCTAssertNil(AgentLoop.wrongness("OK"))
        XCTAssertNil(AgentLoop.wrongness("Not sure, looks fine"), "only a plain NO stops the task")
        XCTAssertNil(AgentLoop.wrongness(""))
    }

    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x - 0.05, y: y - 0.01, width: 0.1, height: 0.02))
    }

    func testAnOpenFolderIsTold() {
        let folder = [[piece("3:00", 0.15, 0.03)], [piece("工具程式", 0.5, 0.25)],
                      [piece("計算機", 0.3, 0.4)], [piece("指南針", 0.5, 0.4)], [piece("測距儀", 0.7, 0.4)]]
        XCTAssertTrue(AppPlaces.looksLikeOpenFolder(folder))
        let home = [[piece("抖音", 0.15, 0.17)], [piece("淘宝", 0.15, 0.29)], [piece("搜尋", 0.5, 0.84)], [piece("美团", 0.85, 0.17)]]
        XCTAssertFalse(AppPlaces.looksLikeOpenFolder(home))
        let page = [[piece("這是一段很長很長的文字內容", 0.5, 0.3)], [piece("短", 0.5, 0.4)], [piece("短", 0.5, 0.5)]]
        XCTAssertFalse(AppPlaces.looksLikeOpenFolder(page))
    }

    func testAWrongPlaceIsForgottenAlone() {
        AppPlaces.clear()
        AppPlaces.learnPage(2, [[piece("抖音", 0.15, 0.17)], [piece("美团", 0.85, 0.17)]])
        AppPlaces.mapped = true
        AppPlaces.forget("抖音")
        XCTAssertNil(AppPlaces.page(of: "抖音"))
        XCTAssertEqual(AppPlaces.page(of: "美团"), 2)
        XCTAssertTrue(AppPlaces.mapped, "the other pages are not read again")
        AppPlaces.clear()
    }

    func testAnAppOpenedIsOnThePhone() {
        XCTAssertFalse(AppPlaces.wasOpened("從沒打開過的App"))
        AppPlaces.noteOpened("天氣")
        XCTAssertTrue(AppPlaces.wasOpened("天氣"))
    }

    func testTheStallWatchTellsAStuckMainThread() {
        typealias V = StallWatch.Verdict
        XCTAssertEqual(StallWatch.verdict(now: 10, lastMain: 9, stuckSince: nil), V.none)
        XCTAssertEqual(StallWatch.verdict(now: 14, lastMain: 9, stuckSince: nil), V.began)
        XCTAssertEqual(StallWatch.verdict(now: 15, lastMain: 9, stuckSince: 9), V.none, "still stuck: said once, at the end")
        XCTAssertEqual(StallWatch.verdict(now: 21, lastMain: 20.5, stuckSince: 9), V.ended(12))
        XCTAssertEqual(StallWatch.verdict(now: 5, lastMain: 0, stuckSince: nil), V.none, "nothing known yet")
    }

    func testRecognitionOffTheMainThreadReadsTheSame() async {
        // Not an image: nothing to read, the same way on both paths, and no crash.
        let same = await CandidatePicker.rowsOffMain(in: Data([0xff, 0xd8]), top: 0, bottom: 1)
        XCTAssertEqual(same.count, CandidatePicker.rows(in: Data([0xff, 0xd8]), top: 0, bottom: 1).count)
    }
}
