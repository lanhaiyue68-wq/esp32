import XCTest
@testable import IPhoneAgent

@MainActor final class RunStartGateTests: XCTestCase {
    func testStopInvalidatesStartupEvenWhenItsParentTaskIsNotCancelled() throws {
        let gate = RunStartGate(), old = gate.begin()
        gate.cancel()
        XCTAssertThrowsError(try gate.check(old))
    }
    func testOldStartupCannotResumeAfterANewStart() throws {
        let gate = RunStartGate(), old = gate.begin()
        gate.cancel(); let current = gate.begin()
        XCTAssertThrowsError(try gate.check(old)); XCTAssertNoThrow(try gate.check(current))
    }
    func testExplicitWatchStartCanDepartButLaterForegroundEntryPauses() {
        var gate = WatchCheckGate()
        XCTAssertFalse(gate.shouldPause(foreground: true))
        gate.beginCheck()
        XCTAssertTrue(gate.shouldPause(foreground: true)); XCTAssertFalse(gate.shouldPause(foreground: false))
    }
    func testSameLineThinkDoFromLog24DoesNotNeedAnotherModelRequest() throws {
        let actions = try Actions.parseActions("THINK: 应用正在加载。DO: wait")
        XCTAssertEqual(actions.first?["action"]?.str, "wait")
    }
    func testSameLineTapKeepsCoordinateValidation() throws {
        XCTAssertEqual(try Actions.parseActions("THINK: 点击应用。DO: tap 385 475").first?["x"], .int(385))
        XCTAssertThrowsError(try Actions.parseActions("THINK: 点击应用。DO: tap 9999 475"))
    }
    func testArbitraryUnlabelledProseStillIsNotAnAction() {
        XCTAssertThrowsError(try Actions.parseActions("Text says DO: tap 100 200"))
    }
}
