import XCTest
import UIKit
@testable import IPhoneAgent

/// logs27: the tap on 测试群's input box landed above it; no keyboard came up, and "nihaoya" was typed seven times
/// into nothing. Underneath, calibration learned a probe that had stopped at the screen edge (x 0.998), which broke
/// the x correction: every check landed 4% right.
@MainActor final class TapAccuracyTests: XCTestCase {
    private func frame(keyboard: Bool, extra: String? = nil) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            func draw(_ text: String, x: CGFloat, y: CGFloat) {
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.white])
            }
            draw("测试群", x: 290, y: 110)
            if let extra { draw(extra, x: 120, y: 700) }  // the typed text, in the box or a bubble
            if keyboard {
                for (i, k) in ["ABC", "DEF", "GHI"].enumerated() { draw(k, x: CGFloat(150 + i * 180), y: 1100) }
                draw("空格", x: 330, y: 1350); draw("发送", x: 600, y: 1350)
            }
        }.jpegData(compressionQuality: 0.9)!
    }

    func testTypingWithoutAKeyboardIsRefusedAndTheNextTapAims() async throws {
        let screen = FakeScreen(); screen.frame = frame(keyboard: false)
        let keyboardFrame = frame(keyboard: true)
        let phone = AimGestures(); phone.onTap = { screen.frame = keyboardFrame }
        let actor = FakeModel { n in
            n <= 3 ? ["THINK: The box is focused.\nDO: type hello", "THINK: Tap the box.\nDO: tap 450 925",
                      "THINK: Keyboard up.\nDO: type hello"][n - 1] : "THINK: Typed.\nDO: done ok"
        }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: FakeModel { _ in "1. Type it" }, trace: nil)
        agent.directStart = true
        agent.keyboardGuard = true
        let ended = expectation(description: "agent completed")
        agent.onFinish = { ended.fulfill() }
        try agent.start("在测试群输入 hello")
        await fulfillment(of: [ended], timeout: 15)
        agent.stop()
        XCTAssertEqual(agent.steps.filter { $0["action"] == .str("blocked") }.count, 1)
        XCTAssertEqual(phone.aims, [true], "the tap after a refused type finds the pointer first")
        XCTAssertEqual(phone.typed, 1)
    }

    /// logs28: the phone task sent "你好" to 测试群 with 发送, typed it again, sent it again, and was typing a third time.
    func testTextAlreadySentInThisRunIsNotTypedAgain() async throws {
        let screen = FakeScreen(); screen.frame = frame(keyboard: true)
        let phone = AimGestures()
        let replies = ["THINK: Type.\nDO: type hello", "THINK: Send.\nDO: tap 900 845", "THINK: Type it.\nDO: type \"hello\"",
                       "THINK: It shows.\nDO: done sent"]
        let actor = FakeModel { n in replies[min(n, replies.count) - 1] }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: FakeModel { _ in "1. Send it" }, trace: nil)
        agent.directStart = true
        agent.keyboardGuard = true
        let ended = expectation(description: "agent completed")
        agent.onFinish = { ended.fulfill() }
        try agent.start("给测试群发你好")
        await fulfillment(of: [ended], timeout: 15)
        agent.stop()
        XCTAssertEqual(phone.typed, 1)
        XCTAssertTrue(agent.steps.contains { $0["reason"] == .str(AgentLoop.sentAgainReason) })
        XCTAssertEqual(AgentLoop.typedKey(" “你好” "), "你好")
    }

    /// 60 on the PC harness: the model sent with WeChat's green 发送 beside the box (y ~0.49, missed by the tap
    /// check), typed the same text again, and left it in the box. Once the text shows more often than when it was
    /// first typed, typing it again is refused.
    func testTextAlreadyOnScreenSinceItWasTypedIsNotTypedAgain() async throws {
        let screen = FakeScreen(); screen.frame = frame(keyboard: true)
        let shown = frame(keyboard: true, extra: "hello world")
        let phone = AimGestures(); phone.onType = { screen.frame = shown }
        let replies = ["THINK: Type.\nDO: type hello world", "THINK: Send it.\nDO: tap 900 300",
                       "THINK: Type it.\nDO: type hello world", "THINK: It shows.\nDO: done sent"]
        let actor = FakeModel { n in replies[min(n, replies.count) - 1] }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: FakeModel { _ in "1. Send it" }, trace: nil)
        agent.directStart = true
        agent.keyboardGuard = true
        let ended = expectation(description: "agent completed")
        agent.onFinish = { ended.fulfill() }
        try agent.start("给测试群发 hello world")
        await fulfillment(of: [ended], timeout: 15)
        agent.stop()
        XCTAssertEqual(phone.typed, 1)
        XCTAssertTrue(agent.steps.contains { $0["reason"] == .str(AgentLoop.sentAgainReason) })
    }

    func testAProbeStoppedAtTheEdgeIsNotLearned() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let pointer = Pointer(device: FakeDevice(), calibrationFile: file)
        // logs27's probes: x = 0.00341·u + 0.038; probe 2 stopped at the right edge
        let samples: [(ux: Double, uy: Double, fx: Double, fy: Double)] = [
            (150, 150, 0.545, 0.254), (350, 350, 0.998, 0.594), (69, 148, 0.278, 0.250), (206, 148, 0.740, 0.257),
            (138, 295, 0.517, 0.479), (69, 442, 0.268, 0.704), (206, 442, 0.742, 0.716)]
        pointer.applyProbe(x: .init(a: 0.00341, b: 0.038, rms: 0.005), y: .init(a: 0.00157, b: 0.021, rms: 0.01), samples: samples)
        let aimed = pointer.fix(0.5, "x")
        let units = (aimed * Double(pointer.span!.w)).rounded()
        XCTAssertEqual(0.00341 * units + 0.038, 0.5, accuracy: 0.008, "logs27 landed 0.540 for 0.5")
    }
}

@MainActor private final class AimGestures: Gestures {
    let device: HIDDevice = FakeDevice()
    var aims: [Bool] = [], typed = 0
    var onTap: (() -> Void)?
    var onType: (() -> Void)?
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { aims.append(aim); onTap?() }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func type(_ text: String) async throws { typed += 1; onType?() }
    func key(_ combo: String) async throws {}
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
