import Foundation
import XCTest
@testable import PointerMotion

/// The real firmware's curve query/set contract, with a varying landing while enabled.
/// This counterexample does not claim to simulate iOS acceleration numerically.
@MainActor final class CurveBoard: HIDDevice {
    var curve = true
    var sent: [String] = []
    var reply: String?
    var queryFailure: String?
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
        if command == "home" { at = .zero }
        let parts = command.split(separator: " ")
        if parts.first == "move" {
            moves += 1
            let extra = curve ? (moves.isMultiple(of: 2) ? 0.05 : -0.02) : 0
            at.x += Double(parts[1])! / 300 + extra
            at.y += Double(parts[2])! / 650
        }
        return ""
    }
}

final class PointerMotionTests: XCTestCase {
    @MainActor func testHomeConfirmsStraightModeBeforeTheFirstMovement() async throws {
        let board = CurveBoard()
        try await ProbeMotion.home(board)
        XCTAssertEqual(board.sent.prefix(3), ["curve", "curve off", "home"])
        XCTAssertFalse(board.curve)
    }

    @MainActor func testIdenticalCommandsDoNotKeepTheFirmwareCurveVariation() async throws {
        let board = CurveBoard()
        for _ in 0..<2 {
            try await ProbeMotion.home(board)
            try await ProbeMotion.move(board, 140, 265)
            XCTAssertEqual(board.at.x, 140.0 / 300, accuracy: 0.0001)
            XCTAssertEqual(board.at.y, 265.0 / 650, accuracy: 0.0001)
        }
    }

    @MainActor func testAResetBoardIsCheckedAgainBeforeAnotherGesture() async throws {
        let board = CurveBoard()
        try await ProbeMotion.home(board)
        board.curve = true  // restored board configuration or another controller
        try await ProbeMotion.home(board)
        XCTAssertFalse(board.curve)
        XCTAssertEqual(board.sent.filter { $0 == "curve off" }.count, 2)
    }

    @MainActor func testAlreadyStraightDoesNotRewriteTheStoredSetting() async throws {
        let board = CurveBoard(); board.curve = false
        try await ProbeMotion.home(board)
        XCTAssertEqual(board.sent, ["curve", "home"])
    }

    @MainActor func testUnexpectedModeReplyDoesNotSendHome() async {
        let board = CurveBoard(); board.reply = "garbled"
        do { try await ProbeMotion.home(board); XCTFail("unconfirmed motion mode must stop") }
        catch { XCTAssertFalse(board.sent.contains("home")) }
    }

    @MainActor func testFailedModeChangeDoesNotSendHome() async {
        let board = CurveBoard(); board.reply = "on"
        do { try await ProbeMotion.home(board); XCTFail("curve still enabled must stop") }
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
