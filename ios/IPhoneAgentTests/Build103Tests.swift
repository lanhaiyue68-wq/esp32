import XCTest
import UIKit
@testable import IPhoneAgent

/// The closed loop's eye: where the pointer arrived, from the frame before a move and the frame after it.
/// Frames like the test phone's direct capture (592x1280, JPEG 0.72); the pointer a translucent grey disk, radius 15 px.
final class Build103Tests: XCTestCase {
    private let size = CGSize(width: 592, height: 1280)

    /// A busy screen (dark sheet, an orange button, text, a list), the pointer drawn at each of `pointers`.
    private func frame(pointers: [CGPoint], shiftContent: Bool = false) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.11, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 1, green: 0.58, blue: 0.2, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 497, y: 104, width: 68, height: 68))  // a ✓ button, top right
            let dy: CGFloat = shiftContent ? 40 : 0
            for i in 0..<8 {
                ("第 \(i) 行 加入鬧鐘 上午 8:00" as NSString).draw(at: CGPoint(x: 40, y: 300 + CGFloat(i) * 110 + dy),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.white])
            }
            UIColor(white: 0.5, alpha: 0.55).setFill()
            for p in pointers {
                ctx.cgContext.fillEllipse(in: CGRect(x: p.x * size.width - 15, y: p.y * size.height - 15, width: 30, height: 30))
            }
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.72))
    }

    func testThePointerIsFoundWhereItArrivedOverAnyContent() throws {
        let left = CGPoint(x: 0.3, y: 0.7)
        for target in [CGPoint(x: 0.889, y: 0.135),   // half over the ✓ button (the live test)
                       CGPoint(x: 0.55, y: 0.26),     // over a line of text
                       CGPoint(x: 0.5, y: 0.5)] {
            let before = try frame(pointers: [left]), after = try frame(pointers: [target])
            let seen = try XCTUnwrap(Vision.arrival(before, after, near: CGPoint(x: target.x + 0.03, y: target.y - 0.03)),
                                     "pointer at \(target) not found")
            XCTAssertEqual(seen.x, target.x, accuracy: 0.006, "\(target)")
            XCTAssertEqual(seen.y, target.y, accuracy: 0.006, "\(target)")
        }
    }

    func testAPointerAgainstTheRightEdgeIsFoundToo() throws {
        let target = CGPoint(x: 0.985, y: 0.4)
        let seen = try XCTUnwrap(Vision.arrival(try frame(pointers: []), try frame(pointers: [target]), near: CGPoint(x: 0.95, y: 0.4)))
        XCTAssertEqual(seen.y, 0.4, accuracy: 0.006)
        XCTAssertGreaterThan(seen.x, 0.96)
    }

    func testThePointerItLeftIsNotTakenForWhereItArrived() throws {
        let from = CGPoint(x: 0.6, y: 0.45), to = CGPoint(x: 0.75, y: 0.5)  // close: both disks inside the search window
        let seen = try XCTUnwrap(Vision.arrival(try frame(pointers: [from]), try frame(pointers: [to]), near: CGPoint(x: 0.76, y: 0.52)))
        XCTAssertEqual(seen.x, to.x, accuracy: 0.006)
        XCTAssertEqual(seen.y, to.y, accuracy: 0.006)
    }

    func testAScreenThatChangedAroundTheSpotGivesNothing() throws {
        let target = CGPoint(x: 0.4, y: 0.33)
        let before = try frame(pointers: []), after = try frame(pointers: [target], shiftContent: true)
        XCTAssertNil(Vision.arrival(before, after, near: target), "the text moved under it: no clean disk, click at the estimate")
    }
}
