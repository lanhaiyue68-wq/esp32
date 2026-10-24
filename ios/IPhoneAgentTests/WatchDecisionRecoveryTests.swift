import XCTest
@testable import IPhoneAgent

@MainActor final class WatchDecisionRecoveryTests: XCTestCase {
    private let before: [WatchReport.Line] = [.init(sender: "朋友", text: "上一条", mine: false)]
    private var screen: [WatchReport.Line] { before + [.init(sender: "朋友", text: "@助手 在吗", mine: false)] }

    func testMalformedDecisionLeavesTheNewMessageEligibleForRetry() async throws {
        let fresh = WatchReport.new(screen, history: before)
        var saved: [WatchReport.Line]? = WatchReport.remember(fresh, screen: screen, history: before)
        let result = try await WatchReport.decide("reply", client: FakeModel { _ in #"{"reply": broken}"# },
                                                  onReply: { _ in }, rollback: { saved = self.before })
        XCTAssertNil(result)
        XCTAssertEqual(WatchReport.new(screen, history: saved), fresh,
                       "A failed decision must not consume messages before a reply can be chosen")
    }

    func testModelTimeoutAlsoLeavesTheNewMessageEligibleForRetry() async {
        let fresh = WatchReport.new(screen, history: before)
        var saved: [WatchReport.Line]? = WatchReport.remember(fresh, screen: screen, history: before)
        do {
            _ = try await WatchReport.decide("reply", client: FailedDecisionModel(), onReply: { _ in },
                                             rollback: { saved = self.before })
            XCTFail("The model should time out")
        } catch {
            XCTAssertEqual(WatchReport.new(screen, history: saved), fresh)
        }
    }

    func testAValidDecisionToStaySilentDoesNotRetryTheSameMessage() async throws {
        let fresh = WatchReport.new(screen, history: before)
        var saved: [WatchReport.Line]? = WatchReport.remember(fresh, screen: screen, history: before)
        let result = try await WatchReport.decide("reply", client: FakeModel { _ in #"{"reply":"","task":""}"# },
                                                  onReply: { _ in }, rollback: { saved = self.before })
        XCTAssertNotNil(result)
        XCTAssertEqual(WatchReport.new(screen, history: saved), [])
    }
}

@MainActor private final class FailedDecisionModel: ChatModel {
    let model = "timeout-test"
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        throw URLError(.timedOut)
    }
}
