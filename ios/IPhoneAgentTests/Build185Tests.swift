import XCTest
import UIKit
@testable import IPhoneAgent

/// 185 (Echo 184 on the customer's iPad, 11-26, 辅助触控 on): calibration failed every time ("粗校准落点无有效跨度"):
/// the rough probes were 600 / 1200 units whatever the pointer's speed, and the home's place and the edge gate's span
/// disagreed; 辅助触控's button had been moved, so a fixed spot for it was wrong.
@MainActor final class Build185Tests: XCTestCase {
    func frame(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280), format: format).jpegData(withCompressionQuality: 0.95) { r in
            r.cgContext.setFillColor(red: 242 / 255, green: 241 / 255, blue: 247 / 255, alpha: 1)  // a plain page
            r.cgContext.fill(CGRect(x: 0, y: 0, width: 960, height: 1280))
            draw(r.cgContext)
        }
    }
    func grey(_ c: CGContext, _ v: CGFloat) { c.setFillColor(red: v / 255, green: v / 255, blue: (v + 5) / 255, alpha: 1) }
    /// 辅助触控's button as it looked on Echo's page (11-26): a grey rounded square, a lighter ring, a lighter disk.
    func button(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, disk: Bool = true) {
        grey(c, 163)
        c.addPath(UIBezierPath(roundedRect: CGRect(x: x - 44, y: y - 44, width: 88, height: 88), cornerRadius: 20).cgPath)
        c.fillPath()
        guard disk else { return }
        grey(c, 177)
        c.fillEllipse(in: CGRect(x: x - 26, y: y - 26, width: 52, height: 52))
        grey(c, 199)
        c.fillEllipse(in: CGRect(x: x - 17, y: y - 17, width: 34, height: 34))
    }

    /// 11-26: the probes were where 600 / 1200 units went at 11-25's speed; now shares of the screen measured.
    func testRoughProbesAsSharesOfTheScreen() {
        let pad = AutoCalibrator.roughPoints(pad: true, span: (w: 547, h: 624))
        XCTAssertEqual(pad.map { $0.0 }, [170, 339])
        XCTAssertEqual(pad.map { $0.1 }, [156, 318])
        let old = AutoCalibrator.roughPoints(pad: true, span: (w: 1934, h: 2357))  // 11-25's speed: as before
        XCTAssertEqual(Double(old[0].0), 600, accuracy: 3)
        XCTAssertEqual(Double(old[1].0), 1200, accuracy: 3)
        XCTAssertEqual(AutoCalibrator.roughPoints(pad: false, span: (w: 547, h: 624)).map { $0.0 }, AutoCalibrator.roughStops)
    }

    /// 11-26: the owner moved the button from the bottom's middle to the bottom-right corner: found where it is.
    func testAssistiveTouchButtonFound() throws {
        let px = try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 620, 1234) }))
        let p = try XCTUnwrap(XiaoLanRecall.assistiveTouchButton(px))
        XCTAssertEqual(Double(p.x) * 960, 620, accuracy: 8)
        XCTAssertEqual(Double(p.y) * 1280, 1234, accuracy: 8)
        let corner = try XCTUnwrap(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 912, 1226) }))))
        XCTAssertEqual(Double(corner.x) * 960, 912, accuracy: 8)
        XCTAssertEqual(Double(corner.y) * 1280, 1226, accuracy: 8)
        // not by an edge (iOS keeps the button there), no lighter disk, a white dot: nothing is clicked
        XCTAssertNil(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 480, 640) }))))
        XCTAssertNil(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 620, 1234, disk: false) }))))
        XCTAssertNil(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { c in
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            c.fillEllipse(in: CGRect(x: 600, y: 1210, width: 50, height: 50))
        }))))
    }

    /// B7/B11 (Echo 184, 11-26): the return only when the field holds exactly the text; after it, still holding the
    /// text (a new line at most) means not sent.
    func testFieldHoldsTheTextBeforeTheReturn() {
        let t = "【小蓝测试】184 个微 0000"
        XCTAssertTrue(KeyboardLink.fieldMatches(t, before: t, after: ""))
        XCTAssertTrue(KeyboardLink.fieldMatches(t, before: nil, after: nil))                    // no context given: as before
        XCTAssertFalse(KeyboardLink.fieldMatches(t, before: t + "都没问题呀没有细看", after: nil)) // dictated after it
        XCTAssertFalse(KeyboardLink.fieldMatches(t, before: "看看我" + t, after: nil))            // left before it
        XCTAssertFalse(KeyboardLink.fieldMatches(t, before: t, after: "取消"))
        XCTAssertTrue(KeyboardLink.fieldMatches("一二三四五六七八九十", before: "三四五六七八九十", after: nil))  // the end only
        XCTAssertFalse(KeyboardLink.fieldMatches("一二三四五六七八九十", before: "九十", after: nil))
        XCTAssertTrue(KeyboardLink.stillHolds(t, before: t + "\n"))                             // the return made a new line
        XCTAssertFalse(KeyboardLink.stillHolds(t, before: ""))                                  // emptied: sent
        XCTAssertFalse(KeyboardLink.stillHolds(t, before: nil))
        XCTAssertGreaterThanOrEqual(KeyboardLink.returnDelay, 0.8)
        // a job of an older app has no `dismiss`
        XCTAssertNil(KeyboardLink.job(#"{"id":"a1","text":"t","enter":true}"#)?.dismiss)
        let down = KeyboardLink.Job(id: "b2", text: "", enter: false, dismiss: true)
        XCTAssertEqual(KeyboardLink.job(KeyboardLink.line(down)), down)
    }

    /// B8 (11-26: 「【小蓝测试】」 matched 183's lines): the end of the text tells the line just sent.
    func testSentLineToldByItsEnd() {
        XCTAssertEqual(XiaoLanSelf.sendSignature("【小蓝测试】184 个微 0003 语音模式"), "03语音模式")
        XCTAssertEqual(XiaoLanSelf.sendSignature("好"), "好")
        XCTAssertFalse("【小蓝测试】183个微0038连发2".contains(XiaoLanSelf.sendSignature("【小蓝测试】184 个微 0000")))
    }

    /// B19 (11-26: voice notes 2" and 6" reported as 「小）2"」「小）6"」).
    func testVoiceNoteLengthIsNoText() {
        XCTAssertEqual(WatchOCR.withoutUIWords("小）2\""), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("6\""), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("2个人"), "2个人")
        XCTAssertEqual(WatchOCR.withoutUIWords("你好"), "你好")
    }

    /// B18 (11-26: a line read in 测试群 came again under 企微测试群): the app's other chats count, not the other app's.
    func testSeenInTheAppsOtherChats() {
        let seen: [String: Set<String>] = ["wechat|测试群": ["a"], "wechat|企微测试群": ["b"], "wework|企微测试群": ["c"]]
        XCTAssertEqual(XiaoLanSelf.seenInApp(seen, app: "wechat", chat: "wechat|企微测试群"), ["a", "b"])
        XCTAssertEqual(XiaoLanSelf.seenInApp(seen, app: "wework", chat: "wework|企微测试群"), ["c"])
    }
}
