import XCTest
import UIKit
@testable import IPhoneAgent

/// 184 (Echo 183 on the customer's iPad, 11-26): the pointer taken at WeCom's blinking text cursor, never seen by a
/// window's top (the top 6 % left out), a history that no longer met the screen after the keyboard went down, the
/// corners kept clear outside calibration, the top band taking in the search box.
@MainActor final class Build184Tests: XCTestCase {
    typealias L = WatchReport.Line

    func frame(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280), format: format).jpegData(withCompressionQuality: 0.95) { r in
            r.cgContext.setFillColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1)
            r.cgContext.fill(CGRect(x: 0, y: 0, width: 960, height: 1280))
            draw(r.cgContext)
        }
    }
    func dark(_ c: CGContext, _ x: CGFloat, _ y: CGFloat) {
        c.setFillColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        c.fill(CGRect(x: x, y: y, width: 10, height: 16))  // ~160 changed pixels, the arrow's size at 960
    }

    /// 11-26: the iPad home found "the arrow" at a blinking text cursor, again and again; only a pair a nudge apart is
    /// the pointer.
    func testOnlyANudgedPairIsThePointer() throws {
        let span = 1934.0, step = 60.0 / span  // a 60-unit nudge, ~0.031 of the screen
        let was = CGPoint(x: 0.30, y: 0.50), now = CGPoint(x: 0.30 + step, y: 0.50)
        XCTAssertEqual(Pointer.pickNudged([was, now], nudge: 60, span: span), was)
        XCTAssertEqual(Pointer.pickNudged([now, was], nudge: -60, span: span), now)          // the nudge the other way
        XCTAssertNil(Pointer.pickNudged([CGPoint(x: 0.569, y: 0.666)], nudge: 60, span: span))  // a cursor blinking alone
        let caret = CGPoint(x: 0.569, y: 0.666)
        XCTAssertEqual(Pointer.pickNudged([caret, was, now], nudge: 60, span: span), was)    // the cursor beside the pair
        XCTAssertNil(Pointer.pickNudged([was, CGPoint(x: 0.30 + 6 * step, y: 0.50)], nudge: 60, span: span))  // too far
        XCTAssertNil(Pointer.pickNudged([was, CGPoint(x: 0.30 + step, y: 0.55)], nudge: 60, span: span))      // not on its row
    }

    /// 11-26: by a window's top (back arrow, 取消, ＋ at ~0.05) the pointer was never seen: the top 6 % was left out.
    func testPointerSeenInAWindowsTitleBar() {
        let before = frame { dark($0, 300, 50) }, after = frame { dark($0, 330, 50) }
        XCTAssertTrue(Vision.arrows(before, after, near: CGPoint(x: 0.33, y: 0.05), window: 0.25).isEmpty)  // as before
        let tips = Vision.arrows(before, after, near: CGPoint(x: 0.33, y: 0.05), window: 0.25, top: Pointer.padTopMask)
        XCTAssertEqual(tips.count, 2)
        let was = Pointer.pickNudged(tips, nudge: 60, span: 1934)
        XCTAssertEqual(Double(was?.x ?? 0) * 960, 300, accuracy: 3)
        XCTAssertEqual(Double(was?.y ?? 0) * 1280, 50, accuracy: 3)
    }

    /// 11-26: after a send the keyboard went down and older lines came in above; "no overlap" on every pass.
    func testHistoryFoundAnywhereOnTheScreen() {
        let history = [L(sender: "", text: "【小蓝测试】183 0004", mine: true), L(sender: "范兆磊", text: "【小蓝测试】183 企微 0005", mine: false)]
        let screen = [L(sender: "范兆磊", text: "【小蓝测试】182 企微 0125", mine: false), L(sender: "", text: "【小蓝测试】183 0004", mine: true),
                      L(sender: "范兆磊", text: "【小蓝测试】183企微0005", mine: false), L(sender: "客户甲", text: "在吗", mine: false)]
        XCTAssertEqual(XiaoLanSelf.afterAnchor(screen, history: history)?.map(\.text), ["在吗"])
        XCTAssertEqual(XiaoLanSelf.afterAnchor(Array(screen.prefix(3)), history: history)?.count, 0)  // nothing after it
        // the last line elsewhere, after another line than the history's: not it
        let other = [L(sender: "客户乙", text: "早", mine: false), L(sender: "范兆磊", text: "【小蓝测试】183 企微 0005", mine: false)]
        XCTAssertNil(XiaoLanSelf.afterAnchor(other, history: history))
        XCTAssertNil(XiaoLanSelf.afterAnchor(screen, history: [L(sender: "客户甲", text: "好", mine: false)]))  // too short
    }

    /// User 11-26: the corners only while calibrating; the clock's bar always.
    func testCornersKeptClearOnlyWhileCalibrating() {
        let span = (w: 2000, h: 2400)
        XCTAssertEqual(CommandChannel.padKeptClear("move -1100 0", from: (1000, 1000), span: span), "move -960 0")  // calibrating
        XCTAssertNil(CommandChannel.padKeptClear("move -1000 0", from: (1000, 1000), span: span, calibrating: false))  // to the side
        XCTAssertEqual(CommandChannel.padKeptClear("move 0 -1000", from: (1000, 1000), span: span, calibrating: false),
                       "move 0 -928")  // never into the status bar (3 %)
        XCTAssertFalse(CommandChannel.padCalibrating)
    }

    /// User 11-26: the pointer made big and red (指针控制 › 颜色): found in one frame by its hollow red outline; red
    /// badges, a red word and the Dock's pink are not it.
    func testRedPointerInOneFrame() throws {
        func red(_ c: CGContext) { c.setFillColor(red: 236 / 255, green: 67 / 255, blue: 60 / 255, alpha: 1) }
        let shot = frame { c in
            red(c)
            c.fill(CGRect(x: 32, y: 78, width: 40, height: 52))                       // the outline …
            c.setFillColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            c.fill(CGRect(x: 38, y: 84, width: 28, height: 40))                       // … round its grey fill
            red(c)
            c.fill(CGRect(x: 520, y: 380, width: 22, height: 22))                     // a red mark (badge)
            c.fill(CGRect(x: 34, y: 640, width: 40, height: 14))                      // a red word
            c.setFillColor(red: 219 / 255, green: 165 / 255, blue: 179 / 255, alpha: 1)
            c.fill(CGRect(x: 0, y: 1172, width: 960, height: 108))                    // the Dock
        }
        let tip = try XCTUnwrap(Vision.redPointer(shot))
        XCTAssertEqual(Double(tip.x) * 960, 34, accuracy: 3)
        XCTAssertEqual(Double(tip.y) * 1280, 80, accuracy: 3)
        XCTAssertNil(Vision.redPointer(shot, near: CGPoint(x: 0.9, y: 0.9), window: 0.2))  // not near there
        XCTAssertNil(Vision.redPointer(frame { red($0); $0.fill(CGRect(x: 520, y: 380, width: 22, height: 22)) }))  // a badge only
        // a solid red block the pointer's size (WeChat's 删除) is no pointer: not hollow
        XCTAssertNil(Vision.redPointer(frame { red($0); $0.fill(CGRect(x: 600, y: 600, width: 44, height: 52)) }))
    }

    /// 11-26: the top band to 0.12 took in the search box (0.10): no search ever ran.
    func testTopBandIsTheTitleBarOnly() {
        XCTAssertEqual(XiaoLanPanes.topBand, 0.08)
        XCTAssertGreaterThan(0.105, XiaoLanPanes.topBand)                         // the lists' search box
        XCTAssertLessThan(Double(XiaoLanPanes.back.y), XiaoLanPanes.topBand)      // the back arrow
        XCTAssertLessThan(Double(XiaoLanPanes.menuCloseSpot.y), XiaoLanPanes.topBand)
    }
}
