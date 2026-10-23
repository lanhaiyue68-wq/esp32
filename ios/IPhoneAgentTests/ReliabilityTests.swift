import XCTest
@testable import IPhoneAgent

@MainActor final class ReliabilityTests: XCTestCase {
    func testMalformedCoordinatesNeverTrapOrExecute() {
        for line in ["tap 9223372036854775808 2", "tap 1e999 2", "tap -1 4", "tap 1001 4", "path 0 0 2 1001"] {
            XCTAssertThrowsError(try Actions.parseCommand(line), line)
        }
        XCTAssertEqual(try Actions.parseCommand("tap 1000 0")["x"], .int(1000))
    }

    func testDroppedClickReplyDoesNotReplayClick() async {
        let board = FakeBoard(); board.silent = true
        let channel = CommandChannel(transport: board); board.channel = channel
        var recoveries = 0
        channel.onTimeout = { _ in recoveries += 1 }
        do { try await channel.send("click"); XCTFail("expected uncertainty") } catch { XCTAssertTrue(error is BoardTimeout) }
        XCTAssertEqual(board.lines.count, 1)
        XCTAssertEqual(recoveries, 1)
    }

    func testCancelledQueuedCommandIsNotWritten() async throws {
        let board = FakeBoard(); board.silent = true
        let channel = CommandChannel(transport: board); board.channel = channel
        let first = Task { try await channel.send("click", timeout: 0.1) }
        try await Task.sleep(nanoseconds: 20_000_000)
        let queued = Task { try await channel.send("type must-not-appear") }
        queued.cancel()
        _ = try? await first.value; _ = try? await queued.value
        XCTAssertEqual(board.lines.count, 1)
    }

    func testAbortBypassesRunningCommandAndDiscardsQueuedWork() async throws {
        let board = FakeBoard(); board.silent = true
        let channel = CommandChannel(transport: board); board.channel = channel
        let active = Task { try await channel.send("type first") }
        try await Task.sleep(nanoseconds: 20_000_000)
        let queued = Task { try await channel.send("click") }
        try await Task.sleep(nanoseconds: 20_000_000)
        board.silent = false
        try await channel.abort()
        _ = try? await active.value; _ = try? await queued.value
        XCTAssertEqual(board.lines.map { $0.split(separator: " ")[1] }, ["type", "abort"])
    }

    func testUnsupportedTextFailsBeforeAnyKeyboardSideEffect() async {
        let device = FakeDevice()
        let pointer = Pointer(device: device, calibrationFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        do { try await pointer.type("hello😀"); XCTFail("unsupported text must fail") } catch {}
        XCTAssertEqual(device.sent, [])
    }

    func testChineseLeavesCompositionOpenForCandidateInspection() async {
        let device = FakeDevice()
        let pointer = Pointer(device: device, calibrationFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        do { try await pointer.type("你好"); XCTFail("must inspect candidates") }
        catch let input as InputNeedsVerification { XCTAssertEqual(input.expected, "你好"); XCTAssertEqual(input.remaining, "") }
        catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(device.sent, ["type nihao"])
    }

    func testDrawingTravelBetweenStrokesCountsTowardRehomeBudget() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(#"{"w":1000,"h":1000}"#.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let device = FakeDevice(), pointer = Pointer(device: device, calibrationFile: file)
        let near = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0)]
        let far = [CGPoint(x: 1000, y: 1000), CGPoint(x: 999, y: 1000), CGPoint(x: 998, y: 1000)]
        for path in [near, far, near, far, near] { try await pointer.drag(path, hold: false) }
        XCTAssertGreaterThanOrEqual(device.sent.filter { $0 == "home" }.count, 2)
    }

    func testTextChunksKeepWhitespaceAndRejectUnsupportedBeforeTyping() throws {
        let text = String(repeating: "a ", count: 250) + "  "
        let chunks = try Pointer.keyboardChunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 400 })
        XCTAssertThrowsError(try Pointer.keyboardChunks("ok😀"))
    }

    func testQuietScreenRequiresCurrentStatusAndLatestDecodedFrame() {
        XCTAssertTrue(FrameFreshness.usable(frameAt: 10, decodedMs: 100, latestMs: 100, statusAt: 20, at: 21, after: 19, broken: false))
        XCTAssertFalse(FrameFreshness.usable(frameAt: 10, decodedMs: 100, latestMs: 200, statusAt: 20, at: 21, after: 19, broken: false))
        XCTAssertFalse(FrameFreshness.usable(frameAt: 10, decodedMs: 100, latestMs: 100, statusAt: 10, at: 21, after: 19, broken: false))
        XCTAssertFalse(FrameFreshness.usable(frameAt: 20, decodedMs: 100, latestMs: 100, statusAt: 20, at: 21, after: 19, broken: true))
    }
}
