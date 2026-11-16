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

    /// D21, 134 (z6): the Today View's Screen Time widget names apps (天氣, WeChat, 行事曆); it is no Home Screen.
    func testTheTodayViewIsNoHomeScreen() {
        func p(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            CandidatePicker.Piece(text: t, box: CGRect(x: x - 0.06, y: y - 0.012, width: 0.12, height: 0.024))
        }
        let today = [[p("照片處理完會顯示在此處", 0.5, 0.22)], [p("如何", 0.15, 0.39), p("加入遺產", 0.21, 0.42)],
                     [p("聯絡人", 0.19, 0.46), p("99%", 0.68, 0.46)], [p("7時37分", 0.25, 0.55)],
                     [p("天氣", 0.24, 0.78), p("WeChat", 0.69, 0.78)], [p("1時28分", 0.27, 0.80), p("30分", 0.66, 0.80)],
                     [p("行事曆", 0.25, 0.84), p("高德地圖", 0.74, 0.84)], [p("34分", 0.24, 0.86), p("26分", 0.66, 0.86)],
                     [p("設定", 0.24, 0.89), p("淘宝", 0.66, 0.89)]]
        XCTAssertFalse(AppPlaces.looksLikeHome(today))
    }

    /// D22, 134 真人单句 (h06, h08).
    func testAnAbsentAppWasLookedForAndDeadSwipesStop() {
        let absent: [JObject] = [["action": .str("open failed"), "app": .str("京东"), "reason": .str("京东 is not on this phone")]]
        XCTAssertEqual(AgentLoop.unvisitedApps(task: "京东上搜一下鼠标垫，第一个多少钱？手机上没有京东就直接告诉我没装", steps: absent), [])
        func swipe(_ x1: Double, _ x2: Double, changed: Bool) -> JObject {
            ["action": .str("swipe"), "x1": .num(x1), "y1": .num(450), "x2": .num(x2), "y2": .num(450), "changed": .bool(changed)]
        }
        let left = swipe(850, 150, changed: false)
        XCTAssertTrue(AgentLoop.swipesGoNowhere([left, left, left], next: swipe(850, 150, changed: false)))
        XCTAssertFalse(AgentLoop.swipesGoNowhere([left, left, swipe(850, 150, changed: true)], next: left), "the last one moved")
        XCTAssertFalse(AgentLoop.swipesGoNowhere([left, left, left], next: ["action": .str("swipe"), "x1": .num(500), "y1": .num(700),
                                                                            "x2": .num(500), "y2": .num(300)]), "the other axis")
        XCTAssertEqual(AgentLoop.swipeWay(["action": .str("swipe"), "x1": .num(500), "y1": .num(700), "x2": .num(500), "y2": .num(300)]), "up")
    }

    /// D24, 135 (y1 item 30): the bracket was keyed last and 8,367,… was noted; the goal's sums are worked out on the phone.
    func testTheGoalsSumsAreWorkedOut() {
        let goal = "30. 用计算器算 (12345 × 678 − 9876) ÷ 3.5，保留两位小数；38. 用计算器算 √2 × 1000；41. 用计算器算 2 的 30 次方"
        let facts = AgentLoop.mathFacts(in: goal)
        XCTAssertTrue(facts.contains("(12345 × 678 − 9876) ÷ 3.5 = 2388581.142857"), facts)
        XCTAssertTrue(facts.contains("√2 × 1000 = 1414.213562"), facts)
        XCTAssertTrue(facts.contains("2 的 30 次方 = 1073741824"), facts)
        XCTAssertEqual(AgentLoop.mathFacts(in: "在日历看2026-12-25和2026/12/25分别是星期几（只有北京就记0）"), "", "dates are no sums")
        XCTAssertEqual(AgentLoop.sumValue("(365-28)×24"), 8088)
        XCTAssertNil(AgentLoop.sumValue("(1+2"))
        XCTAssertTrue(AgentLoop.installFirst("京东").contains("不适用于“京东”"), "D23: the owner's yes wins over 不要下载")
    }

    /// D25, 135 (y1): the answer stopped at item 28 of 49; over half, so the notes of 29–49 were not added.
    func testACutAnswerGetsTheRestOfTheNotes() {
        let goal = (1...20).map { "\($0). 第\($0)件事" }.joined(separator: "；")
        let cut = (1...12).map { "\($0). 结果\($0)" }.joined(separator: "；") + "；13. 差价"
        let full = AgentLoop.completedAnswer(cut, notes: ["第15项：淘宝¥9.9", "第18项：2的30次方 = 1073741824"], task: goal) ?? ""
        XCTAssertTrue(full.contains("第15项：淘宝¥9.9") && full.contains("第18项"), full)
        let nearlyAll = (1...18).map { "\($0). 结果\($0)" }.joined(separator: "；")
        XCTAssertNil(AgentLoop.completedAnswer(nearlyAll, notes: ["第19项：x"], task: goal), "two missing: as it was")
        XCTAssertEqual(AgentLoop.bigGoalTokens, 30000, "user 11-15: 上限擡高到3萬")
        XCTAssertEqual(LLMClient.ceiling(from: "max_tokens must be less than or equal to 16384", asked: 30000), 16384)
        XCTAssertEqual(LLMClient.ceiling(from: "Invalid max_tokens value, the valid range is [1, 16384]", asked: 30000), 16384)
        XCTAssertEqual(LLMClient.ceiling(from: "max_tokens is too large", asked: 30000), 8192, "no number: 8192")
        XCTAssertNil(LLMClient.ceiling(from: "image too large", asked: 30000), "another 400")
    }

    /// D26, 135 (y1): 温差小 went out, and "never sent Y1温差大" made the run send that too.
    func testOneOfTwoMessagesIsEnough() {
        let goal = "27. 如果深圳今天最高温比首尔高10度以上，就在微信测试群发“Y1温差大”，否则发“Y1温差小”；48. 在微信测试群发“Y1全部做完”"
        XCTAssertEqual(AgentLoop.eitherMessages(goal), [["Y1温差大", "Y1温差小"]])
        XCTAssertEqual(AgentLoop.eitherPartnerSent("Y1温差大", task: goal, sent: ["Y1温差小"]), "Y1温差小")
        XCTAssertNil(AgentLoop.eitherPartnerSent("Y1温差大", task: goal, sent: []))
        XCTAssertNil(AgentLoop.unsentGoalReason(task: goal, sent: ["Y1温差小", "Y1全部做完"], answer: ""))
        XCTAssertNotNil(AgentLoop.unsentGoalReason(task: goal, sent: ["Y1温差小"], answer: ""), "全部做完 is still owed")
    }

    /// D27, user 11-15 (爬楼): a read up a chat, screen by screen, comes out oldest first, each line once.
    func testAReadUpTheChatComesOutOldestFirst() throws {
        let newest = ["下午3:52", "Y1全部做完", "Y1温差小"], older = ["昨天 晚上9:30", "C1比价做完", "下午3:52"]
        XCTAssertEqual(AgentLoop.readUpMerge([newest, older]), ["昨天 晚上9:30", "C1比价做完", "下午3:52", "Y1全部做完", "Y1温差小"])
        let note = AgentLoop.readUpNote(["a", "b"], screens: 2, until: "11月14日")
        XCTAssertTrue(note.hasPrefix("往上读到的聊天记录（2 屏，从旧到新，读到“11月14日”为止；行首“（我）”"), note)
        XCTAssertTrue(note.contains("单独一行的时间是它下面那些消息的发送时间"))  // D46
        XCTAssertLessThan(AgentLoop.readUpNote([String(repeating: "字", count: 9000)], screens: 40, until: "").count, 6200)
        XCTAssertEqual(try Actions.parseCommand("readup 11月14日")["until"]?.str, "11月14日")
        XCTAssertEqual(try Actions.parseCommand("readup")["action"]?.str, "readup")
    }

    /// D28, user 11-15: the owner is asked before 发布.
    func testAPublishTapIsSeen() {
        let tap: JObject = ["action": .str("tap"), "x": .num(860), "y": .num(930), "thought": .str("标题和话题都填好了，点击右下角的发布按钮")]
        XCTAssertTrue(AgentLoop.publishTap(tap, label: "发布", app: "抖音"))
        XCTAssertTrue(AgentLoop.publishTap(tap, label: nil, app: "小红书"), "the model says it is the publish button")
        XCTAssertTrue(AgentLoop.publishTap(["action": .str("tap"), "x": .num(1), "y": .num(1)], label: "Post", app: nil))
        let notYet: JObject = ["action": .str("tap"), "x": .num(500), "y": .num(500), "thought": .str("先不要点发布，先选封面")]
        XCTAssertFalse(AgentLoop.publishTap(notYet, label: "选封面", app: "抖音"))
        XCTAssertFalse(AgentLoop.publishTap(tap, label: nil, app: "备忘录"), "not an app that publishes")
        XCTAssertTrue(AgentLoop.publishQuestion("快手").contains("要发布吗"))
    }

    /// D29, user 11-15: monthly jobs and the owner's invoice details.
    func testMonthlyJobsAndInvoiceDetails() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let at = { (m: Int, d: Int, h: Int) in cal.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))! }
        var job = ScheduledJob(task: "申请发票", day: 1, hour: 9, minute: 0, lastRun: at(11, 15, 12))
        XCTAssertFalse(job.isDue(at: at(11, 30, 12), calendar: cal), "ran this month already")
        XCTAssertTrue(job.isDue(at: at(12, 1, 10), calendar: cal), "next month's time has come")
        XCTAssertFalse(job.isDue(at: at(12, 1, 8), calendar: cal), "not yet 9:00")
        job.enabled = false
        XCTAssertFalse(job.isDue(at: at(12, 2, 10), calendar: cal))
        XCTAssertEqual(ScheduledJob(task: "x", day: 31, hour: 9, minute: 0).dueDate(in: at(2, 10, 0), calendar: cal),
                       at(2, 28, 9), "day kept within 28")
        let profile = InvoiceProfile(kind: "单位", title: "蓝海乐科技有限公司", taxID: "91440300MA5XXXXXXX", email: "fp@example.com")
        let facts = AgentLoop.invoiceFacts(in: "在麦当劳申请上个月的发票", profile: profile)
        XCTAssertTrue(facts.contains("蓝海乐科技有限公司") && facts.contains("91440300MA5XXXXXXX") && facts.contains("fp@example.com"), facts)
        XCTAssertEqual(AgentLoop.invoiceFacts(in: "看深圳天气", profile: profile), "")
        XCTAssertTrue(AgentLoop.invoiceFacts(in: "开发票", profile: InvoiceProfile()).contains("not filled in"))
    }

    /// F, user 11-15: what the owner teaches, as the model puts it.
    func testATaughtWayIsRead() {
        let tip = TeachTip.parse("APP: 丰巢\nWHEN: 取件码页面要授权手机号\nWAY: 点“拒绝”，改从“我的”里看取件码\nSAY: 明白了，下次先拒绝授权再找取件码。")
        XCTAssertEqual(tip.app, "丰巢")
        XCTAssertTrue(tip.isLesson)
        XCTAssertEqual(tip.say, "明白了，下次先拒绝授权再找取件码。")
        XCTAssertFalse(TeachTip.parse("APP:\nWAY:\nSAY: 学到了三条做法。").isLesson, "a question answered, nothing to keep")
    }

    /// D31, 135 (y4): "从今天…到那天还有225天", 那天 being 2027年2月6日 said just before (83 days).
    func testACountToThatDayIsPutRight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 14))!
        XCTAssertEqual(AgentLoop.rightDayCounts("第22项：2027年春节为2027年2月6日（农历正月初一）；从今天2026年11月15日到那天还有225天。",
                                                today: today, calendar: cal),
                       "第22项：2027年春节为2027年2月6日（农历正月初一）；从今天2026年11月15日到那天还有83天。")
        XCTAssertEqual(AgentLoop.rightDayCounts("春节是2027年2月6日，距那天还有90天", today: today, calendar: cal), "春节是2027年2月6日，距那天还有84天")
        XCTAssertEqual(AgentLoop.rightDayCounts("21. 2026年12月25日是星期五；22. 从今天到那天还有10天", today: today, calendar: cal),
                       "21. 2026年12月25日是星期五；22. 从今天到那天还有10天", "another item's date is not 那天")
    }

    /// D30, 135 (y2): this run's values and progress were kept as ways for the app.
    func testARunsResultIsNoWay() {
        XCTAssertEqual(AgentLoop.parseCoaching("WAY: 深圳天气页的日落卡已显示日出6:36、日落17:40，相差11小时4分"), .unknown)
        XCTAssertEqual(AgentLoop.parseCoaching("WAY: 第10项已听取并记录；当前在淘宝商品页，可继续完成后续事项"), .unknown)
        XCTAssertEqual(AgentLoop.parseCoaching("WAY: 拼多多首个商品¥19.9"), .unknown)
        XCTAssertEqual(AgentLoop.parseCoaching("WAY: 在支付宝详情页向上滑到“评分与评论”看评分和评分人数"),
                       .way("在支付宝详情页向上滑到“评分与评论”看评分和评分人数"))
    }

    /// 134: whole prompts filled the trace in ~15 minutes.
    func testATracedPromptKeepsItsHeadAndTail() {
        let long = String(repeating: "甲", count: 400) + String(repeating: "乙", count: 5000) + "这一眼"
        let kept = AgentLoop.tracedPrompt(long)
        XCTAssertLessThan(kept.count, 2100)
        XCTAssertTrue(kept.hasPrefix("甲") && kept.hasSuffix("这一眼"))
        XCTAssertEqual(AgentLoop.tracedPrompt("短"), "短")
    }

    /// D32, D33 (y5 on 135): what a part found is a note; the check knows that another page's price is no contradiction.
    func testWhatAPartFoundIsNoted() {
        XCTAssertEqual(AgentLoop.partResultNote(part: "第39项：The calculation is recorded — open 計算機",
                                                found: "第39项：(12345 × 678 − 9876) ÷ 3.5 = 2,388,581.14"),
                       "第39项：(12345 × 678 − 9876) ÷ 3.5 = 2,388,581.14")
        XCTAssertEqual(AgentLoop.partResultNote(part: "第11项：2027年2月的星期一已记录", found: "2027年2月共有4个星期一：1、8、15、22日。"),
                       "第11项：2027年2月共有4个星期一：1、8、15、22日。")
        XCTAssertEqual(AgentLoop.partResultNote(part: "打开设置看电量", found: "电量 98%"), "电量 98%")
        XCTAssertNil(AgentLoop.partResultNote(part: "第3项：x", found: ""))
        XCTAssertNil(AgentLoop.partResultNote(part: "第3项：x", found: "已完成。"))
        let prompt = AgentLoop.checkPrompt(goal: "帮我做这49件事：…", today: "", answer: "7. 淘宝12元", did: "", notes: [],
                                           sent: [], parts: 49)
        XCTAssertTrue(prompt.contains("no contradiction"), prompt)
    }

    /// D34, D35 (y6 on 135): a dropped board is a link loss; the service's stock refusal is not the model's reply.
    func testAServiceRefusalAndADroppedBoardAreNoFailures() {
        for t in ["抱歉，您的问题我无法识别", "你好，这个问题我无法回答", "抱歉，没有找到相关的结果", "你好，我无法给到相关内容"] {
            XCTAssertTrue(AgentLoop.serviceRefused(t), t)
        }
        for t in ["THINK: 抱歉无法\nDO: back", "DO: done 抱歉", "好的",
                  "抱歉，屏幕上没有找到发送按钮，我需要先返回上一页再找找看这个按钮在哪里吧，然后再试一次"] {
            XCTAssertFalse(AgentLoop.serviceRefused(t), t)
        }
        XCTAssertTrue(AgentLoop.isLinkLoss(VideoReadinessError.boardDisconnected, screenLive: true))
    }

    /// D36 (s2 on 136): comparing the first 10 places is 10 things' worth of steps.
    func testComparingTenCandidatesGetsTheirSteps() {
        let goal = "用高德地图找附近评分4.5分以上的川菜馆，比较前10家的店名、评分、评价数、人均价格和距离，最后推荐三家"
        XCTAssertEqual(AgentLoop.candidateCount(goal), 10)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "", base: 40, goal: goal), 200)
        XCTAssertEqual(AgentLoop.candidateCount("帮我找十来家酒店比一比"), 10)
        XCTAssertEqual(AgentLoop.candidateCount("在抖音推荐页看前三个视频"), 3)
        XCTAssertEqual(AgentLoop.candidateCount("算 2 的 30 次方"), 0)
        XCTAssertEqual(AgentLoop.stepBudget(plan: "", base: 40, goal: "打开微信看看消息"), 40)
    }

    /// D37 (s3 on 136): WeChat's pickers and settings pages are no chat; the reason reaches the owner in Chinese.
    func testAPickerIsNoChat() {
        for t in ["新聊天", "选择联系人", "设置备注和标签", "聊天成员(3)", "群成员（5）"] { XCTAssertTrue(AgentLoop.notAChat(t), t) }
        for t in ["测试群", "测试群(5)", "验证群", "文件传输助手", "设置备注的小王"] { XCTAssertFalse(AgentLoop.notAChat(t), t) }
        XCTAssertEqual(CloudBridge.failureWords("about to send into the wrong place: the chat at the top is “新聊天”"),
                       "要发消息的地方不是题目说的那个聊天，为了不发错停下了")
    }

    /// D38 (s6 on 136): the owner's own messages, on the right with no name, are marked in a read up a chat.
    func testTheOwnersOwnMessagesAreMarked() {
        typealias P = CandidatePicker.Piece
        XCTAssertEqual(AgentLoop.readUpLine([P(text: "Y5全部做完", box: CGRect(x: 0.6, y: 0.3, width: 0.24, height: 0.03))]),
                       "（我）Y5全部做完")
        XCTAssertEqual(AgentLoop.readUpLine([P(text: "workbuddy这个远程控制可以啊", box: CGRect(x: 0.17, y: 0.4, width: 0.5, height: 0.03))]),
                       "workbuddy这个远程控制可以啊")
        XCTAssertEqual(AgentLoop.readUpLine([P(text: "11月14日 下午3:20", box: CGRect(x: 0.36, y: 0.2, width: 0.28, height: 0.02))]),
                       "11月14日 下午3:20")
    }

    /// D40, user 11-16: 京东 reads "JD" on a Traditional phone; the Search pill names no page.
    func testJDAndThePillOnAHomePage() {
        XCTAssertEqual(AppNames.searchName("京东", language: "zh-Hant-TW"), "JD")
        XCTAssertEqual(AppNames.searchName("京东", language: "zh-Hans-CN"), "京东")
        XCTAssertTrue(AppNames.variants("京东").contains("JD"))
        XCTAssertTrue(AppNames.variants("京东").contains("京東"))
        let page = [[CandidatePicker.Piece(text: "JD", box: CGRect(x: 0.12, y: 0.09, width: 0.06, height: 0.02))],
                    [CandidatePicker.Piece(text: "Q搜尋", box: CGRect(x: 0.44, y: 0.82, width: 0.11, height: 0.02))]]
        XCTAssertEqual(AppPlaces.names(page).map(\.text), ["JD"])
        XCTAssertNotNil(AppPlaces.searchPill(in: page))
    }

    /// D41/D42, y1 on 136: a failed part is noted by its number, in Chinese; past half, only the missing things' notes are added.
    func testAFailedPartIsNotedInChineseAndOnlyMissingThingsAreAdded() {
        XCTAssertEqual(AgentLoop.failedPartNote("1. 第21项：The first data cable’s name and price are recorded - open 淘宝",
                                                why: "stuck: 1 new plans in a row and nothing got on"),
                       "第21项（卡住了，换了几种做法都没有进展）")
        XCTAssertEqual(AgentLoop.failedPartNote("Open 微信", why: "kept tapping a spot that does nothing"),
                       "Open 微信（一直点一个没反应的地方，没能做完）")
        let goal = (1...20).map { "\($0). 第\($0)件事" }.joined(separator: "；")
        let answer = (1...16).map { "\($0). 结果\($0)" }.joined(separator: "；")
        let notes = ["第3项：深圳日出6:36", "新学到的做法：点返回", "深圳最高27°", "第18项：2的30次方 = 1073741824", "未能完成：第19项（卡住了）"]
        let full = AgentLoop.completedAnswer(answer, notes: notes, task: goal) ?? ""
        XCTAssertTrue(full.contains("第18项") && full.contains("第19项"), full)
        XCTAssertFalse(full.contains("第3项") || full.contains("新学到") || full.contains("深圳最高"), full)
    }

    /// D43, y1 on 136: a reply going round and round is cut where the repeats start; a long reply that moves on is not.
    func testAReplyGoingRoundIsCut() {
        let long = (1...700).map { "第\($0)项" }.joined()
        XCTAssertNil(LLMClient.goingRound(long))
        let loop = "THINK: ok\nDO: done 结果" + String(repeating: "abc def ghi jkl mno pqr stu vwx yz 0123456789. ", count: 200)
        let kept = LLMClient.goingRound(loop) ?? ""
        XCTAssertTrue(kept.hasPrefix("THINK: ok") && kept.count < 400, kept)
        XCTAssertEqual(LLMClient.goingRound("答案" + String(repeating: "。", count: 3500)), "答案")
    }

    /// D44, y2 on 136: an answer of item 47 alone, for a goal of 49, leaves out many things; one of 47 does not.
    func testAnAnswerOfOneThingLeavesMuchOut() {
        let goal = "帮我做这49件事：" + (1...49).map { "\($0). 第\($0)件事" }.joined(separator: "；")
        XCTAssertTrue(AgentLoop.fewThingsTold("第47项完成：已在测试群发送“Y2全部做完”", task: goal))
        XCTAssertFalse(AgentLoop.fewThingsTold((1...47).map { "\($0). 结果\($0)" }.joined(separator: "\n"), task: goal))
        XCTAssertTrue(AgentLoop.wholeAnswerPrompt.contains("Simplified Chinese"))
    }

    /// D45, y2 on 136 (item 31): the day 100 days on from today is worked out on the phone, both ways of counting.
    func testTheHundredthDayIsWorkedOut() {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10))!
        let facts = AgentLoop.dateFacts(in: "31. 用计算器和日历算出从今天起第100天是几月几号、星期几", today: today, calendar: cal)
        XCTAssertTrue(facts.contains("2027-02-23, Tuesday (星期二) counting today as day 1"), facts)
        XCTAssertTrue(facts.contains("2027-02-24, Wednesday (星期三) counting 100 days on"), facts)
        XCTAssertTrue(AgentLoop.dateFacts(in: "100天后是几号", today: today, calendar: cal).contains("2027-02-24, Wednesday (星期三) 100 days from today"))
    }

    /// D47, z5/z6 on 136: Doubao's account was overdue (HTTP 403 AccountOverdueError) and two runs of 50 things ended.
    func testAnOverdueExecutorHandsTheRunToCodex() async {
        XCTAssertTrue(ModelRequestFailure.accountClosed(#"LLM HTTP 403: {"error":{"code":"AccountOverdueError","message":"x"}}"#))
        XCTAssertTrue(ModelRequestFailure.accountClosed("LLM HTTP 401: invalid key"))
        XCTAssertFalse(ModelRequestFailure.accountClosed("LLM HTTP 429: rate limit"))
        XCTAssertFalse(ModelRequestFailure.accountClosed("网络连接已中断。"))
        let actor = OverdueModel()
        let planner = FakeModel { $0 == 1 ? "1. look" : "THINK: finished\nDO: done 好了" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: planner, trace: nil)
        agent.showMock(task: "查", plan: "", steps: [], running: false)
        await agent.run()
        let kinds = agent.steps.map { $0["action"]?.str ?? "?" }
        XCTAssertEqual(kinds.last, "done", "\(kinds)")
        XCTAssertFalse(kinds.contains("error"), "\(kinds)")
        XCTAssertTrue(kinds.contains("executor closed"), "\(kinds)")
        XCTAssertEqual(actor.calls, 1, "Doubao is not asked again in this run")
    }

    /// D47: Codex resting for one dropped connection is asked again when Doubao answers that its account cannot be used.
    func testCodexRestingForTheNetworkIsAskedAgainWhenDoubaoIsOverdue() async throws {
        let rest = PlusRest()
        var calls = 0
        let tokens = ChatGPTPlus.Tokens(idToken: "i", accessToken: "a", refreshToken: "r", accountID: "x")
        let plus = PlusChat(model: "m", fallback: OverdueModel(), tokens: { tokens }, save: { _ in },
                            ask: { _, _, _, _, _ in
                                calls += 1
                                if calls == 1 { throw URLError(.networkConnectionLost) }
                                return (ChatGPTPlus.Answer(text: "plan", model: "m", firstTokenMs: 1, totalMs: 2, quota: [:]), tokens)
                            }, rest: rest)
        let reply = try await plus.chat(system: "s", text: "t", image: nil, maxTokens: 1, temperature: 0)
        XCTAssertEqual(reply.text, "plan")
        XCTAssertEqual(calls, 2)
        XCTAssertFalse(rest.resting)
        rest.failed("请求超时。")
        rest.wake()
        XCTAssertTrue(rest.resting, "a real failure is not woken")
    }

    /// D48, y3 on 136 (item 24): the refusal of a scroll back quotes what Doubao said it saw on the page, to be noted.
    func testARefusedScrollBackQuotesWhatWasSeen() {
        func swipe(_ y1: Int, _ y2: Int, _ thought: String) -> JObject {
            ["action": .str("swipe"), "x1": .int(40), "y1": .int(y1), "x2": .int(40), "y2": .int(y2), "thought": .str(thought)]
        }
        let steps: [JObject] = [
            ["action": .str("tap"), "x": .int(284), "y": .int(493), "thought": .str("點進關於本機")],
            swipe(800, 350, "The 關於本機 page shows 機型名稱 iPhone 13 mini; I need 總容量"),
            swipe(300, 750, "The page shows 容量 256GB, but the model name row is above"),
            swipe(800, 300, "已读到机型名称 iPhone 13 mini；总容量还没显示"),
        ]
        XCTAssertTrue(AgentLoop.scrollsBackAgain(steps, next: swipe(300, 750, "")))
        let reason = AgentLoop.scrollBackRefusal(steps + [["action": .str("refused"), "reason": .str("x")]])
        XCTAssertTrue(reason.hasPrefix(AgentLoop.scrollBackReason))
        XCTAssertTrue(reason.contains("iPhone 13 mini") && reason.contains("256GB"), reason)
        XCTAssertTrue(reason.contains("with note"), reason)
        XCTAssertFalse(reason.contains("點進關於本機"), "only what was said while scrolling")
        XCTAssertEqual(AgentLoop.scrollBackRefusal([["action": .str("tap")]]), AgentLoop.scrollBackReason)
    }

    /// D49, y3 on 136 (item 46): after one lost paste trip, text that can only be pasted (several lines) tries the trip again.
    func testTextThatCanOnlyBePastedTriesTheTripAgain() async throws {
        let actor = FakeModel { n in n == 1 ? "DO: type 你好" : #"DO: type "Y3组记录\n1. 春节""# }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: actor, trace: nil)
        agent.fastText = true; agent.pinyinMisses = 2
        var hops = 0
        agent.pasteHop = { _ in hops += 1; return .lost }
        _ = try? await agent.step()
        XCTAssertEqual(hops, 1)
        _ = try? await agent.step()
        XCTAssertEqual(hops, 2, "several lines cannot be typed: the trip is tried again")
    }

    /// D50, y3 on 136 (item 7): Codex leaving a screen the run keeps coming back to is let through; the executor alone is not.
    func testCodexLeavingAScreenTheRunKeepsComingBackToIsLetThrough() {
        let opener: JObject = ["action": .str("tap"), "x": .int(875), "y": .int(925)]
        var back: JObject = ["action": .str("tap"), "x": .int(55), "y": .int(88)]
        XCTAssertFalse(AgentLoop.codexLeaves(back, opener: opener), "the executor alone is still refused (traces(33))")
        back["by"] = .str("planner")
        XCTAssertTrue(AgentLoop.codexLeaves(back, opener: opener))
        var codexTap = opener
        codexTap["by"] = .str("planner")
        XCTAssertFalse(AgentLoop.codexLeaves(codexTap, opener: back), "only a move that leaves")
        XCTAssertTrue(AgentLoop.openerReason.contains("go back further"))
    }

    /// D51, y5 on 136: items 23, 24 and 25 noted in 20 steps of one part were counted as a stalled part and a thing skipped.
    func testANoteOfANewThingIsThePartGettingOn() {
        XCTAssertTrue(AgentLoop.newThingNoted("第24项：淘宝搜索“数据线”按价格从低到高排序后，第一个商品…", before: [23]))
        XCTAssertFalse(AgentLoop.newThingNoted("第23项：网易头条新闻正文第一句话…（更正）", before: [23]), "the same thing again")
        XCTAssertFalse(AgentLoop.newThingNoted("未能完成：第25项（一直点一个没反应的地方）", before: []))
        XCTAssertFalse(AgentLoop.newThingNoted("新学到的做法：先回到首页", before: []))
    }

    /// D52, y4 on 136 (item 3): 微信's back after an item in 淘宝 ended is no back-and-forth with 淘宝's taps.
    func testMovesInTheLastAppAreNoBackAndForthInTheNext() {
        func tap(_ x: Int, _ y: Int) -> JObject { ["action": .str("tap"), "x": .int(x), "y": .int(y)] }
        let taobao = [tap(247, 765), tap(56, 89), tap(246, 765)]
        XCTAssertNotNil(AgentLoop.bounce(tap(56, 89), after: taobao), "in one app it is a back-and-forth")
        let then: [JObject] = [["action": .str("part done")], ["action": .str("open"), "app": .str("微信")]]
        XCTAssertNil(AgentLoop.bounce(tap(56, 89), after: taobao + then))
        XCTAssertNil(AgentLoop.bounce(tap(56, 89), after: taobao + [["action": .str("thing skipped")]]))
    }

    /// D53, y4 on 136 (item 27): after two swipes with nothing noted, what was said while scrolling is shown again.
    func testWhatWasSaidWhileScrollingIsShownAgain() {
        func swipe(_ thought: String) -> JObject {
            ["action": .str("swipe"), "x1": .int(40), "y1": .int(800), "x2": .int(40), "y2": .int(350), "thought": .str(thought)]
        }
        let open: JObject = ["action": .str("tap"), "x": .int(284), "y": .int(493)]
        let hint = AgentLoop.scrollingHint([open, swipe("關於本機 shows 機型名稱 iPhone 13 mini"), swipe("容量 256GB is shown")])
        XCTAssertTrue(hint?.contains("iPhone 13 mini") == true && hint?.contains("256GB") == true, hint ?? "nil")
        XCTAssertTrue(hint?.contains("note TEXT") == true)
        XCTAssertNil(AgentLoop.scrollingHint([open, swipe("a")]), "one swipe")
        XCTAssertNil(AgentLoop.scrollingHint([swipe("a"), ["action": .str("note"), "text": .str("第24项：…")], swipe("b")]),
                     "noted since")
    }

    /// D54, 136 y3–y6: a message's send time is the nearest time line above it, worked out by the program, not a model.
    func testTheSendTimeOfAMessageIsWorkedOutFromTheTimeLineAboveIt() {
        let lines = ["昨天清晨6:43", "Z5全部做完", "昨天下午1:20", "（我）133真人测试一", "昨天下午2:34", "Y1温差大"]
        XCTAssertEqual(AgentLoop.sentTimes(of: "133真人测试一", in: lines), ["昨天下午1:20"])
        let note = AgentLoop.readUpNote(lines, screens: 5, until: "133真人测试一")
        XCTAssertTrue(note.contains("程序按时间行算出：“133真人测试一”的发送时间是“昨天下午1:20”"), note)
        let twice = lines + ["今天上午8:13", "133真人测试一"]
        XCTAssertEqual(AgentLoop.sentTimes(of: "133真人测试一", in: twice), ["昨天下午1:20", "今天上午8:13"])
        XCTAssertTrue(AgentLoop.readUpNote(twice, screens: 5, until: "133真人测试一").contains("共读到2条"))
        XCTAssertTrue(AgentLoop.isChatTimeLine("11月14日 下午3:30"))
        XCTAssertTrue(AgentLoop.isChatTimeLine("凌晨12:20"))
        XCTAssertFalse(AgentLoop.isChatTimeLine("Y3验证2:32"), "a message with a time in it")
        XCTAssertFalse(AgentLoop.readUpNote(["a"], screens: 1, until: "b").contains("程序按时间行算出"))
    }
}

/// A model whose account is overdue: every call answers HTTP 403 AccountOverdueError (D47).
@MainActor private final class OverdueModel: ChatModel {
    let model = "doubao"
    private(set) var calls = 0
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        calls += 1
        throw LLMError(message: #"LLM HTTP 403: {"error":{"code":"AccountOverdueError","message":"overdue"}}"#)
    }
}
