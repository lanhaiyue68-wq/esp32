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

private func assertClose(_ a: [Double], _ b: [Double], accuracy: Double, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, "\(a) vs \(b)", file: file, line: line)
    for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: accuracy, file: file, line: line) }
}
