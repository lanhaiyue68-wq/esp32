import XCTest
@testable import IPhoneAgent

@MainActor final class SpeedTests: XCTestCase {
    private func finish(_ agent: AgentLoop, task: String = "打开备忘录") async throws {
        let ended = expectation(description: "agent completed")
        agent.onFinish = { ended.fulfill() }
        try agent.start(task)
        await fulfillment(of: [ended], timeout: 5)
        agent.stop()
    }

    func testDirectStartActsOnTheCurrentGoalWithoutAnInitialPlannerRound() async throws {
        let actor = FakeModel { n in n == 1 ? "THINK: Open Notes.\nDO: tap 100 200" : "THINK: Notes is open.\nDO: done opened" }
        let planner = FakeModel { _ in "1. Open Notes" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.directStart = true
        try await finish(agent)
        XCTAssertEqual(phone.calls, ["tap"])
        XCTAssertEqual(agent.steps.last?["action"], .str("done"))
        XCTAssertEqual(planner.prompts.count, 0, "A second model round before the first move adds no action")
        XCTAssertTrue(actor.prompts.first?.contains("打开备忘录") == true)
    }

    func testDirectStartStillUsesThePlannerWhenTheActorRequestsRecovery() async throws {
        let actor = FakeModel { n in n == 1 ? "THINK: Need another route.\nDO: replan" : "THINK: The goal is visible.\nDO: done opened" }
        let planner = FakeModel { _ in "1. Resume from the current screen" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.directStart = true
        try await finish(agent)
        // User 11-08: Codex then drives; a reply of its with no action hands the step back to the executor.
        XCTAssertEqual(planner.prompts.count, 2)
        XCTAssertTrue(planner.prompts.first?.contains("got stuck") == true)
        XCTAssertEqual(agent.steps.last?["action"], .str("done"))
    }

    func testOrdinaryTasksKeepThePlannerAndFixedPlansTakePrecedence() async throws {
        for fixed in [false, true] {
            let actor = FakeModel { _ in "THINK: The destination is visible.\nDO: done opened" }
            let planner = FakeModel { _ in "1. Open Notes" }
            let agent = AgentLoop(phone: nil, screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
            agent.directStart = fixed
            agent.presetPlan = fixed ? "Verify the target title before finishing." : ""
            try await finish(agent)
            XCTAssertEqual(planner.prompts.count, fixed ? 0 : 1)
            if fixed { XCTAssertTrue(actor.prompts.first?.contains("Verify the target title") == true) }
        }
    }

    func testDirectStartDoesNotBypassTheOutgoingTextGuard() async throws {
        let actor = FakeModel { n in n == 1 ? "THINK: Type.\nDO: type private value" : "THINK: Text refused.\nDO: fail blocked" }
        let planner = FakeModel { _ in "1. Type the reply" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.directStart = true
        agent.outgoingGuard = { _ in "protected" }
        try await finish(agent, task: "输入回复")
        XCTAssertTrue(phone.calls.isEmpty)
        XCTAssertTrue(agent.steps.contains { $0["action"] == .str("blocked") })
    }

    func testStoppingAtTheFrameGatePreventsDirectStartInput() async throws {
        let actor = FakeModel { _ in "THINK: Tap.\nDO: tap 100 200" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.directStart = true
        agent.gate = { throw CancellationError() }
        try await finish(agent)
        XCTAssertTrue(phone.calls.isEmpty)
        XCTAssertTrue(actor.prompts.isEmpty)
        XCTAssertEqual(agent.steps.last?["action"], .str("stopped"))
    }

    private func quietFeed() async throws -> (VideoFeed, SpeedDevice) {
        let device = SpeedDevice(), feed = VideoFeed()
        feed.device = device; feed.mirroring = true
        feed.status(BoardStatus(up: 1000, video_ms: 1000))
        // Synthetic black 64x128 H264 frame, generated locally; no phone screenshot or private content.
        let intra = try XCTUnwrap(Data(base64Encoded: "AAAAAWdCwAraEEbARAAAAwAEAAADAAo8SJqAAAAAAWjOD8gAAAABZYiEOiYoAAkCycnJ1111111111114AAAAAFlCIiEOiYoAAkCycnJ1111111111114A=="))
        let flags: VideoAssembler.Flags = [.start, .end, .idr]
        var packet = Data([0, 0, flags.rawValue, 0xe8, 3, 0, 0]); packet.append(intra)
        feed.receive(packet)
        let deadline = now() + 3
        while feed.frame == nil && now() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotNil(feed.frame, "The real VideoToolbox decoder must publish the synthetic frame")
        try await feed.stream(true)
        // AirPlay emits no more pixels on a quiet screen; the last heartbeat has now aged past the boundary.
        try await Task.sleep(nanoseconds: 1_100_000_000)
        return (feed, device)
    }

    func testCurrentFrameReturnsWhenAHeartbeatVerifiesAnUnchangedDecodedImage() async throws {
        let (feed, device) = try await quietFeed()
        let confirmation = Task { @MainActor in
            try await Task.sleep(nanoseconds: 100_000_000)
            feed.status(BoardStatus(up: 2200, video_ms: 1000))
        }
        defer { confirmation.cancel() }
        let began = now()
        _ = try await feed.currentFrame(wait: 1.5)
        XCTAssertLessThan(now() - began, 0.9, "A verified unchanged screen must not wait for pixels AirPlay will never resend")
        XCTAssertEqual(device.sent, ["stream on"])
    }

    func testAfterActionUsesPostActionHeartbeatWithoutTheFullNewFrameTimeout() async throws {
        let (feed, device) = try await quietFeed()
        let began = now()
        let confirmation = Task { @MainActor in
            try await Task.sleep(nanoseconds: 100_000_000)
            feed.status(BoardStatus(up: 2200, video_ms: 1000))
        }
        defer { confirmation.cancel() }
        await feed.afterAction(since: began)
        try await feed.requireFrame(after: began)
        XCTAssertLessThan(now() - began, 0.9, "Post-action proof should finish the wait as soon as the existing settling check passes")
        XCTAssertEqual(device.sent, ["stream on"])
    }

    func testQuietScreenStillNeedsMatchingRecentBoardEvidence() {
        XCTAssertFalse(FrameFreshness.usable(frameAt: 98, decodedMs: 1000, latestMs: 2000, statusAt: 100.2,
                                             at: 100.3, after: 100, broken: false))
        XCTAssertFalse(FrameFreshness.usable(frameAt: 98, decodedMs: 1000, latestMs: 1000, statusAt: 99.9,
                                             at: 100.3, after: 100, broken: false))
        XCTAssertFalse(FrameFreshness.usable(frameAt: 98, decodedMs: 1000, latestMs: 1000, statusAt: 100.2,
                                             at: 100.3, after: 100, broken: true))
        XCTAssertTrue(FrameFreshness.usable(frameAt: 98, decodedMs: 1000, latestMs: 1000, statusAt: 100.2,
                                            at: 100.3, after: 100, broken: false))
    }
}

@MainActor private final class SpeedDevice: HIDDevice {
    var links = 1
    var connected = true
    var sent: [String] = []
    func send(_ command: String) async throws -> String { sent.append(command); return "ok" }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { connected }
}
