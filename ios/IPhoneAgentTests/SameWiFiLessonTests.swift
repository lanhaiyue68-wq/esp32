import XCTest
@testable import IPhoneAgent

/// Firmware v22 has no hotspot: the phone and the board meet on one Wi-Fi, and the app never joins a network.
final class SameWiFiTests: XCTestCase {
    private func status(_ json: String) -> BoardStatus { BoardStatus.decode(Data(json.utf8))! }

    func testSameWiFiNeedsAConnectedStationThatThePhoneReached() {
        XCTAssertNil(SameWiFi.problem(connected: true, status: status(#"{"net":"sta","ip":"192.168.13.12","sta":1,"tcp":1}"#), boardSSID: "Home"))
        let notReached = SameWiFi.problem(connected: true, status: status(#"{"net":"sta","ip":"192.168.13.12","sta":1,"tcp":0}"#), boardSSID: "Home")
        XCTAssertTrue(notReached?.contains("Home") == true)
    }

    func testWaitingBoardAndOldFirmwareAreExplained() {
        let waiting = SameWiFi.problem(connected: true, status: status(#"{"net":"none","ip":"0.0.0.0","sta":0,"tcp":0}"#), boardSSID: "Home")
        XCTAssertTrue(waiting?.contains("Home") == true)
        XCTAssertNotNil(SameWiFi.problem(connected: true, status: status(#"{"net":"none","sta":0}"#), boardSSID: ""))
        XCTAssertNotNil(SameWiFi.problem(connected: true, status: status(#"{"net":"ap","ip":"192.168.4.1","sta":1}"#), boardSSID: "ESP32Agent-CEED"))
        XCTAssertNotNil(SameWiFi.problem(connected: false, status: nil, boardSSID: "Home"))
    }

    func testReducedStatusKeepsTheLastTcpValue() {
        let full = status(#"{"net":"sta","tcp":1,"ble":{"mtu":512}}"#)
        let short = status(#"{"up":2,"net":"sta","ap":"idle","ble":{"mtu":23}}"#)
        XCTAssertEqual(full.merged(with: short).tcp, 1)
    }
}

/// Silence during a run keeps the app alive in the background; starting and stopping must be safe in any order.
@MainActor final class BackgroundAudioTests: XCTestCase {
    func testStartReportsWhetherItPlaysAndStopIsIdempotent() {
        let audio = BackgroundAudio()
        audio.stop()  // before any start: nothing to do
        let started = audio.start()
        XCTAssertEqual(audio.playing, started)
        XCTAssertEqual(audio.start(), started)  // a second start while playing changes nothing
        audio.stop()
        XCTAssertFalse(audio.playing)
        audio.stop()
    }
}

@MainActor final class LessonBookTests: XCTestCase {
    func testNotesReachSimilarTasksOnly() {
        let book = LessonBook(file: nil)
        book.learn(group: "run1:review", task: "打开白板画一个笑脸", items: [("a", "打开时已经有画好的脸，就要新建一个白板再画")])
        XCTAssertTrue(book.context(task: "打开无边记画个笑脸").contains("新建一个白板"))
        XCTAssertEqual(book.context(task: "打开微信给妈妈发消息"), "")
    }

    func testGeneralNotesReachEveryTaskAndRelearningReplaces() {
        let book = LessonBook(file: nil)
        book.learn(group: "run1:review", task: "设置闹钟", items: [("a", "通用：完成前先截图确认结果")])
        XCTAssertTrue(book.context(task: "打开微信给妈妈发消息").contains("完成前先截图确认结果"))
        XCTAssertFalse(book.context(task: "anything").contains("通用"))
        book.learn(group: "run1:review", task: "设置闹钟", items: [])
        XCTAssertEqual(book.count, 0)
    }

    func testLessonsPersistAndCanBeSwitchedOff() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lessons-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        LessonBook(file: file).learnHints(["Type the time instead of scrolling the wheel"], task: "Set an alarm at 7", run: "r1")
        let again = LessonBook(file: file)
        XCTAssertTrue(again.context(task: "Set an alarm at 6").contains("Type the time"))
        again.enabled = false
        XCTAssertEqual(again.context(task: "Set an alarm at 6"), "")
    }

    func testLessonsReachThePlannerAndTheActor() async {
        let model = SystemRecorder { n in n == 1 ? "1. go" : "THINK: there\nDO: done ok" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: model, planner: model, trace: nil)
        let book = LessonBook(file: nil)
        book.learn(group: "r:review", task: "test", items: [("a", "通用：Never trust a result you did not make")])
        agent.lessons = book
        await agent.run()
        XCTAssertTrue(model.systems[0].contains("Never trust a result you did not make"))
        XCTAssertTrue(model.systems[1].contains("Never trust a result you did not make"))
    }

    func testSelfLearnedLessonsRankBelowTheUsersAndAreCapped() {
        let book = LessonBook(file: nil)
        book.learnFromRun("r1", task: "打开白板画一个笑脸",
                          lessons: (1...6).map { "自学经验\($0)" })  // the reviewer may say more; only 3 are parsed, but cap anyway
        book.learn(group: "r0:review", task: "打开白板画笑脸", items: [("a", "已经有脸就新建白板")])
        let context = book.context(task: "打开白板画一个笑脸")
        let user = context.range(of: "已经有脸就新建白板"), own = context.range(of: "自学经验")
        XCTAssertNotNil(user); XCTAssertNotNil(own)
        XCTAssertLessThan(user!.lowerBound, own!.lowerBound)
        XCTAssertEqual(book.relevant(to: "打开白板画一个笑脸").filter { $0.auto == true }.count, 4)
    }

    func testMarkingARunWrongDropsWhatTheModelLearnedFromIt() {
        let book = LessonBook(file: nil)
        book.learnFromRun("r1", task: "打开白板画一个笑脸", lessons: ["脸已经画好，可以直接完成"])
        let draft = ReviewDraft(source: .run, folder: nil, runID: "r1", outcome: .done,
                                steps: [DraftStep(action: ["action": .str("done")], verdict: false, note: "不能就这样交了")],
                                name: "", prompt: "打开白板画一个笑脸")
        book.learnReview(draft)
        let context = book.context(task: "打开白板画一个笑脸")
        XCTAssertFalse(context.contains("可以直接完成"))
        XCTAssertTrue(context.contains("不能就这样交了"))
    }

    func testReviewerRepliesAreParsedAndThePlanIsLeftOut() {
        XCTAssertEqual(LessonBook.parseLessons("LESSON: 点搜索框再输入\nnoise\nlesson: 新建按钮在右下角\nLESSON:\nLESSON: c\nLESSON: d"),
                       ["点搜索框再输入", "新建按钮在右下角", "c"])
        XCTAssertEqual(LessonBook.parseLessons("NONE"), [])
        let input = LessonBook.reflectionInput(task: "t", steps: [["action": .str("plan"), "plan": .str("SECRET PLAN")],
                                                                   ["action": .str("tap"), "x": .int(1), "y": .int(2), "changed": .bool(false)]])
        XCTAssertFalse(input.contains("SECRET PLAN"))
        XCTAssertTrue(input.contains("(screen did not change)"))
    }

    func testTokensSplitChineseIntoPairsAndOtherScriptsIntoWords() {
        XCTAssertEqual(LessonBook.tokens("画笑脸 Draw a face"), ["画笑", "笑脸", "draw", "face"])
    }
}
