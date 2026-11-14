import XCTest
@testable import IPhoneAgent

/// Build 133: from 132's three waves over the cloud (11-14).
@MainActor final class Build133Tests: XCTestCase {

    /// 132 (c3): three fails in 14 s with nothing done between took both allowed and ended the run at item 15.
    func testAFailRightAfterARefusedOneIsTheSameItem() {
        XCTAssertFalse(AgentLoop.failIsRepeat(refusedAt: -1, lastActed: 0, free: 0), "no fail refused yet")
        XCTAssertTrue(AgentLoop.failIsRepeat(refusedAt: 100, lastActed: 90, free: 0), "nothing done since the refusal")
        XCTAssertTrue(AgentLoop.failIsRepeat(refusedAt: 100, lastActed: 100, free: 1))
        XCTAssertFalse(AgentLoop.failIsRepeat(refusedAt: 100, lastActed: 101, free: 0), "it acted since: a new item")
        XCTAssertFalse(AgentLoop.failIsRepeat(refusedAt: 100, lastActed: 90, free: 2), "free twice in a row at most")
    }

    /// 132 (c3): 美团 shows no toast; "一份" became 10 things in its cart.
    func testAPlusInMeituanIsAnAddAndElsewhereNot() {
        XCTAssertTrue(AgentLoop.addsWithoutToast("美团外卖"))
        XCTAssertTrue(AgentLoop.addsWithoutToast("饿了么"))
        XCTAssertFalse(AgentLoop.addsWithoutToast("淘宝"), "淘宝 shows 加购成功")
        XCTAssertFalse(AgentLoop.addsWithoutToast(nil))
        XCTAssertTrue(AgentLoop.addsDish("美团披萨搜索结果已显示，最便宜的是¥9.9的披萨，我点它的绿色加号加入购物车。", in: "美团"))
        XCTAssertTrue(AgentLoop.addsDish("The cheapest pizza is ¥9.9, so I tap its green + button.", in: "美团"))
        XCTAssertFalse(AgentLoop.addsDish("点右上角的加号发起群聊", in: "微信"), "a + elsewhere is no add")
        XCTAssertFalse(AgentLoop.addsDish("点减号去掉一份", in: "美团"))
        XCTAssertTrue(AgentLoop.cartTapNote(1).contains("第1次"))
    }

    /// 132 (g4, c1): "未完整读取", "未确认" went through, and "未支付" counted as a reason.
    func testNewWordsForNotDoneAndPayingIsNoReason() {
        let goal = (1...20).map { "\($0). 第\($0)件事" }.joined(separator: "；")
        func answer(_ n: Int, _ body: String) -> String {
            (1...20).map { $0 == n ? "\(n). \(body)" : "\($0). 结果\($0)" }.joined(separator: "；")
        }
        let g4 = AgentLoop.skippedWithoutReason(answer(7, "美团外卖：已到确认订单页未支付；配送费与合计金额未完整读取"), task: goal) ?? ""
        XCTAssertTrue(g4.hasPrefix("The answer says item 7 was not done"), g4)
        let c1 = AgentLoop.skippedWithoutReason(answer(16, "淘宝购物车共79件商品，商品种类数未确认"), task: goal) ?? ""
        XCTAssertTrue(c1.hasPrefix("The answer says item 16 was not done"), c1)
        XCTAssertNil(AgentLoop.skippedWithoutReason(answer(7, "起送价还差¥15.52，无法进入确认订单页，店名未记录"), task: goal),
                     "the clause before gives the reason")
        XCTAssertNil(AgentLoop.skippedWithoutReason(answer(7, "已到确认订单页，合计¥38，未提交订单"), task: goal),
                     "stopping before paying is what was asked")
        XCTAssertNil(AgentLoop.skippedWithoutReason(answer(12, "抖音：没装抖音，未执行"), task: goal))
        XCTAssertNil(AgentLoop.skippedWithoutReason(answer(5, "因为要登录，所以没做，无记录"), task: goal), "a reason two clauses back")
        let after = AgentLoop.skippedWithoutReason(answer(9, "店名未记录，后来因为网络慢退出"), task: goal) ?? ""
        XCTAssertTrue(after.hasPrefix("The answer says item 9"), "a reason after it is not its reason: " + after)
    }

    /// 132 (c3): "2026年12月1日是星期日"; it is a Tuesday.
    func testAWeekdayForADateIsPutRight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        XCTAssertEqual(AgentLoop.rightWeekdays("3. 2026年12月1日是星期日", today: today, calendar: calendar), "3. 2026年12月1日是星期二")
        XCTAssertEqual(AgentLoop.rightWeekdays("12月1日（周日）", today: today, calendar: calendar), "12月1日（周二）")
        XCTAssertEqual(AgentLoop.rightWeekdays("11月15日星期天", today: today, calendar: calendar), "11月15日星期天", "right already")
        XCTAssertEqual(AgentLoop.rightWeekdays("1月1日是星期一", today: today, calendar: calendar), "1月1日是星期五",
                       "over half a year back: next year's (2027-01-01 is a Friday)")
        XCTAssertEqual(AgentLoop.rightWeekdays("2月30日星期一", today: today, calendar: calendar), "2月30日星期一", "no such day")
        XCTAssertEqual(AgentLoop.rightWeekdays("温度12.5度，周末", today: today, calendar: calendar), "温度12.5度，周末")
    }

    /// 133 (g7): the title read "测试群（4人" with its ）cut off; two sends were refused and the run failed.
    func testAChatTitleWithItsBracketCutOffIsStillTheGroup() {
        let task = "在微信测试群发“G7买东西做完”"
        XCTAssertEqual(AgentLoop.chatCheck(seen: "测试群（4人", task: task, steps: []), .right)
        XCTAssertEqual(AgentLoop.chatCheck(seen: "测试群(4", task: task, steps: []), .right)
        XCTAssertNotEqual(AgentLoop.chatCheck(seen: "验证群（4人", task: task, steps: []), .right)
        XCTAssertTrue(AgentLoop.goalNamesChat("测试群（4人", task: task))
    }

    /// 133 (h21): "北京明天最高X度（X换成你看到的数字）" sent as 北京明天最高12度 was reported as not sent.
    func testAMessageWithAWordToReplaceMatchesTheFilledOne() {
        let task = "帮我做这三件事：1. 天气里看北京明天的最高温；2. 在验证群发“北京明天最高X度”（X换成你看到的数字）；3. 告诉我发出去没有"
        XCTAssertEqual(AgentLoop.placeholders(task), ["X"])
        XCTAssertTrue(AgentLoop.wasSent("北京明天最高X度", ["北京明天最高12度"], task: task))
        XCTAssertFalse(AgentLoop.wasSent("北京明天最高X度", ["北京明天最高度"], task: task), "nothing in its place")
        XCTAssertFalse(AgentLoop.wasSent("北京明天最高X度", ["上海明天最高12度"], task: task))
        XCTAssertNil(AgentLoop.unverifiedNote(task: task, steps: [], sent: ["北京明天最高12度"]).flatMap { $0.contains("没有发出") ? $0 : nil })
        let city = "在验证群发“截图城市是：城市名”（城市名换成你看到的）"
        XCTAssertTrue(AgentLoop.wasSent(AgentLoop.typedKey("截图城市是：城市名"), ["截图城市是：首尔"], task: city))
        XCTAssertTrue(AgentLoop.wasSent("X2首尔温差N度", ["X2首尔温差5度"], task: "发“X2首尔温差N度”（N换成第10项算出的数字）"))
        XCTAssertFalse(AgentLoop.wasSent("G5全部做完", ["G4全部做完"], task: "发“G5全部做完”"), "no word to replace")
    }

    func testTheCursorNoteSaysWhereTheDiskIs() {
        XCTAssertTrue(AgentLoop.cursorNote(CGPoint(x: 0.25, y: 0.5)).contains("x 250, y 500"))
    }
}
