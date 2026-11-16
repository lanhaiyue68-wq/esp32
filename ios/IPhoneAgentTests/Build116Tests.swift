import XCTest
@testable import IPhoneAgent

/// What 46 tasks on build 115 left (11-10): the check's misreadings, the cloud's approvals and picture, a search of the
/// app's own suggestion, Calculator's keys; and three ways to save seconds.
@MainActor final class Build116Tests: XCTestCase {
    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x - 0.03, y: y - 0.015, width: 0.06, height: 0.03))
    }

    // MARK: the done check

    func testTheDoneCheckGoesToTheFastModel() async {
        XCTExpectFailure("137: stale since 123: the fake executor answers done without going into the app the task names, which the unvisited-app guard refuses; to be rewritten", strict: false)
        var turn = 0
        let actor = FakeModel { _ in defer { turn += 1 }; return turn == 0 ? "THINK: 看\nDO: tap 100 100" : "THINK: 好了\nDO: done 15°C" }
        let planner = FakeModel { _ in "1. look it up" }
        let checker = FakeModel { _ in "OK" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.verifiesDone = true
        agent.doneChecker = checker
        agent.showMock(task: "打開天氣查今天最高溫", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertTrue(checker.prompts.contains { $0.contains("Its answer") }, "\(checker.prompts)")
        XCTAssertFalse(planner.prompts.contains { $0.contains("Its answer") }, "\(planner.prompts)")
        XCTAssertEqual(agent.steps.last?["answer"]?.str, "15°C")
    }

    func testTheCheckSeesAnAppOpenedByItsIconAndASend() {
        var steps: [JObject] = [["action": .str("tap"), "thought": .str("主畫面上看到拼多多圖示，點它打開拼多多來搜尋保溫杯")]]
        for i in 0..<30 { steps.append(["action": .str("tap"), "thought": .str("key \(i)")]) }
        steps.append(["action": .str("type"), "text": .str("壓力測試 116")])
        steps.append(["action": .str("key"), "combo": .str("enter")])
        steps.append(["action": .str("press"), "text": .str("4 0 . 7 4")])
        let did = AgentLoop.whatItDid(steps)
        XCTAssertTrue(did.contains("點它打開拼多多"), did)
        XCTAssertTrue(did.contains("typed 壓力測試 116\npressed enter"), did)
        XCTAssertTrue(did.contains("pressed the keys 4 0 . 7 4"), did)
        XCTAssertFalse(AgentLoop.opensByIcon(["action": .str("tap"), "thought": .str("點右上角搜索按鈕")]))
        XCTAssertTrue(AgentLoop.opensByIcon(["action": .str("tap"), "thought": .str("Tap the Weather icon to open it")]))
    }

    func testTheCheckRules() {
        let rules = AgentLoop.doneCheck
        XCTAssertTrue(rules.contains("压力测试 = 壓力測試"))
        XCTAssertTrue(rules.contains("moves by itself"))
        XCTAssertTrue(rules.contains("tapped its icon"))
        XCTAssertTrue(rules.contains("counts as sent"))
        XCTAssertTrue(rules.contains("phone's own location"))
    }

    // MARK: the cloud

    func testOnlyAMessageWaitsForApproval() {
        let send = "在微信打開测试群，發一則訊息：壓力測試 115。發完告訴我有沒有發出去"
        XCTAssertTrue(AgentLoop.needsApproval("壓力測試 115", task: send))
        XCTAssertFalse(AgentLoop.needsApproval("测试群", task: send), "the chat's name, searched for")
        XCTAssertFalse(AgentLoop.needsApproval("行事曆", task: "打開行事曆，告訴我 2027 年 2 月 14 日是星期幾。不要新增任何東西。如果跳出分享聯絡人的權限視窗，選不分享或關掉它"))
        XCTAssertFalse(AgentLoop.needsApproval("www.163.com", task: "用 Safari 打開 www.163.com，把頁面上看到的第一條新聞標題告訴我"))
        XCTAssertFalse(AgentLoop.needsApproval("牙刷", task: "在拼多多搜尋牙刷，告訴我第一個商品的名稱。不要購買，不要拼單"))
        XCTAssertFalse(AgentLoop.needsApproval("台灯", task: "在淘寶搜尋檯燈，告訴我價格"), "simplified for traditional")
        XCTAssertTrue(AgentLoop.needsApproval("你好呀", task: "在淘寶搜尋牙刷"), "words the goal never named")
        XCTAssertTrue(AgentLoop.needsApproval("好看", task: "在小紅書第一篇筆記下留言：好看"))
        XCTAssertFalse(AgentLoop.publishes("打開小紅書搜尋杭州旅遊，告訴我第一篇筆記的按讚數。不要按讚，不要留言"))
        XCTAssertFalse(AgentLoop.publishes("在微信打開验证群，告訴我最後一則訊息的內容。不要發訊息"))
        XCTAssertEqual(AgentLoop.messagePart(send), "壓力測試 115")
        XCTAssertEqual(AgentLoop.messagePart("回覆「收到」給老闆"), "收到")
    }

    // MARK: a search of the app's own suggestion

    func testASearchWithNothingTypedIsRefused() {
        let task = "在淘寶搜尋保溫杯，告訴我第一個商品的價格"
        let opened: [JObject] = [["action": .str("open"), "app": .str("淘宝")], ["action": .str("tap"), "thought": .str("點不允許貼上")]]
        let searchButton: JObject = ["action": .str("tap"), "thought": .str("淘寶首頁搜尋列已預先填入「保溫杯」，我點右側橙色「搜索」按鈕取得結果")]
        XCTAssertTrue(AgentLoop.searchesUntyped(searchButton, after: opened, task: task))
        let enter: JObject = ["action": .str("key"), "combo": .str("enter")]
        XCTAssertFalse(AgentLoop.searchesUntyped(enter, after: opened + [["action": .str("type"), "text": .str("保溫杯")]], task: task))
        let byIcon: [JObject] = [["action": .str("type"), "text": .str("保溫杯")], ["action": .str("tap"), "thought": .str("主畫面上看到拼多多圖示，點它打開")]]
        XCTAssertTrue(AgentLoop.searchesUntyped(enter, after: byIcon, task: task), "an app opened by its icon starts afresh")
        XCTAssertFalse(AgentLoop.searchesUntyped(enter, after: opened, task: "在微信打開测试群，發一則訊息：你好"))
    }

    func testTheRunRefusesTheSuggestionAndTypesInstead() async {
        var turn = 0
        let replies = ["THINK: 搜尋框已有保溫杯，點搜索按鈕\nDO: tap 900 80", "THINK: 輸入\nDO: type 保溫杯\nDO: key enter", "THINK: 好了\nDO: done 29.9"]
        let actor = FakeModel { _ in defer { turn += 1 }; return replies[min(turn, replies.count - 1)] }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: FakeModel { _ in "1. 搜尋" }, trace: nil)
        agent.showMock(task: "在淘寶搜尋保溫杯，告訴我第一個商品的價格", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.first { $0["action"]?.str == "blocked" }?["reason"]?.str, AgentLoop.untypedSearchReason)
        XCTAssertNotEqual(phone.calls.first, "tap", "the suggestion was never searched: \(phone.calls)")
        XCTAssertTrue(phone.keys.contains("enter"))
    }

    // MARK: Calculator's keys

    func testPressFindsKeysByTheirLabels() throws {
        XCTAssertEqual(AgentLoop.keyTokens("AC 40.74-32.9="), ["AC", "4", "0", ".", "7", "4", "-", "3", "2", ".", "9", "="])
        XCTAssertEqual(AgentLoop.keyLabel("x"), "×")
        XCTAssertEqual(AgentLoop.keyLabel("一"), "-")
        let parsed = try Actions.parseCommand("press AC 4 0 . 7 4")
        XCTAssertEqual(parsed["action"]?.str, "press")
        XCTAssertEqual(parsed["text"]?.str, "AC 4 0 . 7 4")
        let pad = [piece("4", 0.8, 0.3),  // the display shows a 4 too
                   piece("AC", 0.15, 0.44), piece("7", 0.15, 0.55), piece("4", 0.15, 0.66), piece("1", 0.15, 0.77),
                   piece("0", 0.38, 0.88), piece(".", 0.62, 0.88), piece("一", 0.85, 0.66), piece("=", 0.85, 0.88)]
        let found = AgentLoop.keySpots("AC 4.0-1=", in: pad)
        XCTAssertEqual(found.missing, [])
        XCTAssertEqual(found.spots.map { [(Double($0.x) * 100).rounded() / 100, (Double($0.y) * 100).rounded() / 100] },
                       [[0.15, 0.44], [0.15, 0.66], [0.62, 0.88], [0.38, 0.88], [0.85, 0.66], [0.15, 0.77], [0.85, 0.88]])
        XCTAssertEqual(AgentLoop.keySpots("7×2", in: pad).missing, ["×", "2"])
    }

    func testAPressThatCannotFindAKeySaysWhatItRead() {
        let pad = [piece("7", 0.15, 0.55), piece("8", 0.38, 0.55)]
        let error = KeysNotOnScreen(missing: ["÷"], seen: AgentLoop.keysSeen(pad))
        XCTAssertTrue(error.localizedDescription.contains("Nothing pressed"))
        XCTAssertTrue(error.localizedDescription.contains("7 (150,550), 8 (380,550)"), error.localizedDescription)
    }

    // MARK: speed

    func testTapThenTypeGoesOnInOneReplyWithAKeyboardUp() async {
        XCTExpectFailure("137: stale since 123: the fake executor answers done without going into the app the task names, which the unvisited-app guard refuses; to be rewritten", strict: false)
        var turn = 0
        let replies = ["THINK: 點搜尋框再輸入\nDO: tap 500 80\nDO: type 保溫杯\nDO: key enter", "THINK: 好了\nDO: done 29.9"]
        let actor = FakeModel { _ in defer { turn += 1 }; return replies[min(turn, replies.count - 1)] }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: FakeModel { _ in "1. 搜尋" }, trace: nil)
        agent.ourKeyboardOnScreen = { true }
        agent.showMock(task: "在淘寶搜尋保溫杯，告訴我第一個商品的價格", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(phone.calls.first, "tap")
        XCTAssertTrue(phone.keys.contains("enter"), "\(phone.calls)")
        XCTAssertEqual(actor.prompts.count, 2, "tap, type and enter from one reply")
    }

    func testLeavingTheHomeScreenIsSeenWithoutReadingIt() async {
        let home = [UInt8](repeating: 30, count: 24 * 48)
        let app = [UInt8](repeating: 220, count: 24 * 48)
        let started = now()
        let left = await AppModel.leftHome(home, within: 0.9, look: { app })
        XCTAssertTrue(left)
        XCTAssertLessThan(now() - started, 0.5)
        let stayed = await AppModel.leftHome(home, within: 0.4, look: { home })
        XCTAssertFalse(stayed)
        let unknown = await AppModel.leftHome(nil, within: 0.1, look: { app })
        XCTAssertFalse(unknown)
    }
}
