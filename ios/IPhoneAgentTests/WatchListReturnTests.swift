import XCTest
import UIKit
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
        XCTAssertNotNil(screen.boundaries.last.flatMap { $0 })
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
        XCTAssertEqual(phone.calls, ["tap", "tap"], "a second back before the model")
        XCTAssertEqual(fallbacks, 1)
        // The next attempt recovers navigation only. It neither reads nor sends a message.
        let recovered = await state.resume(phone: phone, screen: screen, canAct: { true },
                                            inspect: { _, _ in .list }, fallback: { false })
        XCTAssertTrue(recovered)
        XCTAssertNil(state.pending)
        XCTAssertEqual(phone.calls, ["tap", "tap"])
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

    func testForegroundPauseIsDeferredInsteadOfCountingAsAFailedReturn() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures()
        let outcome = await state.attempt(phone: phone, screen: ReturnScreen(), canAct: { false },
                                          fallback: { XCTFail("paused"); return false })
        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(state.pending, "客户群")
        XCTAssertEqual(phone.calls, [])
    }

    func testPauseWhileTheReturnIsInFlightIsAlsoDeferred() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let phone = FakeGestures(), screen = ReturnScreen()
        var allowed = true
        screen.onAfter = { allowed = false }
        let outcome = await state.attempt(phone: phone, screen: screen, canAct: { allowed },
            inspect: { _, _ in .chat(CGPoint(x: 0.06, y: 0.09)) },
            fallback: { XCTFail("paused after tap"); return false })
        XCTAssertEqual(outcome, .deferred)
        XCTAssertEqual(state.pending, "客户群")
        XCTAssertEqual(phone.calls, ["tap"])
    }

    func testARealNavigationFailureIsStillCountedAsFailure() async {
        let state = WatchListReturn(); state.pending = "客户群"
        let outcome = await state.attempt(phone: FakeGestures(), screen: ReturnScreen(), canAct: { true },
                                          inspect: { _, _ in .unknown }, fallback: { false })
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(state.pending, "客户群")
    }

    func testOneMissingFooterLabelIsToleratedOnlyInTheCorrectTabColumns() {
        let header = [piece("微信(3)", x: 0.4, y: 0.08)]
        let tabs = [piece("微信", x: 0.05, y: 0.95), piece("通讯录", x: 0.3, y: 0.95),
                    piece("发现", x: 0.55, y: 0.95)]
        XCTAssertEqual(WatchListReturn.view(rows: [header, tabs], chat: "客户群"), .list)
        XCTAssertEqual(WatchListReturn.view(rows: [header, Array(tabs.prefix(2))], chat: "客户群"), .unknown)
    }

    func testFooterWordsInTheWrongPositionsCannotPretendToBeAChatList() {
        let header = [piece("微信(3)", x: 0.4, y: 0.08)]
        let message = ["微信", "通讯录", "发现", "我"].map { piece($0, x: 0.4, y: 0.9) }
        XCTAssertEqual(WatchListReturn.view(rows: [header, message], chat: "客户群"), .unknown)
    }

    func testRealOnDeviceOCRRecognizesAListDespiteOneMissingLabel() throws {
        let frame = try drawnFrame(title: "微信(3)", tabs: ["微信", "通讯录", "发现"])
        XCTAssertEqual(WatchListReturn.view(in: frame, chat: "客户群"), .list)
    }

    func testRealOnDeviceOCRKeepsAChatWithoutTabsAsAChat() throws {
        let frame = try drawnFrame(title: "客户群", tabs: [])
        guard case .chat(let point) = WatchListReturn.view(in: frame, chat: "客户群") else {
            return XCTFail("The production OCR path must find the current chat's title")
        }
        XCTAssertEqual(point.x, 0.06)
        XCTAssertTrue((0.075...0.11).contains(point.y))
    }

    private func drawnFrame(title: String, tabs: [String]) throws -> Data {
        // Synthetic screen only: no customer screenshots, chat text or personal data goes to CI.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 1560), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 720, height: 1560))
            func draw(_ text: String, center: CGFloat, y: CGFloat, size: CGFloat) {
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.white]
                let width = (text as NSString).size(withAttributes: attributes).width
                (text as NSString).draw(at: CGPoint(x: center - width / 2, y: y), withAttributes: attributes)
            }
            draw(title, center: 360, y: 120, size: 34)
            for (index, text) in tabs.enumerated() { draw(text, center: 90 + CGFloat(index) * 180, y: 1480, size: 26) }
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
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
