import UIKit
import XCTest
@testable import IPhoneAgent

@MainActor final class PasteRoundTripTests: XCTestCase {
    func testPasteReturnsToClaudeInsteadOfOpeningWeChat() async {
        let phone = PasteApps(["Lan Agent", "Claude"], at: 1)
        let result = await phone.paste("你好")
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(phone.current, "Claude")
        XCTAssertEqual(phone.clipboard, "你好")
        XCTAssertEqual(phone.visited, ["Lan Agent", "Claude"])
    }

    func testTwoSwitchesAreReversedBeforeAnyPasteIsAllowed() async {
        let phone = PasteApps(["Lan Agent", "WeChat", "Claude"], at: 2)
        let result = await phone.paste("你好")
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(phone.current, "Claude")
        XCTAssertEqual(phone.visited, ["WeChat", "Lan Agent", "WeChat", "Claude"])
    }

    func testWrongReturnScreenIsLostEvenWhenTheClipboardWasFilled() async {
        let phone = PasteApps(["Lan Agent", "Claude"], at: 1)
        phone.restoreWrongApp = true
        let result = await phone.paste("你好")
        XCTAssertEqual(result, .lost)
        XCTAssertNotEqual(phone.current, "Claude")
    }

    func testARefusedClipboardStillRestoresTheTargetBeforeReturning() async {
        let phone = PasteApps(["Lan Agent", "Claude"], at: 1)
        phone.allowClipboard = false
        let result = await phone.paste("你好")
        XCTAssertEqual(result, .refused)
        XCTAssertEqual(phone.current, "Claude")
        XCTAssertNil(phone.clipboard)
    }

    func testFailureToFindLanAgentNeverWritesTheClipboard() async {
        let phone = PasteApps(["WeChat", "Claude"], at: 1)
        let result = await phone.paste("你好")
        XCTAssertEqual(result, .lost)
        XCTAssertNil(phone.clipboard)
        XCTAssertLessThanOrEqual(phone.visited.count, 2)
    }

    func testAnUnexpectedForegroundAgentCannotPretendToRestoreATarget() async {
        let phone = PasteApps(["Lan Agent", "Claude"], at: 0)
        let result = await phone.paste("你好")
        XCTAssertEqual(result, .lost)
        XCTAssertNil(phone.clipboard)
        XCTAssertTrue(phone.visited.isEmpty)
    }

    func testTheSameTargetScreenCanBeVerified() {
        let screen = labelledScreen("CLAUDE")
        XCTAssertTrue(PasteRoundTrip.matchesSource(screen, screen))
    }

    func testASimilarDarkScreenInAnotherAppCannotBeVerified() {
        XCTAssertFalse(PasteRoundTrip.matchesSource(labelledScreen("CLAUDE"), labelledScreen("WECHAT")))
    }

    private func labelledScreen(_ title: String) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            (title as NSString).draw(at: CGPoint(x: 80, y: 170),
                                    withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }.jpegData(compressionQuality: 0.9)!
    }
}

/// Only iOS app switches and its foreground-only pasteboard are simulated; the round-trip policy is real code.
@MainActor private final class PasteApps {
    let apps: [String]
    var index: Int
    var clipboard: String?
    var visited: [String] = []
    var allowClipboard = true
    var restoreWrongApp = false
    var current: String { apps[index] }

    init(_ apps: [String], at index: Int) { self.apps = apps; self.index = index }

    func paste(_ text: String) async -> PasteHopResult {
        let source = current
        return await PasteRoundTrip.perform(text, isActive: { self.current == "Lan Agent" }, previousApp: {
            self.index = max(0, self.index - 1); self.visited.append(self.current)
        }, nextApp: {
            self.index = self.restoreWrongApp ? 0 : min(self.apps.count - 1, self.index + 1)
            self.visited.append(self.current)
        }, waitForAgent: { self.current == "Lan Agent" }, put: { text in
            guard self.current == "Lan Agent", self.allowClipboard else { return false }
            self.clipboard = text
            return true
        }, verifySource: { self.current == source && self.current != "Lan Agent" })
    }
}
