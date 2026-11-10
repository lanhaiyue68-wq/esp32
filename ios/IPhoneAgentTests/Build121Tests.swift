import XCTest
@testable import IPhoneAgent

/// Build 121 (user 11-11): the WeChat assistant. What a stress test on build 120 found ("誰發的" and "評論數" held as
/// sending), and what was asked for: images, videos, links and 视频号 looked at for the owner, a video's spoken words
/// (listen), chats followed and summed up, the owner proven by name, passphrase and WeChat ID, and the owner's tools
/// (GitHub, the customer's server).
@MainActor final class Build121Tests: XCTestCase {

    // MARK: - what counts as sending

    func testAskingForCountsOrWhoPostedIsNotSending() {
        XCTAssertFalse(AgentLoop.publishes("打開抖音第一個影片，告訴我影片是誰發的"))
        XCTAssertFalse(AgentLoop.publishes("告訴我這個影片的按讚、評論、收藏、轉發各是多少"))
        XCTAssertFalse(AgentLoop.publishes("給我看這個視頻的點讚評論收藏轉發數據"))
        XCTAssertFalse(AgentLoop.publishes("跟我說一下今天深圳的天氣"))
        XCTAssertFalse(AgentLoop.publishes("用 Safari 打開 www.163.com，告訴我第一條新聞標題"))
    }

    func testWaysOfSayingSendStillCount() {
        XCTAssertTrue(AgentLoop.publishes("在微信打開测试群，發一則訊息：你好"))
        XCTAssertTrue(AgentLoop.publishes("在小紅書第一篇筆記下留言：好看"))
        XCTAssertTrue(AgentLoop.publishes("把結果發到微信测试群"))
        XCTAssertTrue(AgentLoop.publishes("用微信傳送「你好」給测试群"))
        XCTAssertTrue(AgentLoop.publishes("跟張三說一聲明天開會"))
        XCTAssertTrue(AgentLoop.publishes("告訴大家明天放假"))
        XCTAssertTrue(AgentLoop.publishes("在测试群发一则消息：你好"))
        XCTAssertFalse(AgentLoop.publishes("打開小紅書搜尋杭州旅遊。不要按讚，不要留言"))
    }

    func testAReadOnlyOwnerTaskSendsNothingAndMaySearch() {
        let look = WatchSettings.ownerTask(chat: "测试群", task: "看看这个视频的点赞数和口播文案", phone: true, readOnly: true)
        XCTAssertFalse(AgentLoop.publishes(look), "its own rules must not read as sending")
        XCTAssertFalse(AgentLoop.needsApproval("杭州旅游", task: look, chatApp: false), "a search typed in 抖音")
        XCTAssertTrue(AgentLoop.needsApproval("杭州旅游", task: look, chatApp: true), "typing in WeChat is held (and refused)")
        XCTAssertTrue(look.contains("只读任务") && look.contains("listen"), look)
        XCTAssertFalse(look.contains("@某人"), "no instructions for sending")
        let phone = WatchSettings.ownerTask(chat: "测试群", task: "打开天气看深圳", phone: true)
        XCTAssertFalse(phone.contains("只读任务"))
    }

    // MARK: - listen

    func testListenIsAnAction() throws {
        XCTAssertEqual(try Actions.parseCommand("listen 30"), ["action": .str("listen"), "seconds": .int(30)])
        XCTAssertEqual(try Actions.parseCommand("listen"), ["action": .str("listen"), "seconds": .int(60)])
    }

    func testWhatIsHeardGoesIntoTheNotes() async {
        var turn = 0
        let replies = ["THINK: 听视频\nDO: listen 10", "THINK: 听完了\nDO: done 视频说了你好"]
        let actor = FakeModel { _ in defer { turn += 1 }; return replies[min(turn, replies.count - 1)] }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: FakeModel { _ in "1. 听视频" }, trace: nil)
        var asked: [Double] = []
        agent.listen = { seconds in asked.append(seconds); return "【语音转文字】你好\n【画面字幕】（没有）" }
        agent.showMock(task: "听这个视频讲了什么", plan: "", steps: [], running: false)
        await agent.run()
        XCTAssertEqual(asked, [10])
        XCTAssertTrue(agent.notes.contains { $0.hasPrefix("听到和字幕（10 秒）：【语音转文字】你好") }, "\(agent.notes)")
    }

    func testSubtitlesAreWordsKeptOnce() {
        XCTAssertTrue(ScreenListener.subtitle("今天我们来聊一聊怎么做饭"))
        XCTAssertFalse(ScreenListener.subtitle("1.2万"), "a count")
        XCTAssertFalse(ScreenListener.subtitle("@蓝海乐的日常"), "a handle")
        XCTAssertFalse(ScreenListener.subtitle("分享"), "a button")
        var seen = ScreenListener.merge([], "今天我们来聊一聊怎么做饭")
        seen = ScreenListener.merge(seen, "今天我们来聊一聊怎么做饭")
        seen = ScreenListener.merge(seen, "第一步先把水烧开")
        XCTAssertEqual(seen, ["今天我们来聊一聊怎么做饭", "第一步先把水烧开"])
    }

    // MARK: - who may ask

    private var rules: WatchSettings.Rules {
        WatchSettings.Rules(targets: ["测试群", "主人蓝海乐"], onlyListed: true, senders: ["主人蓝海乐"], passphrases: ["芝麻开门"],
                            myNames: ["小蓝"], lookTasks: true)
    }

    func testTheOwnerMayAskToLookByTheNameThisPhoneShows() {
        let at = ReadMessage(chat: "测试群", group: true, sender: "主人蓝海乐", text: "@小蓝 看看这个视频讲了什么")
        XCTAssertTrue(WatchSettings.lookOwner(at, rules))
        var plain = at; plain.text = "看看这个视频讲了什么"
        XCTAssertFalse(WatchSettings.lookOwner(plain, rules), "in a group: an @ or a passphrase")
        plain.text = "芝麻开门 看看这个视频"
        XCTAssertTrue(WatchSettings.lookOwner(plain, rules))
        var other = at; other.sender = "蓝海乐"
        XCTAssertFalse(WatchSettings.lookOwner(other, rules), "the name others see is not the owner's remark")
        let direct = ReadMessage(chat: "主人蓝海乐", group: false, sender: "主人蓝海乐", text: "[图片]")
        XCTAssertTrue(WatchSettings.lookOwner(direct, rules))
        var off = rules; off.lookTasks = false
        XCTAssertFalse(WatchSettings.lookOwner(direct, off))
        XCTAssertEqual(WatchSettings.bare("@小蓝 芝麻开门 确认", rules), "确认")
    }

    func testAnAttachmentOnItsOwnSaysWhatToDo() {
        XCTAssertTrue(WatchSettings.lookDefault("[图片]")?.contains("图片") == true)
        XCTAssertTrue(WatchSettings.lookDefault("[视频]")?.contains("口播文案") == true)
        XCTAssertTrue(WatchSettings.lookDefault("[视频号] 某某的分享")?.contains("视频号") == true)
        XCTAssertNotNil(WatchSettings.lookDefault("[链接] 杭州三天两夜怎么玩"))
        XCTAssertNotNil(WatchSettings.lookDefault("https://v.douyin.com/abc123/ 复制此链接，打开Dou音搜索，直接观看视频"))
        XCTAssertNil(WatchSettings.lookDefault("[链接] 帮我总结一下"), "the sender's words ask: the model reads them")
        XCTAssertNil(WatchSettings.lookDefault("今天晚上吃什么"))
    }

    func testTheWeChatIDIsReadUnderTheName() {
        func row(_ text: String, _ y: Double) -> [CandidatePicker.Piece] {
            [CandidatePicker.Piece(text: text, box: CGRect(x: 0.3, y: y, width: 0.4, height: 0.03))]
        }
        XCTAssertEqual(WatchSettings.weChatID(rows: [row("蓝海乐", 0.15), row("微信号：lanhaile_686", 0.2), row("地区：广东 深圳", 0.24)]),
                       "lanhaile_686")
        XCTAssertNil(WatchSettings.weChatID(rows: [row("微信号：lanhaile_686", 0.15)]), "a name that looks like an ID")
        XCTAssertNil(WatchSettings.weChatID(rows: [row("蓝海乐", 0.15), row("微信号：12", 0.2)]))
        XCTAssertTrue(WatchSettings.sameID("lanhaiLe_686", "1anhaile_686"), "l and 1 read alike")
        XCTAssertTrue(WatchSettings.sameID("abcO12", "abc012"))
        XCTAssertFalse(WatchSettings.sameID("abc123x", "abc124x"))
        XCTAssertFalse(WatchSettings.sameID("", ""))
    }

    func testALongAnswerGoesOutInPieces() {
        let sentence = String(repeating: "这是一句口播文案里的话", count: 3) + "。"
        let text = String(repeating: sentence, count: 50)  // 1700 characters: more than five pieces hold
        let parts = WatchSettings.chunks(text)
        XCTAssertEqual(parts.count, 5)
        XCTAssertTrue(parts.allSatisfy { $0.count <= 280 + 6 }, "\(parts.map(\.count))")
        XCTAssertTrue(parts.dropLast().allSatisfy { $0.hasSuffix("。") }, "cut at sentence ends")
        XCTAssertTrue(parts.last?.hasSuffix("（后面省略）") == true)
        XCTAssertEqual(WatchSettings.chunks("短话"), ["短话"])
        XCTAssertEqual(WatchSettings.chunks("  "), [])
    }

    func testFollowedChatsAreReadNotAnswered() {
        var r = WatchSettings.Rules(targets: ["测试群"], onlyListed: false, follow: ["家人群"])
        XCTAssertTrue(WatchSettings.readOnly("家人群", group: false, r))
        XCTAssertTrue(WatchSettings.openTask(r).contains("“家人群”"))
        r.follow = []
        XCTAssertFalse(WatchSettings.readOnly("家人群", group: false, r))
        var look = WatchSettings.Rules(targets: ["测试群"], senders: ["主人蓝海乐"], lookTasks: true)
        XCTAssertTrue(WatchTaskReply(chat: "测试群", sender: "主人蓝海乐", text: "好了").canDeliver(look, watching: true))
        look.lookTasks = false
        XCTAssertFalse(WatchTaskReply(chat: "测试群", sender: "主人蓝海乐", text: "好了").canDeliver(look, watching: true))
    }

    func testTheLookPromptAsksForATask() {
        let due = [ReadMessage(chat: "测试群", group: true, sender: "主人蓝海乐", text: "@小蓝 这个视频讲了什么")]
        let prompt = WatchSettings.composePrompt(chat: "测试群", group: true, recent: [], due: due, r: rules, knowledge: "",
                                                 owner: false, look: true)
        XCTAssertTrue(prompt.contains("主人要你去看"), prompt)
        XCTAssertTrue(prompt.contains("手机上"), prompt)
        let plain = WatchSettings.composePrompt(chat: "测试群", group: true, recent: [], due: due, r: rules, knowledge: "", owner: false)
        XCTAssertFalse(plain.contains("主人要你去看"))
    }

    // MARK: - the read log

    func testRecentReadsComeFromTheLog() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("readlog-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date()
        func put(_ chat: String, _ text: String, hoursAgo: Double) {
            let at = now.addingTimeInterval(-hoursAgo * 3600)
            ReadLog.append([ReadMessage(chat: chat, group: true, sender: "张三", text: text, at: at)], at: at, in: dir)
        }
        put("测试群", "昨天的事", hoursAgo: 30)
        put("测试群", "今天开会", hoursAgo: 2)
        put("家人群", "吃饭了吗", hoursAgo: 1)
        XCTAssertEqual(ReadLog.recent(chat: "测试群", hours: 24, now: now, in: dir).map(\.text), ["今天开会"])
        XCTAssertEqual(ReadLog.recent(chat: "测试群", hours: 48, now: now, in: dir).map(\.text), ["昨天的事", "今天开会"])
        XCTAssertEqual(ReadLog.recent(chat: nil, hours: 24, now: now, in: dir).count, 2)
        XCTAssertTrue(ReadLog.chatSummaryPrompt(chat: "测试群", hours: 24).contains("“测试群”"))
    }

    // MARK: - the owner's tools

    private let post = OwnerTools.Endpoint(name: "发码", method: "POST", url: "https://x.example.com/codes", about: "生成激活码")
    private let get = OwnerTools.Endpoint(name: "查码", method: "GET", url: "https://x.example.com/codes?a=1", about: "")

    func testToolsAreListedInSettings() {
        XCTAssertEqual(OwnerTools.repos(from: "a/b\n 不是仓库\nowner/repo-2 \nhttps://github.com/x/y"), ["a/b", "owner/repo-2"])
        let parsed = OwnerTools.endpoints(from: "发码 | post | https://x.example.com/codes | 生成激活码\n坏的 | GET | ftp://x\n只有名字")
        XCTAssertEqual(parsed, [post])
    }

    func testWhetherAToolIsWantedIsDecidedWithoutAModel() {
        XCTAssertTrue(OwnerTools.wants("这个群最近在聊什么", repos: [], endpoints: []))
        XCTAssertFalse(OwnerTools.wants("总结一下这个视频讲了什么", repos: [], endpoints: []), "the phone's work")
        XCTAssertTrue(OwnerTools.wants("看看仓库最近的编译", repos: ["a/b"], endpoints: []))
        XCTAssertFalse(OwnerTools.wants("看看仓库最近的编译", repos: [], endpoints: []), "no repositories listed")
        XCTAssertTrue(OwnerTools.wants("发码给张三", repos: [], endpoints: [post]))
        XCTAssertFalse(OwnerTools.wants("打开天气看看深圳", repos: ["a/b"], endpoints: [post]))
    }

    func testTheModelsChoiceIsChecked() {
        let call = { (reply: String) in OwnerTools.call(from: reply, chat: "测试群", repos: ["a/b"], endpoints: [self.post, self.get]) }
        XCTAssertEqual(call(#"{"tool":"github_runs","repo":"b"}"#), .githubRuns(repo: "a/b"))
        XCTAssertNil(call(#"{"tool":"github_file","repo":"evil/x","path":"README.md"}"#), "a repository that is not listed")
        XCTAssertNil(call(#"{"tool":"github_search","repo":"a/b","query":""}"#))
        XCTAssertEqual(call(#"{"tool":"summary","chat":"","hours":12}"#), .summary(chat: "测试群", hours: 12))
        XCTAssertEqual(call(#"{"tool":"summary","chat":"家人群","hours":500}"#), .summary(chat: "家人群", hours: 72))
        XCTAssertEqual(call(#"好的 {"tool":"api","name":"发码","args":{"n":2}}"#), .api(post, json: #"{"n":2}"#))
        XCTAssertNil(call(#"{"tool":"api","name":"删库","args":{}}"#), "an endpoint that is not configured")
        XCTAssertNil(call(#"{"tool":"none"}"#))
    }

    func testWhatChangesSomethingWaitsForConfirmation() {
        XCTAssertTrue(OwnerTools.needsConfirmation(.api(post, json: "{}")))
        XCTAssertFalse(OwnerTools.needsConfirmation(.api(get, json: "{}")))
        XCTAssertFalse(OwnerTools.needsConfirmation(.githubRuns(repo: "a/b")))
        XCTAssertFalse(OwnerTools.needsFullOwner(.summary(chat: "测试群", hours: 24)))
        XCTAssertTrue(OwnerTools.needsFullOwner(.githubRuns(repo: "a/b")))
        XCTAssertTrue(OwnerTools.isConfirmation("确认"))
        XCTAssertTrue(OwnerTools.isConfirmation(" 確認。"))
        XCTAssertFalse(OwnerTools.isConfirmation("确认一下这是什么"))
    }

    func testGitHubIsAskedWithTheToken() async {
        var asked: [URLRequest] = []
        let commits = #"[{"commit":{"message":"fix: 修好发送\n细节","author":{"name":"lan","date":"2026-11-11T01:00:00Z"}}}]"#
        let out = await OwnerTools.run(.githubCommits(repo: "a/b"), githubToken: "t", apiToken: "", fetch: { request in
            asked.append(request)
            return (Data(commits.utf8), 200)
        })
        XCTAssertTrue(out.contains("lan：fix: 修好发送"), out)
        XCTAssertFalse(out.contains("细节"), "the first line of a commit message")
        XCTAssertEqual(asked.first?.url?.path, "/repos/a/b/commits")
        XCTAssertEqual(asked.first?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        let denied = await OwnerTools.run(.githubRuns(repo: "a/b"), githubToken: "t", apiToken: "", fetch: { _ in (Data(), 401) })
        XCTAssertTrue(denied.contains("401"), denied)
        let none = await OwnerTools.run(.githubRuns(repo: "a/b"), githubToken: "", apiToken: "", fetch: { _ in (Data(), 200) })
        XCTAssertTrue(none.contains("还没有填"), none)
    }

    func testAnEndpointIsCalledAsListed() async throws {
        var asked: [URLRequest] = []
        let got = await OwnerTools.run(.api(get, json: #"{"n":2}"#), githubToken: "", apiToken: "k", fetch: { request in
            asked.append(request)
            return (Data("剩余 8 个".utf8), 200)
        })
        XCTAssertEqual(got, "剩余 8 个")
        let url = try XCTUnwrap(asked.first?.url)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items, [URLQueryItem(name: "a", value: "1"), URLQueryItem(name: "n", value: "2")])
        XCTAssertEqual(asked.first?.httpMethod, "GET")
        XCTAssertEqual(asked.first?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let posted = await OwnerTools.run(.api(post, json: #"{"n":2}"#), githubToken: "", apiToken: "", fetch: { request in
            asked.append(request)
            return (Data("bad".utf8), 500)
        })
        XCTAssertTrue(posted.hasPrefix("服务器返回 500"), posted)
        XCTAssertEqual(asked.last?.httpMethod, "POST")
        XCTAssertEqual(asked.last?.httpBody, Data(#"{"n":2}"#.utf8))
        XCTAssertNil(asked.last?.value(forHTTPHeaderField: "Authorization"), "no token, no header")
    }
}
