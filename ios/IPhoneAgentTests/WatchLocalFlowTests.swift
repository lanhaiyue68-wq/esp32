import XCTest
import UIKit
@testable import IPhoneAgent

/// logs26: with two listed chats every check opened the chat with an agent run (6–35 s) and every reply was sent
/// by one (15–76 s). The list's red badges and the shared input box let both happen on the phone, checked locally.
@MainActor final class WatchLocalFlowTests: XCTestCase {
    private let rules = WatchSettings.Rules(targets: ["测试群", "张三"])
    private func piece(_ text: String, x: Double = 0.24, y: Double, h: Double = 0.022) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x, y: y, width: 0.22, height: h))
    }
    private func list(_ chats: [(String, Double)]) -> [[CandidatePicker.Piece]] {
        var rows: [[CandidatePicker.Piece]] = [[piece("微信", x: 0.4, y: 0.08)]]
        for (name, y) in chats { rows += [[piece(name, y: y)], [piece("最新消息", y: y + 0.035, h: 0.016)]] }
        return rows + [[piece("微信", x: 0.03, y: 0.94), piece("通讯录", x: 0.28, y: 0.94),
                        piece("发现", x: 0.53, y: 0.94), piece("我", x: 0.78, y: 0.94)]]
    }

    func testTheTopmostBadgedListedChatIsOpened() {
        let rows = list([("测试群", 0.20), ("公众号", 0.29), ("张三", 0.38)])
        let badged: Set<Int> = [Int(0.29 * 1000), Int(0.38 * 1000)]
        let pick = WatchChatOpen.unread(rows: rows, rules: rules, badge: { badged.contains(Int($0.minY * 1000)) })
        guard case .row(let chat, let point) = pick else { return XCTFail("expected a row, got \(pick)") }
        XCTAssertEqual(chat, "张三", "公众号 is badged but not listed")
        XCTAssertEqual(point.y, 0.391, accuracy: 0.002)
    }

    func testNothingUnreadOnlyWhenEveryListedChatIsVisible() {
        XCTAssertEqual(WatchChatOpen.unread(rows: list([("测试群", 0.20), ("张三", 0.29)]), rules: rules, badge: { _ in false }), .none)
        XCTAssertEqual(WatchChatOpen.unread(rows: list([("测试群", 0.20)]), rules: rules, badge: { _ in false }), .unknown,
                       "张三 may be below the screen")
    }

    func testDuplicateNamesAndOtherScreensStayWithTheModel() {
        let twins = list([("测试群", 0.20), ("张三", 0.29), ("张三", 0.38)])  // logs26 had two 蓝海乐
        XCTAssertEqual(WatchChatOpen.unread(rows: twins, rules: rules, badge: { _ in true }), .unknown)
        XCTAssertEqual(WatchChatOpen.unread(rows: Array(list([("测试群", 0.20), ("张三", 0.29)]).dropLast()), rules: rules,
                                            badge: { _ in true }), .unknown, "no tab bar: not the chat list")
        XCTAssertEqual(WatchChatOpen.unread(rows: list([("测试群", 0.20)]), rules: .init(targets: ["测试群"]), badge: { _ in true }),
                       .unknown, "one chat keeps the single-chat path")
    }

    func testNothingUnreadNeedsNoTapAndAListedChatOnScreenIsKept() async {
        let phone = FakeGestures()
        var result = await WatchChatOpen.open(phone: phone, screen: LocalScreen(), rules: rules, canAct: { true },
                                              inspectList: { _ in .none }, title: { _ in nil })
        XCTAssertEqual(result, .nothing)
        result = await WatchChatOpen.open(phone: phone, screen: LocalScreen(), rules: rules, canAct: { true },
                                          inspectList: { _ in .unknown }, title: { _ in "张三" })
        XCTAssertEqual(result, .opened("张三"))
        XCTAssertTrue(phone.calls.isEmpty)
    }

    func testOneTapOnTheBadgedRowMustLandOnThatChat() async {
        let phone = FakeGestures()
        var result = await WatchChatOpen.open(phone: phone, screen: LocalScreen(), rules: rules, canAct: { true },
                                              inspectList: { _ in .row("张三", CGPoint(x: 0.5, y: 0.39)) },
                                              title: { $0 == Data([2]) ? "张三" : nil })
        XCTAssertEqual(result, .opened("张三"))
        result = await WatchChatOpen.open(phone: phone, screen: LocalScreen(), rules: rules, canAct: { true },
                                          inspectList: { _ in .row("张三", CGPoint(x: 0.5, y: 0.39)) },
                                          title: { $0 == Data([2]) ? "测试群" : nil })
        XCTAssertEqual(result, .unverified)
        XCTAssertEqual(phone.calls, ["tap", "tap"])
    }

    func testProductionOCRAndBadgePixelsOnASyntheticList() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat) {
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.white])
            }
            draw("微信", x: 325, y: 120, size: 34)
            draw("测试群", x: 170, y: 310, size: 34); draw("最新消息", x: 170, y: 365, size: 24)
            draw("张三", x: 170, y: 520, size: 34); draw("今天下午见面吗", x: 170, y: 575, size: 24)
            UIColor.gray.setFill(); ctx.fill(CGRect(x: 40, y: 500, width: 92, height: 92))  // avatar
            UIColor(red: 0.98, green: 0.32, blue: 0.32, alpha: 1).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 118, y: 498, width: 24, height: 24))  // its badge
            for (i, text) in ["微信", "通讯录", "发现", "我"].enumerated() { draw(text, x: CGFloat(65 + i * 180), y: 1480, size: 26) }
        }
        let frame = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let rows = CandidatePicker.rows(in: frame, top: 0.055, bottom: 1)
        let seen = rows.map { $0.map { String(format: "%@@%.3f,%.3f", $0.text, $0.box.minX, $0.box.midY) }.joined(separator: " ") }
        let cg = try XCTUnwrap(Vision.image(frame))
        guard case .row(let chat, _) = WatchChatOpen.unread(in: frame, rules: rules) else {
            let all = WatchChatOpen.unread(rows: rows, rules: rules, badge: { _ in true })
            let share = rows.flatMap { $0 }.filter { $0.text.contains("张") }
                .map { Vision.redShare(cg, in: WatchChatOpen.badgeArea($0.box)) }
            return XCTFail("Real Vision must find both titles and the badge next to 张三; rows \(seen); any badge \(all); red \(share)")
        }
        XCTAssertEqual(chat, "张三")
    }

    /// The report's way back: the owner's chat row by its (now unique) remark, on the list only.
    func testTheReportFindsTheOwnersRowOnTheList() {
        let rows = list([("测试群", 0.20), ("主人蓝海乐", 0.29)])
        XCTAssertEqual(WatchChatOpen.row(of: "主人蓝海乐", rows: rows)?.y ?? 0, 0.301, accuracy: 0.002)
        XCTAssertNil(WatchChatOpen.row(of: "张三", rows: list([("张三", 0.20), ("张三", 0.29)])), "a name shown twice")
        XCTAssertNil(WatchChatOpen.row(of: "测试群", rows: Array(rows.dropLast())), "not the chat list")
    }

    func testOnlyAKeyboardDownTapIsKeptAsTheInputBox() {
        XCTAssertTrue(WatchSettings.usableBox(CGPoint(x: 0.45, y: 0.925)))
        XCTAssertFalse(WatchSettings.usableBox(CGPoint(x: 0.45, y: 0.55)), "the box with the keyboard up")
        XCTAssertFalse(WatchSettings.usableBox(CGPoint(x: 0.92, y: 0.925)), "send / + button")
    }
}

@MainActor private final class LocalScreen: ScreenSource {
    var live = true
    var frame: Data? = Data([1])
    var updated = 0.0, capturedAt = 0.0, aspect = 0.46
    func afterAction(since: Double) async { frame = Data([2]) }
    func requireFrame(after: Double?) async throws {}
}
