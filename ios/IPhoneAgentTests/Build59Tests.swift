import XCTest
@testable import IPhoneAgent

/// PC harness, 2026-10-25: relative moves drift 5–7% within a few gestures; space commits the first pinyin candidate,
/// which is right for common words on the full pinyin keyboard; the 9-key keyboard turns letters into digits.
@MainActor final class Build59Tests: XCTestCase {
    private func pointer() -> (Pointer, FakeDevice) {
        let device = FakeDevice()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let p = Pointer(device: device, calibrationFile: file)
        p.finishCalibration(x: 0.5, y: 0.25)  // span 400 x 800
        return (p, device)
    }

    func testEveryTapStartsFromTheCorner() async throws {
        let (p, device) = pointer()
        for _ in 0..<3 { try await p.tap(0.5, 0.5) }
        let homes = device.sent.enumerated().filter { $0.element == "home" }.map(\.offset)
        let clicks = device.sent.enumerated().filter { $0.element == "click" }.map(\.offset)
        XCTAssertEqual(homes.count, 3)
        for (h, c) in zip(homes, clicks) { XCTAssertLessThan(h, c) }
    }

    func testQuickTypingSendsPinyinAndCommitsEachChunkWithSpace() async throws {
        let (p, device) = pointer()
        try await p.typeQuick("你好")
        XCTAssertEqual(device.sent, ["type nihao", "key space"])
    }

    func testQuickChunksKeepTheTextAndStayShort() {
        let text = "我在帮你测试电脑端的操作流程"
        let chunks = Pointer.quickChunks(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 6 })
    }

    func testTheWholeTextIsFoundAcrossAWrappedBox() {
        let lines = ["我在帮你测试电脑端的操作流", "程,一切正常"]
        XCTAssertEqual(CandidatePicker.shows("我在帮你测试电脑端的操作流程，一切正常", lines: lines), 1)
        XCTAssertEqual(CandidatePicker.shows("他正在恢复", lines: ["它正在回复"]), 0, "a homophone is not the text")
    }

    func testComputerLogsAreOffUnlessSwitchedOn() {
        let d = UserDefaults.standard, old = d.object(forKey: DebugLog.computerKey)
        defer { if let old { d.set(old, forKey: DebugLog.computerKey) } else { d.removeObject(forKey: DebugLog.computerKey) } }
        d.removeObject(forKey: DebugLog.computerKey)
        XCTAssertFalse(DebugLog.toComputer)
        d.set(true, forKey: DebugLog.computerKey)
        XCTAssertTrue(DebugLog.toComputer)
    }

    /// 59 on the PC harness: a passcode task "@ the owner and say 这不是简简单单吗" ran as a phone task, whose prompt
    /// had none of the WeChat steps; it sent 这不是简简单单 without the @ and reported failure.
    func testPhoneTasksCarryTheWeChatMentionAndOwnerSteps() {
        let task = WatchSettings.ownerTask(chat: "蓝海乐", task: "去群里@群主说这不是简简单单吗", phone: true)
        for part in ["选择提醒的人", "拼音", "第一个", "一字不差", "只发一次", "不要把这句指令原文当内容"] { XCTAssertTrue(task.contains(part), part) }
    }

    /// build 62: an @-the-owner task sent without the passcode got "好的，我这就去测试群发消息." and then nothing ran.
    func testWithoutAuthorityTheReplyNeverPromisesToDoIt() {
        let r = WatchSettings.Rules(targets: ["蓝海乐"], senders: ["蓝海乐"])
        let m = ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "你去给测试群的群主@他发一条消息")
        let stranger = WatchSettings.composePrompt(chat: "蓝海乐", group: false, recent: [], due: [m], r: r, knowledge: "", owner: false)
        XCTAssertTrue(stranger.contains("不要答应去做"))
        let unproven = WatchSettings.composePrompt(chat: "蓝海乐", group: false, recent: [], due: [m], r: r, knowledge: "",
                                                   owner: false, needsPasscode: true)
        XCTAssertTrue(unproven.contains("请在消息开头带上口令再发一次"))
    }

    func testNineKeyKeyboardIsRecognized() {
        func row(_ labels: [String], y: Double) -> [CandidatePicker.Piece] {
            labels.enumerated().map { .init(text: $0.element, box: CGRect(x: 0.1 + 0.25 * Double($0.offset), y: y, width: 0.2, height: 0.04)) }
        }
        XCTAssertTrue(CandidatePicker.nineKey(rows: [row(["ABC", "DEF"], y: 0.7), row(["GHI", "JKL", "MNO"], y: 0.75)]))
        XCTAssertFalse(CandidatePicker.nineKey(rows: [row(["q", "w", "e", "r", "t", "y"], y: 0.7)]))
    }
}
