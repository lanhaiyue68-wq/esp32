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

    func testRereadLanguagesStartWithSimplifiedChinese() {
        XCTAssertEqual(CandidatePicker.rereadLanguages.first, "zh-Hans")
    }
}
