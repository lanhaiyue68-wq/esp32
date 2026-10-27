import XCTest
@testable import IPhoneAgent

@MainActor final class Logs38RegressionTests: XCTestCase {
    private let request = WatchReport.Line(sender: "Owner", text: "Open Notes and write the shopping list", mine: false)

    func testAnAuthorizedTaskDoesNotDependOnItsAcknowledgementBeingVerified() {
        var rules = WatchSettings.Rules(targets: ["Owner"], senders: ["Owner"], myNames: [])
        rules.phoneTasks = true
        let source = ReadMessage(chat: "Owner", group: false, sender: "Owner", text: request.text, verified: true)
        XCTAssertTrue(WatchSettings.canStartTask(replySent: false, sources: [source], rules: rules))
        var unverified = source; unverified.verified = false
        XCTAssertFalse(WatchSettings.canStartTask(replySent: false, sources: [unverified], rules: rules))
        var disabled = rules; disabled.phoneTasks = false
        XCTAssertFalse(WatchSettings.canStartTask(replySent: false, sources: [source], rules: disabled))
    }

    func testAConfirmedSendFinishesBeforeTheActorCanMisreadItAndRetype() async {
        let actor = FakeModel { n in n == 1 ? "DO: key enter" : "DO: type Received, working on it." }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.inputToInspect = "Received, working on it."
        agent.directStart = true; agent.endAfterSend = 2
        agent.sendReceipt = { text in
            WatchReport.confirmedReply(text, after: self.request, in: [self.request,
                .init(sender: "Me", text: "Received, working on it.", mine: true)])
        }
        await agent.run()
        XCTAssertEqual(agent.steps.last?["action"], .str("done"), "logs38: a new own bubble must not become a failed acknowledgement")
        XCTAssertEqual(actor.prompts.count, 1, "do not ask the actor to reinterpret an independently verified receipt")
        XCTAssertEqual(phone.calls, ["key"], "no duplicate input, navigation, or send")
    }

    func testAnOldMatchingBubbleCannotConfirmThisSend() async {
        let actor = FakeModel { n in n == 1 ? "DO: key enter" : "DO: type Received, working on it." }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.inputToInspect = "Received, working on it."
        agent.directStart = true; agent.endAfterSend = 2
        agent.sendReceipt = { text in
            WatchReport.confirmedReply(text, after: self.request, in: [
                .init(sender: "Me", text: text, mine: true), self.request])
        }
        await agent.run()
        XCTAssertEqual(agent.steps.last?["action"], .str("fail"))
        XCTAssertEqual(phone.calls, ["key"], "unknown results retain the duplicate-send protection")
    }

    func testMissingRequestAnchorCannotTurnAnOldBubbleIntoAReceipt() {
        XCTAssertFalse(WatchReport.confirmedReply("Received", after: request,
            in: [.init(sender: "Me", text: "Received", mine: true)]))
    }

    func testTheEntireReplyMustMatchIncludingCodeOperatorsAndCase() {
        for (expected, wrong) in [("abcdefgh correct", "abcdefgh wrong"), ("value += 1", "value -= 1"), ("Result", "result")] {
            XCTAssertFalse(WatchReport.confirmedReply(expected, after: request,
                in: [request, .init(sender: "Me", text: wrong, mine: true)]), "\(expected) != \(wrong)")
        }
    }

    func testAReplyMustFollowTheLastMatchingRequest() {
        XCTAssertFalse(WatchReport.confirmedReply("Received", after: request,
            in: [request, .init(sender: "Me", text: "Received", mine: true), request]))
    }

    func testReadFormattingCanVaryWithoutChangingTheWholeReply() {
        XCTAssertTrue(WatchReport.confirmedReply("收到，我去处理。", after: request,
            in: [request, .init(sender: "Me", text: "收到, 我去处理.", mine: true)]))
    }
}
