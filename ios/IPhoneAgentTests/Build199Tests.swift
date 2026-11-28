import XCTest
import UIKit
@testable import IPhoneAgent

/// 199: the hand's side of a customer's friend's kernel (「从来话到回执」) — an order heard twice not done twice, the same
/// risky order not done again blind, results done / failed / half done / not known, risky orders paced, a hand by the
/// test channel first, an app's QR page told.
@MainActor final class Build199Tests: XCTestCase {
    override func setUp() async throws {
        OrderLedger.writes = false
        OrderLedger.entries = []
        RiskPace.began = [:]
        RiskPace.nextAt = [:]
        DeviceLock.handUntil = 0
    }

    override func tearDown() async throws {
        RiskPace.began = [:]
        RiskPace.nextAt = [:]
        OrderLedger.entries = []
        OrderLedger.writes = true
    }

    func testOutcomeByItsReason() {
        XCTAssertEqual(OrderOutcome.of(ok: true, reason: ""), .done)
        XCTAssertEqual(OrderOutcome.of(ok: false, reason: "没找到输入栏"), .failed)
        XCTAssertEqual(OrderOutcome.of(ok: false, reason: OrderOutcome.partialMark + "群建好了，但群公告没设"), .partial)
        XCTAssertEqual(OrderOutcome.of(ok: false, reason: OrderOutcome.unknownMark + "点了「发送」，确认框没有消失"), .unknown)
    }

    /// Risky orders of an app a random gap apart and at most 8 an hour; a message is never held.
    func testRiskyOrdersPaced() {
        let group = ChatToolLink.Command(chat: "Echo测试群", text: "", type: 206, app: .wechat)
        let say = ChatToolLink.Command(chat: "测试群", text: "收到", type: 203, app: .wechat)
        let other = ChatToolLink.Command(chat: "Echo测试群", text: "", type: 206, app: .wework)
        XCTAssertTrue(RiskPace.due(group, at: 1000))
        RiskPace.start(group, at: 1000, random: { _ in 60 })
        XCTAssertFalse(RiskPace.due(group, at: 1030), "its gap not gone by")
        XCTAssertTrue(RiskPace.due(say, at: 1030), "a message is never held")
        XCTAssertTrue(RiskPace.due(other, at: 1030), "each app its own pace")
        XCTAssertTrue(RiskPace.due(group, at: 1061))
        for k in 1..<8 { RiskPace.start(group, at: 1061 + Double(k), random: { _ in 0 }) }
        XCTAssertFalse(RiskPace.due(group, at: 2000), "eight in the hour")
        XCTAssertTrue(RiskPace.due(group, at: 1000 + 3601))
    }

    /// An order heard again gets its result again, nothing done twice; the same risky order under another number is
    /// answered at once from the ledger, not done again.
    func testAnOrderHeardTwiceIsNotDoneTwice() throws {
        let link = ChatToolLink()
        func packet(_ id: String) -> String {
            #"{"socketType":2,"messageId":""# + id + #"","list":[{"type":206,"selectList":["蓝海乐","主人蓝海乐"],"groupName":"Echo测试群"}]}"#
        }
        _ = link.accept(packet("m1"), now: Date())
        XCTAssertEqual(link.pending.count, 1)
        _ = link.accept(packet("m1"), now: Date())
        XCTAssertEqual(link.pending.count, 1, "heard again while queued: not queued twice")
        let c = try XCTUnwrap(link.nextCommand())
        let result = try XCTUnwrap(link.finish(c, ok: true, sending: false))
        XCTAssertEqual(OrderLedger.entries.last?.outcome, .done)
        let again = link.accept(packet("m1"), now: Date())
        XCTAssertTrue(again.contains(result), "its result sent once more")
        XCTAssertTrue(link.pending.isEmpty, "not done again")
        let alike = link.accept(packet("m2"), now: Date())
        XCTAssertTrue(link.pending.isEmpty, "the same group under another number: not made again")
        XCTAssertEqual(alike.count, 2, "its receipt and its result at once")
        XCTAssertEqual(OrderLedger.entries.last?.messageId, "m2")
        XCTAssertTrue(OrderLedger.entries.last?.reason.contains("已经做过") ?? false)
    }

    /// Half done before: the same risky order is not done again blind, and says so (not known how it ended).
    func testHalfDoneIsNotDoneAgainBlind() throws {
        let link = ChatToolLink(app: .wework)
        func packet(_ id: String) -> String {
            #"{"socketType":2,"messageId":""# + id + #"","list":[{"type":206,"selectList":["蓝海乐"],"groupName":"Echo半成群"}]}"#
        }
        _ = link.accept(packet("h1"), now: Date())
        let c = try XCTUnwrap(link.nextCommand())
        link.finish(c, ok: false, reason: OrderOutcome.partialMark + "群建好了，但群公告没设", sending: false)
        XCTAssertEqual(OrderLedger.entries.last?.outcome, .partial)
        _ = link.accept(packet("h2"), now: Date())
        XCTAssertTrue(link.pending.isEmpty)
        XCTAssertEqual(OrderLedger.entries.last?.outcome, .unknown)
        XCTAssertTrue(OrderLedger.entries.last?.reason.contains("只做了一部分") ?? false)
        XCTAssertTrue(OrderLedger.lines(5).first?.hasPrefix("?") ?? false, "the ledger's line marks it")
    }

    /// User 11-28 on 199: 「一開始不是貝塞爾曲綫」 — the share check's nudge (move 8 0, sent as 80) and the search's 141 bowed
    /// 3–5 units; now a bow that shows, 25 units and more off the line, landing where it did.
    func testTinyMovesBowVisibly() throws {
        let mid: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }
        func path(_ s: String) -> [(Int, Int)] {
            let v = s.split(separator: " ").dropFirst().compactMap { Int($0) }
            var p = (0, 0), out: [(Int, Int)] = []
            for i in stride(from: 0, to: v.count - 1, by: 2) { p = (p.0 + v[i], p.1 + v[i + 1]); out.append(p) }
            return out
        }
        let nudge = path(try XCTUnwrap(CommandChannel.padCurved("move 8 0", from: (3000, 3000), span: (5854, 7626), held: false,
                                                                step: 60, pace: 30, random: mid)))
        XCTAssertGreaterThan(nudge.map { abs($0.1) }.max() ?? 0, 25, "the share check's nudge bows visibly")
        XCTAssertEqual(Double(nudge.last!.0), 80, accuracy: 2, "and goes as far as before")
        let search = path(try XCTUnwrap(PadCurve.strokeAnywhere(by: (141, 0), span: (5854, 7626), random: mid)))
        XCTAssertGreaterThan(search.map { abs($0.1) }.max() ?? 0, 25, "the search's nudge bows visibly")
        XCTAssertEqual(Double(search.last!.0), 141, accuracy: 2)
    }

    func testTheSameOrderReadsTheSame() {
        XCTAssertEqual(OrderLedger.canonical(#"{"type":206,"groupName":"G","selectList":["a","b"]}"#),
                       OrderLedger.canonical(#"{"selectList":["a","b"],"groupName":"G","type":206}"#))
        XCTAssertNotEqual(OrderLedger.canonical(#"{"type":206,"groupName":"G"}"#), OrderLedger.canonical(#"{"type":206,"groupName":"H"}"#))
    }

    /// 200 (user 11-28: 「你怎麽還是亂動個微啊」): WeChat's watch can be paused; off by default, both watched as before.
    func testWeChatWatchPausedBySwitch() {
        let d = UserDefaults.standard, kept = d.object(forKey: WatchSettings.wechatOffKey)
        defer { if let kept { d.set(kept, forKey: WatchSettings.wechatOffKey) } else { d.removeObject(forKey: WatchSettings.wechatOffKey) } }
        d.removeObject(forKey: WatchSettings.wechatOffKey)
        XCTAssertFalse(WatchSettings.wechatOff, "both watched unless the owner pauses WeChat")
        d.set(true, forKey: WatchSettings.wechatOffKey)
        XCTAssertTrue(WatchSettings.wechatOff)
    }

    func testAHandFirst() {
        XCTAssertFalse(DeviceLock.heldByHand)
        DeviceLock.hand(5)
        XCTAssertTrue(DeviceLock.heldByHand)
        DeviceLock.handUntil = 0
        XCTAssertFalse(DeviceLock.heldByHand)
    }

    /// Echo 198 11-28 18:36: WeChat's window on 「用手机微信扫码登录」.
    func testQRPageIsLoggedOut() {
        func row(_ t: String) -> [CandidatePicker.Piece] { [CandidatePicker.Piece(text: t, box: CGRect(x: 0.3, y: 0.5, width: 0.4, height: 0.02))] }
        XCTAssertTrue(XiaoLanPanes.loggedOut([row("用手机微信扫码登录"), row("在 iPad 看直播")]))
        XCTAssertFalse(XiaoLanPanes.loggedOut([row("微信"), row("蓝海乐")]))
    }
}
