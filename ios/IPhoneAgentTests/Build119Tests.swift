import XCTest
@testable import IPhoneAgent

@MainActor private final class TapScreen: ScreenSource {
    var live = true
    var frame: Data? = Data([1])
    var updated = 0.0, capturedAt = 0.0, aspect = 0.46
    func afterAction(since: Double) async { frame = Data([2]) }
    func requireFrame(after: Double?) async throws {}
}

/// What build 118 on the phone left (11-10/11): a watch reply with a made-up date, a return that did not send, a tapped
/// chat left unread, a search held for approval, and loop guards that kept refusing after Codex's new plan.
@MainActor final class Build119Tests: XCTestCase {
    // MARK: WeChat watch

    func testTheReplyIsWrittenWithThePhonesDate() throws {
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 0, minute: 27)))
        XCTAssertTrue(WatchSettings.todayZh(date).contains("2026年11月11日 星期三"), WatchSettings.todayZh(date))
        let prompt = WatchSettings.composePrompt(chat: "测试群", group: true, recent: [], due: [], r: WatchSettings.Rules(),
                                                 knowledge: "", owner: false)
        XCTAssertTrue(prompt.hasPrefix("现在是"), prompt)
    }

    func testATappedListedChatIsNamedEvenWhenItsTitleIsNotConfirmed() async {
        var tapped: String?
        let result = await WatchChatOpen.open(phone: FakeGestures(), screen: TapScreen(), rules: WatchSettings.Rules(targets: ["测试群"]),
                                              canAct: { true }, inspectList: { _ in .row("测试群", CGPoint(x: 0.5, y: 0.21)) },
                                              title: { _ in nil }, onTap: { tapped = $0 })
        XCTAssertEqual(result, .unverified)
        XCTAssertEqual(tapped, "测试群", "the caller reads it with readChat's own title check")
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("diagnostics")
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(kept.contains { $0.hasPrefix("watch-unverified-") }, "the frame is kept for a look later")
    }

    // MARK: approvals

    func testASearchInAnAppThatSendsNothingNeedsNoApproval() {
        let metro = "打開高德地圖，查從現在位置走路到最近的地鐵站要多久。不要開始導航"
        XCTAssertFalse(AgentLoop.needsApproval("下水徑地鐵站", task: metro, chatApp: false))
        XCTAssertTrue(AgentLoop.needsApproval("下水徑地鐵站", task: metro, chatApp: true), "in a chat app it could be a message")
        XCTAssertTrue(AgentLoop.needsApproval("116 第四批測試", task: "在微信打開测试群，發一則訊息：116 第四批測試。發完告訴我有沒有發出去", chatApp: false))
        XCTAssertFalse(AgentLoop.inChatApp([["action": .str("open"), "app": .str("高德地圖")]]))
        XCTAssertTrue(AgentLoop.inChatApp([["action": .str("open"), "app": .str("微信")]]))
        XCTAssertTrue(AgentLoop.inChatApp([]), "no app opened by name: it may be one")
    }

    // MARK: swipes

    func testAThirdSwipeTheWayThatMovedNothingIsRefused() {
        let up: JObject = ["action": .str("swipe"), "x1": .int(40), "y1": .int(800), "x2": .int(40), "y2": .int(350), "changed": .bool(false)]
        let steps = [up, ["action": .str("stale plan")], up]
        XCTAssertTrue(AgentLoop.swipedToTheEnd(["action": .str("swipe"), "y1": .int(800), "y2": .int(300)], after: steps))
        XCTAssertFalse(AgentLoop.swipedToTheEnd(["action": .str("swipe"), "y1": .int(300), "y2": .int(750)], after: steps), "the other way")
        var moved = up; moved["changed"] = .bool(true)
        XCTAssertFalse(AgentLoop.swipedToTheEnd(["action": .str("swipe"), "y1": .int(800), "y2": .int(300)], after: [up, moved]))
        XCTAssertTrue(AgentLoop.endReachedReason.contains("swipe 500 300 500 750"))
    }
}
