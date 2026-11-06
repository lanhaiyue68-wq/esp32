import UIKit
import XCTest
@testable import IPhoneAgent

@MainActor final class Logs37RegressionTests: XCTestCase {
    func testSendTapRequiresVisualAimEvenOnItsFirstAttempt() async throws {
        let screen = FakeScreen()
        screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs37Gestures()
        phone.onType = { screen.frame = InputFieldVerificationTests.screen(input: $0, candidate: "我") }
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: tap 908 543" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 5
        _ = try await agent.step(); _ = try await agent.step()
        XCTAssertEqual(phone.aims, [true], "logs37: an acknowledged move overshot into the bottom-right corner")
    }

    // logs 11-06: the dark keyboard hid the pointer, so every tap on its 发送 key was withheld; nothing was ever sent.
    func testATapOnTheKeyboardsReturnKeyPressesReturnWithoutThePointer() async throws {
        let screen = FakeScreen()
        screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs37Gestures()
        phone.onType = { screen.frame = InputFieldVerificationTests.screen(input: $0, candidate: "我") }
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: tap 863 886" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 5
        _ = try await agent.step(); _ = try await agent.step()
        XCTAssertEqual(phone.keys, ["enter"])
        XCTAssertTrue(phone.aims.isEmpty, "the key is pressed, not tapped")
    }

    func testTheSameSpotWithoutAKeyboardIsStillATap() async throws {
        let screen = FakeScreen()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        screen.frame = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            ("PHOTOS" as NSString).draw(at: CGPoint(x: 80, y: 170),
                withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white])
        }.jpegData(compressionQuality: 0.9)!
        let phone = Logs37Gestures()
        let actor = FakeModel { _ in "DO: tap 863 886" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        _ = try await agent.step()
        XCTAssertTrue(phone.keys.isEmpty)
        XCTAssertEqual(phone.aims.count, 1)
    }

    // logs 11-06: "the 主人蓝海乐 row is visible", the tap opened 小柳 and then another group.
    func testAListTapOpensTheTargetChatsRowAsReadOnThePhone() async throws {
        let (agent, phone) = listAgent(tap: "DO: tap 450 580")
        _ = try await agent.step()
        XCTAssertEqual(try XCTUnwrap(phone.points.first).y, 0.225, accuracy: 0.002)
    }

    func testATapOutsideTheListBodyIsNotMoved() async throws {
        let (agent, phone) = listAgent(tap: "DO: tap 450 95")  // the search bar
        _ = try await agent.step()
        XCTAssertEqual(try XCTUnwrap(phone.points.first).y, 0.095, accuracy: 0.002)
    }

    private func listAgent(tap: String) -> (AgentLoop, Logs37Gestures) {
        let screen = FakeScreen()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        screen.frame = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
        }.jpegData(compressionQuality: 0.9)!
        let phone = Logs37Gestures()
        let actor = FakeModel { _ in tap }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.rowTarget = { _ in CGPoint(x: 0.5, y: 0.225) }
        return (agent, phone)
    }

    func testCorrectDraftSurvivingAMissedSendCanRetryWithoutRetyping() async throws {
        let screen = FakeScreen()
        screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs37Gestures()
        phone.onType = { screen.frame = InputFieldVerificationTests.screen(input: $0, candidate: "我") }
        phone.onTap = { n in
            if n == 2 { screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我") }
        }
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: tap 908 543" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 5
        _ = try await agent.step(); _ = try await agent.step()
        XCTAssertTrue(agent.sent.isEmpty, "an unchanged draft is awaiting send, not a sent message")
        _ = try await agent.step()
        XCTAssertEqual(phone.types, ["hello"], "preserve the correct field")
        XCTAssertEqual(phone.aims.count, 2, "a missed first tap must not permanently lock the send")
        XCTAssertEqual(agent.sent, ["hello"])
    }

    func testANewBubbleKeepsSendProtectionEvenIfTheDraftRemainsVisible() async throws {
        let screen = FakeScreen()
        screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs37Gestures()
        phone.onType = { screen.frame = InputFieldVerificationTests.screen(input: $0, candidate: "我") }
        phone.onTap = { _ in
            let draft = InputFieldVerificationTests.screen(input: "hello", candidate: "我")
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            screen.frame = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { _ in
                UIImage(data: draft)!.draw(in: CGRect(x: 0, y: 0, width: 720, height: 1560))
                ("hello" as NSString).draw(at: CGPoint(x: 450, y: 550),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 40), .foregroundColor: UIColor.white])
            }.jpegData(compressionQuality: 0.9)!
        }
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: tap 908 543" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 5
        _ = try await agent.step(); _ = try await agent.step(); _ = try await agent.step()
        XCTAssertEqual(phone.aims.count, 1, "a new matching bubble must prevent a second send")
        XCTAssertEqual(agent.sent, ["hello"])
    }

    func testUnreadablePostSendFrameDoesNotAuthorizeAnotherSend() async throws {
        let screen = FakeScreen()
        screen.frame = InputFieldVerificationTests.screen(input: "", candidate: "我")
        let phone = Logs37Gestures()
        phone.onType = { screen.frame = InputFieldVerificationTests.screen(input: $0, candidate: "我") }
        phone.onTap = { _ in screen.frame = Data([0]) }
        let actor = FakeModel { n in n == 1 ? "DO: type hello" : "DO: tap 908 543" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: actor, trace: nil)
        agent.endAfterSend = 5
        _ = try await agent.step(); _ = try await agent.step(); _ = try await agent.step()
        XCTAssertEqual(phone.aims.count, 1)
        XCTAssertEqual(agent.sent, ["hello"])
    }

    func testAnUnlocatablePointerCannotClickDuringAPrecisionTap() async throws {
        let phone = SimPhone(w: 281, h: 626)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let pointer = Pointer(device: phone, calibrationFile: file)
        pointer.finishCalibration(x: 200.0 / 281, y: 200.0 / 626)
        pointer.finder = { _, _ in nil }
        do { try await pointer.tap(0.863, 0.887, aim: true); XCTFail("an unverified pointer must not click") }
        catch is DeviceError {}
        XCTAssertTrue(phone.clicks.isEmpty)
    }

    func testRealPixelAimVerifiesThePositionAfterTheProbeReturns() async throws {
        let device = Logs37PixelDevice()
        let screen = Logs37PixelScreen(phone: device.phone)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let pointer = Pointer(device: device, calibrationFile: file, screen: screen)
        pointer.finishCalibration(x: 200.0 / 281, y: 200.0 / 626)
        // Real pixel detection, no finder shortcut: a probe's inverse move can return to a different point.
        try await pointer.tap(0.863, 0.887, aim: true)
        let hit = try XCTUnwrap(device.phone.clicks.last)
        XCTAssertEqual(hit.x, 0.863, accuracy: Pointer.aimTolerance)
        XCTAssertEqual(hit.y, 0.887, accuracy: Pointer.aimTolerance)
    }

    func testAStillMisalignedPointerCannotClickAfterItsCorrectionBudget() async throws {
        let phone = SimPhone(w: 281, h: 626)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let pointer = Pointer(device: phone, calibrationFile: file)
        pointer.finishCalibration(x: 200.0 / 281, y: 200.0 / 626)
        pointer.finder = { _, _ in CGPoint(x: 0.97, y: 0.982) }
        do { try await pointer.tap(0.863, 0.887, aim: true); XCTFail("correction exhaustion must not fall through to click") }
        catch is DeviceError {}
        XCTAssertTrue(phone.clicks.isEmpty)
    }

    func testLostPointerDuringCorrectionCannotAuthorizeAClick() async throws {
        let phone = SimPhone(w: 281, h: 626)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let pointer = Pointer(device: phone, calibrationFile: file)
        pointer.finishCalibration(x: 200.0 / 281, y: 200.0 / 626)
        var looks = 0
        pointer.finder = { _, _ in looks += 1; return looks == 1 ? CGPoint(x: 0.97, y: 0.982) : nil }
        do { try await pointer.tap(0.863, 0.887, aim: true); XCTFail("losing the pointer leaves the tap unverified") }
        catch is DeviceError {}
        XCTAssertTrue(phone.clicks.isEmpty)
    }
}

@MainActor private final class Logs37PixelDevice: HIDDevice {
    let phone = SimPhone(w: 281, h: 626)
    var links: Int { phone.links }
    var connected: Bool { phone.connected }
    private var shifted = false
    func send(_ command: String) async throws -> String {
        let result = try await phone.send(command)
        if command == "move -12 0", !shifted {
            shifted = true
            phone.at.x += 0.02
        }
        return result
    }
    func waitConnected(_ timeout: TimeInterval) async -> Bool { true }
}

@MainActor private final class Logs37PixelScreen: ScreenSource {
    let phone: SimPhone
    init(phone: SimPhone) { self.phone = phone }
    var live = true
    var updated: Double { now() }
    var capturedAt: Double { now() }
    var aspect = 592.0 / 1280
    var frame: Data? {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 592, height: 1280), format: format).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 592, height: 1280))
            UIColor.gray.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: phone.at.x * 592 - 18, y: phone.at.y * 1280 - 18, width: 36, height: 36))
        }.jpegData(compressionQuality: 0.95)
    }
}

@MainActor private final class Logs37Gestures: Gestures {
    let device: HIDDevice = FakeDevice()
    var aims: [Bool] = []
    var points: [CGPoint] = []
    var types: [String] = []
    var keys: [String] = []
    var onType: ((String) -> Void)?
    var onTap: ((Int) -> Void)?
    func type(_ text: String) async throws { types.append(text); onType?(text) }
    func key(_ combo: String) async throws { keys.append(combo) }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { aims.append(aim); points.append(CGPoint(x: x, y: y)); onTap?(aims.count) }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
