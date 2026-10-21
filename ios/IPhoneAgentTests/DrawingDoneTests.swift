import XCTest
@testable import IPhoneAgent

/// build 14: trace(25-29) - "done" on an old board's smiley, eyes drawn as open arcs, a 3-point mouth drawn as a V.
@MainActor final class DrawingDoneTests: XCTestCase {
    let smiley = "打开白板画一个笑脸"
    let tap: JObject = ["action": .str("tap"), "x": .int(382), "y": .int(472)]

    func testDrawingTaskIsNotDoneBeforeThisRunDrewAnything() {
        XCTAssertNotNil(AgentLoop.unmadeResult(task: smiley, steps: [tap]))  // an old board's smiley is not this run's
        let circle: JObject = ["action": .str("circle"), "x": .int(500), "y": .int(450), "r": .int(180)]
        XCTAssertNil(AgentLoop.unmadeResult(task: smiley, steps: [tap, circle]))
        XCTAssertNil(AgentLoop.unmadeResult(task: smiley, steps: [["action": .str("takeover"), "reason": .str("by hand")]]))
        XCTAssertNotNil(AgentLoop.unmadeResult(task: "Draw a cat in Notes", steps: []))
    }

    func testOtherTasksAreNeverHeldBack() {
        for task in ["回到主画面", "打开漫画App看第一话", "把画质调成高清", "打开设置", "截图发给我"] {
            XCTAssertNil(AgentLoop.unmadeResult(task: task, steps: []), task)
        }
    }

    func testTypingTasksAreNeverHeldBack() {
        // traces(32): "你好" went in as a compose step, "done" was turned down, and it sent the message again.
        XCTAssertNil(AgentLoop.unmadeResult(task: "在备忘录里输入你好", steps: [tap]))
        let compose: JObject = ["action": .str("compose"), "expected": .str("你好")]
        XCTAssertNil(AgentLoop.unmadeResult(task: "打开微信，直接打字发送一句“你好”", steps: [tap, compose, tap]))
    }

    func testRepeatedDoneWithoutDrawingIsRejectedThenAsksForHelp() async {
        let model = FakeModel { n in n == 1 ? "1. Draw the face" : "THINK: a smiley is on screen\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.showMock(task: smiley, plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(agent.steps.map { $0["action"]?.str }, ["plan", "done rejected", "done rejected", "fail"])
    }

    func testThreePointSmileIsDrawnAsACurveButACheckmarkIsNot() {
        let aspect = 0.46
        func pts(_ v: [Double]) -> [CGPoint] { stride(from: 0, to: v.count, by: 2).map { CGPoint(x: v[$0], y: v[$0 + 1]) } }
        XCTAssertTrue(AgentLoop.isGentleBend(pts([419, 467, 500, 492, 581, 467]), aspect: aspect))   // run 11:20
        XCTAssertTrue(AgentLoop.isGentleBend(pts([374, 478, 500, 510, 626, 478]), aspect: aspect))   // run 11:26
        XCTAssertFalse(AgentLoop.isGentleBend(pts([300, 500, 350, 560, 450, 420]), aspect: aspect))  // a checkmark
        XCTAssertFalse(AgentLoop.isGentleBend(pts([100, 500, 480, 520, 500, 500]), aspect: aspect))  // lopsided
        XCTAssertFalse(AgentLoop.isGentleBend(pts([100, 100, 200, 200, 300, 300, 400, 400]), aspect: aspect))  // 4 points
    }

    func testSmoothCurvePassesThroughItsPointsAndFitsOneCommand() {
        let input = [CGPoint(x: 419, y: 467), CGPoint(x: 500, y: 492), CGPoint(x: 581, y: 467)]
        let out = smoothCurve(input)
        XCTAssertEqual(out.count, 17)
        XCTAssertEqual(out[0], input[0])
        XCTAssertEqual(out[8].x, 500, accuracy: 1e-9); XCTAssertEqual(out[8].y, 492, accuracy: 1e-9)
        XCTAssertEqual(out[16].x, 581, accuracy: 1e-9); XCTAssertEqual(out[16].y, 467, accuracy: 1e-9)
        XCTAssertTrue(out.allSatisfy { $0.y >= 466 && $0.y <= 493 })  // no wild overshoot
        let long = (0..<20).map { CGPoint(x: Double($0) * 40, y: 500 + Double($0 % 2) * 30) }
        XCTAssertLessThanOrEqual(smoothCurve(long).count, 40)
    }

    func testPathSmoothKeywordIsParsed() throws {
        XCTAssertEqual(try Actions.parseCommand("path smooth 419 467 500 492 581 467")["smooth"], .bool(true))
        XCTAssertNil(try Actions.parseCommand("path 419 467 500 492 581 467")["smooth"])
        let plain = try Actions.parseCommand("path 419 467 500 492 581 467")
        XCTAssertTrue(Actions.sameTarget(plain, plain.merging(["smooth": .bool(true)])))  // still a repeat
    }

    func testInternalReasonsReachTheUserInPlainWords() {
        let blind = StepText.userReason("board replied but no verified current video frame was decoded")
        XCTAssertTrue(blind.contains("ESP32"))  // tells the user what to do, not the decoder's state
        XCTAssertEqual(StepText.userReason("lost the phone screen: reconnect Screen Mirroring"), blind)
        XCTAssertEqual(StepText.userReason("3 errors in a row"), String(localized: "Went wrong \(3) times in a row."))
        XCTAssertNotEqual(StepText.userReason("claimed done 3 times without doing it: Nothing has been drawn"),
                          "claimed done 3 times without doing it: Nothing has been drawn")
        XCTAssertEqual(StepText.userReason("密码弹窗挡住了"), "密码弹窗挡住了")  // the model's own words stay
        let fail: JObject = ["action": .str("fail"), "reason": .str("3 errors in a row")]
        XCTAssertFalse(StepText.line(fail).contains("errors in a row"))
        XCTAssertEqual(fail["reason"], .str("3 errors in a row"))  // the trace keeps the original
    }

    func testSmallCircleGoesPastItsStartSoTheEndsOverlap() {
        let aspect = 0.46
        let eye = circle(0.437, 0.425, 0.025, aspect: aspect, extra: 0.25)
        XCTAssertEqual(eye.count, 31)  // 24 segments and 6 more
        XCTAssertEqual(eye[24].x, eye[0].x, accuracy: 1e-9)
        XCTAssertEqual(eye[30].x, eye[6].x, accuracy: 1e-9); XCTAssertEqual(eye[30].y, eye[6].y, accuracy: 1e-9)
        XCTAssertEqual(circle(0.5, 0.5, 0.2, aspect: aspect).count, 25)  // unchanged by default
    }
}
