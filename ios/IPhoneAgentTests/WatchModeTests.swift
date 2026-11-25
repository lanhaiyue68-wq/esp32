import XCTest
import UIKit
@testable import IPhoneAgent

/// WeChat watch: who is read and answered, what triggers a reply, what is kept and reported, what never leaves.
@MainActor final class WatchModeTests: XCTestCase {
    private func rules(_ edit: (inout WatchSettings.Rules) -> Void = { _ in }) -> WatchSettings.Rules {
        var r = WatchSettings.Rules(targets: ["客户群"], onlyListed: true, senders: ["蓝海乐"], passphrases: ["天王盖地虎"],
                                    myNames: ["蓝"], interject: false, serverReplies: false, instruction: "礼貌回复", fallback: "稍后告诉你")
        edit(&r)
        return r
    }

    private func message(_ sender: String, _ text: String) -> ReadMessage {
        ReadMessage(chat: "客户群", group: true, sender: sender, text: text)
    }

    func testNamesAreOnePerLineOrSeparatedByCommas() {
        XCTAssertEqual(WatchSettings.lines("张三\n 客户群 ，李四、张三\n\n"), ["张三", "客户群", "李四"])
    }

    func testOnlyAWhitelistedAtMentionOrPassphraseIsAReplyTrigger() {
        let r = rules()
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "@蓝 你告诉我群主是谁"), r))
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "＠蓝 在吗"), r))
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "天王盖地虎，今天几点开会"), r))
        XCTAssertFalse(WatchSettings.fires(message("蓝海乐", "妈的还得调试"), r))      // traces(34): read, not answered
        XCTAssertFalse(WatchSettings.fires(message("路人甲", "@蓝 借我点钱"), r))      // not whitelisted
        XCTAssertTrue(WatchSettings.fires(message("路人甲", "@蓝 在吗"), rules { $0.senders = [] }))  // no whitelist: anyone
        XCTAssertFalse(WatchSettings.fires(message("蓝海乐", "@蓝色妖姬 你好"), rules { $0.myNames = ["小蓝"] }))
    }

    func testAnAtPassphraseMeansAnAtMentionOfThisAccount() {
        XCTAssertEqual(WatchSettings.passphrases(from: "@我\n天王盖地虎"), ["天王盖地虎"])  // "@我" is not words to look for
        XCTAssertEqual(WatchSettings.names(typed: "蓝", codes: "@我"), ["蓝"])
        XCTAssertEqual(WatchSettings.names(typed: "", codes: "＠蓝\n天王盖地虎"), ["蓝"])
        XCTAssertEqual(WatchSettings.names(typed: "@蓝\n蓝", codes: "@蓝"), ["蓝"])
        let r = rules { $0.passphrases = WatchSettings.passphrases(from: "@我") }
        XCTAssertTrue(WatchSettings.fires(message("蓝海乐", "@蓝 你告诉我群主是谁"), r))
        XCTAssertFalse(WatchSettings.fires(message("蓝海乐", "大家@我一下"), r))
    }

    func testOpeningTheChatNeverReplies() {
        let one = WatchSettings.openTask(rules())
        XCTAssertTrue(one.contains("“客户群”"))
        XCTAssertTrue(one.contains("没有红色标记的会话不要打开"))  // build98: one chat needs its red mark too
        XCTAssertTrue(one.contains("不要回复"))
        let many = WatchSettings.openTask(rules { $0.targets = ["客户群", "张三"] })
        XCTAssertTrue(many.contains(#"{"chat":"会话名"}"#))
        XCTAssertFalse(one.contains("画") || many.contains("画"))  // never looks like a drawing task (unmadeResult)
        XCTAssertTrue(WatchSettings.sendTask(chat: "客户群", text: "好的").contains("一字不改"))
    }

    func testTheScreenIsReadIntoLinesAndOnlyWhatFollowsTheSeenOnesIsNew() throws {
        let reply = #"```json {"group":true,"messages":[{"sender":"蓝海乐","text":"@蓝 你人呢"},{"sender":"我","text":"在的","mine":true},{"sender":"蓝海乐","text":"妈的还得调试"},{"sender":"x","text":" "}]} ```"#
        let screen = try XCTUnwrap(WatchReport.screen(reply))
        XCTAssertTrue(screen.group)
        XCTAssertEqual(screen.lines.map(\.text), ["@蓝 你人呢", "在的", "妈的还得调试"])
        XCTAssertEqual(WatchReport.new(screen.lines, history: Array(screen.lines.prefix(2))).map(\.text), ["妈的还得调试"])
        XCTAssertEqual(WatchReport.new(screen.lines, history: screen.lines), [])
        XCTAssertNil(WatchReport.screen("看不清"))
        XCTAssertEqual(WatchReport.openedChat(#"{"chat":"张三"}"#), "张三")
        XCTAssertNil(WatchReport.openedChat(#"{"chat":""}"#))
    }

    func testARepeatedQuestionIsNewAndAQuoteReadTwoWaysIsNot() {
        // traces(35): the owner asked "@蓝 你告诉我群主是谁" a second time, word for word; the quote under "+1" was
        // read once inside the message and once without it.
        let line = { (sender: String, text: String) in WatchReport.Line(sender: sender, text: text, mine: false) }
        let before = [line("蓝海乐", "妈的还得调试"), line("良三", "+1"), line("蓝海乐", "@蓝 你告诉我群主是谁")]
        let now = [line("蓝海乐", "妈的还得调试"), line("良三", "+1 \n江南芳言 admin：个微用的怎么样"), line("蓝海乐", "@蓝 你告诉我群主是谁"),
                   line("蓝海乐", "@蓝 你告诉我群主是谁")]
        XCTAssertEqual(WatchReport.new(now, history: before).map(\.text), ["@蓝 你告诉我群主是谁"])
        let scrolled = [line("新人", "大家好"), line("蓝海乐", "@蓝 你在不在")]  // nothing of the previous look is left
        XCTAssertEqual(WatchReport.new(scrolled, history: before).map(\.text), ["大家好", "@蓝 你在不在"])
    }

    func testAChatAlreadyOpenIsNotOpenedAgain() {
        // traces(38): every check ran an agent just to find it was in the group already (~10 s of thinking).
        let read = WatchReport.screen(#"{"title":"虾笔刀陪跑学员元群(90)","group":true,"messages":[{"sender":"蓝海乐","text":"@蓝 在不在"}]}"#)
        XCTAssertEqual(read?.title, "虾笔刀陪跑学员元群(90)")
        XCTAssertTrue(WatchReport.isChat("虾笔刀陪跑学员元群(90)", "虾笔刀陪跑学员元群"))
        XCTAssertTrue(WatchReport.isChat("虾笔刀陪跑学员…", "虾笔刀陪跑学员元群"))  // a long name cut short
        XCTAssertFalse(WatchReport.isChat("蓝海乐", "虾笔刀陪跑学员元群"))
        XCTAssertFalse(WatchReport.isChat("", "虾笔刀陪跑学员元群"))  // not a chat screen
        XCTAssertEqual(WatchReport.screen(#"{"group":false,"messages":[]}"#)?.title, "")
        XCTAssertTrue(WatchSettings.sendPlan(chat: "客户群", back: false).contains("tap 发送"))
        XCTAssertTrue(WatchSettings.openPlan(chat: "客户群").contains("done right away"))
    }

    func testTheSameWordsSentAgainAreNewEachTime() {
        // logs(12): "@蓝 在不在" sent three times was never new: the previous tail matched the newest copy.
        let a = WatchReport.Line(sender: "蓝海乐", text: "@蓝 在不在", mine: false)
        let comma = WatchReport.Line(sender: "蓝海乐", text: "，", mine: false)
        XCTAssertEqual(WatchReport.new([a, a], history: [comma, a]), [a])
        XCTAssertEqual(WatchReport.new([a, a, a], history: [a, a]), [a])
        XCTAssertEqual(WatchReport.new([a, a], history: [a, a]), [])  // nothing sent: nothing new
        XCTAssertEqual(WatchReport.remember([a], screen: [a, a, a], history: [a, a]), [a, a, a])
        // the top line cut off or read differently: the run may start up to two lines down
        let z = WatchReport.Line(sender: "良三", text: "+1", mine: false), n = WatchReport.Line(sender: "蓝海乐", text: "@蓝 新的", mine: false)
        XCTAssertEqual(WatchReport.new([WatchReport.Line(sender: "蓝海乐", text: "又傻", mine: false), z, n], history: [comma, a, z]), [n])
        // and a read written with Python's True/False is still read (logs(12) lost one)
        let read = WatchReport.screen(#"{"title":"测试群","group":True,"messages":[{"sender":"蓝海乐","text":"@蓝 在不在","mine":False}]}"#)
        XCTAssertEqual(read?.group, true)
        XCTAssertEqual(read?.lines, [a])
    }

    func testAWatchStartsAfterTheLastLookOfThePreviousOne() {
        let line = { (sender: String, text: String, mine: Bool) in WatchReport.Line(sender: sender, text: text, mine: mine) }
        // traces(39): the previous watch had already seen the old "find the group owner" from a test; only what came
        // after it is new, so that old request is not carried out again.
        let earlier = [line("蓝海乐", "@蓝 在不在", false), line("我", "在的,有什么事吗", true), line("蓝海乐", "@蓝 告诉我群主是谁，并把他@出来", false)]
        let now = earlier + [line("蓝海乐", "又傻逼了", false), line("蓝海乐", "@蓝 在不在", false)]
        XCTAssertEqual(WatchReport.new(now, history: earlier).map(\.text), ["又傻逼了", "@蓝 在不在"])
        // traces(36): sent while the watch was still opening the chat: after the last look, so it is new.
        XCTAssertEqual(WatchReport.new(earlier + [line("蓝海乐", "@蓝 在不在", false)], history: earlier).map(\.text), ["@蓝 在不在"])
        // No history yet: the watch starts here. History but no overlap: more than a screenful came in, all new.
        XCTAssertEqual(WatchReport.new(now, history: nil), [])
        XCTAssertEqual(WatchReport.new(now, history: [line("某人", "很久以前的话", false)]), now)
    }

    func testTheReplyIsWrittenFromTheChatTheRulesAndTheKnowledge() {
        let lines = [WatchReport.Line(sender: "蓝海乐", text: "@蓝 群主是谁", mine: false)]
        let due = [message("蓝海乐", "@蓝 群主是谁")]
        let prompt = WatchSettings.composePrompt(chat: "客户群", group: true, recent: lines, due: due, r: rules(), knowledge: "## 群.md\n群主是王老师", owner: true)
        XCTAssertTrue(prompt.contains("蓝海乐：@蓝 群主是谁"))
        XCTAssertTrue(prompt.contains("群主是王老师"))
        XCTAssertTrue(prompt.contains("“@蓝”"))
        XCTAssertTrue(prompt.contains("reply 开头不要@人"))  // traces(38): replies start with what they say, no @
        XCTAssertFalse(prompt.contains("@发言人"))
        let bare = WatchSettings.composePrompt(chat: "张三", group: false, recent: lines, due: due, r: rules(), knowledge: "", owner: false)
        XCTAssertTrue(bare.contains("用户没有给知识库"))
        XCTAssertFalse(bare.contains("@发言人"))
        XCTAssertTrue(WatchSettings.interjectPrompt(chat: "客户群", recent: lines, r: rules()).contains("SKIP"))
        XCTAssertTrue(prompt.contains("主人"))
        XCTAssertTrue(prompt.contains(#""task":"#))
        XCTAssertTrue(bare.contains("不能给 task"))
    }

    func testTheOwnersRequestBecomesAPhoneTaskThatReallyMentions() {
        XCTAssertEqual(WatchReport.decision(#"{"reply":"","task":"查看群成员找出群主，并在群里@群主说：这是群主"}"#)?.task,
                       "查看群成员找出群主，并在群里@群主说：这是群主")
        XCTAssertEqual(WatchReport.decision(#"```json {"reply":"@蓝海乐 在的","task":""} ```"#)?.reply, "@蓝海乐 在的")
        XCTAssertEqual(WatchReport.decision("在的，有事吗")?.reply, "在的，有事吗")  // plain words still work
        XCTAssertNil(WatchReport.decision(#"{"reply": "半截"#))               // broken JSON is never typed
        let task = WatchSettings.ownerTask(chat: "客户群", task: "找出群主并@他")
        XCTAssertTrue(task.contains("群主就是成员头像里的第一个"))  // traces(39): WeChat shows no 群主 label to scroll for
        XCTAssertTrue(task.contains("在弹出的成员列表里找到并点选他"))
        XCTAssertTrue(task.contains("不准付款"))
    }

    func testTheReadLogKeepsEachDayAndFeedsTheSummary() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readlog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        ReadLog.append([ReadMessage(chat: "客户群", group: true, sender: "老板", text: "明天开会")], at: day, in: dir)
        ReadLog.append([ReadMessage(chat: "张三", group: false, sender: "张三", text: "在吗", replied: "在")], at: day, in: dir)
        let kept = ReadLog.messages(on: day, in: dir)
        XCTAssertEqual(kept.map(\.text), ["明天开会", "在吗"])
        let input = ReadLog.summaryInput(kept)
        XCTAssertTrue(input.contains("[群·客户群] 老板：明天开会"))
        XCTAssertTrue(input.contains("（已回复：在）"))
    }

    func testChatToolPacketsMatchTheRobotFormat() throws {
        XCTAssertEqual(ChatToolLink.socketURL("192.168.31.85:8881", robot: "lan_agent_iphone")?.absoluteString,
                       "ws://192.168.31.85:8881/webserver/wechat/lan_agent_iphone")
        XCTAssertNil(ChatToolLink.socketURL("", robot: "x"))
        let packet = try XCTUnwrap(ChatToolLink.packet(ReadMessage(chat: "客户群", group: true, sender: "老板", text: "你好", atMe: true)))
        let item = try XCTUnwrap(((try JSONSerialization.jsonObject(with: Data(packet.utf8)) as? [String: Any])?["list"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["titleList"] as? [String], ["客户群"])
        XCTAssertEqual(item["receivedName"] as? String, "老板")
        XCTAssertEqual(item["rawSpoken"] as? String, "你好")
        XCTAssertEqual(item["atMe"] as? String, "1")
        XCTAssertEqual(item["roomType"] as? Int, 3)
        let down = #"{"socketType":2,"list":[{"type":203,"titleList":["客户群"],"roomType":3,"receivedContent":"收到","textType":1},{"type":202}]}"#
        XCTAssertEqual(ChatToolLink.commands(down).map { [$0.chat, $0.text] }, [["客户群", "收到"]])
        XCTAssertEqual(ChatToolLink.commands("not json"), [])
    }

    private func object(_ packet: String?) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(XCTUnwrap(packet).utf8)) as? [String: Any])
    }

    /// 161 (小藍 iPad 版): the personal robot's socket protocol — base path kept, receipt, orders, results.
    func testXiaoLanOrdersGetAReceiptAndOneResultEach() throws {
        XCTAssertEqual(ChatToolLink.socketURL("127.0.0.1:18971/zwt", robot: "r1")?.absoluteString, "ws://127.0.0.1:18971/zwt/webserver/wechat/r1")
        XCTAssertEqual(ChatToolLink.socketURL("https://relay.example/relay/zwt/", robot: "r1")?.absoluteString,
                       "wss://relay.example/relay/zwt/webserver/wechat/r1")
        XCTAssertEqual(try object(ChatToolLink.heartbeatPacket())["socketType"] as? Int, 0)

        let link = ChatToolLink()
        let start = Date(timeIntervalSince1970: 100)
        let down = #"{"socketType":2,"messageId":"m1","list":[{"type":203,"titleList":["客户群","测试群"],"receivedContent":"收到","atList":["老板"]},{"type":202},{"type":299},{"type":204,"titleList":[]}]}"#
        let now = try link.accept(down, now: start).map(object)
        XCTAssertEqual(now.count, 3)  // receipt, 299 unknown, 204 without a chat
        XCTAssertEqual(now[0]["socketType"] as? Int, 1)
        XCTAssertEqual(now[0]["messageId"] as? String, "m1")
        let unsupported = try XCTUnwrap((now[1]["list"] as? [[String: Any]])?.first)
        XCTAssertEqual(now[1]["socketType"] as? Int, 3)
        XCTAssertEqual(unsupported["type"] as? Int, 299)
        XCTAssertEqual(unsupported["errorCode"] as? Int, ChatToolLink.otherError)
        XCTAssertEqual(((now[2]["list"] as? [[String: Any]])?.first)?["errorCode"] as? Int, ChatToolLink.badData)

        let first = try XCTUnwrap(link.nextCommand()), second = try XCTUnwrap(link.nextCommand())
        XCTAssertNil(link.nextCommand())
        XCTAssertEqual([first.chat, second.chat], ["客户群", "测试群"])
        XCTAssertEqual(first.at, ["老板"])
        XCTAssertEqual(first.messageId, "m1")
        XCTAssertNil(link.finish(first, ok: true, now: start.addingTimeInterval(2)))  // one chat of two: no result yet
        let result = try object(link.finish(second, ok: false, reason: ChatToolLink.reasonNotSent, now: start.addingTimeInterval(4.5)))
        let item = try XCTUnwrap((result["list"] as? [[String: Any]])?.first)
        XCTAssertEqual(result["socketType"] as? Int, 3)
        XCTAssertEqual(result["messageId"] as? String, "m1")
        XCTAssertEqual(item["type"] as? Int, 203)
        XCTAssertEqual(item["errorCode"] as? Int, ChatToolLink.sendFailed)
        XCTAssertEqual(item["errorReason"] as? String, ChatToolLink.reasonNotSent)
        XCTAssertEqual(item["successList"] as? [String], ["客户群"])
        XCTAssertEqual(item["failList"] as? [String], ["测试群"])
        XCTAssertEqual(item["runTime"] as? Int, 100_000)
        XCTAssertEqual(item["timeCost"] as? Double, 4.5)
        XCTAssertTrue((item["rawMsg"] as? String)?.contains("收到") == true)
        XCTAssertNil(link.finish(second, ok: true))  // already reported

        // 304 clears what is queued: each dropped order is answered, then the clear itself.
        link.accept(#"{"socketType":2,"messageId":"m2","list":[{"type":203,"titleList":["客户群"],"receivedContent":"在吗"}]}"#, now: start)
        let cleared = try link.accept(#"{"socketType":2,"messageId":"m3","list":[{"type":304}]}"#, now: start).map(object)
        XCTAssertNil(link.nextCommand())
        XCTAssertEqual(cleared.map { $0["messageId"] as? String }, ["m3", "m2", "m3"])
        XCTAssertEqual(((cleared[1]["list"] as? [[String: Any]])?.first)?["errorReason"] as? String, ChatToolLink.reasonCleared)
        XCTAssertEqual(((cleared[2]["list"] as? [[String: Any]])?.first)?["type"] as? Int, 304)
    }

    /// 161: every order of Android 小藍's two engines is taken; each becomes a task, a read or a local answer.
    func testXiaoLanTakesEveryOrderOfBothEngines() throws {
        let personal: Set<Int> = [201, 202, 203, 204, 205, 206, 207, 210, 212, 213, 214, 218, 219, 220, 221, 226, 231, 232, 241, 242, 243,
                                  260, 261, 263, 265, 304, 501, 502, 503, 504, 505, 507, 508, 509, 512]
        XCTAssertEqual(Set(XiaoLanOrders.personal.keys), personal)
        XCTAssertEqual(Set(XiaoLanOrders.wework.keys), Set(201...237).union([303, 304, 305]).union(501...514))
        let link: Set<Int> = [201, 202, 303, 304, 305]
        let full = XiaoLanOrders.Fields([
            "titleList": ["测试群"], "receivedContent": "你好", "originalContent": "原话", "receivedName": "老板", "nameList": ["客户群"],
            "groupName": "测试群", "selectList": ["张三", "李四"], "objectName": "报价单.pdf", "fileUrl": "https://example.com/a.jpg",
            "friend": ["name": "张三", "phone": "13800000000"], "messageList": [["originalContent": "第一条"]],
            "meta": #"{"runId":"r1","robotId":"b1","resultUrl":"https://example.com/gequan/result/r1","resultToken":"t","uploadUrl":"https://example.com/gequan/upload/r1","uploadToken":"u","params":{"friendName":"王五","text":"文案"}}"#,
        ] as [String: Any])
        for (app, table) in [(XiaoLanOrders.App.wechat, XiaoLanOrders.personal), (.wework, XiaoLanOrders.wework)] {
            for type in table.keys where !link.contains(type) {
                XCTAssertNil(XiaoLanOrders.problem(type, app, full), "\(app) \(type)")
                let job = try XCTUnwrap(XiaoLanOrders.job(type: type, app: app, f: full, chat: "测试群"), "\(app) \(type)")
                XCTAssertTrue(job.local != nil || !job.task.isEmpty, "\(app) \(type)")
                if job.local == nil {
                    XCTAssertTrue(job.task.contains(job.readOnly ? "只看不改" : "fail"), "\(app) \(type)")
                    XCTAssertEqual(job.task.contains("企业微信"), app == .wework, "\(app) \(type)")
                }
            }
        }
        // what the agent types is checked, files are fetched first, reads come back as JSON
        let send = try XCTUnwrap(XiaoLanOrders.job(type: 203, app: .wework, f: full, chat: "测试群"))
        XCTAssertEqual(send.texts, ["你好"])
        XCTAssertTrue(send.task.hasPrefix("先打开企业微信"))
        let file = try XCTUnwrap(XiaoLanOrders.job(type: 218, app: .wechat, f: full, chat: "测试群"))
        XCTAssertEqual(file.media, ["https://example.com/a.jpg"])
        XCTAssertEqual(file.mediaKind, .photos)
        XCTAssertEqual(XiaoLanOrders.mediaKind(fileType: "", url: "https://x/y/报价.pdf"), .files)
        XCTAssertTrue(try XCTUnwrap(XiaoLanOrders.job(type: 512, app: .wechat, f: full, chat: "测试群")).query)
        XCTAssertEqual(XiaoLanOrders.job(type: 513, app: .wework, f: full, chat: "")?.local, .resources)
        XCTAssertNil(XiaoLanOrders.job(type: 222, app: .wechat, f: full, chat: ""))  // 打卡 is WeCom's only

        // missing fields are answered at once, not tried
        XCTAssertNotNil(XiaoLanOrders.problem(206, .wechat, XiaoLanOrders.Fields(["groupName": "x"] as [String: Any])))
        XCTAssertNotNil(XiaoLanOrders.problem(213, .wework, XiaoLanOrders.Fields(["friend": ["name": "x"]] as [String: Any])))

        // a read's answer becomes the engines' bean
        let me = try XCTUnwrap(XiaoLanOrders.dataBean(type: 503, chat: "", f: full, answer: #"好了 {"name":"小蓝","alias":"lan01"}"#))
        XCTAssertEqual(me["type"] as? Int, 503)
        XCTAssertEqual((me["myInfo"] as? [String: Any])?["alias"] as? String, "lan01")
        let members = try XCTUnwrap(XiaoLanOrders.dataBean(type: 512, chat: "测试群", f: full, answer: #"{"nameList":["张三"]}"#))
        XCTAssertEqual(members["groupName"] as? String, "测试群")
        XCTAssertNil(XiaoLanOrders.dataBean(type: 505, chat: "", f: full, answer: "没读到"))

        // 跟圈: entries carry stable fingerprints; image posts go up as incomplete
        let entries = XiaoLanOrders.momentEntries(friend: "王五", answer: #"{"entries":[{"text":"新品到了","imageCount":3},{"text":"","summary":""}]}"#)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["imagesComplete"] as? Bool, false)
        XCTAssertEqual(entries[0]["fp"] as? String, XiaoLanOrders.fingerprint(["王五", "新品到了", ""].joined(separator: "\n")))
        XCTAssertEqual(XiaoLanOrders.fingerprint("a"), "af63dc4c8601ec8c")
        let run = try XCTUnwrap(XiaoLanOrders.job(type: 260, app: .wechat, f: full, chat: "王五")?.moments)
        XCTAssertEqual(run.resultURL?.absoluteString, "https://example.com/gequan/result/r1?robotId=b1&token=t")
        XCTAssertEqual(run.uploadURL?.absoluteString, "https://example.com/gequan/upload/r1?robotId=b1&token=u")
        XCTAssertTrue(XiaoLanOrders.openMomentPicture(friend: "王五", locate: "新品到了").contains("第一张图片"))
    }

    /// 164: 小藍 reads a chat with no model — the recognizer's lines and the colour each sits on (iPad WeChat 11-25).
    func testXiaoLanReadsAChatByTheBubbleColours() {
        XCTAssertEqual(WatchOCR.kind(of: (147, 236, 106)), .mine)
        XCTAssertEqual(WatchOCR.kind(of: (254, 254, 254)), .theirs)
        XCTAssertEqual(WatchOCR.kind(of: (237, 237, 237)), .grey)
        XCTAssertEqual(WatchOCR.titled("测试群(6)").name, "测试群")
        XCTAssertTrue(WatchOCR.titled("测试群（6）").group)
        XCTAssertFalse(WatchOCR.titled("蓝海乐").group)
        func at(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {  // pixels of the 960 x 1280 frame
            CGRect(x: x0 / 960, y: y0 / 1280, width: (x1 - x0) / 960, height: (y1 - y0) / 1280)
        }
        let pieces: [WatchOCR.Piece] = [
            .init(text: "昨天 05:20", box: at(432, 128, 528, 148), kind: .grey),
            .init(text: "@蓝海乐【小蓝测试】输入法提醒 5479", box: at(450, 205, 845, 228), kind: .mine),
            .init(text: "昨天 06:18", box: at(432, 300, 528, 320), kind: .grey),
            .init(text: "蓝海乐", box: at(97, 355, 146, 372), kind: .grey),
            .init(text: "在吗", box: at(115, 398, 160, 418), kind: .theirs),
            .init(text: "第二行", box: at(115, 421, 190, 441), kind: .theirs),  // the same bubble, wrapped
            .init(text: "柳掌柜(本人号)通过扫描加入群聊", box: at(222, 548, 738, 566), kind: .grey),
            .init(text: "好的", box: at(800, 620, 845, 642), kind: .mine),
        ]
        let screen = WatchOCR.lines(pieces, title: "测试群(6)")
        XCTAssertEqual(screen.title, "测试群")
        XCTAssertTrue(screen.group)
        XCTAssertEqual(screen.lines.map(\.sender), ["我", "蓝海乐", "我"])
        XCTAssertEqual(screen.lines.map(\.text), ["@蓝海乐【小蓝测试】输入法提醒 5479", "在吗第二行", "好的"])
        XCTAssertEqual(screen.lines.map(\.mine), [true, false, true])
        // a private chat: the other side is the chat itself, no names above bubbles
        let one = WatchOCR.lines([.init(text: "在吗", box: at(115, 398, 160, 418), kind: .theirs)], title: "蓝海乐")
        XCTAssertEqual(one.lines.first?.sender, "蓝海乐")
        XCTAssertFalse(one.group)
    }

    /// 165: the input box found on the screen, no model: the field just under the bar's top (iPad WeChat colours).
    func testXiaoLanFindsTheInputBoxByItsColours() throws {
        let size = CGSize(width: 300, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let frame = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 1) { ctx in
            UIColor(white: 237 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))  // the chat
            UIColor(white: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 40, y: 100, width: 120, height: 30))  // a white bubble: not the bar
            UIColor(white: 246 / 255, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 300, width: 300, height: 100))  // the input bar
            UIColor(white: 1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 20, y: 305, width: 260, height: 28))  // its field
        }
        let box = try XCTUnwrap(WatchOCR.inputBox(frame))
        XCTAssertEqual(box.x, 0.45, accuracy: 0.001)
        XCTAssertEqual(box.y, 0.777, accuracy: 0.01)
        XCTAssertEqual(ChatToolLink.reasonNoSteps.isEmpty, false)
    }

    /// 163: the engines' robot settings, QA callback and type-101 report (docs/xiaolan-engine-logic.md).
    func testXiaoLanQACallbackLikeTheEngines() throws {
        XCTAssertEqual(ChatToolLink.configURL("127.0.0.1:18971/zwt", robot: "r1")?.absoluteString,
                       "http://127.0.0.1:18971/zwt/robot/robotInfo/get?robotId=r1")
        XCTAssertEqual(ChatToolLink.httpBase("wss://relay.example/relay/zwt/"), "https://relay.example/relay/zwt")
        let cfg = try XCTUnwrap(ChatToolLink.robotConfig(Data(#"{"code":200,"data":{"openCallback":1,"callbackUrl":"http://x/cb","replyAll":-1,"robotType":1}}"#.utf8)))
        XCTAssertFalse(cfg.replyAll)
        let group = ReadMessage(chat: "群", group: true, sender: "张三", text: "你好", atMe: false)
        XCTAssertFalse(ChatToolLink.asksQA(group, config: cfg))  // replyAll -1: only @ in groups
        XCTAssertTrue(ChatToolLink.asksQA(ReadMessage(chat: "群", group: true, sender: "张三", text: "@小蓝 你好", atMe: true), config: cfg))
        XCTAssertTrue(ChatToolLink.asksQA(ReadMessage(chat: "张三", group: false, sender: "张三", text: "在吗", atMe: false), config: cfg))
        XCTAssertFalse(ChatToolLink.asksQA(ReadMessage(chat: "张三", group: false, sender: "me", text: "在", atMe: false), config: cfg))
        var all = cfg
        all.replyAll = true
        XCTAssertTrue(ChatToolLink.asksQA(group, config: all))
        all.autoReply = false
        XCTAssertFalse(ChatToolLink.asksQA(group, config: all))  // robotType 2
        XCTAssertNil(ChatToolLink.robotConfig(Data(#"{"code":500,"message":"no"}"#.utf8)))
        XCTAssertEqual(ChatToolLink.qaReply(Data(#"{"code":0,"data":{"info":{"text":" 收到 "}}}"#.utf8)), "收到")
        XCTAssertNil(ChatToolLink.qaReply(Data(#"{"code":0,"data":{"info":{"text":""}}}"#.utf8)))  // empty: do not reply
        let body = ChatToolLink.qaBody(group)
        XCTAssertEqual(body["spoken"] as? String, "你好")
        XCTAssertEqual(body["atMe"] as? String, "false")
        XCTAssertEqual(body["groupName"] as? String, "群")
        let packet = try object(ChatToolLink.packet(group))
        let item = try XCTUnwrap((packet["list"] as? [[String: Any]])?.first)
        XCTAssertEqual(packet["socketType"] as? Int, 2)
        XCTAssertEqual(item["type"] as? Int, 101)
        let sub = try XCTUnwrap((item["messageList"] as? [[String: Any]])?.first)
        XCTAssertEqual(sub["nameList"] as? [String], ["张三"])
        XCTAssertEqual(((sub["itemMessageList"] as? [[String: Any]])?.first)?["text"] as? String, "你好")
        XCTAssertTrue(ChatToolLink.isLocal("qa#1"))
        XCTAssertFalse(ChatToolLink.isLocal("m1"))
    }

    /// 162: the tool box builds the engines' orders; they run like a server's but answer only into the record.
    func testXiaoLanToolboxOrdersStayOnTheIPad() throws {
        for group in XiaoLanTools.groups {
            for tool in group.tools { XCTAssertFalse(tool.apps.isEmpty, "\(tool.type)") }
        }
        let item = XiaoLanTools.order(203, app: .wechat, values: ["titleList": "测试群，客户群", "receivedContent": " 你好 ", "atList": ""], toggles: [:])
        XCTAssertEqual(item["titleList"] as? [String], ["测试群", "客户群"])
        XCTAssertEqual(item["receivedContent"] as? String, "你好")
        XCTAssertNil(item["atList"])
        let friend = XiaoLanTools.order(213, app: .wework, values: ["friend.phone": "13800000000"], toggles: [:])
        XCTAssertEqual((friend["friend"] as? [String: Any])?["phone"] as? String, "13800000000")
        let many = XiaoLanTools.order(229, app: .wework, values: ["titleList": "群", "messages": "一\n二"], toggles: [:])
        XCTAssertEqual((many["messageList"] as? [[String: Any]])?.count, 2)

        let link = ChatToolLink()
        XCTAssertNotNil(link.enqueueLocal(["type": 203, "titleList": ["群"]]))  // no text: refused, nothing queued
        XCTAssertNil(link.enqueueLocal(item))
        XCTAssertEqual(link.pending.count, 2)
        let first = try XCTUnwrap(link.nextCommand()), second = try XCTUnwrap(link.nextCommand())
        XCTAssertTrue(first.messageId.hasPrefix(ChatToolLink.localPrefix))
        XCTAssertNil(link.finish(first, ok: true))
        XCTAssertNil(link.finish(second, ok: false, reason: "测试"))  // a tool-box order never makes a server packet
        XCTAssertTrue(link.history.last?.contains("✗ 发消息") == true)
        link.deliver(["type": 503, "myInfo": ["name": "小蓝"]], for: first)
        XCTAssertTrue(link.history.last?.contains("小蓝") == true)
        XCTAssertNotNil(link.enqueueLocal(["type": 222]))  // 打卡 is WeCom's only
    }

    /// 162: an iPad home pushes only a little past the top (from where the pointer is), never blindly.
    func testIPadHomeNeverPushesFarPastTheTop() {
        let span = (w: 3900, h: 5270)
        XCTAssertEqual(CommandChannel.padHome(from: (1000, 2000), span: span, locatedY: nil),
                       ["abort", "move -1300 0", "move 0 -2300"])
        // not known: the height seen on screen decides; left still goes all the way
        XCTAssertEqual(CommandChannel.padHome(from: nil, span: span, locatedY: 0.5), ["abort", "move -4200 0", "move 0 -2935"])
        XCTAssertNil(CommandChannel.padHome(from: nil, span: span, locatedY: nil))
        // tracking: moves clamp at the edges; anything that can move it unseen forgets it
        var p = CommandChannel.padTrack("move 500 700", from: (0, 0), span: span)
        XCTAssertEqual(p?.x, 500)
        XCTAssertEqual(p?.y, 700)
        p = CommandChannel.padTrack("stroke -900 0 0 9000", from: p, span: span)
        XCTAssertEqual(p?.x, 0)
        XCTAssertEqual(p?.y, 5270)
        XCTAssertEqual(CommandChannel.padTrack("click", from: (1, 2), span: span)?.y, 2)
        XCTAssertNil(CommandChannel.padTrack("abort", from: (1, 2), span: span))
        XCTAssertNil(CommandChannel.padTrack("flickhome", from: (1, 2), span: span))
        XCTAssertNil(CommandChannel.padTrack("move 5 5", from: nil, span: span))
    }

    /// 跟圈 pictures are kept as the viewer shows them: the black around them and the status bar are cut off.
    func testMomentPictureLosesTheViewerBlack() throws {
        let size = CGSize(width: 300, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let frame = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 1) { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 10, y: 4, width: 40, height: 6))  // status bar
            UIColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 100, width: 300, height: 200))  // the picture
        }
        let cut = try XCTUnwrap(UIImage(data: try XCTUnwrap(XiaoLanMedia.trimmed(frame))))
        XCTAssertEqual(cut.size.width, 300, accuracy: 3)
        XCTAssertEqual(cut.size.height, 200, accuracy: 4)
    }

    func testXiaoLanWeComLinkAndQueueOrders() throws {
        XCTAssertEqual(ChatToolLink.socketURL("127.0.0.1:18970/qiwei", robot: "w1", app: .wework)?.absoluteString,
                       "ws://127.0.0.1:18970/qiwei/webserver/wework/w1")
        let link = ChatToolLink(app: .wework)
        let start = Date(timeIntervalSince1970: 0)
        // one 218 to two chats: two commands; a 222 (WeCom only) is queued here
        link.accept(#"{"socketType":2,"messageId":"a","list":[{"type":218,"titleList":["甲","乙"],"fileUrl":"https://e/x.png"},{"type":222}]}"#, now: start)
        let first = try XCTUnwrap(link.nextCommand())
        XCTAssertEqual(first.app, .wework)
        XCTAssertEqual(first.type, 218)
        XCTAssertEqual(link.pending.map(\.chat), ["乙", "打卡"])
        // 305 removes queued orders by messageId and answers each
        let removed = try link.accept(#"{"socketType":2,"messageId":"b","list":[{"type":305,"selectList":["a"]}]}"#, now: start).map(object)
        XCTAssertTrue(link.pending.isEmpty)
        XCTAssertEqual(removed.map { $0["messageId"] as? String }, ["b", "a", "b"])
        // 303 is answered at once
        let test = try link.accept(#"{"socketType":2,"messageId":"c","list":[{"type":303}]}"#, now: start).map(object)
        XCTAssertEqual(((test.last?["list"] as? [[String: Any]])?.first)?["errorCode"] as? Int, 0)
        // a personal-only order on the WeCom link is not taken
        let personalOnly = try link.accept(#"{"socketType":2,"messageId":"d","list":[{"type":260,"meta":"{}"}]}"#, now: start).map(object)
        XCTAssertEqual(((personalOnly.last?["list"] as? [[String: Any]])?.first)?["errorCode"] as? Int, ChatToolLink.otherError)
        // a read's data goes up as socketType 2
        let data = try object(link.sendData(["type": 503, "myInfo": ["name": "小蓝"]]))
        XCTAssertEqual(data["socketType"] as? Int, 2)
    }

    func testComputerKnowledgeAddressesCarryTheToken() {
        let url = ComputerKnowledge.url("192.168.31.85:8882", "/files", [URLQueryItem(name: "token", value: "abc")])
        XCTAssertEqual(url?.absoluteString, "http://192.168.31.85:8882/files?token=abc")
        XCTAssertNil(ComputerKnowledge.url(" ", "/files", []))
    }

    func testPrivateWordsAndNumbersAreRefusedWithoutRepeatingThem() {
        let words = ["幸福路88号"]
        let reason = PrivacyGuard.check("我家在幸福路88号", words: words, numbers: true)
        XCTAssertNotNil(reason)
        XCTAssertFalse(reason!.contains("幸福路"))
        XCTAssertNotNil(PrivacyGuard.check("电话 138 1234 5678", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("010-1234-5678", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("身份证 11010519491231002X", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("卡号 6222021234567890123", words: [], numbers: true))
        XCTAssertNotNil(PrivacyGuard.check("邮箱 me@example.com", words: [], numbers: true))
        XCTAssertNil(PrivacyGuard.check("好的，明天下午 3 点见，订单 2 件", words: words, numbers: true))
        XCTAssertNil(PrivacyGuard.check("电话 13812345678", words: [], numbers: false))
    }

    func testOnlyTheChosenKnowledgeFilesAreUsedAndLongTextIsCut() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "营业时间：每天 10 点到 22 点".write(to: dir.appendingPathComponent("营业.md"), atomically: true, encoding: .utf8)
        try "私人日记".write(to: dir.appendingPathComponent("日记.md"), atomically: true, encoding: .utf8)
        let used = KnowledgeBase.text(["营业.md"], in: dir)
        XCTAssertTrue(used.text.contains("营业时间"))
        XCTAssertFalse(used.text.contains("私人日记"))
        XCTAssertFalse(used.truncated)
        XCTAssertTrue(KnowledgeBase.text(["营业.md"], in: dir, limit: 5).truncated)
    }

    func testARefusedReplyIsNeverTypedAndTheKnowledgeReachesTheModel() async {
        let model = SystemRecorder { n in
            n == 1 ? "1. reply" : n == 2 ? "THINK: answer\nDO: type 我的电话是13812345678" : "THINK: rewritten\nDO: done ok"
        }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.reference = "## 营业.md\n营业时间：每天 10 点到 22 点"
        agent.outgoingGuard = { PrivacyGuard.check($0, words: [], numbers: true) }
        await agent.run()
        XCTAssertFalse(phone.calls.contains("type"))
        XCTAssertTrue(agent.steps.contains { $0["action"]?.str == "blocked" })
        XCTAssertTrue(model.systems[0].contains("营业时间"))  // planner
        XCTAssertTrue(model.systems[1].contains("营业时间"))  // actor
    }
}
