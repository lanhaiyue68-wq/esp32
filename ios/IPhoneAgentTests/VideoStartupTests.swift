import XCTest
@testable import IPhoneAgent

@MainActor final class VideoStartupTests: XCTestCase {
    func testDisconnectedBoardDoesNotSendStartCommands() async {
        let device = StartupDevice(); device.connected = false
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Must not start without the board") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .boardDisconnected) }
        XCTAssertTrue(device.sent.isEmpty)
    }

    func testDisconnectedMirrorDoesNotRequestSnapshots() async {
        let device = StartupDevice(), feed = VideoFeed(); feed.device = device
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Must not start without mirroring") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .mirroringDisconnected) }
        XCTAssertTrue(device.sent.isEmpty)
    }

    func testConnectedMirrorWithoutDecodableGOPHasDistinctFailure() async {
        let device = StartupDevice(); device.snapError = DeviceError(message: "err no video (start screen mirroring)")
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true; feed.noVideoGrace = 0
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Missing GOP cannot authorize a run") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .decoderUnavailable) }
        XCTAssertEqual(device.sent, ["stream on", "snap"]) // no repeated snap, reset or experimental kick
    }

    func testCurrentVerifiedFrameStartsWithoutFetchingGOPAgain() async throws {
        let device = StartupDevice(), feed = VideoFeed(); feed.device = device; feed.mirroring = true
        feed.status(BoardStatus(up: 0, video_ms: 0))
        feed.show(Data([0xff, 0xd8]), width: 360, height: 780)
        let source = try await feed.prepareForRun(wait: 0)
        XCTAssertEqual(source, "live")
        XCTAssertEqual(device.sent, ["stream on"])
    }

    func testOldFrameBehindBoardDoesNotPassPreflight() async {
        let device = StartupDevice(); device.snapError = DeviceError(message: "err no video (start screen mirroring)")
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true; feed.noVideoGrace = 0
        feed.status(BoardStatus(up: 100_000, video_ms: 1234))
        feed.show(Data([0xff, 0xd8]), width: 360, height: 780) // boardMs=0, older than current status
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Cached old pixels must not authorize actions") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .decoderUnavailable) }
        XCTAssertEqual(device.sent, ["stream on", "snap"])
    }

    func testOtherCommandFailuresAreNotMislabelledAsMissingGOP() async {
        let device = StartupDevice(); device.snapError = DeviceError(message: "err video not subscribed")
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Subscription failure must propagate") }
        catch { XCTAssertEqual((error as? DeviceError)?.message, "err video not subscribed") }
        XCTAssertEqual(device.sent, ["stream on", "snap"])
    }

    func testLiveFrameArrivingDuringSnapshotFailureCanRecover() async throws {
        let device = StartupDevice(); device.snapError = DeviceError(message: "err no video (start screen mirroring)")
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true
        device.onSnap = {
            feed.status(BoardStatus(up: 0, video_ms: 0))
            feed.show(Data([0xff, 0xd8]), width: 360, height: 780)
        }
        let source = try await feed.prepareForRun(wait: 0)
        XCTAssertEqual(source, "live (recovered during snap)")
        XCTAssertEqual(device.sent, ["stream on", "snap"])
    }

    func testMirrorLostDuringSnapshotDoesNotReportConnectedDecoderProblem() async {
        let device = StartupDevice(); device.snapError = DeviceError(message: "err no video (start screen mirroring)")
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true; feed.noVideoGrace = 0
        device.onSnap = { feed.mirroring = false }
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Mirror dropped during startup") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .mirroringDisconnected) }
    }

    func testCancellationIsNotChangedIntoVideoFailure() async {
        let device = StartupDevice(); device.snapError = CancellationError()
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true
        do { _ = try await feed.prepareForRun(wait: 0); XCTFail("Cancellation must stop startup") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testStartupDiagnosticsPreserveDecoderAndStreamState() async throws {
        let device = StartupDevice(), feed = VideoFeed(); feed.device = device; feed.mirroring = true
        feed.status(BoardStatus(up: 0, video_ms: 0))
        feed.show(Data([0xff, 0xd8]), width: 360, height: 780)
        _ = try await feed.prepareForRun(wait: 0)
        let state = feed.diagnostics
        XCTAssertEqual(state["connected"], .bool(true))
        XCTAssertEqual(state["mirroring"], .bool(true))
        XCTAssertEqual(state["stream_on"], .bool(true))
        XCTAssertEqual(state["has_frame"], .bool(true))
        XCTAssertEqual(state["broken"], .bool(false))
        XCTAssertEqual(state["decoded_ms"], .int(0))
        XCTAssertEqual(state["latest_board_ms"], .int(0))
        XCTAssertNotNil(state["status_age_s"]?.double)
    }

    func testSnapModePreflightKeepsStreamOff() async throws {
        let device = StartupDevice(), feed = VideoFeed(); feed.device = device; feed.mirroring = true
        device.onSnap = {
            feed.status(BoardStatus(up: 0, video_ms: 0))
            feed.show(Data([0xff, 0xd8]), width: 360, height: 780)
        }
        let source = try await feed.prepareForRun(snapMode: true, wait: 0)
        XCTAssertEqual(source, "snap")
        XCTAssertEqual(device.sent, ["snap"])  // the user's snap mode: no "stream on"
        XCTAssertFalse(feed.streamOn)
    }

    func testLostBoardOrMirrorIsNotCountedAsAnAgentFailure() {
        XCTAssertTrue(AgentLoop.isLinkLoss(VideoReadinessError.boardDisconnected, screenLive: true))
        XCTAssertTrue(AgentLoop.isLinkLoss(VideoReadinessError.mirroringDisconnected, screenLive: true))
        XCTAssertFalse(AgentLoop.isLinkLoss(VideoReadinessError.decoderUnavailable, screenLive: false))
        XCTAssertTrue(AgentLoop.isLinkLoss(DeviceError(message: "link lost"), screenLive: false))  // as before
        XCTAssertFalse(AgentLoop.isLinkLoss(DeviceError(message: "err busy"), screenLive: true))  // as before
        XCTAssertFalse(AgentLoop.isLinkLoss(URLError(.timedOut), screenLive: nil))
        XCTAssertFalse(AgentLoop.isLinkLoss(VideoReadinessError.checkTimedOut, screenLive: true))
    }

    // build 14: trace(25-29) showed "restart mirroring" while the stream recovered by itself seconds later.

    func testNoVideoWaitsForTheStreamToRecoverBeforeBlamingMirroring() async throws {
        let device = StartupDevice(); device.snapError = DeviceError(message: "err no video (start screen mirroring)")
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true; feed.noVideoGrace = 3
        device.onSnap = {
            Task { @MainActor in  // the stream comes back a moment after the board said "no video"
                try? await Task.sleep(nanoseconds: 300_000_000)
                feed.status(BoardStatus(up: 0, video_ms: 0))
                feed.show(Data([0xff, 0xd8]), width: 360, height: 780)
            }
        }
        let source = try await feed.prepareForRun(wait: 0)
        XCTAssertEqual(source, "live (recovered)")
        XCTAssertEqual(device.sent, ["stream on", "snap"])
    }

    func testSlowSnapshotInPreflightIsCappedWithAClearError() async {
        let device = StartupDevice(); device.snapError = BoardTimeout(command: "snap", seconds: 1)
        let feed = VideoFeed(); feed.device = device; feed.mirroring = true; feed.noVideoGrace = 0
        do { _ = try await feed.prepareForRun(wait: 0, snapLimit: 1); XCTFail("A capped snapshot must not be retried") }
        catch { XCTAssertEqual(error as? VideoReadinessError, .checkTimedOut) }
        XCTAssertEqual(device.sent, ["stream on", "snap"])  // one snapshot, no longer second try
    }
}

@MainActor private final class StartupDevice: HIDDevice {
    var links = 1
    var connected = true
    var sent: [String] = []
    var snapError: Error?
    var onSnap: (() -> Void)?
    func send(_ command: String) async throws -> String {
        sent.append(command)
        if command == "snap" {
            onSnap?()
            if let snapError { throw snapError }
        }
        return "ok"
    }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { connected }
}
