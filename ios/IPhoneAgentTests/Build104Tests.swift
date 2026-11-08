import XCTest
import UIKit
@testable import IPhoneAgent

/// A board and phone that behave like the test phone did in the accuracy test of 11-08:
/// - the board sends 4 app units as one HID count and keeps the remainder for the next move (BLE_MOVE_DIV);
/// - a lone count moves the pointer less than a count within a longer move (iOS acceleration);
/// - the calibrated span is a few percent off, so moves from the corner land 2-4 % away;
/// - the frame of the pointer stopping is published before the move command answers (direct capture publishes
///   on change; the board's answer comes back over BLE ~100 ms later).
@MainActor private final class CountingBoard: HIDDevice {
    var links = 1
    var connected = true
    var at = CGPoint(x: 0.3, y: 0.6)
    var clicks: [CGPoint] = []
    var changedAt = 0.0
    private var remX = 0, remY = 0
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func send(_ command: String) async throws -> String {
        let parts = command.split(separator: " ")
        switch parts.first {
        case "curve": return "on"
        case "home": at = .zero; changedAt = now()
        case "click": clicks.append(at)
        case "move" where parts.count == 3:
            let tx = Int(parts[1])! + remX, ty = Int(parts[2])! + remY
            let cx = tx / 4, cy = ty / 4              // C's division: toward zero, like the firmware
            remX = tx - cx * 4; remY = ty - cy * 4
            if cx != 0 || cy != 0 {
                at.x = min(max(at.x + Self.travel(cx, perCount: 0.0145), 0), 1)
                at.y = min(max(at.y + Self.travel(cy, perCount: 0.0068), 0), 1)
                changedAt = now()
            }
        default: break
        }
        try await Task.sleep(nanoseconds: 100_000_000)  // the answer arrives after the frame
        return ""
    }
    private static func travel(_ counts: Int, perCount: Double) -> Double {
        Double(counts) * perCount * (abs(counts) == 1 ? 0.6 : 1)
    }
}

/// Direct capture: a new frame only when the pointer moved; the frame is captured when it moved.
@MainActor private final class ChangeOnlyScreen: ScreenSource {
    let board: CountingBoard
    init(board: CountingBoard) { self.board = board }
    var live = true
    var aspect = 592.0 / 1280
    var updated: Double { board.changedAt }
    var capturedAt: Double { board.changedAt }
    private var cache: (CGPoint, Data)?
    var frame: Data? {
        if let cache, cache.0 == board.at { return cache.1 }
        let size = CGSize(width: 592, height: 1280), at = board.at
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let jpeg = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.11, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for i in 0..<8 {
                ("第 \(i) 行 加入鬧鐘 上午 8:00" as NSString).draw(at: CGPoint(x: 40, y: 300 + CGFloat(i) * 110),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.white])
            }
            UIColor(white: 0.5, alpha: 0.55).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: at.x * size.width - 15, y: at.y * size.height - 15, width: 30, height: 30))
        }.jpegData(compressionQuality: 0.72)
        cache = (at, jpeg!)
        return jpeg
    }
}

@MainActor final class Build104Tests: XCTestCase {
    /// Accuracy test 11-08 (three runs after a relaunch): screen sharing was off, no frame reached the pointer, and
    /// the closed loop skipped every tap without a word. A tap with no frame must say so and report the eye blind.
    func testATapWithNoScreenFrameSaysTheEyeWasBlind() async throws {
        let screen = FakeScreen(); screen.frame = nil
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: FakeDevice(), calibrationFile: file, screen: screen)
        p.finishCalibration(x: 0.5, y: 0.25)
        var lines: [String] = []
        p.log = { lines.append($0) }
        try await p.tap(0.4, 0.6)
        XCTAssertEqual(p.lastArrival, .unseen)
        XCTAssertTrue(lines.contains { $0.contains("no screen frame") }, lines.joined(separator: "\n"))
    }

    /// The accuracy test's spots, through the same closed loop: every click within 1 % on both axes, although the
    /// frame comes before the answer, short corrections are held back by the board, and the span is off.
    func testTapsLandWithinOnePercentOnABoardThatKeepsARemainder() async throws {
        let board = CountingBoard()
        let screen = ChangeOnlyScreen(board: board)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let p = Pointer(device: board, calibrationFile: file, screen: screen)
        p.finishCalibration(x: 200.0 / 265, y: 200.0 / 565)  // true span ~276 x 588: moves land short by ~4 %
        var lines: [String] = []
        p.log = { lines.append($0) }
        let spots: [(Double, Double)] = [(0.12, 0.1), (0.63, 0.1), (0.38, 0.5), (0.9, 0.5), (0.12, 0.9), (0.63, 0.9)]
        for (x, y) in spots {
            try await p.tap(x, y)
            let hit = try XCTUnwrap(board.clicks.last)
            XCTAssertEqual(hit.x, x, accuracy: 0.01, "(\(x), \(y))\n" + lines.joined(separator: "\n"))
            XCTAssertEqual(hit.y, y, accuracy: 0.01, "(\(x), \(y))\n" + lines.joined(separator: "\n"))
            XCTAssertEqual(p.lastArrival, .onTarget, "(\(x), \(y))")
        }
        XCTAssertFalse(lines.contains { $0.contains("no frame after the move") }, "the frame came before the answer")
    }

    func testACorrectionAlwaysSendsAtLeastOneCount() {
        XCTAssertEqual(Pointer.fineUnits(0.009, perUnit: 1.0 / 276), 4)    // 2.5 units: would send nothing
        XCTAssertEqual(Pointer.fineUnits(-0.009, perUnit: 1.0 / 276), -4)
        XCTAssertEqual(Pointer.fineUnits(0.05, perUnit: 1.0 / 276), 14)
    }

    func testWhatACorrectionReallyMovedIsLearned() {
        let estimate = 1.0 / 276
        XCTAssertEqual(Pointer.learned(estimate, moved: 0.0145, units: 4), 0.5 * estimate + 0.5 * 0.0145 / 4, accuracy: 1e-9)
        XCTAssertEqual(Pointer.learned(estimate, moved: 0, units: 4), estimate)          // held back by the board
        XCTAssertEqual(Pointer.learned(estimate, moved: -0.01, units: 4), estimate)      // the wrong way: not trusted
    }
}

/// User 11-08: "加了 codex，爲啥 codex 也做不好這個活，這不是説明 codex 根本就沒介入嗎" (Plus planned 3 of 53
/// decisions). The planner splits a task into parts, checks each on the screen, and drives when the executor stalls.
@MainActor final class PlannerCommandsTests: XCTestCase {
    private let task = "打开设置，再打开备忘录"
    private let twoParts = "1. Settings is open - open 设置\n2. Notes is open - open 备忘录"
    private func actions(_ agent: AgentLoop) -> [String] { agent.steps.compactMap { $0["action"]?.str } }

    func testEachPartIsCheckedByThePlannerBeforeTheNextBegins() async {
        let planner = FakeModel { n in
            switch n {
            case 1: return self.twoParts
            case 2: return #"{"done": false, "why": "the Settings list is not on screen", "next": "tap the Settings icon"}"#
            default: return #"{"done": true, "why": "it is on screen"}"#
            }
        }
        let actor = FakeModel { _ in "THINK: this part looks finished\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: task, plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "part not done", "part done", "part done", "done"])
        XCTAssertEqual(actor.prompts.count, 3)
        XCTAssertTrue(actor.prompts[0].contains("Current part (1 of 2): 1. Settings is open"))
        XCTAssertTrue(actor.prompts[1].contains("Planner: tap the Settings icon"))
        XCTAssertTrue(actor.prompts[2].contains("Current part (2 of 2): 2. Notes is open"))
        XCTAssertTrue(actor.prompts[2].contains("Done and checked by the planner: 1. Settings is open"))
    }

    func testAfterTwoRefusalsThePlannerDrivesThePartItself() async {
        let planner = FakeModel { n in
            switch n {
            case 1: return self.twoParts
            case 2, 3: return #"{"done": false, "why": "still the home screen", "next": "open 设置"}"#
            default: return "THINK: I open it myself\nDO: done opened"
            }
        }
        let actor = FakeModel { _ in "THINK: finished\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: task, plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "part not done", "part not done", "planner drives", "part done", "part done", "done"])
        XCTAssertEqual(actor.prompts.count, 2, "the executor stops once the planner drives")
        XCTAssertEqual(agent.steps.last?["by"]?.str, "planner")
    }

    func testAOnePartTaskIsNotCheckedTwice() async {
        let planner = FakeModel { _ in "1. Settings is open - open 设置" }
        let actor = FakeModel { _ in "THINK: Settings is open\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "done"])
        XCTAssertEqual(planner.prompts.count, 1)
    }

    func testTheCheckIsReadFromItsJSONAndPartsFromNumberedLines() {
        let v = AgentLoop.partVerdict("Sure.\n{\"done\": false, \"why\": \"no alarm\", \"next\": \"tap +\"}")
        XCTAssertEqual(v?.done, false); XCTAssertEqual(v?.next, "tap +")
        XCTAssertNil(AgentLoop.partVerdict("1. Open Clock"))
        XCTAssertEqual(AgentLoop.parts(of: "Plan:\n1. A\n  2) B\nnote\n3、C"), ["1. A", "2) B", "3、C"])
    }
}
