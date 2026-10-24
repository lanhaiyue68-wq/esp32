import XCTest
@testable import IPhoneAgent

@MainActor final class WatchPhoneTaskTests: XCTestCase {
    private func enabledRules() -> WatchSettings.Rules {
        var r = WatchSettings.Rules(targets: ["蓝海乐", "测试群"], senders: ["蓝海乐"], myNames: ["蓝"])
        r.phoneTasks = true
        return r
    }

    func testAnEnabledOwnersRequestCanBecomeATaskOutsideWeChat() {
        let defaults = UserDefaults.standard
        let values: [String: Any] = [
            "watchPhoneTasksV1": true,
            WatchSettings.targetsKey: "蓝海乐",
            WatchSettings.sendersKey: "蓝海乐",
            WatchSettings.serverOnKey: false
        ]
        let previous = values.keys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in previous {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for (key, value) in values { defaults.set(value, forKey: key) }
        let request = ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "打开备忘录，新建一条买牛奶的备忘录")
        let prompt = WatchSettings.composePrompt(chat: request.chat, group: false, recent: [], due: [request],
                                                r: WatchSettings.rules, knowledge: "", owner: true)
        // The planner must be offered the phone executor, otherwise the request can only receive a chat reply.
        XCTAssertTrue(prompt.contains("微信以外"), "The opted-in owner's request is still confined to WeChat")
    }

    func testPhoneTasksRequireEverySourceMessageToBeExplicitlyAuthorized() {
        let owner = ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "打开备忘录，写下买牛奶", verified: true)
        let r = enabledRules()
        XCTAssertEqual(WatchSettings.phoneRequest([owner], r), "打开备忘录，写下买牛奶")
        var denied = r; denied.phoneTasks = false
        XCTAssertNil(WatchSettings.phoneRequest([owner], denied))
        denied = r; denied.senders = []
        XCTAssertNil(WatchSettings.phoneRequest([owner], denied))
        denied = r; denied.targets = []
        XCTAssertNil(WatchSettings.phoneRequest([owner], denied))
        denied = r; denied.serverReplies = true
        XCTAssertNil(WatchSettings.phoneRequest([owner], denied))
        var other = owner; other.sender = "冒充蓝海乐"
        XCTAssertNil(WatchSettings.phoneRequest([other], r))
        XCTAssertNil(WatchSettings.phoneRequest([owner, other], r))
        other = owner; other.chat = "陌生会话"
        XCTAssertNil(WatchSettings.phoneRequest([other], r))
        XCTAssertNil(WatchSettings.phoneRequest([], r))
        other = owner; other.text = " \n "
        XCTAssertNil(WatchSettings.phoneRequest([other], r))
    }

    func testGroupMessagesNeverStartPhoneTasksEvenFromTheOwnersName() {
        // logs26: anyone in a group can take the owner's name as a group nickname.
        let first = ReadMessage(chat: "测试群", group: true, sender: "蓝海乐", text: "@蓝 打开备忘录", verified: true)
        let second = ReadMessage(chat: "测试群", group: true, sender: "蓝海乐", text: "@蓝 写下买牛奶", verified: true)
        XCTAssertNil(WatchSettings.phoneRequest([first, second], enabledRules()))
        let unproven = ReadMessage(chat: "蓝海乐", group: false, sender: "蓝海乐", text: "打开备忘录")
        XCTAssertNil(WatchSettings.phoneRequest([unproven], enabledRules()), "a private message without the passcode")
        var proven = unproven; proven.verified = true
        XCTAssertEqual(WatchSettings.phoneRequest([proven, proven], enabledRules()), "打开备忘录\n打开备忘录")
    }

    func testPendingResultSurvivesRelaunchWithoutKeepingAnExecutableTask() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "watch-result-\(UUID().uuidString)"))
        let result = WatchTaskReply(chat: "蓝海乐", sender: "蓝海乐", text: "已新建买牛奶备忘录")
        WatchTaskReply.save(result, in: defaults)
        XCTAssertEqual(WatchTaskReply.saved(in: defaults), result)
        WatchTaskReply.save(nil, in: defaults)
        XCTAssertNil(WatchTaskReply.saved(in: defaults))
    }

    func testAStoredResultCannotBeSentAfterStopOrRevokingItsPermission() {
        let result = WatchTaskReply(chat: "蓝海乐", sender: "蓝海乐", text: "已完成")
        let r = enabledRules()
        XCTAssertTrue(result.canDeliver(r, watching: true))
        XCTAssertFalse(result.canDeliver(r, watching: false))
        var denied = r; denied.phoneTasks = false
        XCTAssertFalse(result.canDeliver(denied, watching: true))
        denied = r; denied.senders = []
        XCTAssertFalse(result.canDeliver(denied, watching: true))
        denied = r; denied.targets = []
        XCTAssertFalse(result.canDeliver(denied, watching: true))
        denied = r; denied.serverReplies = true
        XCTAssertFalse(result.canDeliver(denied, watching: true))
    }
}
