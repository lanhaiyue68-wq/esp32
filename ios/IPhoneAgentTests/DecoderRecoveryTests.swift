import XCTest
@testable import IPhoneAgent

final class DecoderRecoveryTests: XCTestCase {
    func testUsableFrameDecodedAfterBackgroundDoesNotRebuildTheGOP() {
        // A successful decode after the transition proves the decoder survived it.
        // Replaying hundreds of old units here blocks the live stream and paste verification.
        XCTAssertFalse(FrameFreshness.needsDecoderRefresh(decodedAt: 101.2, transitionAt: 100, usable: true))
    }

    func testAnOldQuietFrameStillRebuildsEvenIfTheBoardSaysItIsCurrent() {
        // The image may be current while iOS has invalidated the decoder for the next frame.
        XCTAssertTrue(FrameFreshness.needsDecoderRefresh(decodedAt: 99, transitionAt: 100, usable: true))
        XCTAssertTrue(FrameFreshness.needsDecoderRefresh(decodedAt: 100, transitionAt: 100, usable: true))
    }

    func testADecodeAfterBackgroundMustAlsoPassExistingFreshnessChecks() {
        XCTAssertTrue(FrameFreshness.needsDecoderRefresh(decodedAt: 101.2, transitionAt: 100, usable: false))
        XCTAssertTrue(FrameFreshness.needsDecoderRefresh(decodedAt: 0, transitionAt: 100, usable: false))
    }
}
