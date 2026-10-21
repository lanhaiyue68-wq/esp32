import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IPhoneAgent

/// The Codex review of build 14: stale plans, old streams, late lessons, done heuristics, lesson file size.
@MainActor final class Build14ReviewTests: XCTestCase {
    /// A dark frame with an optional light square (x, y, side in pixels of a 498 x 1080 frame).
    private func frame(square: (Int, Int, Int)?) -> Data {
        let (w, h) = (498, 1080)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(red: 0.15, green: 0.2, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        if let (x, y, side) = square {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: x, y: y, width: side, height: side))
        }
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// The model answers a tap at the next of `targets` while the screen switches to the next of `frames` on every
    /// request (it moves while the model answers).
    private func run(frames: [Data], targets: [String], steps: Int) async -> (AgentLoop, FakeGestures) {
        let screen = FakeScreen(), phone = FakeGestures()
        screen.frame = frames[0]
        var shown = 0, asked = 0
        let model = FakeModel { n in
            shown += 1
            screen.frame = frames[shown % frames.count]
            if n == 1 { return "1. tap the middle" }
            asked += 1
            return "THINK: tap it\nDO: tap " + targets[(asked - 1) % targets.count]
        }
        let agent = AgentLoop(phone: phone, screen: screen, actor: model, planner: model, trace: nil, maxSteps: steps)
        await agent.run()
        return (agent, phone)
    }

    private func stale(_ agent: AgentLoop) -> Int { agent.steps.filter { $0["action"]?.str == "stale plan" }.count }

    func testCoordinatesFromAScreenThatMovedUnderThemAreNeverSent() async {
        // Three different layouts right where the tap would land, and the model picks a different spot each time.
        let frames = [frame(square: nil), frame(square: (220, 510, 60)), frame(square: (200, 490, 100))]
        let (agent, phone) = await run(frames: frames, targets: ["500 500", "545 500", "500 545"], steps: 4)
        XCTAssertFalse(phone.calls.contains("tap"))
        XCTAssertEqual(stale(agent), 4)
    }

    func testAChangeAwayFromTheTargetDoesNotBlockTheRunForever() async {
        // Only a corner keeps changing, far from where the model taps (two spots, so never "the same spot again").
        let frames = [frame(square: nil), frame(square: (400, 150, 40))]
        let (agent, phone) = await run(frames: frames, targets: ["500 500", "500 560"], steps: 3)
        XCTAssertEqual(phone.calls, ["tap"])  // two looks dropped, the third acts: nothing changed where it lands
        XCTAssertEqual(stale(agent), 2)
    }

    func testALiveTargetChosenAgainOnTheNewerScreenIsTapped() async {
        // traces(30): the Clock icon's second hand moves right under the tap, and the run ran out of steps.
        let frames = [frame(square: nil), frame(square: (240, 530, 16))]
        let (agent, phone) = await run(frames: frames, targets: ["500 500", "505 498"], steps: 2)
        XCTAssertEqual(phone.calls, ["tap"])  // dropped once; the newer look chose the same spot, so it acts
        XCTAssertEqual(stale(agent), 1)
    }

    func testSameSpotAllowsAFewUnitsButNotAnotherTarget() {
        func tap(_ x: Int, _ y: Int) -> JObject { ["action": .str("tap"), "x": .int(x), "y": .int(y)] }
        XCTAssertTrue(AgentLoop.sameSpot(tap(160, 165), tap(169, 166)))
        XCTAssertFalse(AgentLoop.sameSpot(tap(167, 237), tap(160, 165)))
        XCTAssertFalse(AgentLoop.sameSpot(tap(160, 165), ["action": .str("swipe"), "x1": .int(160), "y1": .int(165),
                                                         "x2": .int(160), "y2": .int(300)]))
        let type: JObject = ["action": .str("type"), "text": .str("时钟")]
        XCTAssertTrue(AgentLoop.sameSpot(type, type))
        XCTAssertFalse(AgentLoop.sameSpot(type, ["action": .str("type"), "text": .str("闹钟")]))
    }

    func testARunSpentWaitingForTheScreenTeachesNothing() {
        let tap: JObject = ["action": .str("tap"), "x": .int(1), "y": .int(2)]
        let wait: JObject = ["action": .str("stale plan"), "reason": .str("screen changed")]
        XCTAssertFalse(LessonBook.worthReviewing([tap, wait, wait, wait]))  // traces(30): it blamed the route
        XCTAssertTrue(LessonBook.worthReviewing([tap, tap, tap, wait]))
    }

    func testAFrameFromAnEarlierBoardBootIsNotCurrent() {
        // Board rebooted: old board time 600 s + new clock offset puts the frame ~599 s in the future.
        XCTAssertFalse(FrameFreshness.usable(frameAt: 10_599, decodedMs: 600_000, latestMs: 1_000, statusAt: 10_000,
                                             at: 10_000, after: nil, broken: false))
        XCTAssertTrue(FrameFreshness.usable(frameAt: 9_999.6, decodedMs: 1_000, latestMs: 1_000, statusAt: 10_000,
                                            at: 10_000, after: nil, broken: false))
    }

    func testALateRunReviewCannotUndoACorrectionOrAClear() {
        let book = LessonBook(file: nil)
        book.forget(group: "r1:auto")  // the user marked a step of r1 wrong while the model was still reviewing it
        book.learnFromRun("r1", task: "打开白板画一个笑脸", lessons: ["脸已经画好，可以直接完成"])
        XCTAssertEqual(book.count, 0)
        let epoch = book.epoch
        book.clear()  // cleared while the review of r2 was under way
        book.learnFromRun("r2", task: "打开白板画一个笑脸", lessons: ["无边记：先新建画板"], epoch: epoch)
        XCTAssertEqual(book.count, 0)
        book.learnFromRun("r3", task: "打开白板画一个笑脸", lessons: ["无边记：先新建画板"], epoch: book.epoch)
        XCTAssertEqual(book.count, 1)
    }

    func testInputMethodsAndDrawersAreNotTypingOrDrawingTasks() {
        for task in ["打开设置，切换输入法", "查看输入法列表", "Open the app drawer", "把键盘的输入框调大"] {
            XCTAssertNil(AgentLoop.unmadeResult(task: task, steps: []), task)
        }
        XCTAssertNotNil(AgentLoop.unmadeResult(task: "在输入框里输入你好", steps: []))
        XCTAssertNotNil(AgentLoop.unmadeResult(task: "Open Notes and type \"hello\"", steps: []))
        XCTAssertNotNil(AgentLoop.unmadeResult(task: "draw a house", steps: []))
    }

    func testTheLessonFileAlwaysFitsWhatTheNextLaunchReads() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let book = LessonBook(file: file)
        // 4-byte characters, the longest tasks and lessons: ~2.5 KB a lesson, ~500 KB for 200 before the cap.
        let longTask = String(repeating: "📝", count: 300)
        for i in 0..<LessonBook.limit {
            book.learn(group: "r\(i):review", task: longTask + "\(i)", items: [("a", String(repeating: "📝", count: 400))])
        }
        let size = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertLessThanOrEqual(size, LessonBook.maxBytes)
        XCTAssertLessThanOrEqual(book.lessons.map(\.task.count).max() ?? 0, LessonBook.taskChars)
        XCTAssertEqual(LessonBook(file: file).count, book.count)  // the next launch reads every lesson back
        XCTAssertGreaterThan(book.count, 0)
    }

    func testAnUnreadableLessonFileIsKeptAsideNotOverwritten() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("lessons-v1.json")
        try Data("not json".utf8).write(to: file)
        let book = LessonBook(file: file)
        XCTAssertEqual(book.count, 0)
        book.learn(group: "r1:review", task: "t", items: [("a", "a note")])
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("lessons-v1.json.unreadable-") })
    }
}
