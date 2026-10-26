import XCTest
@testable import IPhoneAgent

@MainActor final class WatchTaskRetryTests: XCTestCase {
    private let claudeTask = "去 Claude 说你好"

    func testLoggedRetryKeepsTheClaudeTaskWordForWord() {
        XCTAssertEqual(WatchSettings.redo("重新去做", last: claudeTask), claudeTask)
    }

    func testRetryFeedbackAndReferencesKeepTheOriginalTask() {
        for request in ["这次重新去做", "上一条，重新去做", "刚才没有做好，重新去做。",
                        "請幫我重新去做一次！", "重新执行刚才的任务", "再來一次"] {
            XCTAssertEqual(WatchSettings.redo(request, last: claudeTask), claudeTask, request)
        }
    }

    func testAnExplicitNewDestinationIsNeverReplacedByThePreviousTask() {
        for request in ["重新去测试群发你好", "刚才没做好，这次去备忘录写你好",
                        "重新去做：打开微信给测试群发消息", "上一条不用做了，去设置打开蓝牙"] {
            XCTAssertEqual(WatchSettings.redo(request, last: claudeTask), request)
        }
    }

    func testBareRetryWithoutAGoalCannotStartAnInventedPhoneTask() {
        XCTAssertNil(WatchSettings.resolvedPhoneTask("重新去做", last: nil))
        XCTAssertNil(WatchSettings.resolvedPhoneTask("再来一次", last: " \n"))
        XCTAssertNil(WatchSettings.resolvedPhoneTask("重新去做", last: "再做一遍"))
        XCTAssertEqual(WatchSettings.resolvedPhoneTask(claudeTask, last: nil), claudeTask)
    }

    func testRepeatedRetriesKeepTheSameConcreteGoal() {
        let first = WatchSettings.resolvedPhoneTask("重新去做", last: claudeTask)
        XCTAssertEqual(WatchSettings.resolvedPhoneTask("刚才没有做好，再试一次", last: first), claudeTask)
        XCTAssertEqual(WatchSettings.resolvedPhoneTask("重新去测试群发你好", last: first), "重新去测试群发你好")
    }
}

@MainActor final class WatchTaskOutcomeTests: XCTestCase {
    func testOnlyAnExplicitDoneWithAUsefulAnswerReportsTheResult() {
        XCTAssertEqual(WatchSettings.phoneTaskResult(action: "done", answer: #"{"send":"已在 Claude 收到回复"}"#,
                                                     attempted: ["你好"]), "已在 Claude 收到回复")
    }

    func testFailOrStopCannotTurnASendGestureIntoDeliveryConfirmation() {
        for action in ["fail", "stopped", "error"] {
            let report = WatchSettings.phoneTaskResult(action: action, answer: #"{"send":"任务已完成"}"#,
                                                       attempted: ["你好"])
            XCTAssertTrue(report.contains("已尝试发送“你好”"), action)
            XCTAssertTrue(report.contains("未能确认任务完成"), action)
            XCTAssertFalse(report.contains("已发出"), action)
            XCTAssertFalse(report.contains("任务已完成"), action)
            XCTAssertFalse(report.contains("再发一次"), action)
        }
    }

    func testDoneWithoutAValidResultRemainsUnconfirmed() {
        for answer in ["", "done", #"{"send":"   "}"#, #"{"send":"🙂"}"#] {
            let report = WatchSettings.phoneTaskResult(action: "done", answer: answer, attempted: ["你好"])
            XCTAssertTrue(report.contains("未能确认任务完成"), answer)
        }
    }

    func testAFailureWithoutASendDoesNotInventASentMessage() {
        let report = WatchSettings.phoneTaskResult(action: "fail", answer: nil, attempted: [])
        XCTAssertTrue(report.contains("未能确认完成"))
        XCTAssertFalse(report.contains("已尝试发送"))
        XCTAssertFalse(report.contains("已发出"))
    }
}
