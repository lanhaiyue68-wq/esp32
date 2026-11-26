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

    /// B32: a preview's beginning counts only when it is cut short with "…".
    func testPreviewBeginningOnlyWhenCut() {
        XCTAssertFalse(XiaoLanSelf.previewShowsSent("【小蓝测试】186个微0018", "【小蓝测试】186 个微 0018 连发2"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("【小蓝测试】186个微0018连发2", "【小蓝测试】186 个微 0018 连发2"))
        XCTAssertTrue(XiaoLanSelf.previewShowsSent("【小蓝测试】186 个微 0004 长消息：这一条故…",
                                                   "【小蓝测试】186 个微 0004 长消息：这一条故意写得比较长"))
    }
}
