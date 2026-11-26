import XCTest
import UIKit
@testable import IPhoneAgent

/// 185 (Echo 184 on the customer's iPad, 11-26, 辅助触控 on): calibration failed every time ("粗校准落点无有效跨度"):
/// the rough probes were 600 / 1200 units whatever the pointer's speed, and the home's place and the edge gate's span
/// disagreed; 辅助触控's button had been moved, so a fixed spot for it was wrong.
@MainActor final class Build185Tests: XCTestCase {
    func frame(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 960, height: 1280), format: format).jpegData(withCompressionQuality: 0.95) { r in
            r.cgContext.setFillColor(red: 242 / 255, green: 241 / 255, blue: 247 / 255, alpha: 1)  // a plain page
            r.cgContext.fill(CGRect(x: 0, y: 0, width: 960, height: 1280))
            draw(r.cgContext)
        }
    }
    func grey(_ c: CGContext, _ v: CGFloat) { c.setFillColor(red: v / 255, green: v / 255, blue: (v + 5) / 255, alpha: 1) }
    /// 辅助触控's button as it looked on Echo's page (11-26): a grey rounded square, a lighter ring, a lighter disk.
    func button(_ c: CGContext, _ x: CGFloat, _ y: CGFloat, disk: Bool = true) {
        grey(c, 163)
        c.addPath(UIBezierPath(roundedRect: CGRect(x: x - 44, y: y - 44, width: 88, height: 88), cornerRadius: 20).cgPath)
        c.fillPath()
        guard disk else { return }
        grey(c, 177)
        c.fillEllipse(in: CGRect(x: x - 26, y: y - 26, width: 52, height: 52))
        grey(c, 199)
        c.fillEllipse(in: CGRect(x: x - 17, y: y - 17, width: 34, height: 34))
    }

    /// 11-26: the probes were where 600 / 1200 units went at 11-25's speed; now shares of the screen measured.
    func testRoughProbesAsSharesOfTheScreen() {
        let pad = AutoCalibrator.roughPoints(pad: true, span: (w: 547, h: 624))
        XCTAssertEqual(pad.map { $0.0 }, [170, 339])
        XCTAssertEqual(pad.map { $0.1 }, [156, 318])
        let old = AutoCalibrator.roughPoints(pad: true, span: (w: 1934, h: 2357))  // 11-25's speed: as before
        XCTAssertEqual(Double(old[0].0), 600, accuracy: 3)
        XCTAssertEqual(Double(old[1].0), 1200, accuracy: 3)
        XCTAssertEqual(AutoCalibrator.roughPoints(pad: false, span: (w: 547, h: 624)).map { $0.0 }, AutoCalibrator.roughStops)
    }

    /// 11-26: the owner moved the button from the bottom's middle to the bottom-right corner: found where it is.
    func testAssistiveTouchButtonFound() throws {
        let px = try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 620, 1234) }))
        let p = try XCTUnwrap(XiaoLanRecall.assistiveTouchButton(px))
        XCTAssertEqual(Double(p.x) * 960, 620, accuracy: 8)
        XCTAssertEqual(Double(p.y) * 1280, 1234, accuracy: 8)
        let corner = try XCTUnwrap(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 912, 1226) }))))
        XCTAssertEqual(Double(corner.x) * 960, 912, accuracy: 8)
        XCTAssertEqual(Double(corner.y) * 1280, 1226, accuracy: 8)
        // not by an edge (iOS keeps the button there), no lighter disk, a white dot: nothing is clicked
        XCTAssertNil(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 480, 640) }))))
        XCTAssertNil(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { self.button($0, 620, 1234, disk: false) }))))
        XCTAssertNil(XiaoLanRecall.assistiveTouchButton(try XCTUnwrap(WatchOCR.Pixels(frame { c in
            c.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            c.fillEllipse(in: CGRect(x: 600, y: 1210, width: 50, height: 50))
        }))))
    }
}
