import XCTest
@testable import IPhoneAgent

@MainActor final class Trace18Tests: XCTestCase {
    func testCircleBoundsUseTheActualPortraitAspect() throws {
        let act: JObject = ["action": .str("circle"), "x": .int(500), "y": .int(450), "r": .int(180)]
        let bounds = try XCTUnwrap(Actions.drawingBounds(act, aspect: 6.0 / 13))
        XCTAssertEqual(bounds.minX, 320, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 680, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 533.076923, accuracy: 0.001)
        XCTAssertFalse(bounds.contains(CGPoint(x: 500, y: 558))) // trace18's mouth is outside even with perfect HID
    }

    func testFirstStrokeIsObservedBeforeMorePartsAreDrawn() async throws {
        let actor = FakeModel { _ in "DO: circle 500 450 180\nDO: circle 437 396 25\nDO: circle 563 396 25" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["drag"])
        XCTAssertEqual(agent.steps.count, 1)
    }

    func testPrecisionRetryActuallyExecutesAfterTwoUnchangedPlainTaps() async throws {
        let actor = FakeModel { _ in "DO: tap 345 935" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        let plain: JObject = ["action": .str("tap"), "x": .int(345), "y": .int(935), "changed": .bool(false), "act_s": .num(0.5)]
        agent.steps = [plain, plain]
        _ = try await agent.step()
        XCTAssertEqual(phone.calls, ["tap"])
        XCTAssertEqual(agent.steps.last?["precise"], .bool(true))
        XCTAssertNotNil(agent.steps.last?["act_s"])
    }

    func testMemoryExpiresAndCanBeDisabled() {
        var date = Date()
        let store = ExperienceStore(file: nil, clock: { date })
        let scene = Array(repeating: UInt8(12), count: 64)
        store.review(id: "a", goal: "open settings", scene: scene, aspect: 0.46,
                     action: ["action": .str("tap"), "x": .int(100), "y": .int(200)], verdict: true, correction: nil)
        store.enabled = false
        XCTAssertTrue(store.recall(goal: "open settings", scene: scene, aspect: 0.46).isEmpty)
        store.enabled = true
        XCTAssertEqual(store.recall(goal: "open settings", scene: scene, aspect: 0.46).count, 1)
        date = date.addingTimeInterval(31 * 86400)
        XCTAssertTrue(store.recall(goal: "open settings", scene: scene, aspect: 0.46).isEmpty)
    }

    func testMemoryIsBoundedAcrossManyFeedbackEvents() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExperienceStore(file: file)
        for i in 0..<140 {
            store.review(id: String(i), goal: "open settings", scene: Array(repeating: UInt8(12), count: 64), aspect: 0.46,
                         action: ["action": .str("tap"), "x": .int(i), "y": .int(200)], verdict: false, correction: nil)
        }
        XCTAssertLessThanOrEqual(store.count, 128)
        XCTAssertLessThanOrEqual(try Data(contentsOf: file).count, 256_000)
        XCTAssertEqual(ExperienceStore(file: file).count, store.count)
    }
}
