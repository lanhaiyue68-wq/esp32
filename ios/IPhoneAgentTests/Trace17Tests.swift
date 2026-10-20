import XCTest
@testable import IPhoneAgent

/// Regression fixtures from traces(17): valid repeated taps were called parse errors,
/// and six undo taps or tap-then-draw ran without observing the first tap's result.
@MainActor final class Trace17Tests: XCTestCase {
    func testOneMissedTapGetsOnePrecisionRetryWithoutThreeModelRequests() async throws {
        let actor = FakeModel { _ in "THINK: The pen is visible.\nDO: tap 345 935" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.steps = [["action": .str("tap"), "x": .int(345), "y": .int(935), "changed": .bool(false)]]
        let next = try await agent.nextActions()
        XCTAssertEqual(next[0].act["action"], .str("tap"))
        XCTAssertEqual(next[0].act["precise"], .bool(true))
        XCTAssertEqual(actor.prompts.count, 1)
    }

    func testUnchangedPrecisionTapReplansInsteadOfLoopingOrCallingItBadSyntax() async throws {
        let actor = FakeModel { _ in "THINK: The pen is visible.\nDO: tap 345 935" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.steps = [["action": .str("tap"), "x": .int(345), "y": .int(935),
                        "precise": .bool(true), "changed": .bool(false)]]
        let next = try await agent.nextActions()
        XCTAssertEqual(next[0].act["action"], .str("replan"))
        XCTAssertTrue(next[0].act["reason"]?.str?.contains("unchanged") == true)
        XCTAssertEqual(actor.prompts.count, 1)
    }

    func testSixUndoTapsStopAfterTheFirstForScreenInspection() async throws {
        let actor = FakeModel { _ in (0..<6).map { _ in "DO: tap 458 88" }.joined(separator: "\n") }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["tap"])
    }

    func testToolTapDoesNotImmediatelyDrawOnAnUnverifiedScreen() async throws {
        let actor = FakeModel { _ in "DO: tap 345 935\nDO: circle 500 450 150" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["tap"])
    }

    func testIndependentDrawingStrokesCanStillRunAsOneBatch() async throws {
        let actor = FakeModel { _ in "DO: circle 448 405 25\nDO: circle 552 405 25" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["drag", "drag"])
    }

    func testInspectDrawingBeforeAnyLaterUiTap() async throws {
        let actor = FakeModel { _ in "DO: circle 500 450 150\nDO: tap 897 88" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["drag"])
    }

    func testRecoveryRecognizesTheSameTargetAcrossPrecisionModes() {
        let plain: JObject = ["action": .str("tap"), "x": .int(345), "y": .int(935)]
        XCTAssertTrue(Actions.sameTarget(plain, plain.merging(["precise": .bool(true)])))
        XCTAssertFalse(Actions.sameTarget(plain, ["action": .str("tap"), "x": .int(346), "y": .int(935)]))
    }

    func testDrawingCannotDeclareCompletionBeforeInspectingItsResult() async throws {
        let actor = FakeModel { _ in "DO: circle 500 450 150\nDO: done" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        let finished = try await agent.step()
        XCTAssertFalse(finished)
        XCTAssertEqual(phone.calls, ["drag"])
        XCTAssertEqual(agent.steps.last?["action"], .str("circle"))
    }
}
