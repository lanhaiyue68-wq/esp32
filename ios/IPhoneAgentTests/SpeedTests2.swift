import UIKit
import XCTest
@testable import IPhoneAgent

/// logs 11-06 (build89): the same task twice was barely faster. A blinking text cursor kept the screen "moving", so
/// every action waited the full 2 s and dropped plans as stale; the 8-character acknowledgement went through the paste
/// hop every time.
@MainActor final class CursorAndAcknowledgementSpeedTests: XCTestCase {
    func testABlinkingCursorIsNotAVisibleChangeForSettling() throws {
        let a = try XCTUnwrap(VideoFeed.look(Self.chat(caret: false)))
        let b = try XCTUnwrap(VideoFeed.look(Self.chat(caret: true)))
        XCTAssertFalse(VideoFeed.visiblyChanged(a, b))
    }

    func testATypedCharacterOrANewScreenIsAVisibleChange() throws {
        let before = try XCTUnwrap(VideoFeed.look(Self.chat(caret: true)))
        XCTAssertTrue(VideoFeed.visiblyChanged(before, try XCTUnwrap(VideoFeed.look(Self.chat(caret: true, typed: "好")))))
        XCTAssertTrue(VideoFeed.visiblyChanged(before, try XCTUnwrap(VideoFeed.look(Self.chat(caret: false, sheet: true)))))
    }

    func testTheStatusBarClockIsNotAVisibleChange() throws {
        let a = try XCTUnwrap(VideoFeed.look(Self.chat(caret: false, clock: "21:09")))
        let b = try XCTUnwrap(VideoFeed.look(Self.chat(caret: false, clock: "21:10")))
        XCTAssertFalse(VideoFeed.visiblyChanged(a, b))
    }

    func testAPlanIsNotStaleBecauseTheCursorBlinked() {
        let off = Self.chat(caret: false), on = Self.chat(caret: true)
        XCTAssertFalse(Vision.changed(off, on, caret: true), "the stale check ignores a cursor blink")
        XCTAssertTrue(Vision.changed(off, on), "an action's own result still counts a cursor that appeared")
        XCTAssertTrue(Vision.changed(off, Self.chat(caret: false, typed: "好"), caret: true))
    }

    func testTheTaskAcknowledgementIsTypedNotPasted() {
        XCTAssertFalse(Pasteboard.prefersExact(WatchSettings.taskAcknowledgement), "typed as pinyin, no paste hop")
        XCTAssertTrue(Pasteboard.prefersExact("收到，我去处理。"), "the old one always needed the hop")
    }

    /// A dark chat with an input box; optionally the cursor, a typed character, a sheet over the bottom half.
    static func chat(caret: Bool, typed: String = "", sheet: Bool = false, clock: String = "21:09") -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: 1170, height: 2532)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.07, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let white: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor(white: 0.9, alpha: 1)]
            (clock as NSString).draw(at: CGPoint(x: 110, y: 40), withAttributes: white)
            ("主人蓝海乐" as NSString).draw(at: CGPoint(x: 420, y: 170), withAttributes: white)
            ("9527 你现在去 claude 给他发一句你好" as NSString).draw(at: CGPoint(x: 120, y: 600), withAttributes: white)
            UIColor(white: 0.17, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 120, y: 1060, width: 760, height: 110), cornerRadius: 20).fill()
            if !typed.isEmpty { (typed as NSString).draw(at: CGPoint(x: 150, y: 1078), withAttributes: white) }
            if caret {
                UIColor(red: 0.2, green: 0.75, blue: 0.4, alpha: 1).setFill()
                ctx.fill(CGRect(x: typed.isEmpty ? 150 : 220, y: 1085, width: 4, height: 60))
            }
            if sheet {
                UIColor(white: 0.25, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 1250, width: 1170, height: 1282))
            }
        }.jpegData(compressionQuality: 0.8)!
    }
}

/// User 11-08: no special cases for test tasks. The alarm's wheel guard (matched on words in the model's thought)
/// is gone; swipes go through as the model asks, and a part that stalls goes to the planner.
@MainActor final class WheelGuardTests: XCTestCase {
    func testAWheelSwipeGoesThroughLikeAnyOther() async throws {
        let (agent, phone) = run("THINK: 小时滚轮当前显示9，我向上滑动滚轮把它调到8。\nDO: swipe 300 600 300 540")
        _ = try await agent.step(); _ = try await agent.step()
        XCTAssertEqual(phone.swipes, 2)
    }

    func testScrollingAListIsNotAWheel() async throws {
        let (agent, phone) = run("THINK: 列表里还没看到测试群，继续向上滑动列表。\nDO: swipe 500 700 500 400")
        _ = try await agent.step(); _ = try await agent.step()
        XCTAssertEqual(phone.swipes, 2)
    }

    private func run(_ reply: String) -> (AgentLoop, WheelPhone) {
        let screen = FakeScreen()
        screen.frame = CursorAndAcknowledgementSpeedTests.chat(caret: false)
        let phone = WheelPhone(screen: screen)
        let actor = FakeModel { _ in reply }
        return (AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil), phone)
    }
}

@MainActor private final class WheelPhone: Gestures {
    let device: HIDDevice = FakeDevice()
    let screen: FakeScreen
    var swipes = 0
    init(screen: FakeScreen) { self.screen = screen }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws {}
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {
        swipes += 1  // the wheel turns: the screen changes
        screen.frame = CursorAndAcknowledgementSpeedTests.chat(caret: false, sheet: swipes % 2 == 1)
    }
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func type(_ text: String) async throws {}
    func key(_ combo: String) async throws {}
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
