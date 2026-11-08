import XCTest
@testable import IPhoneAgent

/// Live test 11-08 over USB (build99): the model asked for 时钟 and 无边记 on a Traditional-Chinese phone, and a tap a
/// little low on the alarm's ✓ was clicked again in the same place until the run ran out of steps.
final class Build100Tests: XCTestCase {
    func testAppsAreSearchedByThePhonesOwnName() {
        XCTAssertEqual(AppNames.searchName("时钟", language: "zh-Hant-TW"), "時鐘")
        XCTAssertEqual(AppNames.searchName("无边记", language: "zh-Hant-HK"), "無邊記")
        XCTAssertEqual(AppNames.searchName("设置", language: "zh-Hant-TW"), "設定", "Taiwan's name, not 設置")
        XCTAssertEqual(AppNames.searchName("时钟", language: "zh-Hans-CN"), "时钟")
        XCTAssertEqual(AppNames.searchName("时钟", language: "en-US"), "Clock")
        XCTAssertEqual(AppNames.searchName("時鐘", language: "zh-Hans-CN"), "时钟")
        XCTAssertEqual(AppNames.hant("闹钟"), "鬧鐘", "plain character conversion for names not in the table")
    }

    func testEveryFormOfAnAppsNameIsRecognisedUnderItsIcon() {
        XCTAssertTrue(AppNames.variants("时钟").contains("時鐘"))
        XCTAssertTrue(AppNames.variants("时钟").contains("Clock"))
        XCTAssertTrue(AppNames.variants("Freeform").contains("无边记"))
        XCTAssertEqual(AppNames.variants("微信").first, "微信", "the given name first")
        let rows = [[CandidatePicker.Piece(text: "時鐘", box: CGRect(x: 0.4, y: 0.3, width: 0.1, height: 0.02))]]
        XCTAssertEqual(AppPlaces.label("时钟", in: rows)?.y ?? 0, 0.31, accuracy: 0.001)
        XCTAssertNil(AppPlaces.label("无边记", in: rows))
    }

    func testADeadTapIsTriedAroundItsSpotUpFirst() {
        let nudges = AgentLoop.deadTapNudges
        XCTAssertEqual(nudges.count, 4)
        XCTAssertLessThan(nudges[0].1, 0, "up first: misses near the top landed low")
        for (dx, dy) in nudges { XCTAssertLessThanOrEqual(max(abs(dx), abs(dy)), 0.03, "still the same spot, so the count goes on") }
    }
}
