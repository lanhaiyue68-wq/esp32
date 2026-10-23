import XCTest
@testable import IPhoneAgent

/// WeChat watch: who is read and answered, what triggers a reply, what is kept and reported, what never leaves.
@MainActor final class WatchModeTests: XCTestCase {
    private func rules(_ edit: (inout WatchSettings.Rules) -> Void = { _ in }) -> WatchSettings.Rules {
        var r = WatchSettings.Rules(targets: ["客户群", "张三"], onlyListed: true, senders: ["老板"], passphrases: ["天王盖地虎"],
                                    interject: false, serverReplies: false, instruction: "礼貌回复", fallback: "稍后人工回复", knowledge: true)
        edit(&r)
        return r
    }

    func testNamesAreOnePerLineOrSeparatedByCommas() {
        XCTAssertEqual(WatchSettings.lines("张三\n 客户群 ，李四、张三\n\n"), ["张三", "客户群", "李四"])
    }

    func testOnlyAnAtOrAPassphraseFromTheWhitelistTriggersAReply() {
        let task = WatchSettings.task(rules())
        XCTAssertTrue(task.contains("只看这些会话：“客户群”、“张三”"))
        XCTAssertTrue(task.contains("只有“老板”在消息里@你，或消息里出现暗号“天王盖地虎”时，才回复"))
        XCTAssertTrue(task.contains("只读取并记录"))
        XCTAssertFalse(task.contains("插嘴模式"))
        XCTAssertTrue(task.contains("知识库里没有答案时，回复：“稍后人工回复”"))
        XCTAssertTrue(task.contains("不点红包、转账、付款"))
        XCTAssertTrue(task.contains(#"{"messages":["#))
        XCTAssertFalse(task.contains("画"))  // never looks like a drawing task (unmadeResult)
    }

    func testInterjectAndServerModesChangeOnlyTheReplyRule() {
        XCTAssertTrue(WatchSettings.task(rules { $0.interject = true }).contains("插嘴模式"))
        let server = WatchSettings.task(rules { $0.serverReplies = true; $0.interject = true })
        XCTAssertTrue(server.contains("不要自己回复任何消息"))
        XCTAssertFalse(server.contains("插嘴模式"))
        let anyone = WatchSettings.task(rules { $0.senders = []; $0.onlyListed = false; $0.knowledge = false })
        XCTAssertTrue(anyone.contains("只有会话里的人在消息里@你"))
        XCTAssertTrue(anyone.contains("看私聊里的未读消息"))
        XCTAssertTrue(anyone.contains("用户没有选定知识库"))
        XCTAssertTrue(WatchSettings.sendTask(chat: "客户群", text: "好的").contains("“客户群”"))
    }

    func testTheMessagesReadAreParsedFromTheDoneAnswer() {
        let answer = #"读完了 {"messages":[{"chat":"客户群","group":true,"sender":"老板","text":"@我 天王盖地虎 明天几点","atMe":true,"replied":"十点"},{"chat":"张三","sender":"张三","text":""}]}"#
        let read = WatchReport.parse(answer)
        XCTAssertEqual(read.count, 1)  // the empty one is dropped; missing fields default
        XCTAssertEqual(read.first?.chat, "客户群")
        XCTAssertEqual(read.first?.atMe, true)
        XCTAssertEqual(read.first?.replied, "十点")
        XCTAssertEqual(WatchReport.parse("没有新消息"), [])
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
