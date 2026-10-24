import XCTest
@testable import IPhoneAgent

@MainActor final class WatchNavigationTests: XCTestCase {
    private func title(_ text: String, x: Double = 0.4, y: Double = 0.075) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x, y: y, width: 0.2, height: 0.02))
    }

    func testAnOpenedTargetStopsBeforeTheActorCanGoBackAndEraseUnread() async throws {
        // logs(22): the actor saw the desired chat, went back, then said no unread chat remained.
        let model = FakeModel { _ in "THINK: Go back to the list first.\nDO: tap 54 86" }
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        var gates = 0
        agent.gate = { gates += 1 }
        agent.frameCompletion = { _ in #"{"chat":"客户群"}"# }
        let actions = try await agent.nextActions()
        XCTAssertEqual(actions.first?.act["action"]?.str, "done")
        XCTAssertEqual(actions.first?.act["answer"]?.str, #"{"chat":"客户群"}"#)
        XCTAssertTrue(model.prompts.isEmpty)
        XCTAssertEqual(gates, 1) // foreground/freshness checks still run before local completion
    }

    func testNoLocalDestinationKeepsTheNormalActorPath() async throws {
        let model = FakeModel { _ in "THINK: Open the unread row.\nDO: tap 300 225" }
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.frameCompletion = { _ in nil }
        let actions = try await agent.nextActions()
        XCTAssertEqual(actions.first?.act["action"]?.str, "tap")
        XCTAssertEqual(model.prompts.count, 1)
    }

    func testOnlyTheNavigationTitleCanFinishOpening() {
        let targets = ["客户群", "张三"]
        XCTAssertEqual(WatchReport.navigationChat(rows: [[title("客户群(90)")]], targets: targets), "客户群")
        XCTAssertNil(WatchReport.navigationChat(rows: [[title("微信")], [title("客户群", y: 0.22)]], targets: targets))
        XCTAssertNil(WatchReport.navigationChat(rows: [[title("客户群", x: 0.0)]], targets: targets))
    }

    func testNavigationNeverGuessesPrefixesTruncatedOrAmbiguousNames() {
        let targets = ["客户群", "客户群二"]
        XCTAssertNil(WatchReport.navigationChat(rows: [[title("客户群二的朋友")]], targets: targets))
        XCTAssertNil(WatchReport.navigationChat(rows: [[title("客户…")]], targets: targets))
        XCTAssertNil(WatchReport.navigationChat(rows: [[title("客户群")], [title("客户群二")]], targets: targets))
        XCTAssertEqual(WatchReport.navigationChat(rows: [[title("客户群二")]], targets: targets), "客户群二")
    }

    func testReadingConfirmsTheDestinationAndAllowedScope() {
        let rules = WatchSettings.Rules(targets: ["客户群", "张三"], onlyListed: true)
        XCTAssertTrue(WatchReport.confirms(.init(title: "客户群(90)", group: true, lines: []), chat: "客户群", rules: rules))
        XCTAssertFalse(WatchReport.confirms(.init(title: "", group: false, lines: []), chat: "客户群", rules: rules))
        XCTAssertFalse(WatchReport.confirms(.init(title: "张三", group: false, lines: []), chat: "客户群", rules: rules))
        XCTAssertFalse(WatchReport.confirms(.init(title: "客户群二", group: true, lines: []), chat: "客户群", rules: rules))
        XCTAssertFalse(WatchReport.confirms(.init(title: "陌生人", group: false, lines: []), chat: "陌生人", rules: rules))
    }
}
