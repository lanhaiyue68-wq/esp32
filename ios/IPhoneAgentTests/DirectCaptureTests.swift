import XCTest
@testable import IPhoneAgent

@MainActor final class DirectCaptureTests: XCTestCase {
    private var retainedDevice: DirectDevice?
    private func ready() -> (VideoFeed, DirectDevice, UUID) {
        let device = DirectDevice(), feed = VideoFeed(source: .direct), id = UUID()
        retainedDevice = device
        feed.device = device
        feed.receiveDirect(.began(id))
        feed.receiveDirect(.frame(id, 1, Data([1, 2, 3]), 360, 780, now(), 2))
        return (feed, device, id)
    }

    func testNativePreflightAndSnapshotsNeverAskBoardForVideo() async throws {
        let (feed, device, _) = ready()
        let source = try await feed.prepareForRun(snapMode: true, wait: 0)
        XCTAssertEqual(source, "direct display")
        _ = try await feed.snap(timeout: 0)
        try await feed.stream(true)
        try await feed.stream(false)
        XCTAssertTrue(device.sent.isEmpty)
        XCTAssertFalse(feed.streamOn)
    }

    func testBoardMirrorStatusAndPixelsCannotOverrideDirectSource() {
        let (feed, _, _) = ready()
        feed.mirroring = false
        feed.status(BoardStatus(up: 0, video_ms: 0, ap: "idle"))
        feed.receive(Data([1, 2, 3]))
        feed.show(Data([9]), width: 12, height: 20)
        XCTAssertEqual(feed.frame, Data([1, 2, 3]))
        XCTAssertTrue(feed.mirroring)
    }

    func testBLEReconnectKeepsCaptureButDisconnectedBoardCannotAct() async {
        let (feed, device, _) = ready()
        device.connected = false; feed.linkLost()
        XCTAssertFalse(feed.live)
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Disconnected controls must block") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .boardDisconnected) }
        device.connected = true; feed.resetStream()
        XCTAssertTrue(feed.live)
        XCTAssertEqual(feed.frame, Data([1, 2, 3]))
    }

    func testStoppedCaptureRejectsDelayedFrames() {
        let (feed, _, id) = ready()
        feed.receiveDirect(.stopped(id, "stopped"))
        feed.receiveDirect(.frame(id, 20, Data([9]), 360, 780, now(), 1))
        XCTAssertNil(feed.frame)
        XCTAssertFalse(feed.mirroring)
        XCTAssertFalse(feed.sharingActive)
    }

    func testReplacementRejectsOldStreamStopAndFrame() {
        let (feed, _, old) = ready(), next = UUID()
        feed.receiveDirect(.began(next))
        feed.receiveDirect(.frame(next, 1, Data([7]), 360, 780, now(), 1))
        feed.receiveDirect(.stopped(old, "late stop"))
        feed.receiveDirect(.frame(old, 99, Data([9]), 360, 780, now(), 1))
        XCTAssertEqual(feed.frame, Data([7]))
        XCTAssertTrue(feed.sharingActive)
    }

    func testSuspensionClearsPixelsUntilCompleteFrame() {
        let (feed, _, id) = ready()
        feed.receiveDirect(.unavailable(id, 2, "suspended"))
        feed.receiveDirect(.idle(id, 3, now()))
        XCTAssertNil(feed.frame)
        XCTAssertFalse(feed.live)
        feed.receiveDirect(.frame(id, 4, Data([4]), 360, 780, now(), 1))
        XCTAssertTrue(feed.live)
    }

    func testIdleConfirmationDoesNotChangePixelsOrSettlingClock() async throws {
        let (feed, _, id) = ready()
        let changed = feed.updated, captured = feed.capturedAt
        let boundary = now()
        feed.receiveDirect(.idle(id, 2, now()))
        try await feed.requireFrame(after: boundary)
        XCTAssertEqual(feed.updated, changed)
        XCTAssertEqual(feed.capturedAt, captured)
        XCTAssertGreaterThanOrEqual(feed.confirmedAt, boundary)
        let fresh = await feed.fresh(since: captured, timeout: 0.01)
        XCTAssertEqual(fresh, feed.frame)
    }

    func testMissingNativeSharingDoesNotFallBackToBoardSnapshot() async {
        let device = DirectDevice(), feed = VideoFeed(source: .direct)
        feed.device = device
        do { _ = try await feed.currentFrame(wait: 0); XCTFail("Missing sharing must block") }
        catch { XCTAssertTrue(error is BlindError) }
        XCTAssertTrue(device.sent.isEmpty)
    }

    func testLateInvalidationCannotEraseNewerFrame() {
        let (feed, _, id) = ready()
        feed.receiveDirect(.frame(id, 5, Data([5]), 360, 780, now(), 1))
        feed.receiveDirect(.unavailable(id, 4, "old blank"))
        XCTAssertEqual(feed.frame, Data([5]))
        XCTAssertTrue(feed.live)
    }
}

@MainActor private final class DirectDevice: HIDDevice {
    var connected = true
    var links = 1
    var sent: [String] = []
    func send(_ command: String) async throws -> String { sent.append(command); return "ok" }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { connected }
}
