import XCTest
@testable import IPhoneAgent

/// logs(31): the report for 蓝海乐 was refused 15 times as "not the chat 蓝海乐" while the title bar read 蓝海乐.
/// The fixture is that frame's title bar (above the messages) on a blank screen of the same size.
@MainActor final class TitleCheckTests: XCTestCase {
    func testTheRealTitleBarFromLogs31IsRecognized() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "logs31-title", withExtension: "jpg"))
        let data = try Data(contentsOf: url)
        let rows = CandidatePicker.rows(in: data, top: 0.055, bottom: 0.135)
        let seen = rows.map { $0.map { String(format: "%@@%.3f,%.3f", $0.text, $0.box.midX, $0.box.midY) }.joined(separator: " ") }
        XCTAssertEqual(WatchReport.navigationChat(in: data, targets: ["蓝海乐"]), "蓝海乐", "OCR rows: \(seen)")
    }
}
