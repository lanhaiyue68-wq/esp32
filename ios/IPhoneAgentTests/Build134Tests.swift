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
        let note = "9. 深圳AQI 12优\n10. 已在验证群发“Y1验证9:47”\n11. 小红书前4篇：1.深圳Citywalk…"
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
        let hold: JObject = ["action": .str("hold"), "x": .int(580), "y": .int(462), "thought": .str("tomorrow 3 p.m. is 26°")]
        XCTAssertTrue(AgentLoop.scrollingHint([open, hold, hold])?.contains("26°") == true, "holds that read a value count too")
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

    /// D57, s2 on 137: an answer with its line breaks written out ("\\n") gets real ones; typed text keeps them as they are.
    func testWrittenOutLineBreaksInAnAnswerAreBreaks() throws {
        XCTAssertEqual(try Actions.parseCommand(#"done 以下是前10家：\n\n1. 老四川大排档\n2. 川味烧烤"#)["answer"]?.str,
                       "以下是前10家：\n\n1. 老四川大排档\n2. 川味烧烤")
        XCTAssertEqual(try Actions.parseCommand(#"fail 京东要求登录\n未查到价格"#)["reason"]?.str, "京东要求登录\n未查到价格")
        XCTAssertEqual(try Actions.parseCommand(#"type C:\new\notes"#)["text"]?.str, #"C:\new\notes"#, "typed text stays literal")
    }

    /// D59, user 11-16: a security check is the owner's to do by hand; the run goes on after it, or notes the thing not done.
    func testASecurityCheckIsLeftToTheOwner() async throws {
        XCTAssertEqual(try Actions.parseCommand("verify 淘宝")["app"]?.str, "淘宝")
        XCTAssertTrue(AgentLoop.verifyQuestion("淘宝").contains("亲手完成"))
        func run(_ answer: Bool?) async -> AgentLoop {
            let actor = FakeModel { $0 == 1 ? "THINK: 出现了滑块验证\nDO: verify 淘宝" : "THINK: 验证没了\nDO: done 第一个是9.9元" }
            let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: actor, planner: nil, trace: nil)
            agent.directStart = true  // no planner: the actor works from the screen (138 CI: without it, "no planner model")
            agent.askVerify = { _ in answer }
            agent.showMock(task: "查一下保温杯第一个多少钱", plan: "", steps: [], running: false)
            await agent.run()
            return agent
        }
        let done = await run(true)
        let kinds = done.steps.map { $0["action"]?.str ?? "?" }
        XCTAssertTrue(kinds.contains("needs verification") && kinds.contains("verified by owner"), "\(kinds)")
        XCTAssertEqual(kinds.last, "done", "\(kinds)")
        for answer in [false, nil] as [Bool?] {
            let left = await run(answer)
            XCTAssertEqual(left.steps.last?["action"]?.str, "fail", "\(answer as Any)")
            XCTAssertTrue(left.steps.last?["reason"]?.str?.contains("人工安全验证") == true, "\(answer as Any)")
        }
    }

    /// D64, y3 on 137 (item 9): function keys are one key, AC clears all, and keys the screen reading missed are typed.
    func testCalculatorFunctionKeysArePressedAsKeys() {
        func key(_ t: String, _ x: Double, _ y: Double) -> CandidatePicker.Piece {
            .init(text: t, box: CGRect(x: x - 0.03, y: y - 0.015, width: 0.06, height: 0.03))
        }
        let pad = [key("xY", 0.58, 0.34), key("2x", 0.89, 0.34), key("AC", 0.38, 0.62), key("2", 0.38, 0.82)]
        func shown(_ s: [AgentLoop.KeyStep]?) -> [String] {
            (s ?? []).map { step -> String in
                switch step {
                case .type(let t): return t
                case .tap(let p): return String(format: "tap %.2f %.2f", Double(p.x), Double(p.y))
                }
            }
        }
        XCTAssertEqual(AgentLoop.keyTokens("AC 30 2x", keys: ["2X"]), ["AC", "3", "0", "2x"])
        XCTAssertEqual(AgentLoop.keyTokens("2 xʸ 30 ="), ["2", "xʸ", "3", "0", "="])
        XCTAssertEqual(AgentLoop.keyTokens("128x0.85="), ["1", "2", "8", "x", "0", ".", "8", "5", "="], "x between numbers is ×")
        XCTAssertTrue(AgentLoop.namesFunctionKey("AC 30 2x"))
        XCTAssertFalse(AgentLoop.namesFunctionKey("AC 128 × 0.85 ="))
        XCTAssertEqual(AgentLoop.keyLabel("xʸ"), AgentLoop.keyLabel("xY"))
        XCTAssertNil(AgentLoop.typedKeys(AgentLoop.keyTokens("2 xʸ 30 =")), "xʸ has no key of its own")
        XCTAssertEqual(shown(AgentLoop.mixedKeys("2 xʸ 30 =", in: pad)), ["2", "tap 0.58 0.34", "30="])
        XCTAssertEqual(shown(AgentLoop.mixedKeys("AC 30 2x", in: pad)), ["esc", "esc", "30", "tap 0.89 0.34"])
        XCTAssertNil(AgentLoop.mixedKeys("2 √ 2 =", in: pad), "√ was not read and the keyboard has none")
        XCTAssertNil(AgentLoop.mixedKeys("2 + 2 =", in: pad), "all typed: nothing to tap")
    }

    /// D62, y3 on 137 (item 41): in a goal of many things a stall of swipes gets a new plan before the thing is skipped.
    func testAStallOfSwipesGetsCodexBeforeTheThingIsSkipped() {
        XCTAssertEqual(AgentLoop.stallsToSkip(bigGoal: true, swiping: true), 2)
        XCTAssertEqual(AgentLoop.stallsToSkip(bigGoal: true, swiping: false), 1)
        XCTAssertEqual(AgentLoop.stallsToSkip(bigGoal: false, swiping: true), AgentLoop.stallLimit)
    }

    /// D63, y3 on 137: the coach is shown what the app rules say of the app it is stuck in.
    func testTheCoachIsToldWhatIsKnownOfTheApp() {
        let rules = "Calendar (日曆/日历), month view: the months scroll up and down, never sideways.\nWeChat: chats."
        XCTAssertTrue(AgentLoop.appRuleLines("日曆", rules: rules).contains("scroll up and down"))
        XCTAssertFalse(AgentLoop.appRuleLines("日曆", rules: rules).contains("WeChat"))
        XCTAssertEqual(AgentLoop.appRuleLines("小红书", rules: rules), "")
        XCTAssertTrue(AgentLoop.appRuleLines("行事曆").contains("sideways"), "the real rules name 日历")
    }

    /// D65, y3 on 137 (item 20): what the done check found wrong stays in the notes for the answer written at the end.
    /// D86, z1 on 138 (item 21): the result Calculator shows is read, and a note without it is known.
    func testANoteOnCalculatorHoldsItsResult() {
        typealias P = CandidatePicker.Piece
        func row(_ t: String, _ y: CGFloat) -> [P] { [P(text: t, box: CGRect(x: 0.5, y: y, width: 0.2, height: 0.03))] }
        let scientific = [row("97-5", 0.15), row("19.4", 0.207), row("mc", 0.276), row("x2", 0.342), row("AC", 0.618),
                          row("%", 0.619), row("7", 0.688), row("1", 0.827)]
        XCTAssertEqual(AgentLoop.calculatorResult(scientific), "19.4")
        let plain = [row("2,388,581.1428571", 0.38), row("AC", 0.47), row("%", 0.47), row("7", 0.6)]
        XCTAssertEqual(AgentLoop.calculatorResult(plain), "2388581.1428571")
        XCTAssertNil(AgentLoop.calculatorResult([row("0", 0.38), row("AC", 0.47)]), "nothing worked out")
        XCTAssertNil(AgentLoop.calculatorResult([row("19.4", 0.3)]), "no keys: not Calculator")
        XCTAssertFalse(AgentLoop.holdsNumber("第21项：五城最高温总和87°C，平均为17.4°C。", "19.4"))
        XCTAssertTrue(AgentLoop.holdsNumber("第21项：五城最高温总和97°C，平均为19.4°C。", "19.4"))
        XCTAssertTrue(AgentLoop.holdsNumber("第32项：≈ 2,388,581.14。", "2388581.1428571"), "rounded, with commas")
        XCTAssertTrue(AgentLoop.holdsNumber("第17项：√2 × 1000 ≈ 1414.21", "1414.2135623"))
        XCTAssertTrue(AgentLoop.holdsNumber("2的30次方 = 1,073,741,824", "1073741824"))
    }

    /// D87, z1 on 138 (item 38): the days of a weekday in a month are worked out by the calendar.
    func testTheDaysOfAWeekdayInAMonthArePutRight() {
        let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 17))!
        XCTAssertEqual(AgentLoop.rightWeekdayLists("38. 2027年2月共有4个星期一，分别是2日、9日、16日、23日。", today: today),
                       "38. 2027年2月共有4个星期一，分别是1日、8日、15日、22日。")
        XCTAssertEqual(AgentLoop.rightWeekdayLists("2027年2月星期一共4个：2、9、16、23日", today: today), "2027年2月星期一共4个：2、9、16、23日",
                       "the count after the weekday is not this form")
        XCTAssertEqual(AgentLoop.rightWeekdayLists("2027年2月有4个星期一：2、9、16、23日", today: today), "2027年2月有4个星期一：1、8、15、22日")
        XCTAssertEqual(AgentLoop.rightWeekdayLists("2月有5个星期一", today: today), "2月有4个星期一", "February next year")
        let right = "2026年3月有5个星期日：1日、8日、15日、22日、29日"
        XCTAssertEqual(AgentLoop.rightWeekdayLists(right, today: today), right)
        XCTAssertEqual(AgentLoop.rightWeekdayLists("2027年2月有4个星期一，分别是2、9、16、23日，3月有5个星期一", today: today),
                       "2027年2月有4个星期一，分别是1、8、15、22日，3月有5个星期一", "3月 is not a day of the list")
        XCTAssertEqual(AgentLoop.rightFacts("1. 2027年2月共有4个星期一，分别是2日、9日、16日、23日；2. 12月25日是星期四", today: today),
                       "1. 2027年2月共有4个星期一，分别是1日、8日、15日、22日；2. 12月25日是星期五")
    }

    /// D85, y6 on 138 (item 22): a span said after two clock times in one item is worked out and put right.
    func testASpanBetweenTwoTimesIsPutRight() {
        XCTAssertEqual(AgentLoop.rightSpans("22. 深圳今天日出清晨6:37，日落下午5:39；记录中的白昼时长为11小时22分钟。\n23. 首尔85%"),
                       "22. 深圳今天日出清晨6:37，日落下午5:39；记录中的白昼时长为11小时2分钟。\n23. 首尔85%")
        XCTAssertEqual(AgentLoop.rightSpans("第22项：深圳今天日出清晨6:37，日落下午5:39，白昼时长11小时22分钟。"),
                       "第22项：深圳今天日出清晨6:37，日落下午5:39，白昼时长11小时2分钟。")
        let right = "9. 深圳日出6:37，日落17:39，白天11小时2分钟。"
        XCTAssertEqual(AgentLoop.rightSpans(right), right)
        XCTAssertEqual(AgentLoop.rightSpans("3. 深圳今天日出6:37，日落5:39，白天共11小时2分钟。"), "3. 深圳今天日出6:37，日落5:39，白天共11小时2分钟。",
                       "a later time with no 下午 that would come first is the afternoon")
        let train = "25. G4710次，06:02出发，06:31到达；页面显示暂无余票。"
        XCTAssertEqual(AgentLoop.rightSpans(train), train, "no span said")
        XCTAssertEqual(AgentLoop.rightSpans("从9:00到17:30，共8小时"), "从9:00到17:30，共8小时30分钟")
        let three = "1. 6:00起床，7:00出门，9:00到，共5小时"
        XCTAssertEqual(AgentLoop.rightSpans(three), three, "three times: which two is unclear")
        XCTAssertEqual(AgentLoop.rightSpans("1. 9:00到17:30，共8小时30分钟；2. 8:00到9:00，用时2小时"),
                       "1. 9:00到17:30，共8小时30分钟；2. 8:00到9:00，用时1小时", "each item on its own")
    }

    /// D84, y5 on 138 (item 43): Lan Agent's own keyboard is known on screen by its status line and its keys.
    func testOurKeyboardIsKnownOnScreen() {
        typealias P = CandidatePicker.Piece
        let keys = [P(text: "下一個", box: CGRect(x: 0.1, y: 0.78, width: 0.12, height: 0.02)),
                    P(text: "空格", box: CGRect(x: 0.34, y: 0.78, width: 0.07, height: 0.02)),
                    P(text: "搜尋", box: CGRect(x: 0.82, y: 0.78, width: 0.07, height: 0.02))]
        let ours: [[P]] = [
            [P(text: "Python教程毛", box: CGRect(x: 0.15, y: 0.07, width: 0.3, height: 0.03))],
            [P(text: "連不上 Lan Agent（請先打開 Lan Agent）", box: CGRect(x: 0.13, y: 0.73, width: 0.74, height: 0.02))],
            keys,
        ]
        XCTAssertTrue(CandidatePicker.ourKeyboardShown(rows: ours))
        XCTAssertTrue(CandidatePicker.ourKeyboardShown(rows: [[P(text: "Lan Agent 已填入：猫", box: CGRect(x: 0.3, y: 0.73, width: 0.4, height: 0.02))], keys]))
        XCTAssertFalse(CandidatePicker.ourKeyboardShown(rows: [[P(text: "空格", box: CGRect(x: 0.4, y: 0.95, width: 0.1, height: 0.02))]]),
                       "the system keyboard")
        XCTAssertFalse(CandidatePicker.ourKeyboardShown(rows: [[P(text: "Lan Agent 真好用", box: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.02))], keys]),
                       "a chat line high on the screen is not the keyboard")
        XCTAssertFalse(CandidatePicker.ourKeyboardShown(rows: [[P(text: "請到 設定 › 一般 › 鍵盤 › Lan Agent 打開「允許完整取用」", box: CGRect(x: 0.1, y: 0.73, width: 0.8, height: 0.04))], keys]),
                       "without Full Access it never asks")
    }

    /// D83, y4 on 138 (item 27): what was said while scrolling is noted by the run under the part's item.
    func testWhatWasSaidWhileScrollingIsNoted() {
        let a = "The 關於本機 page shows 機型名稱 iPhone 13 mini; total capacity is not visible, so I swipe up to find it."
        let b = "I'm on the 關於本機 page. The total capacity shows 256 GB, but the model name is above the visible area."
        let steps: [JObject] = [
            ["action": .str("tap"), "thought": .str("I tap 關於本機.")],
            ["action": .str("swipe"), "thought": .str(a)],
            ["action": .str("swipe"), "thought": .str(b)],
            ["action": .str("swipe"), "thought": .str(a)],
            ["action": .str("note"), "text": .str("第27项：总容量为256GB。")],
            ["action": .str("refused"), "reason": .str("Refused: this page was already scrolled")],
        ]
        XCTAssertEqual(AgentLoop.seenWhileScrollingNote(steps, part: "2. 第27项：Read the model name and total capacity"),
                       "第27项（滚动页面时看到，原话）：" + a + " " + b)
        XCTAssertEqual(AgentLoop.seenWhileScrollingNote(steps, part: nil), "（滚动页面时看到，原话）：" + a + " " + b)
        XCTAssertEqual(AgentLoop.seenWhileScrollingNote(steps, part: "1. 第21–30项：x"), "（滚动页面时看到，原话）：" + a + " " + b)
        XCTAssertNil(AgentLoop.seenWhileScrollingNote([["action": .str("tap")]], part: nil))
    }

    /// D81, y4 on 138 (item 40): a thing that asks for a message is not done by a note of what was read on the way.
    func testAThingThatSendsIsDoneWhenItsMessageWent() {
        let items = (1...12).map { n in
            n == 10 ? "10. 如果深圳今天最高温比首尔高10度以上，就在微信测试群发“Y4温差大”，否则发“Y4温差小”" : "\(n). 查第\(n)样东西"
        }
        let task = "帮我做这12件事：" + items.joined(separator: "；")
        let told = (1...9).map { "第\($0)项：有" } + ["第11项：有", "第12项：有", "第10项：首尔今日最高温14°，最低温10°"]
        XCTAssertEqual(AgentLoop.itemsLeft(task: task, told: told, sent: []), [10])
        XCTAssertEqual(AgentLoop.itemsLeft(task: task, told: told, sent: [AgentLoop.typedKey("Y4温差大")]), [])
        XCTAssertEqual(AgentLoop.itemsLeft(task: task, told: told + ["第10项未完成：微信发送被拒"], sent: []), [])
        XCTAssertEqual(AgentLoop.itemsLeft(task: task, told: Array(told.dropLast()) + ["第10项：温差14度；第11项：有"], sent: []), [10],
                       "what is said of 10 ends at 11's head")
        XCTAssertEqual(AgentLoop.itemsLeft(task: task, told: Array(told.dropLast()) + ["第10项：条件不满足，不发"], sent: []), [])
    }

    /// D82, y4 on 138: parts whose items were noted inside an earlier part are passed; the plan's last part is not.
    func testPartsNotedOnTheWayArePassed() {
        let task = "帮我做这12件事：" + (1...11).map { "\($0). 查第\($0)样东西" }.joined(separator: "；") + "；12. 把结果告诉我"
        let parts = ["1. 第8项：x", "2. 第9项：x", "3. 第10项：x", "4. 第11项：x", "5. 第12项：x"]
        let told = (1...7).map { "第\($0)项：有" } + ["第8项：有", "第9项：有", "第10项：有"]
        XCTAssertEqual(AgentLoop.partsNoted(parts, from: 1, task: task, told: told, sent: []), 2, "9 and 10 noted; 11 is not")
        XCTAssertEqual(AgentLoop.partsNoted(parts, from: 3, task: task, told: told, sent: []), 0)
        let all = (1...12).map { "第\($0)项：有" }
        XCTAssertEqual(AgentLoop.partsNoted(parts, from: 1, task: task, told: all, sent: []), 3, "the last part stays")
        XCTAssertEqual(AgentLoop.partsNoted(["1. 第8项：x", "2. Open 微信", "3. 第10项：x"], from: 1, task: task, told: all, sent: []), 0,
                       "a part with no item number is not passed")
        XCTAssertEqual(AgentLoop.partItems("3. 第21–30项：x"), Array(21...30))
        XCTAssertEqual(AgentLoop.partItems("3. 第43项：x"), [43])
        XCTAssertNil(AgentLoop.partItems("Open 微信"))
        let small = "帮我做3件事：1. a；2. b；3. c"
        XCTAssertEqual(AgentLoop.partsNoted(["1. 第1项：a", "2. 第2项：b", "3. 第3项：c"], from: 0, task: small, told: ["第1项：有"], sent: []), 0)
    }

    /// D79, y3 on 138 (item 1): "距<today>还有81天" counts from today to the date said before it; it is not 0.
    func testADayCountFromTodayRunsToTheDateSaidBefore() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 3))!
        let wrong = "1. 2027年春节是2027年2月6日，星期六；距2026年11月17日还有0天。\n2. 拼多多29.4元"
        XCTAssertEqual(AgentLoop.rightDayCounts(wrong, today: today, calendar: cal),
                       "1. 2027年春节是2027年2月6日，星期六；距2026年11月17日还有81天。\n2. 拼多多29.4元")
        let right = "1. 2027年春节是2027年2月6日，星期六；距2026年11月17日还有81天。"
        XCTAssertEqual(AgentLoop.rightDayCounts(right, today: today, calendar: cal), right)
        XCTAssertEqual(AgentLoop.rightDayCounts("2. 距2026年11月17日还有5天", today: today, calendar: cal), "2. 距2026年11月17日还有5天",
                       "no date before it in the item: left alone")
        XCTAssertEqual(AgentLoop.rightDayCounts("距离2027年2月6日还有88天", today: today, calendar: cal), "距离2027年2月6日还有81天")
    }

    /// D80, y3 on 138: a part keeps its own number before its run of items; an item put off is no result.
    func testAPartNumberedInThePlanStillHasItsRun() {
        XCTAssertEqual(AgentLoop.partItemRange("3. 第21–30项：Complete the conditional WeChat message"), 21...30)
        XCTAssertEqual(AgentLoop.partItemRange("1. 第1–10项：Record the requested dates"), 1...10)
        XCTAssertNil(AgentLoop.partItemRange("5. 第46项：A new note contains items 1–45"))
        let task = "帮我做这30件事：" + (1...30).map { "\($0). 查第\($0)样东西" }.joined(separator: "；")
        let told = ["第21项：已发送", "3. 第21–30项：x -> 第21–30项已完成：第21项已发送；第24项待后续记录；第25项下水径253米；第28项待后续记录"]
        let left = AgentLoop.itemsLeft(task: task, told: told, sent: []).filter { (21...30).contains($0) }
        XCTAssertEqual(left, [22, 23, 24, 26, 27, 28, 29, 30])
    }

    /// D78, y2 on 138 (item 46): new lines written into a memo are the work getting on; the same text again is not.
    func testWritingNewLinesIsGettingOn() {
        let line = "23. 2027年2月有4个星期一：1日、8日、15日、22日。"
        let typed: JObject = ["action": .str("type"), "text": .str(line)]
        let earlier: [JObject] = [["action": .str("type"), "text": .str("22. 深圳citywalk前4篇笔记标题已记下。")], ["action": .str("key")]]
        XCTAssertTrue(AgentLoop.typedNewText(typed, earlier: earlier[...]))
        XCTAssertFalse(AgentLoop.typedNewText(typed, earlier: (earlier + [typed])[...]), "typed before")
        XCTAssertFalse(AgentLoop.typedNewText(["action": .str("type"), "text": .str("保温杯")], earlier: earlier[...]), "a search")
        XCTAssertFalse(AgentLoop.typedNewText(["action": .str("note"), "text": .str(line)], earlier: earlier[...]))
    }

    /// D77, y2 on 138: an empty line under "结果如下：" does not end the answer; the numbered results under it are kept.
    func testAnEmptyLineInsideAnAnswerKeepsWhatFollows() throws {
        let reply = "THINK: 现在按编号整理全部结果汇报。\nDO: done 已完成全部49项任务的整理与汇报，结果如下：\n\n1. 深圳AQI 35，体感24℃。\n"
            + "2. 第一个数据线¥2.16。\n\n3. 支付宝评分4.5\n```"
        let acts = try Actions.parseActions(reply)
        XCTAssertEqual(acts.count, 1)
        XCTAssertEqual(acts[0]["answer"]?.str, "已完成全部49项任务的整理与汇报，结果如下： 1. 深圳AQI 35，体感24℃。；2. 第一个数据线¥2.16。；3. 支付宝评分4.5")
        let two = try Actions.parseActions("THINK: 好\nDO: done 好了\n\nDO: tap 100 200")
        XCTAssertEqual(two.count, 2, "the next label still ends it")
        XCTAssertEqual(two[0]["answer"]?.str, "好了")
    }

    /// D76, y1 on 138 (item 39): a date a note found gets its days from today worked out, as a date the goal names does.
    func testADateANoteFoundIsCountedFromToday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 0, minute: 5))!
        let goal = "用 Safari 查2027年春节是几月几号，再用计算器算从今天（以日历为准）到那天还有多少天；在日历看2026年12月25日是星期几"
        let notes = ["第39项：2027年春节为2027年2月6日（星期六），除夕为2月5日（星期五）", "第1项：2026年12月25日是星期五"]
        let said = AgentLoop.foundDateFacts(notes, goal: goal, today: today, calendar: cal)
        XCTAssertTrue(said.contains("2027-02-06, Saturday (星期六) 81 days from today"), said)
        XCTAssertTrue(said.contains("2027-02-05, Friday (星期五) 80 days from today"), said)
        XCTAssertFalse(said.contains("2026-12-25"), "the goal's own date is said once, with the goal's")
        XCTAssertEqual(AgentLoop.foundDateFacts([], goal: goal, today: today, calendar: cal), "")
        XCTAssertTrue(AgentLoop.dateFacts(in: goal, today: today, calendar: cal).hasPrefix(" Dates in the goal: 2026-12-25"))
    }

    /// D75, s7 on 138: "设置步骤" is the steps to set something up, not the Settings app.
    func testSettingStepsNameNoApp() {
        let task = "在小红书搜“iPhone 定时关机 快捷指令”，打开前三篇笔记，整理出一份设置步骤；看看每篇是什么时候发的"
        let steps: [JObject] = [["action": .str("open"), "app": .str("小红书")]]
        XCTAssertEqual(AgentLoop.unvisitedApps(task: task, steps: steps), [])
        XCTAssertEqual(AgentLoop.unvisitedApps(task: "怎么设置定时关机？在小红书查一下", steps: steps), [])
        XCTAssertEqual(AgentLoop.unvisitedApps(task: "在设置的“通用-关于本机”里看型号名称", steps: steps), ["设置"])
        XCTAssertEqual(AgentLoop.unvisitedApps(task: "在设置里看电池电量", steps: steps), ["设置"])
    }

    /// D74, h06 on 138: an app is not on the phone only by Home Screen pages that were read; no Home Screen is no answer.
    func testNoHomeScreenSaysNothingOfWhetherAnAppIsThere() {
        XCTAssertTrue(AppModel.absentFromPages(sawHome: true, readFailed: false))
        XCTAssertFalse(AppModel.absentFromPages(sawHome: false, readFailed: false), "京东's own pages were all it saw")
        XCTAssertFalse(AppModel.absentFromPages(sawHome: true, readFailed: true), "a page could not be read")
        let said = AppModel.noHomeToLookIn("京东")
        XCTAssertTrue(said.hasPrefix("京东 did not open this time"))
        XCTAssertTrue(said.contains("does not mean it is not on this phone"))
    }

    /// D73, z2 on 137: a Codex answer that hangs is given up well before 15 minutes, and not before a slow one is in.
    func testACodexAnswerHasADeadline() {
        XCTAssertGreaterThanOrEqual(ChatGPTPlus.answerDeadline, 120)
        XCTAssertLessThanOrEqual(ChatGPTPlus.answerDeadline, 240)
    }

    /// D72, z2 on 137: a run that stops early sends back what each part's "done" found, not only the separate notes.
    func testAStoppedRunSendsBackWhatEachPartFound() {
        let steps: [JObject] = [
            ["action": .str("note"), "text": .str("第1项：草莓酱爱咖啡版，点赞792")],
            ["action": .str("part done"), "part": .int(1)],
            ["action": .str("part done"), "part": .int(2), "found": .str("第6项：免拼购买价39.9元，179人好评")],
            ["action": .str("part done"), "part": .int(3), "found": .str("第1项：草莓酱爱咖啡版，点赞792")],
            ["action": .str("fail"), "reason": .str("手机上没有“携程”，机主选择不下载，任务结束")],
        ]
        XCTAssertEqual(CloudBridge.foundNotes(steps), ["第1项：草莓酱爱咖啡版，点赞792", "第6项：免拼购买价39.9元，179人好评"])
        XCTAssertTrue(CloudBridge.outcome(of: steps).answer.contains("已查到：第1项：草莓酱爱咖啡版，点赞792；第6项：免拼购买价39.9元"))
    }

    /// D71, y6 on 137: a feed that keeps playing does not stop the swipe to the next video, nor opening an app.
    func testAPlayingFeedDoesNotStopTheSwipeToTheNextVideo() {
        XCTAssertTrue(AgentLoop.staleProof(["action": .str("swipe"), "x1": .int(500), "y1": .int(800), "x2": .int(500), "y2": .int(300)]))
        XCTAssertTrue(AgentLoop.staleProof(["action": .str("open"), "app": .str("抖音")]))
        XCTAssertFalse(AgentLoop.staleProof(["action": .str("swipe"), "x1": .int(900), "y1": .int(500), "x2": .int(200), "y2": .int(520)]))
        XCTAssertFalse(AgentLoop.staleProof(["action": .str("swipe"), "x1": .int(500), "y1": .int(800), "x2": .int(500), "y2": .int(700)]))
        XCTAssertFalse(AgentLoop.staleProof(["action": .str("tap"), "x": .int(500), "y": .int(500)]))
    }

    /// D69, y5 on 137: a part over a run of items is not done while some of them have nothing written down.
    func testAPartOverARunOfItemsNeedsEachOfThem() {
        XCTAssertEqual(AgentLoop.partItemRange("第10–21项：各项结果或无法完成的原因已逐项记下 — 依次完成淘宝订单数"), 10...21)
        XCTAssertEqual(AgentLoop.partItemRange("第22-34项：各项结果"), 22...34)
        XCTAssertNil(AgentLoop.partItemRange("第24项：The cheapest-sorted first data cable"))
        XCTAssertNil(AgentLoop.partItemRange("第46项：A new note contains items 1–45"))
        let task = "帮我做这25件事：" + (1...25).map { "\($0). 查第\($0)样东西" }.joined(separator: "；")
        let notes = ["第10项：待付款0", "第11项：4个星期一", "第12项：已发送", "第13项：粉丝8921万", "第14项：只有北京",
                     "第15项：仪仗兵", "第20项：下水径256米", "第21项：25°"]
        let left = AgentLoop.itemsLeft(task: task, told: notes, sent: []).filter { (10...21).contains($0) }
        XCTAssertEqual(left, [16, 17, 18, 19])
        XCTAssertTrue(AgentLoop.itemsLeftInPartReason(left).hasPrefix("Not done: nothing is written down yet for 第16项、第17项、第18项、第19项."))
        XCTAssertTrue(AgentLoop.doneCheck.contains("carries the time when it was typed"))
    }

    func testWhatTheCheckFoundWrongIsKeptInTheNotes() {
        let line = AgentLoop.objectionNote("第20项把明天说成11月18日（周三），实际明天是11月17日（周二）。")
        XCTAssertTrue(line.hasPrefix("核对更正") && line.contains("11月17日"))
    }

    /// D67, y4 on 137: an item that holds its own numbered list does not cut the answer's count short.
    func testAListInsideAnItemDoesNotEndTheAnswer() {
        let lines = (1...20).map { $0 == 13 ? "13. 前4篇笔记标题：1. 自从iPhone拍照；2. 17是不是最难用；3. 气到发帖；4. 苹果17p" : "\($0). 结果\($0)" }
        XCTAssertEqual(AgentLoop.numberedItems(lines.joined(separator: "\n")).map { $0.n }, Array(1...20))
        XCTAssertFalse(AgentLoop.fewThingsTold(lines.joined(separator: "\n"), task: (1...20).map { "\($0). 查一下" }.joined(separator: "；")))
        XCTAssertEqual(AgentLoop.numberedItems("说明 3. 无关 1. 甲 2. 乙 3. 丙").map { $0.n }, [1, 2, 3])
        let readup = "往上读到的聊天记录（40 屏，从旧到新）：\n（我）Y1全部做完"
        let full = AgentLoop.completedAnswer("1. 甲", notes: [readup, "第2项：乙"], task: "1. 查甲；2. 查乙；3. 查丙；4. 查丁")
        XCTAssertTrue(full?.contains("第2项：乙") == true && full?.contains("往上读到") == false, full ?? "nil")
    }

    /// D68, y4 on 137: a part is closed by its own number, not by one in its last words.
    func testAPartIsClosedByItsOwnNumber() {
        let part = "第46项：A new “Y4组记录” note contains the previous results - open 備忘錄, including the outcome of item 44."
        XCTAssertFalse(AgentLoop.saysPartDone("第44项已完成，现在打开备忘录新建“Y4组记录”笔记。", part: 2, text: part))
        XCTAssertTrue(AgentLoop.saysPartDone("第46项已完成，现在打开微信。", part: 2, text: part))
        XCTAssertTrue(AgentLoop.saysPartDone("第18项完成。", part: 5, text: "18. 新建一条备忘录，下面写第1到第17项的结果"))
    }

    /// D60, y1 on 137 (item 10): back, the back arrow and back again that all left 测试群 where it was are no back-and-forth.
    func testMovesThatChangedNothingAreNoBackAndForth() {
        let back: JObject = ["action": .str("back")], arrow: JObject = ["action": .str("tap"), "x": .int(55), "y": .int(88)]
        func dead(_ s: JObject) -> JObject { var d = s; d["changed"] = .bool(false); return d }
        XCTAssertNotNil(AgentLoop.bounce(arrow, after: [back, arrow, back]), "moves that changed the screen")
        XCTAssertNil(AgentLoop.bounce(arrow, after: [dead(back), dead(arrow), dead(back)]))
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
