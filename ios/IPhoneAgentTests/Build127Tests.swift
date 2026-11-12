import XCTest
@testable import IPhoneAgent

/// Build 127: from 126's regression on the phone (11-12).
@MainActor final class Build127Tests: XCTestCase {

    /// User 11-12: Claude as the backup planner, with an Anthropic API key.
    func testAClaudeRequestAndItsAnswer() {
        let body = ClaudeChat.body(model: "claude-opus-5-5", system: "s", text: "t", image: Data([0xFF, 0xD8]))
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertNil(body["temperature"], "API version 2026-10-21 refuses it")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        let content = ((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        XCTAssertEqual(content.first?["type"] as? String, "image")
        XCTAssertEqual(content.last?["text"] as? String, "t")
        XCTAssertNil(ClaudeChat.body(model: "claude-haiku-5-5", system: "s", text: "t", image: nil)["fallbacks"])
        let reply = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"PLAN"}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(ClaudeChat.text(Data(reply.utf8)).text, "PLAN")
        XCTAssertEqual(ClaudeChat.text(Data(reply.utf8)).stop, "end_turn")
    }

    /// User 11-12: the backup plans before 豆包, and one that failed rests.
    func testTheBackupPlansBeforeDoubaoAndRestsAfterAFailure() async throws {
        final class Failing: ChatModel {
            let model = "backup"
            var calls = 0
            func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
                calls += 1
                throw LLMError(message: "HTTP 429")
            }
        }
        let backup = Failing(), doubao = FakeModel { _ in "doubao" }, rest = PlusRest()
        let chain = ModelChain([backup, doubao], rests: [rest, nil])
        let first = try await chain.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(first.text, "doubao")
        XCTAssertTrue(rest.resting)
        _ = try await chain.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(backup.calls, 1, "a backup that failed is not asked again at once")
        let answering = ModelChain([FakeModel { _ in "backup" }, doubao], rests: [PlusRest(), nil])
        let answered = try await answering.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(answered.text, "backup")
    }

    /// User 11-12: "登錄兩個 codex，一個額度用完自動切換另一個".
    func testASecondCodexAccountPlansWhenTheFirstIsOutOfQuota() async throws {
        let one = PlusRest(), two = PlusRest()
        var said: [String] = [], asked: [String] = []
        one.onFailure = { said.append($0) }
        let t1 = ChatGPTPlus.Tokens(idToken: "i", accessToken: "a1", refreshToken: "r1", accountID: "1")
        let t2 = ChatGPTPlus.Tokens(idToken: "i", accessToken: "a2", refreshToken: "r2", accountID: "2")
        var secondOut = false
        let second = PlusChat.Account(name: "2", tokens: { t2 }, save: { _ in }, rest: two)
        let plus = PlusChat(model: "m", fallback: FakeModel { _ in "doubao" }, tokens: { t1 }, save: { _ in },
                            ask: { tokens, _, _, _, _ in
                                asked.append(tokens.accessToken)
                                if tokens.accessToken == "a1" || secondOut { throw ChatGPTPlus.Failure(message: "HTTP 429：usage limit") }
                                return (ChatGPTPlus.Answer(text: "plan", model: "m", firstTokenMs: 1, totalMs: 2, quota: [:]), tokens)
                            }, rest: one, second: second)
        let first = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(first.text, "plan")
        XCTAssertEqual(asked, ["a1", "a2"])
        XCTAssertEqual(plus.lastAccount, "2")
        XCTAssertTrue(one.resting, "account 1 rests after its 429")
        XCTAssertEqual(said.count, 1)
        XCTAssertTrue(said[0].contains("帳號 2"), said[0])
        _ = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(asked, ["a1", "a2", "a2"], "account 1 rests: account 2 straight away")
        // account 2 out too: Doubao plans, and the user is told once
        secondOut = true
        let last = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(last.text, "doubao")
        XCTAssertNil(plus.lastAccount)
        XCTAssertTrue(said.last?.contains("豆包") == true)
    }

    /// User 11-12: a message from the owner while a task runs is seen by its banner, and only a listed sender's.
    func testTheOwnersBannerDuringATaskIsSeen() {
        func row(_ pieces: (String, Double, Double)...) -> [CandidatePicker.Piece] {
            pieces.map { CandidatePicker.Piece(text: $0.0, box: CGRect(x: $0.1, y: $0.2 - 0.01, width: 0.2, height: 0.02)) }
        }
        // iOS's banner over 美团: icon at the left, the group, the time at the right, the message under it
        let group = [row(("测试群", 0.19, 0.075), ("现在", 0.86, 0.075)), row(("主人蓝海乐: @蓝 帮我查首尔天气", 0.19, 0.105)),
                     row(("美团外卖", 0.40, 0.17))]
        let seen = WatchReport.banner(rows: group)
        XCTAssertEqual(seen?.title, "测试群")
        XCTAssertEqual(seen?.body, "主人蓝海乐:@蓝帮我查首尔天气")
        let targets = ["测试群", "主人蓝海乐"], senders = ["主人蓝海乐", "蓝海乐"]
        XCTAssertEqual(seen.flatMap { WatchReport.bannerChat($0, targets: targets, senders: senders) }, "测试群")
        // someone else in the group, a private chat with the owner, a chat not listed
        XCTAssertNil(WatchReport.bannerChat(("测试群", "清青:[语音]"), targets: targets, senders: senders))
        XCTAssertEqual(WatchReport.bannerChat(("主人蓝海乐", "在吗"), targets: targets, senders: senders), "主人蓝海乐")
        XCTAssertNil(WatchReport.bannerChat(("虾笔刀陪跑学员元群", "主人蓝海乐:哈哈"), targets: targets, senders: senders))
        // a chat's own title is centred, with the first message far below it: no banner
        let chat = [row(("测试群(3)", 0.42, 0.088)), row(("主人蓝海乐", 0.17, 0.175))]
        XCTAssertNil(WatchReport.banner(rows: chat))
    }

    /// 126 in 测试群: "@蓝 这是哪个城市" came in as the watch left the chat after the picture before it, with no red mark.
    /// The list line is checked against the last message read there.
    func testAListLineThatIsNotTheLastMessageReadIsSeen() {
        let picture = WatchReport.Line(sender: "主人蓝海乐", text: "[图片]", mine: false)
        let asked = WatchReport.Line(sender: "主人蓝海乐", text: "@蓝 这是哪个城市", mine: false)
        let body = WatchReport.previewBody("主人蓝海乐: @蓝 这是哪个城市")
        XCTAssertFalse(WatchReport.previewShows(body, picture))
        XCTAssertTrue(WatchReport.previewShows(body, asked))
        // cut short, a tag before it, a private chat with no sender, a voice
        XCTAssertTrue(WatchReport.previewShows(WatchReport.previewBody("[有人@我] 主人蓝海乐: @蓝 这是哪个城…"), asked))
        XCTAssertTrue(WatchReport.previewShows(WatchReport.previewBody("截图城市是：首尔"),
                                               WatchReport.Line(sender: "", text: "截图城市是：首尔", mine: true)))
        XCTAssertTrue(WatchReport.previewShows(WatchReport.previewBody("主人蓝海乐: [语音]"),
                                               WatchReport.Line(sender: "主人蓝海乐", text: "[语音] 首尔明天几度", mine: false)))
        XCTAssertEqual(WatchReport.previewBody("[草稿] 收到"), "")
        // a different question is not the one read
        XCTAssertFalse(WatchReport.previewShows(body, WatchReport.Line(sender: "主人蓝海乐", text: "@蓝 这张图是哪个城市", mine: false)))
    }

    /// 126 in 测试群: "把它往下拖一下关闭" came with a swipe up. A page scrolled "往下滑" is not turned.
    func testADragDownToCloseAPictureGoesDown() {
        XCTAssertTrue(AgentLoop.saysDragDown("按任务要求，看完图片后把它往下拖一下关闭，回到聊天。"))
        XCTAssertTrue(AgentLoop.saysDragDown("A picture shown full screen: drag it down to close it."))
        XCTAssertFalse(AgentLoop.saysDragDown("往下滑看更多商品"))
        XCTAssertFalse(AgentLoop.saysDragDown("Swipe down the list to see more chats."))
    }

    /// 126 over the cloud (g3): cn.bing.com typed in Safari for a goal that also posts to 测试群 was held as a message.
    func testAnAddressTypedOutsideAChatIsNotAMessage() {
        let goal = "帮我做这两件事：1. 用 Safari 搜索“今天油价”，记下第一个结果的标题；2. 在微信测试群发“G3全部做完”"
        XCTAssertFalse(AgentLoop.needsApproval("cn.bing.com", task: goal, chatApp: false))
        XCTAssertFalse(AgentLoop.needsApproval("https://www.baidu.com/", task: goal, chatApp: false))
        XCTAssertTrue(AgentLoop.needsApproval("G3全部做完", task: goal, chatApp: true))
        // the goal's message is an address: still a message, and in a chat app anything typed may be one
        XCTAssertTrue(AgentLoop.needsApproval("cn.bing.com", task: "在测试群发“cn.bing.com”", chatApp: false))
        XCTAssertTrue(AgentLoop.needsApproval("cn.bing.com", task: goal, chatApp: true))
    }

    /// 126 over the cloud (g7): a part the thought called finished stayed open, and the run went back to it for 56 steps.
    func testAPartTheThoughtCallsFinishedIsDone() {
        let part = "18. 新建一条备忘录，第一行写“第7组记录”，下面写第1到第17项的结果"
        XCTAssertTrue(AgentLoop.saysPartDone("备忘录已完整写入第1至17项结果，第18项完成。接下来打开微信。", part: 5, text: part))
        XCTAssertTrue(AgentLoop.saysPartDone("备忘录已打开，第5部分完成，接下来要在微信测试群发送", part: 5, text: part))
        XCTAssertTrue(AgentLoop.saysPartDone("Part 5 done; now open WeChat.", part: 5, text: part))
        XCTAssertFalse(AgentLoop.saysPartDone("第17项已写入，接下来保存。", part: 5, text: part))
        XCTAssertFalse(AgentLoop.saysPartDone("第4部分完成", part: 5, text: part))
    }

    /// 126 over the cloud (g6): 加入购物车 was tapped again and again after the "added" toast.
    func testAddingToACartStopsAtWhatTheGoalAsks() {
        let g6 = "4. 在淘宝搜索“蓝牙耳机”，在前5个商品里挑价格最低的一个，选第一个颜色或规格，加入购物车一件，再打开购物车确认它在里面、数量是1"
        XCTAssertEqual(AgentLoop.cartWanted(g6), 1)
        XCTAssertEqual(AgentLoop.cartWanted("在美团外卖把两杯奶茶加入购物车，再加购一份薯条"), 3)
        XCTAssertEqual(AgentLoop.cartWanted("在天气看深圳"), 1)
        XCTAssertTrue(AgentLoop.addsToCart("规格弹窗已选中【基础款｜黑色】，数量为1，直接点加入购物车完成加购。"))
        XCTAssertTrue(AgentLoop.addsToCart("The spec sheet is open; I tap 加入购物车 once."))
        XCTAssertFalse(AgentLoop.addsToCart("我已多次点击加入购物车，先点右上角的X关闭弹窗，再去购物车确认。"))
        XCTAssertFalse(AgentLoop.addsToCart("点击底部导航栏的“购物车”图标，进入购物车页面。"))
        XCTAssertFalse(AgentLoop.addsToCart("购物车里有3件，点 − 减到1件。"))
    }

    /// 126 over the cloud (g5): a long note quoting a message sent a moment before is not that message.
    func testANoteQuotingASentMessageIsNotThatMessage() {
        let note = "第5组记录\n1. 北京今天最高15°最低3°\n8. 已在微信测试群发送“G5买东西做完”\n9. 高德到福田站16.7公里39分钟"
        XCTAssertNil(AgentLoop.sameMessage(note, in: ["G5买东西做完"]))
        XCTAssertEqual(AgentLoop.sameMessage("@蓝海乐 G5买东西做完", in: ["G5买东西做完"]), "G5买东西做完")
    }

    /// 126 in 测试群: the answered voice was read again as new, once with its length and once without.
    func testAVoiceIsTheSameWithOrWithoutItsLength() {
        let a = WatchReport.Line(sender: "蓝海乐", text: "[语音] 2\" 嘿，你能聽到我說話嗎？", mine: false)
        let b = WatchReport.Line(sender: "蓝海乐", text: "[语音] 嘿，你能聽到我說話嗎？", mine: false)
        XCTAssertEqual(WatchReport.key(a), WatchReport.key(b))
        XCTAssertTrue(WatchReport.new([a], history: [b]).isEmpty)
    }

    /// 126 in 测试群: the list stayed scrolled with the pinned 测试群 half under the title bar.
    func testAChatListScrolledPastItsTopIsSeen() {
        func piece(_ text: String, _ x: Double, _ y: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: text, box: CGRect(x: x, y: y - 0.01, width: 0.3, height: 0.02))]
        }
        let rest = [piece("蓝海乐", 0.2, 0.30), piece("能听到，你好呀。", 0.2, 0.33)]
        let cut = [piece("测试群", 0.2, 0.122), piece("蓝海乐发的图片是一张天气截图", 0.2, 0.151)] + rest
        let top = [piece("搜尋", 0.45, 0.148), piece("测试群", 0.2, 0.21), piece("蓝海乐发的图片是一张天气截图", 0.2, 0.24)] + rest
        let noSearch = [piece("测试群", 0.2, 0.145), piece("蓝海乐发的图片是一张天气截图", 0.2, 0.175)] + rest
        let titleGone = [piece("蓝海乐发的图片是一张天气截图", 0.2, 0.115)] + rest
        XCTAssertTrue(WatchChatOpen.isScrolled(cut))
        XCTAssertFalse(WatchChatOpen.isScrolled(top))
        XCTAssertFalse(WatchChatOpen.isScrolled(noSearch))
        XCTAssertTrue(WatchChatOpen.isScrolled(titleGone))
    }
}
