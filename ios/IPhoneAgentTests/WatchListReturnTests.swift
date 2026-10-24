import XCTest
@testable import IPhoneAgent

@MainActor final class WatchListReturnTests: XCTestCase {
    private func piece(_ text: String, x: Double, y: Double) -> CandidatePicker.Piece {
        .init(text: text, box: CGRect(x: x, y: y, width: 0.1, height: 0.02))
    }

    func testChatTitleUsesTheVisibleNavigationBarBackButton() {
        let rows = [[piece("客户群(8)", x: 0.4, y: 0.08)]]
        XCTAssertEqual(WatchListReturn.view(rows: rows, chat: "客户群"), .chat(CGPoint(x: 0.06, y: 0.09)))
        XCTAssertEqual(WatchListReturn.view(rows: rows, chat: "另一个群"), .unknown)
    }

    func testListNeedsBothNavigationTitleAndBottomTabs() {
        let header = [piece("微信(3)", x: 0.4, y: 0.08)]
        let tabs = [piece("微信", x: 0.05, y: 0.95), piece("通讯录", x: 0.3, y: 0.95),
                    piece("发现", x: 0.55, y: 0.95), piece("我", x: 0.8, y: 0.95)]
        XCTAssertEqual(WatchListReturn.view(rows: [header, tabs], chat: "客户群"), .list)
        XCTAssertEqual(WatchListReturn.view(rows: [header], chat: "客户群"), .unknown)
        XCTAssertEqual(WatchListReturn.view(rows: [tabs], chat: "客户群"), .unknown)
        XCTAssertEqual(WatchListReturn.view(rows: [[piece("微信", x: 0.4, y: 0.4)], tabs], chat: "客户群"), .unknown)
    }

    func testOneBackButtonTapVerifiesTheListWithoutAModelCall() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures(), screen = ReturnScreen()
        var fallbackCalls = 0
        let ok = await state.resume(phone: phone, screen: screen, canAct: { true }, inspect: { frame, _ in
            frame == Data([1]) ? .chat(CGPoint(x: 0.06, y: 0.09)) : .list
        }, fallback: { fallbackCalls += 1; return true })
        XCTAssertTrue(ok)
        XCTAssertNil(state.pending)
        XCTAssertEqual(phone.calls, ["tap"])
        XCTAssertEqual(screen.afterCalls, 1)
        XCTAssertEqual(screen.boundaries.count, 2)
        XCTAssertNotNil(screen.boundaries.last!)
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testAlreadyOnTheListDoesNotTapOrAskAModel() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures()
        let ok = await state.resume(phone: phone, screen: ReturnScreen(), canAct: { true },
                                    inspect: { _, _ in .list }, fallback: { XCTFail("already there"); return false })
        XCTAssertTrue(ok)
        XCTAssertEqual(phone.calls, [])
        XCTAssertNil(state.pending)
    }

    func testFailedReturnKeepsRecoveryPendingInsteadOfRescanningTheChat() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures(), screen = ReturnScreen()
        var fallbacks = 0
        let ok = await state.resume(phone: phone, screen: screen, canAct: { true },
                                    inspect: { _, _ in .chat(CGPoint(x: 0.06, y: 0.09)) },
                                    fallback: { fallbacks += 1; return false })
        XCTAssertFalse(ok)
        XCTAssertEqual(state.pending, "客户群")
        XCTAssertEqual(phone.calls, ["tap"])
        XCTAssertEqual(fallbacks, 1)
        // The next attempt recovers navigation only. It neither reads nor sends a message.
        let recovered = await state.resume(phone: phone, screen: screen, canAct: { true },
                                            inspect: { _, _ in .list }, fallback: { false })
        XCTAssertTrue(recovered)
        XCTAssertNil(state.pending)
        XCTAssertEqual(phone.calls, ["tap"])
    }

    func testFallbackCompletionAloneCannotClaimAVisibleList() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures()
        let ok = await state.resume(phone: phone, screen: ReturnScreen(), canAct: { true },
                                    inspect: { _, _ in .unknown }, fallback: { true })
        XCTAssertFalse(ok)
        XCTAssertEqual(state.pending, "客户群")
        XCTAssertEqual(phone.calls, [])
    }

    func testStaleFrameOrForegroundGatePreventsAnyGesture() async {
        for stale in [false, true] {
            let state = WatchListReturn(); state.pending = "客户群"
            let phone = FakeGestures(), screen = ReturnScreen(); screen.stale = stale
            let ok = await state.resume(phone: phone, screen: screen, canAct: { stale },
                                        inspect: { _, _ in .chat(CGPoint(x: 0.06, y: 0.09)) },
                                        fallback: { XCTFail("no fresh permission to act"); return false })
            XCTAssertFalse(ok)
            XCTAssertEqual(state.pending, "客户群")
            XCTAssertEqual(phone.calls, [])
        }
    }

    func testStoppingAfterTheTapCannotRunFallbackOrClearPending() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures(), screen = ReturnScreen()
        var allowed = true
        screen.onAfter = { allowed = false }
        let ok = await state.resume(phone: phone, screen: screen, canAct: { allowed },
                                    inspect: { _, _ in .chat(CGPoint(x: 0.06, y: 0.09)) },
                                    fallback: { XCTFail("stopped"); return false })
        XCTAssertFalse(ok)
        XCTAssertEqual(state.pending, "客户群")
        XCTAssertEqual(phone.calls, ["tap"])
    }
}

@MainActor private final class ReturnScreen: ScreenSource {
    var live = true
    var frame: Data? = Data([1])
    var updated = 0.0
    var capturedAt = 0.0
    var aspect = 0.46
    var stale = false
    var boundaries: [Double?] = []
    var afterCalls = 0
    var onAfter: (() -> Void)?
    func afterAction(since: Double) async { afterCalls += 1; frame = Data([2]); onAfter?() }
    func requireFrame(after: Double?) async throws {
        boundaries.append(after)
        if stale { throw BlindError() }
    }
}
