import UIKit
import XCTest
@testable import IPhoneAgent

/// Learned routes (RouteBook): the user felt no learning across runs (2026-11-05). Lessons only advised the model,
/// so every step still waited for it; a route walks known navigation without the model.
@MainActor final class RouteBookTests: XCTestCase {
    /// Plain screens whose coarse signatures differ: the home screen, the chat list, a chat, another chat.
    static func screen(_ top: Double, _ bottom: Double) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 296, height: 640), format: format).jpegData(withCompressionQuality: 0.8) { ctx in
            ctx.cgContext.setFillColor(gray: top, alpha: 1); ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 296, height: 320))
            ctx.cgContext.setFillColor(gray: bottom, alpha: 1); ctx.cgContext.fill(CGRect(x: 0, y: 320, width: 296, height: 320))
        }
    }
    var home: Data { Self.screen(0, 0) }
    var list: Data { Self.screen(1, 1) }
    var chat: Data { Self.screen(1, 0) }
    var other: Data { Self.screen(0, 1) }

    private func tap(_ x: Double, _ y: Double, changed: Bool = true) -> JObject {
        ["action": .str("tap"), "x": .num(x), "y": .num(y), "changed": .bool(changed)]
    }

    func testRouteKeepsTheNavigationUpToTypingWithoutDetours() throws {
        let steps: [JObject] = [["action": .str("plan")], tap(850, 590), tap(500, 300), ["action": .str("back"), "changed": .bool(true)],
                                tap(500, 400), tap(500, 930, changed: false), tap(500, 930),
                                ["action": .str("type"), "text": .str("你好")], ["action": .str("key"), "combo": .str("enter")],
                                ["action": .str("done")]]
        let shots: [Int: Data] = [1: home, 2: list, 3: other, 4: list, 5: chat, 6: chat, 7: chat]
        let route = try XCTUnwrap(RouteBook.route(steps: steps, shots: shots) { _, p in
            p.y == 0.59 ? ("微信", CGPoint(x: 0.85, y: 0.64)) : p.y == 0.4 ? ("蓝海乐", CGPoint(x: 0.3, y: 0.39)) : nil
        })
        XCTAssertEqual(route.map(\.action), ["tap", "tap", "tap"], "the wrong chat and its Back are a detour; typing is never kept")
        XCTAssertEqual(route.map(\.anchor), ["微信", "蓝海乐", nil])
        XCTAssertEqual(route[0].offsetY, -50)
    }

    func testARouteNeverKeepsASendOrPaymentTap() throws {
        let steps: [JObject] = [tap(850, 590), tap(900, 930), ["action": .str("done")]]
        let route = try XCTUnwrap(RouteBook.route(steps: steps, shots: [0: home, 1: chat]) { _, p in
            p.y == 0.93 ? ("发送", p) : ("微信", p)
        })
        XCTAssertEqual(route.map(\.anchor), ["微信"])
        XCTAssertNil(RouteBook.route(steps: [tap(850, 590), ["action": .str("fail")]], shots: [0: home]) { _, _ in nil })
    }

    func testAReplayNeedsTheSameNamedAppAndStartScreen() throws {
        let book = RouteBook(file: nil)
        let scene = try XCTUnwrap(Vision.experienceScene(home))
        book.store(task: "去 claude 说一句你好", aspect: 0.46,
                   steps: [.init(action: "tap", values: [386, 708], scene: scene, anchor: "Claude", offsetX: 0, offsetY: -40)])
        XCTAssertNotNil(book.match(task: "去 claude 说一句再见", scene: scene, aspect: 0.46))
        XCTAssertNil(book.match(task: "去 chatgpt 说一句你好", scene: scene, aspect: 0.46), "Claude's route must not open for ChatGPT")
        XCTAssertNil(book.match(task: "去 claude 说一句你好", scene: try XCTUnwrap(Vision.experienceScene(list)), aspect: 0.46))
        book.enabled = false
        XCTAssertNil(book.match(task: "去 claude 说一句你好", scene: scene, aspect: 0.46))
    }

    func testRepeatedMissesDropARoute() throws {
        let book = RouteBook(file: nil)
        let scene = try XCTUnwrap(Vision.experienceScene(home))
        book.store(task: "打开设置", aspect: 0.46, steps: [.init(action: "tap", values: [500, 500], scene: scene)])
        let id = try XCTUnwrap(book.routes.first?.id)
        for _ in 0..<3 { book.missed(id) }
        XCTAssertEqual(book.count, 0)
    }

    func testReplayWalksTheLearnedRouteWithoutAskingTheModel() async throws {
        let screen = RouteScreen(frames: [home, list, chat])
        let phone = RoutePhone(screen: screen)
        let model = FakeModel { _ in "DO: done 已打开" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: model, planner: model, trace: nil)
        let book = RouteBook(file: nil)
        book.store(task: "打开微信看蓝海乐", aspect: 0.46, steps: [
            .init(action: "tap", values: [850, 590], scene: try XCTUnwrap(Vision.experienceScene(home))),
            .init(action: "tap", values: [500, 400], scene: try XCTUnwrap(Vision.experienceScene(list)))])
        agent.routes = book
        agent.directStart = true
        try agent.start("打开微信看蓝海乐")
        for _ in 0..<200 where agent.running { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(phone.taps.count, 2)
        XCTAssertEqual(agent.steps.filter { $0["source"] == .str("route") }.count, 2)
        XCTAssertEqual(model.prompts.count, 1, "the model only confirms the result")
        XCTAssertEqual(agent.steps.last?["action"], .str("done"))
    }

    func testReplayHandsOverAtTheFirstScreenThatDiffers() async throws {
        let screen = RouteScreen(frames: [home, other, chat])  // the first tap opened something else
        let phone = RoutePhone(screen: screen)
        let model = FakeModel { _ in "DO: done 已打开" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: model, planner: model, trace: nil)
        let book = RouteBook(file: nil)
        book.store(task: "打开微信看蓝海乐", aspect: 0.46, steps: [
            .init(action: "tap", values: [850, 590], scene: try XCTUnwrap(Vision.experienceScene(home))),
            .init(action: "tap", values: [500, 400], scene: try XCTUnwrap(Vision.experienceScene(list)))])
        agent.routes = book
        agent.directStart = true
        try agent.start("打开微信看蓝海乐")
        for _ in 0..<200 where agent.running { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(phone.taps.count, 1, "the second step was learned on another screen")
        XCTAssertEqual(agent.steps.filter { $0["source"] == .str("route") }.count, 1)
    }

    // logs 11-06: "go to Claude" was learned starting inside WeChat; the next same task began on the Home Screen.
    func testARunStartingFurtherAlongJoinsTheRouteAtThatStep() throws {
        let book = RouteBook(file: nil)
        let chatScene = try XCTUnwrap(Vision.experienceScene(chat)), homeScene = try XCTUnwrap(Vision.experienceScene(home))
        let task = "你现在去 claude 给他发一句你好"
        book.store(task: task, aspect: 0.46, steps: [
            .init(action: "home", values: [], scene: chatScene),
            .init(action: "tap", values: [386, 708], scene: homeScene, anchor: "Claude", offsetX: 0, offsetY: -40)])
        XCTAssertEqual(book.entry(task: task, scene: homeScene, aspect: 0.46)?.from, 1)
        XCTAssertEqual(book.entry(task: task, scene: chatScene, aspect: 0.46)?.from, 0)
        XCTAssertNil(book.entry(task: "你现在去 chatgpt 给他发一句你好", scene: homeScene, aspect: 0.46), "never into another app")
    }

    func testAJoinedReplayWalksOnlyTheRestOfTheRoute() async throws {
        let screen = RouteScreen(frames: [list, chat])  // already past the first step (it was taken on home)
        let phone = RoutePhone(screen: screen)
        let model = FakeModel { _ in "DO: done 已打开" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: model, planner: model, trace: nil)
        let book = RouteBook(file: nil)
        book.store(task: "打开微信看蓝海乐", aspect: 0.46, steps: [
            .init(action: "tap", values: [850, 590], scene: try XCTUnwrap(Vision.experienceScene(home))),
            .init(action: "tap", values: [500, 400], scene: try XCTUnwrap(Vision.experienceScene(list)))])
        agent.routes = book
        agent.directStart = true
        try agent.start("打开微信看蓝海乐")
        for _ in 0..<200 where agent.running { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(phone.taps.count, 1)
        XCTAssertEqual(Double(try XCTUnwrap(phone.taps.first).y), 0.4, accuracy: 0.001, "the step learned on this screen")
        XCTAssertEqual(book.routes.first?.misses, 0, "joining part way is not a miss")
    }

    func testATimeOrACountIsNeverAnAnchor() throws {
        let steps: [JObject] = [tap(850, 590), tap(500, 300), ["action": .str("done")]]
        let route = try XCTUnwrap(RouteBook.route(steps: steps, shots: [0: home, 1: list]) { _, p in
            p.y == 0.3 ? ("20:20", p) : ("微信", p)
        })
        XCTAssertEqual(route.map(\.anchor), ["微信"], "the route ends before a tap on a time, which changes by the next run")
        let fragment = try XCTUnwrap(RouteBook.route(steps: steps, shots: [0: home, 1: list]) { _, p in
            p.y == 0.3 ? ("它", p) : ("微信", p)
        })
        XCTAssertEqual(fragment.map(\.anchor), ["微信"], "one character (logs 11-07: 它) is a message fragment")
    }
}

@MainActor private final class RouteScreen: ScreenSource {
    var live = true
    var frames: [Data]
    var frame: Data? { frames.first }
    var updated = 0.0
    var capturedAt = 0.0
    var aspect = 0.46
    init(frames: [Data]) { self.frames = frames }
    func next() { if frames.count > 1 { frames.removeFirst() }; updated = now(); capturedAt = updated }
}

@MainActor private final class RoutePhone: Gestures {
    let device: HIDDevice = FakeDevice()
    let screen: RouteScreen
    var taps: [CGPoint] = []
    init(screen: RouteScreen) { self.screen = screen }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { taps.append(CGPoint(x: x, y: y)); screen.next() }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws { screen.next() }
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func type(_ text: String) async throws {}
    func key(_ combo: String) async throws {}
    func goHome() async throws { screen.next() }
    func goBack() async throws { screen.next() }
    func reset() async throws {}
}

/// The lessons the user saw: unrelated ones reached every WeChat check, and "don't" rules carried old coordinates.
@MainActor final class LessonCleanupTests: XCTestCase {
    static let watchTask = "如果已经在范围内的微信会话里，直接完成并返回这个会话名，不要退出再查未读。否则打开微信，回到聊天列表（底部“微信”标签页），"
        + "在这些会话：“测试群”、“蓝海乐”里找第一个带红色未读数字或红点的会话并打开。一旦进入目标会话就完成，不要返回列表。"

    func testAShortTaskSharingCommonWordsNoLongerTeachesTheWatchCheck() {
        let book = LessonBook(file: nil)
        book.learn(group: "r1:review", task: "打开微信看看未读", items: [("a", "先选择中间三个按钮的左边那个")])
        book.learn(group: "r2:review", task: Self.watchTask, items: [("a", "看清两行的红点再完成")])
        let context = book.context(task: Self.watchTask)
        XCTAssertFalse(context.contains("三个按钮"))
        XCTAssertTrue(context.contains("看清两行的红点"))
        XCTAssertTrue(book.context(task: "打开无边记画个笑脸").isEmpty)
    }

    func testLessonsNamingCoordinatesAreNotKept() {
        let found = LessonBook.parseLessons("LESSON: 微信聊天列表：不要点 (265,147) 的蓝海乐\nLESSON: 微信聊天列表：先看红点再点会话")
        XCTAssertEqual(found, ["微信聊天列表：先看红点再点会话"])
    }

    func testDroppingSelfLearnedLessonsKeepsTheUsersOwn() {
        let book = LessonBook(file: nil)
        book.learn(group: "r1:review", task: "设置闹钟", items: [("a", "直接输入时间")])
        book.learnFromRun("r2", task: "设置闹钟", lessons: ["时钟：先点闹钟标签"])
        book.dropSelfLearned()
        XCTAssertEqual(book.lessons.map(\.text), ["直接输入时间"])
    }
}
