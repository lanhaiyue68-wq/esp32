import UIKit
import XCTest
@testable import IPhoneAgent

@MainActor final class Logs36RegressionTests: XCTestCase {
    // A blinking insertion caret was identified as the mouse in logs36. A single disappearing shape
    // cannot establish movement, even when it is compact and close to the requested target.
    func testBlinkingCaretCannotMoveTheMouseCalibration() {
        func frame(caret: Bool) -> Data {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 592, height: 1280), format: format).image { ctx in
                UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 592, height: 1280))
                if caret {
                    UIColor.white.setFill(); ctx.fill(CGRect(x: 86, y: 600, width: 3, height: 40))
                }
            }.jpegData(compressionQuality: 0.9)!
        }
        XCTAssertNil(Vision.pointer(frame(caret: true), frame(caret: false),
                                    near: CGPoint(x: 0.5, y: 0.5), shift: -12.0 / 281,
                                    reach: CGPoint(x: 0.5, y: 0.5)))
    }

    func testDisappearingPointerWithoutALandingCannotConfirmANudge() {
        let vision = VisionTests()
        XCTAssertNil(Vision.pointer(vision.screen(pointer: (262, 856)), vision.screen(),
                                    near: CGPoint(x: 0.5, y: 0.8), shift: 12.0 / 498))
    }

    func testFullKeyboardSurvivesOneMissedLetterInOCR() {
        let labels = Array("qwertyuop") // Vision missed the i key; the remaining keys are still ordered.
        let row = labels.enumerated().map { index, letter in
            CandidatePicker.Piece(text: String(letter),
                                  box: CGRect(x: 0.02 + Double(index) * 0.1, y: 0.68, width: 0.04, height: 0.025))
        }
        XCTAssertTrue(CandidatePicker.keyboardUp(rows: [row]))
        XCTAssertEqual(CandidatePicker.shows("你好", rows: [
            [.init(text: "你好", box: CGRect(x: 0.04, y: 0.48, width: 0.1, height: 0.03))],
            [.init(text: "你好", box: CGRect(x: 0.04, y: 0.6, width: 0.1, height: 0.03))], row]), 1,
            "a suggestion must not be counted when a key was missed")
    }

    func testAnExtraLetterIsNotVerifiedAsTheRequestedText() {
        XCTAssertEqual(CandidatePicker.shows("你好", lines: ["你好p"]), 0)
        XCTAssertEqual(CandidatePicker.shows("hello", lines: ["hellop"]), 0)
        XCTAssertEqual(CandidatePicker.shows("你好", lines: ["你好"]), 1)
    }

    func testARealLeftwardMouseNudgeIsStillFound() throws {
        let vision = VisionTests()
        let point = try XCTUnwrap(Vision.pointer(vision.screen(pointer: (274, 856)), vision.screen(pointer: (262, 856)),
                                                near: CGPoint(x: 0.5, y: 0.8), shift: -12.0 / 498))
        XCTAssertEqual(point.x * 498, 274, accuracy: 3)
        XCTAssertEqual(point.y * 1080, 856, accuracy: 3)
    }

    func testANewMatchingBubbleKeepsDuplicateSendProtection() {
        let before = InputFieldVerificationTests.screen(input: "hello", candidate: "我")
        let draft = InputFieldVerificationTests.screen(input: "hellop", candidate: "我")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let after = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { _ in
            UIImage(data: draft)!.draw(in: CGRect(x: 0, y: 0, width: 720, height: 1560))
            ("hello" as NSString).draw(at: CGPoint(x: 450, y: 550),
                withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white])
        }.jpegData(compressionQuality: 0.9)!
        XCTAssertNil(CandidatePicker.mistypedDraft("hello", before: before, after: after))
    }

    func testUnchangedOrUnreadableDraftDoesNotAuthorizeAnotherSend() {
        let frame = InputFieldVerificationTests.screen(input: "hello", candidate: "我")
        XCTAssertNil(CandidatePicker.mistypedDraft("hello", before: frame, after: frame))
        XCTAssertNil(CandidatePicker.mistypedDraft("hello", before: frame, after: Data([0])))
    }

    func testAMessageStillAwaitingSendCannotBeClaimedAsComplete() async throws {
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: done Sent hello" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 2
        _ = try await agent.step()
        let ended = try await agent.step()
        XCTAssertFalse(ended)
        XCTAssertEqual(agent.steps.last?["action"], .str("done rejected"))
    }

    func testLongChineseReportUsesExactPasteBeforeHomophonePronePinyin() async throws {
        let text = "已尝试发送你好，但未能确认任务完成，请先查看目标应用里的结果。"
        let screen = FakeScreen(); screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs36Gestures()
        phone.onKey = { combo in
            if combo == "cmd+v" { screen.frame = InputFieldVerificationTests.screen(input: text, candidate: "我") }
        }
        let actor = FakeModel { _ in "DO: type \(text)" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.fastText = true
        var pasted: [String] = []
        agent.pasteHop = { text in pasted.append(text); return .filled }
        _ = try await agent.step()
        XCTAssertEqual(pasted, [text])
        XCTAssertEqual(phone.calls, ["key cmd+v"], "the first pinyin candidate can turn 已尝试 into 宜昌市")
    }

    func testMisplacedSendThatAddsALetterCanBeCorrectedBeforeSendingAgain() async throws {
        let screen = FakeScreen(); screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs36Gestures()
        phone.onType = { _ in screen.frame = InputFieldVerificationTests.screen(input: "hello", candidate: "我") }
        var taps = 0
        phone.onTap = {
            taps += 1
            screen.frame = InputFieldVerificationTests.screen(input: taps == 1 ? "hellop" : "", candidate: "我")
        }
        phone.onKey = { combo in
            if combo == "backspace" { screen.frame = InputFieldVerificationTests.screen(input: "hello", candidate: "我") }
        }
        let replies = ["DO: type hello", "DO: tap 907 543", "DO: key backspace", "DO: tap 907 543"]
        let actor = FakeModel { n in replies[min(n, replies.count) - 1] }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 2
        for _ in replies { _ = try await agent.step() }
        XCTAssertEqual(phone.calls, ["type hello", "tap", "key backspace", "tap"])
        XCTAssertEqual(agent.sent, ["hello"], "the first misplaced click must not count as a successful send")
    }
}

@MainActor private final class Logs36Gestures: Gestures {
    let device: HIDDevice = FakeDevice()
    var calls: [String] = []
    var onType: ((String) -> Void)?
    var onKey: ((String) -> Void)?
    var onTap: (() -> Void)?
    func type(_ text: String) async throws { calls.append("type " + text); onType?(text) }
    func key(_ combo: String) async throws { calls.append("key " + combo); onKey?(combo) }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { calls.append("tap"); onTap?() }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func goHome() async throws { calls.append("home") }
    func goBack() async throws {}
    func reset() async throws {}
}
