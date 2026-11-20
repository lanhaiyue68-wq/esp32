import Network
import XCTest
@testable import IPhoneAgent

/// Phase B (specs/004): typing by Lan Agent's keyboard, `open APP`, the screen's text for the model, learned app places.
@MainActor final class PhaseBTests: XCTestCase {
    override func setUp() { AppPlaces.clear() }
    override func tearDown() { AppPlaces.clear() }

    // MARK: open

    func testOpenTakesTheWholeAppName() throws {
        XCTAssertEqual(try Actions.parseCommand("open 微信"), ["action": .str("open"), "app": .str("微信")])
        XCTAssertEqual(try Actions.parseCommand("open App Store")["app"], .str("App Store"))
    }

    func testAnOpenStepOpensTheAppByName() async throws {
        let (agent, phone) = run("THINK: 先打开微信。\nDO: open 微信")
        var opened: [String] = []
        agent.openApp = { opened.append($0); return true }
        _ = try await agent.step()
        XCTAssertEqual(opened, ["微信"])
        XCTAssertEqual(phone.taps, 0, "the opener taps, not the model's guess")
    }

    // MARK: typing by Lan Agent's keyboard

    func testChineseTextGoesThroughLanAgentsKeyboardAndReturnSends() async throws {
        let (agent, phone) = run("THINK: 输入框已聚焦，输入你好。\nDO: type 你好")
        var typed: [String] = []
        agent.keyboardType = { typed.append($0); return true }
        agent.ourKeyboardOnScreen = { true }
        agent.returnSends = true
        _ = try await agent.step()
        XCTAssertEqual(typed, ["你好"])
        XCTAssertTrue(phone.typed.isEmpty, "no pinyin when the keyboard took it")
        XCTAssertEqual(phone.keys, ["cmd+a", "backspace", "enter"], "the box emptied first, then Return sends")
    }

    func testPlainAsciiIsStillTypedByTheBoard() async throws {
        let (agent, phone) = run("THINK: 输入 hello。\nDO: type hello")
        var typed: [String] = []
        agent.keyboardType = { typed.append($0); return true }
        _ = try await agent.step()
        XCTAssertTrue(typed.isEmpty)
        XCTAssertEqual(phone.typed, ["hello"])
    }

    // MARK: the screen's text for the model

    func testScreenTextIsTopToBottomThenLeftToRight() {
        let piece = { (text: String, x: Double, y: Double) in
            CandidatePicker.Piece(text: text, box: CGRect(x: x - 0.05, y: y - 0.01, width: 0.1, height: 0.02))
        }
        let rows = [[piece("发送", 0.9, 0.5), piece("微信", 0.1, 0.502)], [piece("通讯录", 0.5, 0.2)], [piece("  ", 0.5, 0.3)],
                    [piece("say \"hi\"", 0.5, 0.8)]]
        XCTAssertEqual(AgentLoop.screenText(rows), "\"通讯录\" 500 200\n\"微信\" 100 502\n\"发送\" 900 500\n\"say 'hi'\" 500 800")
        XCTAssertEqual(AgentLoop.screenText(rows, limit: 1), "\"通讯录\" 500 200")
        XCTAssertNil(AgentLoop.screenText([[piece(" ", 0.5, 0.5)]]))
    }

    func testTheModelGetsTheScreensTextAndHearsTheKeyboardIsOurs() async throws {
        let (agent, _) = run("THINK: 等一下。\nDO: wait")
        agent.readsScreenText = true
        agent.ourKeyboardOnScreen = { true }
        _ = try await agent.step()
        let prompt = try XCTUnwrap(model?.prompts.last)
        XCTAssertTrue(prompt.contains("Text read on this screen"), prompt)
        XCTAssertTrue(prompt.contains("Pilot 輸入法"))
    }

    func testNoScreenTextUnlessAsked() async throws {
        let (agent, _) = run("THINK: 等一下。\nDO: wait")
        _ = try await agent.step()
        XCTAssertFalse(try XCTUnwrap(model?.prompts.last).contains("Text read on this screen"))
    }

    // MARK: learned app places

    func testAnAppsLabelIsFoundExactlyAndTheTopmostWins() {
        let rows = [[CandidatePicker.Piece(text: "微信读书", box: CGRect(x: 0.1, y: 0.2, width: 0.1, height: 0.02))],
                    [CandidatePicker.Piece(text: "微 信", box: CGRect(x: 0.3, y: 0.4, width: 0.1, height: 0.02))],
                    [CandidatePicker.Piece(text: "微信", box: CGRect(x: 0.6, y: 0.6, width: 0.1, height: 0.02))],
                    [CandidatePicker.Piece(text: "微信", box: CGRect(x: 0.6, y: 0.02, width: 0.1, height: 0.02))]]
        let spot = AppPlaces.label("微信", in: rows)
        XCTAssertEqual(spot?.x ?? 0, 0.35, accuracy: 0.001, "spaces do not matter, 微信读书 is another app, the status bar is skipped")
        XCTAssertEqual(spot?.y ?? 0, 0.41, accuracy: 0.001)
        XCTAssertNil(AppPlaces.label("Claude", in: rows))
        XCTAssertEqual(AppPlaces.icon(above: CGPoint(x: 0.5, y: 0.3)).y, 0.26, accuracy: 0.001)
        XCTAssertEqual(AppPlaces.icon(above: CGPoint(x: 0.5, y: 0.06)).y, 0.05, accuracy: 0.001)
    }

    func testTheSearchPillIsOnlyAboveTheDock() {
        let low = [CandidatePicker.Piece(text: "搜索", box: CGRect(x: 0.45, y: 0.86, width: 0.1, height: 0.02))]
        let high = [CandidatePicker.Piece(text: "搜索", box: CGRect(x: 0.45, y: 0.1, width: 0.1, height: 0.02))]
        XCTAssertEqual(AppPlaces.searchPill(in: [low])?.y ?? 0, 0.87, accuracy: 0.001)
        XCTAssertNil(AppPlaces.searchPill(in: [high]), "a search field at the top is an app's, not the Home Screen's")
    }

    func testPlacesAreKeptByNameAndCleared() {
        AppPlaces.set(AppPlace(page: 1, x: 0.3, y: 0.4), for: "Claude")
        AppPlaces.set(AppPlace(page: nil, x: 0, y: 0), for: "时钟")
        XCTAssertEqual(AppPlaces.place(for: "claude")?.page, 1)
        XCTAssertEqual(AppPlaces.place(for: "时钟")?.bySearch, true)
        XCTAssertEqual(AppPlaces.count, 2)
        AppPlaces.clear()
        XCTAssertEqual(AppPlaces.count, 0)
    }

    // MARK: the keyboard reports in

    func testTheKeyboardIsOnScreenOnlyWhileItAsks() async throws {
        let bridge = KeyboardBridge(port: 47_833)
        bridge.start()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(bridge.onScreen())
        _ = await KeyboardLinkTests.exchange(KeyboardLink.line(.hello(fullAccess: true)), port: 47_833)
        XCTAssertTrue(bridge.onScreen())
        XCTAssertFalse(bridge.onScreen(at: Date().addingTimeInterval(1.5)), "gone once it stops asking")
    }

    // MARK: helpers

    private var model: FakeModel?

    private func run(_ reply: String) -> (AgentLoop, RecordingPhone) {
        let screen = FakeScreen()
        screen.frame = CursorAndAcknowledgementSpeedTests.chat(caret: true)
        let phone = RecordingPhone()
        let actor = FakeModel { _ in reply }
        model = actor
        return (AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil), phone)
    }
}

@MainActor private final class RecordingPhone: Gestures {
    let device: HIDDevice = FakeDevice()
    var taps = 0
    var typed: [String] = []
    var keys: [String] = []
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { taps += 1 }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func type(_ text: String) async throws { typed.append(text) }
    func key(_ combo: String) async throws { keys.append(combo) }
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
