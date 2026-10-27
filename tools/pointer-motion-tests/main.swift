import Foundation
import XCTest
@testable import PointerMotion

/// The real firmware's curve query/set contract, with a varying landing while enabled.
/// This counterexample does not claim to simulate iOS acceleration numerically.
@MainActor final class CurveBoard: HIDDevice {
    var curve = true
    var sent: [String] = []
    var reply: String?
    var setReply: String?
    var queryFailure: String?
    var curvedMoves = 0
    var at = CGPoint.zero
    private var moves = 0

    func send(_ command: String) async throws -> String {
        sent.append(command)
        if command == "curve" {
            if let queryFailure { throw DeviceError(message: queryFailure) }
            return reply ?? (curve ? "on" : "off")
        }
        if command == "curve off" {
            if let reply { return reply }
            curve = false
            return "off"
        }
        if command == "curve on" {
            if let setReply { return setReply }
            curve = true
            return "on"
        }
        if command == "home" { at = .zero }
        let parts = command.split(separator: " ")
        if parts.first == "move" {
            moves += 1
            if curve { curvedMoves += 1 }
            let extra = curve ? (moves.isMultiple(of: 2) ? 0.05 : -0.02) : 0
            at.x += Double(parts[1])! / 300 + extra
            at.y += Double(parts[2])! / 650
        }
        return ""
    }
}

final class PointerMotionTests: XCTestCase {
    @MainActor func testHomePreservesTheEnabledBezierSetting() async throws {
        let board = CurveBoard()
        try await ProbeMotion.home(board)
        XCTAssertEqual(board.sent, ["curve", "home"])
        XCTAssertTrue(board.curve)
    }

    @MainActor func testCalibrationAndPositioningKeepUsingFirmwareBezierMoves() async throws {
        let board = CurveBoard()
        try await ProbeMotion.home(board)
        try await ProbeMotion.move(board, 140, 265)
        XCTAssertEqual(board.curvedMoves, 2, "both axis moves must reach the firmware with Bezier enabled")
        XCTAssertFalse(board.sent.contains("curve off"))
    }

    @MainActor func testAResetBoardRestoresBezierBeforeAnotherGesture() async throws {
        let board = CurveBoard()
        try await ProbeMotion.home(board)
        board.curve = false  // build79's stored setting, reset or another controller
        try await ProbeMotion.home(board)
        XCTAssertTrue(board.curve)
        XCTAssertEqual(board.sent.filter { $0 == "curve on" }.count, 1)
        XCTAssertFalse(board.sent.contains("curve off"))
    }

    @MainActor func testBuild79DisabledSettingIsRecoveredBeforeHome() async throws {
        let board = CurveBoard(); board.curve = false
        try await ProbeMotion.home(board)
        XCTAssertEqual(board.sent, ["curve", "curve on", "home"])
        XCTAssertTrue(board.curve)
        try await ProbeMotion.home(board)
        XCTAssertEqual(board.sent.filter { $0 == "curve on" }.count, 1, "do not rewrite NVS when already enabled")
    }

    @MainActor func testUnexpectedModeReplyDoesNotSendHome() async {
        let board = CurveBoard(); board.reply = "garbled"
        do { try await ProbeMotion.home(board); XCTFail("unconfirmed motion mode must stop") }
        catch { XCTAssertFalse(board.sent.contains("home")) }
    }

    @MainActor func testFailedModeChangeDoesNotSendHome() async {
        let board = CurveBoard(); board.curve = false; board.setReply = "off"
        do { try await ProbeMotion.home(board); XCTFail("Bezier was not restored; positioning must stop") }
        catch { XCTAssertFalse(board.sent.contains("home")) }
    }

    @MainActor func testModeTimeoutDoesNotPretendTheBoardIsLegacy() async {
        let board = CurveBoard(); board.queryFailure = "timeout"
        do { try await ProbeMotion.home(board); XCTFail("a timeout is not an unsupported command") }
        catch { XCTAssertFalse(board.sent.contains("home")) }
    }

    @MainActor func testOlderStraightFirmwareCanReportUnsupportedCurveCommand() async throws {
        let board = CurveBoard(); board.curve = false; board.queryFailure = "unknown command"
        try await ProbeMotion.home(board)
        XCTAssertEqual(board.sent.last, "home")
        XCTAssertFalse(board.sent.contains("curve off"))
    }
}
