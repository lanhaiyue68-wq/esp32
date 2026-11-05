import UIKit
import XCTest
@testable import IPhoneAgent

/// logs46, at night: the phone was in the dark appearance. The keyboard was up, but text recognition read none of
/// its single letters, so typing was refused twice and the reply went through the paste hop, which lost its way.
/// A Claude task that had to bring Claude's reply back was held after its first send and failed.
@MainActor final class Logs46RegressionTests: XCTestCase {
    private func render(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 592, height: 1280), format: format)
            .jpegData(withCompressionQuality: 0.7) { draw($0.cgContext) }
    }

    private func box(_ c: CGContext, _ gray: Double, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        c.setFillColor(gray: gray, alpha: 1)
        c.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: 6, cornerHeight: 6, transform: nil))
        c.fillPath()
    }

    /// The pinyin QWERTY keyboard as the logs46 frames show it (592 x 1280): letters on every key.
    private func keyboard(dark: Bool) -> Data {
        render { c in
            let key = dark ? 0.29 : 1.0, glyph = dark ? 1.0 : 0.0
            box(c, dark ? 0.08 : 0.95, 0, 0, 592, 1280)
            box(c, dark ? 0.11 : 0.82, 0, 745, 592, 535)
            for (row, (count, x0)) in [(10, 12.0), (9, 41.0), (7, 98.0)].enumerated() {
                let y = 832 + Double(row) * 88
                for i in 0..<count {
                    let x = x0 + Double(i) * 58.6
                    box(c, key, x, y, 48, 66)
                    box(c, glyph, x + 18, y + 22, 12, 22)
                }
            }
            box(c, key, 12, 1008, 64, 66); box(c, key, 516, 1008, 64, 66)
            box(c, key, 12, 1096, 60, 66); box(c, key, 84, 1096, 60, 66); box(c, key, 156, 1096, 280, 66); box(c, key, 446, 1096, 134, 66)
        }
    }

    func testTheKeyboardIsSeenInTheDarkAppearance() {
        XCTAssertTrue(Vision.letterKeyboard(keyboard(dark: true)))
        XCTAssertTrue(CandidatePicker.keyboardUp(in: keyboard(dark: true)))
    }

    func testTheKeyboardIsSeenInTheLightAppearance() {
        XCTAssertTrue(Vision.letterKeyboard(keyboard(dark: false)))
    }

    func testIconGridsAndPlainScreensAreNoKeyboard() {
        let home = render { c in
            box(c, 0.5, 0, 0, 592, 1280)
            for row in 0..<6 { for col in 0..<4 { box(c, 0.9, 40 + Double(col) * 138, 100 + Double(row) * 150, 100, 100) } }
            for col in 0..<4 { box(c, 0.9, 40 + Double(col) * 138, 1140, 100, 100) }
        }
        XCTAssertFalse(Vision.letterKeyboard(home))
        for dark in [true, false] {
            let chat = render { c in
                box(c, dark ? 0.08 : 0.95, 0, 0, 592, 1280)
                box(c, dark ? 0.2 : 1.0, 76, 1180, 376, 60)  // the input box, no keyboard
            }
            XCTAssertFalse(Vision.letterKeyboard(chat))
        }
    }

    func testBringingAReplyBackIsAPartAfterTheSend() {
        XCTAssertTrue(WatchSettings.severalParts("去 claude 说一句你好，并把 claude 回复的内容发给我"))
        XCTAssertTrue(WatchSettings.severalParts("问问 ChatGPT 今天几号，告诉我"))
        XCTAssertFalse(WatchSettings.severalParts("去测试群@一下群主"))
        let prompt = WatchSettings.ownerTask(chat: "蓝海乐", task: "去 claude 说一句你好，并把 claude 回复的内容发给我", phone: true)
        XCTAssertTrue(prompt.contains("把内容原文写进答案"))
        XCTAssertTrue(prompt.contains("不要切回微信"))
    }
}
