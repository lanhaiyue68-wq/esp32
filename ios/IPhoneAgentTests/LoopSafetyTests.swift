import UIKit
import XCTest
@testable import IPhoneAgent

/// logs(32): stale-screen events hid an unchanged Home action; after sending, the actor kept moving and sent again.
@MainActor final class LoopSafetyTests: XCTestCase {
    private func frame(_ color: UIColor) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 520), format: format).image { ctx in
            color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 520))
        }.jpegData(compressionQuality: 0.9)!
    }

    func testHomeDoesNotDiscardItsPlanWhenAnAnimationChangesTheScreen() async throws {
        let screen = FakeScreen(); screen.frame = frame(.black)
        let changed = frame(.white), phone = FakeGestures()
        let actor = FakeModel { _ in screen.frame = changed; return "DO: home" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["home"])
        XCTAssertFalse(agent.steps.contains { $0["action"] == .str("stale plan") })
    }

    func testReplanningAllowsOnlyOneKeyboardFallbackForAnUnchangedHome() async throws {
        let actor = FakeModel { _ in "DO: home" }, planner = FakeModel { _ in "1. Take another route" }
        let phone = FakeGestures()
        let screen = FakeScreen(); screen.frame = frame(.black)
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: planner, trace: nil)
        agent.steps = [["action": .str("home"), "changed": .bool(false)],
                       ["action": .str("stale plan"), "reason": .str("screen changed")],
                       ["action": .str("replan (stuck)"), "plan": .str("Try Home again")]]
        let first = try await agent.step(), second = try await agent.step()
        XCTAssertFalse(first, "first repeated Home tries the keyboard alternative")
        XCTAssertTrue(second, "insisting after the keyboard fallback failed ends with a clear failure")
        XCTAssertEqual(phone.calls, ["key"], "the original Home flick is never dispatched again")
        XCTAssertEqual(agent.steps.last?["action"], .str("fail"))
        XCTAssertTrue(agent.steps.last?["reason"]?.str?.contains("Home changed nothing") == true)
    }

    func testAnUnchangedTapStillGetsOnlyItsPrecisionRetryAfterReplanning() async throws {
        let actor = FakeModel { _ in "DO: tap 350 900" }
        let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.steps = [["action": .str("tap"), "x": .int(350), "y": .int(900), "changed": .bool(false)],
                       ["action": .str("replan (stuck)"), "plan": .str("Try again")]]
        let acts = try await agent.nextActions()
        XCTAssertEqual(acts.first?.act["precise"], .bool(true))
    }

    func testSingleMessageSendDropsTheRestOfItsBatchAndOnlyVerifiesAfterwards() async {
        let actor = FakeModel { n in
            if n == 1 { return "DO: type hello\nDO: key enter\nDO: home" }
            return n == 2 ? "DO: type hello" : "DO: done The new hello bubble is visible in the requested chat"
        }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor,
                              planner: FakeModel { _ in "1. Send hello" }, trace: nil)
        agent.directStart = true; agent.endAfterSend = 5
        await agent.run()
        XCTAssertEqual(phone.calls, ["type", "key"], "neither the batched Home nor a repeated type is dispatched")
        XCTAssertEqual(agent.steps.last?["action"], .str("done"))
        XCTAssertTrue(agent.steps.contains { $0["action"] == .str("send verification") })
        XCTAssertTrue(actor.prompts.last?.contains("Do not send it again") == true)
    }

    func testUnverifiedSendFailsWithinItsExistingObservationBudget() async {
        let actor = FakeModel { n in n == 1 ? "DO: type hello\nDO: key enter" : "DO: wait" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor,
                              planner: FakeModel { _ in "1. Send hello" }, trace: nil)
        agent.directStart = true; agent.endAfterSend = 2
        await agent.run()
        XCTAssertEqual(phone.calls, ["type", "key"])
        XCTAssertEqual(agent.steps.last?["action"], .str("fail"))
        XCTAssertTrue(agent.steps.last?["reason"]?.str?.contains("could not verify") == true)
        XCTAssertFalse(agent.steps.contains { $0["action"] == .str("done") })
    }

    func testARejectedSendCommandIsNeverRecordedAsSent() async throws {
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: key enter" }
        let phone = RejectingSendGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        do { _ = try await agent.step(); XCTFail("the keyboard command must fail") } catch {}
        XCTAssertTrue(agent.sent.isEmpty)
    }

    func testALostPasteTargetStopsBeforeAnyTextOrSendCanReachAnotherApp() async throws {
        let actor = FakeModel { _ in "DO: type 你好" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.fastText = true; agent.pinyinMisses = 2
        agent.pasteHop = { _ in .lost }
        do {
            _ = try await agent.step()
            XCTFail("an unknown paste destination must stop the run")
        } catch is BlindError {
            // A normal DeviceError would be replanned and could continue sending in the wrong app.
        } catch {
            XCTFail("the lost target must stop as a screen-safety error, got \(error)")
        }
        XCTAssertTrue(phone.calls.isEmpty)
        XCTAssertTrue(agent.sent.isEmpty)
    }
}

@MainActor private final class RejectingSendGestures: Gestures {
    let device: HIDDevice = FakeDevice()
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws {}
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func type(_ text: String) async throws {}
    func key(_ combo: String) async throws { throw DeviceError(message: "keyboard command rejected") }
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
