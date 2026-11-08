import XCTest
@testable import IPhoneAgent

/// What the night of stress tests over USB (11-09) found: what a run read stays with it, and it does not go round.
@MainActor final class StressNightTests: XCTestCase {
    /// Whichever model drives: the first reply is the plan, the rest follow the script.
    private func models(_ script: [String]) -> (FakeModel, FakeModel) {
        var turn = 0
        func next() -> String {
            turn += 1
            return script[min(turn, script.count) - 1]
        }
        return (FakeModel { _ in next() }, FakeModel { _ in next() })
    }

    func testANoteGoesWithEveryLookAndTouchesNothing() async {
        let (actor, planner) = models(["1. read it", "THINK: read\nDO: note 淘寶 ¥19.9\nDO: wait", "THINK: that is all\nDO: done ¥19.9"])
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "查價", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.notes, ["淘寶 ¥19.9"])
        XCTAssertTrue((actor.prompts + planner.prompts).contains { $0.contains("- 淘寶 ¥19.9") })
        XCTAssertTrue(phone.calls.isEmpty, "a note moves nothing on the phone")
    }

    func testAPartPassesOnWhatItFound() async {
        let (actor, planner) = models(["1. read a price\n2. send it", "THINK: read\nDO: done 價格 19", "THINK: sent\nDO: done ok"])
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "查價再發", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertTrue((actor.prompts + planner.prompts).contains { $0.contains("1. read a price -> 價格 19") })
    }

    func testWaitingIsRefusedOnceItChangedNothing() {
        let wait: JObject = ["action": .str("wait"), "changed": .bool(false)]
        let moved: JObject = ["action": .str("wait"), "changed": .bool(true)]
        let refused: JObject = ["action": .str("refused")]
        XCTAssertFalse(AgentLoop.waitedEnough([wait, wait]))
        XCTAssertTrue(AgentLoop.waitedEnough([wait, wait, wait]))
        XCTAssertTrue(AgentLoop.waitedEnough([wait, wait, wait, refused]), "a refusal does not start the count again")
        XCTAssertFalse(AgentLoop.waitedEnough([wait, moved, wait]))
    }

    func testLeavingTheSameScreenTheSameWayIsCounted() {
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: FakeModel { _ in "" }, planner: nil, trace: nil)
        let sheet = [UInt8](repeating: 100, count: 24 * 48), home = [UInt8](repeating: 200, count: 24 * 48)
        let toHome: JObject = ["action": .str("home")]
        let reminders: JObject = ["action": .str("open"), "app": .str("提醒事項")]
        XCTAssertFalse(agent.circling(toHome, on: sheet))
        XCTAssertFalse(agent.circling(toHome, on: sheet))
        XCTAssertTrue(agent.circling(toHome, on: sheet), "the third time it does not go")
        for name in ["淘寶", "拼多多", "美團", "微信"] {  // many apps from the Home Screen are not a circle
            XCTAssertFalse(agent.circling(["action": .str("open"), "app": .str(name)], on: home))
        }
        XCTAssertFalse(agent.circling(reminders, on: home))
        XCTAssertFalse(agent.circling(["action": .str("tap"), "x": .int(1), "y": .int(1)], on: sheet), "only ways off a screen")
    }

    func testSameScreenAllowsAKeyAndNotAPage() {
        let shown = [UInt8](repeating: 100, count: 24 * 48)
        var key = shown, page = shown
        for i in 300..<320 { key[i] = 200 }
        for i in 100..<600 { page[i] = 200 }
        XCTAssertTrue(Vision.sameScreen(shown, key))
        XCTAssertFalse(Vision.sameScreen(shown, page))
    }

    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: text, box: CGRect(x: x - 0.05, y: y - 0.01, width: 0.1, height: 0.02))
    }

    func testWordsInTheirPlacesTellAVideoFromAScroll() {
        let shown = [[piece("關注", 0.3, 0.1), piece("推薦", 0.5, 0.1), piece("搜尋", 0.9, 0.1), piece("首頁", 0.1, 0.95)]]
        let video = [[piece("關注", 0.3, 0.1), piece("推薦", 0.5, 0.1), piece("搜尋", 0.9, 0.1), piece("首頁", 0.1, 0.95)]]
        let scrolled = [[piece("關注", 0.3, 0.2), piece("推薦", 0.5, 0.2), piece("搜尋", 0.9, 0.2), piece("首頁", 0.1, 0.8)]]
        XCTAssertTrue(AgentLoop.sameWords(shown, video))
        XCTAssertFalse(AgentLoop.sameWords(shown, scrolled))
        XCTAssertFalse(AgentLoop.sameWords([], []))
    }

    func testSearchFindsAnAppByPartOfItsNameOnlyUnderTheAppHeader() {
        let found = [[piece("App", 0.1, 0.1)], [piece("高德地圖", 0.3, 0.15)], [piece("建議", 0.1, 0.25)]]
        XCTAssertEqual(AppPlaces.searchResult("高德", in: found)?.y ?? 0, 0.15, accuracy: 0.001)
        let web = [[piece("建議", 0.1, 0.1)], [piece("小藍藍記賬", 0.3, 0.15)]]
        XCTAssertNil(AppPlaces.searchResult("小藍藍記賬", in: web), "Safari's suggestion is not the app")
    }

    func testOurKeyboardsReturnKeyIsItsLastKey() {
        XCTAssertTrue(AgentLoop.onOurReturnKey(["action": .str("tap"), "x": .int(861), "y": .int(795)]))
        XCTAssertFalse(AgentLoop.onOurReturnKey(["action": .str("tap"), "x": .int(620), "y": .int(795)]), "backspace")
        XCTAssertFalse(AgentLoop.onOurReturnKey(["action": .str("tap"), "x": .int(861), "y": .int(300)]))
    }

    func testANoteParses() throws {
        let act = try Actions.parseCommand("note 淘寶 ¥19.9，拼多多 ¥13.8")
        XCTAssertEqual(act["action"]?.str, "note")
        XCTAssertEqual(act["text"]?.str, "淘寶 ¥19.9，拼多多 ¥13.8")
    }

    func testSharingOnIsNotAReasonToAskTheUser() {
        XCTAssertFalse(BlindError().sharingOn)
        XCTAssertTrue(BlindError(reason: "late", sharingOn: true).sharingOn)
    }
}
