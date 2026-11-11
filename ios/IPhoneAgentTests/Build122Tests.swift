import AVFoundation
import XCTest
@testable import IPhoneAgent

/// Build 122 (user 11-11): how much of Codex is left, shown in Settings, read off the x-codex-* headers its answers carry
/// (the values below are the shape seen in the phone's log).
@MainActor final class Build122Tests: XCTestCase {

    func testTheQuotaIsReadFromCodexsHeaders() throws {
        let now = 1_794_074_561.0
        let headers = ["x-codex-primary-used-percent": "1", "x-codex-primary-window-minutes": "300",
                       "x-codex-primary-reset-after-seconds": "17635", "x-codex-secondary-used-percent": "73",
                       "x-codex-secondary-window-minutes": "10080", "x-codex-secondary-reset-at": "1794452772",
                       "x-codex-plan-type": "plus", "x-codex-credits-balance": "0"]
        let quota = try XCTUnwrap(PlusQuota(headers: headers, now: now))
        XCTAssertEqual(quota.short, PlusQuota.Window(minutes: 300, usedPercent: 1, resetAt: now + 17635))
        XCTAssertEqual(quota.long?.usedPercent, 73)
        XCTAssertEqual(quota.long?.resetAt, 1_794_452_772)
        XCTAssertEqual(quota.plan, "plus")
        let lines = quota.lines(now: now)
        XCTAssertEqual(lines.first, "5 小时额度：剩 99%，4 小时 53 分后重置")
        XCTAssertTrue(lines[1].hasPrefix("本周额度：剩 27%，"), lines[1])
        XCTAssertEqual(lines.last, "刚刚更新")
        XCTAssertEqual(quota.lines(now: now + 7200).last, "2 小时前更新")
        XCTAssertNil(PlusQuota(headers: ["x-codex-plan-type": "plus"]), "nothing about the quota")
    }

    func testAWindowPastItsResetIsFullAgain() {
        XCTAssertEqual(PlusQuota.line(.init(minutes: 300, usedPercent: 100, resetAt: 1000), now: 2000), "5 小时额度：已重置（剩 100%）")
        XCTAssertEqual(PlusQuota.line(.init(minutes: 300, usedPercent: 40, resetAt: 2600), now: 2000), "5 小时额度：剩 60%，10 分后重置")
        XCTAssertEqual(PlusQuota.line(.init(minutes: 300, usedPercent: 40, resetAt: nil), now: 2000), "5 小时额度：剩 60%")
    }

    // MARK: - found testing 121 on the phone (batch g, 11-11)

    /// g01: a 抖音 share link pasted into 测试群 (cmd+v) and sent with Return, no approval asked.
    func testAPastedMessageWaitsForApprovalLikeATypedOne() async {
        XCTAssertTrue(AgentLoop.pastes(["action": .str("key"), "combo": .str("cmd+v")]))
        XCTAssertTrue(AgentLoop.pastes(["action": .str("key"), "combo": .str("Cmd + V")]))
        XCTAssertFalse(AgentLoop.pastes(["action": .str("key"), "combo": .str("enter")]))
        XCTAssertEqual(AgentLoop.pastedText(nil), "（粘贴的内容）")
        XCTAssertEqual(AgentLoop.pastedText("  https://v.douyin.com/abc/ "), "https://v.douyin.com/abc/")

        var turn = 0
        let replies = ["THINK: 粘贴\nDO: key cmd+v", "THINK: 发送\nDO: key enter", "THINK: 好了\nDO: done 发了"]
        let actor = FakeModel { _ in defer { turn += 1 }; return replies[min(turn, replies.count - 1)] }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: FakeModel { _ in "1. 分享到测试群" }, trace: nil)
        var asked: [String] = []
        agent.approveSend = { asked.append($0); return false }
        agent.pasteboard = { "7.43 复制打开抖音，看看【二虎仔的作品】 https://v.douyin.com/abc/" }
        agent.showMock(task: "打開抖音首頁的第一個影片，用分享把它發到微信的测试群", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(asked.count, 1, "\(asked)")
        XCTAssertTrue(asked.first?.contains("v.douyin.com") == true)
        XCTAssertFalse(phone.keys.contains("enter"), "\(phone.keys)")
    }

    /// h01: asked to copy a WeChat message, both models wrote a long press their own way and the run failed.
    func testALongPressIsAnAction() throws {
        XCTAssertEqual(try Actions.parseCommand("hold 669 849"), ["action": .str("hold"), "x": .int(669), "y": .int(849)])
        XCTAssertEqual(try Actions.parseCommand("touch_and_hold 669 849")["action"], .str("hold"))
        XCTAssertEqual(try Actions.parseCommand("long_press 10 20")["action"], .str("hold"))
    }

    /// g04: 8816 audio samples in 180 s of a news video, no word recognized, and nothing in the log said why. How loud
    /// the audio was is kept now (0: silence).
    func testHowLoudTheScreensAudioWas() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 8
        XCTAssertEqual(ScreenAudio.loudness(buffer), 0, "silence")
        buffer.floatChannelData?[0][3] = -0.5
        XCTAssertEqual(ScreenAudio.loudness(buffer), 0.5)
        XCTAssertFalse(ScreenAudio.shared.report().silent, "nothing came in: not called silence")
    }

    func testTheQuotaIsKept() throws {
        let saved = UserDefaults.standard.data(forKey: PlusQuota.key)
        defer { UserDefaults.standard.set(saved, forKey: PlusQuota.key) }
        let quota = try XCTUnwrap(PlusQuota(headers: ["x-codex-secondary-used-percent": "100"], now: 5))
        PlusQuota.save(quota)
        XCTAssertEqual(PlusQuota.saved, quota)
        XCTAssertEqual(PlusQuota.saved?.long?.minutes, 10080, "the week when the header leaves it out")
    }
}
