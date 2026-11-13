import XCTest
@testable import IPhoneAgent

/// Build 129: from 128's four 20-task days on the phone (11-13).
@MainActor final class Build129Tests: XCTestCase {

    /// 128 (g1): the right border's lift started at 0 on every launch; the right column of the Home Screen was missed.
    func testTheBorderLiftStartsAtTheUsualBiasAndSurvivesARestart() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let fresh = Pointer(device: FakeDevice(), calibrationFile: file)
        XCTAssertEqual(fresh.borderLiftY, Pointer.borderLiftStart, accuracy: 1e-9)
        XCTAssertGreaterThan(Pointer.borderLiftStart, 0.025, "border landings are 0.03-0.05 low")

        try Data(#"{"w": 445, "h": 620}"#.utf8).write(to: file)  // a calibrated phone
        let p = Pointer(device: FakeDevice(), calibrationFile: file)
        p.learnBorderLift(missedBy: 0.02)
        let learned = p.borderLiftY
        XCTAssertEqual(learned, Pointer.borderLiftStart + 0.005, accuracy: 1e-9)
        let again = Pointer(device: FakeDevice(), calibrationFile: file)
        XCTAssertEqual(again.borderLiftY, learned, accuracy: 1e-9, "the next launch starts from what was learned")
        XCTAssertEqual(again.span, Pointer.Span(w: 445, h: 620), "the calibration itself is kept")
    }

    /// 128 (g1): Codex's parts name their things without numbers; the apps a part names count as its things.
    func testAPartWithoutNumbersCountsTheAppsItNames() {
        XCTAssertEqual(AgentLoop.partSteps(for: "Results 13–15 and 17 are noted — open Safari for “人民币汇率”, 天氣 for Guangzhou’s tomorrow forecast, 計算機 for 1234×56, and 時鐘 for the existing world clock cities."), 50)
        XCTAssertEqual(AgentLoop.partSteps(for: "打开天气看深圳今天的最高温"), 20)
    }

    /// 128 (g2): the done check "corrected" a chat's latest three to the messages the run had sent there itself.
    func testAnObjectionQuotingTheRunsOwnSendIsNotAWrongAnswer() {
        let sent: Set<String> = [AgentLoop.typedKey("G2全部做完"), AgentLoop.typedKey("G2买东西做完")]
        XCTAssertTrue(AgentLoop.blamesOwnSend("第2项最新三条消息与屏幕不符，屏幕最新三条是G2全部做完、G2买东西做完、G1全部做完，没有G8全部做完。", sent: sent))
        XCTAssertTrue(AgentLoop.blamesOwnSend("item 2's latest three messages differ from the current screen: the screen shows G2 全部做完, G2买东西做完, G1全部做完.", sent: sent))
        XCTAssertFalse(AgentLoop.blamesOwnSend("第15项计算结果与屏幕不符：屏幕是32084", sent: sent))
        XCTAssertFalse(AgentLoop.blamesOwnSend("item 2 is wrong", sent: []))
        XCTAssertFalse(AgentLoop.blamesOwnSend("第3项写的是你好，屏幕上是早安", sent: ["你好"]), "too short to tell")
        // second round (g4): the run's own message named only in part
        let g4: Set<String> = [AgentLoop.typedKey("G4买东西做完"), AgentLoop.typedKey("G4全部做完"), "tap:发送"]
        XCTAssertTrue(AgentLoop.blamesOwnSend("第2项说最新三条消息含9:43\"G1全部做完\"，但当前测试群最新三条是9:55、10:03两条G2和10:17的G4消息，没有9:43的G1消息。", sent: g4))
        XCTAssertFalse(AgentLoop.blamesOwnSend("第2项说最新三条消息含G1全部做完，屏幕不同", sent: []), "nothing sent: the check stands")
        XCTAssertFalse(AgentLoop.blamesOwnSend("第4项购物车数量为2", sent: g4), "not about the chat")
    }

    /// 128 (g8): the lamp was in the cart twice from earlier days; the check called ×3 "more than the 1 asked".
    func testACartCountAboveWhatThisRunAddedWasThereBefore() {
        XCTAssertTrue(AgentLoop.blamesOldCart("淘宝购物车台灯数量为×3，超出目标要求的1件。", adds: 1, wanted: 1))
        XCTAssertTrue(AgentLoop.blamesOldCart("购物车台灯数量为×3，目标要求加购1件，数量不符。", adds: 1, wanted: 2))
        XCTAssertTrue(AgentLoop.blamesOldCart("the cart shows the lamp x 3, the goal asked for one", adds: 1, wanted: 1))
        XCTAssertFalse(AgentLoop.blamesOldCart("淘宝购物车台灯数量为×3，超出目标要求的1件。", adds: 3, wanted: 1), "this run added three")
        XCTAssertFalse(AgentLoop.blamesOldCart("淘宝购物车台灯数量为×3", adds: 0, wanted: 1), "no add seen: not known")
        XCTAssertFalse(AgentLoop.blamesOldCart("购物车里没有台灯", adds: 1, wanted: 1), "missing from the cart still stands")
        XCTAssertFalse(AgentLoop.blamesOldCart("the cart shows a lamp box 2, not the cup", adds: 1, wanted: 1))
        XCTAssertEqual(AgentLoop.cartWanted("4. 在淘宝搜索“台灯”，加入购物车一件；13. 看淘宝购物车最上面一件"), 1)
    }

    /// 128 (second round, g1): a written note scrolled up and down 15 times to "check" it.
    func testScrollingBackAndForthAgainIsRefused() {
        func swipe(_ y1: Double, _ y2: Double) -> JObject {
            ["action": .str("swipe"), "x1": .num(40), "y1": .num(y1), "x2": .num(40), "y2": .num(y2)]
        }
        let down = swipe(250, 750), up = swipe(800, 350)
        XCTAssertFalse(AgentLoop.scrollsBackAgain([down, down, up, up], next: down), "one way, back, and that way again")
        XCTAssertTrue(AgentLoop.scrollsBackAgain([down, down, up, up, down], next: up))
        XCTAssertFalse(AgentLoop.scrollsBackAgain([up, up, up, up, up], next: up), "a long list read one way")
        XCTAssertFalse(AgentLoop.scrollsBackAgain([down, up, down, ["action": .str("tap"), "x": .num(500), "y": .num(500)]], next: up),
                       "a tap between starts again")
        XCTAssertNil(AgentLoop.swipeDirection(swipe(500, 520)), "too short to scroll")
        XCTAssertNil(AgentLoop.swipeDirection(["action": .str("swipe"), "x1": .num(900), "y1": .num(500), "x2": .num(100), "y2": .num(520)]),
                     "a sideways swipe")
    }

    /// 129 (g1): the landings read off 129's first day keep the lift near the steady bias.
    func testTheBorderLiftHoldsAgainstOddReadings() {
        let p = Pointer(device: FakeDevice(), calibrationFile: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json"))
        var lifts: [Double] = []
        for raw in [0.026, -0.004, -0.06, 0.034] {  // where they really landed, below the target
            p.learnBorderLift(missedBy: raw - p.borderLiftY)
            lifts.append(p.borderLiftY)
        }
        XCTAssertTrue(lifts.allSatisfy { $0 > 0.02 && $0 < 0.04 }, "\(lifts)")
    }

    /// 129 (g1): the pages are read again when a remembered app is not on its page, at most every 10 minutes.
    func testThePagesMayBeReadAgainSoonAfterAMiss() {
        let now = Date()
        AppPlaces.readAgainNow(now: now.addingTimeInterval(-700))
        XCTAssertTrue(AppPlaces.mayReadAgain(now: now, every: AppPlaces.rereadAfterMiss))
        XCTAssertFalse(AppPlaces.mayReadAgain(now: now), "the three days for an app no page knew stay")
        AppPlaces.readAgainNow(now: now.addingTimeInterval(-300))
        XCTAssertFalse(AppPlaces.mayReadAgain(now: now, every: AppPlaces.rereadAfterMiss))
        AppPlaces.clear()  // 131 (g4): "重新記 App 位置" reads at the next open, whatever the last read
        XCTAssertTrue(AppPlaces.mayReadAgain(now: now, every: AppPlaces.rereadAfterMiss))
        XCTAssertFalse(AppPlaces.mapped)
    }

    /// 129 (g4): item 2 was noted right when read; the final answer retold it with the run's own later message.
    func testAnItemRetoldWithTheRunsOwnMessagesIsPutBackAsNoted() {
        let answer = "已完成全部20项任务，结果如下：1. 深圳多云；2. 微信测试群最新三条消息：下午1:40「G2买东西做完」、下午1:50「G2全部做完」、下午2:01「G4买东西做完」。；3. 抖音价格 12.5元；4. 淘宝 ×1"
        let notes = ["1. 深圳多云", "2. 测试群最新三条（均为我自己发的）：下午1:19 G1全部做完；下午1:28 G2买东西做完；下午1:40 G2全部做完"]
        let sent: Set<String> = [AgentLoop.typedKey("G4买东西做完"), AgentLoop.typedKey("G4全部做完")]
        let kept = AgentLoop.keepReadNotes(answer, notes: notes, sent: sent)
        XCTAssertTrue(kept.contains("下午1:19 G1全部做完"), kept)
        XCTAssertFalse(kept.contains("G4买东西做完"), kept)
        XCTAssertTrue(kept.hasPrefix("已完成全部20项任务，结果如下：1. 深圳多云；2. 测试群"), kept)
        XCTAssertTrue(kept.hasSuffix("；3. 抖音价格 12.5元；4. 淘宝 ×1"), kept)
        XCTAssertEqual(AgentLoop.keepReadNotes(answer, notes: notes, sent: []), answer, "nothing sent: as answered")
        let told = "1. 深圳多云；2. 最新三条：G1全部做完、G2买东西做完、G2全部做完；3. 已发G4买东西做完"
        XCTAssertEqual(AgentLoop.keepReadNotes(told, notes: notes, sent: sent), told, "item 3 has no note; item 2 tells no own message")
        XCTAssertEqual(AgentLoop.numberedItems("第13项：Safari搜索").first?.n, 13)
        XCTAssertEqual(AgentLoop.numberedItems(answer).map { $0.n }, [1, 2, 3, 4], "12.5元 is not item 12")
    }

    /// 130 (g2): a learned "send" was the + by the input box; a garbled message went out and the check was set aside.
    func testAMessageThatDidNotGoOutIsNeverSetAside() {
        let sent: Set<String> = [AgentLoop.typedKey("G2买东西做完"), AgentLoop.typedKey("G2全部做完")]
        XCTAssertFalse(AgentLoop.blamesOwnSend("测试群最新三条消息顺序与内容不符，且“G2买东西做完”“G2全部做完”未单独发出，屏幕显示为重复拼接的乱码消息。", sent: sent))
        XCTAssertFalse(AgentLoop.blamesOwnSend("item 8: G2买东西做完 was not sent; the chat shows a garbled message", sent: sent))
        XCTAssertTrue(AgentLoop.blamesOwnSend("第2项最新三条消息与屏幕不符，屏幕最新三条是G2全部做完、G2买东西做完、G1全部做完", sent: sent))
    }

    /// 130 (g2): only a spot with 发送 written on it is learned as the send button.
    func testOnlyASpotLabelledSendIsASendButton() {
        let keyboard = [[CandidatePicker.Piece(text: "發送", box: CGRect(x: 0.80, y: 0.77, width: 0.11, height: 0.04))]]
        XCTAssertTrue(AgentLoop.labelsSend(keyboard, at: CGPoint(x: 0.86, y: 0.79)))
        XCTAssertFalse(AgentLoop.labelsSend(keyboard, at: CGPoint(x: 0.933, y: 0.607)), "the + by the input box")
        XCTAssertFalse(AgentLoop.labelsSend([[CandidatePicker.Piece(text: "G2买东西做完", box: CGRect(x: 0.2, y: 0.59, width: 0.4, height: 0.03))]],
                                            at: CGPoint(x: 0.933, y: 0.607)))
    }

    /// 130 (g4): one objection about item 2 (the run's own messages) and item 4 (the cart's earlier count).
    func testEachPartOfAnObjectionIsWeighedOnItsOwn() {
        let sent: Set<String> = [AgentLoop.typedKey("G4买东西做完"), AgentLoop.typedKey("G4全部做完")]
        let g4 = "第2项最新三条消息与屏幕不符，最新三条应为G4买东西做完、G4全部做完、G2买东西做完；第4项购物车数量为2，目标要求数量1。"
        let task = "4. 在淘宝搜索“充电宝”，选第一个规格，加入购物车一件；7. 在美团外卖搜索“汉堡”，把一份最便宜的加入购物车"
        XCTAssertEqual(AgentLoop.cartWanted(task), 2)
        XCTAssertEqual(AgentLoop.cartEach(task), 1)
        XCTAssertNil(AgentLoop.standingObjection(g4, sent: sent, adds: 1, wanted: 2, each: 1))
        let mixed = "第2项最新三条应为G4买东西做完；第15项计算结果应为89991"
        XCTAssertEqual(AgentLoop.standingObjection(mixed, sent: sent, adds: 1, wanted: 2, each: 1), "第15项计算结果应为89991")
        XCTAssertEqual(AgentLoop.standingObjection("第15项计算结果应为89991", sent: sent, adds: 1, wanted: 2), "第15项计算结果应为89991")
    }

    /// 130 (q130b g5): on 淘宝's cart the executor noted made-up results for items 5-8 and typed them into the note.
    func testMadeUpPartsAreCaughtAndAnHonestAnswerMayFinish() {
        let goal = "帮我做这二十件事：4. 在淘宝搜索“洗衣液”；5. 在拼多多搜索“洗衣液”，记下第一个商品的价格；8. 在微信测试群发“G5买东西做完”；19. 在微信测试群发“G5全部做完”"
        let steps: [JObject] = [
            ["action": .str("open"), "app": .str("淘宝")],
            ["action": .str("note"), "thought": .str("items 4-8 are done"), "text": .str("5. 拼多多洗衣液第一个商品价格¥13.9")],
            ["action": .str("open"), "app": .str("微信")],
            ["action": .str("type"), "text": .str("4. 淘宝… 5. 拼多多洗衣液¥13.9")],
        ]
        XCTAssertEqual(AgentLoop.unvisitedApps(task: goal, steps: steps), ["拼多多"])
        XCTAssertEqual(AgentLoop.goalMessages(goal), ["G5买东西做完", "G5全部做完"])
        let sent: Set<String> = ["G5全部做完"]
        let madeUp = "4. 淘宝¥13.9；5. 拼多多¥13.9；8. 已在微信测试群发送“G5买东西做完”"
        XCTAssertNotNil(AgentLoop.unvisitedReason(task: goal, steps: steps, answer: madeUp))
        XCTAssertNotNil(AgentLoop.unsentGoalReason(task: goal, sent: sent, answer: madeUp))
        let honest = "4. 淘宝¥13.9；5. 拼多多没做；8. “G5买东西做完”未发送"
        XCTAssertNil(AgentLoop.unvisitedReason(task: goal, steps: steps, answer: honest))
        XCTAssertNil(AgentLoop.unsentGoalReason(task: goal, sent: sent, answer: honest))
        XCTAssertEqual(AgentLoop.unverifiedNote(task: goal, steps: steps, sent: sent),
                       "本次没有打开拼多多，相关项目没有做；没有发出“G5买东西做完”")
        XCTAssertEqual(AgentLoop.goalMessages("不要在测试群发“你好”；在验证群发送「C1全部做完」"), ["C1全部做完"])
        // fourth round (g8): the plan in an open's thought is no visit
        let clockGoal = "16. 在美团打开“订单”；17. 在时钟的世界时钟里看有哪些城市"
        let planned: [JObject] = [["action": .str("open"), "app": .str("美团"),
                                   "thought": .str("现在需要完成第16项（美团订单）和第17项（时钟世界时钟），先打开美团")]]
        XCTAssertEqual(AgentLoop.unvisitedApps(task: clockGoal, steps: planned), ["时钟"])
        let visited = planned + [["action": .str("open"), "app": .str("時鐘")]]
        XCTAssertEqual(AgentLoop.unvisitedApps(task: clockGoal, steps: visited), [])
    }

    /// 130 (q130b g5): "open 淘寶" left 测试群 in front and a message went out unapproved as "typing in 淘寶".
    func testAChatTitleTheGoalNamesMakesItAMessage() {
        let goal = "8. 在微信测试群发“G5买东西做完”；18. 新建一条备忘录，第一行写“第5组记录”"
        XCTAssertTrue(AgentLoop.goalNamesChat("测试群（4人）", task: goal))
        XCTAssertTrue(AgentLoop.goalNamesChat("測試群(4)", task: goal))
        XCTAssertFalse(AgentLoop.goalNamesChat("第5组记录的备忘", task: goal))
        XCTAssertFalse(AgentLoop.goalNamesChat("群", task: goal), "too short to tell")
        XCTAssertFalse(AgentLoop.goalNamesChat("虾笔刀陪跑学员元群", task: goal))
    }

    private func piece(_ t: String, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CandidatePicker.Piece {
        CandidatePicker.Piece(text: t, box: CGRect(x: x0 / 592, y: y0 / 1280, width: (x1 - x0) / 592, height: (y1 - y0) / 1280))
    }

    /// 130: "the latest three" read one short or out of order; the chat on screen is listed newest first.
    func testAChatOnScreenIsListedNewestFirst() {
        XCTAssertTrue(AgentLoop.asksLatestMessages("打开微信测试群，看最新的三条消息是谁发的"))
        XCTAssertFalse(AgentLoop.asksLatestMessages("在微信测试群发“G1全部做完”"))
        // g6's last screen: three time labels, four own bubbles, Lan Agent's keyboard below
        let g6 = [piece("测试群(4人)", 218, 98, 372, 128), piece("G5买东西做完", 298, 185, 468, 215), piece("下午4:05", 250, 272, 342, 298),
                  piece("G5全部做完", 324, 345, 468, 375), piece("下午4:12", 250, 433, 342, 459), piece("G6买东西做完", 298, 506, 468, 536),
                  piece("下午4:20", 250, 594, 342, 620), piece("G6全部做完", 324, 667, 468, 697), piece("已填入：", 252, 935, 342, 960),
                  piece("發送", 486, 1002, 534, 1030)].map { [$0] }
        let list = AgentLoop.chatLines(g6) ?? ""
        XCTAssertTrue(list.contains("1. me (right, green): G6全部做完  [time above: 下午4:20]"), list)
        XCTAssertTrue(list.contains("3. me (right, green): G5全部做完"), list)
        XCTAssertTrue(list.contains("4. me (right, green): G5买东西做完"), list)
        XCTAssertFalse(list.contains("發送"), "the keyboard is not a message")
        // g2's garbled two-line bubble is one message
        let g2 = [piece("测试群(4人)", 218, 98, 372, 128), piece("下午2:57", 250, 560, 342, 586),
                  piece("G2买东 G2G2全部做完部做完", 116, 634, 468, 664), piece("西做完", 116, 668, 190, 698),
                  piece("發送", 486, 1002, 534, 1030)].map { [$0] }
        XCTAssertTrue((AgentLoop.chatLines(g2) ?? "").contains("1. a long message (side: see the picture): G2买东 G2G2全部做完部做完西做完"))
        XCTAssertNil(AgentLoop.chatLines([[piece("淘宝", 30, 300, 100, 330)]]), "no chat title")
        // a note titled 第5组记录 has a centred title too: the app in front is what keeps its lines out of the list
        let goal = "2. 打开微信测试群，看最新的三条消息；18. 新建一条备忘录，第一行写“第5组记录”"
        XCTAssertTrue(AgentLoop.goalNamesChat("第5组记录", task: goal), "the goal names it, so the title alone is not enough")
        XCTAssertFalse(AgentLoop.inChatApp([["action": .str("open"), "app": .str("备忘录")]], task: goal))
        XCTAssertTrue(AgentLoop.inChatApp([["action": .str("open"), "app": .str("微信")]], task: goal))
    }

    /// 130 (fourth round, g4): a note's first line, which the goal says to write, was taken for a message.
    func testWhatTheGoalSaysToWriteIsNotAMessage() {
        let goal = "8. 在微信测试群发“G4买东西做完”；18. 新建一条备忘录，第一行写“第4组记录”，下面写第1到第17项的结果"
        XCTAssertEqual(AgentLoop.goalWrites(goal), ["第4组记录"])
        XCTAssertEqual(AgentLoop.goalMessages(goal), ["G4买东西做完"])
        XCTAssertEqual(AgentLoop.goalWrites("在验证群发“写好了”"), [], "写 inside a message is not a note")
        XCTAssertEqual(AgentLoop.goalWrites("在测试群写“你好”"), ["你好"], "written in a chat: the app and the title decide")
        XCTAssertTrue(AgentLoop.chatApps.contains("微信"))
    }

    /// 131 (r131b g5, g6): a chat opened mid-history; older messages were read as the newest after one swipe up (g5) or none (g6).
    func testTheLatestMessagesWaitForASwipeUpThatMovesNothing() {
        let open: JObject = ["action": .str("open"), "app": .str("微信")]
        let up: JObject = ["action": .str("swipe"), "x1": .num(40), "y1": .num(800), "x2": .num(40), "y2": .num(300), "changed": .bool(true)]
        XCTAssertTrue(AgentLoop.chatBottomNote([open])?.hasPrefix("It is not known yet") == true, "g6: read at once")
        XCTAssertTrue(AgentLoop.chatBottomNote([open, up])?.hasPrefix("The last swipe up still moved") == true, "g5")
        var still = up; still["changed"] = .bool(false)
        XCTAssertNil(AgentLoop.chatBottomNote([open, up, still]), "nothing moved: the bottom")
        var words = up; words["scrolled"] = .bool(false)
        XCTAssertNil(AgentLoop.chatBottomNote([open, words]), "the words did not move")
        var down = up; down["y1"] = .num(300); down["y2"] = .num(800)
        XCTAssertNil(AgentLoop.chatBottomNote([open, still, down, ["action": .str("note")]]), "older ones after the bottom")
        XCTAssertNotNil(AgentLoop.chatBottomNote([open, still, ["action": .str("tap")]]), "a tap since: look again")
    }

    /// User 11-14: "下次更新要顯示每個賬號的賬號和賬號名字": email, name and plan from the id token.
    func testAnAccountIsShownByItsEmailNameAndPlan() throws {
        let payload: [String: Any] = ["email": "someone@example.com", "name": "Some One",
                                      "https://api.openai.com/auth": ["chatgpt_plan_type": "plus", "chatgpt_account_id": "acc-1"]]
        let body = try JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let token = "e30." + body + ".sig"
        XCTAssertEqual(ChatGPTPlus.identity(idToken: token),
                       ChatGPTPlus.Identity(email: "someone@example.com", name: "Some One", plan: "plus"))
        XCTAssertEqual(ChatGPTPlus.accountID(idToken: token), "acc-1")
        XCTAssertNil(ChatGPTPlus.identity(idToken: "not a token"))
    }

    /// User 11-14: "默認就一個6.1luna" — account 1's plan lists gpt-6.1-luna, not gpt-6.1-terra; it plans with its own.
    func testACodexAccountThatCannotUseTheModelPlansWithItsOwn() async throws {
        XCTAssertEqual(PlusChat.model(for: [], preferred: "gpt-6.1-terra"), "gpt-6.1-terra", "nothing read yet")
        XCTAssertEqual(PlusChat.model(for: ["gpt-6.1-luna", "gpt-6.1-terra"], preferred: "gpt-6.1-terra"), "gpt-6.1-terra")
        XCTAssertEqual(PlusChat.model(for: ["gpt-6.1-luna", "gpt-5.6-terra"], preferred: "gpt-6.1-terra"), "gpt-6.1-luna")
        let t1 = ChatGPTPlus.Tokens(idToken: "i", accessToken: "a1", refreshToken: "r1", accountID: "1")
        var listed: [String] = [], reads = 0, asked: [String] = []
        let rest = PlusRest()
        let plus = PlusChat(model: "gpt-6.1-terra", fallback: FakeModel { _ in "doubao" }, tokens: { t1 }, save: { _ in },
                            ask: { tokens, model, _, _, _ in
                                asked.append(model)
                                if model == "gpt-6.1-terra" {
                                    throw ChatGPTPlus.Failure(message: "HTTP 400：{\"detail\":\"The 'gpt-6.1-terra' model is not supported when using Codex with a ChatGPT account.\"}")
                                }
                                return (ChatGPTPlus.Answer(text: "plan", model: model, firstTokenMs: 1, totalMs: 2, quota: [:]), tokens)
                            }, rest: rest, listed: { listed },
                            readModels: { _ in reads += 1; listed = ["gpt-6.1-luna", "gpt-5.6-terra"]; return listed })
        let first = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(first.text, "plan")
        XCTAssertEqual(asked, ["gpt-6.1-terra", "gpt-6.1-luna"])
        XCTAssertEqual(plus.model, "plus:gpt-6.1-luna")
        XCTAssertFalse(rest.resting, "account 1 answered: it does not rest")
        _ = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(asked.last, "gpt-6.1-luna", "its own from then on")
        XCTAssertEqual(reads, 1)
    }

    /// 131 (r131b g6): one sentence about item 2 (the run's own messages) and item 4's price; all of it was set aside.
    func testAnObjectionInOneSentenceIsWeighedItemByItem() {
        let sent: Set<String> = [AgentLoop.typedKey("G6买东西做完"), AgentLoop.typedKey("G6全部做完")]
        let g6 = "任务2最新三条消息与屏幕不符，屏幕最新为G6全部做完、G6买东西做完，任务4商品价格前后矛盾，任务6差价用的价格与任务4不同。"
        let kept = AgentLoop.standingObjection(g6, sent: sent, adds: 1, wanted: 2, each: 1) ?? ""
        XCTAssertTrue(kept.contains("任务4商品价格前后矛盾") && kept.contains("任务6"), kept)
        XCTAssertFalse(kept.contains("任务2"), kept)
        XCTAssertEqual(AgentLoop.standingObjection("第2项最新三条应为G6全部做完，与答案不符", sent: sent, adds: 1, wanted: 2, each: 1),
                       nil, "a comma inside one item's part does not part it")
    }

    /// 131 (r131b g5): item 12 was lost in four new plans and answered "未执行，无记录" with nothing in its way.
    func testAnItemNotDoneWithNoReasonIsSentBackOnce() {
        let goal = (1...20).map { "\($0). 第\($0)件事" }.joined(separator: "；")
        let full = (1...20).map { n -> String in
            n == 12 ? "12. 抖音搜索“北京胡同”：未执行，无记录" : n == 7 ? "7. 美团：差¥18.72起送，无法进入确认订单页"
                : n == 5 ? "5. 拼多多：要求登录，已跳过" : n == 20 ? "20. 以上为全部结果；第12项未执行" : "\(n). 结果\(n)"
        }.joined(separator: "；")
        let reason = AgentLoop.skippedWithoutReason(full, task: goal) ?? ""
        XCTAssertTrue(reason.hasPrefix("The answer says item 12 was not done"), reason)  // not 5 (login), 7 (起送), 20 (summary)
        XCTAssertNil(AgentLoop.skippedWithoutReason("12. 抖音：没装抖音，未执行", task: goal), "a reason given")
        XCTAssertNil(AgentLoop.skippedWithoutReason(full, task: "看天气"), "not a goal of several things")
        let jd = "7. 京东鼠标垫第一个商品：未记录到具体名称和价格（任务执行中未完成该项读取）"
        XCTAssertNotNil(AgentLoop.skippedWithoutReason(jd, task: goal))
        XCTAssertNil(AgentLoop.skippedWithoutReason(jd, task: goal, absent: ["京東"]), "r131c c1: 京东 is not on the phone")
    }

    /// 131 (r131b g5): 淘宝 一件 and 美团外卖 一份 made 2 for both; 淘宝 got a second bottle and 美团's add was refused.
    func testEachAppIsHeldToWhatTheGoalAsksOfIt() {
        let task = "4. 在淘宝搜索“洗衣液”，在前5个商品里挑价格最低的一个，选第一个颜色或规格，加入购物车一件，再打开购物车确认；"
            + "7. 在美团外卖搜索“麻辣烫”，打开第一家店，把一份最便宜的加入购物车（要选规格就选默认的第一个）；13. 看淘宝购物车最上面一件"
        XCTAssertEqual(AgentLoop.cartWanted(task), 2, "the whole goal, as before")
        XCTAssertEqual(AgentLoop.cartWanted(task, in: "淘寶"), 1)
        XCTAssertEqual(AgentLoop.cartWanted(task, in: "美团"), 1, "美团外卖's part names 美团 too")
        XCTAssertEqual(AgentLoop.cartWanted(task, in: nil), 2)
        XCTAssertEqual(AgentLoop.cartWanted(task, in: "京东"), 2, "no part names it: the whole goal")
        XCTAssertEqual(AgentLoop.cartWanted("在美团外卖把两杯奶茶加入购物车，再加购一份薯条", in: "美团外卖"), 3)
    }

    /// 131 (r131b g3): "已加入购物车" in an old note and the model's own typing in 备忘录 counted as two more adds.
    func testOnlyAShopsToastCountsAsAnAdd() {
        XCTAssertTrue(AgentLoop.sellsThings("淘寶"))
        XCTAssertTrue(AgentLoop.sellsThings("美团外卖"))
        XCTAssertTrue(AgentLoop.sellsThings(nil), "no app known: as before")
        XCTAssertFalse(AgentLoop.sellsThings("备忘录"))
        XCTAssertFalse(AgentLoop.sellsThings("備忘錄"))
        XCTAssertFalse(AgentLoop.sellsThings("微信"))
    }

    /// 131 (g1): with Codex down the run ended with one part's answer; the notes held the rest.
    func testAnAnswerCoveringFewThingsGetsTheNotesAdded() {
        let goal = (1...20).map { "\($0). 第\($0)件事" }.joined(separator: "；")
        let notes = ["深圳今天天气：毛毛雨，最高27°", "高德地图：到深圳北站35分钟", "第11项 淘宝我的淘宝：待收货0个",
                     "购物车：第1次看到加购成功的提示，这一件已经加进去了", "高德地图：到深圳北站35分钟"]
        let short = "第11项完成：淘宝我的淘宝：待收货0个"
        let full = AgentLoop.completedAnswer(short, notes: notes, task: goal) ?? ""
        XCTAssertTrue(full.hasPrefix(short), full)
        XCTAssertTrue(full.contains("深圳今天天气：毛毛雨，最高27°") && full.contains("高德地图：到深圳北站35分钟"), full)
        XCTAssertFalse(full.contains("购物车：第1次"), "the run's own cart line")
        XCTAssertEqual(full.components(separatedBy: "高德地图").count, 2, "a note once")
        let whole = (1...20).map { "\($0). 结果\($0)" }.joined(separator: "；")
        XCTAssertNil(AgentLoop.completedAnswer(whole, notes: notes, task: goal), "an answer to all twenty stays")
    }

    /// 131 (g1): account 1 "model not supported" was asked again every few minutes; account 2 rested 30 min though it
    /// said it would reset in 8.
    func testACodexAccountRestsAsLongAsItsOwnErrorSays() {
        let unsupported = #"HTTP 400：{"detail":"The 'gpt-6.1-terra' model is not supported when using Codex with a ChatGPT account.","error":{"type":"invalid_request_error"}}"#
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: unsupported), 6 * 3600)
        let limit = #"HTTP 429：{"error":{"type":"usage_limit_reached","message":"The usage limit has been reached","plan_type":"plus","resets_at":1794571252}}"#
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: limit, at: 1794570772), 510, accuracy: 0.001, "8 minutes and 30 s")
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: limit, at: 1794571300), 60, "already past: a minute")
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: "HTTP 429：limit"), 1800, "no time given: as before")
        let picture = #"HTTP 400：{"error":{"type":"invalid_request_error","message":"image too large"}}"#
        XCTAssertEqual(PlusRest.restSeconds(failures: 1, message: picture), 120, "one request's 400 is not the account's")
    }

    /// 130: an answer dropped as stale although the words around its tap target had not moved.
    func testTheWordsAroundATargetTellWhetherItMoved() {
        let before = [[piece("加入购物车", 250, 1180, 340, 1210)], [piece("双11大促", 20, 300, 200, 330)]]
        let banner = [[piece("加入购物车", 250, 1180, 340, 1210)], [piece("限时秒杀", 20, 300, 200, 330)]]
        let target = CGPoint(x: 295.0 / 592, y: 1195.0 / 1280)
        XCTAssertTrue(AgentLoop.sameWordsNear(before, banner, around: target), "a banner turned elsewhere")
        let popup = [[piece("加入购物车", 250, 1180, 340, 1210)], [piece("选择颜色", 230, 1150, 330, 1172)]]
        XCTAssertFalse(AgentLoop.sameWordsNear(before, popup, around: target), "something new came over the target")
        let moved = [[piece("加入购物车", 250, 1100, 340, 1130)]]
        XCTAssertFalse(AgentLoop.sameWordsNear(before, moved, around: target), "the button moved")
        XCTAssertFalse(AgentLoop.sameWordsNear([[piece("x", 20, 30, 30, 40)]], banner, around: target), "no words there: cannot tell")
    }

    /// 128 (g1): twenty things followed the remembered end of the last such run; several numbered things plan afresh.
    func testSeveralNumberedThingsAreNotARememberedWay() {
        XCTAssertGreaterThanOrEqual(AgentLoop.goalParts("帮我做这三件事：1. 查天气；2. 算差价；3. 发群"), 3)
        XCTAssertLessThan(AgentLoop.goalParts("在抖音推荐页打开第一个视频，用 listen 听它讲了什么"), 3)
    }
}
