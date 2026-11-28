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

    /// 201 (user 11-28: 「一定要每一步都要用貝塞爾曲綫！！！」): a short swipe or drag bends too (under 640 units it went
    /// straight), up and down toward its side, sideways down toward the hand.
    func testShortSwipesBend() throws {
        let span = (w: 3700, h: 5200)
        let mid: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }
        let side = try XCTUnwrap(PadCurve.thumbEnd(from: (0.8, 0.5), to: (0.7, 0.5), span: span, random: mid))
        XCTAssertGreaterThanOrEqual((side.y - 0.5) * Double(span.h), 40, "a short sideways drag bends down")
        // 202 (Echo 201 11-28 20:44: the ＋ panel's drag, 0.390 → 0.122 across, bent 0.021 down to 红包's row): a long
        // sideways drag bends 40–70 units, its row kept
        let panel = try XCTUnwrap(PadCurve.thumbEnd(from: (0.8, 0.747), to: (0.25, 0.747), span: (5854, 7626), random: mid))
        XCTAssertLessThanOrEqual((panel.y - 0.747) * 7626, 70.5)
        XCTAssertGreaterThanOrEqual((panel.y - 0.747) * 7626, 39.5)
        let up = try XCTUnwrap(PadCurve.thumbEnd(from: (0.3, 0.55), to: (0.3, 0.45), span: span, random: mid))
        XCTAssertGreaterThanOrEqual((0.3 - up.x) * Double(span.w), 40, "a short one on the left bends left")
    }

    /// 202 (Echo 201 11-28 20:48: X2's second line 「发到测试群」 not read, and the newest line at 0.90 of the window over the
    /// input bar left out by 0.86): my message found by its start read, the line to quote found that low.
    func testShortReadAndLowLineFound() {
        func row(_ t: String, _ cx: Double, _ cy: Double, _ w: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: cx - w / 2, y: cy - 0.009, width: w, height: 0.018))]
        }
        let rows = [row("Echo201测试X1：这句等一", 0.49, 0.47, 0.6), row("下会撤回", 0.29, 0.494, 0.19),
                    row("Echo201测试X2：这句要转", 0.49, 0.90, 0.6)]
        let want = "Echo201测试X2：这句要转发到测试群"
        XCTAssertEqual(XiaoLanGroups.mineLine(rows, want).map { Double($0.y) } ?? 0, 0.90, accuracy: 0.002, "its start read is enough")
        XCTAssertNil(XiaoLanGroups.mineLine([row("Echo201", 0.49, 0.90, 0.6)], want), "too short a start is not it")
        XCTAssertEqual(XiaoLanMediaFind.quoteSpot(rows, quote: want).map { Double($0.y) } ?? 0, 0.90, accuracy: 0.002, "found that low")
    }

    /// 202 (Echo 201 11-28: the ＋ panel's sideways drag narrowed WeChat's window, twice): its pages turned by its dots —
    /// two grey dots on the panel's 246 at the window's foot (h03c: 0.477 and 0.520 across, 0.985 down).
    func testPanelPageDots() throws {
        let size = CGSize(width: 400, height: 800)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 246 / 255, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 120 / 255, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 0.477 * 400 - 4, y: 0.985 * 800 - 4, width: 8, height: 8))
            UIColor(white: 190 / 255, alpha: 1).setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 0.520 * 400 - 4, y: 0.985 * 800 - 4, width: 8, height: 8))
        }
        let dots = XiaoLanGroups.pageDots(try XCTUnwrap(WatchOCR.Pixels(try XCTUnwrap(image.pngData()))))
        XCTAssertEqual(dots.count, 2)
        XCTAssertEqual(Double(dots.first?.x ?? 0), 0.477, accuracy: 0.008)
        XCTAssertEqual(Double(dots.last?.x ?? 0), 0.520, accuracy: 0.008)
        let blank = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 246 / 255, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        XCTAssertTrue(XiaoLanGroups.pageDots(try XCTUnwrap(WatchOCR.Pixels(try XCTUnwrap(blank.pngData())))).isEmpty, "no dots, no page turned")
    }

    /// 202 (user 11-28: 「你要能記住你爬的東西」): what 爬樓 and 跟圈 read is kept, each line once.
    func testReadsKeptOnce() {
        ReadStore.writes = false
        ReadStore.items = []
        defer { ReadStore.items = []; ReadStore.writes = true }
        let one = ReadItem(kind: "爬楼", app: "wechat", place: "测试群", key: "蓝海乐\u{2}1\u{2}", readAt: 1, time: "", sender: "蓝海乐", text: "1")
        XCTAssertEqual(ReadStore.add([one, one]), 1)
        XCTAssertEqual(ReadStore.add([one]), 0, "read again, not kept twice")
        var two = one
        two.key = "蓝海乐\u{2}2\u{2}"
        two.text = "2"
        XCTAssertEqual(ReadStore.add([two]), 1)
        XCTAssertEqual(ReadStore.lines(5).first, "爬楼 · 测试群｜蓝海乐：2")
    }

    /// 202 (Echo 201 11-28 21:00): a 公众号 link card — summary only a little smaller, a colour picture at its right — is a
    /// card by its picture; WeCom's 名片 read 「•微信 方舱科技」 is 方舱科技's.
    func testLinkCardByItsPictureAndWeComCardName() {
        let card: [(text: String, height: Double)] = [("加拿大KiniMobile黑五套", 0.018), ("餐优惠来了！换个好套…", 0.018),
                                                      ("黑五来了每月CA$25起", 0.015), ("易博通eSender", 0.012)]
        XCTAssertEqual(XiaoLanMediaFind.cardLine(card, spanHeight: 0.12, quoted: false, picture: true),
                       "[链接] 加拿大KiniMobile黑五套餐优惠来了！换个好套…")
        XCTAssertNil(XiaoLanMediaFind.cardLine(card, spanHeight: 0.12, quoted: false), "no picture, sizes too close: no card")
        XCTAssertEqual(XiaoLanMediaFind.cardLine([("•微信", 0.014), ("方舱科技", 0.020), ("个人名片", 0.014)], spanHeight: 0.1, quoted: false),
                       "[名片] 方舱科技")
    }

    /// 202 (Echo 201 11-28 21:14): the line to forward or quote is never a grey quote box's words under a later reply.
    func testQuoteSpotSkipsQuoteBoxes() throws {
        let size = CGSize(width: 400, height: 800)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 149 / 255, green: 236 / 255, blue: 105 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0.3 * 400, y: 0.28 * 800, width: 0.5 * 400, height: 0.05 * 800))  // my bubble
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(try XCTUnwrap(image.pngData())))
        func row(_ t: String, _ y: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: 0.35, y: y - 0.009, width: 0.3, height: 0.018))]
        }
        let rows = [row("Echo转发和引用用这句", 0.30), row("转发和引用用这句", 0.60)]  // the second on the grey: a quote box's
        XCTAssertEqual(XiaoLanMediaFind.quoteSpot(rows, quote: "Echo转发和引用用这句", px: px).map { Double($0.y) } ?? 0, 0.30, accuracy: 0.002)
        XCTAssertEqual(XiaoLanMediaFind.quoteSpot(rows, quote: "Echo转发和引用用这句").map { Double($0.y) } ?? 0, 0.60, accuracy: 0.002,
                       "without the pixels the lowest words, as before")
    }

    func testTheSameOrderReadsTheSame() {
        XCTAssertEqual(OrderLedger.canonical(#"{"type":206,"groupName":"G","selectList":["a","b"]}"#),
                       OrderLedger.canonical(#"{"selectList":["a","b"],"groupName":"G","type":206}"#))
        XCTAssertNotEqual(OrderLedger.canonical(#"{"type":206,"groupName":"G"}"#), OrderLedger.canonical(#"{"type":206,"groupName":"H"}"#))
        // 202: the messageId inside an order (as the server sends it) is no part of it
        XCTAssertEqual(OrderLedger.canonical(#"{"type":206,"groupName":"G","messageId":"m1"}"#),
                       OrderLedger.canonical(#"{"messageId":"m2","groupName":"G","type":206}"#))
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

    /// 202 (Echo 201 11-28 21:27: the ＋ panel's lower tiles taken for the input field; 收藏, 礼物, 永恒玫瑰 pressed): the
    /// panel's top lies between the bar and its first row of tiles (11-28 20:47, window fractions: bar 0.689–0.737,
    /// tiles 0.765–0.832, labels 0.851 and 0.951), so the field is looked for above the tiles only.
    /// 202 (Echo 201 11-28 20:55): WeCom's notice after a 撤回 — its 「我知道了」 across the middle — is found; a 「知道了」
    /// bubble at a chat's side is not.
    func testGotItIsANoticeButton() {
        func p(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x - 0.06, y: y - 0.01, width: 0.12, height: 0.02))
        }
        let notice = [[p("和微信联系人聊天，你可以撤", 0.5, 0.25)], [p("回2分钟内发送的消息", 0.5, 0.28)], [p("我知道了", 0.5, 0.34)]]
        XCTAssertEqual(XiaoLanGroups.gotIt(notice)?.y ?? 0, 0.34, accuracy: 0.001)
        XCTAssertNil(XiaoLanGroups.gotIt([[p("知道了", 0.85, 0.6)], [p("知道了", 0.18, 0.7)]]))
    }

    /// 202 (Echo 201 11-28 20:52, WeChat): the long-press menu over my own lines naming its words — 「…转发和引用用这句」
    /// high up, 「…引用回复」 lower — is still a menu, and its 撤回 found.
    func testMenuOverLinesNamingItsWords() throws {
        func p(_ t: String, _ x: Double, _ y: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: x - 0.05, y: y - 0.01, width: 0.1, height: 0.02))]
        }
        let rows = [p("Echo201全测A4：转发和引用用这句", 0.5, 0.25), p("复制", 0.13, 0.80), p("转发", 0.33, 0.80),
                    p("收藏", 0.52, 0.80), p("撤回", 0.70, 0.80), p("多选", 0.88, 0.80), p("Echo201全测A6：引用回复", 0.5, 0.83),
                    p("引用", 0.13, 0.86), p("提醒", 0.33, 0.86)]
        let band = try XCTUnwrap(XiaoLanMediaFind.menuBand(rows))
        XCTAssertTrue(band.contains(0.80) && band.contains(0.86))
        XCTAssertFalse(band.contains(0.25))
        XCTAssertNil(XiaoLanMediaFind.menuBand([p("Echo201全测A4：转发和引用用这句", 0.5, 0.25), p("Echo201全测A6：引用回复", 0.5, 0.6)]))
    }

    /// 202 (follow, Echo 201 11-28 22:05): the friend's name under the avatar on 聊天详情, read whole or a mark off.
    func testMemberNameOnChatDetails() {
        func p(_ t: String, _ y: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: 0.1, y: y - 0.008, width: 0.1, height: 0.016))]
        }
        XCTAssertNotNil(XiaoLanGroups.memberName([p("聊天详情", 0.05), p("蓝海乐", 0.183), p("查找聊天内容", 0.25)], "蓝海乐"))
        XCTAssertNotNil(XiaoLanGroups.memberName([p("蓝海乐.", 0.183)], "蓝海乐"))
        XCTAssertNil(XiaoLanGroups.memberName([p("查找聊天内容", 0.25), p("蓝海乐", 0.05)], "蓝海乐"))
        XCTAssertNil(XiaoLanGroups.memberName([p("主人蓝海乐", 0.183)], "蓝海乐"), "two marks more: another")
    }

    /// 202 (Echo 201 11-28 22:13, WeCom): the sheet asking to delete a message is cancelled by its 取消; a chat with a
    /// 「取消」 line and no such question is left alone.
    func testActionSheetIsCancelled() {
        func p(_ t: String, _ y: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: 0.3, y: y - 0.01, width: 0.4, height: 0.02))]
        }
        let sheet = [p("Echo201补测D1：企微私聊，等一下撤回", 0.3), p("此消息删除后将无法撤回，聊天成员依旧可见。", 0.80),
                     p("删除消息", 0.85), p("撤回消息", 0.90), p("取消", 0.96)]
        XCTAssertEqual(XiaoLanPanes.actionSheetCancel(sheet)?.y ?? 0, 0.96, accuracy: 0.001)
        XCTAssertNil(XiaoLanPanes.actionSheetCancel([p("好的", 0.6), p("取消", 0.7)]))
    }

    /// 202 (Echo 201 11-28 22:16): a WeCom group's title with its logo and a 「…」 after the head count is the group's;
    /// (182's rule — one mark after the head count is the logo — stays as it was.)
    func testTitleWithMarksAfterTheHeadCount() {
        XCTAssertEqual(WatchOCR.titled("Echo201测试群企微（3）◎…").name, "Echo201测试群企微")
        XCTAssertTrue(WatchOCR.titled("Echo201测试群企微（3）◎…").group)
        XCTAssertEqual(WatchOCR.titled("企微测试群（7）Q").name, "企微测试群")
    }

    /// 202 (Echo 201 11-28 22:53, WeCom): a PDF card whose 「.pdf」 was read 「.paf」 is still a file card.
    func testPdfReadAsPaf() {
        XCTAssertEqual(XiaoLanMediaFind.fileExtension("paf"), "pdf")
        XCTAssertTrue(XiaoLanMediaFind.cardText("研判.paf"))
        XCTAssertEqual(XiaoLanMediaFind.fileKey("研判.paf"), XiaoLanMediaFind.fileKey("研判.pdf"))
    }

    /// 202 (Echo 201 11-28 23:45): a video's 「[视频] 0:03」 line — on its thumbnail, no avatar beside it, in no bubble — is
    /// kept as theirs; other words there (a photo's) are still none.
    func testVideoLineOnItsThumbnailIsKept() throws {
        let size = CGSize(width: 400, height: 800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 237 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.25, alpha: 1).setFill()
            ctx.fill(CGRect(x: 80, y: 300, width: 140, height: 240))  // the thumbnail
        }
        let px = try XCTUnwrap(image.jpegData(compressionQuality: 0.9).flatMap { WatchOCR.Pixels($0) })
        let box = CGRect(x: 0.45, y: 0.64, width: 0.08, height: 0.012)  // its length label, on the thumbnail
        let out = WatchOCR.bySide([WatchOCR.Piece(text: "[视频] 0:03", box: box, kind: .theirs),
                                   WatchOCR.Piece(text: "9Wet", box: box.offsetBy(dx: -0.1, dy: -0.1), kind: .theirs)], px)
        XCTAssertEqual(out.first { $0.text.hasPrefix("[视频]") }?.kind, .theirs)
        XCTAssertEqual(out.first { $0.text == "9Wet" }?.kind, .other)
    }

    func testPlusPanelTopIsOverItsTiles() throws {
        func p(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x - 0.03, y: y - 0.009, width: 0.06, height: 0.018))
        }
        let rows = [[p("照片", 0.15, 0.851), p("拍摄", 0.38, 0.851), p("视频通话", 0.62, 0.851), p("位置", 0.86, 0.851)],
                    [p("红包", 0.15, 0.951), p("礼物", 0.38, 0.951), p("转账", 0.62, 0.951), p("收藏", 0.86, 0.951)]]
        let top = try XCTUnwrap(XiaoLanGroups.plusPanelTop(rows))
        XCTAssertGreaterThan(top, 0.737)
        XCTAssertLessThan(top, 0.765)
        XCTAssertNil(XiaoLanGroups.plusPanelTop([[p("蓝海乐", 0.3, 0.9)], [p("Echo201全测A6：引用回复", 0.5, 0.8)]]))
    }
}
