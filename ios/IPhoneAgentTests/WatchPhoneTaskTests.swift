import XCTest
@testable import IPhoneAgent

@MainActor final class WatchPhoneTaskTests: XCTestCase {
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
}
