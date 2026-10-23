import XCTest
@testable import IPhoneAgent

/// WeChat watch: who is read and answered, what triggers a reply, what is kept and reported, what never leaves.
@MainActor final class WatchModeTests: XCTestCase {
    private func rules(_ edit: (inout WatchSettings.Rules) -> Void = { _ in }) -> WatchSettings.Rules {
        var r = WatchSettings.Rules(targets: ["客户群"], onlyListed: true, senders: ["蓝海乐"], passphrases: ["天王盖地虎"],
                                    myNames: ["蓝"], interject: false, serverReplies: false, instruction: "礼貌回复", fallback: "稍后告诉你")
        edit(&r)
        return r
    }

    private func message(_ sender: String, _ text: String) -> ReadMessage {
        ReadMessage(chat: "客户群", group: true, sender: sender, text: text)
    }

    func testNamesAreOnePerLineOrSeparatedByCommas() {
        XCTAssertEqual(WatchSettings.lines("张三\n 客户群 ，李四、张三\n\n"), ["张三", "客户群", "李四"])
    }

    func testOnlyAWhitelistedAtMentionOrPassphraseIsAReplyTrigger() {
        let r = rules()
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "@蓝 你告诉我群主是谁"), r))
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "＠蓝 在吗"), r))
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "天王盖地虎，今天几点开会"), r))
        XCTAssertFalse(WatchSettings.fires(message("蓝海乐", "妈的还得调试"), r))      // traces(34): read, not answered
        XCTAssertFalse(WatchSettings.fires(message("路人甲", "@蓝 借我点钱"), r))      // not whitelisted
        XCTAssertTrue(WatchSettings.fires(message("路人甲", "@蓝 在吗"), rules { $0.senders = [] }))  // no whitelist: anyone
        XCTAssertFalse(WatchSettings.fires(message("蓝海乐", "@蓝色妖姬 你好"), rules { $0.myNames = ["小蓝"] }))
    }

    func testAnAtPassphraseMeansAnAtMentionOfThisAccount() {
        XCTAssertEqual(WatchSettings.passphrases(from: "@我\n天王盖地虎"), ["天王盖地虎"])  // "@我" is not words to look for
        XCTAssertEqual(WatchSettings.names(typed: "蓝", codes: "@我"), ["蓝"])
        XCTAssertEqual(WatchSettings.names(typed: "", codes: "＠蓝\n天王盖地虎"), ["蓝"])
        XCTAssertEqual(WatchSettings.names(typed: "@蓝\n蓝", codes: "@蓝"), ["蓝"])
        let r = rules { $0.passphrases = WatchSettings.passphrases(from: "@我") }
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "@蓝 你告诉我群主是谁"), r))
        XCTAssertFalse(WatchSettings.fires(message("蓝海乐", "大家@我一下"), r))
    }

    func testOpeningTheChatNeverReplies() {
        let one = WatchSettings.openTask(rules())
        XCTAssertTrue(one.contains("“客户群”"))
        XCTAssertTrue(one.contains("已经在这个会话里"))
        XCTAssertTrue(one.contains("不要回复"))
        let many = WatchSettings.openTask(rules { $0.targets = ["客户群", "张三"] })
        XCTAssertTrue(many.contains(#"{"chat":"会话名"}"#))
        XCTAssertFalse(one.contains("画") || many.contains("画"))  // never looks like a drawing task (unmadeResult)
        XCTAssertTrue(WatchSettings.sendTask(chat: "客户群", text: "好的").contains("一字不改"))
    }

    func testTheScreenIsReadIntoLinesAndOnlyWhatFollowsTheSeenOnesIsNew() throws {
        let reply = #"```json {"group":true,"messages":[{"sender":"蓝海乐","text":"@蓝 你人呢"},{"sender":"我","text":"在的","mine":true},{"sender":"蓝海乐","text":"妈的还得调试"},{"sender":"x","text":" "}]} ```"#
        let screen = try XCTUnwrap(WatchReport.screen(reply))
        XCTAssertTrue(screen.group)
        XCTAssertEqual(screen.lines.map(\.text), ["@蓝 你人呢", "在的", "妈的还得调试"])
        let seen = Set(screen.lines.prefix(2).map(WatchReport.key))
        XCTAssertEqual(WatchReport.new(screen.lines, seen: seen).map(\.text), ["妈的还得调试"])
        XCTAssertEqual(WatchReport.new(screen.lines, seen: Set(screen.lines.map(WatchReport.key))), [])
        XCTAssertNil(WatchReport.screen("看不清"))
        XCTAssertEqual(WatchReport.openedChat(#"{"chat":"张三"}"#), "张三")
        XCTAssertNil(WatchReport.openedChat(#"{"chat":""}"#))
    }

    func testTheReplyIsWrittenFromTheChatTheRulesAndTheKnowledge() {
        let lines = [WatchReport.Line(sender: "蓝海乐", text: "@蓝 群主是谁", mine: false)]
        let due = [message("蓝海乐", "@蓝 群主是谁")]
        let prompt = WatchSettings.composePrompt(chat: "客户群", group: true, recent: lines, due: due, r: rules(), knowledge: "## 群.md\n群主是王老师", owner: true)
        XCTAssertTrue(prompt.contains("蓝海乐：@蓝 群主是谁"))
        XCTAssertTrue(prompt.contains("群主是王老师"))
        XCTAssertTrue(prompt.contains("“@蓝”"))
        XCTAssertTrue(prompt.contains("@发言人"))
        let bare = WatchSettings.composePrompt(chat: "张三", group: false, recent: lines, due: due, r: rules(), knowledge: "", owner: false)
        XCTAssertTrue(bare.contains("用户没有给知识库"))
        XCTAssertFalse(bare.contains("@发言人"))
        XCTAssertTrue(WatchSettings.interjectPrompt(chat: "客户群", recent: lines, r: rules()).contains("SKIP"))
        XCTAssertTrue(prompt.contains("主人"))
        XCTAssertTrue(prompt.contains(#""task":"#))
        XCTAssertTrue(bare.contains("不能给 task"))
    }

    func testTheOwnersRequestBecomesAPhoneTaskThatReallyMentions() {
        XCTAssertEqual(WatchReport.decision(#"{"reply":"","task":"查看群成员找出群主，并在群里@群主说：这是群主"}"#)?.task,
                       "查看群成员找出群主，并在群里@群主说：这是群主")
        XCTAssertEqual(WatchReport.decision(#"```json {"reply":"@蓝海乐 在的","task":""} ```"#)?.reply, "@蓝海乐 在的")
        XCTAssertEqual(WatchReport.decision("在的，有事吗")?.reply, "在的，有事吗")  // plain words still work
        XCTAssertNil(WatchReport.decision(#"{"reply": "半截"#))               // broken JSON is never typed
        let task = WatchSettings.ownerTask(chat: "客户群", task: "找出群主并@他")
        XCTAssertTrue(task.contains("标着“群主”"))
        XCTAssertTrue(task.contains("在弹出的成员列表里找到并点选他"))
        XCTAssertTrue(task.contains("不准付款"))
    }

    func testTheReadLogKeepsEachDayAndFeedsTheSummary() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        ReadLog.append([ReadMessage(chat: "客户群", group: true, sender: "老板", text: "明天开会")], at: day, in: dir)
        ReadLog.append([ReadMessage(chat: "张三", group: false, sender: "张三", text: "在吗", replied: "在")], at: day, in: dir)
        let kept = ReadLog.messages(on: day, in: dir)
        XCTAssertEqual(kept.map(\.text), ["明天开会", "在吗"])
        let input = ReadLog.summaryInput(kept)
        XCTAssertTrue(input.contains("[群·客户群] 老板：明天开会"))
        XCTAssertTrue(input.contains("（已回复：在）"))
    }

    func testChatToolPacketsMatchTheRobotFormat() throws {
        XCTAssertEqual(ChatToolLink.socketURL("192.168.31.85:8881", robot: "lan_agent_iphone")?.absoluteString,
                       "ws://192.168.31.85:8881/webserver/wechat/lan_agent_iphone")
        XCTAssertNil(ChatToolLink.socketURL("", robot: "x"))
        let packet = try XCTUnwrap(ChatToolLink.packet(ReadMessage(chat: "客户群", group: true, sender: "老板", text: "你好", atMe: true)))
        let item = try XCTUnwrap(((try JSONSerialization.jsonObject(with: Data(packet.utf8)) as? [String: Any])?["list"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["titleList"] as? [String], ["客户群"])
        XCTAssertEqual(item["receivedName"] as? String, "老板")
        XCTAssertEqual(item["rawSpoken"] as? String, "你好")
        XCTAssertEqual(item["atMe"] as? String, "1")
        XCTAssertEqual(item["roomType"] as? Int, 3)
        let down = #"{"socketType":2,"list":[{"type":203,"titleList":["客户群"],"roomType":3,"receivedContent":"收到","textType":1},{"type":202}]}"#
        XCTAssertEqual(ChatToolLink.commands(down), [ChatToolLink.Command(chat: "客户群", text: "收到")])
        XCTAssertEqual(ChatToolLink.commands("not json"), [])
    }

    func testComputerKnowledgeAddressesCarryTheToken() {
        let url = ComputerKnowledge.url("192.168.31.85:8882", "/files", [URLQueryItem(name: "token", value: "abc")])
        XCTAssertEqual(url?.absoluteString, "http://192.168.31.85:8882/files?token=abc")
        XCTAssertNil(ComputerKnowledge.url(" ", "/files", []))
    }

    func testPrivateWordsAndNumbersAreRefusedWithoutRepeatingThem() {
        let words = ["幸福路88号"]
        let reason = PrivacyGuard.check("我家在幸福路88号", words: words, numbers: true)
        XCTAssertNotNil(reason)
        XCTAssertFalse(reason!.contains("幸福路"))
        XCTAssertNotNil(PrivacyGuard.check("电话 138 1234 5678", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("010-1234-5678", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("身份证 11010519491231002X", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("卡号 6222021234567890123", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("邮箱 me@example.com", words: [], numbers: true))
        XCTAssertNil(PrivacyGuard.check("好的，明天下午 3 点见，订单 2 件", words: words, numbers: true))
        XCTAssertNil(PrivacyGuard.check("电话 13812345678", words: [], numbers: false))
    }

    func testOnlyTheChosenKnowledgeFilesAreUsedAndLongTextIsCut() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "营业时间：每天 10 点到 22 点".write(to: dir.appendingPathComponent("营业.md"), atomically: true, encoding: .utf8)
        try "私人日记".write(to: dir.appendingPathComponent("日记.md"), atomically: true, encoding: .utf8)
        let used = KnowledgeBase.text(["营业.md"], in: dir)
        XCTAssertTrue(used.text.contains("营业时间"))
        XCTAssertFalse(used.text.contains("私人日记"))
        XCTAssertFalse(used.truncated)
        XCTAssertTrue(KnowledgeBase.text(["营业.md"], in: dir, limit: 5).truncated)
    }

    func testARefusedReplyIsNeverTypedAndTheKnowledgeReachesTheModel() async {
        let model = SystemRecorder { n in
            n == 1 ? "1. reply" : n == 2 ? "THINK: answer\nDO: type 我的电话是13812345678" : "THINK: rewritten\nDO: done ok"
        }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.reference = "## 营业.md\n营业时间：每天 10 点到 22 点"
        agent.outgoingGuard = { PrivacyGuard.check($0, words: [], numbers: true) }
        await agent.run()
        XCTAssertFalse(phone.calls.contains("type"))
        XCTAssertTrue(agent.steps.contains { $0["action"]?.str == "blocked" })
        XCTAssertTrue(model.systems[0].contains("营业时间"))  // planner
        XCTAssertTrue(model.systems[1].contains("营业时间"))  // actor
    }
}
