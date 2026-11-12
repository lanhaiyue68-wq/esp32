import XCTest
@testable import IPhoneAgent

/// Build 125: 群收录 (user 11-12, from the customer; docs/spec-group-archive-125.md).
@MainActor final class Build125Tests: XCTestCase {

    func testWhatIsOpenedLater() {
        XCTAssertEqual(WatchArchive.kind("[图片]"), "image")
        XCTAssertEqual(WatchArchive.kind("[视频号] 某某的视频"), "channels")
        XCTAssertEqual(WatchArchive.kind("[文件]"), "file")
        XCTAssertEqual(WatchArchive.kind("[链接] 新手必看的十个技巧"), "link")
        XCTAssertEqual(WatchArchive.kind("看这个 https://v.douyin.com/abc/"), "link")
        XCTAssertEqual(WatchArchive.kind("[聊天记录] 群聊的聊天记录"), "card")
        XCTAssertNil(WatchArchive.kind("大家早上好"))
        XCTAssertNil(WatchArchive.kind("[语音] 今天开会"), "a voice is written out, not opened")
        XCTAssertNil(WatchArchive.kind("[动画表情]"))
    }

    func testTheOpenTaskIsReadOnlyAndSendsNothing() {
        let item = ArchiveItem(chat: "测试群", sender: "张三", kind: "file", text: "[文件]", at: Date())
        let task = WatchArchive.openTask(item)
        XCTAssertTrue(task.contains("微信会话“测试群”"), "starts in WeChat: an open of WeChat is refused")
        XCTAssertTrue(task.contains("只看不动"))
        XCTAssertTrue(task.contains("点下载"))
        XCTAssertTrue(task.contains("不会发给任何人"))
    }

    func testTheDaysKnowledgeIsReadAndSent() {
        let reply = "好的：\n[{\"title\":\"投流先小额测试\",\"content\":\"先 100 元测三天\",\"links\":[],\"source\":\"测试群·张三\"},{\"title\":\"\"}]"
        let items = WatchArchive.knowledge(reply)
        XCTAssertEqual(items?.count, 1, "an item without a title is dropped")
        XCTAssertEqual(WatchArchive.knowledge("[]")?.count, 0, "no knowledge that day")
        XCTAssertNil(WatchArchive.knowledge("没有干货"), "not a list: tried again later")
        let body = WatchArchive.uploadBody(day: "2026-11-12", device: "home_iphone_01", items: items ?? [])
        XCTAssertEqual(body["date"] as? String, "2026-11-12")
        XCTAssertEqual((body["items"] as? [[String: Any]])?.count, 1)
    }

    func testTheInputHoldsTalkAndWhatWasOpened() {
        let talk = ReadMessage(chat: "测试群", group: true, sender: "张三", text: "这个工具很好用", atMe: false, replied: "")
        var seen = ArchiveItem(chat: "测试群", sender: "李四", kind: "image", text: "[图片]", at: Date())
        seen.summary = "一张价格表"; seen.ok = true
        let input = WatchArchive.distillInput(day: "2026-11-12", messages: [talk], opened: [seen])
        XCTAssertTrue(input.contains("张三：这个工具很好用"))
        XCTAssertTrue(input.contains("点开看到：一张价格表"))
    }
}
