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

    /// N36: WeChat's bar with only ~7 px of its grey over the field (12:58); a white bubble over it is still no field.
    func testTheFieldUnderAThinBarIsFoundAndABubbleIsNot() throws {
        func window(bar: Bool) -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 456, height: 1145), format: format).jpegData(withCompressionQuality: 0.95) { r in
                let c = r.cgContext
                c.setFillColor(gray: 237 / 255, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 456, height: 1145))  // the chat
                c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 40, y: 900, width: 360, height: 45))  // a white bubble
                guard bar else { return }
                c.setFillColor(gray: 246 / 255, alpha: 1); c.fill(CGRect(x: 0, y: 962, width: 456, height: 183))  // the bar
                c.setFillColor(gray: 1, alpha: 1); c.fill(CGRect(x: 50, y: 970, width: 370, height: 168))  // its field, 8 px under its top
            }
        }
        let field = try XCTUnwrap(XiaoLanPanes.inputField(try XCTUnwrap(WatchOCR.Pixels(window(bar: true)))))
        XCTAssertGreaterThan(Double(field.y), 0.84, "the field, not the bubble over it")
        XCTAssertNil(XiaoLanPanes.inputField(try XCTUnwrap(WatchOCR.Pixels(window(bar: false)))), "a bubble on the chat's grey is no field")
    }

    /// N32: one link read three ways is one link; another link is not.
    func testALinkReadALittleDifferentlyIsTheSameLink() throws {
        let a = try XCTUnwrap(XiaoLanMediaFind.linkKey("https://www.baidu.com"))
        let b = try XCTUnwrap(XiaoLanMediaFind.linkKey("[链接] https://www.baiau.com"))
        let c = try XCTUnwrap(XiaoLanMediaFind.linkKey("https://www.bardu.com"))
        XCTAssertEqual(a, "baiducom")
        XCTAssertTrue(XiaoLanMediaFind.sameLink(a, b))
        XCTAssertTrue(XiaoLanMediaFind.sameLink(a, c))
        XCTAssertFalse(XiaoLanMediaFind.sameLink(a, try XCTUnwrap(XiaoLanMediaFind.linkKey("https://www.taobao.com"))))
        XCTAssertNil(XiaoLanMediaFind.linkKey("你好"))
    }

    /// N29 (190): an address the chat would not open goes to Safari by x-safari-, 「www.…」 with https://; Safari is
    /// known by the domain at the top, read loosely, and not by a chat's title.
    func testAnUnopenedLinkGoesToSafari() throws {
        XCTAssertEqual(XiaoLanMediaFind.safariURL("www.baidu.com")?.absoluteString, "x-safari-https://www.baidu.com")
        XCTAssertEqual(XiaoLanMediaFind.safariURL("https://v.douyin.com/abc/")?.absoluteString, "x-safari-https://v.douyin.com/abc/")
        XCTAssertEqual(XiaoLanMediaFind.safariURL("http://a.cn/x")?.absoluteString, "x-safari-http://a.cn/x")
        XCTAssertNil(XiaoLanMediaFind.safariURL(""))
        XCTAssertNil(XiaoLanMediaFind.safariURL("www.baidu.com 看看"))
        func top(_ t: String, y: Double = 0.03) -> [[CandidatePicker.Piece]] {
            [[CandidatePicker.Piece(text: t, box: CGRect(x: 0.4, y: y, width: 0.2, height: 0.02))]]
        }
        XCTAssertTrue(XiaoLanMediaFind.safariShown(top("baidu.com"), link: "www.baidu.com"))
        XCTAssertTrue(XiaoLanMediaFind.safariShown(top("m.baidu.com"), link: "https://www.baidu.com"))
        XCTAssertTrue(XiaoLanMediaFind.safariShown(top("baiau.com"), link: "www.baidu.com"), "a letter misread")
        XCTAssertTrue(XiaoLanMediaFind.safariShown(top("douyin.com"), link: "https://v.douyin.com/abc/"))
        XCTAssertFalse(XiaoLanMediaFind.safariShown(top("蓝海乐"), link: "www.baidu.com"))
        XCTAssertFalse(XiaoLanMediaFind.safariShown(top("taobao.com"), link: "www.baidu.com"))
        XCTAssertFalse(XiaoLanMediaFind.safariShown(top("baidu.com", y: 0.5), link: "www.baidu.com"), "not at the top")
        XCTAssertFalse(XiaoLanMediaFind.safariShown(top("baidu.com")), "no link given: only Safari's name")
        XCTAssertEqual(Double(try XCTUnwrap(XiaoLanMediaFind.copyItem(top("复制链接"))).x), 0.5, accuracy: 0.001)
        XCTAssertNil(XiaoLanMediaFind.copyItem(top("百度一下")))
    }

    /// N37/N38 (191): the owner's four shares as the iPad read them (11-27 15:20): Douyin's folded share is a link, each
    /// job finds its own line, the folded ones their 「更多」.
    func testSharesFindTheirOwnLinesAndFolds() throws {
        func p(_ t: String, _ y: Double, _ w: Double = 0.55, x: Double = 0.2) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: 0.02))
        }
        let rows: [[CandidatePicker.Piece]] = [
            [p("1.07复制打开抖音，看看", 0.12)], [p("【dontbesilent聊赚钱.更多", 0.142)],
            [p("https://xhslink.cn/o/7CHZf", 0.2)], [p("N6alKN拷走链接，去【小红", 0.222)], [p("书】逛逛分享～", 0.244, 0.3)],
            [p("https://v.kuaishou.com/nq2", 0.305)], [p("LENRb...更多", 0.327, 0.25)],
        ]
        XCTAssertEqual(XiaoLanMediaFind.kind(of: "1.07复制打开抖音，看看【dontbesilent聊赚钱.更多"), .link)
        XCTAssertNil(XiaoLanMediaFind.kind(of: "我在小红书上看到你们的"))
        XCTAssertEqual(XiaoLanMediaFind.tag("[视频号] 露露lulu0517"), .image)
        let ks = try XCTUnwrap(XiaoLanMediaFind.linkLine(rows, text: "[链接] https://V.kuaishou.com/nq2LENRD..更多", rank: 0))
        XCTAssertTrue(ks.text.contains("kuaishou"))
        let xhs = try XCTUnwrap(XiaoLanMediaFind.linkLine(rows, text: "https://xhslink.cn/o/7CHZfN6qlKN 拷走链接", rank: 0))
        XCTAssertTrue(xhs.text.contains("xhslink"), "the job's own line, not the newest")
        let dy = try XCTUnwrap(XiaoLanMediaFind.linkLine(rows, text: "1.07复制打开抖音，看看【dontbesilent聊赚钱.更多", rank: 0))
        XCTAssertTrue(dy.text.contains("抖音"))
        let more = try XCTUnwrap(XiaoLanMediaFind.moreSpot(rows, from: ks))
        XCTAssertEqual(more.y, 0.337, accuracy: 0.001)
        XCTAssertGreaterThan(more.x, 0.4, "on 「更多」 at the line's end")
        XCTAssertNotNil(XiaoLanMediaFind.moreSpot(rows, from: dy))
        XCTAssertNil(XiaoLanMediaFind.moreSpot(rows, from: xhs), "Xiaohongshu's is not folded")
        XCTAssertGreaterThan(XiaoLanMediaFind.addressStart(p("最... https://v.douyin.com/", 0.5, 0.8, x: 0.1)).x, 0.25)
    }

    /// 191: Douyin's app-only page, the ··· menu's 「用默认浏览器打开」, Xiaohongshu's video page, a 视频号 card and player.
    func testPagesMenusAndChannelsCards() throws {
        func p(_ t: String, _ y: Double, x: Double = 0.2, w: Double = 0.3) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: 0.02))
        }
        XCTAssertTrue(XiaoLanMediaFind.appOnlyPage([[p("抱歉出错了", 0.55)], [p("请尝试在抖音内观看", 0.58)], [p("打开抖音", 0.66)]]))
        XCTAssertFalse(XiaoLanMediaFind.appOnlyPage([[p("百度一下，你就知道", 0.3)]]))
        XCTAssertEqual(XiaoLanMediaFind.defaultBrowserItem([[p("转发给朋友", 0.49), p("用默认", 0.49, x: 0.89, w: 0.1)]])?.text, "用默认")
        let note = [[p("梨形身材的茶茶", 0.53), p("关注", 0.53, x: 0.45, w: 0.06)], [p("发弹幕", 0.65)], [p("App内打开", 0.95)]]
        let play = try XCTUnwrap(XiaoLanMediaFind.pageVideoSpot(note))
        XCTAssertTrue((0.2...0.4).contains(Double(play.y)))
        XCTAssertNil(XiaoLanMediaFind.pageVideoSpot([[p("百度一下", 0.3)]]))
        let card = CGRect(x: 0.17, y: 0.37, width: 0.37, height: 0.18)
        let author = try XCTUnwrap(XiaoLanMediaFind.cardAuthor([[p("♥露露lulu0517", 0.525, x: 0.17, w: 0.28)]], in: card))
        XCTAssertEqual(author, "露露lulu0517")
        XCTAssertTrue(XiaoLanMediaFind.channelsPlayer([[p("露露lulu0517", 0.93)]], author: "W露露lulu0517"))
        XCTAssertFalse(XiaoLanMediaFind.channelsPlayer([[p("露露lulu0517", 0.3)]], author: author), "the author at the bottom")
    }

    /// 191 (user 11-27: 「自動切換這個模型」): Seed-2.0-mini's stronger sibling on the same key is Seed-2.1-lite (its
    /// newest), never a video maker or itself; a doubtful answer sends the look to the other model.
    func testTheStrongerModelAndADoubtfulAnswer() {
        let listed = ["doubao-seedance-2-5-flash-261115", "doubao-seed-2-0-mini-260428", "doubao-seed-2-1-lite-260801",
                      "doubao-seed-2-1-lite-260915", "doubao-seed-2-0-lite-260301", "doubao-seedream-5-0-260101"]
        XCTAssertEqual(Settings.stronger(than: "doubao-seed-2-0-mini-260428", in: listed), "doubao-seed-2-1-lite-260915")
        XCTAssertEqual(Settings.stronger(than: "doubao-seed-2-1-lite-260915", in: ["doubao-seed-2-1-lite-260915", "doubao-seed-2-0-lite-260301"]),
                       "doubao-seed-2-0-lite-260301", "never itself")
        XCTAssertNil(Settings.stronger(than: "qwen-vl-max", in: ["qwen-vl-max", "qwen-plus"]))
        XCTAssertTrue(XiaoLanMediaFind.unsure("图片太模糊，看不清内容"))
        XCTAssertTrue(XiaoLanMediaFind.unsure("一张图"))
        XCTAssertFalse(XiaoLanMediaFind.unsure("一个女生在楼下录口播，抬头看到有东西跑过去"))
    }

    /// 191 (user 11-27: 「一個未讀，兩個未讀…一二三四那種的」): the number on a chat's red mark, at its avatar's top right;
    /// 「99+」 as 99; a bare dot (a muted chat) or another row's number is none.
    func testTheNumberOnARedMark() {
        func p(_ t: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double = 0.02) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: h))]
        }
        let list = [p("4", 0.165, 0.135, 0.02, 0.015), p("蓝海乐", 0.22, 0.17, 0.1), p("好的，这个我帮您查一下", 0.22, 0.2, 0.4, 0.018),
                    p("测试群", 0.22, 0.27, 0.1), p("蓝海乐：多少钱", 0.22, 0.3, 0.3, 0.018)]
        XCTAssertEqual(XiaoLanPanes.markCount(list, name: "蓝海乐"), 4)
        XCTAssertNil(XiaoLanPanes.markCount(list, name: "测试群"), "no number on its row")
        let many = [p("99+", 0.16, 0.135, 0.03, 0.015), p("蓝海乐", 0.22, 0.17, 0.1), p("好的", 0.22, 0.2, 0.2, 0.018)]
        XCTAssertEqual(XiaoLanPanes.markCount(many, name: "蓝海乐"), 99)
    }

    /// N45 (192): two 「这里面讲了什么」, each quoting a message (rows as read at 15:58, screen fractions): each finds its
    /// own quote; a link share and a file read loosely 「，pdf」 are known by kind; the report carries what was seen.
    func testAQuestionQuotingAMessage() throws {
        func p(_ t: String, _ x: Double, _ y: Double, _ w: Double = 0.3) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: 0.02))]
        }
        let rows = [p("9.20复制打开抖音，看看", 0.1, 0.3), p("【爱折腾的JOE的作品.更多", 0.1, 0.323),
                    p("这里面讲了什么", 0.1, 0.48, 0.17), p("蓝海乐：9.20复制打开抖音，看", 0.1, 0.525), p("看【爱折腾昀JOE昀作品】赢了…", 0.1, 0.542),
                    p("这里面讲了什么", 0.1, 0.594, 0.17), p("蓝海乐：山中国经济今明两", 0.1, 0.634, 0.24), p("PDF", 0.35, 0.646, 0.03),
                    p("年深度研判，pdf", 0.1, 0.654, 0.15)]
        let box: (CGRect) -> Bool = { $0.minY > 0.52 && $0.minY < 0.56 || $0.minY > 0.63 && $0.minY < 0.67 }  // the two quotes' grey
        let second = try XCTUnwrap(XiaoLanMediaFind.quoteUnder(rows, line: "这里面讲了什么", rank: 0, isBox: box))
        XCTAssertEqual(second.text, "山中国经济今明两年深度研判，pdf")
        XCTAssertEqual(XiaoLanMediaFind.quotedKind(second.text), .file)
        let first = try XCTUnwrap(XiaoLanMediaFind.quoteUnder(rows, line: "这里面讲了什么", rank: 1, isBox: box))
        XCTAssertTrue(first.text.hasPrefix("9.20复制打开抖音"))
        XCTAssertEqual(XiaoLanMediaFind.quotedKind(first.text), .link)
        XCTAssertEqual(Double(first.at.y), 0.535, accuracy: 0.001)
        XCTAssertNil(XiaoLanMediaFind.quoteUnder(rows, line: "9.20复制打开抖音，看看", isBox: box), "a share has no quote under it")
        XCTAssertFalse(XiaoLanMediaFind.quoteHead("https://v.douyin.com/x"))
        let report = XiaoLanMediaFind.quotedReport(question: "这里面讲了什么", quoted: second.text, kind: .file, seen: "内容：经济增速", failed: nil)
        XCTAssertEqual(report, "这里面讲了什么\n（引用的文件：山中国经济今明两年深度研判，pdf；小蓝看了：内容：经济增速）")
        XCTAssertEqual(ChatToolLink.quoteLine(report), "这里面讲了什么", "the answer quotes the question")
        XCTAssertEqual(ChatToolLink.quoteLine("[链接] https://v.douyin.com/abc/\n网页：…"), "https://v.douyin.com/abc/")
        XCTAssertEqual(ChatToolLink.quoteLine("[语音] 4\"\n语音转文字：多少钱"), "", "no words of its own to quote")
        XCTAssertTrue(XiaoLanMediaFind.sameMemory(XiaoLanMediaFind.memoryKey("https://v.douyin.com/y2OT5I9zhXI/"),
                                                  XiaoLanMediaFind.memoryKey("看 https://v.douyin.com/y2OT5l9zhXI/ :0pm")))
    }

    /// 192 (N39–N41, N46): Kuaishou's playable page is no error page and has a video to start; WeChat's leave sheet is
    /// cancelled; 「重播」 or that sheet end a video; a mark's number read alone.
    func testPlayablePagesTheLeaveSheetAndAMarksNumber() throws {
        func p(_ t: String, _ y: Double, x: Double = 0.1) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: 0.3, height: 0.02))]
        }
        let kuaishou = [p("快手", 0.05), p("v.m.chenzhongtech.com", 0.07), p("分享", 0.65, x: 0.85), p("@宝红", 0.83),
                        p("打开快手，看更多精彩视频", 0.9), p("打开快手", 0.93, x: 0.85)]
        XCTAssertFalse(XiaoLanMediaFind.appOnlyPage(kuaishou))
        let play = try XCTUnwrap(XiaoLanMediaFind.pageVideoSpot(kuaishou))
        XCTAssertTrue((0.25...0.6).contains(Double(play.y)))
        let sheet = [p("可能离开微信，打开第三方应用", 0.45), [CandidatePicker.Piece(text: "取消", box: CGRect(x: 0.25, y: 0.55, width: 0.08, height: 0.02)),
                                                     CandidatePicker.Piece(text: "继续", box: CGRect(x: 0.65, y: 0.55, width: 0.08, height: 0.02))]]
        XCTAssertNotNil(XiaoLanMediaFind.leaveSheet(sheet))
        XCTAssertNil(XiaoLanMediaFind.leaveSheet([p("取消", 0.6)]), "a 取消 alone is no leave sheet")
        XCTAssertTrue(XiaoLanMediaFind.videoOver("去抖音重播"))
        XCTAssertTrue(XiaoLanMediaFind.videoOver("可能离开微信，打开第三方应用"))
        XCTAssertFalse(XiaoLanMediaFind.videoOver("没有任何一家公司可以像"))
        XCTAssertEqual(XiaoLanPanes.markNumber("2"), 2)
        XCTAssertEqual(XiaoLanPanes.markNumber("99+"), 99)
        XCTAssertNil(XiaoLanPanes.markNumber("蓝海乐"))
    }

    /// N34: a private chat's line with no sender is its person's; a group's stays nameless.
    func testAPrivateLineWithNoSenderIsItsChatsPersons() {
        XCTAssertEqual(ChatToolLink.who(ReadMessage(chat: "蓝海乐", group: false, sender: "", text: "［视频］", atMe: false)), "蓝海乐")
        XCTAssertEqual(ChatToolLink.who(ReadMessage(chat: "测试群", group: true, sender: "", text: "你好", atMe: false)), "")
        XCTAssertEqual(ChatToolLink.who(ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "你好", atMe: false)), "蓝海乐")
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
