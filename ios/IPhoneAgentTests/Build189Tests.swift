import XCTest
import UIKit
@testable import IPhoneAgent

/// 189 (user 11-27 「還有辦法壓縮時間嗎…我在個微群裡發的是好的嗎，他回的是好嗎」): a QA reply that failed before a word
/// was typed goes once more, first in its turn (N16); a Chinese line narrower in words than in width is read again (N17).
@MainActor final class Build189Tests: XCTestCase {
    func testAnOrderHandedBackGoesFirstAgainInItsTurn() throws {
        let wechat = ChatToolLink(), wework = ChatToolLink(app: .wework)
        func packet(_ id: String) -> String {
            #"{"socketType":2,"messageId":""# + id + #"","list":[{"type":203,"titleList":["测试群"],"receivedContent":"收到"}]}"#
        }
        _ = wework.accept(packet("a1"), now: Date())
        _ = wechat.accept(packet("b1"), now: Date())
        _ = wework.accept(packet("a2"), now: Date())
        let first = try XCTUnwrap(PaneTurns.next(firsts: [wechat.firstTurn, wework.firstTurn], asking: [nil, nil]))
        let c = try XCTUnwrap([wechat, wework][first.index].take(turn: first.turn))
        XCTAssertEqual(c.messageId, "a1")
        wework.retry(c)  // nothing typed: handed back
        var done: [String] = []
        while let next = PaneTurns.next(firsts: [wechat.firstTurn, wework.firstTurn], asking: [nil, nil]) {
            done.append(try XCTUnwrap([wechat, wework][next.index].take(turn: next.turn)).messageId)
        }
        XCTAssertEqual(done, ["a1", "b1", "a2"], "the order handed back keeps its turn: first again")
    }

    func testFinishedOrderLeavesNoTurnBehind() throws {
        let link = ChatToolLink()
        _ = link.accept(#"{"socketType":2,"messageId":"x1","list":[{"type":203,"titleList":["测试群"],"receivedContent":"收到"}]}"#, now: Date())
        let turn = try XCTUnwrap(link.firstTurn)
        let c = try XCTUnwrap(link.take(turn: turn))
        link.finish(c, ok: true)
        XCTAssertNil(link.firstTurn)
        XCTAssertTrue(ChatToolLink.isQA(ChatToolLink.qaPrefix + "abc"))
        XCTAssertFalse(ChatToolLink.isQA("x1"))
    }

    func testWideCharactersAndOrder() {
        XCTAssertTrue("好的嗎【】：？".allSatisfy(CandidatePicker.isWide))
        XCTAssertFalse(CandidatePicker.isWide("a"))
        XCTAssertFalse(CandidatePicker.isWide("1"))
        XCTAssertTrue(CandidatePicker.keepsInOrder(Array("好嗎"), Array("好的嗎")))
        XCTAssertFalse(CandidatePicker.keepsInOrder(Array("好嗎"), Array("嗎好的")))
        XCTAssertFalse(CandidatePicker.keepsInOrder(Array("好嗎"), Array("好的")))
    }

    /// A white strip `w`×`h` px, as Vision's crop.
    func strip(_ w: Int, _ h: Int) throws -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { r in
            r.cgContext.setFillColor(UIColor.white.cgColor)
            r.cgContext.fill(CGRect(x: 0, y: 0, width: w, height: h))
        }
        return try XCTUnwrap(image.cgImage)
    }

    func testALineAsWideAsItsWordsIsNotReadAgain() throws {
        let crop = try strip(400, 100)
        // 「你們好嗎」 as measured 11-27: 92×25.6 px for 4 characters (0.90 a character)
        let box = CGRect(x: 0.1, y: 0.3, width: 92.0 / 400, height: 25.6 / 100)
        XCTAssertNil(CandidatePicker.reread(crop, box: box, read: "你們好嗎"))
        // words with Latin letters, digits or spaces are never read again
        XCTAssertNil(CandidatePicker.reread(crop, box: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.25), read: "188个微0140"))
        XCTAssertNil(CandidatePicker.reread(crop, box: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.25), read: "好 嗎"))
    }

    func testAWiderLineReadAgainOnABlankStripKeepsTheFirstReading() throws {
        // 「好嗎」 in a box three characters wide (11-27: 70×24.3 px): read again; a blank strip gives nothing better
        let crop = try strip(400, 100)
        let box = CGRect(x: 0.1, y: 0.3, width: 70.0 / 400, height: 24.3 / 100)
        XCTAssertNil(CandidatePicker.reread(crop, box: box, read: "好嗎"))
    }

    /// N21: a screen that does not go on from the history; an old line misread this time is above lines read and mine.
    func testOnlyWhatFollowsTheLastLineReadOrMineIsNew() {
        typealias L = WatchReport.Line
        let known: Set<String> = [XiaoLanSelf.plain("好的吗")]
        let lines = [L(sender: "主人蓝海乐", text: "遠好嗎", mine: false),  // 「還好嗎」, answered at 11:37, misread
                     L(sender: "", text: "【模拟服务器】收到：還好嗎", mine: true),
                     L(sender: "主人蓝海乐", text: "好的吗", mine: false),
                     L(sender: "", text: "【模拟服务器】收到：好的吗", mine: true),
                     L(sender: "主人蓝海乐", text: "我在等你我回我", mine: false)]
        XCTAssertEqual(XiaoLanSelf.unseen(lines, known: known).map(\.text), ["我在等你我回我"])
        // nothing read before and nothing mine on it: every line, as before
        let fresh = [L(sender: "甲", text: "第一句", mine: false), L(sender: "乙", text: "第二句", mine: false)]
        XCTAssertEqual(XiaoLanSelf.unseen(fresh, known: []).map(\.text), ["第一句", "第二句"])
        // a line read before at the bottom: nothing new
        XCTAssertEqual(XiaoLanSelf.unseen(Array(lines.prefix(3)), known: known).map(\.text), [])
    }

    /// N22: a reply quoting the tester's words made the tester the owner's other account.
    func testAnAccountIsLearnedOnlyFromTheOwnersWholeWords() {
        let sent = [XiaoLanSelf.Sent(app: .wework, chat: "企微测试群", text: "【模拟服务器】收到：我在等你我回我", at: 100)]
        XCTAssertTrue(XiaoLanSelf.sentByOther("我在等你我回我", chat: "企微测试群", app: .wechat, sent: sent, now: 110))
        XCTAssertFalse(XiaoLanSelf.sentByOther("我在等你我回我", chat: "企微测试群", app: .wechat, sent: sent, now: 110, whole: true))
        XCTAssertTrue(XiaoLanSelf.sentByOther("【模拟服务器】收到：我在等你我回我", chat: "企微测试群", app: .wechat, sent: sent, now: 110, whole: true))
        XCTAssertFalse(XiaoLanSelf.sentByOther("好的", chat: "企微测试群", app: .wechat,
                                               sent: [XiaoLanSelf.Sent(app: .wework, chat: "企微测试群", text: "好的", at: 100)], now: 110, whole: true))
        XCTAssertEqual(XiaoLanSelf.learnedKey, "xiaolanSelvesV2", "names learned before 189 are dropped")
    }

    /// N24: the quick bar's ¥ on a line of its own is no message; a customer's words with ¥ in them still are.
    func testTheQuickBarsIconAloneIsNoText() {
        XCTAssertEqual(WatchOCR.withoutUIWords("¥"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("• ●"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("谢谢"), "谢谢")
        XCTAssertEqual(WatchOCR.withoutUIWords("¥299 一个月吗"), "¥299 一个月吗")
    }

    /// N27/N28: a voice note's words are what is new right under it, not an older line scrolled into view or the bar.
    func testAVoiceNotesWordsAreWhatIsNewUnderIt() {
        func p(_ t: String, _ y: Double, x: Double = 0.2) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y - 0.008, width: 0.2, height: 0.016))
        }
        let before = [p("在吗", 0.40), p("9\"", 0.60)]
        let after = [p("我们按套餐收费：基础版", 0.30, x: 0.5), p("在吗", 0.35), p("9\"", 0.55),
                     p("我想请问一下有没有优惠", 0.60), p("G+在这", 0.95)]
        XCTAssertEqual(XiaoLanMediaFind.added(before: before, after: after, below: 0.2, seconds: 9), "我想请问一下有没有优惠")
        XCTAssertEqual(XiaoLanMediaFind.added(before: before, after: after, below: 0.2),
                       "我们按套餐收费：基础版我想请问一下有没有优惠G+在这", "without the note's length: everything new, as before")
        XCTAssertEqual(XiaoLanMediaFind.noteSeconds("[语音] 9\""), 9)
        XCTAssertNil(XiaoLanMediaFind.noteSeconds("[语音]"))
    }

    /// N30: a note WeCom already turned into words (as read 11-27 12:40: 「•））2''」, 「有优惠吗？」, 「转換完成」).
    func testANoteAlreadyTurnedIntoWordsIsReadAsItIs() {
        func p(_ t: String, _ y: Double, x: Double = 0.6) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y - 0.008, width: 0.1, height: 0.016))
        }
        let pieces = [p("•））2''", 0.459), p("有优惠吗？", 0.501), p("转換完成", 0.525), p("您好！我是小蓝助手", 0.577, x: 0.75)]
        XCTAssertEqual(XiaoLanMediaFind.convertedWords(pieces, seconds: 2), "有优惠吗？")
        XCTAssertNil(XiaoLanMediaFind.convertedWords(Array(pieces.prefix(2)), seconds: 2), "no 完成 mark: not turned yet")
        XCTAssertNil(XiaoLanMediaFind.convertedWords(pieces, seconds: 5), "another note's length")
    }

    /// N25: a draft's preview with full-width brackets is no line.
    func testADraftWithFullWidthBracketsIsNoLine() {
        XCTAssertEqual(WatchReport.previewBody("［草稿］你好"), "")
        XCTAssertEqual(WatchReport.previewBody("[草稿]你好"), "")
        XCTAssertEqual(WatchReport.previewBody("蓝海乐：你好"), "蓝海乐：你好")
    }

    func testRereadLanguagesStartWithSimplifiedChinese() {
        XCTAssertEqual(CandidatePicker.rereadLanguages.first, "zh-Hans")
    }
}
