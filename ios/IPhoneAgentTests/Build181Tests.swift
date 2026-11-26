import XCTest
import UIKit
@testable import IPhoneAgent

/// 181 (Echo 180 on the customer's iPad, 11-25): windows of any width, a list told by its title, the WeCom logo read as
/// "0" after the head count, a preview line is no chat, the owner's other account is never answered, 514's day range.
@MainActor final class Build181Tests: XCTestCase {
    typealias P = CandidatePicker.Piece
    func at(_ t: String, _ x: Double, _ y: Double, _ w: Double = 0.1) -> P { P(text: t, box: CGRect(x: x, y: y - 0.01, width: w, height: 0.02)) }

    func picture(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280), format: format).jpegData(withCompressionQuality: 0.95) { draw($0.cgContext) }
    }
    func fill(_ c: CGContext, _ r: CGRect, _ v: (CGFloat, CGFloat, CGFloat)) {
        c.setFillColor(red: v.0 / 255, green: v.1 / 255, blue: v.2 / 255, alpha: 1)
        c.fill(r)
    }

    /// User 11-25: "寬度他可能會自由調整…有時候左邊寬一些，有時候右邊寬一些": a wide gap anywhere, windows moved in from
    /// the screen's sides; each window is only itself (its taps are its own fractions).
    func testWindowsOfAnyWidthMovedIn() throws {
        let screen = picture { c in
            fill(c, CGRect(x: 0, y: 0, width: 960, height: 1280), (180, 60, 120))
            fill(c, CGRect(x: 40, y: 0, width: 260, height: 1152), (237, 237, 237))
            fill(c, CGRect(x: 360, y: 0, width: 570, height: 1152), (236, 237, 241))
        }
        let wins = XiaoLanPanes.windows(try XCTUnwrap(WatchOCR.Pixels(screen)))
        XCTAssertEqual(wins.count, 2)
        XCTAssertEqual(Double(wins[0].minX), 40 / 960, accuracy: 0.004)
        XCTAssertEqual(Double(wins[0].maxX), 300 / 960, accuracy: 0.004)
        XCTAssertEqual(Double(wins[1].minX), 360 / 960, accuracy: 0.004)
        XCTAssertEqual(Double(wins[1].maxX), 930 / 960, accuracy: 0.004)
        XCTAssertEqual(Double(wins[0].height), 0.9, accuracy: 0.005)
        // the back arrow of the left window is its own, not the wallpaper's
        let back = XiaoLanPanes.onScreen(XiaoLanPanes.back, in: wins[0])
        XCTAssertEqual(Double(back.x), (40 + 0.055 * 260) / 960, accuracy: 0.004)
        // the right window wider than the left, flush with the screen's sides: as before
        let wide = picture { c in
            fill(c, CGRect(x: 0, y: 0, width: 960, height: 1280), (180, 60, 120))
            fill(c, CGRect(x: 0, y: 0, width: 330, height: 1152), (237, 237, 237))
            fill(c, CGRect(x: 342, y: 0, width: 618, height: 1152), (236, 237, 241))
        }
        let two = XiaoLanPanes.windows(try XCTUnwrap(WatchOCR.Pixels(wide)))
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(Double(two[0].minX), 0, accuracy: 0.001)
        XCTAssertEqual(Double(two[1].maxX), 1, accuracy: 0.001)
    }

    /// 180's WeChat window went untold when its tab bar was not read: its list title tells it.
    func testListTitleTellsTheApp() {
        XCTAssertEqual(XiaoLanPanes.app([[at("微信 (1)", 0.42, 0.054, 0.16)], [at("企微测试群", 0.2, 0.18)]]), .wechat)
        XCTAssertEqual(XiaoLanPanes.app([[at("消息", 0.45, 0.058)]]), .wework)
        XCTAssertNil(XiaoLanPanes.app([[at("企微测试群（7）", 0.35, 0.05, 0.3)]]))
        XCTAssertEqual(XiaoLanPanes.view([[at("微信 (1)", 0.42, 0.054, 0.16)]]), .list)
        XCTAssertEqual(XiaoLanPanes.bottomText([[at("微信", 0.08, 0.95), at("我", 0.82, 0.95)], [at("测试群", 0.2, 0.3)]]), "微信 我")
    }

    /// User 11-25: "它兩邊不論怎么多寬…都可以看到": a list with no word read is told by its chosen tab's colour.
    func testTabColourTellsTheApp() throws {
        func window(_ tab: (CGFloat, CGFloat, CGFloat)?) -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 420, height: 1000), format: format).jpegData(withCompressionQuality: 0.95) { ctx in
                fill(ctx.cgContext, CGRect(x: 0, y: 0, width: 420, height: 1000), (247, 247, 247))
                if let tab { fill(ctx.cgContext, CGRect(x: 25, y: 930, width: 40, height: 50), tab) }
            }
        }
        XCTAssertEqual(XiaoLanPanes.tabApp(try XCTUnwrap(WatchOCR.Pixels(window((7, 193, 96))))), .wechat)
        XCTAssertEqual(XiaoLanPanes.tabApp(try XCTUnwrap(WatchOCR.Pixels(window((25, 110, 240))))), .wework)
        XCTAssertNil(XiaoLanPanes.tabApp(try XCTUnwrap(WatchOCR.Pixels(window(nil)))))
    }

    /// "企微测试群（7）0": the（7）is the head count, the 0 the WeCom logo; the chat is 企微测试群.
    func testHeadCountAndLogoAreNoName() {
        XCTAssertEqual(WatchOCR.titled("企微测试群（7）0").name, "企微测试群")
        XCTAssertEqual(WatchOCR.titled("企微测试群（7）O").name, "企微测试群")
        XCTAssertEqual(WatchOCR.titled("企微测试群（7）Q").name, "企微测试群")
        XCTAssertEqual(WatchOCR.titled("测试群(6)").name, "测试群")
        XCTAssertEqual(WatchOCR.withoutIconTail("测试群0"), "测试群0")  // no head count before it: part of a name
        XCTAssertTrue(WatchChatOpen.sameChat(WatchOCR.titled("企微测试群（7）0").name, listName: "企微测试群"))
    }

    /// "同事们在看《安克被告…》", 行业资讯's preview, read as a chat when the rows came closer together.
    func testPreviewLineIsNoChat() {
        let list: [[P]] = [[at("行业资讯", 0.2, 0.30, 0.15)], [at("同事们在看《安克被告》", 0.2, 0.32, 0.6)],
                           [at("企业微信团队", 0.2, 0.355, 0.2)], [at("登录操作通知", 0.2, 0.375, 0.3)]]
        XCTAssertEqual(XiaoLanPanes.entries(list).map(\.name), ["行业资讯", "企业微信团队"])
    }

    /// User 11-25: "兩個號在一個群里…就相當于是同一個人，就不用回復了": what one account said is known on the other side.
    func testOwnersOtherAccount() {
        let sent = [XiaoLanSelf.Sent(app: .wework, chat: "企微测试群", text: "【小蓝测试】180 企微发消息 2300", at: 100)]
        XCTAssertTrue(XiaoLanSelf.sentByOther("【小蓝测试】180企微发消息2300", chat: "企微测试群", app: .wechat, sent: sent, now: 150))
        XCTAssertFalse(XiaoLanSelf.sentByOther("【小蓝测试】180企微发消息2300", chat: "企微测试群", app: .wework, sent: sent, now: 150))
        XCTAssertFalse(XiaoLanSelf.sentByOther("【小蓝测试】180企微发消息2300", chat: "测试群", app: .wechat, sent: sent, now: 150))
        // 183 (11-26: a line sent 33 min before came back on a scrolled-up screen and was reported): 4 hours, was 10 min
        XCTAssertTrue(XiaoLanSelf.sentByOther("【小蓝测试】180企微发消息2300", chat: "企微测试群", app: .wechat, sent: sent, now: 900))
        XCTAssertFalse(XiaoLanSelf.sentByOther("【小蓝测试】180企微发消息2300", chat: "企微测试群", app: .wechat, sent: sent,
                                               now: 100 + XiaoLanSelf.sentWindow + 1))
        XCTAssertFalse(XiaoLanSelf.sentByOther("你好", chat: "企微测试群", app: .wechat, sent: sent, now: 150))
        XCTAssertTrue(XiaoLanSelf.isOwner("蓝海乐@微信", names: ["蓝海乐"]))
        XCTAssertFalse(XiaoLanSelf.isOwner("范兆磊", names: ["蓝海乐"]))
        XCTAssertFalse(XiaoLanSelf.isOwner("", names: [""]))
    }

    /// 514 for "2026-11-25" to "2026-11-25" returned nothing; the times are the device's own zone.
    func testLogRangeIsTheDeviceDay() throws {
        let taipei = try XCTUnwrap(TimeZone(identifier: "Asia/Taipei")), seoul = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let day = XiaoLanMedia.logBounds("2026-11-25", "2026-11-25", zone: taipei)
        XCTAssertEqual(day.0, "2026-11-24T16:00:00")
        XCTAssertEqual(day.1, "2026-11-25T16:00:00")
        XCTAssertTrue("2026-11-25T13:52:13" >= day.0 && "2026-11-25T13:52:13" < day.1)
        XCTAssertEqual(XiaoLanMedia.logBounds("2026-11-25", "", zone: seoul).0, "2026-11-24T15:00:00")
        let minutes = XiaoLanMedia.logBounds("2026-11-25 09:00", "2026-11-25 09:30", zone: taipei)
        XCTAssertEqual(minutes.0, "2026-11-25T01:00:00")
        XCTAssertEqual(minutes.1, "2026-11-25T01:31:00")
        XCTAssertEqual(XiaoLanMedia.logBounds("", "", zone: taipei).0, "")
    }
}
