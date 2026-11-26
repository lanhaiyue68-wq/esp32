import XCTest
import UIKit
@testable import IPhoneAgent

/// 183 (Echo 182 overnight on the customer's iPad, 11-26): a window's bottom taken at a wide bubble's edge (the input
/// bar cut off), WeCom's quick bar and the group's own name read as senders, 小藍's menu row read with "一", WeChat's ＋
/// menu left open, news accounts' red marks never opened, a system keyboard's keys taken for the field, a keyboard tap
/// on a time line.
@MainActor final class Build183Tests: XCTestCase {
    typealias P = CandidatePicker.Piece
    func at(_ t: String, _ x: Double, _ y: Double, _ w: Double = 0.1, _ h: Double = 0.02) -> P {
        P(text: t, box: CGRect(x: x, y: y - h / 2, width: w, height: h))
    }
    func picture(_ size: CGSize, _ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.95) { draw($0.cgContext) }
    }
    func fill(_ c: CGContext, _ r: CGRect, _ v: (CGFloat, CGFloat, CGFloat)) {
        c.setFillColor(red: v.0 / 255, green: v.1 / 255, blue: v.2 / 255, alpha: 1)
        c.fill(r)
    }
    /// The customer's iPad: WeChat left to 474, the gap, WeCom from 486, both to 0.9; the wallpaper around them.
    func screen(_ more: (CGContext) -> Void = { _ in }) -> Data {
        picture(CGSize(width: 960, height: 1280)) { c in
            fill(c, CGRect(x: 0, y: 0, width: 960, height: 1280), (141, 31, 60))
            fill(c, CGRect(x: 0, y: 0, width: 474, height: 1152), (237, 237, 237))
            fill(c, CGRect(x: 486, y: 0, width: 474, height: 1152), (236, 237, 241))
            more(c)
        }
    }

    /// 11-26: 测试群 open with its keyboard down ended at 0.829, the bottom of a wide green bubble: the input bar was cut
    /// off ("没找到输入框" for every second line in a row, the 按住 说话 bar never switched back).
    func testWindowBottomIsNoBubbleEdge() throws {
        let voice = screen { c in
            self.fill(c, CGRect(x: 58, y: 900, width: 340, height: 161), (149, 236, 105))  // the bubble, to 0.829
            self.fill(c, CGRect(x: 0, y: 1074, width: 474, height: 2), (226, 226, 226))    // the bar's line
            self.fill(c, CGRect(x: 0, y: 1076, width: 474, height: 76), (255, 255, 255))   // 按住 说话
        }
        let wins = XiaoLanPanes.windows(try XCTUnwrap(WatchOCR.Pixels(voice)))
        XCTAssertEqual(wins.count, 2)
        XCTAssertEqual(Double(wins[0].height), 0.9, accuracy: 0.005)
        XCTAssertEqual(Double(wins[1].height), 0.9, accuracy: 0.005)
        // a keyboard over both windows' bottoms (no wallpaper under any edge): the bottom measured before
        let keyboard = screen { c in self.fill(c, CGRect(x: 0, y: 950, width: 960, height: 330), (210, 212, 218)) }
        let under = XiaoLanPanes.windows(try XCTUnwrap(WatchOCR.Pixels(keyboard)))
        XCTAssertEqual(under.count, 2)
        XCTAssertEqual(Double(under[0].height), 0.9, accuracy: 0.005)
    }

    /// 11-26: 24 lines "企业名片: ¥发起收款 •推荐客服" reported from WeCom's 企微测试群.
    func testQuickBarIsNoMessage() {
        XCTAssertEqual(WatchOCR.withoutUIWords("¥发起收款 •推荐客服"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("发起收款 ●推荐客服"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("企业名片 ¥发起收款 快捷回复 •推荐客服"), "")
        XCTAssertEqual(WatchOCR.withoutUIWords("请发起收款给我"), "请发起收款给我")  // a message that mentions a button
        XCTAssertEqual(WatchOCR.withoutUIWords("你好"), "你好")
    }

    /// 11-26: senders "企业名片", "国企业名片", "企微测试群" (the group's own name): no sender read.
    func testNoSenderRead() {
        XCTAssertTrue(XiaoLanSelf.noSender("企业名片", chat: "企微测试群"))
        XCTAssertTrue(XiaoLanSelf.noSender("国企业名片", chat: "企微测试群"))
        XCTAssertTrue(XiaoLanSelf.noSender("企微测试群", chat: "企微测试群"))
        XCTAssertFalse(XiaoLanSelf.noSender("范兆磊", chat: "企微测试群"))
        XCTAssertFalse(XiaoLanSelf.noSender("", chat: "企微测试群"))
    }

    /// 11-26: the iPad's globe menu, read off the screen: 小藍 — Echo came as "小藍-Echo"; read as "小藍一Echo" it was
    /// not matched and 简体拼音 stayed.
    func testKeyboardMenuRowReadWithAnyDash() throws {
        for name in ["小藍-Echo", "小藍一Echo", "小藍 — Echo", "小蓝一Echo"] {
            let menu: [[P]] = [[at("键盘设置…", 0.073, 0.626, 0.102)], [at("简体拼音", 0.073, 0.671, 0.084)],
                               [at("简体手写", 0.073, 0.717, 0.083)], [at("English（US）", 0.073, 0.765, 0.117)],
                               [at("表情符号", 0.073, 0.810, 0.086)], [at(name, 0.071, 0.849, 0.119)], [at("中文", 0.071, 0.867, 0.031)]]
            let spot = try XCTUnwrap(CandidatePicker.keyboardMenuEntry(rows: menu), name)
            XCTAssertEqual(Double(spot.y), 0.849, accuracy: 0.01, name)
        }
        XCTAssertTrue(CandidatePicker.ourKeyboardName("小藍echo中文"))
        XCTAssertFalse(CandidatePicker.ourKeyboardName("简体拼音"))
        XCTAssertFalse(CandidatePicker.ourKeyboardName("一echo的消息说小蓝今天很忙别打扰"))  // a long chat line
    }

    /// 11-26: a second 取消 clicked unseen hit WeChat's ＋; its menu (with 收付款) stayed open three minutes.
    func testPlusMenuAndTheTopBand() {
        let menu: [[P]] = [[at("微信", 0.45, 0.058)], [at("发起群聊", 0.72, 0.105)], [at("添加朋友", 0.72, 0.16)],
                           [at("扫一扫", 0.72, 0.21)], [at("收付款", 0.72, 0.26)]]
        XCTAssertTrue(XiaoLanPanes.plusMenu(menu))
        XCTAssertFalse(XiaoLanPanes.plusMenu([[at("测试群", 0.2, 0.2)], [at("明天扫一扫这个码", 0.3, 0.4, 0.4)]]))
        XCTAssertLessThan(Double(XiaoLanPanes.menuCloseSpot.y), XiaoLanPanes.topBand)  // a click there only on a seen pointer
        XCTAssertLessThan(Double(XiaoLanPanes.menuCloseSpot.x), 0.4)                  // clear of the ＋ and its menu
        XCTAssertGreaterThan(0.13, XiaoLanPanes.topBand)  // 取消 (< 0.13) is in it
    }

    /// User 11-25: "所有紅點都要消失" — 行业资讯's mark stayed all night (11-26).
    func testNewsAccountsMarkedToo() {
        let bar = [at("消息", 0.05, 0.95), at("邮件", 0.25, 0.95), at("文档", 0.45, 0.95), at("工作台", 0.62, 0.95)]
        let list: [[P]] = [[at("消息", 0.45, 0.058)],
                           [at("行业资讯", 0.184, 0.212, 0.15)], [at("同事们在看《安克被告》", 0.184, 0.236, 0.6)],
                           [at("企微测试群外部", 0.184, 0.358, 0.25)], [at("来自微信的柳掌柜", 0.184, 0.382, 0.6)], bar]
        XCTAssertEqual(XiaoLanPanes.marked(list) { _ in 0.2 }.map(\.name), ["企微测试群"])  // the chats first, as before
        XCTAssertEqual(XiaoLanPanes.systemMarked(list) { _ in 0.2 }.map(\.name), ["行业资讯"])
        XCTAssertTrue(XiaoLanPanes.systemMarked(list) { _ in 0 }.isEmpty)
        XCTAssertNotNil(ReadLog.noticeFolder)
    }

    /// 11-26: 简体拼音 over 测试群: a white key was taken for the input field and a letter typed.
    func testFieldLookedForAboveASystemKeyboard() throws {
        let keys: [[P]] = [["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"].enumerated().map { at($1, 0.03 + 0.095 * Double($0), 0.80, 0.03) },
                           ["a", "s", "d", "f", "g", "h", "j", "k", "l"].enumerated().map { at($1, 0.07 + 0.095 * Double($0), 0.86, 0.03) }]
        let top = try XCTUnwrap(XiaoLanPanes.keyboardTop(keys))
        XCTAssertEqual(top, 0.79, accuracy: 0.01)
        XCTAssertNil(XiaoLanPanes.keyboardTop([[at("【小蓝测试】182个微0074", 0.2, 0.6, 0.5)]]))
        let chat = picture(CGSize(width: 480, height: 1150)) { c in
            self.fill(c, CGRect(x: 0, y: 0, width: 480, height: 1150), (237, 237, 237))
            self.fill(c, CGRect(x: 40, y: 760, width: 300, height: 40), (255, 255, 255))   // the field, 0.66–0.70
            self.fill(c, CGRect(x: 0, y: 830, width: 480, height: 320), (209, 211, 217))   // the keyboard from 0.72
            for row in [900.0, 970.0, 1040.0] {                                            // its white keys
                for k in stride(from: 8.0, to: 470.0, by: 47.0) { self.fill(c, CGRect(x: k, y: row, width: 40, height: 50), (255, 255, 255)) }
            }
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(chat))
        let field = try XCTUnwrap(XiaoLanPanes.inputField(px, above: 0.72))
        XCTAssertEqual(Double(field.y), 0.68, accuracy: 0.015)
        XCTAssertGreaterThan(Double(XiaoLanPanes.inputField(px)?.y ?? 0), 0.75)  // without it: a key (11-26's miss)
    }

    /// 11-26: the owner's other account 蓝海乐 read as "监海乐" and its line reported; 范光磊 stays another person (182).
    func testOwnerNameReadWithAnAlikeLetter() {
        XCTAssertTrue(XiaoLanSelf.isOwner("监海乐", names: ["蓝海乐"]))
        XCTAssertTrue(XiaoLanSelf.isOwner("監海樂", names: ["藍海樂"]))
        XCTAssertTrue(XiaoLanSelf.isOwner("监海乐@微信", names: ["蓝海乐"]))
        XCTAssertFalse(XiaoLanSelf.isOwner("范光磊＠某公司", names: ["范兆磊"]))  // 182, as before
        XCTAssertFalse(XiaoLanSelf.isOwner("监海东", names: ["蓝海乐"]))          // two letters off
        XCTAssertFalse(XiaoLanSelf.isOwner("主人蓝海乐", names: ["蓝海乐"]))      // 182, as before
        XCTAssertFalse(XiaoLanSelf.readAlike("蓝", "监"))                        // one letter is no name
    }

    /// 11-26: after the reinstall the first look at 企微测试群 reported an old line; what was read lived in memory only.
    func testHistoryKeptAcrossLaunches() {
        typealias L = WatchReport.Line
        let saved = UserDefaults.standard.data(forKey: PaneHistory.key)
        defer { UserDefaults.standard.set(saved, forKey: PaneHistory.key) }
        let old = [L(sender: "范兆磊", text: "0081", mine: false), L(sender: "", text: "0082", mine: true),
                   L(sender: "蓝海乐", text: "你好", mine: false)]
        PaneHistory.save(["wework|企微测试群": old])
        XCTAssertEqual(PaneHistory.load()["wework|企微测试群"], old)
        // the screen goes on from the history: only what follows is new
        let screen = old + [L(sender: "客户甲", text: "在吗", mine: false)]
        XCTAssertEqual(PaneHistory.newAfterLaunch(screen, history: old, fromMark: true).map(\.text), ["在吗"])
        // no overlap: nothing new, or the last line of someone's when a red mark opened the chat
        let other = [L(sender: "客户乙", text: "第一句", mine: false), L(sender: "客户乙", text: "第二句", mine: false)]
        XCTAssertTrue(PaneHistory.newAfterLaunch(other, history: old, fromMark: false).isEmpty)
        XCTAssertEqual(PaneHistory.newAfterLaunch(other, history: old, fromMark: true).map(\.text), ["第二句"])
    }

    /// 11-26 (n=95): WeCom in 企微测试群 sent back to its list; its group line is never the title.
    func testWeComGroupLineIsNoTitle() {
        XCTAssertEqual(XiaoLanPanes.titleLine([[at("外部群|群主:范兆磊", 0.35, 0.071, 0.3)]]), "")
        XCTAssertEqual(XiaoLanPanes.titleLine([[at("企微测试群(7)", 0.35, 0.050, 0.3)], [at("外部群|群主:范兆磊", 0.35, 0.071, 0.3)]]),
                       "企微测试群(7)")
        XCTAssertEqual(XiaoLanPanes.view([[at("外部群 | 群主: 范兆磊", 0.35, 0.071, 0.3)]]), .unknown)
    }

    /// 11-26: the keyboard's tap went on a time line ("11月26日 星期四 04:08") and the keyboard stayed up.
    func testKeyboardTapMissesATimeLine() throws {
        let chat = picture(CGSize(width: 480, height: 1150)) { c in
            self.fill(c, CGRect(x: 0, y: 0, width: 480, height: 1150), (237, 237, 237))
            for x in stride(from: 181.0, to: 300.0, by: 9.0) {                       // the time line's grey strokes
                self.fill(c, CGRect(x: x, y: 752, width: 2, height: 14), (175, 175, 175))
            }
            self.fill(c, CGRect(x: 0, y: 805, width: 480, height: 345), (246, 246, 246))   // the input bar from 0.70
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(chat))
        let spot = try XCTUnwrap(XiaoLanPanes.blankSpot(px, above: 0.70))
        XCTAssertTrue(Double(spot.y) + 0.012 < 752.0 / 1150 || Double(spot.y) - 0.012 > 766.0 / 1150, "\(spot.y)")
    }
}
