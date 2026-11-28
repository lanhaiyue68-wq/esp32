import XCTest
import UIKit
@testable import IPhoneAgent

/// 195: what Echo 194 got wrong on the iPad, 11-28 00:10–00:45 (N70b, N76, N77, N78, N79), and 195's review (N80–N89).
@MainActor final class Build195Tests: XCTestCase {
    typealias F = XiaoLanMediaFind
    typealias Line = WatchReport.Line

    func q(_ t: String, x: Double, y: Double, w: Double, h: Double) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: h))
    }
    /// A piece by its middle, as the iPad's OCR gave it.
    func m(_ t: String, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double) -> [CandidatePicker.Piece] {
        [q(t, x: cx - w / 2, y: cy - h / 2, w: w, h: h)]
    }

    func fixture(_ name: String) throws -> WatchOCR.Pixels {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
        return try XCTUnwrap(WatchOCR.Pixels(try Data(contentsOf: url)), name)
    }

    /// Echo 194's WeCom window of 11-28 00:14 (its frame, x 467–960 of 960 × 1280): 蓝海乐's 「1」 (avatar top 0.466) and
    /// 「2」 (0.523), the answer under them, the quote bar and 小藍's keyboard below. OCR gave the lone 「1」 no words.
    var bubbles: WatchOCR.Pixels { get throws { try fixture("wecom-bubbles-1-2") } }

    // MARK: N76 a lone digit OCR gave no words

    func testALoneDigitIsReadOffItsBubble() throws {
        let px = try bubbles
        let tops = F.avatarTops(px, bottom: 0.64)
        XCTAssertEqual(tops.count, 2, "\(tops)")
        // as 194 read it: 「2」 alone
        let read = [Line(sender: "蓝海乐", text: "2", mine: false, y: 0.536)]
        let found = F.unreadDigits(px, tops: tops, lines: read, bottom: 0.64)
        XCTAssertEqual(found.map { $0.text }, ["1"])
        XCTAssertEqual(found.first?.y ?? 0, 0.479, accuracy: 0.01)
        XCTAssertEqual(F.unreadDigits(px, tops: tops, lines: [], bottom: 0.64).map { $0.text }, ["2", "1"], "neither read: both, lowest first")
        // its line in its place, then the mark's two counted by their avatars: 「1」 and 「2」
        var lines = [Line(sender: "蓝海乐", text: "好的，这个我帮您查一下，稍等～", mine: true, y: 0.15)] + read
        for d in found { lines.insert(Line(sender: "蓝海乐", text: d.text, mine: false, y: d.y), at: lines.firstIndex { ($0.y ?? 0) > d.y } ?? lines.count) }
        XCTAssertEqual(lines.map(\.text).suffix(2), ["1", "2"])
        let pick = XiaoLanBatch.pick(lines, history: nil, opened: .mark(2), avatarTops: tops, previewY: 0.536)
        XCTAssertEqual(pick.lines.map(\.text), ["1", "2"])
    }

    /// A bubble drawn as WeCom's (white on the chat's grey, an avatar beside it) with `text` in the system font.
    func drawnBubble(_ text: String) -> WatchOCR.Pixels? {
        let size = CGSize(width: 493, height: 1280)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 236 / 255, green: 237 / 255, blue: 241 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.4, green: 0.7, blue: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: 15, y: 600, width: 46, height: 46))
            UIColor.white.setFill()
            let w = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 20)]).width + 40
            UIBezierPath(roundedRect: CGRect(x: 74, y: 600, width: w, height: 49), cornerRadius: 6).fill()
            (text as NSString).draw(at: CGPoint(x: 94, y: 612), withAttributes: [.font: UIFont.systemFont(ofSize: 20), .foregroundColor: UIColor(white: 0.1, alpha: 1)])
        }
        return image.pngData().flatMap { WatchOCR.Pixels($0) }
    }

    func testDigitsAreReadAndACharacterIsNot() throws {
        for (text, want) in [("1", "1"), ("3", "3"), ("12", "12"), ("10", "10"), ("好", nil), ("嗯", nil), ("你好", nil)] as [(String, String?)] {
            let px = try XCTUnwrap(drawnBubble(text))
            let tops = F.avatarTops(px, bottom: 0.9)
            XCTAssertEqual(tops.count, 1, text)
            XCTAssertEqual(F.unreadDigits(px, tops: tops, lines: [], bottom: 0.9).first?.text, want, text)
        }
    }

    // MARK: N80 a lone digit that came in with the chat open

    /// 195's review (N80: N76 read a bubble's digits only under a red mark): the same window read with the chat open (no
    /// mark), my answer above, 「1」 and 「2」 come in after it, OCR reading 「2」 only: both are new.
    func testALoneDigitThatCameInWithTheChatOpenIsNew() throws {
        let px = try bubbles
        let tops = F.avatarTops(px, bottom: 0.64)
        let answer = Line(sender: "我", text: "好的，这个我帮您查一下，稍等～", mine: true, y: 0.15)
        let read = [answer, Line(sender: "蓝海乐", text: "2", mine: false, y: 0.536)]
        let lines = F.withDigits(read, F.unreadDigits(px, tops: tops, lines: read, bottom: 0.64), sender: "蓝海乐")
        XCTAssertEqual(lines.map(\.text), [answer.text, "1", "2"])
        XCTAssertEqual(lines[1].sender, "蓝海乐")
        XCTAssertEqual(lines[1].y ?? 0, 0.479, accuracy: 0.01)
        let pick = XiaoLanBatch.pick(lines, history: [answer], opened: .live)
        XCTAssertEqual(pick.lines.map(\.text), ["1", "2"], pick.why)
        XCTAssertEqual(XiaoLanBatch.pick(read, history: [answer], opened: .live).lines.map(\.text), ["2"], "194: 「1」 lost")
        // the next read goes on from the history with 「1」 in it, its pixels giving it again or not
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: lines, opened: .live).lines.map(\.text), [])
        XCTAssertEqual(XiaoLanBatch.pick(read, history: lines, opened: .live).lines.map(\.text), [])
    }

    /// An old lone 「1」 over the lines read before (never read: OCR gave it no words) is no new line when its pixels
    /// give it now.
    func testAnOldLoneDigitOverTheLinesReadIsNotNew() throws {
        let px = try bubbles
        let tops = F.avatarTops(px, bottom: 0.64)
        let read = [Line(sender: "蓝海乐", text: "2", mine: false, y: 0.536),
                    Line(sender: "我", text: "您好！我是小蓝助手，请问有什么需要？", mine: true, y: 0.6)]
        let lines = F.withDigits(read, F.unreadDigits(px, tops: tops, lines: read, bottom: 0.64), sender: "蓝海乐")
        XCTAssertEqual(lines.map(\.text), ["1", "2", read[1].text])
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: read, opened: .live).lines.map(\.text), [])
    }

    /// N85: with no red mark's count, a digit read off its bubble counts only under where the history goes on.
    func testADigitOverWhereTheHistoryGoesOnIsAnOldOne() {
        let one: [(text: String, y: Double)] = [(text: "1", y: 0.479)]
        let answer = Line(sender: "我", text: "好的，这个我帮您查一下，稍等～", mine: true, y: 0.15)
        let weather = Line(sender: "蓝海乐", text: "今天天气怎么样", mine: false, y: 0.2)
        let two = Line(sender: "蓝海乐", text: "2", mine: false, y: 0.536)
        XCTAssertEqual(F.belowRead(one, lines: [answer, two], history: [answer]).map { $0.text }, ["1"], "came in after my answer")
        XCTAssertEqual(F.belowRead(one, lines: [weather, two], history: [weather, two]).map { $0.text }, [],
                       "an old 「1」 hidden in the last read (the pointer over it), no line of mine under it")
        XCTAssertEqual(F.belowRead(one, lines: [weather, two], history: [weather]).map { $0.text }, ["1"],
                       "「1」 and 「2」 new, though 「2」 may have been read before")
        XCTAssertEqual(F.belowRead(one, lines: [weather, two], history: []).map { $0.text }, ["1"])
        XCTAssertEqual(F.belowRead(one, lines: [two, Line(sender: "我", text: "收到", mine: true, y: 0.6)], history: []).map { $0.text }, [],
                       "over a line of mine")
    }

    /// N88 (测试群 11-28 01:20): 「2」 came onto the window after the read and sat over my answer when read again; with a
    /// line the history goes on from, my lines are no floor.
    func testADigitOverMyAnswerButUnderWhereTheHistoryGoesOnIsNew() {
        let two: [(text: String, y: Double)] = [(text: "2", y: 0.50)]
        let much = Line(sender: "蓝海乐", text: "多少钱", mine: false, y: 0.2)
        let hello = Line(sender: "蓝海乐", text: "你好", mine: false, y: 0.40)
        let answer = Line(sender: "我", text: "您好！我是小蓝助手，请问有什么需要？", mine: true, y: 0.55)
        XCTAssertEqual(F.belowRead(two, lines: [much, hello, answer], history: [much, hello]).map { $0.text }, ["2"])
        XCTAssertEqual(F.belowRead(two, lines: [much, hello, answer], history: []).map { $0.text }, [], "nothing to go on from: under mine only")
    }

    /// N89 (测试群 11-28 01:20): every name row of 主人蓝海乐 read 「主人监海乐」; the lists' names put it right.
    func testANameReadWrongEveryTimeIsPutRightByTheListsNames() {
        func l(_ who: String, _ t: String) -> Line { Line(sender: who, text: t, mine: false) }
        let lines = [l("主人监海乐", "1"), l("主人监海乐", "2"), l("蓝海乐", "你好"), Line(sender: "我", text: "好的", mine: true)]
        XCTAssertEqual(F.steadySenders(lines, known: [], names: ["主人蓝海乐", "蓝海乐", "测试群"]).map(\.sender),
                       ["主人蓝海乐", "主人蓝海乐", "蓝海乐", "我"])
        XCTAssertEqual(F.steadySenders(lines, known: []).map(\.sender)[0], "主人监海乐", "read twice alike, no list name: left")
    }

    /// N87 (WeCom 11-28 01:09, 01:16): 「引用」 read with its icon as one piece is still the item; words are not.
    func testAMenuWordReadWithItsIconIsTheItem() throws {
        let p = try XCTUnwrap(F.menuItem([m("66引用", 0.377, 0.55, 0.06, 0.04)], "引用"))
        XCTAssertEqual(Double(p.x), 0.377, accuracy: 0.001)
        XCTAssertNotNil(F.menuItem([m("❝引用", 0.377, 0.55, 0.06, 0.04)], "引用"))
        XCTAssertNil(F.menuItem([m("我引用了一下", 0.377, 0.55, 0.2, 0.02)], "引用"), "a sentence is no item")
    }

    /// N88 (user chose 「回覆前再讀一次」; 测试群 11-28 01:20, its frames 17:20:44.8 and 17:20:46.0): read again right after
    /// its read, what comes after that read's last lines is new — 「2」 that came a second late — and nothing else.
    func testReadAgainRightAfterTheReadGoesOnFromIt() {
        func l(_ who: String, _ t: String) -> Line { Line(sender: who, text: t, mine: false) }
        let first = [l("蓝海乐", "多少钱"), l("蓝海乐", "你好"), l("主人蓝海乐", "1"), l("主人蓝海乐", "2"), l("蓝海乐", "你好"), l("主人蓝海乐", "1")]
        let again = first + [l("主人蓝海乐", "2")]
        let pick = XiaoLanBatch.pick(again, history: first, opened: .live, seen: ["1", "2", "你好"], justRead: true)
        XCTAssertEqual(pick.lines.map(\.text), ["2"], pick.why)
        XCTAssertEqual(XiaoLanBatch.pick(first, history: first, opened: .live, justRead: true).lines.map(\.text), [], "nothing came")
        let early = Array(first.prefix(5))
        XCTAssertEqual(XiaoLanBatch.pick(early + [l("主人蓝海乐", "1"), l("主人蓝海乐", "2")], history: early, opened: .live,
                                         justRead: true).lines.map(\.text), ["1", "2"], "both late")
        XCTAssertNil(XiaoLanBatch.readEnd([l("蓝海乐", "别的")], history: first), "not shown: the usual way")
    }

    // MARK: N81/N82 a group's lone digit

    /// 测试群 on the iPad 11-28 00:12 (WeChat's window, x 0–457 of 960 × 1280, 小藍's keyboard below): 蓝海乐's 「你好」,
    /// then 主人蓝海乐's 「1」 and 「2」, each under its name; OCR read 「2」, not 「1」.
    var group: WatchOCR.Pixels { get throws { try fixture("wechat-group-1-2") } }
    /// That window's OCR (screen fractions as the iPad gave them; the window 0.476 of the screen wide).
    func groupRows() -> [[CandidatePicker.Piece]] {
        func w(_ t: String, _ cx: Double, _ cy: Double, _ cw: Double, _ ch: Double) -> [CandidatePicker.Piece] {
            [q(t, x: (cx - cw / 2) / 0.476, y: cy - ch / 2, w: cw / 0.476, h: ch)]
        }
        return [w("00:11", 0.237, 0.453, 0.050, 0.014), w("蓝海乐", 0.110, 0.484, 0.054, 0.014), w("你好", 0.123, 0.515, 0.050, 0.019),
                w("主人蓝海乐", 0.126, 0.555, 0.090, 0.016), w("主人蓝海乐", 0.127, 0.627, 0.088, 0.016),
                w("2", 0.105, 0.658, 0.019, 0.016)]
    }

    func testAGroupsLoneDigitIsReadUnderItsNameAndIsItsSenders() throws {
        let px = try group
        let bottom = try XCTUnwrap(px.inputTop(from: 0.3)) - 0.005
        let tops = F.avatarTops(px, bottom: bottom)
        let read = [Line(sender: "蓝海乐", text: "你好", mine: false, y: 0.5055),
                    Line(sender: "主人蓝海乐", text: "2", mine: false, y: 0.65)]
        // N84: each bubble from its own top, under its name row (the avatar's top is the name's)
        XCTAssertEqual(F.bubbleTop(px, from: 0.550), 0.5648, accuracy: 0.002)
        let privateChat = try bubbles
        XCTAssertEqual(F.bubbleTop(privateChat, from: 0.466), 0.466, accuracy: 0.002, "a private chat's bubble starts at its avatar")
        let found = F.unreadDigits(px, tops: tops, lines: read, bottom: bottom)
        XCTAssertEqual(found.map { $0.text }, ["1"], "N82: the name row over its bubble left out")
        XCTAssertEqual(found.first?.y ?? 0, 0.579, accuracy: 0.008)
        XCTAssertEqual(F.unreadDigits(px, tops: tops, lines: [], bottom: bottom).map { $0.text }, ["2", "1"], "你好 and older: no digits")
        let lines = F.withDigits(read, found, sender: "测试群", group: true, rows: groupRows())
        XCTAssertEqual(lines.map(\.text), ["你好", "1", "2"])
        XCTAssertEqual(lines[1].sender, "主人蓝海乐", "N81: its own name, not 蓝海乐's over the line before")
        XCTAssertEqual(F.withDigits(read, found, sender: "测试群").map(\.sender)[1], "蓝海乐", "not a group: the line over it")
        XCTAssertEqual(F.nameOver(groupRows(), y: 0.5055), "蓝海乐", "你好's own name, 0.022 over it")
        XCTAssertNil(F.nameOver(groupRows(), y: 0.45), "the time label 00:11 is no name")
        // its answer quotes it: on the 「1」 itself, under the name row
        let spot = try XCTUnwrap(F.digitSpot(px, rows: groupRows(), quote: "1"))
        XCTAssertEqual(Double(spot.y), 0.586, accuracy: 0.01)
    }

    /// N83: Echo 194's read of 测试群 under its mark (11-28 00:12, its read log): 「2」 from 「主人监海乐」 — the same name read
    /// right two rows up was 主人蓝海乐.
    func testANameReadOnceOneCharacterOffIsTheOneReadMoreOften() {
        func l(_ who: String, _ t: String) -> Line { Line(sender: who, text: t, mine: false) }
        let lines = [l("主人蓝海乐", "在吗"), l("主人蓝海乐", "多少钱"), l("蓝海乐", "在吗"), l("蓝海乐", "多少钱"), l("蓝海乐", "你好"),
                     l("主人监海乐", "2"), Line(sender: "我", text: "好的", mine: true)]
        XCTAssertEqual(F.steadySenders(lines, known: []).map(\.sender),
                       ["主人蓝海乐", "主人蓝海乐", "蓝海乐", "蓝海乐", "蓝海乐", "主人蓝海乐", "我"])
        // the history's names count too
        XCTAssertEqual(F.steadySenders([l("主人监海乐", "2")], known: ["主人蓝海乐", "主人蓝海乐"]).first?.sender, "主人蓝海乐")
        // two names each read twice stay as they are; a short name is never changed
        let two = [l("小王同学A", "1"), l("小王同学A", "2"), l("小王同学B", "3"), l("小王同学B", "4")]
        XCTAssertEqual(F.steadySenders(two, known: []).map(\.sender), two.map(\.sender))
        XCTAssertEqual(F.steadySenders([l("蓝海乐", "1"), l("蓝海东", "2"), l("蓝海东", "3")], known: []).first?.sender, "蓝海乐")
    }

    // MARK: N77 a digit to quote that OCR gives no words now

    func testADigitToQuoteIsFoundByItsBubble() throws {
        let px = try bubbles
        let one = try XCTUnwrap(F.digitSpot(px, rows: [], quote: "1"))
        XCTAssertEqual(Double(one.y), 0.485, accuracy: 0.015)
        XCTAssertLessThan(Double(one.x), 0.3, "on 蓝海乐's bubble, at the left")
        let two = try XCTUnwrap(F.digitSpot(px, rows: [], quote: "2"))
        XCTAssertEqual(Double(two.y), 0.541, accuracy: 0.015)
        XCTAssertNil(F.digitSpot(px, rows: [], quote: "3"), "no bubble of 3")
        XCTAssertNil(F.digitSpot(px, rows: [], quote: "你好"), "words are found by OCR, not here")
    }

    // MARK: N70b 「引用」 not read in its menu

    /// WeCom's menu over 「2」 as the iPad read it (11-28 00:12, its OCR, in the window's fractions): icons above their
    /// words, 复制 转发 引用 添加至 翻译 多选, under them 删除.
    func weComMenu(quote: Bool, icon: Bool) -> [[CandidatePicker.Piece]] {
        var rows = [m("蓝海乐：", 0.4859, 0.457, 0.1168, 0.016), m("账户交易明细（1）.xIs", 0.632, 0.478, 0.3038, 0.014),
                    m("包", 0.112, 0.522, 0.0487, 0.017), m("复制", 0.1082, 0.546, 0.0565, 0.012), m("→", 0.2425, 0.522, 0.0448, 0.016),
                    m("转发", 0.2386, 0.547, 0.0604, 0.014), m("添加至", 0.5093, 0.547, 0.0818, 0.014), m("さA", 0.6475, 0.522, 0.0565, 0.019),
                    m("翻译", 0.6456, 0.547, 0.0623, 0.014), m("多选", 0.78, 0.547, 0.0565, 0.014), m("向大圆", 0.1062, 0.61, 0.0857, 0.012),
                    m("删除", 0.2406, 0.61, 0.0565, 0.012)]
        if icon { rows.append(m("$6", 0.3769, 0.523, 0.037, 0.014)) }
        if quote { rows.append(m("引用", 0.3749, 0.547, 0.0565, 0.014)) }
        return rows
    }

    func testWeComsQuoteIsBetweenForwardAndAddTo() throws {
        let read = weComMenu(quote: true, icon: true)
        let item = try XCTUnwrap(F.menuItem(read, "引用"))
        for icon in [true, false] {
            let rows = weComMenu(quote: false, icon: icon)
            XCTAssertNil(F.menuItem(rows, "引用"))
            let band = try XCTUnwrap(F.menuBand(rows))
            let slot = try XCTUnwrap(F.quoteSlot(rows, in: band), "icon \(icon)")
            XCTAssertEqual(Double(slot.x), Double(item.x), accuracy: 0.01, "icon \(icon)")
            XCTAssertEqual(Double(slot.y), Double(item.y), accuracy: 0.002)
        }
        // 添加至 not read: nothing clicked blind
        let rows = weComMenu(quote: false, icon: true).filter { $0.first?.text != "添加至" }
        XCTAssertNil(F.quoteSlot(rows, in: try XCTUnwrap(F.menuBand(rows))))
        // another word read at its place: nothing clicked
        let other = weComMenu(quote: false, icon: true) + [m("翻m", 0.3749, 0.547, 0.0565, 0.014)]
        XCTAssertNil(F.quoteSlot(other, in: try XCTUnwrap(F.menuBand(other))))
        // 198 (Echo 197 11-28 06:16): 引用 misread at its place (「51用」, 「引m」) is clicked there
        for misread in ["51用", "引m"] {
            let rows = weComMenu(quote: false, icon: true) + [m(misread, 0.3749, 0.547, 0.0565, 0.014)]
            let slot = try XCTUnwrap(F.quoteSlot(rows, in: try XCTUnwrap(F.menuBand(rows))), misread)
            XCTAssertEqual(Double(slot.x), Double(item.x), accuracy: 0.01, misread)
        }
    }

    /// WeChat's menu over a 5" note (11-27 19:57, its OCR; the window 0.476 of the screen): 收藏 背景播放 转文字 删除 多选,
    /// then 引用 提醒 连续朗读; the small 转文字 button beside the note below.
    func testWeChatsQuoteIsLeftOfRemind() throws {
        func w(_ t: String, _ cx: Double, _ cy: Double, _ cw: Double, _ ch: Double) -> [CandidatePicker.Piece] {
            [q(t, x: (cx - cw / 2) / 0.476, y: cy - ch / 2, w: cw / 0.476, h: ch)]
        }
        let rows = [w("17", 0.112, 0.388, 0.029, 0.017), w("收藏", 0.064, 0.484, 0.044, 0.017), w("文", 0.239, 0.462, 0.019, 0.014),
                    w("转文字", 0.239, 0.485, 0.065, 0.019), w("背景", 0.152, 0.485, 0.046, 0.019), w("播放", 0.151, 0.504, 0.044, 0.019),
                    w("删除", 0.326, 0.485, 0.044, 0.019), w("多选", 0.415, 0.485, 0.042, 0.016),
                    w("提醒", 0.151, 0.577, 0.044, 0.019), w("连续", 0.239, 0.578, 0.044, 0.017), w("朗读", 0.240, 0.596, 0.049, 0.021),
                    w("•）5\"", 0.128, 0.657, 0.056, 0.017), w("转文字", 0.282, 0.658, 0.060, 0.012)]
        let band = try XCTUnwrap(F.menuBand(rows))
        let slot = try XCTUnwrap(F.quoteSlot(rows, in: band))
        XCTAssertEqual(Double(slot.x), 0.064 / 0.476, accuracy: 0.012, "where 引用 was read on the same menu")
        XCTAssertEqual(Double(slot.y), 0.578, accuracy: 0.003)
    }

    /// After the place by its neighbours was clicked and no quote bar came, only another titled page is backed out of:
    /// the same chat (its title read with 「(1)」 or a group's count) or a window told nothing of is left as it is.
    func testOnlyAnotherTitledPageIsBackedOutOfAfterAMissedQuote() {
        XCTAssertTrue(XiaoLanPanes.sameChat(.chat("蓝海乐"), .chat("蓝海乐")))
        XCTAssertFalse(XiaoLanPanes.sameChat(.chat("选择聊天"), .chat("蓝海乐")), "WeCom's 转发 page: backed out of")
        XCTAssertFalse(XiaoLanPanes.sameChat(.unknown, .chat("蓝海乐")))
        XCTAssertFalse(XiaoLanPanes.sameChat(.list, .chat("蓝海乐")))
    }

    // MARK: N78 a line with no words of its own is quoted too

    func testAPhotoOrANoteIsQuotedByItsTag() {
        XCTAssertEqual(ChatToolLink.quoteLine("[图片]\n小蓝看了：两个人在玩游戏"), "[图片]")
        XCTAssertEqual(ChatToolLink.quoteLine("[语音] 4\"\n语音转文字：多少钱"), "[语音]")
        XCTAssertEqual(ChatToolLink.quoteLine("[视频]"), "[视频]")
        XCTAssertEqual(F.tag(ChatToolLink.quoteLine("[图片]\n小蓝看了：…")), .image, "paneQuote finds it as a picture")
        XCTAssertEqual(F.tag(ChatToolLink.quoteLine("[语音] 4\"")), .voice)
        // words of its own: those, as before
        XCTAssertEqual(ChatToolLink.quoteLine("[链接] https://v.douyin.com/abc/\n网页：…"), "https://v.douyin.com/abc/")
        XCTAssertEqual(ChatToolLink.quoteLine("1"), "1")
        XCTAssertEqual(ChatToolLink.quoteLine(""), "")
    }

    // MARK: N79 the sharing stopped, the owner told

    func testTheOwnerIsToldOnceTheSharingIsGoneLongEnough() {
        XCTAssertFalse(XiaoLanPanes.shareGoneSay(5), "a restart by hand takes ~10 s")
        XCTAssertFalse(XiaoLanPanes.shareGoneSay(20))
        XCTAssertTrue(XiaoLanPanes.shareGoneSay(21))
    }
}
