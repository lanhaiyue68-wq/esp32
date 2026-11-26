import XCTest
import UIKit
@testable import IPhoneAgent

/// 187 (Echo 186 on the customer's iPad, 11-26): a white bubble taken for the input field (B23), a delete's
/// confirmation skipped for a name the slid row cut short (B36), a preview's beginning taken for the line sent (B32).
@MainActor final class Build187Tests: XCTestCase {
    func window(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 1150), format: format).jpegData(withCompressionQuality: 0.95) { r in
            r.cgContext.setFillColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1)  // WeChat's chat
            r.cgContext.fill(CGRect(x: 0, y: 0, width: 480, height: 1150))
            draw(r.cgContext)
        }
    }
    func fill(_ c: CGContext, _ rect: CGRect, _ v: CGFloat) {
        c.setFillColor(red: v / 255, green: v / 255, blue: v / 255, alpha: 1)
        c.fill(rect)
    }
    func piece(_ text: String, y: CGFloat) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: text, box: CGRect(x: 0.2, y: y, width: 0.3, height: 0.02))
    }

    /// B23: a white bubble on the chat's grey (237) is no field; the field sits in the bar (246, measured 11-26).
    func testBubbleIsNoField() throws {
        let bubble = window { c in self.fill(c, CGRect(x: 80, y: 500, width: 260, height: 60), 255) }
        XCTAssertNil(XiaoLanPanes.inputField(try XCTUnwrap(WatchOCR.Pixels(bubble))))
        let chat = window { c in
            self.fill(c, CGRect(x: 80, y: 500, width: 260, height: 60), 255)
            self.fill(c, CGRect(x: 0, y: 1066, width: 480, height: 84), 246)
            self.fill(c, CGRect(x: 58, y: 1085, width: 277, height: 55), 255)
        }
        let field = try XCTUnwrap(XiaoLanPanes.inputField(try XCTUnwrap(WatchOCR.Pixels(chat))))
        XCTAssertEqual(Double(field.y), 1112.5 / 1150, accuracy: 0.01)
    }

    /// B36: the slid row's name cut short still counts; the confirmation is there to click.
    func testCutNameIsNotGone() {
        let slid = [[piece("文件传输助", y: 0.50)], [CandidatePicker.Piece(text: "删除并清空记录", box: CGRect(x: 0.4, y: 0.50, width: 0.4, height: 0.03))]]
        XCTAssertFalse(XiaoLanPanes.gone("文件传输助手", slid))
        XCTAssertNotNil(XiaoLanPanes.confirmDelete(slid))
        XCTAssertTrue(XiaoLanPanes.gone("文件传输助手", [[piece("测试群", y: 0.3)], [piece("文件", y: 0.5)]]))
    }

    /// User 11-26 ("都一次性點好"): an iPad curve aims against its bow (it lands ~0.22 of it toward the bow) and a
    /// little further (the bow's extra length comes short), so it lands where the move asked; still a visible bow.
    func testPadCurveAimsAgainstItsBow() throws {
        let span = (w: 5854, h: 7626)
        let mid: (ClosedRange<Double>) -> Double = { ($0.lowerBound + $0.upperBound) / 2 }  // side +1, bow 9 %
        let by = (-492, 2135), from = (1200, 2000)
        let s = try XCTUnwrap(PadCurve.stroke(from: from, by: by, span: span, random: mid))
        let v = s.split(separator: " ").dropFirst().compactMap { Int($0) }
        var end = (0, 0), bow = 0.0
        let len = hypot(Double(by.0), Double(by.1)), n = (x: -Double(by.1) / len, y: Double(by.0) / len)  // side +1
        for i in stride(from: 0, to: v.count - 1, by: 2) {
            end = (end.0 + v[i], end.1 + v[i + 1])
            bow = max(bow, Double(end.0) * n.x + Double(end.1) * n.y)
        }
        let across = Double(end.0 - by.0) * n.x + Double(end.1 - by.1) * n.y
        let along = (Double(end.0 - by.0) * Double(by.0) + Double(end.1 - by.1) * Double(by.1)) / len
        XCTAssertGreaterThan(bow, len * 0.05, "a bow that shows")
        XCTAssertEqual(across, -0.22 * 0.09 * len, accuracy: 3, "back against the bow by 0.22 of it")
        XCTAssertGreaterThan(along, 0, "a little further")
        XCTAssertLessThan(along, 0.03 * len)
    }

    /// User 11-26: an iPad hop's gain per axis is learned from long hops seen where they arrived; a short hop or a
    /// sighting far off what the gain expects teaches nothing.
    func testPadGainLearnsFromLongHopsOnly() {
        // 3003 units sent for 0.513 of a 5854 span, seen to go 0.459: the units go ~1.12x as far as the span says
        let g = Pointer.learnedPadGain(1, units: 3003, span: 5854, moved: 0.459)
        XCTAssertEqual(g, 0.6 + 0.4 * 3003 / (5854 * 0.459), accuracy: 0.0001)
        XCTAssertEqual(Pointer.learnedPadGain(1, units: 300, span: 5854, moved: 0.05), 1)   // short
        XCTAssertEqual(Pointer.learnedPadGain(1, units: 3003, span: 5854, moved: 0.2), 1)   // 2.6x: not the pointer
        XCTAssertEqual(Pointer.learnedPadGain(1, units: 3003, span: 5854, moved: -0.5), 1)  // the wrong way
        XCTAssertEqual(Pointer.learnedPadGain(1.14, units: 3003, span: 5854, moved: 0.40), 1.15, accuracy: 0.0001)  // kept ≤ 1.15
    }

    /// 11-27: a red mark opened with nothing of anyone's new read: the line the list's preview shows is taken (from the
    /// screen when it is there, else the preview's words); a voice's preview adds nothing; a line read new is enough.
    func testRedMarkTakesThePreviewsLine() {
        typealias L = WatchReport.Line
        let screen = [L(sender: "我", text: "【小蓝测试】186 断线 0020", mine: true),
                      L(sender: "主人蓝海乐", text: "【第三方测试】187 断线1", mine: false)]
        let preview = "主人蓝海乐: 【第三方测试】187断线1"
        XCTAssertEqual(WatchReport.markedLine(screen, fresh: [], preview: preview, sender: "主人蓝海乐"), screen[1])
        XCTAssertEqual(WatchReport.markedLine([screen[0]], fresh: [], preview: preview, sender: "主人蓝海乐"),
                       L(sender: "主人蓝海乐", text: "【第三方测试】187断线1", mine: false))
        XCTAssertNil(WatchReport.markedLine(screen, fresh: [screen[1]], preview: preview, sender: "主人蓝海乐"))
        XCTAssertNil(WatchReport.markedLine(screen, fresh: [], preview: "主人蓝海乐: [语音] 6\"", sender: "主人蓝海乐"))
        XCTAssertNil(WatchReport.markedLine(screen, fresh: [], preview: nil, sender: nil))
        // a private chat's preview has no sender: a colon in its words stays
        XCTAssertEqual(WatchReport.markedLine([], fresh: [], preview: "明天:3点见", sender: nil)?.text, "明天:3点见")
    }

    /// 11-27: a search that found nothing has no result in 小藍's own bar under it ("小藍 已填入：…"); a real row is found.
    func testSearchResultIsNotTheKeyboardsBar() {
        let bar = CandidatePicker.Piece(text: "小藍 已填入：不存在的群187", box: CGRect(x: 0.3, y: 0.86, width: 0.4, height: 0.02))
        let empty = [[piece("不存在的群187", y: 0.03)], [piece("没有找到相关结果", y: 0.35)], [bar]]
        XCTAssertNil(XiaoLanPanes.searchResult("不存在的群187", empty))
        let found = [[piece("测试群", y: 0.03)], [piece("测试群", y: 0.30)], [bar]]
        XCTAssertEqual(Double(XiaoLanPanes.searchResult("测试群", found)?.y ?? 0), 0.31, accuracy: 0.001)
    }

    /// B32: a preview's beginning counts only when it is cut short with "…".
    func testPreviewBeginningOnlyWhenCut() {
        XCTAssertFalse(XiaoLanSelf.previewShowsSent("【小蓝测试】186个微0018", "【小蓝测试】186 个微 0018 连发2"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("【小蓝测试】186个微0018连发2", "【小蓝测试】186 个微 0018 连发2"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("【小蓝测试】186 个微 0004 长消息：这一条故…",
                                                   "【小蓝测试】186 个微 0004 长消息：这一条故意写得比较长"))
    }
}
