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

@MainActor private final class Logs37Gestures: Gestures {
    let device: HIDDevice = FakeDevice()
    var aims: [Bool] = []
    var types: [String] = []
    var onType: ((String) -> Void)?
    var onTap: ((Int) -> Void)?
    func type(_ text: String) async throws { types.append(text); onType?(text) }
    func key(_ combo: String) async throws {}
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws { aims.append(aim); onTap?(aims.count) }
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws {}
    func drag(_ points: [CGPoint], hold: Bool) async throws {}
    func goHome() async throws {}
    func goBack() async throws {}
    func reset() async throws {}
}
