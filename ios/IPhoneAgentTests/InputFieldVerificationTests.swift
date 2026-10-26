import UIKit
import XCTest
@testable import IPhoneAgent

@MainActor final class InputFieldVerificationTests: XCTestCase {
    private func piece(_ text: String, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: 0.06, y: y, width: 0.3, height: 0.03))
    }

    private func rows(input: String, candidate: String) -> [[CandidatePicker.Piece]] {
        [[piece(input, 0.48)], [piece(candidate, 0.6), piece("我", 0.6)],
         [piece("qwertyuiop", 0.65)], [piece("asdfghjkl", 0.72)], [piece("zxcvbnm", 0.8)]]
    }

    func testAKeyboardSuggestionIsNotTextInTheInputField() {
        XCTAssertEqual(CandidatePicker.shows("你好", rows: rows(input: "与助手对话", candidate: "你好")), 0)
    }

    func testTypingIsStillConfirmedWhenTheSameSuggestionDisappears() {
        let before = CandidatePicker.shows("你好", rows: rows(input: "与助手对话", candidate: "你好"))
        let after = CandidatePicker.shows("你好", rows: rows(input: "你好", candidate: "我"))
        XCTAssertEqual(after - before, 1)
    }

    func testASuggestionCannotConfirmAMissedOrWrongInput() {
        XCTAssertEqual(CandidatePicker.shows("你好", rows: rows(input: "你号", candidate: "你好")), 0)
    }

    func testNineKeyCandidateRowsAreExcludedToo() {
        let keyboard = [[piece("ABC", 0.65), piece("DEF", 0.65)],
                        [piece("GHI", 0.73), piece("JKL", 0.73)], [piece("WXYZ", 0.8)]]
        let suggestions = [[piece("你好", 0.6), piece("我", 0.6)]]
        XCTAssertEqual(CandidatePicker.shows("你好", rows: suggestions + keyboard), 0)
        XCTAssertEqual(CandidatePicker.shows("你好", rows: [[piece("你好", 0.48)]] + suggestions + keyboard), 1)
    }

    func testVerifiedPinyinIsKeptWithoutClearingOrSwitchingApps() async throws {
        let screen = FakeScreen(); screen.frame = Self.screen(input: "", candidate: "你好")
        let phone = InputGestures(screen: screen, typed: Self.screen(input: "你好", candidate: "我"))
        let actor = FakeModel { _ in "DO: type 你好" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.fastText = true
        var pasteCalls = 0
        agent.pasteHop = { _ in pasteCalls += 1; return .lost }
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["type"], "a verified greeting must not be deleted")
        XCTAssertEqual(pasteCalls, 0, "successful Pinyin needs no app switch")
        XCTAssertEqual(agent.pinyinMisses, 0)
    }

    func testUncertainPinyinIsLeftForInspectionWithoutDeletingOrPasting() async throws {
        let screen = FakeScreen(); screen.frame = Self.screen(input: "", candidate: "我")
        // An unreadable or partial frame is uncertainty, not evidence that the field needs replacing.
        let phone = InputGestures(screen: screen, typed: Self.screen(input: "", candidate: "我"))
        let actor = FakeModel { _ in "DO: type 你好\nDO: key enter\nDO: home" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.fastText = true
        var pasteCalls = 0
        agent.pasteHop = { _ in pasteCalls += 1; return .lost }
        _ = try await agent.step()
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["type"])
        XCTAssertEqual(pasteCalls, 0)
        XCTAssertTrue(agent.steps.contains { $0["action"] == .str("compose") })
        XCTAssertEqual(agent.steps.last?["action"], .str("blocked"))
        XCTAssertTrue(agent.steps.last?["reason"]?.str?.contains("Do not clear") == true)
    }

    func testUncertainPasteIsNotDeletedAndRetyped() async throws {
        let screen = FakeScreen(); screen.frame = Self.screen(input: "", candidate: "我")
        let phone = InputGestures(screen: screen, typed: Self.screen(input: "", candidate: "我"))
        let actor = FakeModel { _ in "DO: type 你好" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.fastText = true; agent.pinyinMisses = 2
        agent.pasteHop = { _ in .filled }
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["cmd+v"])
        XCTAssertEqual(agent.steps.last?["action"], .str("compose"))
    }

    func testQuickSendHandoffCanSendExistingTextWithoutRetypingIt() async {
        let actor = FakeModel { n in
            if n == 1 { return "DO: type 你好" }
            return n == 2 ? "DO: key enter" : "DO: done New requested message is visible"
        }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.inputToInspect = "你好"; agent.directStart = true; agent.endAfterSend = 5
        await agent.run()
        XCTAssertEqual(phone.calls, ["key"])
        XCTAssertEqual(agent.sent, ["你好"])
        XCTAssertEqual(agent.steps.last?["action"], .str("done"))
        XCTAssertTrue(agent.steps.contains { $0["action"] == .str("blocked") })
    }

    func testInspectionAllowsAnExplicitCorrectionBeforeTypingAgain() async {
        let actor = FakeModel { n in
            n == 1 ? "DO: key cmd+a\nDO: type 你好\nDO: key enter" : "DO: done Corrected message is visible"
        }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.inputToInspect = "你好"; agent.directStart = true; agent.endAfterSend = 5
        await agent.run()
        XCTAssertEqual(phone.calls, ["key", "type", "key"])
        XCTAssertEqual(agent.steps.last?["action"], .str("done"))
    }

    static func screen(input: String, candidate: String) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            for (text, y) in [("ASSISTANT", 170.0), (input, 750.0), (candidate + "  好  我", 940.0),
                              ("q w e r t y u i o p", 1020.0), ("a s d f g h j k l", 1130.0),
                              ("z x c v b n m", 1250.0), ("123       拼", 1350.0)] {
                (text as NSString).draw(at: CGPoint(x: 45, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white])
            }
        }.jpegData(compressionQuality: 0.9)!
    }
}

@MainActor private final class InputGestures: Gestures {
    let device: HIDDevice = FakeDevice()
    let screen: FakeScreen
    let typed: Data
    var calls: [String] = []
    init(screen: FakeScreen, typed: Data) { self.screen = screen; self.typed = typed }
    func type(_ text: String) async throws { calls.append("type"); screen.frame = typed }
    func key(_ combo: String) async throws { calls.append(combo) }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { calls.append("tap") }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws { calls.append("swipe") }
    func drag(_ points: [CGPoint], hold: Bool) async throws { calls.append("drag") }
    func goHome() async throws { calls.append("home") }
    func goBack() async throws { calls.append("back") }
    func reset() async throws { calls.append("reset") }
}
