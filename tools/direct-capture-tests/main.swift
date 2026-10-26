import Foundation
import XCTest
@testable import CapturePolicy

final class DirectFrameTests: XCTestCase {
    func testFreshDisplayFrameCanAuthorizeAction() {
        let id = UUID(); var state = DirectFrameState(); state.begin(id, fullDisplay: true)
        XCTAssertTrue(state.complete(id, sequence: 1, capturedAt: 10, at: 10.1))
        XCTAssertTrue(state.usable(at: 10.2, after: 9.9))
        XCTAssertFalse(state.usable(at: 10.2, after: 10.05))
    }
    func testAppOnlyFramesCannotAuthorizePhoneControl() {
        let id = UUID(); var state = DirectFrameState(); state.begin(id, fullDisplay: false)
        XCTAssertFalse(state.complete(id, sequence: 1, capturedAt: 10, at: 10.1))
        XCTAssertFalse(state.usable(at: 10.2))
    }
    func testIdleConfirmsOnlyExistingUnchangedPixels() {
        let id = UUID(); var state = DirectFrameState(); state.begin(id, fullDisplay: true)
        XCTAssertFalse(state.idle(id, sequence: 1, confirmedAt: 10, at: 10.1))
        XCTAssertTrue(state.complete(id, sequence: 2, capturedAt: 11, at: 11.1))
        XCTAssertFalse(state.usable(at: 20))
        XCTAssertTrue(state.idle(id, sequence: 3, confirmedAt: 20, at: 20.1))
        XCTAssertEqual(state.capturedAt, 11)
        XCTAssertTrue(state.usable(at: 20.2, after: 19))
    }
    func testStoppedOrReplacedSessionCannotReviveOldPixels() {
        let old = UUID(), current = UUID(); var state = DirectFrameState()
        state.begin(old, fullDisplay: true)
        _ = state.complete(old, sequence: 1, capturedAt: 10, at: 10.1)
        state.begin(current, fullDisplay: true)
        XCTAssertFalse(state.complete(old, sequence: 2, capturedAt: 11, at: 11.1))
        XCTAssertFalse(state.usable(at: 11.1))
        _ = state.complete(current, sequence: 1, capturedAt: 12, at: 12.1)
        state.stop()
        XCTAssertFalse(state.complete(current, sequence: 2, capturedAt: 13, at: 13.1))
        XCTAssertFalse(state.usable(at: 13.2))
    }
    func testSuspendedPixelsStayInvalidUntilCompleteFrame() {
        let id = UUID(); var state = DirectFrameState(); state.begin(id, fullDisplay: true)
        _ = state.complete(id, sequence: 1, capturedAt: 10, at: 10.1)
        state.invalidate(id, sequence: 2)
        XCTAssertFalse(state.usable(at: 10.2))
        XCTAssertFalse(state.idle(id, sequence: 3, confirmedAt: 11, at: 11.1))
        XCTAssertTrue(state.complete(id, sequence: 4, capturedAt: 12, at: 12.1))
    }
    func testOutOfOrderCallbacksCannotOverwriteNewPixels() {
        let id = UUID(); var state = DirectFrameState(); state.begin(id, fullDisplay: true)
        XCTAssertTrue(state.complete(id, sequence: 5, capturedAt: 10, at: 10.1))
        XCTAssertFalse(state.complete(id, sequence: 4, capturedAt: 9, at: 10.2))
        state.invalidate(id, sequence: 3)
        XCTAssertTrue(state.usable(at: 10.3))
        XCTAssertEqual(state.capturedAt, 10)
    }
    func testInvalidOrQueuedOldTimestampsAreRejected() {
        let id = UUID(); var state = DirectFrameState(); state.begin(id, fullDisplay: true)
        for timestamp in [Double.nan, .infinity, -1, 20, 1] {
            XCTAssertFalse(state.complete(id, sequence: 1, capturedAt: timestamp, at: 10))
        }
        XCTAssertFalse(state.usable(at: .nan))
    }
}

