import XCTest
@testable import IPhoneAgent

/// Build 119 in 测试群, 11-11: a watch reply went out twice. The return had sent it; four reads could not find the
/// chat's title, and the follow-up was told to fix an empty box, so it typed the reply again.
@MainActor final class Build120Tests: XCTestCase {
    func testAfterAReturnTheFollowUpNeverTypesTheReplyAgain() {
        let task = WatchSettings.sentCheckTask(chat: "测试群", text: "你好，今天是2026年11月11日，星期三。")
        XCTAssertTrue(task.contains("按过发送"))
        XCTAssertTrue(task.contains("输入框是空的，说明已经发出了"))
        XCTAssertTrue(task.contains("不允许输入任何文字"))
        XCTAssertFalse(task.contains("输入框为空时才明确修正"), "the old wording that made it type again")
    }

    func testARunThatMayNotTypeRefusesEveryType() async {
        let actor = FakeModel { n in n == 1 ? "THINK: 输入框是空的，重新输入\nDO: type 你好，今天是2026年11月11日，星期三。"
                                            : "THINK: 已经发出了\nDO: done 输入框已空，可能已发出" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: nil, trace: nil)
        agent.directStart = true
        agent.outgoingGuard = { _ in "Refused: this reply was already typed and Return was pressed. Never type it again." }
        agent.showMock(task: WatchSettings.sentCheckTask(chat: "测试群", text: "你好"), plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertFalse(phone.calls.contains("type"), "\(phone.calls)")
        XCTAssertTrue(agent.steps.contains { $0["action"]?.str == "blocked" })
        XCTAssertEqual(agent.steps.last?["action"]?.str, "done")
    }
}
