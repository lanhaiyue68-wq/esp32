import XCTest
@testable import IPhoneAgent

/// Build 129: from 128's four 20-task days on the phone (11-13).
@MainActor final class Build129Tests: XCTestCase {

    /// 128 (g1): the right border's lift started at 0 on every launch; the right column of the Home Screen was missed.
    func testTheBorderLiftStartsAtTheUsualBiasAndSurvivesARestart() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let fresh = Pointer(device: FakeDevice(), calibrationFile: file)
        XCTAssertEqual(fresh.borderLiftY, Pointer.borderLiftStart, accuracy: 1e-9)
        XCTAssertGreaterThan(Pointer.borderLiftStart, 0.025, "border landings are 0.03-0.05 low")

        try Data(#"{"w": 445, "h": 620}"#.utf8).write(to: file)  // a calibrated phone
        let p = Pointer(device: FakeDevice(), calibrationFile: file)
        p.learnBorderLift(missedBy: 0.02)
        let learned = p.borderLiftY
        XCTAssertEqual(learned, Pointer.borderLiftStart + 0.005, accuracy: 1e-9)
        let again = Pointer(device: FakeDevice(), calibrationFile: file)
        XCTAssertEqual(again.borderLiftY, learned, accuracy: 1e-9, "the next launch starts from what was learned")
        XCTAssertEqual(again.span, Pointer.Span(w: 445, h: 620), "the calibration itself is kept")
    }

    /// 128 (g1): Codex's parts name their things without numbers; the apps a part names count as its things.
    func testAPartWithoutNumbersCountsTheAppsItNames() {
        XCTAssertEqual(AgentLoop.partSteps(for: "Results 13–15 and 17 are noted — open Safari for “人民币汇率”, 天氣 for Guangzhou’s tomorrow forecast, 計算機 for 1234×56, and 時鐘 for the existing world clock cities."), 50)
        XCTAssertEqual(AgentLoop.partSteps(for: "打开天气看深圳今天的最高温"), 20)
    }

    /// 128 (g2): the done check "corrected" a chat's latest three to the messages the run had sent there itself.
    func testAnObjectionQuotingTheRunsOwnSendIsNotAWrongAnswer() {
        let sent: Set<String> = [AgentLoop.typedKey("G2全部做完"), AgentLoop.typedKey("G2买东西做完")]
        XCTAssertTrue(AgentLoop.blamesOwnSend("第2项最新三条消息与屏幕不符，屏幕最新三条是G2全部做完、G2买东西做完、G1全部做完，没有G8全部做完。", sent: sent))
        XCTAssertTrue(AgentLoop.blamesOwnSend("item 2's latest three messages differ from the current screen: the screen shows G2 全部做完, G2买东西做完, G1全部做完.", sent: sent))
        XCTAssertFalse(AgentLoop.blamesOwnSend("第15项计算结果与屏幕不符：屏幕是32084", sent: sent))
        XCTAssertFalse(AgentLoop.blamesOwnSend("item 2 is wrong", sent: []))
        XCTAssertFalse(AgentLoop.blamesOwnSend("第3项写的是你好，屏幕上是早安", sent: ["你好"]), "too short to tell")
        // second round (g4): the run's own message named only in part
        let g4: Set<String> = [AgentLoop.typedKey("G4买东西做完"), AgentLoop.typedKey("G4全部做完"), "tap:发送"]
        XCTAssertTrue(AgentLoop.blamesOwnSend("第2项说最新三条消息含9:43\"G1全部做完\"，但当前测试群最新三条是9:55、10:03两条G2和10:17的G4消息，没有9:43的G1消息。", sent: g4))
        XCTAssertFalse(AgentLoop.blamesOwnSend("第2项说最新三条消息含G1全部做完，屏幕不同", sent: []), "nothing sent: the check stands")
        XCTAssertFalse(AgentLoop.blamesOwnSend("第4项购物车数量为2", sent: g4), "not about the chat")
    }

    /// 128 (g8): the lamp was in the cart twice from earlier days; the check called ×3 "more than the 1 asked".
    func testACartCountAboveWhatThisRunAddedWasThereBefore() {
        XCTAssertTrue(AgentLoop.blamesOldCart("淘宝购物车台灯数量为×3，超出目标要求的1件。", adds: 1, wanted: 1))
        XCTAssertTrue(AgentLoop.blamesOldCart("购物车台灯数量为×3，目标要求加购1件，数量不符。", adds: 1, wanted: 2))
        XCTAssertTrue(AgentLoop.blamesOldCart("the cart shows the lamp x 3, the goal asked for one", adds: 1, wanted: 1))
        XCTAssertFalse(AgentLoop.blamesOldCart("淘宝购物车台灯数量为×3，超出目标要求的1件。", adds: 3, wanted: 1), "this run added three")
        XCTAssertFalse(AgentLoop.blamesOldCart("淘宝购物车台灯数量为×3", adds: 0, wanted: 1), "no add seen: not known")
        XCTAssertFalse(AgentLoop.blamesOldCart("购物车里没有台灯", adds: 1, wanted: 1), "missing from the cart still stands")
        XCTAssertFalse(AgentLoop.blamesOldCart("the cart shows a lamp box 2, not the cup", adds: 1, wanted: 1))
        XCTAssertEqual(AgentLoop.cartWanted("4. 在淘宝搜索“台灯”，加入购物车一件；13. 看淘宝购物车最上面一件"), 1)
    }

    /// 128 (second round, g1): a written note scrolled up and down 15 times to "check" it.
    func testScrollingBackAndForthAgainIsRefused() {
        func swipe(_ y1: Double, _ y2: Double) -> JObject {
            ["action": .str("swipe"), "x1": .num(40), "y1": .num(y1), "x2": .num(40), "y2": .num(y2)]
        }
        let down = swipe(250, 750), up = swipe(800, 350)
        XCTAssertFalse(AgentLoop.scrollsBackAgain([down, down, up, up], next: down), "one way, back, and that way again")
        XCTAssertTrue(AgentLoop.scrollsBackAgain([down, down, up, up, down], next: up))
        XCTAssertFalse(AgentLoop.scrollsBackAgain([up, up, up, up, up], next: up), "a long list read one way")
        XCTAssertFalse(AgentLoop.scrollsBackAgain([down, up, down, ["action": .str("tap"), "x": .num(500), "y": .num(500)]], next: up),
                       "a tap between starts again")
        XCTAssertNil(AgentLoop.swipeDirection(swipe(500, 520)), "too short to scroll")
        XCTAssertNil(AgentLoop.swipeDirection(["action": .str("swipe"), "x1": .num(900), "y1": .num(500), "x2": .num(100), "y2": .num(520)]),
                     "a sideways swipe")
    }

    /// 129 (g1): the landings read off 129's first day keep the lift near the steady bias.
    func testTheBorderLiftHoldsAgainstOddReadings() {
        let p = Pointer(device: FakeDevice(), calibrationFile: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json"))
        var lifts: [Double] = []
        for raw in [0.026, -0.004, -0.06, 0.034] {  // where they really landed, below the target
            p.learnBorderLift(missedBy: raw - p.borderLiftY)
            lifts.append(p.borderLiftY)
        }
        XCTAssertTrue(lifts.allSatisfy { $0 > 0.02 && $0 < 0.04 }, "\(lifts)")
    }

    /// 129 (g1): the pages are read again when a remembered app is not on its page, at most every 10 minutes.
    func testThePagesMayBeReadAgainSoonAfterAMiss() {
        let now = Date()
        AppPlaces.readAgainNow(now: now.addingTimeInterval(-700))
        XCTAssertTrue(AppPlaces.mayReadAgain(now: now, every: AppPlaces.rereadAfterMiss))
        XCTAssertFalse(AppPlaces.mayReadAgain(now: now), "the three days for an app no page knew stay")
        AppPlaces.readAgainNow(now: now.addingTimeInterval(-300))
        XCTAssertFalse(AppPlaces.mayReadAgain(now: now, every: AppPlaces.rereadAfterMiss))
    }

    /// 129 (g4): item 2 was noted right when read; the final answer retold it with the run's own later message.
    func testAnItemRetoldWithTheRunsOwnMessagesIsPutBackAsNoted() {
        let answer = "已完成全部20项任务，结果如下：1. 深圳多云；2. 微信测试群最新三条消息：下午1:40「G2买东西做完」、下午1:50「G2全部做完」、下午2:01「G4买东西做完」。；3. 抖音价格 12.5元；4. 淘宝 ×1"
        let notes = ["1. 深圳多云", "2. 测试群最新三条（均为我自己发的）：下午1:19 G1全部做完；下午1:28 G2买东西做完；下午1:40 G2全部做完"]
        let sent: Set<String> = [AgentLoop.typedKey("G4买东西做完"), AgentLoop.typedKey("G4全部做完")]
        let kept = AgentLoop.keepReadNotes(answer, notes: notes, sent: sent)
        XCTAssertTrue(kept.contains("下午1:19 G1全部做完"), kept)
        XCTAssertFalse(kept.contains("G4买东西做完"), kept)
        XCTAssertTrue(kept.hasPrefix("已完成全部20项任务，结果如下：1. 深圳多云；2. 测试群"), kept)
        XCTAssertTrue(kept.hasSuffix("；3. 抖音价格 12.5元；4. 淘宝 ×1"), kept)
        XCTAssertEqual(AgentLoop.keepReadNotes(answer, notes: notes, sent: []), answer, "nothing sent: as answered")
        let told = "1. 深圳多云；2. 最新三条：G1全部做完、G2买东西做完、G2全部做完；3. 已发G4买东西做完"
        XCTAssertEqual(AgentLoop.keepReadNotes(told, notes: notes, sent: sent), told, "item 3 has no note; item 2 tells no own message")
        XCTAssertEqual(AgentLoop.numberedItems("第13项：Safari搜索").first?.n, 13)
        XCTAssertEqual(AgentLoop.numberedItems(answer).map { $0.n }, [1, 2, 3, 4], "12.5元 is not item 12")
    }

    /// 128 (g1): twenty things followed the remembered end of the last such run; several numbered things plan afresh.
    func testSeveralNumberedThingsAreNotARememberedWay() {
        XCTAssertGreaterThanOrEqual(AgentLoop.goalParts("帮我做这三件事：1. 查天气；2. 算差价；3. 发群"), 3)
        XCTAssertLessThan(AgentLoop.goalParts("在抖音推荐页打开第一个视频，用 listen 听它讲了什么"), 3)
    }
}
