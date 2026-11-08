import XCTest
@testable import IPhoneAgent

/// Phase C: ChatGPT Plus plans (the commander), Doubao acts; any Plus failure plans with Doubao.
@MainActor final class Build101Tests: XCTestCase {
    private let signedIn = ChatGPTPlus.Tokens(idToken: "i", accessToken: "a", refreshToken: "r", accountID: "x")
    private func answer(_ text: String) -> ChatGPTPlus.Answer {
        ChatGPTPlus.Answer(text: text, model: "gpt-6.1-terra", firstTokenMs: 900, totalMs: 1400, quota: [:])
    }

    func testPlusPlansWithThePlannersOwnInstructions() async throws {
        let doubao = FakeModel { _ in "doubao plan" }
        var asked: (system: String, prompt: String, image: Data?)?
        let plus = PlusChat(model: "gpt-6.1-terra", fallback: doubao, tokens: { self.signedIn }, save: { _ in },
                            ask: { tokens, _, system, prompt, image in
                                asked = (system, prompt, image)
                                return (self.answer("1. 打开时钟\n2. 新建 8:00 闹钟"), tokens)
                            })
        let result = try await plus.chat(system: "PLANNER RULES", text: "Goal: 开闹钟", image: Data([1]), maxTokens: 800, temperature: 0)
        XCTAssertEqual(result.text, "1. 打开时钟\n2. 新建 8:00 闹钟")
        XCTAssertEqual(asked?.system, "PLANNER RULES")
        XCTAssertEqual(asked?.prompt, "Goal: 开闹钟")
        XCTAssertEqual(asked?.image, Data([1]), "the planner sees the screen")
        XCTAssertEqual(plus.model, "plus:gpt-6.1-terra")
        XCTAssertTrue(doubao.prompts.isEmpty)
    }

    func testAPlusFailurePlansWithDoubaoAndRestsPlus() async throws {
        let doubao = FakeModel { _ in "doubao plan" }
        var calls = 0
        let plus = PlusChat(model: "gpt-6.1-terra", fallback: doubao, tokens: { self.signedIn }, save: { _ in },
                            ask: { _, _, _, _, _ in calls += 1; throw ChatGPTPlus.Failure(message: "HTTP 429：usage limit") })
        let first = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 10, temperature: 0)
        let second = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 10, temperature: 0)
        XCTAssertEqual(first.text, "doubao plan"); XCTAssertEqual(second.text, "doubao plan")
        XCTAssertEqual(calls, 1, "after a failure Plus rests instead of failing on every plan")
        XCTAssertEqual(plus.model, "fake")
    }

    func testNotSignedInPlansWithDoubao() async throws {
        let doubao = FakeModel { _ in "doubao plan" }
        let plus = PlusChat(model: "m", fallback: doubao, tokens: { nil }, save: { _ in },
                            ask: { _, _, _, _, _ in XCTFail("never asked without a sign-in"); throw CancellationError() })
        let result = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 10, temperature: 0)
        XCTAssertEqual(result.text, "doubao plan")
    }

    func testRefreshedTokensAreKept() async throws {
        var kept: ChatGPTPlus.Tokens?
        let fresh = ChatGPTPlus.Tokens(idToken: "i2", accessToken: "a2", refreshToken: "r2", accountID: "x")
        let plus = PlusChat(model: "m", fallback: FakeModel { _ in "" }, tokens: { self.signedIn }, save: { kept = $0 },
                            ask: { _, _, _, _, _ in (self.answer("plan"), fresh) })
        _ = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 10, temperature: 0)
        XCTAssertEqual(kept, fresh)
    }

    func testSwitchedOffMeansDoubaoPlans() {
        let defaults = UserDefaults(suiteName: "Build101Tests")!
        defaults.removePersistentDomain(forName: "Build101Tests")
        defaults.set(false, forKey: PlusChat.enabledKey)
        let doubao = FakeModel { _ in "" }
        XCTAssertTrue(PlusChat.planner(fallback: doubao, defaults: defaults) === doubao)
    }

    func testEachPartOfAPlanGetsItsOwnSteps() {
        let three = "1. 打开时钟，设置明天早上8点的闹钟。\n2. 打开无边记，画一个太阳。\n3. 打开微信，给测试群发消息。"
        XCTAssertEqual(AgentLoop.stepBudget(plan: three, base: 40), 60)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "1. 打开时钟\n2) 新建\n3、保存\n4．回报", base: 40), 80)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "1. Open Clock and add an 8:00 alarm.", base: 40), 40, "one part: as before")
        XCTAssertEqual(AgentLoop.stepBudget(plan: (1...8).map { "\($0). step" }.joined(separator: "\n"), base: 40), 100)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "Work from the CURRENT screen", base: 15), 15)
    }

    func testAnHourTypedAloneIntoATimeWheelIsHHMM() {
        XCTAssertEqual(AgentLoop.wheelTime("10", thought: "点小时滚轮后输入 10"), "1000")
        XCTAssertEqual(AgentLoop.wheelTime("8", thought: "set the alarm hour"), "0800")
        XCTAssertNil(AgentLoop.wheelTime("1000", thought: "alarm"), "already HHMM")
        XCTAssertNil(AgentLoop.wheelTime("10", thought: "数量填 10"), "not about a time")
        XCTAssertNil(AgentLoop.wheelTime("25", thought: "hour"))
        XCTAssertNil(AgentLoop.wheelTime("收到", thought: "alarm"))
    }
}
