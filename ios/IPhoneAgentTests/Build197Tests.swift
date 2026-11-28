import XCTest
import UIKit
@testable import IPhoneAgent

/// 197: every iPad move a Bezier curve, however short (N91), and what else 197 fixes.
@MainActor final class Build197Tests: XCTestCase {
    let span = (w: 5854, h: 7626)
    let mid: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }

    /// The stroke's points, as app units from its start.
    func points(_ s: String) -> [(Int, Int)] {
        let v = s.split(separator: " ").dropFirst().compactMap { Int($0) }
        var p = (0, 0), out: [(Int, Int)] = []
        for i in stride(from: 0, to: v.count - 1, by: 2) {
            p = (p.0 + v[i], p.1 + v[i + 1])
            out.append(p)
        }
        return out
    }

    /// N91 (user 11-28: 「必須强制走！不要設立門檻！」; Echo 195: `move -472 428`, 637 units, went straight): a short move
    /// is a curve with a bow that shows, lengthened as padShort lengthens a short move, ending where padShort's would.
    func testShortMoveIsACurveLengthenedLikePadShort() throws {
        let s = try XCTUnwrap(CommandChannel.padCurved("move -472 428", from: (3000, 3000), span: span, held: false,
                                                       step: 60, pace: 30, random: mid))
        XCTAssertTrue(s.hasPrefix("stroke "))
        let pts = points(s)
        let len = hypot(472.0, 428.0)
        let k = try XCTUnwrap(CommandChannel.padShortRatio(len))
        XCTAssertGreaterThan(k, 1)
        let end = try XCTUnwrap(pts.last)
        // where padShort would send it, back against the bow by 0.10 of it (bow 12 % at mid)
        XCTAssertEqual(hypot(Double(end.0) + 472 * k, Double(end.1) - 428 * k), 0.10 * 0.12 * len * k, accuracy: 3)
        let n = (x: -428 / len, y: -472 / len)  // perpendicular to (-472, 428)
        let bow = pts.map { abs(Double($0.0) * n.x + Double($0.1) * n.y) }.max() ?? 0
        XCTAssertGreaterThan(bow, 0.07 * len * k, "a bow that shows")
        XCTAssertGreaterThanOrEqual(pts.count, 8)
    }

    /// N91: a tiny move (the share check's 8 units, a correction) is still a curve; at another pace no lengthening.
    func testTinyMoveAndOtherPace() throws {
        let tiny = try XCTUnwrap(CommandChannel.padCurved("move 8 0", from: (3000, 3000), span: span, held: false,
                                                          step: 60, pace: 30, random: mid))
        let pts = points(tiny)
        XCTAssertEqual(Double(pts.last!.0), 80, accuracy: 2)  // padShort sends 8 as 80
        XCTAssertTrue(pts.contains { $0.1 != 0 }, "not a straight line")
        let slow = try XCTUnwrap(CommandChannel.padCurved("move 300 0", from: (3000, 3000), span: span, held: false,
                                                          step: 10, pace: 20, random: mid))
        XCTAssertEqual(Double(points(slow).last!.0), 300, accuracy: 2)
    }

    /// N91: by an edge the bow goes the other way or gets smaller, never straight and never off the screen.
    func testCurveAlongAnEdgeStaysOnTheScreen() throws {
        for (from, by) in [((0, 3000), (0, 300)), ((5854, 100), (0, 900)), ((10, 7620), (500, 0))] {
            let s = try XCTUnwrap(PadCurve.stroke(from: from, by: by, span: span, random: mid), "\(by)")
            let pts = points(s)
            for p in pts {
                XCTAssertTrue((0...span.w).contains(from.0 + p.0) && (0...span.h).contains(from.1 + p.1), "\(p) off the screen")
            }
            let across = pts.map { by.0 == 0 ? abs($0.0) : abs($0.1) }.max() ?? 0
            XCTAssertGreaterThan(across, 0, "\(by): a bow")
        }
        XCTAssertNil(PadCurve.stroke(from: (0, 0), by: (0, 0), span: span), "no move, nothing sent")
    }

    // MARK: Group orders by fixed steps (206 / 207 / 219; screens of Echo 195, 11-28 02:03–02:35)

    typealias G = XiaoLanGroups
    /// A piece by its middle in window fractions; `screen` y is converted by the window's height (0.879 of the screen).
    func m(_ t: String, _ cx: Double, _ sy: Double, w: Double = 0.2, h: Double = 0.02) -> [CandidatePicker.Piece] {
        let cy = sy / 0.879
        return [CandidatePicker.Piece(text: t, box: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))]
    }
    func fixture(_ name: String) throws -> WatchOCR.Pixels {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "png"), name)
        return try XCTUnwrap(WatchOCR.Pixels(try Data(contentsOf: url)), name)
    }

    /// The ＋ and − tiles have no words: found by their glyphs. WeChat with 3 members (w08: ＋ ends the first row, − starts
    /// the second), with 2 (w18: both on the first row; the 群公告 text under the grid has strokes like a glyph), WeCom
    /// with 2 (q20). Measured by hand on the frames: w08 ＋ (0.864, 0.135) − (0.134, 0.238); w18 ＋ (0.621, 0.134)
    /// − (0.864, 0.134); q20 ＋ (0.501, 0.212) − (0.688, 0.211).
    func testMemberTilesFoundWithoutWords() throws {
        let cases: [(String, [[CandidatePicker.Piece]], CGPoint, CGPoint)] = [
            ("wechat-group-info-3", [m("群聊名称", 0.14, 0.314)], CGPoint(x: 0.864, y: 0.135), CGPoint(x: 0.134, y: 0.238)),
            ("wechat-group-info-2", [], CGPoint(x: 0.621, y: 0.134), CGPoint(x: 0.864, y: 0.134)),
            ("wechat-group-info-2", [m("群聊名称", 0.14, 0.223), m("Echo群公告测试", 0.2, 0.350, w: 0.35)],
             CGPoint(x: 0.621, y: 0.134), CGPoint(x: 0.864, y: 0.134)),
            ("wecom-group-info-2", [m("查看全部群成员", 0.25, 0.283)], CGPoint(x: 0.501, y: 0.212), CGPoint(x: 0.688, y: 0.211)),
        ]
        for (name, rows, plus, minus) in cases {
            let t = G.tiles(try fixture(name), rows)
            let p = try XCTUnwrap(t.plus, "\(name): ＋"), n = try XCTUnwrap(t.minus, "\(name): −")
            XCTAssertEqual(Double(p.x), Double(plus.x), accuracy: 0.01, name); XCTAssertEqual(Double(p.y), Double(plus.y), accuracy: 0.01, name)
            XCTAssertEqual(Double(n.x), Double(minus.x), accuracy: 0.01, name); XCTAssertEqual(Double(n.y), Double(minus.y), accuracy: 0.01, name)
        }
    }

    /// A picker's 完成 / 确定 and its count, as OCR read them (w04, w06, q04, q19); 小藍's own 完成 key is not it.
    func testDoneButtonCount() {
        XCTAssertEqual(G.doneButton([m("完成（2）", 0.85, 0.054)])?.count, 2)
        XCTAssertEqual(G.doneButton([m("完成・1", 0.9, 0.605)])?.count, 1)
        XCTAssertEqual(G.doneButton([m("确定・1", 0.9, 0.846)])?.count, 1)
        XCTAssertEqual(G.doneButton([m("完成(1)", 0.87, 0.724)])?.count, 1)
        XCTAssertEqual(G.doneButton([m("完成", 0.88, 0.054)])?.count, 0)
        XCTAssertNil(G.doneButton([m("小藍 已填入：主人蓝海乐", 0.5, 0.875, w: 0.5), m("完成", 0.87, 0.916)]), "the keyboard's key")
        XCTAssertNil(G.doneButton([m("完成任务", 0.5, 0.3)]))
    }

    /// Search results named exactly so, top first, under the 联系人 header and above the keyboard: WeChat lists two 蓝海乐
    /// (w05: 0.267 and 0.407; 主人蓝海乐 between them is another name); WeCom shows 「@微信」 and colleagues (q05).
    func testSearchResultsByExactName() {
        let wechat = [m("取消", 0.09, 0.054), m("蓝海乐", 0.32, 0.118), m("搜索结果", 0.12, 0.174), m("联系人", 0.1, 0.216),
                      m("多选", 0.9, 0.174), m("蓝海乐", 0.27, 0.267), m("主人蓝海乐", 0.32, 0.337), m("蓝海乐", 0.27, 0.407),
                      m("小藍 已填入：蓝海乐", 0.5, 0.875, w: 0.5)]
        assertClose(G.results("蓝海乐", wechat).map { Double($0.y) * 0.879 }, [0.267, 0.407], accuracy: 0.002)
        XCTAssertEqual(G.results("主人蓝海乐", wechat).count, 1)
        let wecom = [m("Q蓝海乐", 0.16, 0.103), m("＆联系人", 0.12, 0.142), m("主人蓝海乐", 0.38, 0.171) + m("＠微信", 0.6, 0.172, w: 0.1),
                     m("微信联系人", 0.35, 0.192), m("蓝海乐＠微信", 0.4, 0.225), m("微信联系人", 0.35, 0.246), m("蓝海乐", 0.3, 0.278),
                     m("青石信息咨询", 0.38, 0.300), m("蓝海乐", 0.3, 0.332), m("小藍已填入：蓝海乐", 0.5, 0.875, w: 0.5)]
        assertClose(G.results("蓝海乐", wecom).map { Double($0.y) * 0.879 }, [0.225, 0.278, 0.332], accuracy: 0.002)
        XCTAssertEqual(G.results("主人蓝海乐", wecom).count, 1)
        XCTAssertTrue(G.results("小蓝", wecom).isEmpty)
    }

    /// The pages a step waits for.
    func testPagesTold() {
        XCTAssertTrue(G.infoPage([m("聊天信息（3）", 0.5, 0.055), m("群聊名称", 0.14, 0.314)]))
        XCTAssertTrue(G.infoPage([m("查看全部群成员", 0.25, 0.283), m("群公告", 0.13, 0.340)]))
        XCTAssertTrue(G.infoPage([m("群公告", 0.13, 0.340), m("群管理", 0.13, 0.660)]))
        XCTAssertFalse(G.infoPage([m("群公告", 0.24, 0.054), m("编辑", 0.92, 0.054)]))
        let create = [m("取消", 0.09, 0.054), m("发起群聊", 0.5, 0.054), m("Q搜索", 0.5, 0.102)]
        XCTAssertTrue(G.picker(create, titles: G.createTitles))
        XCTAssertFalse(G.picker([m("发起群聊", 0.84, 0.108), m("Q搜索", 0.5, 0.106)], titles: G.createTitles), "the ＋ menu's row")
        XCTAssertTrue(G.picker([m("添加群成员", 0.5, 0.054), m("Q搜索", 0.5, 0.104)], titles: G.addTitles))
        XCTAssertTrue(G.picker([m("移出成员", 0.5, 0.054), m("搜索", 0.2, 0.103)], titles: G.removeTitles))
        XCTAssertEqual(G.titleName(.chat("Echo建群测试（3）")), "Echo建群测试")
        XCTAssertNil(G.titleName(.list))
    }

    /// N90 (Echo 195 17:53): Codex tapped (864, 134) for 「发起群聊」 (WeCom's menu: 发起群聊 0.104, 记录面聊 0.159) and
    /// opened 记录面聊; the tap goes to the label its thought names. A thought naming nothing, or a tap on the label
    /// already, stays.
    func testModelTapMovedOntoTheLabelItNames() throws {
        let menu = [CandidatePicker.Piece(text: "•发起群聊", box: CGRect(x: 0.83, y: 0.094, width: 0.09, height: 0.02)),
                    CandidatePicker.Piece(text: "记录面聊", box: CGRect(x: 0.85, y: 0.149, width: 0.08, height: 0.02))]
        XCTAssertEqual(TapSnap.labels("点“发起群聊”建群"), ["发起群聊"])
        XCTAssertTrue(TapSnap.labels("在企业微信里点发起群聊").contains("发起群聊"))
        let s = try XCTUnwrap(TapSnap.spot(x: 0.864, y: 0.134, thought: "点“发起群聊”", pieces: menu))
        XCTAssertEqual(Double(s.y), 0.104, accuracy: 0.001)
        XCTAssertNil(TapSnap.spot(x: 0.864, y: 0.134, thought: "tap the plus", pieces: menu))
        XCTAssertNil(TapSnap.spot(x: 0.875, y: 0.104, thought: "点“发起群聊”", pieces: menu), "on it already")
        XCTAssertNil(TapSnap.spot(x: 0.3, y: 0.6, thought: "点“发起群聊”", pieces: menu), "too far")
    }

    /// N78: of two pictures (or voice notes, videos, links) the earlier answer quotes the earlier one.
    func testEarlierAnswerQuotesTheEarlierLine() {
        let rows = [[CandidatePicker.Piece(text: "4\"", box: CGRect(x: 0.2, y: 0.3, width: 0.1, height: 0.03))],
                    [CandidatePicker.Piece(text: "6\"", box: CGRect(x: 0.2, y: 0.6, width: 0.1, height: 0.03))]]
        let last = XiaoLanMediaFind.mediaQuoteSpot(rows, nil, quote: "[语音]")
        let earlier = XiaoLanMediaFind.mediaQuoteSpot(rows, nil, quote: "[语音]", fromEnd: 2)
        XCTAssertNotNil(last)
        XCTAssertNotNil(earlier)
        if let a = last, let b = earlier { XCTAssertLessThan(Double(b.y), Double(a.y)) }
        XCTAssertEqual(XiaoLanMediaFind.mediaQuoteSpot(rows, nil, quote: "[语音]", fromEnd: 9)?.y, earlier?.y, "more than shown: the first")
    }

    /// N83's edge: a new member one character off a frequent writer is another person, unless the two characters are
    /// ones OCR mixes up (蓝 / 监).
    func testOneCharacterOffIsASlipOnlyForLookAlikes() {
        func l(_ who: String, _ t: String) -> WatchReport.Line { WatchReport.Line(sender: who, text: t, mine: false) }
        XCTAssertTrue(XiaoLanMediaFind.ocrSlip("主人蓝海乐", "主人监海乐"))
        XCTAssertFalse(XiaoLanMediaFind.ocrSlip("主人蓝海乐", "主人蓝海东"))
        let lines = [l("主人蓝海乐", "在吗"), l("主人蓝海乐", "多少钱"), l("主人蓝海东", "我是新来的")]
        XCTAssertEqual(XiaoLanMediaFind.steadySenders(lines, known: []).map(\.sender), ["主人蓝海乐", "主人蓝海乐", "主人蓝海东"])
        XCTAssertEqual(XiaoLanMediaFind.steadySenders([l("主人蓝海东", "1")], known: [], names: ["主人蓝海乐"]).first?.sender, "主人蓝海东")
    }
}

/// 197: 跟圈 (260) and 爬楼 (515) by fixed steps, on Echo 197's screens of 11-28 (m03 album, m04 picture, m06 post page).
@MainActor final class Build197FollowTests: XCTestCase {
    typealias G = XiaoLanGroups
    /// A piece by its middle in window fractions (screen x over the window's 0.4875, y over 0.879).
    func s(_ t: String, _ sx: Double, _ sy: Double, w: Double = 0.1, h: Double = 0.02) -> [CandidatePicker.Piece] {
        let cx = sx / 0.4875, cy = sy / 0.879
        return [CandidatePicker.Piece(text: t, box: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))]
    }
    var now: Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (2026, 11, 28, 4, 30)
        return Calendar(identifier: .gregorian).date(from: c)!
    }
    func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute) = (y, m, d, h, mi)
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// m03: 13 8月 a picture with 「AI嫖客」 beside it (the words inside the picture left out), 12 8月 a picture, 08 8月
    /// words alone in the grey box.
    func testAlbumPostsByDate() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "wechat-moments-album", withExtension: "png"))
        let px = try XCTUnwrap(WatchOCR.Pixels(try Data(contentsOf: url)))
        let rows = [s("L8768HY", 0.422, 0.372), s("138月", 0.047, 0.452), s("不談工具", 0.176, 0.444), s("AI嫖客③", 0.269, 0.451, w: 0.17),
                    s("128月", 0.047, 0.561), s("这帽子给我扣的區", 0.314, 0.558, w: 0.36), s("088月", 0.051, 0.668),
                    s("一批特价剧350量大从优可以", 0.283, 0.674, w: 0.6), s("咸鱼先上后付，支持平台交易", 0.267, 0.702, w: 0.55),
                    s("078月", 0.048, 0.760), s("一批特价剧350可以咸鱼先上", 0.278, 0.765, w: 0.6)]
        let posts = G.posts(rows, px)
        XCTAssertEqual(posts.map(\.date), ["138月", "128月", "088月", "078月"])
        XCTAssertEqual(posts[0].text, "AI嫖客③")
        XCTAssertNotNil(posts[0].picture)
        XCTAssertNotNil(posts[1].picture)
        XCTAssertNil(posts[2].picture, "words alone")
        XCTAssertEqual(posts[2].text, "一批特价剧350量大从优可以咸鱼先上后付，支持平台交易")
        XCTAssertEqual(G.postDay("138月", year: nil, now: now), day(2026, 8, 13))
        XCTAssertEqual(G.postDay("0512月", year: nil, now: now), day(2025, 12, 5), "ahead of today: last year")
        XCTAssertEqual(G.postDay("0512月", year: 2024, now: now), day(2024, 12, 5))
        XCTAssertEqual(G.postDay("昨天", year: nil, now: now), day(2026, 11, 27))
    }

    /// 198: a date at the window's very foot (0.99, under the 0.97 floor) is a cut post: left out, never a range whose
    /// top is under its bottom (that stops the app).
    func testAlbumDateAtTheFootLeftOut() {
        let rows = [s("138月", 0.047, 0.452), s("不談工具", 0.276, 0.444, w: 0.3), s("128月", 0.047, 0.99)]
        XCTAssertEqual(G.posts(rows, nil).map(\.date), ["138月"])
    }

    /// A chat's time lines as WeChat writes them (测试群, 11-28: 「01:20」 「昨天12:10」).
    func testChatTimeLines() {
        XCTAssertEqual(G.chatTime("01:20", now: now), day(2026, 11, 28, 1, 20))
        XCTAssertEqual(G.chatTime("昨天12:10", now: now), day(2026, 11, 27, 12, 10))
        XCTAssertEqual(G.chatTime("星期一 10:00", now: now), day(2026, 11, 23, 10, 0), "11-28 is a Saturday")
        XCTAssertEqual(G.chatTime("11月20日 10:08", now: now), day(2026, 11, 20, 10, 8))
        XCTAssertEqual(G.chatTime("下午3:20", now: now), day(2026, 11, 28, 15, 20))
        XCTAssertEqual(G.chatTime("2025年6月25日 10:08", now: now), day(2025, 6, 25, 10, 8))
        XCTAssertNil(G.chatTime("主人蓝海乐", now: now))
    }

    /// m06: a post's own page; m04: a picture's viewer.
    func testPostPageAndViewer() throws {
        let page = [s("详情", 0.244, 0.054), s("蓝海乐", 0.112, 0.101), s("一批特价剧350量大从优可以咸鱼", 0.271, 0.128, w: 0.6),
                    s("先上后付，支持平台交易", 0.207, 0.155, w: 0.45), s("2026年8月8日22:40", 0.177, 0.183, w: 0.3), s("发表评论：", 0.074, 0.850)]
        let d = try XCTUnwrap(G.postDetail(page, friend: "蓝海乐"))
        XCTAssertEqual(d.text, "一批特价剧350量大从优可以咸鱼先上后付，支持平台交易")
        XCTAssertEqual(d.time, "2026年8月8日22:40")
        let viewer = [s("2026年8月13日00:04", 0.244, 0.054, w: 0.4), s("AI江湖", 0.347, 0.235), s("Al嫖客⑦", 0.065, 0.817),
                      s("♥赞口评论", 0.089, 0.863, w: 0.15), s("详情＞", 0.445, 0.863)]
        XCTAssertEqual(G.viewerTitle(viewer), "2026年8月13日00:04")
        XCTAssertEqual(G.viewerCaption(viewer), "Al嫖客⑦")
        XCTAssertNil(G.viewerTitle(page))
        XCTAssertNil(G.postDetail(viewer, friend: "蓝海乐"), "no time line on a viewer's page")
    }

    /// A read up, oldest first, each line once.
    func testClimbMergeOldestFirst() {
        func l(_ who: String, _ t: String) -> WatchReport.Line { WatchReport.Line(sender: who, text: t, mine: false) }
        let newest = [l("蓝海乐", "你好"), l("主人蓝海乐", "1")], older = [l("主人蓝海乐", "在吗"), l("蓝海乐", "你好")]
        XCTAssertEqual(G.climbMerge([newest, older]).map(\.text), ["在吗", "你好", "1"])
    }
}

/// 198: friend requests accepted by themselves (AutoAccept), on Echo 197's screens of 11-28 04:55–05:00.
@MainActor final class Build198AcceptTests: XCTestCase {
    func p(_ t: String, _ cx: Double, _ cy: Double, w: Double = 0.1, h: Double = 0.02) -> [CandidatePicker.Piece] {
        [CandidatePicker.Piece(text: t, box: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))]
    }

    /// f20: a red mark over 通讯录 (WeChat's, drawn where it was: +0.033, −0.040 from the word); none, none.
    func testContactsMarkOnTheTabBar() throws {
        func window(mark: Bool) throws -> WatchOCR.Pixels {
            let size = CGSize(width: 456, height: 1126)
            let png = UIGraphicsImageRenderer(size: size).pngData { c in
                UIColor.white.setFill()
                c.fill(CGRect(origin: .zero, size: size))
                if mark {
                    UIColor(red: 250 / 255, green: 81 / 255, blue: 81 / 255, alpha: 1).setFill()
                    c.cgContext.fillEllipse(in: CGRect(x: 0.406 * 456 - 11, y: 0.944 * 1126 - 11, width: 22, height: 22))
                }
            }
            return try XCTUnwrap(WatchOCR.Pixels(png))
        }
        let rows = [p("微信", 0.12, 0.984), p("通讯录", 0.373, 0.984), p("发现", 0.62, 0.984), p("我", 0.88, 0.984)]
        XCTAssertTrue(AutoAccept.contactsMarked(rows, try window(mark: true)))
        XCTAssertFalse(AutoAccept.contactsMarked(rows, try window(mark: false)))
        XCTAssertFalse(AutoAccept.contactsMarked([p("通讯录", 0.5, 0.06)], try window(mark: true)), "a title, not the tab bar")
    }

    /// f23 / f27 (WeChat 新的朋友) and f31 (WeCom 新的客户): the waiting rows' 「查看」, the lowest is the first made.
    func testWaitingRequests() {
        let wechat = [p("新朋友", 0.5, 0.061), p("近三天", 0.1, 0.173), p("清青", 0.24, 0.215), p("我是清青", 0.27, 0.243), p("查看", 0.886, 0.224)]
        XCTAssertTrue(AutoAccept.requestsPage(wechat))
        XCTAssertEqual(AutoAccept.waiting(wechat).count, 1)
        XCTAssertEqual(AutoAccept.requester(wechat, at: 0.224), "清青")
        let done = [p("新朋友", 0.5, 0.061), p("清青", 0.24, 0.215), p("已添加", 0.896, 0.21)]
        XCTAssertTrue(AutoAccept.waiting(done).isEmpty)
        let wecom = [p("添加客户", 0.45, 0.061), p("新的客户", 0.67, 0.061), p("清青＠微信", 0.3, 0.198), p("查看", 0.902, 0.208),
                     p("蓝＠微信", 0.27, 0.289), p("已添加", 0.907, 0.300), p("主人蓝海乐@微信", 0.36, 0.415), p("已添加", 0.907, 0.425),
                     p("新来的@微信", 0.3, 0.52), p("查看", 0.902, 0.53)]
        XCTAssertTrue(AutoAccept.requestsPage(wecom))
        XCTAssertEqual(AutoAccept.waiting(wecom).map { Double($0.y) }, [0.208, 0.53])
        XCTAssertEqual(AutoAccept.requester(wecom, at: 0.53), "新来的")
        XCTAssertFalse(AutoAccept.requestsPage([p("通讯录", 0.5, 0.061)]))
        // the lowest waiting near the window's end: older ones may be under it (10 at once, ~7–9 rows a window)
        XCTAssertFalse(AutoAccept.maybeBelow(wecom))
        XCTAssertFalse(AutoAccept.maybeBelow(done))
        XCTAssertTrue(AutoAccept.maybeBelow(wecom + [p("最早的@微信", 0.3, 0.86), p("查看", 0.902, 0.87)]))
    }

    /// 198 (Echo 197 11-28 05:17): WeChat's list scrolled past its search bar, the top row's title at 0.104 — its mark
    /// is still seen; the title bar's 「微信 (1)」 (~0.053) is no chat.
    func testTopRowWithoutSearchBar() {
        let rows = [p("微信 (1)", 0.5, 0.053), p("测试群", 0.28, 0.104, w: 0.14), p("蓝海乐: 1", 0.31, 0.127, w: 0.2),
                    p("腾讯新闻", 0.29, 0.183, w: 0.16), p("APEC会议落幕", 0.4, 0.206, w: 0.4)]
        XCTAssertEqual(XiaoLanPanes.marked(rows, red: { _ in 0.3 }).map(\.name), ["测试群"])
        // the title's unread count (the list pulled down when no row in view shows a mark); a chat's head count is none
        XCTAssertEqual(XiaoLanPanes.titleUnread(rows), 1)
        XCTAssertEqual(XiaoLanPanes.titleUnread([p("微信（12）", 0.5, 0.053)]), 12)
        XCTAssertNil(XiaoLanPanes.titleUnread([p("微信", 0.5, 0.053)]))
        XCTAssertNil(XiaoLanPanes.titleUnread([p("测试群(6)", 0.5, 0.053)]))
    }

    /// 198 (Echo 197 11-28 05:29): two pictures, the mark read 1 with only the first in — sure of the last line read,
    /// both are new; with no history, the mark's number as before.
    func testMarkSaidOneTwoPicturesAfterTheLastLineRead() {
        func l(_ t: String, mine: Bool = false) -> WatchReport.Line { WatchReport.Line(sender: mine ? "" : "蓝海乐", text: t, mine: mine) }
        let history = [l("这是什么意思"), l("在的，请问有什么可以帮您？", mine: true)]
        let lines = history + [l("[图片]"), l("[图片]")]
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: history, opened: .mark(1)).lines.count, 2)
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: history, opened: .mark(2)).lines.count, 2)
        XCTAssertEqual(XiaoLanBatch.pick(lines, history: nil, opened: .mark(1)).lines.count, 1)
    }

    /// 198 (Echo 197 11-28 06:05): 「Echo建群测试2」 deleted, 「Echo建群测试」 left on the list is another chat; a cut name
    /// with its … still counts as the one deleted.
    func testDeletedChatNotTakenForAnother() {
        let left = [p("Echo建群测试", 0.3, 0.5, w: 0.2), p("你已解散此群组", 0.3, 0.525, w: 0.2)]
        XCTAssertTrue(XiaoLanPanes.gone("Echo建群测试2", left))
        XCTAssertFalse(XiaoLanPanes.gone("Echo建群测试", left))
        XCTAssertFalse(XiaoLanPanes.gone("Echo建群测试2", [p("Echo建群测试…", 0.3, 0.5, w: 0.2)]))
        XCTAssertFalse(XiaoLanPanes.gone("Echo建群测试2", [p("Echo建群测试 2", 0.3, 0.5, w: 0.2)]))
        XCTAssertFalse(XiaoLanPanes.gone("Echo建群测试2", [p("Echo建群测试", 0.3, 0.5, w: 0.2), p("删除", 0.9, 0.5, w: 0.1)]),
                       "its row slid open: the name cut by the buttons, no … (B36)")
    }

    /// 198 (218 by fixed steps; the iPad's ＋ panels and file picker 11-28 13:30–13:37): the panel by its words, 文件 only
    /// by its exact word; the picker's way down 浏览 → 我的 iPad → Echo → orders; the file by its stem.
    func testSendFileSteps() {
        XCTAssertEqual(XiaoLanGroups.fileStem("EchoTest218.pdf"), "EchoTest218")
        let page2 = [p("个人名片", 0.15, 0.71, w: 0.1), p("文件", 0.37, 0.71, w: 0.06), p("音乐", 0.6, 0.71, w: 0.06)]
        XCTAssertTrue(XiaoLanGroups.plusPanel(page2))
        XCTAssertFalse(XiaoLanGroups.plusPanel([p("文件", 0.37, 0.71, w: 0.06)]), "one word is no panel")
        let wecom2 = [p("发起收款", 0.15, 0.68, w: 0.1), p("文件", 0.38, 0.68, w: 0.06), p("应用", 0.6, 0.68, w: 0.06), p("个人名片", 0.15, 0.8, w: 0.1)]
        XCTAssertEqual(XiaoLanGroups.find(wecom2, ["文件"], exact: true, band: 0.5...0.97).map { Double($0.x) } ?? 0, 0.38, accuracy: 0.001, "never 发起收款")
        let tabs = [p("最近项目", 0.2, 0.93, w: 0.1), p("共享", 0.5, 0.93, w: 0.06), p("浏览", 0.7, 0.93, w: 0.06)]
        let recent = [p("最近项目", 0.5, 0.06, w: 0.12), p("无最近项目", 0.5, 0.45, w: 0.2)] + tabs
        XCTAssertTrue(XiaoLanGroups.filePicker(recent))
        XCTAssertEqual(XiaoLanGroups.pickerNext(recent)?.what, "浏览")
        XCTAssertEqual(XiaoLanGroups.pickerNext([p("我的 iPad", 0.5, 0.06, w: 0.12), p("Echo", 0.17, 0.25, w: 0.08)] + tabs)?.what, "Echo")
        let echo = [p("Echov", 0.5, 0.06, w: 0.1), p("debug", 0.17, 0.25, w: 0.08), p("orders", 0.5, 0.6, w: 0.1)] + tabs
        XCTAssertEqual(XiaoLanGroups.pickerNext(echo)?.what, "orders")
        let orders = [p("orders", 0.5, 0.06, w: 0.1), p("EchoTest218", 0.17, 0.32, w: 0.15), p("593 字节", 0.17, 0.36, w: 0.1)] + tabs
        XCTAssertEqual(XiaoLanGroups.pickerFile(orders, "EchoTest218").map { Double($0.y) } ?? 0, 0.32, accuracy: 0.001)
        XCTAssertNil(XiaoLanGroups.pickerFile(orders, "EchoTest219"))
        XCTAssertNotNil(XiaoLanGroups.pickerFile([p("账户交易明细(1…", 0.17, 0.32, w: 0.15)], XiaoLanGroups.fileStem("账户交易明细(1).xls")), "a long name shown cut")
    }

    /// 198 (B18, Echo 197 11-28 16:18): a chat whose left strip lies on the split's shadow is still told by its grey
    /// further in; a white page is no chat.
    func testChatGreyBesideTheSplitsShadow() throws {
        func window(strip: UIColor, rest: UIColor) throws -> WatchOCR.Pixels {
            let size = CGSize(width: 470, height: 1126)
            let png = UIGraphicsImageRenderer(size: size).pngData { c in
                rest.setFill()
                c.fill(CGRect(origin: .zero, size: size))
                strip.setFill()
                c.fill(CGRect(x: 0, y: 0, width: 10, height: size.height))
            }
            return try XCTUnwrap(WatchOCR.Pixels(png))
        }
        let shadow = UIColor(red: 202 / 255, green: 203 / 255, blue: 207 / 255, alpha: 1)
        let grey = UIColor(red: 236 / 255, green: 237 / 255, blue: 241 / 255, alpha: 1)
        XCTAssertTrue(XiaoLanPanes.chatBackground(try window(strip: shadow, rest: grey)))
        XCTAssertFalse(XiaoLanPanes.chatBackground(try window(strip: .white, rest: .white)))
    }

    /// 198 (B16/B17, Echo 197 11-28 15:41–15:43): the chat open, no mark, the last line read not on the window — theirs
    /// under my newest line that were never read here are new; read before, or a quote box's 「name：…」, not.
    func testLiveTheirsAfterMyNewestLine() {
        func l(_ t: String, mine: Bool = false) -> WatchReport.Line { WatchReport.Line(sender: mine ? "我" : "蓝海乐", text: t, mine: mine) }
        let history = [l("很久以前的一句话"), l("另一句很久以前的话", mine: true)]
        let lines = [l("这里面是什么"), l("不好意思呀，没法帮您处理导航相关的问题哦", mine: true),
                     l("你工号多少 我要表扬你"), l("A18小黄人 个人名片")]
        let seen: Set<String> = [XiaoLanSelf.plain("这里面是什么")]
        let pick = XiaoLanBatch.pick(lines, history: history, opened: .live, seen: seen)
        XCTAssertEqual(pick.lines.map(\.text), ["你工号多少 我要表扬你", "A18小黄人 个人名片"])
        let read = XiaoLanBatch.pick(lines, history: history, opened: .live,
                                     seen: seen.union([XiaoLanSelf.plain("你工号多少 我要表扬你"), XiaoLanSelf.plain("A18小黄人 个人名片")]))
        XCTAssertTrue(read.lines.isEmpty, "read before: nothing new")
        XCTAssertTrue(XiaoLanBatch.pick([l("你好", mine: true), l("蓝海乐：这里面是什么")], history: history, opened: .live).lines.isEmpty,
                      "a quote box's line is no message")
    }

    /// 198 (218 pictures; WeChat's album 11-28 14:58): its foot told; 「发送(1)」 only with one chosen; the newest's ring.
    func testNewestPhotoSteps() {
        let foot = [p("预览(1)", 0.08, 0.97, w: 0.1), p("原图", 0.5, 0.97, w: 0.06), p("发送(1)", 0.86, 0.97, w: 0.1)]
        XCTAssertTrue(XiaoLanGroups.photoAlbum(foot))
        XCTAssertEqual(XiaoLanGroups.photoSend(foot).map { Double($0.x) } ?? 0, 0.86, accuracy: 0.001)
        XCTAssertNil(XiaoLanGroups.photoSend([p("发送", 0.86, 0.97, w: 0.06)]), "none chosen")
        XCTAssertNil(XiaoLanGroups.photoSend([p("发送(2)", 0.86, 0.97, w: 0.1)]), "two chosen: never sent")
        XCTAssertNotNil(XiaoLanGroups.photoSend([p("发送 （1）", 0.86, 0.97, w: 0.1)]))
        let ring = XiaoLanGroups.newestRing([p("最近项目", 0.5, 0.057, w: 0.2)])
        XCTAssertEqual(Double(ring.x), 0.199, accuracy: 0.001)
        XCTAssertEqual(Double(ring.y), 0.109, accuracy: 0.001)
    }

    /// 198 (B10, Echo 197 11-28 15:42): a group quote's lone 「@name 」 before the reply is the quote's own; anything more
    /// before it still stops the send (words dictated in, 185).
    func testMentionBeforeTheReplyIsTheQuotes() {
        let t = "好的，祝您生活愉快，再见！"
        XCTAssertTrue(KeyboardLink.fieldMatches(t, before: "@蓝海乐 " + t, after: ""))
        XCTAssertTrue(KeyboardLink.fieldMatches(t, before: "@蓝海乐\u{2005}" + t, after: nil))
        XCTAssertTrue(KeyboardLink.fieldMatches(t, before: "＠主人蓝海乐 " + t, after: nil))
        XCTAssertFalse(KeyboardLink.fieldMatches(t, before: "@蓝海乐 看看我" + t, after: nil))
        XCTAssertFalse(KeyboardLink.fieldMatches(t, before: "看看我" + t, after: nil))
    }

    /// 198 (B13, Echo 197 11-28 15:44): a shared card read as three lines under one avatar is one message; two avatars,
    /// two; mine never joined to theirs.
    func testLinesUnderOneAvatarAreOneMessage() {
        func l(_ t: String, _ y: Double, mine: Bool = false) -> WatchReport.Line {
            WatchReport.Line(sender: mine ? "我" : "蓝海乐", text: t, mine: mine, y: y)
        }
        let card = [l("一没在Y大と右", 0.50), l("Gemini4GoogleSEO水..0想要变壮的will", 0.58), l("Gemini4GoogleSEO水平已经无人能敌", 0.62)]
        let one = XiaoLanMediaFind.oneLinePerAvatar(card, tops: [0.495])
        XCTAssertEqual(one.count, 1)
        XCTAssertTrue(one[0].text.hasPrefix("一没在Y大と右 Gemini4GoogleSEO"))
        XCTAssertEqual(XiaoLanMediaFind.oneLinePerAvatar(card, tops: [0.57, 0.495]).count, 2, "lowest first or not, two avatars two messages")
        let mixed = [l("你好", 0.40), l("在的", 0.48, mine: true), l("1", 0.56)]
        XCTAssertEqual(XiaoLanMediaFind.oneLinePerAvatar(mixed, tops: [0.395]).count, 3, "mine between: never joined")
        XCTAssertEqual(XiaoLanMediaFind.oneLinePerAvatar(card, tops: []).count, 3, "no avatar seen: as they are")
    }

    /// 198 (B4, Echo 197 11-28 05:24): Echo's own notice over a window's top is no chat's title; a chat's is.
    func testOwnNoticeIsNoTitle() {
        XCTAssertTrue(XiaoLanPanes.ownNotice("「蓝海乐」：微信里没找到输入框。请看一下这个聊天，需要的话手动回复。"))
        XCTAssertTrue(XiaoLanPanes.ownNotice("小蓝有一条回复没发出去"))
        XCTAssertFalse(XiaoLanPanes.ownNotice("蓝海乐"))
        XCTAssertFalse(XiaoLanPanes.ownNotice("企微测试群(7)"))
        XCTAssertEqual(XiaoLanPanes.titleLine([p("「蓝海乐」：微信里没找到输入框。请看一下", 0.5, 0.05, w: 0.6), p("测试群(6)", 0.5, 0.07, w: 0.2)]), "测试群(6)")
    }

    /// 198 (205 by fixed steps; the iPad's 「选择聊天」 of both apps 11-28 06:26–06:29): rows by their exact names only,
    /// tags and head counts off; the 「发送给」 sheet's 发送.
    func testForwardSteps() {
        let wechat = [p("关闭", 0.06, 0.06, w: 0.06), p("选择聊天", 0.5, 0.06, w: 0.2), p("多选", 0.93, 0.06, w: 0.06),
                      p("蓝海乐", 0.22, 0.23, w: 0.15), p("测试群 (6人)", 0.25, 0.30, w: 0.22), p("清青", 0.2, 0.37, w: 0.1),
                      p("企微测试群 (7人)", 0.3, 0.44, w: 0.3), p("主人蓝海乐", 0.25, 0.51, w: 0.2)]
        XCTAssertTrue(XiaoLanGroups.forwardPage(wechat))
        XCTAssertEqual(XiaoLanGroups.forwardRow(wechat, "测试群").map { Double($0.y) } ?? 0, 0.30, accuracy: 0.001)
        XCTAssertEqual(XiaoLanGroups.forwardRow(wechat, "蓝海乐").map { Double($0.y) } ?? 0, 0.23, accuracy: 0.001, "not 主人蓝海乐")
        XCTAssertNil(XiaoLanGroups.forwardRow(wechat, "测试"), "a name it only resembles is never taken")
        let wecom = [p("企微测试群 (7)", 0.3, 0.33, w: 0.3), p("外部", 0.55, 0.33, w: 0.05),
                     p("青石联盟【流量获客】(150)", 0.4, 0.58, w: 0.5), p("蓝@微信", 0.2, 0.52, w: 0.12)]
        XCTAssertEqual(XiaoLanGroups.forwardRow(wecom, "企微测试群").map { Double($0.y) } ?? 0, 0.33, accuracy: 0.001)
        XCTAssertEqual(XiaoLanGroups.forwardRow(wecom, "蓝").map { Double($0.y) } ?? 0, 0.52, accuracy: 0.001)
        XCTAssertNil(XiaoLanGroups.forwardRow(wecom, "青石联盟"))
        let sheet = [p("发送给：", 0.2, 0.36, w: 0.12), p("企微测试群 (7)", 0.4, 0.41, w: 0.3), p("取消", 0.3, 0.62, w: 0.08), p("发送", 0.7, 0.62, w: 0.08)]
        XCTAssertEqual(XiaoLanGroups.sendSheet(sheet).map { Double($0.x) } ?? 0, 0.7, accuracy: 0.001)
        XCTAssertNil(XiaoLanGroups.sendSheet([p("发送", 0.7, 0.62, w: 0.08)]), "no 发送给, no sheet")
    }

    /// 198 (226 by fixed steps): my own line found on the right, the newest; the recall's grey lines counted (an older one
    /// already there is not this one's); an alert's yes.
    func testRecallSteps() {
        let want = XiaoLanSelf.plain("Echo指令测试：发消息")
        let rows = [p("Echo指令测试：发消息", 0.75, 0.40, w: 0.3), p("你撤回了一条消息", 0.5, 0.48, w: 0.3),
                    p("Echo指令测试：发消息", 0.30, 0.55, w: 0.3), p("Echo指令测试：发消息", 0.75, 0.70, w: 0.3)]
        XCTAssertEqual(XiaoLanGroups.mineLine(rows, want).map { Double($0.y) } ?? 0, 0.70, accuracy: 0.001, "the newest of mine, not theirs")
        XCTAssertNil(XiaoLanGroups.mineLine([p("Echo指令测试：发消息", 0.30, 0.55, w: 0.3)], want), "theirs is not mine")
        XCTAssertEqual(XiaoLanGroups.recalledCount(rows), 1)
        XCTAssertEqual(XiaoLanGroups.recalledCount(rows + [p("你撤回了一条消息 重新编辑", 0.5, 0.75, w: 0.4)]), 2)
        XCTAssertNotNil(XiaoLanGroups.recallConfirm([p("取消", 0.3, 0.6), p("撤回", 0.7, 0.6)]))
        XCTAssertNil(XiaoLanGroups.recallConfirm([p("撤回", 0.7, 0.6)]))
    }

    /// 198 (Echo 197 11-28 05:15–05:52): one question asked once however its quote's note reads; WeCom's 「1条新消息」 chip
    /// is no line; a file's card with its noise glued on is still a file.
    func testAskedOnceChipAndNoisyFileCard() {
        XCTAssertEqual(ChatToolLink.askedLine("这里面是什么\n（引用的文件：区账户交易明细（1）.xIs）"), "这里面是什么")
        XCTAssertEqual(ChatToolLink.askedLine("这里面是什么"), "这里面是什么")
        XCTAssertEqual(ChatToolLink.askedLine("[图片]\n图片内容：导航"), "[图片]\n图片内容：导航", "two pictures are two lines")
        XCTAssertTrue(WatchOCR.newMessagesChip("¥1条新消息"))
        XCTAssertTrue(WatchOCR.newMessagesChip("↓ 3条新消息"))
        XCTAssertFalse(WatchOCR.newMessagesChip("我刚收到1条新消息你看到了吗"))
        XCTAssertEqual(XiaoLanMediaFind.fileName("账户交易明细（1）.xIsO1VD土下キ"), "账户交易明细（1）.xIs")
        XCTAssertEqual(XiaoLanMediaFind.kind(of: "账户交易明细（1）.xIsO1VD土下キ"), .file)
        XCTAssertNil(XiaoLanMediaFind.fileName("see readme.txtfile"), "a lower-case word right after is no extension")
    }

    /// 198 (Echo 197 11-28 05:30): WeChat's quote of a picture reads its writer only; any words after it are no picture.
    func testQuoteOfAPictureReadsItsWriterOnly() {
        XCTAssertEqual(XiaoLanMediaFind.quotedKind("蓝海乐:"), .image)
        XCTAssertEqual(XiaoLanMediaFind.quotedKind("蓝海乐： "), .image)
        XCTAssertNil(XiaoLanMediaFind.quotedKind("蓝海乐: 1"))
        XCTAssertNil(XiaoLanMediaFind.quotedKind("这是什么"))
    }

    /// At most perMinute in any 60 s; the gaps random, never under 3 s.
    func testRateAndRandomGaps() {
        XCTAssertEqual(AutoAccept.gap(5, random: { ($0.lowerBound + $0.upperBound) / 2 }), 12)
        XCTAssertEqual(AutoAccept.gap(5, random: { $0.lowerBound }), 3)
        XCTAssertEqual(AutoAccept.gap(5, random: { $0.upperBound }), 21)
        XCTAssertEqual(AutoAccept.gap(30, random: { $0.lowerBound }), 3)
        let gaps = (0..<50).map { _ in AutoAccept.gap(5) }
        XCTAssertGreaterThan(Set(gaps.map { Int($0 * 10) }).count, 10, "no rhythm")
        XCTAssertTrue(AutoAccept.due([], next: 0, at: 100, perMinute: 5))
        XCTAssertFalse(AutoAccept.due([], next: 105, at: 100, perMinute: 5), "the gap not gone by")
        XCTAssertFalse(AutoAccept.due([50, 60, 70, 80, 90], next: 0, at: 100, perMinute: 5), "five in the last minute")
        XCTAssertTrue(AutoAccept.due([30, 60, 70, 80, 90], next: 0, at: 100, perMinute: 5), "the first went 70 s ago")
    }

    // MARK: 198 cards (B13/B17, docs/shots-2026-11-28-cards d2)

    /// d2: 「A18小黄人」 over 「个人名片」 in one bubble is a contact's card, said by its name; never opened.
    func testContactCardOneLine() {
        XCTAssertEqual(XiaoLanMediaFind.cardLine([("A18小黄人", 0.020), ("个人名片", 0.014)], spanHeight: 0.098, quoted: false), "[名片] A18小黄人")
        XCTAssertNil(XiaoLanMediaFind.kind(of: "[名片] A18小黄人"), "reported as it is, nothing to open")
        XCTAssertNil(XiaoLanMediaFind.cardLine([("请把你的", 0.022), ("名片发我", 0.022)], spanHeight: 0.06, quoted: false))
    }

    /// d2: an article's card — its title, its cover's small print, its words again and its account — one 「[链接] 标题」;
    /// a long message with a lone 「，」 boxed small, a file's card, a quote and a short message are none.
    func testShareCardOneLine() {
        let card: [(text: String, height: Double)] = [("Gemini4的", 0.016), ("GoogleSEO水平", 0.016), ("已经无人能敌", 0.016),
                                                      ("我们刚刚测完两个做B2B的外贸站", 0.007), ("一致在7天左右，核心词从第3页", 0.007),
                                                      ("Gemini4的", 0.016), ("想要变壮的will", 0.012)]
        XCTAssertEqual(XiaoLanMediaFind.cardLine(card, spanHeight: 0.25, quoted: false), "[链接] Gemini4的GoogleSEO水平已经无人能敌")
        XCTAssertNil(XiaoLanMediaFind.cardLine(card, spanHeight: 0.25, quoted: true), "a quote box in the bubble")
        XCTAssertEqual(XiaoLanMediaFind.cardLine(card + [(text: "截图时间 10:08", height: 0.007)], spanHeight: 0.25, quoted: false),
                       "[链接] Gemini4的GoogleSEO水平已经无人能敌", "a clock on its cover is no quote")
        XCTAssertNil(XiaoLanMediaFind.cardLine(Array(card.prefix(2)), spanHeight: 0.05, quoted: false))
        let long: [(text: String, height: Double)] = [("就是所以我知道，其实包括家人什", 0.022), ("么，也许在另外其他的位面还会用", 0.022),
                                                      ("，", 0.008), ("其他的样态存在，", 0.022)]
        XCTAssertNil(XiaoLanMediaFind.cardLine(long, spanHeight: 0.2, quoted: false), "a stray mark is no small print")
        let file: [(text: String, height: Double)] = [("账户交易明细（1）.xIs", 0.020), ("21K", 0.011), ("微信电脑版文件传输", 0.011)]
        XCTAssertNil(XiaoLanMediaFind.cardLine(file, spanHeight: 0.1, quoted: false), "a file's card goes its own way")
        XCTAssertEqual(XiaoLanMediaFind.kind(of: "[链接] Gemini4的GoogleSEO水平已经无人能敌"), .link)
        XCTAssertEqual(XiaoLanMediaFind.cardTitle("[链接] Gemini4的GoogleSEO水平已经无人能敌"), "Gemini4的GoogleSEO水平已经无人能敌")
        XCTAssertNil(XiaoLanMediaFind.cardTitle("[链接] https://v.douyin.com/fv63abc/"), "an address is a link's own way")
        XCTAssertNil(XiaoLanMediaFind.cardTitle("Gemini4的GoogleSEO水平"))
        XCTAssertTrue(XiaoLanMediaFind.sizeLabel("21K"))
        XCTAssertTrue(XiaoLanMediaFind.sizeLabel("1.2 MB"))
        XCTAssertFalse(XiaoLanMediaFind.sizeLabel("A18"))
    }

    /// A card clicked on its first title words, the newest (lowest) first; an old one with the same title above it.
    func testCardSpotByItsTitle() {
        let rows = [p("Gemini4的", 0.25, 0.30), p("我们刚刚测完", 0.25, 0.34, h: 0.007), p("Gemini4的", 0.25, 0.73), p("GoogleSEO水平", 0.27, 0.75)]
        let title = "Gemini4的GoogleSEO水平已经无人能敌"
        XCTAssertEqual(XiaoLanMediaFind.cardSpot(rows, title: title, rank: 0).map { Double($0.y) } ?? 0, 0.73, accuracy: 0.001)
        XCTAssertEqual(XiaoLanMediaFind.cardSpot(rows, title: title, rank: 1).map { Double($0.y) } ?? 0, 0.30, accuracy: 0.001)
        XCTAssertEqual(XiaoLanMediaFind.cardSpot(rows, title: title, rank: 9).map { Double($0.y) } ?? 0, 0.73, accuracy: 0.001,
                       "a rank past the cards found: the newest")
        XCTAssertNil(XiaoLanMediaFind.cardSpot([p("你工号多少", 0.25, 0.5)], title: title, rank: 0))
    }

    /// A window drawn as d2's: the chat's grey, an avatar, a card's white bubble (0.171–0.55 across, 0.38–0.62 down) and
    /// a short message's (0.70–0.76): the card's words one line, the message's left alone.
    func testCardBubbleOnTheWindow() throws {
        let size = CGSize(width: 400, height: 800)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1).setFill()
            ctx.fill(CGRect(x: 12, y: 304, width: 32, height: 32))
            ctx.fill(CGRect(x: 12, y: 560, width: 32, height: 32))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 68.4, y: 304, width: 151.6, height: 192))
            ctx.fill(CGRect(x: 68.4, y: 560, width: 120, height: 48))
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(try XCTUnwrap(image.pngData())))
        XCTAssertEqual(XiaoLanMediaFind.bubbleLeft(px, y: 0.45, from: 0.2) ?? 0, 0.171, accuracy: 0.005)
        XCTAssertNil(XiaoLanMediaFind.bubbleLeft(px, y: 0.66, from: 0.2), "only the chat's grey there")
        let span = try XCTUnwrap(XiaoLanMediaFind.whiteSpan(px, x: 0.182, y: 0.45, top: 0.085, bottom: 0.95))
        XCTAssertEqual(span.lowerBound, 0.38, accuracy: 0.006)
        XCTAssertEqual(span.upperBound, 0.62, accuracy: 0.006)
        func w(_ t: String, _ y: Double, h: Double = 0.016) -> WatchOCR.Piece {
            WatchOCR.Piece(text: t, box: CGRect(x: 0.2, y: y, width: 0.3, height: h), kind: .theirs)
        }
        let pieces = [w("Gemini4的", 0.40), w("GoogleSEO水平", 0.42), w("已经无人能敌", 0.44), w("我们刚刚测完两个做B2B的外贸站", 0.48, h: 0.007),
                      w("一致在7天左右，核心词从第3页", 0.495, h: 0.007), w("想要变壮的will", 0.58, h: 0.012),
                      w("你工号多少", 0.705, h: 0.022), w("我要表扬你", 0.73, h: 0.022)]
        let cards = XiaoLanMediaFind.cardLines(pieces, px, top: 0.085, bottom: 0.95)
        XCTAssertEqual(cards.lines.map(\.text), ["[链接] Gemini4的GoogleSEO水平已经无人能敌"])
        XCTAssertEqual(cards.used.count, 6, "the card's words only, not the message's")
    }
}

private func assertClose(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, "\(a) vs \(b)", file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
