import AVFoundation
import XCTest
@testable import IPhoneAgent

/// Build 122 (user 11-11): how much of Codex is left, shown in Settings, read off the x-codex-* headers its answers carry
/// (the values below are the shape seen in the phone's log).
@MainActor final class Build122Tests: XCTestCase {

    func testTheQuotaIsReadFromCodexsHeaders() throws {
        let now = 1_794_074_561.0
        let headers = ["x-codex-primary-used-percent": "1", "x-codex-primary-window-minutes": "300",
                       "x-codex-primary-reset-after-seconds": "17635", "x-codex-secondary-used-percent": "73",
                       "x-codex-secondary-window-minutes": "10080", "x-codex-secondary-reset-at": "1794452772",
                       "x-codex-plan-type": "plus", "x-codex-credits-balance": "0"]
        let quota = try XCTUnwrap(PlusQuota(headers: headers, now: now))
        XCTAssertEqual(quota.short, PlusQuota.Window(minutes: 300, usedPercent: 1, resetAt: now + 17635))
        XCTAssertEqual(quota.long?.usedPercent, 73)
        XCTAssertEqual(quota.long?.resetAt, 1_794_452_772)
        XCTAssertEqual(quota.plan, "plus")
        let lines = quota.lines(now: now)
        XCTAssertEqual(lines.first, "5 小时额度：剩 99%，4 小时 53 分后重置")
        XCTAssertTrue(lines[1].hasPrefix("本周额度：剩 27%，"), lines[1])
        XCTAssertEqual(lines.last, "刚刚更新")
        XCTAssertEqual(quota.lines(now: now + 7200).last, "2 小时前更新")
        XCTAssertNil(PlusQuota(headers: ["x-codex-plan-type": "plus"]), "nothing about the quota")
    }

    func testAWindowPastItsResetIsFullAgain() {
        XCTAssertEqual(PlusQuota.line(.init(minutes: 300, usedPercent: 100, resetAt: 1000), now: 2000), "5 小时额度：已重置（剩 100%）")
        XCTAssertEqual(PlusQuota.line(.init(minutes: 300, usedPercent: 40, resetAt: 2600), now: 2000), "5 小时额度：剩 60%，10 分后重置")
        XCTAssertEqual(PlusQuota.line(.init(minutes: 300, usedPercent: 40, resetAt: nil), now: 2000), "5 小时额度：剩 60%")
    }

    // MARK: - found testing 121 on the phone (batch g, 11-11)

    /// g01: a 抖音 share link pasted into 测试群 (cmd+v) and sent with Return, no approval asked.
    func testAPastedMessageWaitsForApprovalLikeATypedOne() async {
        XCTAssertTrue(AgentLoop.pastes(["action": .str("key"), "combo": .str("cmd+v")]))
        XCTAssertTrue(AgentLoop.pastes(["action": .str("key"), "combo": .str("Cmd + V")]))
        XCTAssertFalse(AgentLoop.pastes(["action": .str("key"), "combo": .str("enter")]))
        XCTAssertEqual(AgentLoop.pastedText(nil), "（粘贴的内容）")
        XCTAssertEqual(AgentLoop.pastedText("  https://v.douyin.com/abc/ "), "https://v.douyin.com/abc/")

        var turn = 0
        let replies = ["THINK: 粘贴\nDO: key cmd+v", "THINK: 发送\nDO: key enter", "THINK: 好了\nDO: done 发了"]
        let actor = FakeModel { _ in defer { turn += 1 }; return replies[min(turn, replies.count - 1)] }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: FakeModel { _ in "1. 分享到测试群" }, trace: nil)
        var asked: [String] = []
        agent.approveSend = { asked.append($0); return false }
        agent.pasteboard = { "7.43 复制打开抖音，看看【二虎仔的作品】 https://v.douyin.com/abc/" }
        agent.showMock(task: "打開抖音首頁的第一個影片，用分享把它發到微信的测试群", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(asked.count, 1, "\(asked)")
        XCTAssertTrue(asked.first?.contains("v.douyin.com") == true)
        XCTAssertFalse(phone.keys.contains("enter"), "\(phone.keys)")
    }

    /// k02: "先發「k02第一句」，再發「k02第二句」": the second went out with no approval asked.
    func testEveryQuotedMessageWaitsForApproval() {
        let task = "在测试群先發「k02第一句」，再發「k02第二句」"
        XCTAssertEqual(AgentLoop.messageParts(task), ["k02第一句", "k02第二句"])
        XCTAssertTrue(AgentLoop.needsApproval("k02第一句", task: task))
        XCTAssertTrue(AgentLoop.needsApproval("k02第二句", task: task))
        XCTAssertFalse(AgentLoop.needsApproval("测试群", task: task), "the chat's name, searched for")
        XCTAssertEqual(AgentLoop.messageParts("在测试群發：122前測試早安"), ["122前測試早安"])
        XCTAssertEqual(AgentLoop.messageParts("打開天氣"), [])
    }

    /// h01: asked to copy a WeChat message, both models wrote a long press their own way and the run failed.
    func testALongPressIsAnAction() throws {
        XCTAssertEqual(try Actions.parseCommand("hold 669 849"), ["action": .str("hold"), "x": .int(669), "y": .int(849)])
        XCTAssertEqual(try Actions.parseCommand("touch_and_hold 669 849")["action"], .str("hold"))
        XCTAssertEqual(try Actions.parseCommand("long_press 10 20")["action"], .str("hold"))
    }

    /// g04: 8816 audio samples in 180 s of a news video, no word recognized, and nothing in the log said why. How loud
    /// the audio was is kept now (0: silence).
    func testHowLoudTheScreensAudioWas() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 8
        XCTAssertEqual(ScreenAudio.loudness(buffer), 0, "silence")
        buffer.floatChannelData?[0][3] = -0.5
        XCTAssertEqual(ScreenAudio.loudness(buffer), 0.5)
        XCTAssertFalse(ScreenAudio.shared.report().silent, "nothing came in: not called silence")
    }

    /// i06 (121, 11-11): Codex drove a settings read in 12 steps at 14-20 s each; it is asked to reason low now.
    func testCodexIsAskedToReasonLow() {
        let saved = UserDefaults.standard.string(forKey: ChatGPTPlus.effortKey)
        defer { UserDefaults.standard.set(saved, forKey: ChatGPTPlus.effortKey); ChatGPTPlus.effortRefused = false }
        UserDefaults.standard.removeObject(forKey: ChatGPTPlus.effortKey)
        XCTAssertEqual(ChatGPTPlus.reasoningEffort, "low")
        UserDefaults.standard.set("", forKey: ChatGPTPlus.effortKey)
        XCTAssertNil(ChatGPTPlus.reasoningEffort, "switched off")
        UserDefaults.standard.removeObject(forKey: ChatGPTPlus.effortKey)
        ChatGPTPlus.effortRefused = true
        XCTAssertNil(ChatGPTPlus.reasoningEffort, "refused by the backend once: not sent again")
    }

    /// n01: "幫我做這六件事：1. 查深圳明天的最高溫；…6. 把以上結果整理成一段話發到测试群": the list after the colon was taken
    /// for the message, and 深圳 typed in Weather's search was held for approval.
    func testAListAfterAColonIsNotTheMessage() {
        let task = "幫我做這六件事：1. 查深圳明天的最高溫；2. 查上海明天的最高溫；6. 把以上結果整理成一段話發到测试群。不要購買"
        XCTAssertEqual(AgentLoop.messageParts(task), [])
        XCTAssertFalse(AgentLoop.needsApproval("深圳", task: task, chatApp: false), "a search in Weather")
        XCTAssertTrue(AgentLoop.needsApproval("深圳", task: task, chatApp: true), "typed in a chat app it may be the message")
        XCTAssertTrue(AgentLoop.needsApproval("明天深圳28°C，上海19°C", task: task, chatApp: false), "the summary is a message")
        XCTAssertEqual(AgentLoop.messagePart("在微信打開测试群，發一則訊息：壓力測試 115。發完告訴我"), "壓力測試 115")
        XCTAssertEqual(AgentLoop.messagePart("在小紅書第一篇筆記下留言：好看"), "好看")
        XCTAssertEqual(AgentLoop.messagePart("回覆張三：好的"), "好的")
    }

    /// n02, n04: right answers to goals of 7 and 8 parts reported "（未能核實）": the check saw only the last screen.
    func testTheCheckOfASeveralPartGoalKnowsWhatEarlierPartsFound() {
        let prompt = AgentLoop.checkPrompt(goal: "幫我做這七件事：…", today: "Today is 2026-11-11.", answer: "電池 98%",
                                           did: "1. opened 设置", notes: ["電池 98%"], sent: ["122多任務測試開始"], parts: 7)
        XCTAssertTrue(prompt.contains("- 電池 98%"), prompt)
        XCTAssertTrue(prompt.contains("122多任務測試開始"), prompt)
        XCTAssertTrue(prompt.contains("only where the last one ended"), prompt)
        let one = AgentLoop.checkPrompt(goal: "看電量", today: "", answer: "98%", did: "", notes: [], sent: [], parts: 1)
        XCTAssertFalse(one.contains("parts done one after another"))
        XCTAssertTrue(one.hasSuffix("The image is the screen now."))
    }

    /// User 11-11: "不論成功失敗都要反饋，告訴我成功還是失敗". 121's failed cloud tasks came back with an empty answer.
    func testEveryResultSaysWhetherItWorked() {
        let done: [JObject] = [["action": .str("tap")], ["action": .str("done"), "answer": .str("深圳明天 28°C")]]
        XCTAssertEqual(CloudBridge.outcome(of: done).answer, "成功：深圳明天 28°C")
        let failed: [JObject] = [["action": .str("fail"), "reason": .str("kept going back and forth between two screens")]]
        XCTAssertEqual(CloudBridge.outcome(of: failed).status, "failed")
        XCTAssertEqual(CloudBridge.outcome(of: failed).answer, "失败：在几个画面之间来回打转，没能做完")
        XCTAssertEqual(CloudBridge.outcome(of: failed).error, "kept going back and forth between two screens")
        let chinese: [JObject] = [["action": .str("fail"), "reason": .str("請先繫結手機號，之後才能留言。")]]
        // User 11-11: mainland customers get Simplified, even for a reason the model wrote in Traditional.
        XCTAssertEqual(CloudBridge.outcome(of: chinese).answer, "失败：" + AppNames.hans("請先繫結手機號，之後才能留言。"))
        XCTAssertTrue(CloudBridge.outcome(of: chinese).answer.contains("请先"), CloudBridge.outcome(of: chinese).answer)
        let traditional: [JObject] = [["action": .str("done"), "answer": .str("深圳明天（11/12 週四）最高溫 28°")]]
        XCTAssertEqual(CloudBridge.outcome(of: traditional).answer, "成功：深圳明天（11/12 周四）最高温 28°")
        XCTAssertEqual(CloudBridge.outcome(of: [["action": .str("stopped")]]).answer, "失败：任务被停止了")
        XCTAssertEqual(CloudBridge.said(true, "成功：已发出"), "成功：已发出", "not twice")
        // 122 q12: a part not found is not a success.
        XCTAssertEqual(CloudBridge.said(true, "Wi-Fi 是 HUAWEI-510；電池電量百分比未能核實。"), "部分失败：Wi-Fi 是 HUAWEI-510；电池电量百分比未能核实。")
        XCTAssertTrue(WatchSettings.phoneTaskResult(action: "fail", answer: nil, attempted: [], reason: "step limit reached")
            .hasPrefix("失败：这次任务未能确认完成（步骤用完了还没做完）"))
        XCTAssertTrue(WatchSettings.taskFailedReply.hasPrefix("失败："))
    }

    /// r05 (121, 11-11): the model's look let a summary for 测试群 go into 小红书's comment box and into 验证群; r09: it
    /// blocked a search's Return in 拼多多. When the goal names a group, the title at the top decides.
    func testWhereAMessageGoesIsReadOffTheTitle() {
        let task = "幫我做這八件事：1. 在淘寶搜尋充電寶；7. 把以上結果整理成一段話發到测试群；8. 告訴我發出去了沒有"
        XCTAssertTrue(AgentLoop.namedGroups(task).contains { $0.hasSuffix("测试群") }, "\(AgentLoop.namedGroups(task))")
        XCTAssertEqual(AgentLoop.chatCheck(seen: "测试群", task: task, steps: []), .right)
        XCTAssertEqual(AgentLoop.chatCheck(seen: "测试群（3人）", task: task, steps: []), .right)
        XCTAssertEqual(AgentLoop.chatCheck(seen: "測試群", task: "在测试群發：早安", steps: []), .right, "Traditional title")
        if case .wrong = AgentLoop.chatCheck(seen: "验证群", task: task, steps: []) {} else { XCTFail("验证群 is not 测试群") }
        let xhs: [JObject] = [["action": .str("open"), "app": .str("小紅書")]]
        if case .wrong = AgentLoop.chatCheck(seen: nil, task: task, steps: xhs) {} else { XCTFail("小红书's comment box") }
        XCTAssertEqual(AgentLoop.chatCheck(seen: nil, task: task, steps: [["action": .str("open"), "app": .str("微信")]]), .unknown)
        XCTAssertEqual(AgentLoop.chatCheck(seen: "张三", task: "回覆張三：好的", steps: []), .unknown, "no group named")
        XCTAssertEqual(AgentLoop.namedGroups("拉到微信群里"), [], "a word, not a group's name")
        XCTAssertFalse(AgentLoop.needsApproval("充電寶", task: task, chatApp: false), "a search in 淘宝 is not a message")
    }

    func testTheQuotaIsKept() throws {
        let saved = UserDefaults.standard.data(forKey: PlusQuota.key)
        defer { UserDefaults.standard.set(saved, forKey: PlusQuota.key) }
        let quota = try XCTUnwrap(PlusQuota(headers: ["x-codex-secondary-used-percent": "100"], now: 5))
        PlusQuota.save(quota)
        XCTAssertEqual(PlusQuota.saved, quota)
        XCTAssertEqual(PlusQuota.saved?.long?.minutes, 10080, "the week when the header leaves it out")
    }
}
