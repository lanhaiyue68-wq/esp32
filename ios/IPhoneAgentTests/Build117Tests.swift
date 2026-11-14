import XCTest
@testable import IPhoneAgent

/// What 69 cloud tasks on build 116 left (11-10): bottom rows clicked under, swipes that threw lists past what was wanted,
/// Calculator's keys, answers cut to one line, searches held as messages, help nobody could give, a hot phone, device
/// numbers in pictures, and an app sent to Search for good after one miss.
@MainActor final class Build117Tests: XCTestCase {
    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x - 0.03, y: y - 0.015, width: 0.06, height: 0.03))
    }

    private func mapped(_ device: HIDDevice) throws -> (Pointer, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let mapX: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 150, "fraction": 0.5], ["units": 285, "fraction": 0.95]]]
        let mapY: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 130, "fraction": 0.2],
                                                           ["units": 520, "fraction": 0.8], ["units": 650, "fraction": 1]]]
        let saved: [String: Any] = ["w": 300, "h": 650, "quality": 0.01, "stale": false,
            "motionVersion": ProbeMotion.version, "requiresFeedback": false, "maps": ["x": mapX, "y": mapY]]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        return (Pointer(device: device, calibrationFile: file), file)
    }

    // MARK: aiming at the bottom rows and the right

    func testBottomRowsComeBackFromTheBottomBorder() async throws {
        let device = FakeDevice()
        let (p, file) = try mapped(device)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(p.belowReach(0.935), "Clock's tab bar, Safari's address bar")
        XCTAssertFalse(p.belowReach(0.887))
        XCTAssertTrue(p.beyondReach(0.848), "WeChat's icon")
        XCTAssertFalse(p.beyondReach(0.7))
        try await p.tap(0.395, 0.95)
        let push = try XCTUnwrap(device.sent.firstIndex(of: "move 0 975"), "\(device.sent)")
        let up = try XCTUnwrap(device.sent[push...].first { $0.hasPrefix("move 0 -") }, "\(device.sent)")
        XCTAssertEqual(Double(up.split(separator: " ")[2]) ?? 0, -32.5, accuracy: 1)
        XCTAssertEqual(device.sent.last, "click")
    }

    // MARK: swipes

    func testAHeldSwipeUpTheListGoesTwentyUnitsACommand() async throws {
        let device = FakeDevice()
        let (p, file) = try mapped(device)
        defer { try? FileManager.default.removeItem(at: file) }
        try await p.swipe(0.04, 0.6, 0.04, 0.2, hold: true)
        let press = try XCTUnwrap(device.sent.lastIndex(of: "press"))
        let release = try XCTUnwrap(device.sent.lastIndex(of: "release"))
        let stroke = device.sent[(press + 1)..<release]
        XCTAssertEqual(stroke.count, 13, "260 units, 20 at a time: \(stroke)")
        let dy = stroke.compactMap { Int($0.split(separator: " ")[2]) }
        XCTAssertEqual(dy.reduce(0, +), -260)
        XCTAssertTrue(dy.allSatisfy { abs($0) <= Pointer.swipeStep })
    }

    /// 134 (y2, y4): one sideways jump never moved Weather's hourly strip. A held sideways swipe goes slowly too.
    func testAHeldSidewaysSwipeGoesSlowlyToo() async throws {
        let device = FakeDevice()
        let (p, file) = try mapped(device)
        defer { try? FileManager.default.removeItem(at: file) }
        try await p.swipe(0.8, 0.5, 0.2, 0.5, hold: true)
        let press = try XCTUnwrap(device.sent.lastIndex(of: "press"))
        let release = try XCTUnwrap(device.sent.lastIndex(of: "release"))
        let stroke = device.sent[(press + 1)..<release]
        XCTAssertGreaterThan(stroke.count, 1, "\(stroke)")
        let dx = stroke.compactMap { Int($0.split(separator: " ")[1]) }
        XCTAssertTrue(dx.allSatisfy { abs($0) <= Pointer.swipeStep })
    }

    func testAnUnheldSidewaysSwipeIsStillOneFlick() async throws {  // the Home Screen's page turns
        let device = FakeDevice()
        let (p, file) = try mapped(device)
        defer { try? FileManager.default.removeItem(at: file) }
        try await p.swipe(0.8, 0.5, 0.2, 0.5, hold: false)
        let press = try XCTUnwrap(device.sent.lastIndex(of: "press"))
        let release = try XCTUnwrap(device.sent.lastIndex(of: "release"))
        XCTAssertEqual(release - press - 1, 1, "\(device.sent[press...release])")
    }

    // MARK: Calculator

    func testPressTypesWhatAKeypadTakesOnTheKeyboard() {
        XCTAssertEqual(AgentLoop.typedKeys(AgentLoop.keyTokens("AC 128 × 0.85 =")), ["esc", "128*0.85="])
        XCTAssertEqual(AgentLoop.typedKeys(AgentLoop.keyTokens("40.74 − 32.9 =")), ["40.74-32.9="])
        XCTAssertEqual(AgentLoop.typedKeys(AgentLoop.keyTokens("AC 9 ÷ 3 =")), ["esc", "9/3="])
        XCTAssertNil(AgentLoop.typedKeys(["±"]), "a key the keyboard has not: tapped")
        XCTAssertNil(AgentLoop.typedKeys(AgentLoop.keyTokens("SEND")))
    }

    // MARK: answers

    func testAnAnswerOnSeveralLinesKeepsThemAll() throws {
        let reply = "THINK: 三天都讀到了\nDO: done 我的位置（龙岗区）的預報：\n今天 15–22°C\n明天 14–25°C\n後天 20–27°C"
        let acts = try Actions.parseActions(reply)
        XCTAssertEqual(acts.count, 1)
        XCTAssertEqual(acts[0]["answer"]?.str, "我的位置（龙岗区）的預報： 今天 15–22°C；明天 14–25°C；後天 20–27°C")
        let two = try Actions.parseActions("THINK: 點它\nDO: tap 100 200\n這行不是答案\nDO: done 好了")
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two[1]["answer"]?.str, "好了")
    }

    func testAnAnswerTheCheckRefusedTwiceGoesOutUncheckedWhenItGivesUp() async {
        let actor = FakeModel { n in n <= 2 ? "THINK: 第一行就是標題\nDO: done 購物清單" : "THINK: 看不到標題\nDO: fail 無法確認標題" }
        let checker = FakeModel { _ in "NO: only its body is shown, not its title" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: nil, trace: nil)
        agent.directStart = true  // no planner: the actor works from the screen
        agent.verifiesDone = true
        agent.doneChecker = checker
        agent.showMock(task: "打開備忘錄，告訴我最上面那則備忘錄的標題。不要改，不要刪", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.last?["action"]?.str, "done", "\(agent.steps.map { $0["action"]?.str ?? "" })")
        XCTAssertEqual(agent.steps.last?["answer"]?.str, "（未能核實）購物清單")
    }

    func testACloudTaskNeverWaitsForHelp() async {
        let actor = FakeModel { _ in "THINK: 卡住了\nDO: fail 找不到這個按鈕" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: nil, trace: nil)
        agent.directStart = true
        var asked = 0
        agent.onHelp = { _ in asked += 1; return .stop }
        agent.noHelp = true
        agent.showMock(task: "打開時鐘，告訴我有幾個鬧鐘", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(asked, 0)
        XCTAssertFalse(agent.running)
    }

    // MARK: approvals

    func testASearchWordedALittleDifferentlyNeedsNoApproval() {
        let park = "打開高德地圖，搜尋深圳灣公園附近的停車場，告訴我第一個停車場的名稱和距離。不要開始導航"
        XCTAssertFalse(AgentLoop.needsApproval("深圳湾公园附近停车场", task: park), "the goal's words without its 的")
        XCTAssertFalse(AgentLoop.needsApproval("深圳灣公園停車場", task: park))
        XCTAssertTrue(AgentLoop.needsApproval("牙膏", task: "在淘寶搜尋牙刷"), "a short word must be the goal's own")
        XCTAssertTrue(AgentLoop.needsApproval("你好，請問還有貨嗎", task: "在淘寶搜尋手機殼，告訴我第一個商品有多少人付款。不要購買"))
        XCTAssertTrue(AgentLoop.needsApproval("116 第四批測試", task: "在微信打開测试群，發一則訊息：116 第四批測試。發完告訴我有沒有發出去"))
    }

    // MARK: the cloud's picture

    func testDeviceNumbersAreBlackedOut() {
        XCTAssertTrue(ShotPrivacy.isNumber("35 123456 789012 3"))
        XCTAssertTrue(ShotPrivacy.isNumber("89860 12345 67890 12345"))
        XCTAssertTrue(ShotPrivacy.isNumber("AA:BB:CC:11:22:33"))
        XCTAssertFalse(ShotPrivacy.isNumber("208.63 GB"))
        XCTAssertFalse(ShotPrivacy.isNumber("27.0.1"))
        XCTAssertFalse(ShotPrivacy.isNumber("HUAWEI-510"))
        let rows = [[piece("IMEI", 0.1, 0.3), piece("35 123456 789012 3", 0.7, 0.3)],
                    [piece("可用空間", 0.1, 0.4), piece("208.63 GB", 0.8, 0.4)],
                    [piece("藍牙", 0.1, 0.5), piece("開啟", 0.85, 0.5)],
                    [piece("序號", 0.1, 0.6), piece("F2LXK9Q1N72J", 0.75, 0.6)]]
        let boxes = ShotPrivacy.boxes(rows)
        XCTAssertEqual(boxes.count, 2, "\(boxes)")
        XCTAssertTrue(boxes.contains { $0.midY > 0.29 && $0.midY < 0.31 })
        XCTAssertTrue(boxes.contains { $0.midY > 0.59 && $0.midY < 0.61 })
    }

    // MARK: opening apps

    func testOneMissOnItsPageDoesNotSendAnAppToSearchForGood() {
        let name = "測試用App117"
        AppPlaces.found(name)
        defer { AppPlaces.found(name) }
        XCTAssertEqual(AppPlaces.missed(name), 1)
        XCTAssertEqual(AppPlaces.missed(name), 2)
        AppPlaces.found(name)
        XCTAssertEqual(AppPlaces.missed(name), 1, "an open on its page starts the count again")
    }
}
