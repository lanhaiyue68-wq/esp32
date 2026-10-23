import XCTest
import UIKit
@testable import IPhoneAgent

/// logs(14): smileys "drawn" with no pen selected were taken as done; the owner task found the group owner and lost it
/// on the way back to the chat; a private chat needed an @.
@MainActor final class InkAndQuickTests: XCTestCase {
    private let size = CGSize(width: 390, height: 844)

    private func screen(_ draw: (CGContext) -> Void) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            draw(ctx.cgContext)
        }.jpegData(compressionQuality: 0.9)!
    }

    private func dots(offset: CGFloat) -> (CGContext) -> Void {
        { cg in
            cg.setFillColor(UIColor(white: 0.8, alpha: 1).cgColor)
            for x in stride(from: offset, to: 390, by: 20) { for y in stride(from: offset, to: 844, by: 20) {
                cg.fillEllipse(in: CGRect(x: x, y: y, width: 3, height: 3))
            } }
        }
    }

    func testAStrokeCountsOnlyWhenALineShowsWhereItWasDrawn() {
        let aspect = Double(size.width / size.height)
        let stroke = circle(0.5, 0.5, 0.3, aspect: aspect, n: 36)
        let before = screen(dots(offset: 4))
        let drawn = screen { cg in
            self.dots(offset: 4)(cg)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(4)
            let r = 0.3 * self.size.width
            cg.strokeEllipse(in: CGRect(x: self.size.width / 2 - r, y: self.size.height / 2 - r, width: 2 * r, height: 2 * r))
        }
        let panned = screen(dots(offset: 14))  // no pen: the drag only moved the dotted canvas
        XCTAssertGreaterThan(AgentLoop.inkShare(before: before, after: drawn, stroke: stroke) ?? 0, 0.6)
        XCTAssertLessThan(AgentLoop.inkShare(before: before, after: panned, stroke: stroke) ?? 1, 0.25)
        XCTAssertLessThan(AgentLoop.inkShare(before: drawn, after: drawn, stroke: stroke) ?? 1, 0.25)  // an old drawing is not new ink
    }

    func testATapThatPickedNoPenIsTheOneBeforeTheBlankStroke() {
        // traces(44): tap the New Board button, draw, no line; again and again.
        let tap: JObject = ["action": .str("tap"), "x": .num(856), "y": .num(938)]
        let stroke: JObject = ["action": .str("circle"), "x": .num(400), "y": .num(475), "r": .num(120)]
        let noInk: JObject = ["action": .str("no ink")]
        XCTAssertEqual(AgentLoop.tapBeforeStroke([tap, stroke]), tap)
        XCTAssertNil(AgentLoop.tapBeforeStroke([tap, stroke, noInk, stroke]))  // no new try between two blank strokes
        XCTAssertTrue(AgentLoop.noInkReason.contains("New Board"))
        XCTAssertTrue(AgentLoop.deadTapReason.contains("different button"))
    }

    func testSelfLearnedFreeformPenLessonsAreTheOnesDropped() {
        XCTAssertTrue(LessonBook.aboutFreeformPen("无边记画布：先点击底部工具栏的铅笔按钮打开工具面板"))
        XCTAssertTrue(LessonBook.aboutFreeformPen("Freeform board: tap the bottom-right pencil icon"))
        XCTAssertFalse(LessonBook.aboutFreeformPen("微信聊天列表：直接点击目标会话"))
    }

    func testTheOwnerTaskAnswerIsWhatToSend() {
        XCTAssertEqual(WatchReport.sendAnswer(#"{"send":"群主是蓝海乐"}"#), "群主是蓝海乐")
        XCTAssertEqual(WatchReport.sendAnswer(#"已完成 {"send":""}"#), "")
        XCTAssertNil(WatchReport.sendAnswer("Tapped the owner and @ed him"))
        XCTAssertTrue(WatchSettings.ownerTask(chat: "测试群", task: "找出群主").contains(#"{"send":"群主是蓝海乐"}"#))
    }

    func testAWhitelistedPrivateMessageNeedsNoAt() {
        var r = WatchSettings.Rules()
        r.senders = ["蓝海乐"]
        r.myNames = ["蓝"]
        XCTAssertTrue(WatchSettings.fires(ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "帮我看看群主是谁"), r))
        XCTAssertFalse(WatchSettings.fires(ReadMessage(chat: "路人甲", group: false, sender: "路人甲", text: "在吗"), r))
        XCTAssertFalse(WatchSettings.fires(ReadMessage(chat: "测试群", group: true, sender: "蓝海乐", text: "帮我看看"), r))
    }
}
