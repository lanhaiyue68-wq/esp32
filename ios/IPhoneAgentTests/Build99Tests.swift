import XCTest
import UIKit
@testable import IPhoneAgent

/// Moves whose x grows faster past 255 units, like iOS's acceleration beyond the calibrated range in logs(12):
/// 267 units meant for 0.899 landed at 0.975.
@MainActor private final class EdgePhone: HIDDevice {
    var links = 1
    var connected = true
    var at = CGPoint.zero
    var clicks: [CGPoint] = []
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
    func send(_ command: String) async throws -> String {
        if command == "curve" { return "on" }
        if command == "home" { at = .zero }
        if command == "click" { clicks.append(at) }
        let parts = command.split(separator: " ")
        if parts.first == "move", parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]) {
            let run = abs(x) <= 255 ? abs(x) / 300 : 0.85 + (abs(x) - 255) / 150
            at.x = min(max(at.x + (x < 0 ? -run : run), 0), 1)
            at.y = min(max(at.y + y / 650, 0), 1)
        }
        return ""
    }
}

@MainActor final class Build99Tests: XCTestCase {
    private let rules = WatchSettings.Rules(targets: ["测试群", "主人蓝海乐", "蓝海乐"])

    /// The chat list as logs(12) shows it on the user's iPhone 14 Pro Max (592x1280 direct capture, 020.jpg): no
    /// search bar, so the top row's title is at 0.145; previews run to 0.94; Traditional tab labels.
    private func list(badgeOnTop: Bool) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 592, height: 1280), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 592, height: 1280))
            func draw(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: UIColor = .black, width: CGFloat = 0) {
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size), .foregroundColor: color,
                                                                  .paragraphStyle: style]
                if width > 0 { (text as NSString).draw(in: CGRect(x: x, y: y, width: width, height: size * 1.4), withAttributes: attributes) }
                else { (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes) }
            }
            let red = UIColor(red: 0.98, green: 0.32, blue: 0.32, alpha: 1)
            draw("微信 (104)", 236, 98, 24)
            let rows: [(String, String, String)] = [
                ("主人蓝海乐", "9527 你去给我开一个明天早晨8点的闹钟，然后再给我画个太阳，回来再给测试群发个消息", "下午1:31"),
                ("官方賬號", "[1 則通知] 快訊: 最低 17°C！“正经”冷空气要来了，大家注意保暖", "下午1:28"),
                ("小柳", "Lan Agent 輸入法測試：中文直接填入，英文也直接填入，看看能不能一次送出", "凌晨1:47"),
                ("测试群", "你好", "星期五")]
            for (i, row) in rows.enumerated() {
                let top = 167 + CGFloat(i) * 113.5
                UIColor.gray.setFill(); ctx.fill(CGRect(x: 25, y: top, width: 75, height: 75))  // avatar
                draw(row.0, 120, top + 4, 24)
                draw(row.1, 120, top + 44, 19, .gray, width: 432)
                draw(row.2, 488, top + 8, 16, .gray)
            }
            red.setFill()
            if badgeOnTop {
                ctx.cgContext.fillEllipse(in: CGRect(x: 75, y: 157, width: 26, height: 26))  // a red number
                draw("1", 83, 158, 18, .white)
            }
            ctx.cgContext.fillEllipse(in: CGRect(x: 91, y: 277, width: 14, height: 14))  // 官方賬號's dot: not a chat
            ctx.cgContext.fillEllipse(in: CGRect(x: 91, y: 390, width: 14, height: 14))  // 小柳's muted dot
            for (text, x) in [("聊天", 56.0), ("通訊錄", 195.0), ("發現", 352.0), ("我", 509.0)] { draw(text, CGFloat(x), 1190, 18) }
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.72))
    }

    /// Each piece: text, x range, middle y, height and the red share beside it, for a failure on the real recognizer.
    private func describe(_ frame: Data) throws -> String {
        let cg = try XCTUnwrap(Vision.image(frame))
        return CandidatePicker.rows(in: frame, top: 0.055, bottom: 1).flatMap { $0 }.map {
            String(format: "%@@%.3f-%.3f,%.3f h%.4f red%.3f", $0.text, $0.box.minX, $0.box.maxX, $0.box.midY, $0.box.height,
                   Vision.redShare(cg, in: WatchChatOpen.badgeArea($0.box)))
        }.joined(separator: " ")
    }

    func testTheOwnersNewTaskOnTheTopRowWithALongPreviewIsSeen() throws {
        let frame = try list(badgeOnTop: true)
        let pick = WatchChatOpen.unread(in: frame, rules: rules)
        guard case .row(let chat, let point) = pick else {
            let info = (try? describe(frame)) ?? "?"
            return XCTFail("the owner's row has a red number: got \(pick); rows \(info)")
        }
        XCTAssertEqual(chat, "主人蓝海乐")
        XCTAssertEqual(point.y, 0.145, accuracy: 0.015)
    }

    func testAMutedDotOnARowWithALongPreviewIsReadOnlyAndTheOfficialAccountsFolderIsSkipped() throws {
        let frame = try list(badgeOnTop: false)
        let pick = WatchChatOpen.unread(in: frame, rules: rules)
        guard case .other(_, let point) = pick else {
            let info = (try? describe(frame)) ?? "?"
            return XCTFail("小柳 has a red dot: got \(pick); rows \(info)")
        }
        XCTAssertEqual(point.y, 0.322, accuracy: 0.015, "小柳's row, not 官方賬號's above it")
    }

    func testATitleReadTogetherWithItsTimeIsStillTheName() {
        func piece(_ text: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CandidatePicker.Piece {
            .init(text: text, box: CGRect(x: x, y: y, width: w, height: h))
        }
        let rows: [[CandidatePicker.Piece]] = [
            [piece("微信", 0.4, 0.077, 0.2, 0.022)],
            [piece("主人蓝海乐 下午1:31", 0.203, 0.134, 0.75, 0.022)], [piece("9527 你去给我开一个明天早晨8点的闹钟…", 0.203, 0.166, 0.735, 0.017)],
            [piece("聊天", 0.08, 0.93, 0.08, 0.02), piece("通訊錄", 0.33, 0.93, 0.1, 0.02),
             piece("發現", 0.59, 0.93, 0.08, 0.02), piece("我", 0.86, 0.93, 0.04, 0.02)]]
        guard case .row("主人蓝海乐", _) = WatchChatOpen.unread(rows: rows, rules: rules, badge: { _ in true }) else {
            return XCTFail("the time read on the title's line is not part of the name")
        }
        XCTAssertEqual(WatchChatOpen.withoutTime("测试群星期五"), "测试群")
        XCTAssertEqual(WatchChatOpen.withoutTime("蓝海乐昨天"), "蓝海乐")
        XCTAssertEqual(WatchChatOpen.withoutTime("蓝海乐"), "蓝海乐")
        XCTAssertEqual(WatchChatOpen.withoutTime("1:30"), "1:30", "nothing left: keep what was read")
        XCTAssertTrue(WatchReport.sameName("主人监海乐", "主人蓝海乐"))
        XCTAssertFalse(WatchReport.sameName("测验群", "测试群"), "short names must match exactly")
        XCTAssertFalse(WatchReport.sameName("主人蓝海乐", "蓝海乐"))
        XCTAssertFalse(WatchReport.sameName("主人蓝海", "主人蓝海乐"))
    }

    func testPastTheCalibratedRangeTheTapComesBackFromTheRightBorder() async throws {
        let phone = EdgePhone()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: file) }
        let mapX: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 75, "fraction": 0.25],
                                                           ["units": 255, "fraction": 0.85]]]
        let mapY: [String: Any] = ["scatter": 0, "knots": [["units": 0, "fraction": 0], ["units": 130, "fraction": 0.2],
                                                           ["units": 520, "fraction": 0.8], ["units": 650, "fraction": 1]]]
        let saved: [String: Any] = ["w": 300, "h": 650, "quality": 0.01, "stale": false,
            "motionVersion": ProbeMotion.version, "requiresFeedback": false, "maps": ["x": mapX, "y": mapY]]
        try JSONSerialization.data(withJSONObject: saved).write(to: file)
        let p = Pointer(device: phone, calibrationFile: file)
        XCTAssertTrue(p.beyondReach(0.899)); XCTAssertFalse(p.beyondReach(0.7))
        try await p.tap(0.899, 0.111)  // the alarm's ✓
        try await p.tap(0.899, 0.111)  // again, in place
        try await p.tap(0.5, 0.5)      // a hop back into the measured range
        XCTAssertEqual(phone.clicks.count, 3)
        for (hit, spot) in zip(phone.clicks, [(0.899, 0.111), (0.899, 0.111), (0.5, 0.5)]) {
            XCTAssertEqual(hit.x, spot.0, accuracy: 0.01)
            XCTAssertEqual(hit.y, spot.1, accuracy: 0.01)
        }
    }
}
