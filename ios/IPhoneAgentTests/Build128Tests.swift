import XCTest
@testable import IPhoneAgent

/// Build 128: from 127's eight 20-task days on the phone (11-12).
@MainActor final class Build128Tests: XCTestCase {

    /// 127 (g8): 购物车 → ×2 → "−" (which opened the item again), ten times over.
    func testTheSameRoundOfTapsTwiceIsRefused() {
        func tap(_ x: Double, _ y: Double) -> JObject { ["action": .str("tap"), "x": .num(x), "y": .num(y)] }
        let round = [tap(845, 88), tap(908, 284), tap(715, 293)]
        XCTAssertTrue(AgentLoop.repeatsRound(round + Array(round.prefix(2)), next: tap(715, 293)))
        XCTAssertFalse(AgentLoop.repeatsRound(round, next: tap(845, 88)))
        XCTAssertFalse(AgentLoop.repeatsRound(round + [["action": .str("type"), "text": .str("x")]] + Array(round.prefix(2)),
                                              next: tap(715, 293)), "typing between: no round")
        XCTAssertFalse(AgentLoop.repeatsRound([tap(100, 100), tap(900, 900), tap(100, 100)], next: tap(900, 900)),
                       "a back and forth of two spots is allowed twice")
    }

    /// 127 (g4): "美团外卖" was skipped as "not installed": it is a part of 美团.
    func testAPartOfAnAppOpensTheApp() {
        XCTAssertEqual(AgentLoop.hostApp("美团外卖"), "美团")
        XCTAssertEqual(AgentLoop.hostApp("美團外賣"), "美团")
        XCTAssertEqual(AgentLoop.hostApp("视频号"), "微信")
        XCTAssertEqual(AgentLoop.hostApp("饿了么外卖"), "饿了么")
        XCTAssertNil(AgentLoop.hostApp("京东"))
        XCTAssertNil(AgentLoop.hostApp("外卖"))
    }

    /// 127 (g2): 深圳宝安国际机场 typed in 高德 was held as a message, then a search in 淘宝: the run failed.
    func testATextTypedWhereOneOnlySearchesIsNoMessage() {
        for app in ["高德地图", "淘宝", "淘寶", "拼多多", "美团", "Safari", "京东"] {
            XCTAssertTrue(AgentLoop.inLocalApp([["action": .str("open"), "app": .str(app)]]), app)
        }
        XCTAssertFalse(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("抖音")]]), "a comment there goes out")
        XCTAssertFalse(AgentLoop.inLocalApp([["action": .str("open"), "app": .str("微信")]]))
    }

    /// 127 (g1): a part holding five of twenty things was "not getting on" at 20 steps with nothing failed.
    func testAPartWithMoreThingsHasMoreSteps() {
        XCTAssertEqual(AgentLoop.partSteps(for: "打开天气看深圳今天的最高温"), 20)
        XCTAssertEqual(AgentLoop.partSteps(for: "9. 高德查到深圳北站多久；10. 日历看今天；11. 淘宝待收货；12. 抖音搜索；13. Safari 搜索"), 60)
        XCTAssertEqual(AgentLoop.partSteps(for: "5. 拼多多第一个商品 29.9 元；6. 算差价"), 30, "a price is no item")
        XCTAssertEqual(AgentLoop.partSteps(for: (1...20).map { "\($0). 做一件事" }.joined(separator: "；")), 80)
    }
}
