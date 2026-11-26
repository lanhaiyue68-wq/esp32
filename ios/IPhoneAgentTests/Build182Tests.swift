import XCTest
import UIKit
@testable import IPhoneAgent

/// 182 (Echo 181 on the customer's iPad, 11-26, after a restart): the WeCom logo read as any character after the head
/// count, the owner's wide green bubble read as someone else's, an in-app banner read as the open chat's line, the apps'
/// own words read as messages, 小藍's keyboard in the globe menu, the owner's WeCom account with its "＠company", a chat
/// left on its voice bar, a WeCom chat told by its quick bar, a bare spot to put the keyboard down.
@MainActor final class Build182Tests: XCTestCase {
    typealias P = CandidatePicker.Piece
    func at(_ t: String, _ x: Double, _ y: Double, _ w: Double = 0.1, _ h: Double = 0.02) -> P {
        P(text: t, box: CGRect(x: x, y: y - h / 2, width: w, height: h))
    }

    func picture(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 1150), format: format).jpegData(withCompressionQuality: 0.95) { draw($0.cgContext) }
    }
    func fill(_ c: CGContext, _ r: CGRect, _ v: (CGFloat, CGFloat, CGFloat)) {
        c.setFillColor(red: v.0 / 255, green: v.1 / 255, blue: v.2 / 255, alpha: 1)
        c.fill(r)
    }
    /// A chat window: WeChat's grey background, nothing else.
    func chat(_ more: (CGContext) -> Void = { _ in }) -> Data {
        picture { c in
            fill(c, CGRect(x: 0, y: 0, width: 480, height: 1150), (237, 237, 237))
            more(c)
        }
    }

    /// 11-26: "企微测试群（7）9": the logo after the head count read as 9; the reply order failed ("没有打开") and the
    /// chat's old lines were reported as new under that name.
    func testLogoAfterHeadCountReadAsAnything() {
        for read in ["企微测试群（7）9", "企微测试群（7）0", "企微测试群（7）O", "企微测试群（7）Q", "企微测试群（7）©"] {
            let t = WatchOCR.titled(read)
            XCTAssertEqual(t.name, "企微测试群", read)
            XCTAssertTrue(t.group, read)
        }
        XCTAssertEqual(WatchOCR.titled("测试群(6)").name, "测试群")
        XCTAssertEqual(WatchOCR.withoutIconTail("测试群9"), "测试群9")  // no head count before it: part of a name
        XCTAssertEqual(WatchOCR.withoutIconTail("企微测试群Q"), "企微测试群")  // 180, as before
    }

    /// 11-26: the owner's wide green bubble "【小蓝测试】181 个微发消息 / 0001": its edge reached into the left avatar
    /// strip, the second line was taken for someone else's and reported five times.
    func testWideGreenBubbleStaysMine() throws {
        let jpeg = chat { c in
            fill(c, CGRect(x: 58, y: 460, width: 345, height: 115), (149, 236, 105))  // the bubble, 0.12–0.84 across
            fill(c, CGRect(x: 418, y: 460, width: 24, height: 52), (200, 60, 60))     // my avatar, level with line one
            fill(c, CGRect(x: 442, y: 460, width: 24, height: 52), (40, 40, 160))
        }
        let rows = [[at("【小蓝测试】181个微发消息", 0.15, 0.42, 0.6, 0.03)], [at("0001", 0.15, 0.47, 0.1, 0.03)]]
        let read = try XCTUnwrap(WatchOCR.screen(jpeg, title: "测试群(6)", rows: rows))
        XCTAssertEqual(read.lines.count, 1)
        XCTAssertTrue(read.lines.allSatisfy(\.mine))
        XCTAssertTrue(read.lines[0].text.contains("0001"))
    }

    /// 11-26: WeCom's line to 企微测试群 came in as a banner over WeChat's 测试群 and was reported as 测试群's.
    func testBannerSkipsTheRead() throws {
        let banner = [at("企微测试群", 0.15, 0.05, 0.3), at("范兆磊:【小蓝测试】全功能企微0109", 0.15, 0.09, 0.7)]
        XCTAssertTrue(WatchOCR.bannerShown(banner))
        XCTAssertFalse(WatchOCR.bannerShown([at("测试群(6)", 0.38, 0.058, 0.24)]))   // the chat's own centred title
        XCTAssertFalse(WatchOCR.bannerShown([at("时间：明天下午", 0.15, 0.4, 0.4)]))  // a message lower down
        // 188 (B45, Echo 187, 11-27): the iPad's status bar over WeChat's window, and a chat's own time label, are no banner
        XCTAssertFalse(WatchOCR.bannerShown([at("◀企业微信 01:00 11月27日周五 微信", 0.06, 0.021, 0.8)]))
        XCTAssertFalse(WatchOCR.bannerShown([at("企业微信01:0011月27日周五微信", 0.19, 0.035, 0.6)]))
        XCTAssertFalse(WatchOCR.bannerShown([at("昨天 23:56", 0.2, 0.08, 0.2)]))
        XCTAssertTrue(WatchOCR.bannerShown([at("企微测试群", 0.15, 0.05, 0.3), at("主人蓝海乐: 2", 0.15, 0.075, 0.3)]))
        XCTAssertTrue(WatchOCR.bannerShown([at("测试群", 0.15, 0.05, 0.3), at("主人蓝海乐: 11月27日 12:30开会", 0.15, 0.075, 0.5)]))  // a banner's own date
        // 188 (B45 again, 17:35): 小藍's own line with a colon at the top of WeCom's narrow window, nothing over it, is no banner
        XCTAssertFalse(WatchOCR.bannerShown([at("外部群 | 群主：范兆磊", 0.37, 0.065, 0.27), at("【模拟服务器】收到：［图片］", 0.26, 0.10, 0.6)]))
        let jpeg = chat()
        // 188 (B45): under a banner the window is read with the banner's band left out (187: not read at all, lines lost)
        let under = try XCTUnwrap(WatchOCR.screen(jpeg, title: "测试群(6)", rows: banner.map { [$0] }))
        XCTAssertFalse(under.lines.contains { $0.text.contains("0109") })
        XCTAssertNotNil(WatchOCR.screen(jpeg, title: "测试群(6)", rows: banner.map { [$0] }, banner: false))
    }

    /// 11-26: "按住说话" (文件传输助手's voice bar while recording) and "哦。•转换完成" (WeCom's transcript and its
    /// label) were reported as messages.
    func testAppWordsAreNoMessages() {
        XCTAssertEqual(WatchOCR.withoutUIWords("按住 说话"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("松开 发送"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("哦。•转换完成"), "哦。")
        XCTAssertEqual(WatchOCR.withoutUIWords("测试回复 你好"), "测试回复 你好")
        XCTAssertEqual(WatchOCR.withoutUIWords("取消"), "取消")  // a one-word reply stays
        let pieces = [WatchOCR.Piece(text: "按住说话", box: CGRect(x: 0.3, y: 0.5, width: 0.3, height: 0.03), kind: .theirs)]
        XCTAssertTrue(WatchOCR.lines(pieces, title: "文件传输助手").lines.isEmpty)
    }

    /// 11-26: after the restart the globe menu showed 小藍 — Echo, and Echo looked for "Lan Agent" only.
    func testKeyboardMenuListsXiaoLan() throws {
        let menu: [[P]] = [[at("键盘设置…", 0.084, 0.415, 0.23)], [at("简体拼音", 0.084, 0.475)], [at("简体手写", 0.084, 0.537)],
                           [at("English (US)", 0.084, 0.598, 0.23)], [at("表情符号", 0.084, 0.66)],
                           [at("小藍", 0.084, 0.772, 0.06), at("—", 0.15, 0.772, 0.02), at("Echo", 0.18, 0.772, 0.1)],
                           [at("中文", 0.084, 0.8, 0.06)]]
        let spot = try XCTUnwrap(CandidatePicker.keyboardMenuEntry(rows: menu))
        XCTAssertEqual(Double(spot.y), 0.772, accuracy: 0.01)
        XCTAssertTrue(CandidatePicker.ourKeyboardShown(rows: [[at("小藍 輸入法：等待要打的字…", 0.3, 0.86, 0.4)], [at("空格", 0.4, 0.95)]]))
        XCTAssertTrue(CandidatePicker.ourKeyboardShown(rows: [[at("小蓝 已填入：", 0.3, 0.86, 0.3)], [at("空格", 0.4, 0.95)]]))
    }

    /// 11-26: "范兆磊＠某公司" (the owner's WeCom account seen from WeChat) reported after the restart.
    func testOwnerWithCompany() {
        XCTAssertTrue(XiaoLanSelf.isOwner("范兆磊＠某公司", names: ["范兆磊"]))
        XCTAssertTrue(XiaoLanSelf.isOwner("范兆磊", names: ["范兆磊＠某公司"]))
        XCTAssertTrue(XiaoLanSelf.isOwner("蓝海乐@微信", names: ["蓝海乐"]))  // 181, as before
        XCTAssertFalse(XiaoLanSelf.isOwner("范光磊＠某公司", names: ["范兆磊"]))
        XCTAssertFalse(XiaoLanSelf.isOwner("主人蓝海乐", names: ["蓝海乐"]))
        XCTAssertEqual(XiaoLanSelf.person("范兆磊＠某公司"), "范兆磊")
    }

    /// 11-26: 企微测试群 left on 按住 说话; the white button was taken for the field ("小蓝输入法没有打出字").
    func testVoiceBarSwitchedBack() throws {
        let toggle = try XCTUnwrap(XiaoLanPanes.voiceToggle([[at("按住 说话", 0.3, 0.93, 0.3)]]))
        XCTAssertEqual(Double(toggle.x), 0.055, accuracy: 0.001)
        XCTAssertEqual(Double(toggle.y), 0.93, accuracy: 0.001)
        XCTAssertNil(XiaoLanPanes.voiceToggle([[at("发消息或按住说话", 0.2, 0.93, 0.5)]]))  // WeCom's typing field
        XCTAssertNil(XiaoLanPanes.voiceToggle([[at("按住说话", 0.3, 0.3)]]))           // a line up in the chat
    }

    /// 11-26: WeCom in 企微测试群 (a title WeChat has too) was nobody's window and left alone for minutes.
    func testWeComChatToldByItsQuickBar() {
        let rows = [[at("企微测试群（7）", 0.35, 0.05, 0.3)], [at("企业名片", 0.05, 0.88), at("发起收款", 0.25, 0.88)]]
        XCTAssertTrue(XiaoLanPanes.weworkBar(rows))
        XCTAssertEqual(XiaoLanPanes.chatApp(rows), .wework)
        XCTAssertFalse(XiaoLanPanes.weworkBar([[at("测试群(6)", 0.35, 0.05)], [at("你好", 0.2, 0.5)]]))
        XCTAssertEqual(XiaoLanPanes.chatApp([[at("你好", 0.2, 0.5)]]), .wechat)
    }

    /// User 11-26: "點聊天空白處收鍵盤": the spot is bare background above the input bar, never on a bubble.
    func testBareSpotForTheKeyboard() throws {
        let jpeg = chat { c in
            fill(c, CGRect(x: 72, y: 632, width: 216, height: 81), (254, 254, 254))    // a bubble, 0.55–0.62 down
            fill(c, CGRect(x: 0, y: 805, width: 480, height: 345), (246, 246, 246))    // the input bar from 0.70
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(jpeg))
        let bar = try XCTUnwrap(px.inputTop(from: 0.3))
        XCTAssertEqual(bar, 0.70, accuracy: 0.01)
        let spot = try XCTUnwrap(XiaoLanPanes.blankSpot(px, above: bar))
        XCTAssertEqual(Double(spot.x), 0.5)
        XCTAssertGreaterThan(Double(spot.y), 0.63)
        XCTAssertLessThan(Double(spot.y), 0.69)
        // all bubbles, no background: nothing is tapped
        let full = picture { c in fill(c, CGRect(x: 0, y: 0, width: 480, height: 1150), (254, 254, 254)) }
        XCTAssertNil(XiaoLanPanes.blankSpot(try XCTUnwrap(WatchOCR.Pixels(full)), above: 0.7))
    }
}
