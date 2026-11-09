import XCTest
@testable import IPhoneAgent

/// A screen that sends frames all the time, unless iOS is asking whether to stop sharing.
@MainActor private final class SharedScreen: ScreenSource {
    var live = true
    var frame: Data? = Data([0xff, 0xd8])
    var updated = 0.0
    var capturedAt = 0.0
    var aspect = 0.46
    var frozen = false
    /// Only a move shows anything: a click that changes nothing on a page that holds still.
    var onlyMoves = false
    private var ticking: Task<Void, Never>?
    func start() {
        ticking = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self, !self.frozen, !self.onlyMoves { self.updated = now() }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
    func stop() { ticking?.cancel() }
}

/// Where the clicks went, in mouse units. The first click brings the question up if `asks`, the next one answers it.
@MainActor private final class ClockBoard: HIDDevice {
    var links = 1
    var connected = true
    var at = (x: 0, y: 0)
    var clicks: [(x: Int, y: Int)] = []
    var homes = 0
    var asks = false
    let screen: SharedScreen
    init(screen: SharedScreen) { self.screen = screen }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func abort() async throws {}
    func send(_ command: String) async throws -> String {
        let parts = command.split(separator: " ")
        switch parts.first {
        case "curve": return "on"
        case "home": at = (0, 0); homes += 1
        case "move" where parts.count == 3:
            at = (at.x + Int(parts[1])!, at.y + Int(parts[2])!)
            if !screen.frozen { screen.updated = now() }
        case "click":
            clicks.append(at)
            if asks, clicks.count == 1 {  // the last frame comes a moment after the click that asks
                Task { @MainActor [screen] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    screen.frozen = true
                }
            } else if asks {
                screen.frozen = false
            }
        default: break
        }
        return ""
    }
}

@MainActor final class Build112Tests: XCTestCase {
    private func rig(asks: Bool = false, onlyMoves: Bool = false) -> (Pointer, ClockBoard, SharedScreen) {
        let screen = SharedScreen()
        screen.onlyMoves = onlyMoves
        screen.start()
        let board = ClockBoard(screen: screen)
        board.asks = asks
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: board, calibrationFile: file, screen: screen)
        p.finishCalibration(x: 0.5, y: 0.25)  // span 400 x 800
        return (p, board, screen)
    }

    func testAQuestionAfterAClickNearTheClockIsAnsweredWithCancel() async throws {
        let (p, board, screen) = rig(asks: true)
        defer { screen.stop() }
        var lines: [String] = []
        p.log = { lines.append($0) }
        try await p.tap(0.09, 0.088)  // the back button, under the clock
        XCTAssertFalse(screen.frozen, lines.joined(separator: "\n"))
        XCTAssertEqual(board.clicks.count, 2, lines.joined(separator: "\n"))
        XCTAssertEqual(Double(board.clicks[1].x) / 400, Pointer.cancelSharing.x, accuracy: 0.01)
        XCTAssertEqual(Double(board.clicks[1].y) / 800, Pointer.cancelSharing.y, accuracy: 0.01)
        XCTAssertTrue(lines.contains("frames are back"), lines.joined(separator: "\n"))
    }

    func testCancelIsOnTheHalfWithoutStop() {
        XCTAssertLessThan(Pointer.cancelSharing.x, 0.48)
        XCTAssertGreaterThan(Pointer.cancelSharing.x, 0.11)
        XCTAssertLessThan(Pointer.cancelSharing.y, 0.58)
        XCTAssertGreaterThan(Pointer.cancelSharing.y, 0.52)
    }

    func testFramesThatKeepComingMeanNoQuestion() async throws {
        let (p, board, screen) = rig()
        defer { screen.stop() }
        try await p.tap(0.09, 0.088)
        XCTAssertEqual(board.clicks.count, 1)
    }

    func testAClickThatChangedNothingIsNotTakenForAQuestion() async throws {
        let (p, board, screen) = rig(onlyMoves: true)
        defer { screen.stop() }
        try await p.tap(0.09, 0.088)
        XCTAssertEqual(board.clicks.count, 1, "the small move showed frames still come")
    }

    func testFramesStoppedElsewhereAreLeftToTheLoop() async throws {
        let (p, board, screen) = rig()
        defer { screen.stop() }
        screen.frozen = true
        try await p.tap(0.5, 0.5)
        XCTAssertEqual(board.clicks.count, 1)
    }

    func testAskedDirectlyItTapsCancelFromTheCorner() async throws {
        let (p, board, screen) = rig()
        defer { screen.stop() }
        try await p.tap(0.5, 0.5)
        let homes = board.homes
        let back = try await p.answerSharingQuestion()
        XCTAssertTrue(back)
        XCTAssertEqual(board.homes, homes + 1)
        XCTAssertEqual(Double(board.clicks[1].y) / 800, Pointer.cancelSharing.y, accuracy: 0.01)
    }

    func testWhereTheClockIs() {
        XCTAssertTrue(Pointer.nearClock(0.09, 0.088), "a back button")
        XCTAssertFalse(Pointer.nearClock(0.9, 0.088), "the other corner")
        XCTAssertFalse(Pointer.nearClock(0.09, 0.3))
    }

    func testATopBarIsAimedFromTheCorner() async throws {
        let (p, board, screen) = rig()
        defer { screen.stop() }
        try await p.tap(0.5, 0.5)
        XCTAssertEqual(board.homes, 1)
        try await p.tap(0.5, 0.7)
        XCTAssertEqual(board.homes, 1, "lower down it still hops")
        try await p.tap(0.3, 0.133)
        XCTAssertEqual(board.homes, 2, "Taobao's search bar")
    }

    func testWhatGoesAgainstTheMoveIsNotThePointer() {
        let seen = CGPoint(x: 0.301, y: 0.175)
        XCTAssertTrue(Pointer.wentAgainst(from: seen, to: CGPoint(x: 0.179, y: 0.265), units: -6, -36), "the 11-09 reading")
        XCTAssertFalse(Pointer.wentAgainst(from: seen, to: CGPoint(x: 0.296, y: 0.112), units: -6, -36), "where it was sent")
        XCTAssertFalse(Pointer.wentAgainst(from: seen, to: CGPoint(x: 0.302, y: 0.177), units: -6, -36), "too small to tell")
    }

    func testTheFarRightComesBackFromTheBorderEvenWhereTheMapReaches() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let mapX: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 150, "fraction": 0.5], ["units": 285, "fraction": 0.95]]]
        let mapY: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 650, "fraction": 1]]]
        let saved: [String: Any] = ["w": 300, "h": 650, "quality": 0.01, "stale": false,
            "motionVersion": ProbeMotion.version, "requiresFeedback": false, "maps": ["x": mapX, "y": mapY]]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        let p = Pointer(device: FakeDevice(), calibrationFile: file)
        XCTAssertFalse(p.beyondReach(0.85))
        XCTAssertTrue(p.beyondReach(0.89), "Meituan's search button")
    }

    func testTheSameDeadSpotIsNotRefusedUpToTheStepLimit() async {
        let actor = FakeModel { _ in "THINK: 點搜尋\nDO: tap 890 138" }
        let planner = FakeModel { _ in "1. 搜尋" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "搜尋", plan: "", steps: [], running: false)
        await agent.run()
        let refused = agent.steps.filter { $0["action"]?.str == "refused" }.count
        XCTAssertLessThanOrEqual(refused, 2 * (AgentLoop.refusalsInARow - 1), "\(agent.steps.map { $0["action"]?.str ?? "?" })")
    }

    func testTheModelsAreToldTheDate() throws {
        let parts = DateComponents(year: 2026, month: 11, day: 9, hour: 12)
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: parts))
        XCTAssertEqual(AgentLoop.todayLine(date), "Today is 2026-11-09, Monday.")
    }

    func testTheCheckSeesTheDateAndTheTaps() async {
        var turn = 0
        let actor = FakeModel { _ in
            defer { turn += 1 }
            return turn == 0 ? "THINK: 回到列表\nDO: tap 100 100" : "THINK: finished\nDO: done 三項都在"
        }
        var calls = 0
        let planner = FakeModel { _ in defer { calls += 1 }; return calls == 0 ? "1. look it up" : "OK" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.verifiesDone = true
        agent.showMock(task: "打開確認", plan: "", steps: [], running: false)
        await agent.run()
        let check = planner.prompts.first { $0.contains("Its answer") }
        XCTAssertEqual(check?.contains("Today is"), true, "\(planner.prompts)")
        XCTAssertEqual(check?.contains("tapped 回到列表"), true, "\(planner.prompts)")
    }
}
