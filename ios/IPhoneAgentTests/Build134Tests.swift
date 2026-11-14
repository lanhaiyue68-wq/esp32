import XCTest
@testable import IPhoneAgent

/// Build 134: from 133's day on the phone (11-14): three waves, everyday requests, goals of 24 to 50 things.
@MainActor final class Build134Tests: XCTestCase {

    /// 133 (x1): "咖啡" typed in 美团's search box was held as the message “X1咖啡便宜”; the run failed at 515 s.
    func testOneWordOfTheMessageOutsideAChatIsASearch() {
        let task = "帮我做这3件事：1. 在美团外卖搜索“咖啡”，加一杯；2. 如果低于30元，就在微信测试群发“X1咖啡便宜”；3. 告诉我结果"
        XCTAssertFalse(AgentLoop.needsApproval("咖啡", task: task, chatApp: false))
        XCTAssertTrue(AgentLoop.needsApproval("咖啡", task: task, chatApp: true), "in a chat app, as before")
        XCTAssertTrue(AgentLoop.needsApproval("X1咖啡便宜", task: task, chatApp: false), "the whole message")
    }

    /// 133 (x2, x3, x5, x6, y2, y3): one thing that would not go ended goals of 24 to 50 things.
    func testMoreThingsMayFailInABiggerGoalAndItGetsMoreSteps() {
        func goal(_ n: Int) -> String { "帮我做这些事：" + (1...n).map { "\($0). 第\($0)件" }.joined(separator: "；") }
        XCTAssertEqual(AgentLoop.itemFailsAllowed(goal(3)), 2)
        XCTAssertEqual(AgentLoop.itemFailsAllowed(goal(20)), 4)
        XCTAssertEqual(AgentLoop.itemFailsAllowed(goal(50)), 10)
        XCTAssertEqual(AgentLoop.itemFailsAllowed("看天气"), 2)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "", base: 40, goal: goal(20)), 240, "20 things: as before")
        XCTAssertEqual(AgentLoop.stepBudget(plan: "", base: 40, goal: goal(30)), 360)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "", base: 40, goal: goal(50)), 600)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "", base: 40, goal: goal(80)), 600, "at most 600")
    }

    /// 133 (x4, y1): "（未能核實）部分失败：…" went out as "部分失败：部分失败：…".
    func testAPartialFailureIsLabelledOnce() {
        XCTAssertEqual(CloudBridge.said(true, "（未能核實）部分失败：第3项没做成"), "部分失败：第3项没做成")
        XCTAssertEqual(CloudBridge.said(true, "部分失败：第3项没做成"), "部分失败：第3项没做成")
        XCTAssertEqual(CloudBridge.said(true, "（未能核實）深圳26度"), "（未经核实）深圳26度")
    }

    /// 133 (y1): Y1验证9:47, then after a new plan Y1验证9:50, in the same group.
    func testAMessageAskedOnceWithSomethingAddedIsNotSentAgain() {
        let task = "1. 在微信验证群发“Y1验证”加上现在手机顶部显示的时间（例如“Y1验证22:40”）；2. 在微信测试群发“Y1全部做完”"
        XCTAssertEqual(AgentLoop.sameGoalMessage("Y1验证9:50", sent: ["Y1验证9:47"], task: task), "Y1验证9:47")
        XCTAssertNil(AgentLoop.sameGoalMessage("Y1验证9:47", sent: [], task: task))
        XCTAssertNil(AgentLoop.sameGoalMessage("Y1全部做完", sent: ["Y1验证9:47"], task: task), "another message")
        let twice = "1. 在测试群发“打卡”；2. 在验证群发“打卡”"
        XCTAssertNil(AgentLoop.sameGoalMessage("打卡1", sent: ["打卡"], task: twice), "asked twice: not this guard")
        let note = "9. 深圳AQI 12优
10. 已在验证群发“Y1验证9:47”
11. 小红书前4篇：1.深圳Citywalk…"
        XCTAssertNil(AgentLoop.sameGoalMessage(AgentLoop.typedKey(note), sent: ["Y1验证9:47"], task: task),
                     "134 y1: a note of the results is not the message again")
        XCTAssertTrue(AgentLoop.isChatApp("微信") && AgentLoop.isChatApp("企业微信") && !AgentLoop.isChatApp("备忘录"))
    }

    /// 133 (x4, x5, x6): 美团's "网络错误（H403#CS8#…）" page, reloaded until the loop guard ended the run.
    func testAnAppErrorPageIsSeen() {
        func rows(_ t: String) -> [[CandidatePicker.Piece]] { [[CandidatePicker.Piece(text: t, box: CGRect(x: 0.3, y: 0.4, width: 0.4, height: 0.02))]] }
        XCTAssertTrue(AgentLoop.appErrorShown(rows("您的网络好像不太给力，请稍后再试")))
        XCTAssertTrue(AgentLoop.appErrorShown(rows("网络错误（H403#CS8#CCX86H）")))
        XCTAssertFalse(AgentLoop.appErrorShown(rows("美团外卖 汉堡 月售5000+")))
    }

    /// 133 (y3): “iPhone 17” searched in 微信's 搜一搜 counted as sent; typing it again was refused 16 times.
    func testWhatTheGoalSaysToSearchIsASearch() {
        let task = "1. 在微信的搜一搜里搜索“iPhone 17”，记下第一个结果的标题；2. 在抖音搜“猫”；3. 在测试群发“Y3全部做完”"
        XCTAssertEqual(AgentLoop.goalSearches(task), ["iPhone17", "猫"])
        XCTAssertFalse(AgentLoop.goalSearches(task).contains("Y3全部做完"))
    }

    /// 133 (y5): Screen Time's limit page on 天气; the run opened 天气 again and again.
    func testScreenTimesLimitPageIsSeen() {
        func rows(_ t: [String]) -> [[CandidatePicker.Piece]] {
            [t.enumerated().map { CandidatePicker.Piece(text: $1, box: CGRect(x: 0.3, y: 0.3 + Double($0) * 0.05, width: 0.4, height: 0.02)) }]
        }
        XCTAssertTrue(AgentLoop.screenTimeShown(rows(["已达到时间限制", "你已达到“天气”的使用限制", "忽略限制"])))
        XCTAssertTrue(AgentLoop.screenTimeShown(rows(["Time Limit", "Ignore Limit"])))
        XCTAssertFalse(AgentLoop.screenTimeShown(rows(["屏幕使用时间", "每日平均 3小时"])), "the Settings page itself, no limit sheet")
        XCTAssertTrue(AgentLoop.screenTimeShown(rows(["时间限制", "15分钟后提醒我", "今天内忽略限制"])), "the choices after 忽略限制")
        XCTAssertTrue(AgentLoop.screenTimePasscodeShown(rows(["输入屏幕使用时间密码"])), "a passcode is never typed")
        XCTAssertTrue(AgentLoop.screenTimeNote.contains("15分钟后提醒我"), "user 11-15: the limit may be lifted, the least way")
    }

    /// 133 (x3): "tap the yellow Add to Cart button" was not counted in 美团.
    func testLongerAddWordsCount() {
        XCTAssertTrue(AgentLoop.addsToCart("I tap the yellow Add to Cart button under the cheapest set."))
        XCTAssertTrue(AgentLoop.addsToCart("点击规格弹窗底部的黄色按钮加到购物车"))
        XCTAssertTrue(AgentLoop.addsDish("Tap the round yellow + button on the right of the cheapest burger.", in: "美团"))
        XCTAssertFalse(AgentLoop.addsToCart("点击底部导航栏的“购物车”图标，进入购物车页面。"))
    }
}

/// Build 135: user 11-15 — a missing app is asked about (download, or end the task).
@MainActor final class Build135Tests: XCTestCase {
    func testTheInstallNoteNeverTypesAPasswordAndTheNoEndsTheTask() {
        let note = AgentLoop.installNote("京东")
        XCTAssertTrue(note.contains("App Store") && note.contains("京东"))
        XCTAssertTrue(note.contains("绝对不要输入密码"), "Apple asks the owner for the password on the phone")
        XCTAssertTrue(note.contains("不要买 App 内的东西"))
        XCTAssertEqual(AgentLoop.installDeclined("京东"), "手机上没有“京东”，机主选择不下载，任务结束")
        XCTAssertEqual(CloudBridge.failureWords(AgentLoop.installDeclined("京东")), "手机上没有“京东”，机主选择不下载，任务结束",
                       "the owner's words go back as they are")
    }

    /// 134 (y1): Search showed nothing once and 行事曆 was "not on this phone"; Apple's apps are never offered for download.
    func testApplesOwnAppsAreNeverOfferedForDownload() {
        XCTAssertTrue(AgentLoop.builtInApp("行事曆"))
        XCTAssertTrue(AgentLoop.builtInApp("日历"))
        XCTAssertTrue(AgentLoop.builtInApp("App Store"))
        XCTAssertTrue(AgentLoop.builtInApp("計算機"))
        XCTAssertFalse(AgentLoop.builtInApp("京东"))
        XCTAssertFalse(AgentLoop.builtInApp("闲鱼"))
    }
}

/// Build 135: user 11-15 — "要让codex自己能解决这个问题": a stuck step is solved by the planner once, kept as an app
/// tip, given to every later task in that app, and dropped when it does not work.
@MainActor final class Build135LearningTests: XCTestCase {
    func testTheCoachsReplyIsAWayABlockOrNothing() {
        XCTAssertEqual(AgentLoop.parseCoaching("WAY: 天气：明天某小时不在逐小时条里，点十天预报里的那一天看"),
                       .way("天气：明天某小时不在逐小时条里，点十天预报里的那一天看"))
        XCTAssertEqual(AgentLoop.parseCoaching("想了一下\nBLOCKED: 定位服务已关闭，高德无法从当前位置规划路线"),
                       .blocked("定位服务已关闭，高德无法从当前位置规划路线"))
        XCTAssertEqual(AgentLoop.parseCoaching("NONE"), .unknown)
        XCTAssertEqual(AgentLoop.parseCoaching("WAY: 点 (850, 560) 那里"), .unknown, "a spot on the screen is no way")
        XCTAssertEqual(AgentLoop.parseCoaching("随便试试"), .unknown)
        XCTAssertEqual(AgentLoop.thingKey("打开 天气，看深圳明天下午3点！"), AgentLoop.thingKey("打开天气看深圳明天下午3点"))
    }

    func testAnAppTipReachesEveryTaskInThatAppAndIsDroppedWhenItFails() {
        let book = LessonBook(file: nil)
        let id = book.learnAppTip(app: "天氣", goal: "看深圳明天下午3点的温度", text: "明天的小时不在逐小时条里，点十天预报里的那一天", run: "r1")
        XCTAssertNotNil(id)
        XCTAssertEqual(book.appTips(for: "帮我看下天气，明天下午三点多少度").count, 1, "matched by the app, not the whole task")
        XCTAssertEqual(book.appTips(for: "在高德查到深圳北站多久").count, 0)
        XCTAssertTrue(book.context(task: "天气里看首尔后天早上8点").contains("点十天预报里的那一天"))
        XCTAssertEqual(book.learnAppTip(app: "天气", goal: "x", text: "明天的小时不在逐小时条里，点十天预报里的那一天", run: "r2"), id,
                       "the same way again is reinforced, not stored twice")
        book.tipResult(id!, worked: false)
        XCTAssertEqual(book.appTips(for: "天气").count, 1, "one miss: kept")
        book.tipResult(id!, worked: false)
        XCTAssertEqual(book.appTips(for: "天气").count, 0, "two misses and no win: dropped")
        let kept = book.learnAppTip(app: "高德地图", goal: "y", text: "路线页顶部切到公交那一栏", run: "r3")!
        book.tipResult(kept, worked: true)
        book.tipResult(kept, worked: false)
        book.tipResult(kept, worked: false)
        XCTAssertEqual(book.appTips(for: "高德地图").count, 1, "it worked once: kept")
        XCTAssertTrue(book.context(task: "用高德地图查路线").contains("✓1"))
    }
}

/// Build 135: the rest of 134's hell round fixed in code (user 11-15: "把所有问题都修好").
@MainActor final class Build135FixesTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 14))! }

    /// 133 (y6): "从2026-11-14到2027-02-06春节还有99天"; it is 84.
    func testACountOfDaysIsPutRight() {
        XCTAssertEqual(AgentLoop.rightDayCounts("从2026-11-14到2027-02-06春节还有99天", today: today, calendar: calendar),
                       "从2026-11-14到2027-02-06春节还有84天")
        XCTAssertEqual(AgentLoop.rightDayCounts("从2026年11月14日到2027年2月6日共84天", today: today, calendar: calendar),
                       "从2026年11月14日到2027年2月6日共84天", "right already")
        XCTAssertEqual(AgentLoop.rightDayCounts("距离2026年12月25日还有40天", today: today, calendar: calendar),
                       "距离2026年12月25日还有41天")
        XCTAssertEqual(AgentLoop.rightDayCounts("从11月14日到12月25日（含首尾）共42天", today: today, calendar: calendar),
                       "从11月14日到12月25日（含首尾）共42天", "both ends counted: left alone")
        XCTAssertEqual(AgentLoop.rightDayCounts("价格12.5元，3.14倍", today: today, calendar: calendar), "价格12.5元，3.14倍")
    }

    func testTheGoalsDatesAreWorkedOut() {
        let facts = AgentLoop.dateFacts(in: "在日历看2026年12月25日和2027年1月1日分别是星期几", today: today, calendar: calendar)
        XCTAssertTrue(facts.contains("2026-12-25, Friday (星期五) 41 days from today"), facts)
        XCTAssertTrue(facts.contains("2027-01-01, Friday (星期五) 48 days from today"), facts)
        let bare = AgentLoop.dateFacts(in: "12月25日是星期几", today: today, calendar: calendar)
        XCTAssertTrue(bare.contains("2026-12-25, Friday (星期五)"), "no year: this year's: " + bare)
        XCTAssertEqual(AgentLoop.dateFacts(in: "2026年1月1日", today: today, calendar: calendar).components(separatedBy: ";").count, 1,
                       "a date with its year is not counted again without it")
        XCTAssertEqual(AgentLoop.dateFacts(in: "看深圳天气", today: today, calendar: calendar), "")
    }

    /// 134 (y3): 高德's "继续关闭定位服务" sheet, 29 times round.
    func testTheLocationOffSheetIsSeen() {
        let rows = [[CandidatePicker.Piece(text: "繼續關閉定位服務", box: CGRect(x: 0.2, y: 0.6, width: 0.6, height: 0.03))]]
        XCTAssertTrue(AgentLoop.locationOffShown(rows))
        XCTAssertTrue(AgentLoop.locationOffNote.contains("不要去设置里打开"))
    }

    /// D16, 134 (y3, y4): a new plan held the next few things; when it ran out the run went out with 16 of 50 done.
    func testThingsLeftOfABigGoalAreFound() {
        let goal = "帮我做这12件事：" + (1...12).map { n -> String in
            switch n {
            case 5: return "5. 在微信验证群发“Y9验证”加上现在的时间"
            case 6: return "6. 如果深圳比首尔热就在微信测试群发“Y9温差大”，否则发“Y9温差小”"
            case 7: return "7. 在微信测试群往上翻，数一数今天我自己发了几条包含“全部做完”的消息"
            case 11: return "11. 检查一遍：上面哪几项没做成"
            case 12: return "12. 把以上所有结果按编号整理好告诉我"
            default: return "\(n). 在淘宝搜索“保温杯\(n)”，记下价格"
            }
        }.joined(separator: "；")
        let told = ["第1项：¥9.5", "第31项：备忘录\"X4组记录\"第2项——抖音", "未能完成：1. 第3项：高德 — 点击（stuck）",
                    "1. 第4项：打开淘宝 -> 第4项完成：¥3", "第8项：A；第9项：B"]
        XCTAssertEqual(AgentLoop.itemsLeft(task: goal, told: told, sent: ["Y9验证4:13"]), [2, 6, 7, 10],
                       "another list's 第2项 is not this goal's; a message counts once it went out; 告诉我/检查 come with the answer")
        XCTAssertEqual(AgentLoop.itemsLeft(task: goal, told: told, sent: ["Y9验证4:13", "Y9温差小", "Y9全部做完"]), [2, 7, 10],
                       "counting messages that hold 全部做完 is not sending one")
        XCTAssertEqual(AgentLoop.itemsLeft(task: "1. 看天气；2. 发微信", told: [], sent: []), [], "under 10 things: as before")
        XCTAssertEqual(AgentLoop.itemRanges([7, 8, 9, 11, 17, 18, 19, 21, 22]), "7–9, 11, 17–19, 21, 22")
        XCTAssertTrue(AgentLoop.itemsLeftLine([2, 7]).contains("第N项"))
    }

    /// D17, 134 (y4): 高德's round of taps, then the drive time noted; 公车捷运 was refused 25 times as the same round.
    func testARoundThatNotedSomethingIsNoRound() {
        func tap(_ x: Double, _ y: Double) -> JObject { ["action": .str("tap"), "x": .num(x), "y": .num(y)] }
        let taps = [tap(434, 166), tap(919, 166), tap(166, 250), tap(434, 166), tap(919, 166)]
        XCTAssertTrue(AgentLoop.repeatsRound(taps, next: tap(166, 250)))
        XCTAssertFalse(AgentLoop.repeatsRound(taps + [["action": .str("note"), "text": .str("第21项：开车19分钟")]], next: tap(166, 250)))
        XCTAssertEqual(AgentLoop.bigGoalRefusalLimit, 12, "D19: a goal of 10+ things skips a thing after 12 refusals, not 25")
        XCTAssertEqual(AgentLoop.refusalLimit, 25)
    }

    /// D18, 134 (y4, y5): Weather's day chart shows 下午3时's value only under a held finger.
    func testWhatShowedOnlyWhileHeldIsTold() {
        func row(_ texts: [String], _ y: Double) -> [CandidatePicker.Piece] {
            texts.enumerated().map { i, t in CandidatePicker.Piece(text: t, box: CGRect(x: 0.1 + 0.2 * Double(i), y: y, width: 0.15, height: 0.03)) }
        }
        let held = [row(["11月16日", "下午3:00", "25°"], 0.2), row(["凌晨12時", "清晨6時", "中午12時", "下午6時"], 0.6)]
        let after = [row(["11月16日", "27°", "22°"], 0.2), row(["凌晨12時", "清晨6時", "中午12時", "下午6時"], 0.6)]
        XCTAssertEqual(AgentLoop.shownOnlyWhileHeld(held, now: after), "下午3:00 25°")
        XCTAssertEqual(AgentLoop.shownOnlyWhileHeld(after, now: after), "")
    }

    /// 134: whole prompts filled the trace in ~15 minutes.
    func testATracedPromptKeepsItsHeadAndTail() {
        let long = String(repeating: "甲", count: 400) + String(repeating: "乙", count: 5000) + "这一眼"
        let kept = AgentLoop.tracedPrompt(long)
        XCTAssertLessThan(kept.count, 2100)
        XCTAssertTrue(kept.hasPrefix("甲") && kept.hasSuffix("这一眼"))
        XCTAssertEqual(AgentLoop.tracedPrompt("短"), "短")
    }
}
