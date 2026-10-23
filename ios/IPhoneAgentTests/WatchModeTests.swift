import XCTest
@testable import IPhoneAgent

/// WeChat watch: who is answered, from which knowledge, and what never leaves the phone.
@MainActor final class WatchModeTests: XCTestCase {
    func testNamesAreOnePerLineOrSeparatedByCommas() {
        XCTAssertEqual(WatchSettings.lines("张三\n 客户群 ，李四、张三\n\n"), ["张三", "客户群", "李四"])
    }

    func testTheTaskNamesOnlyTheChosenChatsAndKeepsTheSafetyRules() {
        let task = WatchSettings.task(targets: ["客户群", "张三"], onlyListed: true, instruction: "礼貌回复",
                                      fallback: "稍后人工回复", knowledge: true)
        XCTAssertTrue(task.contains("只处理这些会话：“客户群”、“张三”"))
        XCTAssertTrue(task.contains("礼貌回复"))
        XCTAssertTrue(task.contains("知识库里没有答案时，回复：“稍后人工回复”"))
        XCTAssertTrue(task.contains("不点红包、转账、付款"))
        XCTAssertFalse(task.contains("画"))  // never looks like a drawing task (unmadeResult)
        let open = WatchSettings.task(targets: [], onlyListed: false, instruction: "x", fallback: "y", knowledge: false)
        XCTAssertTrue(open.contains("处理私聊里的未读消息"))
        XCTAssertTrue(open.contains("用户没有选定知识库"))
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
