import XCTest
import UIKit
@testable import IPhoneAgent

/// 186 (Echo 185 on the customer's iPad, 11-26): sends that went out reported failed (B24), WeCom's quick bar clicked for
/// the field (B25), a row's drag that opened the chat instead of sliding it (B31), 简体拼音's 123 page not seen as a
/// keyboard (B27), and the user's rule that a WeCom group is WeCom's to answer.
@MainActor final class Build186Tests: XCTestCase {
    func piece(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.02) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: text, box: CGRect(x: x, y: y, width: w, height: h))
    }

    /// B31: the press and a quick eased stroke left, all of it, no step backwards, a small arc.
    func testRowSwipeIsOneQuickStrokeLeft() {
        let steps = Pointer.rowSwipeSteps(900, jitter: { 1 }, wobble: { 0 })
        XCTAssertEqual(steps.count, 8)
        XCTAssertEqual(steps.reduce(0) { $0 + $1.dx }, -900)
        XCTAssertTrue(steps.allSatisfy { $0.dx < 0 })
        XCTAssertGreaterThan(abs(steps[2].dx), abs(steps[7].dx))  // slowing at the end
        XCTAssertTrue(steps.allSatisfy { abs($0.dy) <= 3 })
        XCTAssertTrue(Pointer.rowSwipeSteps(10).allSatisfy { $0.dx <= -1 })
    }

    /// B24: the list's preview of the chat shows the line just sent (its end, or its beginning cut short).
    func testPreviewShowsTheLineSent() {
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("【小蓝测试】185 个微 0005", "【小蓝测试】185 个微 0005"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("185测试 个微第4次 2100", "185测试 个微第4次 2100"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("【小蓝测试】185 个微 0004 长消息：这一条故…",
                                                   "【小蓝测试】185 个微 0004 长消息：这一条故意写得比较长，用来看守候会不会"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("范兆磊: 185测试 企微第4次 2140", "185测试 企微第4次 2140"))
        XCTAssertFalse(XiaoLanSelf.previewShowsSent("「主人蓝海乐」已回收一則訊息", "185测试 个微第5次"))
        XCTAssertFalse(XiaoLanSelf.previewShowsSent("主人蓝海乐: 你好", "你好呀我在呢"))
        XCTAssertFalse(XiaoLanSelf.previewShowsSent("[草稿]185测试 个微第6次", "185测试 个微第6次"))
    }

    /// B24: the preview read under the chat's row on the list.
    func testPreviewTextUnderTheRow() {
        let rows = [[piece("测试群", x: 0.22, y: 0.30)], [piece("185测试 个微第4次 2100", x: 0.22, y: 0.33, w: 0.4)],
                    [piece("主人蓝海乐", x: 0.22, y: 0.38)], [piece("[语音] 6\"", x: 0.22, y: 0.41)]]
        XCTAssertEqual(XiaoLanPanes.previewText(rows, of: "测试群"), "185测试 个微第4次 2100")
        XCTAssertEqual(XiaoLanPanes.previewText(rows, of: "主人蓝海乐"), "[语音] 6\"")
        XCTAssertNil(XiaoLanPanes.previewText(rows, of: "文件传输助手"))
    }

    /// B25: WeCom's quick bar read in a window; the field is under it.
    func testQuickBarBottom() throws {
        let bar = [[piece("山企业名片", x: 0.05, y: 0.900, w: 0.2), piece("¥发起收款", x: 0.30, y: 0.900, w: 0.2),
                    piece("快捷回复", x: 0.55, y: 0.901, w: 0.2)], [piece("发消息或按住…", x: 0.15, y: 0.95, w: 0.4)]]
        XCTAssertEqual(try XCTUnwrap(XiaoLanPanes.quickBarBottom(bar)), 0.921, accuracy: 0.0001)
        XCTAssertNil(XiaoLanPanes.quickBarBottom([[piece("发消息或按住…", x: 0.15, y: 0.95)]]))
    }

    /// B27: a row of one-digit keys is a keyboard; lines of one digit each in a chat are not.
    func testDigitKeysAreAKeyboard() throws {
        let keys = [(0..<10).map { piece(String(($0 + 1) % 10), x: 0.02 + CGFloat($0) * 0.095, y: 0.78, w: 0.03) },
                    ["@", "#", "¥", "/", "(", ")"].enumerated().map { piece($1, x: 0.05 + CGFloat($0) * 0.1, y: 0.84, w: 0.03) }]
        XCTAssertEqual(try XCTUnwrap(XiaoLanPanes.keyboardTop(keys)), 0.78, accuracy: 0.0001)
        let chat = (1...5).map { [piece("\($0)", x: 0.2, y: 0.5 + CGFloat($0) * 0.06, w: 0.03)] }
        XCTAssertNil(XiaoLanPanes.keyboardTop(chat))
    }

    /// The user's rule (11-26): a WeCom group seen from WeChat, told by the logo after its title.
    func testWeComGroupTitle() {
        XCTAssertTrue(XiaoLanPanes.weComGroupTitle("企微测试群（7）Q"))
        XCTAssertTrue(XiaoLanPanes.weComGroupTitle("企微测试群（7）0"))
        XCTAssertFalse(XiaoLanPanes.weComGroupTitle("测试群(6)"))
        XCTAssertFalse(XiaoLanPanes.weComGroupTitle("主人蓝海乐"))
        XCTAssertFalse(XiaoLanPanes.weComGroupTitle("Q不存在群185"))
    }
}
