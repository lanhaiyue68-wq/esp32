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

/// User 11-08: "codex要做的是兜底，而且要做完之後記住做的路徑，下次就可以快速做出來…如果豆包api做不好就讓codex去做".
/// Doubao works part by part; Codex drives when Doubao stalls or gives up; a finished way is followed next time.
@MainActor final class CodexBackstopTests: XCTestCase {
    private let task = "打开设置，再打开备忘录"
    private let twoParts = "1. Settings is open - open 设置\n2. Notes is open - open 备忘录"
    private func actions(_ agent: AgentLoop) -> [String] { agent.steps.compactMap { $0["action"]?.str } }

    func testPartsGoOnWithoutAskingCodex() async {
        let planner = FakeModel { _ in self.twoParts }
        let actor = FakeModel { _ in "THINK: this part looks finished\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: task, plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "part done", "part done", "done"])
        XCTAssertEqual(planner.prompts.count, 1, "Codex only planned")
        XCTAssertTrue(actor.prompts[0].contains("Current part (1 of 2): 1. Settings is open"))
        XCTAssertTrue(actor.prompts[1].contains("Current part (2 of 2): 2. Notes is open"))
        XCTAssertTrue(actor.prompts[1].contains("Already done, with what it found: 1. Settings is open - open 设置 -> ok"))
    }

    func testCodexDoesItWhenTheExecutorGivesUp() async {
        let planner = FakeModel { n in
            switch n {
            case 1: return "1. Settings is open - open 设置"
            case 2: return "1. Settings is open - tap the 设置 icon"
            default: return "THINK: I open it myself\nDO: done opened"
            }
        }
        let actor = FakeModel { _ in "THINK: no icon here\nDO: fail cannot find Settings" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "fail", "replan (stuck)", "planner drives", "done"])
        XCTAssertEqual(actor.prompts.count, 1)
        XCTAssertEqual(agent.steps.last?["by"]?.str, "planner")
    }

    func testAPartCodexRescuedGoesBackToTheExecutor() async {
        let planner = FakeModel { n in n <= 2 ? self.twoParts : "THINK: Settings now\nDO: done opened Settings" }
        let actor = FakeModel { n in n == 1 ? "THINK: lost\nDO: fail no Settings icon" : "THINK: Notes is open\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: task, plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "fail", "replan (stuck)", "planner drives", "part done", "part done", "done"])
        XCTAssertEqual(planner.prompts.count, 3)
        XCTAssertEqual(actor.prompts.count, 2, "the executor takes the next part")
        XCTAssertEqual(agent.steps.last?["by"]?.str, "actor")
    }

    func testATaskDoneBeforeFollowsItsWayWithoutThePlanner() async {
        let routes = RouteBook(file: nil)
        routes.storeRecipe(task: "打开设置", lines: ["open 设置", "tap “通用”"])
        let planner = FakeModel { _ in "1. should not be asked" }
        let actor = FakeModel { _ in "THINK: done as before\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.routes = routes
        agent.showMock(task: "打开设置", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(actions(agent), ["plan", "done"])
        XCTAssertEqual(agent.steps.first?["source"]?.str, "remembered")
        XCTAssertEqual(planner.prompts.count, 0)
        XCTAssertTrue(actor.prompts[0].contains("- open 设置\n- tap “通用”"))
    }

    func testTheWholeWayIsRememberedPastTyping() {
        let shot = Data([1])
        let steps: [JObject] = [
            ["action": .str("plan"), "plan": .str("1. x")],
            ["action": .str("open"), "app": .str("时钟")],
            ["action": .str("tap"), "x": .num(880), "y": .num(90)],
            ["action": .str("tap"), "x": .num(500), "y": .num(300)],
            ["action": .str("swipe"), "x1": .num(500), "y1": .num(600), "x2": .num(500), "y2": .num(500), "changed": .bool(false)],
            ["action": .str("type"), "text": .str("0800")],
            ["action": .str("done"), "answer": .str("ok")],
        ]
        let lines = RouteBook.recipe(steps: steps, shots: [2: shot, 3: shot], label: { _, p in
            p.x > 0.8 ? (text: "新建闹钟", centre: p) : nil
        })
        XCTAssertEqual(lines, ["open 时钟", "tap “新建闹钟”", "tap 500 300", "type “0800”"])
        XCTAssertNil(RouteBook.recipe(steps: Array(steps.dropLast()), shots: [:], label: { _, _ in nil }), "only a finished run")
    }

    func testAWayIntoOneChatIsNotFollowedIntoAnother() {
        let routes = RouteBook(file: nil)
        routes.storeRecipe(task: "打开微信给测试群发你好并截图保存", lines: ["open 微信", "tap “测试群”", "type “你好”"])
        XCTAssertNotNil(routes.recipe(for: "打开微信给测试群发早安并截图保存"), "another text, the same chat")
        // build 115 (user 11-10): another chat follows the same way, with the old chat's name taken out
        let other = routes.recipe(for: "打开微信给测试组发你好并截图保存")
        XCTAssertEqual(other?.lines, ["open 微信", "tap “\(RouteBook.otherPlace)”", "type “你好”"])
        XCTAssertNil(routes.recipe(for: "打开QQ给测试群发你好并截图保存"), "another app is another way")
    }
}

/// build104 live 11-08: part 1 (the alarm) was done, refused three times as "nothing has been drawn" (part 2 was the
/// drawing), and the run stopped for help. The task's own checks are for the done that ends the task.
@MainActor final class PartDoneChecksTests: XCTestCase {
    func testAnEarlierPartIsNotHeldToTheWholeTasksChecks() async {
        let planner = FakeModel { _ in "1. Notes is open - open 备忘录\n2. A sun is drawn - draw it" }
        let actor = FakeModel { _ in "THINK: finished\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "打开备忘录，然后画一个太阳", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.compactMap { $0["action"]?.str }, ["plan", "part done", "done rejected", "done rejected", "fail"])
    }
}

/// build104 live 11-08: a banner with 主人蓝海乐's message ("9527 去给我画个太阳") covered a group's title; the reading
/// model took the banner's sender for the title and the group's talk was answered into 主人蓝海乐.
@MainActor final class WeChatBannerTests: XCTestCase {
    private func piece(_ text: String, x: Double, width: Double, y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x, y: y, width: width, height: 0.02))
    }

    func testABannerIsNotTheChatsTitle() {
        let banner = [[piece("主人蓝海乐", x: 0.2, width: 0.17, y: 0.058)], [piece("9527 去给我画个太阳", x: 0.2, width: 0.44, y: 0.08)]]
        XCTAssertNil(WatchReport.navigationChat(rows: banner, targets: ["主人蓝海乐", "测试群"]))
        XCTAssertNil(WatchReport.navigationTitle(rows: banner))
        XCTAssertEqual(WatchReport.navigationTitle(rows: [[piece("测试群(3)", x: 0.42, width: 0.16, y: 0.08)]]), "测试群")
    }

    func testTitlesCompareWithoutEmojiAndCounts() {
        XCTAssertTrue(WatchReport.sameChatTitle("测试群", "测试群🎉"))
        XCTAssertTrue(WatchReport.sameChatTitle("主人监海乐", "主人蓝海乐"), "one character misread")
        XCTAssertFalse(WatchReport.sameChatTitle("测试群", "主人蓝海乐"))
        XCTAssertFalse(WatchReport.sameChatTitle("", "测试群"))
    }
}

/// build104 live 11-08 (frames from the phone): the flick home left the app switcher open, and the page scan swiped
/// into the App Library; opening 备忘录, 美团 and even 微信 failed in one run.
@MainActor final class AppOpenerScreensTests: XCTestCase {
    private func piece(_ text: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x - 0.05, y: y - 0.01, width: 0.1, height: 0.02))
    }
    private var grid: [[CandidatePicker.Piece]] {
        ["时钟", "相机", "照片", "设置", "备忘录", "日历", "天气", "地图", "微信", "淘宝", "美团", "小红书"].enumerated().map { i, name in
            [piece(name, 0.15 + Double(i % 4) * 0.23, 0.15 + Double(i / 4) * 0.12)]
        }
    }

    func testAHomeScreenIsKnownByItsPillOrItsGrid() {
        XCTAssertTrue(AppPlaces.looksLikeHome([[piece("搜尋", 0.5, 0.82)]]))
        XCTAssertTrue(AppPlaces.looksLikeHome(grid))
    }

    func testTheAppSwitcherIsNotAHomeScreen() {
        XCTAssertFalse(AppPlaces.looksLikeHome([[piece("無邊記", 0.2, 0.06)], [piece("微信", 0.1, 0.06)]]))
    }

    func testTheAppLibraryIsKnownByItsSearchField() {
        let library = [[piece("App 資料庫", 0.5, 0.075)]] + grid
        XCTAssertTrue(AppPlaces.inLibrary(library))
        XCTAssertFalse(AppPlaces.looksLikeHome(library))
        XCTAssertEqual(AppPlaces.libraryField(in: library)?.y ?? 0, 0.075, accuracy: 0.001)
    }
}

/// build105 live 11-08: a search for 无边记 found nothing, and every new word was refused as "already entered", 30 times.
@MainActor final class PendingInputTests: XCTestCase {
    func testOtherWordsReplaceAFieldThatCouldNotBeConfirmed() async {
        let actor = FakeModel { n in n == 1 ? "THINK: wrong name\nDO: type 無邊記" : "THINK: found\nDO: done ok" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.inputToInspect = "无边记"; agent.directStart = true
        await agent.run()
        XCTAssertEqual(phone.calls, ["key", "key", "type"])
        XCTAssertFalse(agent.steps.contains { $0["action"] == .str("blocked") })
    }

    func testTheLibraryFieldReadsWithItsMagnifier() {
        let field = CandidatePicker.Piece(text: "Q App 資料庫", box: CGRect(x: 0.3, y: 0.07, width: 0.4, height: 0.02))
        XCTAssertTrue(AppPlaces.inLibrary([[field]]))
        XCTAssertFalse(AppPlaces.looksLikeHome([[field]]))
    }
}
