import XCTest
@testable import IPhoneAgent

/// Build 125: 群收录 (user 11-12, from the customer; docs/spec-group-archive-125.md).
@MainActor final class Build125Tests: XCTestCase {

    func testWhatIsOpenedLater() {
        XCTAssertEqual(WatchArchive.kind("[图片]"), "image")
        XCTAssertEqual(WatchArchive.kind("[视频号] 某某的视频"), "channels")
        XCTAssertEqual(WatchArchive.kind("[文件]"), "file")
        XCTAssertEqual(WatchArchive.kind("[链接] 新手必看的十个技巧"), "link")
        XCTAssertEqual(WatchArchive.kind("看这个 https://v.douyin.com/abc/"), "link")
        XCTAssertEqual(WatchArchive.kind("[聊天记录] 群聊的聊天记录"), "card")
        XCTAssertNil(WatchArchive.kind("大家早上好"))
        XCTAssertNil(WatchArchive.kind("[语音] 今天开会"), "a voice is written out, not opened")
        XCTAssertNil(WatchArchive.kind("[动画表情]"))
    }

    func testTheOpenTaskIsReadOnlyAndSendsNothing() {
        let item = ArchiveItem(chat: "测试群", sender: "张三", kind: "file", text: "[文件]", at: Date())
        let task = WatchArchive.openTask(item)
        XCTAssertTrue(task.contains("微信会话“测试群”"), "starts in WeChat: an open of WeChat is refused")
        XCTAssertTrue(task.contains("只看不动"))
        XCTAssertTrue(task.contains("点下载"))
        XCTAssertTrue(task.contains("不会发给任何人"))
    }

    func testTheDaysKnowledgeIsReadAndSent() {
        let reply = "好的：\n[{\"title\":\"投流先小额测试\",\"content\":\"先 100 元测三天\",\"links\":[],\"source\":\"测试群·张三\"},{\"title\":\"\"}]"
        let items = WatchArchive.knowledge(reply)
        XCTAssertEqual(items?.count, 1, "an item without a title is dropped")
        XCTAssertEqual(WatchArchive.knowledge("[]")?.count, 0, "no knowledge that day")
        XCTAssertNil(WatchArchive.knowledge("没有干货"), "not a list: tried again later")
        let body = WatchArchive.uploadBody(day: "2026-11-12", device: "home_iphone_01", items: items ?? [])
        XCTAssertEqual(body["date"] as? String, "2026-11-12")
        XCTAssertEqual((body["items"] as? [[String: Any]])?.count, 1)
    }

    func testTheInputHoldsTalkAndWhatWasOpened() {
        let talk = ReadMessage(chat: "测试群", group: true, sender: "张三", text: "这个工具很好用", atMe: false, replied: "")
        var seen = ArchiveItem(chat: "测试群", sender: "李四", kind: "image", text: "[图片]", at: Date())
        seen.summary = "一张价格表"; seen.ok = true
        let input = WatchArchive.distillInput(day: "2026-11-12", messages: [talk], opened: [seen])
        XCTAssertTrue(input.contains("张三：这个工具很好用"))
        XCTAssertTrue(input.contains("点开看到：一张价格表"))
    }
}

/// Build 125, fixes from 124's regression on the phone (11-12, docs/device-2026-11-12-build124-report.md).
@MainActor final class Build125FixTests: XCTestCase {

    /// e03: Codex answered all nine things in the "done" of part 2; it was taken as part 2 only.
    func testADoneThatAnswersTheWholeGoalEndsIt() {
        let goal = "帮我做这九件事：1. 查深圳；2. 查广州；3. 查上海；4. 查北京；5. 排好；6. 在测试群发；7. 在验证群发；8. 再看一眼；9. 告诉我"
        let all = "已完成全部九件事：1. 深圳27°；2. 广州27°；3. 上海18°；4. 北京13°；5. 深圳、广州、上海、北京；6. 已发；7. 已发；8. 都在"
        XCTAssertTrue(AgentLoop.answersWholeGoal(all, task: goal))
        XCTAssertFalse(AgentLoop.answersWholeGoal("深圳今日最高温27°", task: goal))
        XCTAssertFalse(AgentLoop.answersWholeGoal("1. 好了；2. 好了", task: "查深圳明天的天气"), "one part: nothing to skip")
    }

    /// h07: a short 抖音 video plays round and round and was listened to again and again.
    func testHearingTheSameAgainMeansTheVideoStartedOver() {
        let once = "大家好今天给大家分享一个做红烧肉的小窍门先把五花肉切块冷水下锅焯水再炒糖色"
        XCTAssertTrue(AgentLoop.repeatsHeard(once + "大家好今天给大家", before: ["听到和字幕（60 秒）：" + once]))
        XCTAssertFalse(AgentLoop.repeatsHeard("第十七条六G技术预测报告发布专家认为未来五年将进入商用阶段", before: ["听到和字幕（60 秒）：" + once]))
        XCTAssertFalse(AgentLoop.repeatsHeard("短", before: ["短"]), "too little to tell")
        XCTAssertFalse(AgentLoop.repeatsHeard(once, before: []))
    }

    /// User 11-12: a success is just the result; only a failure says 失败.
    func testOnlyAFailureIsLabeled() {
        XCTAssertEqual(CloudBridge.said(true, "成功：深圳明天27°C"), "深圳明天27°C")
        XCTAssertEqual(CloudBridge.said(true, "深圳明天27°C"), "深圳明天27°C")
        XCTAssertEqual(CloudBridge.said(true, ""), "已完成")
        XCTAssertEqual(CloudBridge.said(false, "日历打不开"), "失败：日历打不开")
        XCTAssertEqual(CloudBridge.said(true, "成功：日历未能完成，其余都查到了"), "部分失败：日历未能完成，其余都查到了")
        XCTAssertEqual(CloudBridge.failureWords("stuck: 3 new plans in a row and nothing got on"), "卡住了，换了几种做法都没有进展")
    }

    /// 测试群 11-12: a task was given and the first reply was "这个我不太确定，稍后再告诉你。".
    func testATaskIsAnsweredWithItsOnTheWay() {
        let d = WatchReport.decision(#"{"reply":"这个我不太确定，稍后再告诉你。","task":"查深圳明天最高温"}"#)
        XCTAssertEqual(d?.reply, WatchReport.taskAck)
        XCTAssertEqual(d?.task, "查深圳明天最高温")
        XCTAssertEqual(WatchReport.decision(#"{"reply":"收到","task":"查一下"}"#)?.reply, "收到")
        XCTAssertEqual(WatchReport.decision(#"{"reply":"这个我不太确定","task":""}"#)?.reply, "这个我不太确定", "no task: as it is")
    }

    /// 测试群 11-12: what WeChat wrote out under the owner's voice was read as a message of its own.
    func testWrittenOutWordsGoBackOnTheirVoice() {
        typealias L = WatchReport.Line
        let joined = WatchReport.joinVoiceText([L(sender: "主人蓝海乐", text: "[语音]", mine: false),
                                                L(sender: "主人蓝海乐", text: "給我查一下北京明天的天氣怎麼樣？", mine: false)])
        XCTAssertEqual(joined, [L(sender: "主人蓝海乐", text: "[语音] 給我查一下北京明天的天氣怎麼樣？", mine: false)])
        XCTAssertFalse(WatchReport.bareVoice(joined[0].text))
        let other = [L(sender: "主人蓝海乐", text: "[语音]", mine: false), L(sender: "张三", text: "好的", mine: false)]
        XCTAssertEqual(WatchReport.joinVoiceText(other), other, "someone else's words stay theirs")
        let picture = [L(sender: "主人蓝海乐", text: "[语音]", mine: false), L(sender: "主人蓝海乐", text: "[图片]", mine: false)]
        XCTAssertEqual(WatchReport.joinVoiceText(picture), picture)
    }

    /// User 11-12: "能點到轉文字就不用長按"; never played aloud.
    func testAVoiceIsNeverPlayed() throws {
        let task = try XCTUnwrap(WatchSettings.lookDefault("[语音] 3\""))
        XCTAssertTrue(task.contains("就只点它一下"))
        XCTAssertTrue(task.contains("绝对不要点语音播放"))
        XCTAssertTrue(task.contains("取消转成文字"))
        XCTAssertFalse(task.contains("用 listen 听（"))
    }

    /// The watch tapped 虾笔刀陪跑学员元群's row for 测试群 again and again.
    func testTheOpenTaskReadsTheRowsName() {
        let r = WatchSettings.Rules(targets: ["测试群"], onlyListed: false, follow: [])
        XCTAssertTrue(WatchSettings.openTask(r).contains("不要凭位置记忆去点"))
        XCTAssertTrue(WatchSettings.openTask(r).contains("不要再点同一个位置"))
    }
    /// k03 on 125: both messages went out, then the run went back and forth between the groups with nothing written down.
    func testAMessageSentIsWrittenDown() {
        XCTAssertEqual(AgentLoop.sentNote("125多任务开始", to: "测试群"), "已在“测试群”发出：125多任务开始")
        XCTAssertEqual(AgentLoop.sentNote("好的", to: nil), "已在聊天里发出：好的")
    }
    /// k07 on 125 (and 124's h07): "推荐页第一个视频" took the way of "搜索“早啊新闻”" and typed 早啊新闻.
    func testAWayThatTypedTheOldGoalsWordsIsNotFollowedWithoutThem() {
        let routes = RouteBook(file: nil)
        routes.storeRecipe(task: "在抖音搜索“早啊新闻”，打开第一个视频，从头播放，用 listen 听它讲了什么，给我完整的口播文案。不要点赞，不要评论",
                           lines: ["open 抖音", "tap 927 87", "type “早啊新闻”", "tap “搜索”", "listen"])
        XCTAssertNil(routes.recipe(for: "在抖音推荐页打开第一个视频，从头播放，用 listen 听它讲了什么，给我口播文案。不要点赞，不要评论，不要关注"))
        let other = routes.recipe(for: "在抖音搜索“新闻联播”，打开第一个视频，从头播放，用 listen 听它讲了什么，给我完整的口播文案。不要点赞，不要评论")
        XCTAssertEqual(other?.lines[2], "type “\(RouteBook.otherText)”")
        XCTAssertEqual(RouteBook.typedTexts(in: ["open 抖音", "type “早啊新闻”"]), ["早啊新闻"])
    }
    /// User 11-12 on 125: "不能是別人發的語音…必須是白名單裡我發的".
    func testOnlyTheOwnersVoiceIsAnswered() {
        var r = WatchSettings.Rules()
        r.senders = ["主人蓝海乐"]
        r.myNames = ["蓝"]
        r.passphrases = ["天王盖地虎"]
        func voice(_ sender: String, group: Bool = true, _ words: String = "帮我查一下北京现在几度") -> ReadMessage {
            ReadMessage(chat: group ? "测试群" : sender, group: group, sender: sender, text: "[语音] " + words)
        }
        XCTAssertTrue(WatchSettings.fires(voice("主人蓝海乐"), r))
        XCTAssertFalse(WatchSettings.fires(voice("张三"), r), "someone else's voice in the group")
        XCTAssertFalse(WatchSettings.fires(voice("张三", "天王盖地虎 帮我查一下"), r), "a passphrase spoken by someone else")
        XCTAssertFalse(WatchSettings.fires(voice("主人蓝海乐的朋友"), r), "a name that only holds the owner's")
        XCTAssertFalse(WatchSettings.fires(voice("张三", group: false), r), "a private chat with someone else")
        r.senders = []
        XCTAssertFalse(WatchSettings.fires(voice("主人蓝海乐"), r), "no whitelist: nobody's voice")
    }
    /// Stress test on 125 (s03): a new note's first line, part of the goal's message, was taken for that message.
    func testReturnInAnAppThatSendsNothingIsNotAMessage() {
        XCTAssertTrue(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("備忘錄")]]))
        XCTAssertTrue(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("设置")]]))
        XCTAssertFalse(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("微信")]]))
        XCTAssertFalse(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("小红书")]]), "a comment there goes out")
        XCTAssertFalse(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("備忘錄")], ["action": .str("home")]]))
    }

    /// Stress test on 125 (s01): 加入购物车 again and again, ×5 in the cart.
    func testTheAddedToCartToastIsSeen() {
        func row(_ t: String) -> [CandidatePicker.Piece] { [CandidatePicker.Piece(text: t, box: CGRect(x: 0.3, y: 0.5, width: 0.4, height: 0.03))] }
        XCTAssertTrue(AgentLoop.addedToCart([row("加購成功")]))
        XCTAssertTrue(AgentLoop.addedToCart([row("已加入购物车")]))
        XCTAssertFalse(AgentLoop.addedToCart([row("加入购物车")]), "the button itself")
        XCTAssertTrue(AgentLoop.cartNote(2).contains("一共加了2次"))
    }
    /// Stress test on 125 (t06): “蓝牙耳机” searched in 淘宝 was taken for the goal's message.
    func testOnlyAQuoteAfterSendIsAMessage() {
        let task = "1. 在淘宝搜索“蓝牙耳机”；2. 新建一条备忘录，第一行写“第二轮压力测试”；3. 在测试群发“125压力测试第二轮完成”"
        XCTAssertEqual(AgentLoop.messageParts(task), ["第二轮压力测试", "125压力测试第二轮完成"])
        XCTAssertFalse(AgentLoop.needsApproval("蓝牙耳机", task: task, chatApp: false))
        XCTAssertTrue(AgentLoop.needsApproval("125压力测试第二轮完成", task: task, chatApp: true))
        XCTAssertEqual(AgentLoop.messageParts("在测试群先發「k02第一句」，再發「k02第二句」"), ["k02第一句", "k02第二句"])
        XCTAssertEqual(AgentLoop.messageParts("在抖音搜索“深圳美食”"), [], "a search only")
        XCTAssertEqual(AgentLoop.refusalLimit, 25)
    }
    /// Stress test on 125 (u05): "@蓝海乐 125压力测试艾特" went out twice.
    func testTheSameMessageWithMoreAroundItIsTheSame() {
        let sent: Set<String> = ["125压力测试艾特"]
        XCTAssertEqual(AgentLoop.sameMessage("@蓝海乐 125压力测试艾特", in: sent), "125压力测试艾特")
        XCTAssertEqual(AgentLoop.sameMessage("125压力测试艾特", in: sent), "125压力测试艾特")
        XCTAssertNil(AgentLoop.sameMessage("第三轮丙", in: ["第三轮甲"]))
        XCTAssertNil(AgentLoop.sameMessage("好的，明天见", in: ["好的"]), "too short to tell")
    }
}
