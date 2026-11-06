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

    // logs 11-06 (build89): Claude sat between WeChat and Lan Agent; the reversed swipes stopped in Claude.
    func testReopeningTheSourceAppReturnsThereWhateverTheAppOrder() async {
        let phone = PasteApps(["Lan Agent", "Claude", "WeChat"], at: 2)
        phone.restoreWrongApp = true  // reversing the swipes would not reach WeChat
        let result = await phone.paste("收到，我去处理。", reopen: true)
        XCTAssertEqual(result, .filled)
        XCTAssertEqual(phone.current, "WeChat")
        XCTAssertEqual(phone.visited, ["Claude", "Lan Agent", "WeChat"], "one direct return, no reverse swipes")
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

    func testMissingOrUnreadableFramesCannotVerifyTheDestination() {
        XCTAssertFalse(PasteRoundTrip.matchesSource(Data(), labelledScreen("CLAUDE")))
        XCTAssertFalse(PasteRoundTrip.matchesSource(labelledScreen("CLAUDE"), Data()))
    }

    func testInputFieldChangesDoNotHideTheSameVerifiedConversation() {
        XCTAssertTrue(PasteRoundTrip.matchesSource(conversation(input: "nihao"), conversation(input: "")))
    }

    // logs 11-06: the back button's unread count went 321 → 322 while Lan Agent filled the clipboard.
    func testANewUnreadCountOnTheBackButtonStillVerifiesTheSameConversation() {
        XCTAssertTrue(PasteRoundTrip.matchesSource(conversation(input: "", badge: "321"),
                                                   conversation(input: "", badge: "322")))
    }

    // logs 11-06: a WeChat banner for another group covered the title. That frame cannot verify; the hop looks again.
    func testAFrameWithABannerOverTheTitleIsNotTakenAsTheTarget() {
        XCTAssertFalse(PasteRoundTrip.matchesSource(conversation(input: ""), conversation(input: "", banner: true)))
    }

    func testAnotherConversationWithTheSameMessageIsStillRefused() {
        XCTAssertFalse(PasteRoundTrip.matchesSource(conversation(input: ""),
                                                    conversation(input: "", title: "SOMEONE ELSE")))
    }

    private func conversation(input: String, title: String = "WECHAT OWNER", badge: String? = nil,
                              banner: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let white: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white]
        return UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            if let badge { (badge as NSString).draw(at: CGPoint(x: 20, y: 170), withAttributes: white) }
            for (text, y) in [(title, 170.0), ("HELLO THERE", 350.0), (input, 825.0)] {
                (text as NSString).draw(at: CGPoint(x: badge == nil ? 80 : 300, y: y), withAttributes: white)
            }
            if banner {
                UIColor(white: 0.85, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 16, y: 24, width: 688, height: 200), cornerRadius: 36).fill()
                ("OTHER GROUP NEW PHOTO" as NSString).draw(at: CGPoint(x: 60, y: 100),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
            }
        }.jpegData(compressionQuality: 0.9)!
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

    func paste(_ text: String, reopen: Bool = false) async -> PasteHopResult {
        let source = current
        let reopenSource: (() async throws -> Void)? = reopen ? {
            self.index = self.apps.firstIndex(of: source) ?? self.index
            self.visited.append(self.current)
        } : nil
        return await PasteRoundTrip.perform(text, isActive: { self.current == "Lan Agent" }, previousApp: {
            self.index = max(0, self.index - 1); self.visited.append(self.current)
        }, nextApp: {
            self.index = self.restoreWrongApp ? 0 : min(self.apps.count - 1, self.index + 1)
            self.visited.append(self.current)
        }, waitForAgent: { self.current == "Lan Agent" }, put: { text in
            guard self.current == "Lan Agent", self.allowClipboard else { return false }
            self.clipboard = text
            return true
        }, verifySource: { self.current == source && self.current != "Lan Agent" }, reopenSource: reopenSource)
    }
}
