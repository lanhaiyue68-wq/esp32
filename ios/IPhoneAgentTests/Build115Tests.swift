import XCTest
@testable import IPhoneAgent

/// A cloud that answers like docs/cloud-bridge-protocol.md says.
@MainActor private final class FakeCloud {
    var requests: [(method: String, path: String, body: [String: Any]?)] = []
    var nextTask: [String: Any]?
    var cancel: [String] = []
    var approval = "pending"
    var down = false
    func send(_ method: String, _ path: String, _ body: [String: Any]?) async throws -> (Int, Data) {
        if down { throw URLError(.cannotConnectToHost) }
        requests.append((method, path, body))
        var reply: [String: Any] = [:]
        if path.hasSuffix("/heartbeat") {
            if let nextTask { reply["task"] = nextTask }
            reply["cancel"] = cancel
        } else if method == "GET" {
            reply = ["status": "waiting_approval", "approval": approval]
        }
        return (200, try JSONSerialization.data(withJSONObject: reply))
    }
    var events: [String] { requests.filter { $0.path.hasSuffix("/events") }.compactMap { $0.body?["status"] as? String } }
}

/// What 15 more tasks and two WeChat groups on build 113 found (11-10), and the customer's cloud bridge (spec of 11-10).
@MainActor final class Build115Tests: XCTestCase {
    private func bridge(_ cloud: FakeCloud) -> CloudBridge {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let b = CloudBridge(defaults: defaults)
        b.send = { try await cloud.send($0, $1, $2) }
        b.server = "http://192.168.1.2:8787"
        b.device = "home_iphone_01"
        b.token = "test-token"
        b.enabled = true
        b.startGrace = 0
        b.capabilities = { ["screen_capture": "available", "hid_board": "available", "pointer": "available", "agent": "idle"] }
        return b
    }
    private let task: [String: Any] = ["task_id": "t1", "input": ["instruction": "打开天气，告诉我气温"],
                                       "requires_approval_before_external_action": true]

    func testATaskFromTheCloudIsRunOnceAndReported() async {
        let cloud = FakeCloud()
        cloud.nextTask = task
        let b = bridge(cloud)
        var started: [String] = []
        var running = false
        b.start = { task, _ in started.append(task.instruction); running = true }
        b.running = { running }
        b.outcome = { _ in CloudBridge.Outcome(status: "succeeded", answer: "19°C", error: nil, steps: 6) }
        await b.tick()
        XCTAssertEqual(started, ["打开天气，告诉我气温"])
        XCTAssertEqual(cloud.events, ["accepted", "running"])
        XCTAssertEqual(b.current?.id, "t1")
        running = false
        await b.tick()
        XCTAssertNil(b.current)
        XCTAssertEqual(cloud.events.last, "succeeded")
        let final = cloud.requests.last { $0.path.hasSuffix("/events") }?.body
        XCTAssertEqual((final?["result"] as? [String: Any])?["answer"] as? String, "19°C")
        XCTAssertEqual(final?["device_id"] as? String, "home_iphone_01")
        await b.tick()  // the same task again: said again, not run again
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(cloud.events.last, "succeeded")
    }

    func testAPhoneThatCannotSeeTheScreenTakesNoTask() async {
        let cloud = FakeCloud()
        cloud.nextTask = task
        let b = bridge(cloud)
        b.capabilities = { ["screen_capture": "unavailable", "hid_board": "available", "pointer": "available"] }
        var started = false
        b.start = { _, _ in started = true }
        await b.tick()
        XCTAssertFalse(started)
        XCTAssertEqual(cloud.events, ["retry_pending"])
    }

    func testTheCloudCanCancelAndThePhoneCanTurnItOff() async {
        let cloud = FakeCloud()
        cloud.nextTask = task
        let b = bridge(cloud)
        var stops = 0
        b.start = { _, _ in }
        b.running = { true }
        b.stop = { stops += 1 }
        await b.tick()
        cloud.cancel = ["t1"]
        await b.tick()
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(cloud.events.last, "cancelled")

        cloud.nextTask = ["task_id": "t2", "input": ["instruction": "x"]]
        cloud.cancel = []
        await b.tick()
        XCTAssertEqual(b.current?.id, "t2")
        b.enabled = false
        let before = cloud.requests.count
        await b.tick()
        XCTAssertEqual(stops, 2, "the kill switch stops the run")
        XCTAssertEqual(cloud.events.last, "cancelled")
        XCTAssertEqual(cloud.requests.count, before + 1, "and asks the cloud for nothing more")
        await b.tick()
        XCTAssertEqual(cloud.requests.count, before + 1)
    }

    func testAMessageWaitsForTheCloudsApproval() async {
        let cloud = FakeCloud()
        let b = bridge(cloud)
        cloud.approval = "approved"
        let yes = await b.approve("你好", for: "t1")
        XCTAssertTrue(yes)
        XCTAssertEqual(cloud.events.first, "waiting_approval")
        cloud.approval = "rejected"
        let no = await b.approve("你好", for: "t1")
        XCTAssertFalse(no)
    }

    func testTheOutcomeOfARun() {
        let done: [JObject] = [["action": .str("plan")], ["action": .str("tap")], ["action": .str("done"), "answer": .str("好了")]]
        XCTAssertEqual(CloudBridge.outcome(of: done), .init(status: "succeeded", answer: "好了", error: nil, steps: 2))
        let rejected: [JObject] = [["action": .str("done"), "answer": .str(AgentLoop.notApprovedAnswer), "approval": .str("rejected")]]
        XCTAssertEqual(CloudBridge.outcome(of: rejected).status, "cancelled")
        XCTAssertEqual(CloudBridge.outcome(of: [["action": .str("stopped")]]).status, "cancelled")
        XCTAssertEqual(CloudBridge.outcome(of: [["action": .str("fail"), "reason": .str("step limit reached")]]).error, "step limit reached")
        XCTAssertNil(CloudBridge.task(from: ["task_id": "x", "input": ["instruction": "  "]]))
        XCTAssertEqual(CloudBridge.task(from: ["task_id": "x", "instruction": "看天气"])?.approval, true, "approval unless the cloud says not")
    }

    private func sendRun(approve: Bool) async -> (AgentLoop, FakeGestures, [String]) {
        var turn = 0
        let replies = ["THINK: 输入\nDO: type 你好", "THINK: 发送\nDO: key enter", "THINK: 好了\nDO: done 发了"]
        let actor = FakeModel { _ in defer { turn += 1 }; return replies[min(turn, replies.count - 1)] }
        let planner = FakeModel { _ in "1. 输入并发送" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        var asked: [String] = []
        agent.approveSend = { asked.append($0); return approve }
        agent.showMock(task: "输入你好然后按回车", plan: "", steps: [], running: false)
        await agent.run()
        return (agent, phone, asked)
    }

    func testARejectedMessageIsNeverSent() async {
        let (agent, phone, asked) = await sendRun(approve: false)
        XCTAssertEqual(asked, ["你好"])
        XCTAssertFalse(phone.calls.contains("key"), "\(phone.calls)")
        XCTAssertEqual(agent.steps.last?["answer"]?.str, AgentLoop.notApprovedAnswer)
    }

    func testAnApprovedMessageIsSent() async {
        let (_, phone, asked) = await sendRun(approve: true)
        XCTAssertEqual(asked, ["你好"])
        XCTAssertTrue(phone.calls.contains("key"), "\(phone.calls)")
    }

    func testWhatSendsAMessage() {
        XCTAssertTrue(AgentLoop.asksToSend("在微信打开验证群，发一则消息：你好"))
        XCTAssertTrue(AgentLoop.asksToSend("把結果發到微信测试群"))
        XCTAssertFalse(AgentLoop.asksToSend("在淘宝搜索雨伞，告诉我价格"))
        XCTAssertFalse(AgentLoop.asksToSend("打开设置查看储存空间"))
    }

    func testAMarginSwipeThatDidNotScrollGivesWayToTheModelsSpot() {
        let swipe: JObject = ["action": .str("swipe"), "x1": .int(500), "y1": .int(800), "x2": .int(500), "y2": .int(300)]
        var moved = AgentLoop.safeSwipe(swipe, after: [])
        XCTAssertEqual(moved["x1"]?.int, AgentLoop.marginX)
        moved["changed"] = .bool(true)  // Weather's sky moves by itself
        moved["scrolled"] = .bool(false)
        XCTAssertEqual(AgentLoop.safeSwipe(swipe, after: [moved])["x1"]?.int, 500)
    }

    func testTheCheckSeesEveryAppOpenedAfterManyTaps() {
        var steps: [JObject] = [["action": .str("open"), "app": .str("淘宝")], ["action": .str("open"), "app": .str("拼多多")]]
        for i in 0..<50 { steps.append(["action": .str("tap"), "thought": .str("key \(i)")]) }
        let did = AgentLoop.whatItDid(steps)
        XCTAssertTrue(did.contains("opened 淘宝"))
        XCTAssertTrue(did.contains("opened 拼多多"))
        XCTAssertFalse(did.contains("key 29"), "only the last taps")
        XCTAssertTrue(did.contains("key 49"))
    }

    func testARememberedWaySaysToCheckWhereItIs() {
        let plan = AgentLoop.rememberedPlan(.init(task: "x", lines: ["open 微信", "type “你好”"], updated: Date()))
        XCTAssertTrue(plan.contains("before typing, check that the screen is where this goal says"))
    }
}
