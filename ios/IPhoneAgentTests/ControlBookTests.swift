import UIKit
import XCTest
@testable import IPhoneAgent

/// Learned buttons (ControlBook): a control is remembered by its look where it worked and found again by it.
@MainActor final class ControlBookTests: XCTestCase {
    // logs 11-06: Claude's 发送 sits at the right end of the input bar, which moves with the keyboard and the text.
    func testALearnedSendButtonIsFoundByItsLookWhereverTheInputBarMoved() throws {
        let book = ControlBook(file: nil)
        book.learn("send", at: CGPoint(x: 0.908, y: 0.543), on: Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO"))
        XCTAssertEqual(book.count, 1)
        let hit = try XCTUnwrap(book.find("send", in: Self.screen(button: CGPoint(x: 0.908, y: 0.47), text: "ANOTHER CHAT")))
        XCTAssertEqual(Double(hit.point.x), 0.908, accuracy: 0.02)
        XCTAssertEqual(Double(hit.point.y), 0.47, accuracy: 0.02)
    }

    func testAScreenWithoutTheButtonFindsNothing() {
        let book = ControlBook(file: nil)
        book.learn("send", at: CGPoint(x: 0.908, y: 0.543), on: Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO"))
        XCTAssertNil(book.find("send", in: Self.screen(button: nil, text: "HELLO")))
        XCTAssertNil(book.find("back", in: Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO")), "another role")
    }

    func testAPlainSpotIsNotLearned() {
        let book = ControlBook(file: nil)
        book.learn("send", at: CGPoint(x: 0.5, y: 0.3), on: Self.screen(button: nil, text: ""))
        XCTAssertEqual(book.count, 0)
    }

    func testTheSameButtonAgainIsCreditedNotDuplicated() {
        let book = ControlBook(file: nil)
        let frame = Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO")
        book.learn("send", at: CGPoint(x: 0.908, y: 0.543), on: frame)
        book.learn("send", at: CGPoint(x: 0.905, y: 0.545), on: frame)
        XCTAssertEqual(book.count, 1)
        XCTAssertEqual(book.controls.first?.worked, 2)
    }

    func testASpotThatKeepsDoingNothingIsForgotten() throws {
        let book = ControlBook(file: nil)
        book.learn("send", at: CGPoint(x: 0.908, y: 0.543), on: Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO"))
        let id = try XCTUnwrap(book.controls.first?.id)
        book.failed(id)
        XCTAssertEqual(book.count, 1, "one miss against one success is kept")
        book.failed(id)
        XCTAssertEqual(book.count, 0, "failed twice and more often than it worked")
    }

    func testLearnedButtonsSurviveARestart() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        ControlBook(file: file).learn("send", at: CGPoint(x: 0.908, y: 0.543),
                                     on: Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO"))
        XCTAssertEqual(ControlBook(file: file).count, 1)
    }

    // The model guessed a spot near the send button: the tap goes to the learned button.
    func testASendTapNearTheLearnedButtonLandsOnIt() async throws {
        let screen = FakeScreen()
        screen.frame = Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO")
        let book = ControlBook(file: nil)
        book.learn("send", at: CGPoint(x: 0.908, y: 0.543), on: try XCTUnwrap(screen.frame))
        let phone = PointGestures()
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: tap 850 600" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.controls = book
        _ = try await agent.step(); _ = try await agent.step()
        let tap = try XCTUnwrap(phone.points.first)
        XCTAssertEqual(Double(tap.x), 0.908, accuracy: 0.02)
        XCTAssertEqual(Double(tap.y), 0.543, accuracy: 0.02)
    }

    func testWithNothingTypedTheTapIsLeftAlone() async throws {
        let screen = FakeScreen()
        screen.frame = Self.screen(button: CGPoint(x: 0.908, y: 0.543), text: "HELLO")
        let book = ControlBook(file: nil)
        book.learn("send", at: CGPoint(x: 0.908, y: 0.543), on: try XCTUnwrap(screen.frame))
        let phone = PointGestures()
        let actor = FakeModel { _ in "DO: tap 850 600" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.controls = book
        _ = try await agent.step()
        XCTAssertEqual(Double(try XCTUnwrap(phone.points.first).y), 0.6, accuracy: 0.002)
    }

    /// A dark chat screen: text lines at the top, an input bar, and an orange round send button with a white arrow.
    static func screen(button: CGPoint?, text: String) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: 720, height: 1560)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(white: 0.08, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for (i, line) in [text, "GOOD EVENING", "FREE PLAN"].enumerated() where !line.isEmpty {
                (line as NSString).draw(at: CGPoint(x: 80, y: 200 + 120 * Double(i)),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor(white: 0.85, alpha: 1)])
            }
            guard let b = button else { return }
            let c = CGPoint(x: b.x * size.width, y: b.y * size.height)
            UIColor(white: 0.2, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: c.y - 60, width: 672, height: 120), cornerRadius: 40).fill()
            UIColor(red: 0.85, green: 0.45, blue: 0.3, alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: c.x - 34, y: c.y - 34, width: 68, height: 68)).fill()
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: c.x, y: c.y + 18)); arrow.addLine(to: CGPoint(x: c.x, y: c.y - 18))
            arrow.move(to: CGPoint(x: c.x - 14, y: c.y - 4)); arrow.addLine(to: CGPoint(x: c.x, y: c.y - 18))
            arrow.addLine(to: CGPoint(x: c.x + 14, y: c.y - 4))
            arrow.lineWidth = 7; UIColor.white.setStroke(); arrow.stroke()
        }.jpegData(compressionQuality: 0.9)!
    }
}

@MainActor private final class PointGestures: Gestures {
    let device: HIDDevice = FakeDevice()
    var points: [CGPoint] = []
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { points.append(CGPoint(x: x, y: y)) }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func type(_ text: String) async throws {}
    func key(_ combo: String) async throws {}
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
