import XCTest
import UIKit
@testable import IPhoneAgent

/// 188 (user 11-27): links, pictures, videos, files and voice notes opened and looked at; replies quoting their line;
/// @me with OCR's full-width ＠ (B29). The words and places are as read on the iPad 11-27 (docs/plan-188-media.md).
@MainActor final class Build188MediaTests: XCTestCase {
    typealias F = XiaoLanMediaFind

    func piece(_ text: String, _ x: Double, _ y: Double, w: Double = 0.1, h: Double = 0.016) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: text, box: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
    }

    func testPreviewTagsTellTheKind() {
        XCTAssertEqual(F.tag("[语音] 7\""), .voice)
        XCTAssertEqual(F.tag("［图片］"), .image)
        XCTAssertEqual(F.tag("张三: [视频]"), .video)
        XCTAssertEqual(F.tag("[文件] 6原生家庭创伤治愈.docx"), .file)
        XCTAssertEqual(F.tag("[链接] 抖音"), .link)
        XCTAssertNil(F.tag("[动画表情]"))
        XCTAssertNil(F.tag("你好"))
    }

    func testLinesTellTheKind() {
        XCTAssertEqual(F.kind(of: "7.97 复制打开抖音，看看【某某的作品】 https://v.douyin.com/iAbCdEf/ r@E.uf"), .link)
        XCTAssertEqual(F.kind(of: "6原生家庭创伤治愈.docx"), .file)
        XCTAssertEqual(F.kind(of: "伤治愈.docx13K"), .file)
        XCTAssertEqual(F.kind(of: "•））4\""), .voice)
        XCTAssertNil(F.kind(of: "这不对"))
        XCTAssertNil(F.kind(of: "我等你5分钟"))
        XCTAssertNil(F.kind(of: "【小蓝测试】187个微 0016"))
    }

    func testVoiceSecondsAndClocks() {
        XCTAssertEqual(F.voiceSeconds("4\""), 4)
        XCTAssertEqual(F.voiceSeconds("•））12″"), 12)
        XCTAssertNil(F.voiceSeconds("他说\"好\"了吗"))
        XCTAssertEqual(F.clockSeconds("0:09"), 9)
        XCTAssertEqual(F.clockSeconds("1:02:03"), 3723)
        XCTAssertNil(F.clockSeconds("00:04/00:09"))
    }

    func testPlayerLengthBothApps() {
        XCTAssertEqual(F.playerLength([[piece("00:04/00:09", 0.3, 0.808)]]), 9)       // WeChat
        XCTAssertEqual(F.playerLength([[piece("00:00:00:09", 0.25, 0.810)]]), 9)      // WeCom: now and length run together
        XCTAssertEqual(F.playerLength([[piece("01:10/03:25", 0.3, 0.80)]]), 205)
        XCTAssertNil(F.playerLength([[piece("这不对", 0.3, 0.63)]]))
    }

    func testVideoLabelIsNotACentredTimeLabel() {
        let rows = [[piece("17:35", 0.5, 0.30, w: 0.06, h: 0.012)], [piece("0:09", 0.30, 0.49, w: 0.03, h: 0.008)]]
        let label = F.videoLabel(rows)
        XCTAssertEqual(label?.text, "0:09")
        let spot = F.videoSpot(label!)
        XCTAssertLessThan(Double(spot.x), 0.30)
        XCTAssertLessThan(Double(spot.y), 0.49)
        XCTAssertNil(F.videoLabel([[piece("17:35", 0.5, 0.30, w: 0.06, h: 0.012)]]))
    }

    func testButtonsAndNeverCancelConversion() {
        let menu = [[piece("听筒模式", 0.3, 0.64)], [piece("取消转换", 0.4, 0.64)], [piece("引用", 0.5, 0.64)]]
        XCTAssertNil(F.button(menu, "转文字"))
        XCTAssertNotNil(F.button(menu, "引用"))
        XCTAssertNil(F.voiceButton([[piece("取消转文字", 0.6, 0.8)]]))
        XCTAssertEqual(F.voiceButton([[piece("•转文字", 0.6, 0.809)]])?.y ?? 0, 0.809, accuracy: 0.001)
        XCTAssertNotNil(F.button([[piece("关闭", 0.05, 0.054)]], "关闭", bottom: 0.12))
        XCTAssertNil(F.button([[piece("预览", 0.48, 0.165)]], "预览", top: 0.4))  // the sheet's title, not the page's button
    }

    func testFileCardPicksTheHintedOne() {
        let rows = [[piece("6原生家庭创伤治愈.docx", 0.4, 0.207)], [piece("13K", 0.2, 0.229)], [piece("感.docx13K", 0.3, 0.728)]]
        XCTAssertEqual(F.fileCard(rows, hint: "[文件] 6原生家庭创伤治愈.docx")?.y ?? 0, 0.207, accuracy: 0.001)
        XCTAssertEqual(F.fileCard(rows, hint: "[文件]")?.y ?? 0, 0.728, accuracy: 0.001)
    }

    func testLinkSpotIsTheAddressLine() {
        let rows = [[piece("复制打开抖音 https://v.douyin.com/iAbCdEf/", 0.3, 0.35)], [piece("r@E.uf:1pmliP:/04/26", 0.3, 0.37)]]
        XCTAssertEqual(Double(F.linkSpot(rows)?.box.midY ?? 0), 0.35, accuracy: 0.001)
        XCTAssertEqual(F.url(in: "看 https://v.douyin.com/iAbCdEf/ 。"), "https://v.douyin.com/iAbCdEf/")
    }

    func testVoiceWordsAreWhatCameAfter() {
        let before = [piece("这是什么", 0.3, 0.614), piece("（小））", 0.06, 0.739)]
        let after = before + [piece("你说什么？你说什么？你说", 0.5, 0.785), piece("什么？你说什么？", 0.4, 0.809),
                              piece("✓ 转换完成", 0.4, 0.83)]
        XCTAssertEqual(F.added(before: before, after: after), "你说什么？你说什么？你说什么？你说什么？")
    }

    func testQuoteSpotAndBar() {
        let rows = [[piece("主人蓝海乐", 0.25, 0.65)], [piece("这是什么", 0.29, 0.682)], [piece("发消息或按住", 0.4, 0.92)]]
        XCTAssertEqual(F.quoteSpot(rows, quote: "这是什么")?.y ?? 0, 0.682, accuracy: 0.001)
        XCTAssertNil(F.quoteSpot(rows, quote: "完全不在屏幕上的话"))
        XCTAssertNotNil(F.quoteBar([[piece("主人蓝海乐：这是什么", 0.35, 0.727)]], quote: "这是什么"))
        XCTAssertNotNil(F.quoteBar([[piece("主人蓝海乐: 这不对", 0.35, 0.80)]], quote: "这不对"))
        XCTAssertNil(F.quoteBar([[piece("这是什么", 0.35, 0.727)]], quote: "这是什么"))
    }

    func testBlankSpotAvoidsWords() {
        let rows = (0..<12).map { [piece("行\($0)", 0.3, 0.1 + Double($0) * 0.07)] }
        XCTAssertNil(F.blankSpot(rows))
        let spot = F.blankSpot([[piece("引用", 0.5, 0.64)]])
        XCTAssertNotNil(spot)
        XCTAssertGreaterThanOrEqual(abs(Double(spot!.y) - 0.64), 0.04)
    }

    func testReportKeepsTheLineAndSaysWhy() {
        XCTAssertEqual(F.report("[语音] 7\"", kind: .voice, seen: "语音转文字：你好", failed: nil), "[语音] 7\"\n语音转文字：你好")
        XCTAssertEqual(F.report("6原生家庭创伤治愈.docx", kind: .file, seen: nil, failed: "文件没有打开"),
                       "[文件] 6原生家庭创伤治愈.docx\n（小蓝没能打开看：文件没有打开）")
    }

    func testAtMeWithFullWidthAt() {
        XCTAssertTrue(F.atMe("＠蓝海乐 看一下", names: ["蓝海乐"]))
        XCTAssertTrue(F.atMe("@ 蓝海乐 看一下", names: ["蓝海乐"]))
        XCTAssertFalse(F.atMe("蓝海乐 看一下", names: ["蓝海乐"]))
        XCTAssertFalse(F.atMe("＠别人", names: ["蓝海乐", ""]))
    }

    func testEveryKindOnUntilTurnedOff() {
        let k = F.Kind.file
        let old = UserDefaults.standard.object(forKey: MediaSettings.key(k))
        defer { UserDefaults.standard.set(old, forKey: MediaSettings.key(k)) }
        UserDefaults.standard.removeObject(forKey: MediaSettings.key(k))
        XCTAssertTrue(MediaSettings.on(k))
        MediaSettings.set(k, false)
        XCTAssertFalse(MediaSettings.on(k))
    }

    // MARK: 188 places (XiaoLanSpots), menus, WeChat's blocked link, WeCom's groups first

    func testSpotsDefaultLearnAndForget() {
        let old = XiaoLanSpots.store
        let suite = UserDefaults(suiteName: "spots-test-188")!
        suite.removePersistentDomain(forName: "spots-test-188")
        XiaoLanSpots.store = suite
        defer { XiaoLanSpots.store = old }
        // measured on the iPad 9: the default until something is learned
        let d = XiaoLanSpots.spot(.playerClose, app: .wework, width: 0.495, model: "iPad7,11")
        XCTAssertEqual(d?.x ?? 0, 0.05, accuracy: 0.0001)
        XCTAssertEqual(d?.learned, false)
        XiaoLanSpots.learn(.playerClose, app: .wework, width: 0.495, at: CGPoint(x: 0.06, y: 0.05), model: "iPad7,11")
        let l = XiaoLanSpots.spot(.playerClose, app: .wework, width: 0.495, model: "iPad7,11")
        XCTAssertEqual(l?.learned, true)
        XCTAssertEqual(l?.x ?? 0, 0.06, accuracy: 0.0001)
        // another device or another width finds it again (the default)
        XCTAssertEqual(XiaoLanSpots.spot(.playerClose, app: .wework, width: 0.495, model: "iPad13,1")?.learned, false)
        XCTAssertEqual(XiaoLanSpots.spot(.playerClose, app: .wework, width: 0.33, model: "iPad7,11")?.learned, false)
        // two misses in a row forget it
        XiaoLanSpots.missed(.playerClose, app: .wework, width: 0.495, model: "iPad7,11")
        XCTAssertEqual(XiaoLanSpots.spot(.playerClose, app: .wework, width: 0.495, model: "iPad7,11")?.learned, true)
        XiaoLanSpots.missed(.playerClose, app: .wework, width: 0.495, model: "iPad7,11")
        XCTAssertEqual(XiaoLanSpots.spot(.playerClose, app: .wework, width: 0.495, model: "iPad7,11")?.learned, false)
        // no default and nothing learned: found by its words only
        XCTAssertNil(XiaoLanSpots.spot(.menuVoiceText, app: .wework, width: 0.495, model: "iPad7,11"))
    }

    func testRelativeSpotsAreOffsetsFromThePress() {
        let pressed = CGPoint(x: 0.6, y: 0.5)
        let p = XiaoLanSpots.point(.menuOpenLink, app: .wechat, width: 0.49, from: pressed)
        XCTAssertEqual(Double(p?.x ?? 0), 0.70, accuracy: 0.0001)
        XCTAssertEqual(Double(p?.y ?? 0), 0.55, accuracy: 0.0001)
        XCTAssertNil(XiaoLanSpots.point(.menuOpenLink, app: .wechat, width: 0.49))
        let t = XiaoLanSpots.taught(.menuQuote, found: CGPoint(x: 0.4, y: 0.45), from: pressed)
        XCTAssertEqual(Double(t?.x ?? 0), -0.2, accuracy: 0.0001)
    }

    func testMenuItemInsideAMenuRowNotASentence() {
        let row = [[piece("拷贝搜一搜翻译打开链接＞", 0.52, 0.302, w: 0.757)]]
        let p = F.menuItem(row, "打开链接")
        XCTAssertNotNil(p)
        XCTAssertGreaterThan(Double(p!.x), 0.52)  // right of the row's middle, where 打开链接 is
        XCTAssertNil(F.menuItem([[piece("14天内可以预览和下载", 0.48, 0.785)]], "预览"))
        XCTAssertNotNil(F.menuItem([[piece("引用", 0.14, 0.559)]], "引用"))
    }

    func testWeChatBlockedLinkPage() {
        let page = [[piece("如需浏览，请长按网址复制后使", 0.48, 0.169, w: 0.75)], [piece("用浏览器访问", 0.48, 0.200)],
                    [piece("nttps://.douyin.com/r4iPzEkckGg/", 0.48, 0.258, w: 0.66)]]
        XCTAssertTrue(F.linkBlocked(page))
        XCTAssertEqual(F.addressLine(page)?.text, "nttps://.douyin.com/r4iPzEkckGg/")
        XCTAssertFalse(F.linkBlocked([[piece("这是什么", 0.3, 0.6)]]))
        XCTAssertTrue(F.safariShown([[piece("Safari浏览器", 0.2, 0.015)]]))
        XCTAssertFalse(F.safariShown([[piece("Safari浏览器会阻止追踪器", 0.2, 0.40)]]))
    }

    func testWeComGroupRowOnWeChatsList() {
        let rows = [[piece("企微测试群Q", 0.36, 0.24)], [piece("测试群", 0.29, 0.16)]]
        XCTAssertTrue(XiaoLanPanes.weComGroupRow(rows, name: "企微测试群"))
        XCTAssertFalse(XiaoLanPanes.weComGroupRow(rows, name: "测试群"))
    }

    // MARK: 188 replies in the order the messages came, WeChat and WeCom together

    func testNextTurnWaitsForAnEarlierReply() {
        XCTAssertNil(PaneTurns.next(firsts: [nil, nil], asking: [nil, nil]))
        XCTAssertEqual(PaneTurns.next(firsts: [5, 3], asking: [nil, nil])?.index, 1)
        XCTAssertNil(PaneTurns.next(firsts: [5, nil], asking: [nil, 4]))  // WeCom's message read first: its reply goes first
        XCTAssertEqual(PaneTurns.next(firsts: [5, nil], asking: [6, nil])?.turn, 5)
    }

    func testFirstMarkIsTheOneSeenFirst() {
        let marks = [(name: "新的", at: CGPoint(x: 0.5, y: 0.2)), (name: "旧的", at: CGPoint(x: 0.5, y: 0.4))]
        XCTAssertEqual(PaneTurns.first(marks, seen: { $0 == "旧的" ? 1 : 2 })?.name, "旧的")
        XCTAssertEqual(PaneTurns.first(marks, seen: { _ in 1 })?.name, "旧的")  // seen together: the lower row
        XCTAssertEqual(PaneTurns.first(marks, seen: { $0 == "新的" ? 1 : 2 })?.name, "新的")
    }

    func testOrdersOfBothLinksGoInTurn() throws {
        let wechat = ChatToolLink(), wework = ChatToolLink(app: .wework)
        func packet(_ id: String) -> String {
            #"{"socketType":2,"messageId":""# + id + #"","list":[{"type":203,"titleList":["测试群"],"receivedContent":"收到"}]}"#
        }
        _ = wework.accept(packet("a1"), now: Date())  // 企微 first
        _ = wechat.accept(packet("b1"), now: Date())  // then 个微
        _ = wework.accept(packet("a2"), now: Date())  // then 企微 again
        var done: [String] = []
        while let next = PaneTurns.next(firsts: [wechat.firstTurn, wework.firstTurn], asking: [nil, nil]) {
            let c = try XCTUnwrap([wechat, wework][next.index].take(turn: next.turn))
            done.append(c.messageId)
        }
        XCTAssertEqual(done, ["a1", "b1", "a2"])
    }

    // MARK: 188 voice notes, videos and pictures as lines; echoes; an unchanged window

    /// A WeChat chat window 480×1150: its grey, someone's avatar at the left and, beside it, `draw`'s message.
    func chat(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 480, height: 1150), format: format).jpegData(withCompressionQuality: 0.95) { r in
            let c = r.cgContext
            c.setFillColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1)
            c.fill(CGRect(x: 0, y: 0, width: 480, height: 1150))
            draw(c)
        }
    }
    func avatar(_ c: CGContext, y: CGFloat) {
        c.setFillColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1); c.fill(CGRect(x: 10, y: y, width: 19, height: 40))
        c.setFillColor(red: 0.2, green: 0.3, blue: 0.8, alpha: 1); c.fill(CGRect(x: 29, y: y, width: 19, height: 40))
    }

    func testAPictureBesideAnAvatarIsALineAndItsWordsAreNot() throws {
        let jpeg = chat { c in
            avatar(c, y: 345)
            for k in 0..<10 {  // a photo: bands of colour
                c.setFillColor(red: 0.9 - CGFloat(k) * 0.05, green: 0.5, blue: 0.2 + CGFloat(k) * 0.06, alpha: 1)
                c.fill(CGRect(x: 77, y: 345 + CGFloat(k) * 17, width: 163, height: 17))
            }
            avatar(c, y: 700)  // a bubble of words: white, a few dark lines
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); c.fill(CGRect(x: 77, y: 700, width: 170, height: 110))
            c.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
            for k in 0..<4 { c.fill(CGRect(x: 90, y: 715 + CGFloat(k) * 24, width: 140, height: 6)) }
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(jpeg))
        let blocks = F.pictureBlocks(px, pieces: [], top: 0.09, bottom: 0.93)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(Double(blocks.first?.minX ?? 0), 0.16, accuracy: 0.02)
        XCTAssertEqual(Double(blocks.first?.minY ?? 0), 0.30, accuracy: 0.02)
        let onPicture = WatchOCR.Piece(text: "姓名張知遠", box: CGRect(x: 0.2, y: 0.36, width: 0.2, height: 0.02), kind: .theirs)
        let words = WatchOCR.Piece(text: "这是什么", box: CGRect(x: 0.2, y: 0.63, width: 0.2, height: 0.02), kind: .theirs)
        let out = F.withMedia([onPicture, words], px, top: 0.09, bottom: 0.93)
        XCTAssertTrue(out.contains { $0.text == "[图片]" })
        XCTAssertFalse(out.contains { $0.text == "姓名張知遠" })
        XCTAssertTrue(out.contains { $0.text == "这是什么" })
    }

    func testVoiceAndVideoBecomeLines() throws {
        let px = try XCTUnwrap(WatchOCR.Pixels(chat { _ in }))
        let pieces = [WatchOCR.Piece(text: "•））4\"", box: CGRect(x: 0.2, y: 0.69, width: 0.08, height: 0.02), kind: .theirs),
                      WatchOCR.Piece(text: "•转文字", box: CGRect(x: 0.55, y: 0.80, width: 0.08, height: 0.02), kind: .grey),
                      WatchOCR.Piece(text: "（小））", box: CGRect(x: 0.05, y: 0.80, width: 0.05, height: 0.02), kind: .theirs),
                      WatchOCR.Piece(text: "0:09", box: CGRect(x: 0.38, y: 0.49, width: 0.03, height: 0.008), kind: .other),
                      WatchOCR.Piece(text: "17:35", box: CGRect(x: 0.47, y: 0.30, width: 0.06, height: 0.012), kind: .grey)]
        let texts = F.withMedia(pieces, px, top: 0.09, bottom: 0.93).map { $0.text }
        XCTAssertTrue(texts.contains("[语音] 4\""))
        XCTAssertTrue(texts.contains("[语音]"))        // WeChat's 转文字 beside a note
        XCTAssertFalse(texts.contains("（小））"))      // its speaker read as signs
        XCTAssertTrue(texts.contains("[视频] 0:09"))
        XCTAssertTrue(texts.contains("17:35"))         // a time label stays what it was
        XCTAssertEqual(F.kind(of: "[视频] 0:09"), .video)
        XCTAssertEqual(F.kind(of: "[图片]"), .image)
    }

    func testVoiceWordsAreNotReportedTwice() {
        let said = ["你说什么？你说什么？你说什么？你说什么？"]
        XCTAssertTrue(F.isEcho("你说什么？你说什么？你说", of: said))
        XCTAssertTrue(F.isEcho("[语音] 4\"你说什么？", of: said))  // WeCom: inside the note's bubble
        XCTAssertFalse(F.isEcho("[语音] 4\"", of: said))           // a new voice note
        XCTAssertFalse(F.isEcho("明天见", of: said))
    }

    func testPickByRankFromTheBottom() {
        XCTAssertEqual(F.pick([1, 2, 3], rank: 0), 3)
        XCTAssertEqual(F.pick([1, 2, 3], rank: 2), 1)
        XCTAssertEqual(F.pick([1, 2, 3], rank: 5), 3)
        XCTAssertNil(F.pick([Int](), rank: 0))
    }

    func testUnchangedWindowAndMediaQuote() throws {
        let a = try XCTUnwrap(WatchOCR.Pixels(chat { _ in }))
        let b = try XCTUnwrap(WatchOCR.Pixels(chat { c in c.setFillColor(red: 1, green: 0.2, blue: 0.2, alpha: 1); c.fillEllipse(in: CGRect(x: 60, y: 300, width: 18, height: 18)) }))
        XCTAssertTrue(F.sameSignature(F.signature(a), F.signature(a)))
        XCTAssertFalse(F.sameSignature(F.signature(a), F.signature(b)))  // a red mark came
        let rows = [[piece("6原生家庭创伤治愈.docx", 0.4, 0.5)], [piece("•））4\"", 0.25, 0.7, w: 0.08)]]
        XCTAssertEqual(F.mediaQuoteSpot(rows, nil, quote: "[语音] 4\"\n语音转文字：你好")?.y ?? 0, 0.7, accuracy: 0.001)
        XCTAssertEqual(F.mediaQuoteSpot(rows, nil, quote: "[文件] 6原生家庭创伤治愈.docx\n内容：…")?.y ?? 0, 0.5, accuracy: 0.001)
        XCTAssertNil(F.mediaQuoteSpot(rows, nil, quote: "这是什么"))
    }

    // MARK: 188 night: a window's bottom over Echo's own panel

    func testWindowBottomOverEchosPanel() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280), format: format).jpegData(withCompressionQuality: 0.95) { r in
            let c = r.cgContext
            c.setFillColor(red: 0.78, green: 0.75, blue: 0.86, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 960, height: 1280))  // wallpaper
            c.setFillColor(red: 0.94, green: 0.94, blue: 0.95, alpha: 1); c.fill(CGRect(x: 25, y: 1150, width: 910, height: 70))  // Echo's panel
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            c.fill(CGRect(x: 0, y: 0, width: 456, height: 1110)); c.fill(CGRect(x: 468, y: 0, width: 492, height: 1110))
            c.fill(CGRect(x: 0, y: 1110, width: 430, height: 40)); c.fill(CGRect(x: 494, y: 1110, width: 466, height: 40))  // rounded corners
            c.setFillColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1)
            c.fill(CGRect(x: 0, y: 1008, width: 456, height: 3)); c.fill(CGRect(x: 468, y: 1008, width: 492, height: 3))  // a sharp row at 0.79
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(jpeg))
        let windows = XiaoLanPanes.windows(px)
        XCTAssertEqual(windows.count, 2)
        for w in windows {
            XCTAssertGreaterThan(Double(w.height), 0.86)  // not cut at the 0.79 row: the input bar and my newest line stay in
            XCTAssertLessThan(Double(w.height), 0.95)
        }
    }

    func testAFileCardIsNotASentenceNamingTheFile() {
        XCTAssertTrue(F.cardText("6原生家庭创伤治愈.docx"))
        XCTAssertTrue(F.cardText("伤治愈.docx13K"))
        XCTAssertFalse(F.cardText("【模拟服务器】收到：6原生家庭创伤治愈.docx13K"))
        let rows = [[piece("6原生家庭创伤治愈.docx", 0.4, 0.35)], [piece("【模拟服务器】收到：6原生家庭创伤治愈.docx13K", 0.6, 0.42)]]
        XCTAssertEqual(F.fileCard(rows, hint: "")?.y ?? 0, 0.35, accuracy: 0.001)
    }

    /// Two windows on the wallpaper; `video`: the right one shows a picture whose left edge matches the wallpaper on
    /// half its rows (Douyin's web page in WeCom, 11-27 06:58).
    func split(video: Bool) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280), format: format).jpegData(withCompressionQuality: 0.95) { r in
            let c = r.cgContext
            c.setFillColor(red: 0.78, green: 0.75, blue: 0.86, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 960, height: 1280))
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            c.fill(CGRect(x: 0, y: 0, width: 456, height: 1150)); c.fill(CGRect(x: 468, y: 0, width: 492, height: 1150))
            guard video else { return }
            for k in 0..<24 {  // bands: half of them the wallpaper's own colour at the window's edge
                let y = 150 + CGFloat(k) * 40
                if k % 2 == 0 { c.setFillColor(red: 0.78, green: 0.75, blue: 0.86, alpha: 1) } else { c.setFillColor(red: 0.2, green: 0.3, blue: 0.2, alpha: 1) }
                c.fill(CGRect(x: 468, y: y, width: 492, height: 40))
            }
        }
    }

    func testTheGapKeptWhenAPictureBlursOneEdge() throws {
        let normal = try XCTUnwrap(WatchOCR.Pixels(split(video: false)))
        XCTAssertEqual(XiaoLanPanes.windows(normal).count, 2)
        let page = try XCTUnwrap(WatchOCR.Pixels(split(video: true)))
        XCTAssertEqual(XiaoLanPanes.windows(page).count, 2)  // not one window: no "a window is gone", the watch goes on
    }

    func testMyLongBubbleAtTheTopIsNoBanner() throws {
        let jpeg = chat { c in
            c.setFillColor(red: 149 / 255, green: 236 / 255, blue: 105 / 255, alpha: 1)  // WeChat's green, mine
            c.fill(CGRect(x: 120, y: 110, width: 300, height: 70))
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(jpeg))
        let lines = [CandidatePicker.Piece(text: "【小蓝测试】188个微长消", box: CGRect(x: 0.28, y: 0.100, width: 0.55, height: 0.02)),
                     CandidatePicker.Piece(text: "息：这一条故意写得比较长，", box: CGRect(x: 0.28, y: 0.125, width: 0.55, height: 0.02))]
        XCTAssertTrue(WatchOCR.bannerShown(lines))            // words alone: as before
        XCTAssertFalse(WatchOCR.bannerShown(lines, px: px))  // on my green bubble: no banner
    }
}
