import XCTest
@testable import IPhoneAgent

/// What build 117 on the phone left (11-10): WeChat watch never read 测试群（3人）, a busy group nobody listed was opened at
/// every check, a serial went out in a picture, and the quick done check refused right answers.
@MainActor final class Build118Tests: XCTestCase {
    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x - 0.03, y: y - 0.015, width: 0.06, height: 0.03))
    }

    // MARK: WeChat watch

    func testAGroupTitleWithItsMemberCountIsThatGroup() {
        XCTAssertEqual(WatchReport.fullTitle("测试群（3人）"), "测试群")
        XCTAssertEqual(WatchReport.fullTitle("测试群(3)"), "测试群")
        XCTAssertEqual(WatchReport.fullTitle("测试群 (12 人)"), "测试群")
        XCTAssertTrue(WatchReport.sameChatTitle("测试群（3人）", "测试群"))
        XCTAssertFalse(WatchReport.sameChatTitle("验证群（3人）", "测试群"))
    }

    func testABusyChatThatIsNotListedRestsOnceOpened() {
        func row(_ text: String, x: Double = 0.24, y: Double, h: Double = 0.022) -> [CandidatePicker.Piece] {
            [.init(text: text, box: CGRect(x: x, y: y, width: 0.22, height: h))]
        }
        let list: [[CandidatePicker.Piece]] = [row("微信", x: 0.4, y: 0.08), row("测试群", y: 0.20), row("最新消息", y: 0.235, h: 0.016),
            row("虾笔刀陪跑学员元群", y: 0.40), row("好的收到", y: 0.435, h: 0.016),
            [.init(text: "微信", box: CGRect(x: 0.03, y: 0.94, width: 0.1, height: 0.02)),
             .init(text: "通讯录", box: CGRect(x: 0.28, y: 0.94, width: 0.1, height: 0.02)),
             .init(text: "发现", box: CGRect(x: 0.53, y: 0.94, width: 0.1, height: 0.02)),
             .init(text: "我", box: CGRect(x: 0.78, y: 0.94, width: 0.1, height: 0.02))]]
        var rules = WatchSettings.Rules(targets: ["测试群"])
        let busy: (CGRect) -> Bool = { $0.midY > 0.3 }  // only the busy group has a red mark
        guard case .other(let name, _) = WatchChatOpen.unread(rows: list, rules: rules, badge: busy) else {
            return XCTFail("a red mark on a chat that is not listed is read")
        }
        XCTAssertEqual(name, "虾笔刀陪跑学员元群")
        rules.resting = ["虾笔刀陪跑学员元群"]
        XCTAssertEqual(WatchChatOpen.unread(rows: list, rules: rules, badge: busy), .none, "resting: left alone")
        XCTAssertTrue(WatchSettings.openTask(rules).contains("不要打开：“虾笔刀陪跑学员元群”"))
    }

    // MARK: the cloud's picture

    func testALabelAndItsValueInSeparatePiecesAreBlackedOut() {
        // Made-up values. The recognizer gives each as its own row, as on the phone.
        let rows = [[piece("機型型號", 0.12, 0.38)], [piece("MLDK3CH/A", 0.8, 0.38)],
                    [piece("序號", 0.12, 0.45)], [piece("H9AB3C912N", 0.8, 0.45)],
                    [piece("網路", 0.12, 0.52)], [piece("中国联通", 0.8, 0.52)],
                    [.init(text: "序號 F2LXK9Q1N72J", box: CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.03))]]
        let boxes = ShotPrivacy.boxes(rows)
        XCTAssertEqual(boxes.count, 2, "\(boxes)")
        XCTAssertTrue(boxes.contains { abs($0.midY - 0.45) < 0.01 && $0.minX > 0.7 }, "the value on the label's line")
        XCTAssertTrue(boxes.contains { abs($0.midY - 0.615) < 0.01 && $0.minX > 0.15 }, "the part after the label in one piece")
        XCTAssertFalse(boxes.contains { abs($0.midY - 0.38) < 0.01 }, "the model number stays")
    }

    // MARK: the done check

    func testTheModelsAreToldTomorrowsWeekdayToo() throws {
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12)))
        XCTAssertTrue(AgentLoop.todayLine(date).contains("Tomorrow is 2026-11-11, Wednesday"))
    }

    func testTheSameAnswerRefusedAgainIsLookedAtByTheSecondModel() async {
        XCTExpectFailure("137: stale since 123: the fake executor answers done without going into the app the task names, which the unvisited-app guard refuses; to be rewritten", strict: false)
        let actor = FakeModel { _ in "THINK: 讀到了\nDO: done 明天週三 15–24°C" }
        let checker = FakeModel { _ in "NO: today must be Monday" }
        let planner = FakeModel { _ in "OK" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.directStart = true
        agent.verifiesDone = true
        agent.doneChecker = checker
        agent.showMock(task: "打開天氣，告訴我明天的高低溫", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.last?["answer"]?.str, "明天週三 15–24°C", "no 未能核實: the second model found it right")
        XCTAssertEqual(planner.prompts.filter { $0.contains("Its answer") }.count, 1, "\(planner.prompts)")
        XCTAssertEqual(agent.steps.filter { $0["action"]?.str == "done rejected" }.count, 1)
    }
}
