import XCTest
import UIKit
@testable import IPhoneAgent

/// 192 (Echo 191 tested over USB 11-27 16:15–16:43; user: 「把所有已知的BUG…一次性全部修進去」): a voice note's own
/// 转文字 (N47), a photo of a white page and a 视频号 card at the top found as pictures (N48, N43), a link chosen as a
/// message, a wrapped or misread address clicked on its own characters (N38, N49), a page wider than its window read
/// in parts (N50), a file card's size kept with it (B28), someone's recall reported (B30), the owner's name in a group
/// only both accounts are in (O1), Echo's own window known (B26), the app said to the model.
@MainActor final class Build192Tests: XCTestCase {
    typealias F = XiaoLanMediaFind

    func p(_ t: String, _ y: Double, x: Double = 0.2, w: Double = 0.55, h: Double = 0.02) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: t, box: CGRect(x: x, y: y, width: w, height: h))
    }

    /// N47 (11-27 16:21): two notes, only the older with 「转文字」 beside it; the newer's job has none of its own.
    func testAVoiceNotesOwnButtonOnly() throws {
        let rows = [[p("3\"", 0.53, x: 0.18, w: 0.1)], [p("转文字", 0.535, x: 0.5, w: 0.12)], [p("3\"", 0.78, x: 0.18, w: 0.1)]]
        let spots = F.voiceSpots(rows)
        XCTAssertEqual(spots.count, 2)
        XCTAssertNotNil(F.voiceButton(rows, beside: spots[0]))
        XCTAssertNil(F.voiceButton(rows, beside: spots[1]), "the newer note has no button of its own")
    }

    /// N49 (WeCom 11-27 16:24): the address wrapped after 「https://」 is clicked on the next line, on its characters;
    /// the file card under it is no link.
    func testAWrappedAddressIsClickedOnItsOwnLine() throws {
        let rows = [[p("粉粉嫩嫩的，阳光也偏爱～ https://", 0.60)], [p("xhslink.cn/o/gLh9ko7VJj 把这段复", 0.622)],
                    [p("制好，然后去【小红书】就能看笔", 0.644)], [p("记。", 0.666, w: 0.05)],
                    [p("太上老君说五斗金章受生", 0.72)], [p("经.docx", 0.742, w: 0.15)]]
        let line = try XCTUnwrap(F.linkLine(rows, text: "粉粉嫩嫩的，阳光也偏爱～ https://xhslink.cn/o/gLh9ko7VJj 把这段复制好", rank: 0))
        XCTAssertTrue(line.text.hasPrefix("xhslink"))
        XCTAssertLessThan(Double(F.addressMiddle(line).x), 0.2 + 0.55 * 0.6, "on the address, not the words after it")
        XCTAssertEqual(F.linkBubbles(rows).count, 1, "the file card is no link")
    }

    /// N38 (the four shares as the iPad read them, 11-27 16:43): each job finds its own message; Douyin's address,
    /// read 「.nttps://v.aouyin.com」, is still its address line.
    func testEachShareFindsItsOwnMessage() throws {
        let rows = [[p("1.07 复制打开抖音，看看", 0.14)], [p("【dontbesilent 聊赚钱的作品", 0.162)],
                    [p("... .nttps://v.aouyin.com/fv63", 0.184)], [p("3uNFr3g/ P@X.zt 11/15", 0.206)],
                    [p("https://xhslink.cn/o/7CHZf", 0.40)], [p("N6qIKN 拷走链接，去【小红", 0.422)], [p("书】逛逛分享～", 0.444, w: 0.3)],
                    [p("https://v.kuaishou.com/nq2", 0.51)], [p("LENRb \"亲子满级挑战赛\"老", 0.532)],
                    [p("手被播放过 190.6 万次，点", 0.554)], [p("击链接，打开【快手】直接观", 0.576)]]
        XCTAssertEqual(F.linkBubbles(rows).count, 3)
        let dy = try XCTUnwrap(F.linkLine(rows, text: "1.07 复制打开抖音，看看【dontbesilent 聊赚钱的作品", rank: 0))
        XCTAssertTrue(dy.text.contains("aouyin"), "Douyin's own address line, not Kuaishou's 「打开【快手】」")
        let ks = try XCTUnwrap(F.linkLine(rows, text: "https://v.kuaishou.com/nq2LENRb", rank: 0))
        XCTAssertTrue(ks.text.contains("kuaishou"))
        XCTAssertEqual(F.url(in: ".nttps://v.aouyin.com/fv63"), "https://v.aouyin.com/fv63")
        XCTAssertEqual(F.url(in: "见 http://example.com/a"), "http://example.com/a", "a right scheme left as it is")
    }

    /// A share with no address is clicked on its own words, never the group's name over the bubble.
    func testAShareWithNoAddressIsClickedOnItsWords() throws {
        let rows = [[p("主人蓝海乐", 0.30, x: 0.18, w: 0.12)], [p("1.07复制打开抖音，看看", 0.322)], [p("【dontbesilent聊赚钱.更多", 0.344)]]
        let line = try XCTUnwrap(F.linkLine(rows, text: "1.07复制打开抖音，看看【dontbesilent聊赚钱.更多", rank: 0))
        XCTAssertTrue(line.text.contains("抖音"))
        XCTAssertGreaterThan(F.likeness("107复制打开抖音看看", "107复制打开抖音看看dontbesilent"), 0.9)
        XCTAssertLessThan(F.likeness("107复制打开抖音看看", "击链接打开快手直接观"), 0.5)
    }

    /// N50 (WeCom's .docx preview 11-27 16:26): lines cut at the right edge, dragged left, joined where they overlap.
    func testAWidePageIsJoinedLineByLine() {
        XCTAssertEqual(F.overlapJoin("尔时，太上老君在太清境上、大赤天中、黄", "上老君在太清境上、大赤天中、黄金殿内，召"),
                       "尔时，太上老君在太清境上、大赤天中、黄金殿内，召")
        XCTAssertEqual(F.overlapJoin("abc", "abc"), "abc")
        let left = [p("尔时，太上老君在太清境上、大赤天中、黄", 0.2, x: 0.02, w: 0.97),
                    p("五老帝君及东斗注算君、南斗上生君、西斗记", 0.23, x: 0.02, w: 0.97),
                    p("落死君、中斗总监君、九天生神君、九天注生", 0.26, x: 0.02, w: 0.97)]
        XCTAssertTrue(F.cutOnRight([left]))
        XCTAssertFalse(F.cutOnRight([[p("短的一行字", 0.2, w: 0.3)]]))
        let right = [p("上老君在太清境上、大赤天中、黄金殿内，召", 0.201, x: 0.0, w: 0.9),
                     p("东斗注算君、南斗上生君、西斗记名君、北斗", 0.231, x: 0.0, w: 0.9)]
        let lines = F.joinWide([left, right])
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], "尔时，太上老君在太清境上、大赤天中、黄金殿内，召")
        XCTAssertEqual(lines[1], "五老帝君及东斗注算君、南斗上生君、西斗记名君、北斗")
    }

    /// N48/N43: a white block with no chat-sized words is a picture; a 视频号 card knows its author.
    func testWordsOfAChatsSizeAndAChannelsCardsAuthor() {
        let r = CGRect(x: 0.17, y: 0.6, width: 0.35, height: 0.2)
        let tiny = WatchOCR.Piece(text: "姓名", box: CGRect(x: 0.2, y: 0.65, width: 0.05, height: 0.006), kind: .other)
        XCTAssertEqual(F.chatWordsShare([tiny], in: r), 0)
        let lines = (0..<6).map { WatchOCR.Piece(text: "一行字", box: CGRect(x: 0.2, y: 0.605 + Double($0) * 0.032, width: 0.2, height: 0.024), kind: .theirs) }
        XCTAssertGreaterThan(F.chatWordsShare(lines, in: r), 0.5)
        let card = CGRect(x: 0.175, y: 0.706, width: 0.415, height: 0.2)
        let author = WatchOCR.Piece(text: "凶露露Iulu0517", box: CGRect(x: 0.2, y: 0.88, width: 0.2, height: 0.02), kind: .other)
        XCTAssertEqual(F.channelsAuthor([author], in: card), "凶露露Iulu0517")
        XCTAssertNil(F.channelsAuthor(lines, in: card), "a picture with words over it is no card")
    }

    /// N48 (Echo 191 11-27 16:23): the avatar reaching 0.14 of the window, a photo of a white page beside it (mostly
    /// white, small print, a dark portrait) is one picture block; a white bubble of chat-sized words beside the next
    /// avatar is not.
    func testAPhotoOfAWhitePageBesideAWideAvatarIsAPicture() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 1150), format: format).jpegData(withCompressionQuality: 0.95) { r in
            let c = r.cgContext
            c.setFillColor(red: 237 / 255, green: 237 / 255, blue: 237 / 255, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 480, height: 1150))
            func avatar(_ y: CGFloat) {
                c.setFillColor(red: 0.3, green: 0.6, blue: 0.2, alpha: 1); c.fill(CGRect(x: 10, y: y, width: 28, height: 55))
                c.setFillColor(red: 0.8, green: 0.8, blue: 0.3, alpha: 1); c.fill(CGRect(x: 38, y: y, width: 29, height: 55))
            }
            avatar(300)  // the page: white, a portrait, rows of small print
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); c.fill(CGRect(x: 84, y: 300, width: 170, height: 250))
            c.setFillColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1); c.fill(CGRect(x: 95, y: 330, width: 30, height: 40))
            for k in 0..<20 { c.fill(CGRect(x: 95, y: 390 + CGFloat(k) * 7, width: 140, height: 2)) }
            avatar(700)  // a bubble of words
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1); c.fill(CGRect(x: 84, y: 700, width: 200, height: 140))
        }
        let px = try XCTUnwrap(WatchOCR.Pixels(jpeg))
        let words = (0..<5).map { WatchOCR.Piece(text: "一行聊天的字", box: CGRect(x: 0.2, y: 0.612 + Double($0) * 0.024, width: 0.3, height: 0.02), kind: .theirs) }
        let blocks = F.pictureBlocks(px, pieces: words, top: 0.09, bottom: 0.93)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(Double(blocks.first?.minX ?? 0), 0.175, accuracy: 0.02, "past the avatar's edge, not on it")
        XCTAssertEqual(Double(blocks.first?.minY ?? 0), 0.26, accuracy: 0.02)
    }

    /// B28: a file card's size under its name is the card's line.
    func testAFileCardsSizeIsTheCardsLine() {
        XCTAssertTrue(F.fileSizeLine("486KB 未下载"))
        XCTAssertTrue(F.fileSizeLine("15K"))
        XCTAssertFalse(F.fileSizeLine("486元"))
        let pieces = [WatchOCR.Piece(text: "6原生家庭创伤治愈.docx", box: CGRect(x: 0.2, y: 0.5, width: 0.3, height: 0.022), kind: .theirs),
                      WatchOCR.Piece(text: "12KB未下载", box: CGRect(x: 0.2, y: 0.545, width: 0.15, height: 0.016), kind: .theirs)]
        XCTAssertEqual(WatchOCR.lines(pieces, title: "蓝海乐").lines.count, 1)
    }

    /// B30: someone's recall is a line; mine is not.
    func testSomeonesRecallIsALine() {
        XCTAssertEqual(F.recaller("\"主人蓝海乐\" 撤回了一条消息"), "主人蓝海乐")
        XCTAssertEqual(F.recaller("主人蓝海乐撤回了一条消息"), "主人蓝海乐")
        XCTAssertNil(F.recaller("你撤回了一条消息 重新编辑"))
        XCTAssertNil(F.recaller("17:35"))
        let grey = WatchOCR.Piece(text: "\"主人蓝海乐\" 撤回了一条消息", box: CGRect(x: 0.3, y: 0.5, width: 0.4, height: 0.018), kind: .grey)
        XCTAssertEqual(WatchOCR.lines([grey], title: "测试群(3)").lines.map { $0.text }, [F.recallLine("主人蓝海乐")])
    }

    /// O1: the owner's name in a group means the owner only where the other app has been in that group too.
    func testTheOwnersNameOnlyInAGroupBothAccountsAreIn() {
        XCTAssertTrue(XiaoLanSelf.sharedGroup("企微测试群", app: .wework, chats: ["wechat|企微测试群", "wework|企微测试群"]))
        XCTAssertFalse(XiaoLanSelf.sharedGroup("企微测试群", app: .wework, chats: ["wework|企微测试群", "wechat|家人群"]))
    }

    /// B26: Echo's own window, as OCR reads its pages, is told from an app's page that is no chat or list.
    func testEchosOwnWindowIsKnown() {
        XCTAssertTrue(XiaoLanPanes.echoWindow([[p("微信守候", 0.2)], [p("守候设定", 0.3)]]))
        XCTAssertFalse(XiaoLanPanes.echoWindow([[p("实名认证", 0.2)], [p("请上传身份证", 0.3)]]))
    }

    /// The model is told which app it looks in (the iPad's bar names both).
    func testTheAppIsSaid() {
        XCTAssertTrue(F.appSaid(.wechat).contains("不是企业微信"))
        XCTAssertTrue(F.appSaid(.wework).contains("企业微信"))
    }
}
