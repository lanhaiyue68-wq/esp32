import XCTest
import UIKit
@testable import IPhoneAgent

/// 193 (Echo 192 tested on the iPad 11-27 18:03–18:42 首爾; user: 「只處理紅點上的數字那幾條，舊訊息一律不回、不點開」): one
/// place says which lines are this time's new ones (XiaoLanBatch); a red mark's number read off its pixels (N46); a file
/// card read loosely (N60); WeCom's quote over its question (N60); iPad WeChat's recall (N62); WeCom's leave sheet (N56);
/// one-character quotes (N59); a voice note's menu and its words (N47); a seam misread (N50b); IDs and statements kept
/// back (N53); the typing title (N58); the window at its newest line (N54); WeCom's failure said (N64); sharing lost
/// (N65); the lead model (Codex or 豆包 first).
/// The rows below are the iPad's own OCR of 11-27 19:59 (GET /ocr, the two chats as 192's test left them), in window
/// fractions (WeChat's window 0–0.476 of the screen, WeCom's 0.49–1).
@MainActor final class Build193Tests: XCTestCase {
    typealias F = XiaoLanMediaFind
    typealias Line = WatchReport.Line

    func q(_ t: String, x: Double, y: Double, w: Double, h: Double) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: h))
    }
    func theirs(_ t: String) -> Line { Line(sender: "蓝海乐", text: t, mine: false) }
    func mine(_ t: String) -> Line { Line(sender: "我", text: t, mine: true) }

    /// WeCom's 蓝海乐 as the iPad read it (11-27 19:59).
    var weCom: [[CandidatePicker.Piece]] {
        [q("粉粉嫩嫩的，阳光也偏爱～https://", x: 0.1706, y: 0.102, w: 0.6353, h: 0.024),
         q("xhslink.cn/o/gLh9ko7VJj把这段复", x: 0.1696, y: 0.1235, w: 0.6176, h: 0.017),
         q("太上老君说五斗金章受生", x: 0.1755, y: 0.221, w: 0.4529, h: 0.016),
         q("经.docx", x: 0.1755, y: 0.24, w: 0.151, h: 0.016),
         q("15K", x: 0.1755, y: 0.264, w: 0.0608, h: 0.012),
         q("18:25", x: 0.449, y: 0.3145, w: 0.0941, h: 0.011),
         q("你好", x: 0.1706, y: 0.3555, w: 0.0863, h: 0.017),
         q("你是谁", x: 0.1696, y: 0.4115, w: 0.1275, h: 0.017),
         q("账户交易明细（1）.xIs", x: 0.1784, y: 0.469, w: 0.3686, h: 0.022),
         q("21K", x: 0.1755, y: 0.4955, w: 0.0608, h: 0.011),
         q("蓝海乐：", x: 0.199, y: 0.557, w: 0.1196, h: 0.016),
         q("账户交易明细（1）.xIs", x: 0.2284, y: 0.579, w: 0.3314, h: 0.014),
         q("这里面是什么东西", x: 0.1755, y: 0.6085, w: 0.3314, h: 0.017),
         q("：服务总结", x: 0.0471, y: 0.6745, w: 0.1765, h: 0.015),
         q("发消息或按住.", x: 0.1333, y: 0.715, w: 0.2863, h: 0.02)].map { [$0] }
    }

    /// WeChat's 蓝海乐 as the iPad read it (11-27 19:59).
    var weChat: [[CandidatePicker.Piece]] {
        [q("3", x: 0.2048, y: 0.123, w: 0.0357, h: 0.016),
         q("好的，这个我帮您查一下，", x: 0.2153, y: 0.175, w: 0.5735, h: 0.026),
         q("这个链接说的是啥", x: 0.2059, y: 0.502, w: 0.4034, h: 0.02),
         q("蓝海乐：9.20复制打开抖音，看", x: 0.2059, y: 0.5455, w: 0.6092, h: 0.019),
         q("看【爱折腾的JOE的作品】赢了…", x: 0.2059, y: 0.5635, w: 0.6261, h: 0.017),
         q("1）5\"", x: 0.2122, y: 0.614, w: 0.1176, h: 0.02),
         q("转文字", x: 0.5462, y: 0.618, w: 0.1092, h: 0.014),
         q("「蓝海乐」已回收一則訊息", x: 0.2532, y: 0.6585, w: 0.4853, h: 0.017)].map { [$0] }
    }

    // MARK: N46 a red mark's number off its pixels

    func fixture(_ name: String) throws -> WatchOCR.Pixels {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
        return try XCTUnwrap(WatchOCR.Pixels(try Data(contentsOf: url)), name)
    }

    /// The iPad's own marks on 蓝海乐's row, the badge area as paneMarkCount cuts it (11-27 evening: the owner sent 3, 6,
    /// 9, 20 lines to WeChat and 2, 5, 8, 17 to WeCom, the watch off; 「2」 is Echo 191's frame of 16:20). By shape alone
    /// WeChat's 「6」 was read 5; with its loop, 6.
    func testTheIPadsOwnRedMarksReadTheirNumbers() throws {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        for (name, n) in [("badge-wechat-3", 3), ("badge-wechat-6", 6), ("badge-wechat-9", 9), ("badge-wechat-20", 20),
                          ("badge-wecom-2", 2), ("badge-wecom-5", 5), ("badge-wecom-8", 8), ("badge-wecom-17", 17)] {
            XCTAssertEqual(XiaoLanBadge.number(try fixture(name), in: whole), n, name)
        }
    }

    /// The loops of the iPad's digits, as measured off the device: 6, 9 and 0 one, 8 two, 3 and 5 none.
    func testTheLoopsOfTheIPadsDigits() throws {
        func loops(_ name: String) throws -> [Int] {
            let glyphs = try XCTUnwrap(XiaoLanBadge.glyphs(try fixture(name), in: CGRect(x: 0, y: 0, width: 1, height: 1)), name)
            return glyphs.map { XiaoLanBadge.holes($0) }
        }
        XCTAssertEqual(try loops("badge-wechat-6"), [1])
        XCTAssertEqual(try loops("badge-wechat-9"), [1])
        XCTAssertEqual(try loops("badge-wecom-8"), [2])
        XCTAssertEqual(try loops("badge-wechat-20"), [0, 1])
        XCTAssertEqual(try loops("badge-wechat-3"), [0])
        XCTAssertEqual(try loops("badge-wecom-5"), [0])
    }

    /// A mark drawn as the apps draw theirs (the system font, white on red, ~21 px), JPEG'd like a frame.
    func badge(_ text: String, diameter: CGFloat = 21) -> WatchOCR.Pixels? {
        let w = text.count == 1 ? diameter : diameter * (0.55 + 0.5 * CGFloat(text.count))
        let size = CGSize(width: w + 20, height: diameter + 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 243 / 255, green: 84 / 255, blue: 81 / 255, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 10, y: 10, width: w, height: diameter), cornerRadius: diameter / 2).fill()
            let font = UIFont.systemFont(ofSize: diameter * 0.62, weight: .semibold)
            let s = text as NSString
            let t = s.size(withAttributes: [.font: font])
            s.draw(at: CGPoint(x: 10 + (w - t.width) / 2, y: 10 + (diameter - t.height) / 2),
                   withAttributes: [.font: font, .foregroundColor: UIColor.white])
        }
        return image.jpegData(compressionQuality: 0.8).flatMap { WatchOCR.Pixels($0) }
    }

    func testDrawnMarksReadTheirNumbers() throws {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        for n in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "12", "37", "80"] {
            let px = try XCTUnwrap(badge(n))
            XCTAssertEqual(XiaoLanBadge.number(px, in: whole), Int(n), "mark 「\(n)」")
        }
    }

    func testNoMarkOrABareDotIsNoNumber() throws {
        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        let size = CGSize(width: 40, height: 40)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let dot = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 243 / 255, green: 84 / 255, blue: 81 / 255, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 15, y: 15, width: 10, height: 10)).fill()
        }
        let px = try XCTUnwrap(dot.pngData().flatMap { WatchOCR.Pixels($0) })
        XCTAssertNil(XiaoLanBadge.number(px, in: whole), "a muted chat's bare dot")
        let grey = try XCTUnwrap(badge("2"))
        XCTAssertNil(XiaoLanBadge.number(grey, in: CGRect(x: 0, y: 0, width: 0.2, height: 0.2)), "no red in the area")
    }

    // MARK: the one place that says what is new (N46, N52, N60, N61, N63)

    /// N60/N61 (WeCom 18:25–18:28): its mark said 4 — 你好, 你是谁, the xls (its 「21K」 its own), the question quoting
    /// it; the old link and docx above are never among them.
    func testTheMarksNumberTakesTheNewestThatMany() {
        let lines = [theirs("粉粉嫩嫩的，阳光也偏爱～https://xhslink.cn/o/gLh9ko7VJj"), mine("好的，这个我帮您查一下，稍等～"),
                     theirs("[文件] 太上老君说五斗金章受生经.docx15K"), mine("好的，这个我帮您查一下，稍等～"),
                     theirs("你好"), theirs("你是谁"), theirs("账户交易明细（1）.xIs21K"), theirs("这里面是什么东西")]
        let pick = XiaoLanBatch.pick(lines, history: nil, opened: .mark(4))
        XCTAssertEqual(pick.lines.map(\.text), ["你好", "你是谁", "账户交易明细（1）.xIs21K", "这里面是什么东西"])
    }

    /// N46: the number not read — only what came after the last line read (and after my last line); neither on the
    /// window, the newest line alone; never the old guess.
    func testNoNumberTakesOnlyWhatCameAfterTheLastLineRead() {
        let history = [theirs("你好"), mine("好的，这个我帮您查一下，稍等～")]
        let lines = [theirs("粉粉嫩嫩的，阳光也偏爱"), theirs("你好"), mine("好的，这个我帮您查一下，稍等～"), theirs("你是谁"), theirs("[图片]")]
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: history, opened: .mark(nil)).lines.map(\.text), ["你是谁", "[图片]"])
        let noAnchor = [theirs("老的一句话一"), theirs("老的一句话二"), theirs("新的一句")]
        XCTAssertEqual(XiaoLanBatch.pick(noAnchor, history: [theirs("完全不在窗口上的话")], opened: .mark(nil)).lines.map(\.text), ["新的一句"])
        let withMine = [theirs("老的一句话一"), mine("我的回复在这里"), theirs("甲"), theirs("乙")]
        XCTAssertEqual(XiaoLanBatch.pick(withMine, history: nil, opened: .mark(nil)).lines.map(\.text), ["甲", "乙"])
    }

    /// N52 (WeChat 18:04): reopened for its list line 「［语音］3"」 with no mark, the note's words having come in under
    /// it: only what follows the last line read — never 「这里面讲了什么」 and the four media read before.
    func testReopenedWithNoMarkGivesNothingOld() {
        let history = [theirs("这里面讲了什么"), theirs("中国经济今明两年深度研判.pdf"), theirs("[语音] 3\""), theirs("[图片]"), theirs("[语音] 3\"")]
        let lines = [theirs("这里面讲了什么"), theirs("中国经济今明两年深度研判.pdf"), theirs("[语音] 3\""), theirs("你能不能看到这个是啥？"),
                     theirs("[图片]"), theirs("[语音] 3\""), theirs("我在测试语音")]
        let pick = XiaoLanBatch.pick(lines, history: history, opened: .missed)
        XCTAssertEqual(pick.lines.map(\.text), ["我在测试语音"], "only what follows the last line read")
        let scrolled = [theirs("别的旧话一"), theirs("别的旧话二"), theirs("别的旧话三")]
        XCTAssertTrue(XiaoLanBatch.pick(scrolled, history: history, opened: .missed).lines.isEmpty, "nothing goes on from it: none new")
        XCTAssertTrue(XiaoLanBatch.pick(scrolled, history: history, opened: .live).lines.isEmpty)
    }

    /// N63 (WeChat 18:27–18:42): back from Douyin's page, the question, the voice note and the recall that came in
    /// meanwhile are what follows the last line read.
    func testBackFromAPageTheLinesThatCameMeanwhileAreNew() {
        let history = [mine("好的，这个我帮您查一下，稍等～"), theirs("9.20复制打开抖音，看看【爱折腾JOE的作品"), mine("好的，这个我帮您查一下，稍等～")]
        let lines = history + [theirs("这个链接说的是啥"), theirs("[语音] 5\""), theirs("[撤回] 蓝海乐 撤回了一条消息")]
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: history, opened: .live).lines.map(\.text),
                       ["这个链接说的是啥", "[语音] 5\"", "[撤回] 蓝海乐 撤回了一条消息"])
        XCTAssertTrue(XiaoLanBatch.pick(lines, history: history, opened: .live, firstSinceLaunch: true).lines.isEmpty,
                      "open when watching started, no mark: read")
    }

    /// A voice note's words (reported with it) take no place among the newest.
    func testAVoiceNotesWordsTakeNoPlace() {
        let lines = [mine("好的"), theirs("你好"), theirs("[语音] 5\""), theirs("多少钱")]
        let pick = XiaoLanBatch.pick(lines, history: nil, opened: .mark(2), isEcho: { $0.text == "多少钱" })
        XCTAssertEqual(pick.lines.map(\.text), ["你好", "[语音] 5\""])
    }

    // MARK: N60 a file card read loosely; WeCom's quote over its question

    func testAMisreadExtensionIsStillAFile() throws {
        XCTAssertEqual(F.fileName("账户交易明细（1）.xIs"), "账户交易明细（1）.xIs")
        XCTAssertEqual(F.fileExtension("xIs"), "xls")
        XCTAssertEqual(F.fileName("伤治愈.docx13K"), "伤治愈.docx", "a size right after it")
        XCTAssertEqual(F.fileName("【模拟服务器】收到：6原生家庭创伤治愈.docx13K"), "6原生家庭创伤治愈.docx")
        XCTAssertNil(F.fileName("xhslink.cn/o/gLh9ko7VJj把这段复"))
        XCTAssertNil(F.fileName("9.20复制打开抖音，看看"))
        XCTAssertEqual(F.kind(of: "账户交易明细（1）.xIs"), .file)
        XCTAssertTrue(F.cardText("账户交易明细（1）.xIs"))
        XCTAssertTrue(F.fileSizeLine("21K"))
        // the card's size under its name is the card's, not a message of its own
        let pieces = [WatchOCR.Piece(text: "账户交易明细（1）.xIs", box: CGRect(x: 0.18, y: 0.469, width: 0.37, height: 0.014), kind: .theirs),
                      WatchOCR.Piece(text: "21K", box: CGRect(x: 0.18, y: 0.4955, width: 0.06, height: 0.011), kind: .theirs)]
        let screen = WatchOCR.lines(pieces, title: "蓝海乐")
        XCTAssertEqual(screen.lines.count, 1)
        XCTAssertTrue(screen.lines.first?.text.hasSuffix("21K") ?? false)
    }

    /// N60 (18:28): the xls's job opened an old docx card; a card of the name looked for only, else nothing.
    func testAFileCardOfAnotherNameIsNeverClicked() throws {
        XCTAssertNil(F.fileCard(weCom.filter { !$0[0].text.contains("账户") }, hint: "账户交易明细（1）.xIs21K"))
        // the xls itself — its card (0.48) or its quote (0.586), never the docx (0.248)
        let at = try XCTUnwrap(F.fileCard(weCom, hint: "账户交易明细(1).xls"))
        XCTAssertGreaterThan(Double(at.y), 0.45)
    }

    /// WeCom after its quote was clicked (iPad OCR 11-27 19:55): the chat moved up to the file's own card — its name read
    /// 「（7）」 for (1) — and 「回到引用位置」 showed; the quote's own line, on its grey box, is never the card.
    func testWeComsJumpToTheQuotedCard() throws {
        let rows = [q("你是谁", x: 0.1696, y: 0.138, w: 0.1275, h: 0.019), q("账户交易明细（7）.xIs", x: 0.1588, y: 0.1975, w: 0.3627, h: 0.019),
                    q("21K", x: 0.1755, y: 0.221, w: 0.0608, h: 0.014), q("蓝海乐：", x: 0.199, y: 0.284, w: 0.1176, h: 0.016),
                    q("｜账户交易明细（1）.xIs", x: 0.2167, y: 0.305, w: 0.3235, h: 0.016),
                    q("这里面是什么东西", x: 0.1755, y: 0.3355, w: 0.3314, h: 0.019), q("2", x: 0.1765, y: 0.491, w: 0.0333, h: 0.014),
                    q("♥回到引用位置", x: 0.6922, y: 0.714, w: 0.2451, h: 0.016)].map { [$0] }
        let back = try XCTUnwrap(F.backToQuote(rows))
        XCTAssertEqual(Double(back.y), 0.722, accuracy: 0.002)
        XCTAssertNil(F.backToQuote(weCom))
        let card = try XCTUnwrap(F.fileCard(rows, hint: "账户交易明细（1）.xIs", exclude: { $0.minY > 0.28 && $0.minY < 0.33 }))
        XCTAssertEqual(Double(card.y), 0.207, accuracy: 0.002, "the card, its (1) read (7)")
    }

    func testWeComsQuoteOverItsQuestion() throws {
        let isBox: (CGRect) -> Bool = { $0.minY > 0.55 && $0.minY < 0.6 }  // the grey box in WeCom's bubble
        let q = try XCTUnwrap(F.quoteUnder(weCom, line: "这里面是什么东西", isBox: isBox))
        XCTAssertTrue(q.text.contains("账户交易明细"))
        XCTAssertEqual(F.quotedKind(q.text), .file)
        XCTAssertEqual(Double(q.at.y), 0.586, accuracy: 0.01, "its file line clicked")
        XCTAssertNil(F.quoteUnder(weCom, line: "你是谁", isBox: isBox), "a line with no quote")
        // WeChat's quote stays under its question
        let w = try XCTUnwrap(F.quoteUnder(weChat, line: "这个链接说的是啥", isBox: { $0.minY > 0.54 && $0.minY < 0.6 }))
        XCTAssertTrue(w.text.hasPrefix("9.20复制打开抖音"))
    }

    /// A window drawn with the colours measured on the iPad (11-27 19:54, normal light): the chat's grey, a bubble of
    /// theirs 254, WeCom's quote box in it 248, WeChat's quote box 224, a bubble of mine green.
    func quotePixels() -> WatchOCR.Pixels? {
        let size = CGSize(width: 490, height: 1280)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        func fill(_ r: Int, _ g: Int, _ b: Int, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ ctx: UIGraphicsImageRendererContext) {
            UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1).setFill()
            ctx.fill(CGRect(x: x * 490, y: y * 1280, width: w * 490, height: h * 1280))
        }
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            fill(236, 236, 240, 0, 0, 1, 1, ctx)
            fill(254, 254, 254, 0.14, 0.54, 0.6, 0.1, ctx)    // WeCom's bubble
            fill(248, 248, 250, 0.17, 0.55, 0.55, 0.05, ctx)  // its quote box
            fill(224, 224, 224, 0.19, 0.70, 0.45, 0.05, ctx)  // WeChat's quote box
            fill(149, 236, 105, 0.5, 0.80, 0.4, 0.04, ctx)    // a bubble of mine
        }
        return image.pngData().flatMap { WatchOCR.Pixels($0) }
    }

    func testAQuotesBoxIsToldFromABubble() throws {
        let px = try XCTUnwrap(quotePixels())
        XCTAssertTrue(F.onQuote(CGRect(x: 0.199, y: 0.557, width: 0.12, height: 0.016), px), "WeCom's 「蓝海乐：」 on its 248 box")
        XCTAssertFalse(F.onQuote(CGRect(x: 0.1755, y: 0.6085, width: 0.33, height: 0.017), px), "the question on its bubble")
        XCTAssertTrue(F.onQuote(CGRect(x: 0.2059, y: 0.71, width: 0.4, height: 0.019), px), "WeChat's quote box")
        XCTAssertFalse(F.onQuote(CGRect(x: 0.56, y: 0.81, width: 0.3, height: 0.02), px), "a bubble of mine")
        XCTAssertEqual(WatchOCR.kind(CGRect(x: 0.199, y: 0.557, width: 0.12, height: 0.016), px), .theirs,
                       "why: the bubbles' own test takes 248 for a bubble")
    }

    // MARK: N62, N56, N59, N64, N58, N65

    func testIPadWeChatsRecall() {
        XCTAssertEqual(F.recaller("「蓝海乐」已回收一則訊息"), "蓝海乐")
        XCTAssertNil(F.recaller("你已回收一則訊息"))
        XCTAssertEqual(F.recaller("\"主人蓝海乐\" 撤回了一条消息"), "主人蓝海乐", "192's still")
    }

    /// WeCom's sheet over Xiaohongshu's page as the iPad read it (11-27 19:59).
    func testWeComsLeaveSheetIsCancelled() throws {
        XCTAssertTrue(F.leaveWords("即将离开，打开“小红书”"))
        let rows = [[q("即将离开，打开“小红书”", x: 0.2324, y: 0.3895, w: 0.4627, h: 0.027)],
                    [q("取消", x: 0.2608, y: 0.4675, w: 0.0863, h: 0.019)], [q("允许", x: 0.649, y: 0.4675, w: 0.0863, h: 0.019)],
                    [q("App内打开", x: 0.4157, y: 0.775, w: 0.2176, h: 0.02)]]
        let cancel = try XCTUnwrap(F.leaveSheet(rows))
        XCTAssertEqual(Double(cancel.x), 0.304, accuracy: 0.005, "取消, never 允许")
        XCTAssertTrue(F.videoOver("即将离开，打开“小红书”"))
    }

    func testOneCharacterLinesAreQuoted() throws {
        XCTAssertEqual(ChatToolLink.quoteLine("1"), "1")
        XCTAssertEqual(ChatToolLink.quoteLine("3"), "3")
        XCTAssertEqual(ChatToolLink.quoteLine("[语音] 4\"\n语音转文字：多少钱"), "")
        let at = try XCTUnwrap(F.quoteSpot(weChat, quote: "3"))
        XCTAssertEqual(Double(at.y), 0.131, accuracy: 0.002)
        XCTAssertNotNil(F.quoteBar([[q("蓝海乐：3", x: 0.2, y: 0.8, w: 0.2, h: 0.02)]], quote: "3"))
    }

    func testWeComsFailureIsSaidAsWeComs() {
        XCTAssertEqual(ChatToolLink.notSentSaid(ChatToolLink.reasonNotSent, wework: true), "企业微信里没有发出去")
        XCTAssertEqual(ChatToolLink.notSentSaid(ChatToolLink.reasonNotSent, wework: false), ChatToolLink.reasonNotSent)
        XCTAssertEqual(ChatToolLink.notSentSaid("隐私检查拦下，未发送", wework: true), "隐私检查拦下，未发送")
    }

    func testATypingTitleIsNoChat() {
        XCTAssertTrue(XiaoLanPanes.typingTitle("对方正在输入…"))
        XCTAssertTrue(XiaoLanPanes.typingTitle("對方正在輸入..."))
        XCTAssertFalse(XiaoLanPanes.typingTitle("蓝海乐"))
    }

    func testSharingSilentLongEnoughIsChecked() {
        XCTAssertFalse(XiaoLanPanes.shareQuiet(5))
        XCTAssertTrue(XiaoLanPanes.shareQuiet(25))
    }

    // MARK: N47 a voice note's menu and its words

    /// WeChat's 5" note pressed long on the iPad (11-27 19:57, its OCR): the menu came up over the note, the chat moved
    /// up; 「转文字」 in the menu (0.485), the small button beside the note (0.658), before the press at (0.607, 0.789).
    func testTheMenusTranscribeNotTheSmallButton() throws {
        func w(_ t: String, _ cx: Double, _ cy: Double, _ cw: Double, _ ch: Double) -> [CandidatePicker.Piece] {
            [q(t, x: (cx - cw / 2) / 0.476, y: cy - ch / 2, w: cw / 0.476, h: ch)]
        }
        let rows = [w("17", 0.112, 0.388, 0.029, 0.017), w("收藏", 0.064, 0.484, 0.044, 0.017), w("文", 0.239, 0.462, 0.019, 0.014),
                    w("转文字", 0.239, 0.485, 0.065, 0.019), w("背景", 0.152, 0.485, 0.046, 0.019), w("播放", 0.151, 0.504, 0.044, 0.019),
                    w("删除", 0.326, 0.485, 0.044, 0.019), w("多选", 0.415, 0.485, 0.042, 0.016), w("引用", 0.064, 0.578, 0.044, 0.017),
                    w("提醒", 0.151, 0.577, 0.044, 0.019), w("连续", 0.239, 0.578, 0.044, 0.017), w("朗读", 0.240, 0.596, 0.049, 0.021),
                    w("•）5\"", 0.128, 0.657, 0.056, 0.017), w("转文字", 0.282, 0.658, 0.060, 0.012)]
        let band = try XCTUnwrap(F.menuBand(rows))
        let item = try XCTUnwrap(F.menuItem(rows, "转文字", in: band, avoid: CGPoint(x: 0.607, y: 0.789)))
        XCTAssertEqual(Double(item.y), 0.485, accuracy: 0.002, "the menu's, not the button beside the note")
        XCTAssertEqual(Double(item.x), 0.239 / 0.476, accuracy: 0.01)
        XCTAssertNil(F.menuBand(weChat), "no menu up")
        let lowest = try XCTUnwrap(F.button(rows, "转文字"))
        XCTAssertEqual(Double(lowest.y), 0.658, accuracy: 0.002, "192 took the lowest: the button")
    }

    /// WeChat's window drawn as on the iPad (measured 11-27 19:57: the note's bubble and its words' box both white, the
    /// words' box right under the note at its left, no avatar beside it): the chat's grey, an avatar by the note.
    func chatPixels(wordsBox: Bool) -> WatchOCR.Pixels? {
        let size = CGSize(width: 457, height: 1280)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.3, green: 0.6, blue: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0.03 * 457, y: 0.595 * 1280, width: 0.09 * 457, height: 0.036 * 1280))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0.17 * 457, y: 0.595 * 1280, width: 0.27 * 457, height: 0.036 * 1280))  // the note
            if wordsBox { ctx.fill(CGRect(x: 0.17 * 457, y: 0.638 * 1280, width: 0.52 * 457, height: 0.033 * 1280)) }
        }
        return image.pngData().flatMap { WatchOCR.Pixels($0) }
    }

    /// The note and its words as the iPad read them after 转文字 (11-27 19:57).
    func testWeChatsWordsUnderANoteAreKnown() throws {
        let note = q("1）5\"", x: 0.2101, y: 0.6035, w: 0.1134, h: 0.019)
        let words = q("吧啦啦啦啦啦，三哥。", x: 0.2048, y: 0.6475, w: 0.4811, h: 0.023)
        let px = try XCTUnwrap(chatPixels(wordsBox: true))
        XCTAssertEqual(F.convertedWords([note, words], seconds: 5, px: px), "吧啦啦啦啦啦，三哥。")
        XCTAssertNil(F.convertedWords([note, words], seconds: 5), "no pixels: only with WeCom's mark, as before")
        // the real window's recall under an unturned note is no words of it
        let grey = try XCTUnwrap(chatPixels(wordsBox: false))
        XCTAssertNil(F.convertedWords(weChat.map { $0[0] }, seconds: 5, px: grey))
    }

    /// WeCom turns its notes into words itself (11-27 19:53: 「•）4'」, its words, 「•转换完成」).
    func testWeComsOwnWordsUnderANote() {
        let pieces = [q("•）4'", x: 0.2363, y: 0.555, w: 0.1431, h: 0.014),
                      q("这里面是什么东西，给我看一下。", x: 0.1745, y: 0.5975, w: 0.5627, h: 0.019),
                      q("•转换完成", x: 0.2471, y: 0.6215, w: 0.1471, h: 0.015)]
        XCTAssertEqual(F.convertedWords(pieces, seconds: 4), "这里面是什么东西，给我看一下。")
    }

    // MARK: N50b, N53, N54

    func testASeamWithAMisreadCharacterIsJoinedOnce() {
        let joined = F.overlapJoin("五老帝君及东斗注算君、九天财库禄库君、九享籍掌算君", "九天财库禄库君、九亨籍掌算君、九天生神君")
        XCTAssertEqual(joined.components(separatedBy: "九天财库禄库君").count - 1, 1, joined)
        XCTAssertTrue(joined.hasSuffix("九天生神君"))
        XCTAssertEqual(F.overlapJoin("尔时，太上老君在太清境上、大赤天中、黄", "上老君在太清境上、大赤天中、黄金殿内，召"),
                       "尔时，太上老君在太清境上、大赤天中、黄金殿内，召", "192's still")
    }

    func testIDsCardsAndStatementsAreKeptBack() {
        XCTAssertTrue(F.sensitive("这是一张外国人登录证，持有人…"))
        XCTAssertTrue(F.sensitive("文件名：账户交易明细（1）.xls"))
        XCTAssertTrue(F.sensitive("A PASSPORT photo page"))
        XCTAssertFalse(F.sensitive("一只猫在沙发上"))
        XCTAssertEqual(F.masked("卡号 6222 0212 3456 7890，余额 1,234.56，3 笔"), "卡号 ****，余额 ****，3 笔")
        XCTAssertEqual(F.masked("第 12 页"), "第 12 页")
    }

    func testTheWindowStillShowsItsNewestLine() {
        XCTAssertTrue(F.shows(weCom, "这里面是什么东西"))
        XCTAssertTrue(F.shows(weCom, "账户交易明细（1）.xIs21K"))
        XCTAssertFalse(F.shows(weCom, "这一句是十二点四十的旧话"))
        XCTAssertEqual(F.newestWords(["你好", "这里面是什么东西", "[图片]"]), "这里面是什么东西")
    }

    // MARK: the lead model

    func testTheLeadModelGoesFirst() {
        XCTAssertEqual(LeadModel.order(.codex, codex: true, doubao: true), [.codex, .doubao])
        XCTAssertEqual(LeadModel.order(.doubao, codex: true, doubao: true), [.doubao, .codex])
        XCTAssertEqual(LeadModel.order(.codex, codex: false, doubao: true), [.doubao], "Codex not signed in")
        XCTAssertEqual(LeadModel.order(.doubao, codex: true, doubao: false), [.codex])
        let saved = UserDefaults.standard.string(forKey: LeadModel.key)
        defer { UserDefaults.standard.set(saved, forKey: LeadModel.key) }
        UserDefaults.standard.removeObject(forKey: LeadModel.key)
        XCTAssertEqual(LeadModel.current, .codex, "Codex leads unless switched")
        LeadModel.current = .doubao
        XCTAssertEqual(LeadModel.current, .doubao)
    }

    func testAVideosFramesGoToCodexAsOnePicture() throws {
        let frames = (0..<3).compactMap { i -> Data? in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 100, height: 200), format: format).image { ctx in
                UIColor(white: CGFloat(i) / 3, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
            }.jpegData(compressionQuality: 0.8)
        }
        let grid = try XCTUnwrap(XiaoLanPanes.grid(frames))
        let image = try XCTUnwrap(UIImage(data: grid))
        XCTAssertEqual(image.size.width, 900, accuracy: 1)
        XCTAssertEqual(image.size.height, 1800, accuracy: 2, "two columns, two rows of 450×900")
        XCTAssertEqual(XiaoLanPanes.grid([frames[0]]), frames[0], "one picture goes as it is")
    }
}
