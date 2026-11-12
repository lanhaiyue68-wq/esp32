import UIKit
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

    /// 123 regression: a goal of nine parts on its remembered way (no numbered plan) had the base steps.
    func testTheGoalsOwnPartsCountToo() {
        let goal = "帮我做这九件事：1. 在拼多多搜索数据线，记下第一个商品的价格¥13.5；2. 在淘宝搜索电动牙刷；3. 看视频号；"
            + "4. 看验证群；5. 搜备忘录；6. 看日历；7. 看蓝牙；8. 查北京温度；9. 整理成一段话告诉我"
        XCTAssertEqual(AgentLoop.goalParts(goal), 9)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "Work from the CURRENT screen", base: 55, goal: goal), 180)
        XCTAssertEqual(AgentLoop.goalParts("价格 13.5 元，3. 不是第一件"), 0, "numbered from 1 only")
    }

    /// 123 regression: a note with a tap run on in one DO line.
    func testANoteWithAnActionRunOnIsTwoActions() throws {
        let acts = try Actions.parseActions("THINK: 记下。\nDO: note 广州今天最高温26°; tap 857 938")
        XCTAssertEqual(acts.count, 2)
        XCTAssertEqual(acts[0]["text"]?.str, "广州今天最高温26°")
        XCTAssertEqual(acts[1]["action"]?.str, "tap")
        XCTAssertEqual(acts[1]["x"]?.int, 857)
        XCTAssertEqual(try Actions.parseActions("DO: note 价格¥13.5；已拼128万件").count, 1, "a note's own ；stays")
    }

    /// 123 regression: nine parts, only the weather done, eight results made up and passed.
    func testAResultFromAnAppNeverOpenedIsNotDone() {
        let goal = "帮我做这九件事：1. 在拼多多搜索数据线；2. 在淘宝搜索电动牙刷；8. 在天气查北京现在的温度。不要打开美团"
        let steps: [JObject] = [
            ["action": .str("plan"), "plan": .str("1. 拼多多 2. 淘宝 3. 天气")],
            ["action": .str("tap"), "x": .int(341), "y": .int(938), "thought": .str("Open the Weather app")],
            ["action": .str("type"), "text": .str("北京")],
            ["action": .str("note"), "text": .str("北京现在温度7°")],
        ]
        XCTAssertEqual(AgentLoop.unvisitedApps(task: goal, steps: steps), ["拼多多", "淘宝"], "美团 is not to be opened")
        XCTAssertNotNil(AgentLoop.unvisitedReason(task: goal, steps: steps))
        let all = steps + [["action": .str("open"), "app": .str("拼多多")], ["action": .str("note"), "text": .str("淘宝第一个商品19.9元")]]
        XCTAssertNil(AgentLoop.unvisitedReason(task: goal, steps: all))
        let notDone = try? Actions.parseActions("DO: note 北京现在温度7°。done 已完成九项查询")
        XCTAssertEqual(notDone?.count, 2)
        XCTAssertEqual(CloudBridge.said(true, "口播语音转写无法获取，以下是画面文字"), "部分失败：口播语音转写无法获取，以下是画面文字")
    }

    /// 123 regression: the same text went into 验证群 twice.
    func testTheSameTextIsNotSentTwiceToOneChat() {
        XCTAssertTrue(AgentLoop.samePlace(["验证群(3)"], "验证群"))
        XCTAssertFalse(AgentLoop.samePlace(["验证群(3)"], "测试群"), "another chat may get it")
        XCTAssertTrue(AgentLoop.samePlace(["验证群"], nil), "title not read: refused")
        XCTAssertTrue(AgentLoop.samePlace([], "测试群"), "where it went not read: refused")
        XCTAssertEqual(CloudBridge.failureWords("LLM HTTP 403: {\"error\":{\"code\":\"AccountOverdueError\"}}"), "模型服务账户欠费，请先充值再试")
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

    /// B4: what a paste put in, read off the screen.
    func testWhatAPastePutInIsReadOffTheScreen() {
        let p = { (t: String, y: Double) in CandidatePicker.Piece(text: t, box: CGRect(x: 0.2, y: y, width: 0.5, height: 0.03)) }
        let before = [[p("测试群(3)", 0.07)], [p("你好", 0.5)], [p("发送", 0.9)]]
        let after = [[p("测试群(3)", 0.07)], [p("你好", 0.4)], [p("复制打开抖音，看看【作品】", 0.8)], [p("发送", 0.9)]]
        XCTAssertEqual(AgentLoop.newWords(before: before, after: after), "复制打开抖音，看看【作品】")
        XCTAssertEqual(AgentLoop.newWords(before: before, after: before), "")
    }

    /// B5: a title read as two pieces at slightly different heights.
    func testATitleInTwoPiecesIsOneTitle() {
        let piece = { (t: String, x: Double, w: Double, y: Double) in CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: 0.02)) }
        let split = [[piece("虾笔刀陪跑", 0.25, 0.25, 0.075)], [piece("学员元群(25)", 0.5, 0.27, 0.08)]]
        XCTAssertEqual(WatchReport.navigationTitle(rows: split), "虾笔刀陪跑学员元群")
        let banner = [[piece("主人蓝海乐", 0.2, 0.17, 0.058)], [piece("9527 去给我画个太阳", 0.2, 0.44, 0.08)]]
        XCTAssertNil(WatchReport.navigationTitle(rows: banner), "a banner still is not a title")
    }

    /// B6: the screen dimmed evenly under the question whether to stop sharing; a new page is not that.
    func testADimmedScreenIsTellableFromANewPage() {
        func jpeg(_ bg: CGFloat, _ bar: CGFloat, barY: CGFloat) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 120, height: 260)).jpegData(withCompressionQuality: 0.9) { ctx in
                ctx.cgContext.setFillColor(UIColor(white: bg, alpha: 1).cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 120, height: 260))
                ctx.cgContext.setFillColor(UIColor(white: bar, alpha: 1).cgColor)
                ctx.cgContext.fill(CGRect(x: 10, y: barY, width: 100, height: 40))
            }
        }
        let page = jpeg(1.0, 0.3, barY: 60)
        XCTAssertTrue(Vision.dimmed(page, jpeg(0.6, 0.18, barY: 60)))
        XCTAssertFalse(Vision.dimmed(page, page))
        XCTAssertFalse(Vision.dimmed(page, jpeg(0.6, 0.0, barY: 180)), "another page")
    }

    /// 123 watch test: "测试群（3人）凌晨4:05" was read as the title; "深圳明天最高温几度" answered 23° off the chat.
    func testATimeLabelIsNotTheTitleAndTheWeatherIsLookedUp() {
        let piece = { (t: String, x: Double, w: Double, y: Double) in CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: 0.02)) }
        let rows = [[piece("测试群（3人）", 0.37, 0.26, 0.078)], [piece("凌晨4:05", 0.42, 0.16, 0.122)]]
        XCTAssertTrue(WatchReport.sameChatTitle(WatchReport.navigationTitle(rows: rows) ?? "", "测试群"))
        XCTAssertTrue(WatchReport.timeLabel("昨天 下午1:18"))
        XCTAssertTrue(WatchReport.timeLabel("11月12日 上午9:29"))
        XCTAssertFalse(WatchReport.timeLabel("测试群"))
        let decided = WatchSettings.keptPromise((reply: "深圳明天最高温23度。", task: ""), look: true, asked: ["@蓝 深圳明天最高温几度"])
        XCTAssertEqual(decided.task, "@蓝 深圳明天最高温几度")
        XCTAssertEqual(WatchSettings.keptPromise((reply: "你好呀", task: ""), look: true, asked: ["在吗"]).task, "")
    }

    /// 123 watch test (W2 again): a screenshot opened in WeChat was taken for the app, WeChat opened twice by Search.
    func testAPictureInWeChatIsNotAnotherApp() {
        let tap: JObject = ["action": .str("tap"), "x": .int(311), "y": .int(284)]
        XCTAssertEqual(AgentLoop.appInFront([tap], startedIn: "微信"), "微信")
        XCTAssertNil(AgentLoop.appInFront([tap, ["action": .str("home")]], startedIn: "微信"))
        XCTAssertEqual(AgentLoop.appInFront([["action": .str("open"), "app": .str("天气")], tap], startedIn: "微信"), "天气")
        XCTAssertNil(AgentLoop.appInFront([tap], startedIn: nil))
        XCTAssertTrue(AgentLoop.stillInAppReason("微信").contains("One tap in the middle"))
    }

    /// User 11-12: a voice message is written out, read only.
    func testAVoiceMessageIsWrittenOut() throws {
        let task = try XCTUnwrap(WatchSettings.lookDefault("[语音] 5\""))
        XCTAssertTrue(task.contains("转文字"))
        XCTAssertTrue(task.contains("一律不做"))
        XCTAssertNil(WatchSettings.lookDefault("今天吃什么"))
        // Written out by WeChat before the read: then it is talk, the owner's own words.
        XCTAssertNil(WatchSettings.lookDefault("[语音] 帮我查一下北京现在几度"))
        XCTAssertTrue(WatchReport.bareVoice("[語音] 3\""))
        XCTAssertTrue(WatchReport.bareVoice("[Voice]"))
        XCTAssertFalse(WatchReport.bareVoice("[语音] 帮我查一下"))
        XCTAssertTrue(WatchReport.isVoice("[语音] 帮我查一下"))
        XCTAssertFalse(WatchReport.isVoice("语音通话已结束"))
    }
}
