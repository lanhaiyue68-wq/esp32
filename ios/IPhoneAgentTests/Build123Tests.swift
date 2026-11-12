import XCTest
@testable import IPhoneAgent

/// Build 123: the bugs found testing 122 on the phone and over the cloud (docs/device-2026-11-11-build122-report.md).
@MainActor final class Build123Tests: XCTestCase {

    /// B7: goals of 9 to 15 parts ran out at 100 steps.
    func testAGoalOfManyPartsGetsStepsForEach() {
        let twelve = (1...12).map { "\($0). part" }.joined(separator: "\n")
        XCTAssertEqual(AgentLoop.stepBudget(plan: twelve, base: 40), 240)
        let fifteen = (1...15).map { "\($0). part" }.joined(separator: "\n")
        XCTAssertEqual(AgentLoop.stepBudget(plan: fifteen, base: 40), 240, "at most 240")
    }

    /// B7: what was written down goes back with a failure.
    func testAFailureCarriesWhatWasFound() {
        let steps: [JObject] = [
            ["action": .str("note"), "text": .str("深圳明天最高温27°")],
            ["action": .str("note"), "text": .str("深圳明天最高温27°")],
            ["action": .str("note"), "text": .str("AAPL 355.63")],
            ["action": .str("fail"), "reason": .str("step limit reached")],
        ]
        let out = CloudBridge.outcome(of: steps)
        XCTAssertEqual(out.status, "failed")
        XCTAssertEqual(out.answer, "部分失败：步骤用完了还没做完。已查到：深圳明天最高温27°；AAPL 355.63")
        XCTAssertEqual(CloudBridge.outcome(of: [["action": .str("fail"), "reason": .str("step limit reached")]]).answer,
                       "失败：步骤用完了还没做完", "nothing found: as before")
        let watch = WatchSettings.phoneTaskResult(action: "fail", answer: nil, attempted: [], reason: "step limit reached",
                                                  notes: ["北京 13°"])
        XCTAssertTrue(watch.hasPrefix("部分失败："), watch)
        XCTAssertTrue(watch.contains("已查到：北京 13°"), watch)
    }

    /// B8: a part that reads something is not done with nothing written down.
    func testAPartThatReadsSomething() {
        XCTAssertTrue(AgentLoop.readsSomething("3. 在微信视频号记下第一个视频的作者"))
        XCTAssertTrue(AgentLoop.readsSomething("7. 在设置看蓝牙是不是开着"))
        XCTAssertTrue(AgentLoop.readsSomething("4. 看驗證群最後一條消息是什麼"))
        XCTAssertFalse(AgentLoop.readsSomething("9. 把以上结果整理成一段话告诉我"))
        XCTAssertFalse(AgentLoop.readsSomething("2. 打开微信"))
    }

    /// B9: 2027-01-01 is a Friday; 122 said 星期三.
    func testADateTheGoalNamesGetsItsWeekday() {
        let facts = AgentLoop.dateFacts(in: "在日历看 2027 年 1 月 1 日是星期几")
        XCTAssertTrue(facts.contains("2027-01-01, Friday (星期五)"), facts)
        XCTAssertTrue(AgentLoop.dateFacts(in: "2026-11-13 的天气").contains("2026-11-13, Friday"))
        XCTAssertEqual(AgentLoop.dateFacts(in: "查 AAPL 现价 355.63"), "")
        XCTAssertEqual(AgentLoop.dateFacts(in: "2027 年 2 月 30 日"), "", "no such day")
        XCTAssertTrue(AgentLoop.todayLine(goal: "2027年1月1日是星期几").contains("Dates in the goal: 2027-01-01, Friday"))
    }

    /// B10: Weather's city row, 11 taps in a row.
    func testTheSameSpotTappedAgainAndAgain() {
        let tap = { (x: Int, y: Int) -> JObject in ["action": .str("tap"), "x": .int(x), "y": .int(y)] }
        let steps: [JObject] = [tap(167, 464), tap(179, 462), ["action": .str("stale plan")], tap(174, 465)]
        XCTAssertEqual(AgentLoop.tapsInARow(steps, like: tap(171, 461)), 3)
        XCTAssertEqual(AgentLoop.tapsInARow(steps + [["action": .str("swipe")]], like: tap(171, 461)), 0)
        XCTAssertEqual(AgentLoop.tapsInARow(steps, like: tap(700, 900)), 0, "another spot")
    }

    /// #17: a like or a follow is a public act.
    func testALikeOrAFollowIsNotJustATap() {
        let tap = { (thought: String) -> JObject in ["action": .str("tap"), "x": .int(900), "y": .int(500), "thought": .str(thought)] }
        XCTAssertEqual(AgentLoop.publicTap(tap("点击点赞按钮给这个视频点赞")), "点赞")
        XCTAssertEqual(AgentLoop.publicTap(tap("Tap the follow button to follow the author")), "关注")
        XCTAssertNil(AgentLoop.publicTap(tap("读取点赞数，然后点开评论区")))
        XCTAssertNil(AgentLoop.publicTap(tap("不要点赞，点视频下方的作者名")))
        XCTAssertNil(AgentLoop.publicTap(tap("打开顶部的关注页")))
        XCTAssertTrue(AgentLoop.forbids("打开抖音第一个视频。不要发消息、转发、评论、点赞、收藏、关注", "关注"))
        XCTAssertFalse(AgentLoop.forbids("给这个视频点赞", "点赞"))
    }

    /// W1: "稍后告诉你" with no task, to someone who may give look-ups.
    func testAPromiseToComeBackBecomesTheTask() {
        let kept = WatchSettings.keptPromise((reply: "这个我不太确定，稍后再告诉你。", task: ""), look: true, asked: ["深圳明天几度"])
        XCTAssertEqual(kept.task, "深圳明天几度")
        XCTAssertEqual(kept.reply, WatchSettings.taskAcknowledgement)
        let plain = WatchSettings.keptPromise((reply: "好的", task: ""), look: true, asked: ["在吗"])
        XCTAssertEqual(plain.task, "", "talk stays talk")
        let stranger = WatchSettings.keptPromise((reply: "稍后告诉你", task: ""), look: false, asked: ["深圳明天几度"])
        XCTAssertEqual(stranger.task, "", "only for someone who may give look-ups")
    }

    /// User 11-12: a voice message is written out, read only.
    func testAVoiceMessageIsWrittenOut() throws {
        let task = try XCTUnwrap(WatchSettings.lookDefault("[语音] 5\""))
        XCTAssertTrue(task.contains("转文字"))
        XCTAssertTrue(task.contains("一律不做"))
        XCTAssertNil(WatchSettings.lookDefault("今天吃什么"))
    }
}
