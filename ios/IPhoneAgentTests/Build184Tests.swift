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

    func blue(_ c: CGContext) { c.setFillColor(red: 14 / 255, green: 125 / 255, blue: 234 / 255, alpha: 1) }
    /// 辅助触控's pointer: a coloured ring (6 px) round a grey fill.
    func ring(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, d: CGFloat = 34, tall: CGFloat? = nil, inside: CGFloat = 0.6) {
        let h = tall ?? d
        blue(c)
        c.fillEllipse(in: CGRect(x: x - d / 2, y: y - h / 2, width: d, height: h))
        c.setFillColor(red: inside, green: inside, blue: inside, alpha: 1)
        c.fillEllipse(in: CGRect(x: x - d / 2 + 6, y: y - h / 2 + 6, width: d - 12, height: h - 12))
    }
    func dockPink(_ c: CGContext) {
        c.setFillColor(red: 194 / 255, green: 41 / 255, blue: 106 / 255, alpha: 1)
        c.fill(CGRect(x: 0, y: 1160, width: 960, height: 120))
    }

    /// C15a (user 11-26: 辅助触控 on, the pointer a grey disk in a blue ring ~34 px; 183: "eye: unseen" every time):
    /// found in one frame, its centre; a lens (white inside), a radio button, an oval, a solid dot are not it.
    func testRingPointerInOneFrame() throws {
        let lookalikes: (CGContext) -> Void = { c in
            self.ring(c, 150, 300, inside: 1)                     // a camera's lens: white inside
            self.ring(c, 700, 300, d: 16)                          // a radio button
            self.ring(c, 700, 900, d: 28, tall: 40)                // an oval (a % sign's o, a map pin)
            self.blue(c)
            c.fillEllipse(in: CGRect(x: 133, y: 883, width: 34, height: 34))  // a solid dot
            self.dockPink(c)
        }
        let shot = frame { c in lookalikes(c); self.ring(c, 400, 600) }
        let p = try XCTUnwrap(Vision.ringPointer(shot))
        XCTAssertEqual(Double(p.x) * 960, 400, accuracy: 2.5)
        XCTAssertEqual(Double(p.y) * 1280, 600, accuracy: 2.5)
        XCTAssertEqual(Vision.seenPointer(shot), p)                                // no red arrow: the disk
        XCTAssertNil(Vision.ringPointer(shot, near: CGPoint(x: 0.9, y: 0.1), window: 0.2))
        XCTAssertNil(Vision.ringPointer(frame(lookalikes)))                         // the look-alikes only
        // over the Dock's WeChat icon: green under one half, pink under the other
        let onDock = frame { c in
            self.dockPink(c)
            c.setFillColor(red: 7 / 255, green: 193 / 255, blue: 96 / 255, alpha: 1)
            c.fill(CGRect(x: 302, y: 1181, width: 70, height: 70))
            self.ring(c, 300, 1218, inside: 0.45)
        }
        let d = try XCTUnwrap(Vision.ringPointer(onDock))
        XCTAssertEqual(Double(d.x) * 960, 300, accuracy: 2.5)
        XCTAssertEqual(Double(d.y) * 1280, 1218, accuracy: 2.5)
    }

    /// C15b: the Dock's WeChat (green, hue ~149, not Messages' 130) and WeCom (white with its blue) told by colour;
    /// 辅助触控's button where the owner put it unless set.
    func testDockIconsByColour() throws {
        func icon(_ c: CGContext, _ x: CGFloat, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
            c.setFillColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1)
            c.fill(CGRect(x: x - 35, y: 1181, width: 70, height: 70))
        }
        let shot = frame { c in
            self.dockPink(c)
            icon(c, 70, 52, 199, 89)                                           // Messages
            icon(c, 160, 0, 122, 255)                                          // Safari's blue
            icon(c, 337, 7, 193, 96)                                           // WeChat …
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            c.fillEllipse(in: CGRect(x: 312, y: 1200, width: 30, height: 24))  // … its white bubbles
            c.fillEllipse(in: CGRect(x: 332, y: 1214, width: 26, height: 20))
            icon(c, 425, 255, 255, 255)                                        // WeCom: white …
            c.setStrokeColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
            c.setLineWidth(5)
            c.strokeEllipse(in: CGRect(x: 405, y: 1198, width: 36, height: 30)) // … its blue bubble
        }
        let found = XiaoLanRecall.dockIcons(try XCTUnwrap(WatchOCR.Pixels(shot)))
        let wechat = try XCTUnwrap(found.wechat), wework = try XCTUnwrap(found.wework)
        XCTAssertEqual(Double(wechat.x), 337.0 / 960, accuracy: 0.015)  // its bubbles pull the run right a little
        XCTAssertEqual(Double(wework.x), 425.0 / 960, accuracy: 0.01)
        XCTAssertEqual(Double(wechat.y), 0.95, accuracy: 0.021)
        let none = XiaoLanRecall.dockIcons(try XCTUnwrap(WatchOCR.Pixels(frame { _ in })))
        XCTAssertNil(none.wechat)
        XCTAssertNil(none.wework)
        UserDefaults.standard.removeObject(forKey: XiaoLanRecall.spotKey)
        XCTAssertEqual(Double(XiaoLanRecall.assistiveTouch.x), 0.655, accuracy: 0.001)
        XCTAssertEqual(Double(XiaoLanRecall.assistiveTouch.y), 0.956, accuracy: 0.001)
    }

    /// C12: the writer a list preview names (a group's line read with no name over it); C14: WeCom's private chats'
    /// bar (服务总结, 客户转账) is no one's line.
    func testPreviewSenderAndQuickBar() {
        XCTAssertEqual(XiaoLanPanes.senderOf("主人蓝海乐: 【第三方测试】群消息1"), "主人蓝海乐")
        XCTAssertEqual(XiaoLanPanes.senderOf("[2条]主人蓝海乐：你好"), "主人蓝海乐")
        XCTAssertNil(XiaoLanPanes.senderOf("[语音] 2\""))
        XCTAssertNil(XiaoLanPanes.senderOf("【模拟服务器】收到：嗨"))
        XCTAssertNil(XiaoLanPanes.senderOf("12:30 开会"))
        typealias P = CandidatePicker.Piece
        let rows: [[P]] = [
            [P(text: "测试群", box: CGRect(x: 0.2, y: 0.19, width: 0.2, height: 0.02))],
            [P(text: "主人蓝海乐: 【第三方测试】群消息1", box: CGRect(x: 0.2, y: 0.218, width: 0.6, height: 0.018))],
            [P(text: "腾讯新闻", box: CGRect(x: 0.2, y: 0.29, width: 0.2, height: 0.02))],
            [P(text: "今天的新闻摘要", box: CGRect(x: 0.2, y: 0.318, width: 0.6, height: 0.018))],
        ]
        XCTAssertEqual(XiaoLanPanes.previewSender(rows, of: "测试群"), "主人蓝海乐")
        XCTAssertNil(XiaoLanPanes.previewSender(rows, of: "腾讯新闻"))
        XCTAssertNil(XiaoLanPanes.previewSender(rows, of: "不在列表"))
        XCTAssertEqual(WatchOCR.withoutUIWords("企业名片 ¥发起收款 客户转账"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("服务总结 客户转账 某某"), "")   // two buttons: the bar
        XCTAssertEqual(WatchOCR.withoutUIWords("明天发起收款"), "明天发起收款")   // one: a message
        XCTAssertTrue(XiaoLanSelf.isButton("客户转账"))
        XCTAssertFalse(XiaoLanSelf.isButton("企微测试群"))
        XCTAssertTrue(XiaoLanSelf.noSender("企微测试群", chat: "企微测试群"))    // still no sender read (C12 names it)
    }
}
