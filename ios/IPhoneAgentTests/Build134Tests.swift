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
