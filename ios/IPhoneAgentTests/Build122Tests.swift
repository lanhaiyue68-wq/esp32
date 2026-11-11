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

    func testTheQuotaIsKept() throws {
        let saved = UserDefaults.standard.data(forKey: PlusQuota.key)
        defer { UserDefaults.standard.set(saved, forKey: PlusQuota.key) }
        let quota = try XCTUnwrap(PlusQuota(headers: ["x-codex-secondary-used-percent": "100"], now: 5))
        PlusQuota.save(quota)
        XCTAssertEqual(PlusQuota.saved, quota)
        XCTAssertEqual(PlusQuota.saved?.long?.minutes, 10080, "the week when the header leaves it out")
    }
}
