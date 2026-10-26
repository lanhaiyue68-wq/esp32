import Foundation
import XCTest
@testable import IPhoneAgent

@MainActor final class LearningVisibilityTests: XCTestCase {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("learning-\(UUID().uuidString).json")
    }

    func testUnsupportedScriptsAndMultilineTextRequireExactInput() {
        for text in ["🎉", "こんにちは", "مرحبا", "café", "let a = 1\nprint(a)", "先核对收件人，然后保存本次报告。"] {
            XCTAssertTrue(Pasteboard.prefersExact(text), "must preserve every character: \(text)")
        }
        XCTAssertFalse(Pasteboard.prefersExact("hello"))
        XCTAssertFalse(Pasteboard.prefersExact("早上好"))
    }

    func testOrdinaryTasksUseExactPasteWithoutEnablingWatchMode() async throws {
        for text in ["🎉", "こんにちは", "مرحبا", "let a = 1\nprint(a)", "先核对收件人，然后保存本次报告。"] {
            let encoded = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
            let model = FakeModel { _ in "DO: type \(encoded)" }
            let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: model, planner: model, trace: nil)
            agent.fastText = false
            var pasted: [String] = []
            agent.pasteHop = { value in pasted.append(value); return .filled }
            _ = try await agent.step()
            XCTAssertEqual(pasted, [text])
        }
    }

    func testQuotedActionTextPreservesCodeWhitespaceQuotesAndUnicode() throws {
        for text in ["  let name = \"小明\"\n  print(name)\n", "\"quoted\"", "C:\\work\\file", "مرحبا 🎉"] {
            let encoded = String(data: try JSONEncoder().encode(text), encoding: .utf8)!
            XCTAssertEqual(try Actions.parseActions("DO: type \(encoded)").first?["text"]?.str, text)
        }
    }

    func testVerificationCannotIgnoreChangedCodeOperatorsOrMessagePunctuation() {
        XCTAssertEqual(CandidatePicker.shows("value == 2", lines: ["value != 2"]), 0)
        XCTAssertEqual(CandidatePicker.shows("Send?", lines: ["Send!"]), 0)
        XCTAssertEqual(CandidatePicker.shows("value == 2", lines: ["value == 2"]), 1)
        XCTAssertEqual(CandidatePicker.shows("先检查，再保存", lines: ["先检查,再保存"]), 1,
                       "OCR full-width punctuation may be width-folded, but not discarded")
    }

    func testUnavailableExactPasteDoesNotTypeCodeAsPrematureEnterKeys() async {
        let text = "let a = 1\nprint(a)"
        let encoded = String(data: try! JSONEncoder().encode(text), encoding: .utf8)!
        let model = FakeModel { _ in "DO: type \(encoded)" }
        let phone = FakeGestures()
        let agent = AgentLoop(phone: phone, screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.pasteHop = { _ in .refused }
        do { _ = try await agent.step(); XCTFail("must stop before unsafe keyboard input") }
        catch { XCTAssertTrue(error is DeviceError) }
        XCTAssertTrue(phone.calls.isEmpty)
    }

    func testActualLessonReferencesAreCountedAndPersisted() throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let book = LessonBook(file: file)
        book.learn(group: "r1:review", task: "Set an alarm", items: [("a", "always: Check the result")])
        book.markUsed(book.relevant(to: "Set an alarm"))
        book.markUsed(book.relevant(to: "Set an alarm"))
        let data = try Data(contentsOf: file)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.first?["uses"] as? Int, 2)
        XCTAssertNotNil(LessonBook(file: file).lessons.first?.used)
    }

    func testDisabledLegacyLessonIsStoredButNeverRetrieved() throws {
        let file = location()
        defer { try? FileManager.default.removeItem(at: file) }
        let old = #"[{"id":"r:review:a","task":"alarm","text":"Never quote this disabled lesson","general":true,"updated":0,"disabled":true}]"#
        try Data(old.utf8).write(to: file)
        let book = LessonBook(file: file)
        XCTAssertEqual(book.count, 1)
        XCTAssertEqual(book.context(task: "alarm"), "")
    }

    func testAutomaticLearningLeavesARealBoundedStatusRecord() throws {
        let file = location()
        // Use the documented sidecar path; this checks persistence, not an invented UI counter.
        let activity = file.appendingPathExtension("activity.json")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: activity)
        }
        let book = LessonBook(file: file)
        book.learnFromRun("source-run", task: "Set an alarm", lessons: ["Clock: type the requested time before saving"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: activity.path))
        guard let data = try? Data(contentsOf: activity),
              let events = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        XCTAssertEqual(events.first?["id"] as? String, "source-run")
        XCTAssertEqual(events.first?["state"] as? String, "learned")
        XCTAssertEqual(events.first?["retained"] as? Int, 1)
    }

    func testDisableAndDeletionPersistAndInvalidatePendingReviews() throws {
        let file = location(), activity = file.appendingPathExtension("activity.json")
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: activity) }
        let book = LessonBook(file: file)
        book.learn(group: "r:review", task: "alarm", items: [("a", "always: Verify the saved alarm")])
        let lesson = try XCTUnwrap(book.lessons.first), pendingEpoch = book.epoch
        book.setEnabled(false, id: lesson.id)
        book.markUsed([lesson], run: "stale-reference", task: "alarm")
        XCTAssertNil(book.lessons.first?.uses)
        XCTAssertEqual(LessonBook(file: file).context(task: "alarm"), "")
        book.learnFromRun("late", task: "alarm", lessons: ["do not resurrect"], epoch: pendingEpoch)
        XCTAssertEqual(book.count, 1)
        book.remove(id: lesson.id)
        XCTAssertEqual(LessonBook(file: file).count, 0)
    }

    func testClearCannotBeUndoneByALateReviewOrItsStatus() {
        let book = LessonBook(file: nil)
        book.recordReview("r", task: "alarm", state: .reviewing, reason: "reviewing")
        let epoch = book.epoch
        book.clear()
        book.learnFromRun("r", task: "alarm", lessons: ["late result"], epoch: epoch)
        book.recordReview("r", task: "alarm", state: .failed, reason: "late failure", epoch: epoch)
        XCTAssertTrue(book.lessons.isEmpty)
        XCTAssertTrue(book.activity.isEmpty)
    }

    func testRestartMarksAbandonedReviewInterruptedWithoutInventingALesson() {
        let file = location(), activity = file.appendingPathExtension("activity.json")
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: activity) }
        LessonBook(file: file).recordReview("r", task: "alarm", state: .reviewing, reason: "reviewing")
        let restarted = LessonBook(file: file)
        XCTAssertEqual(restarted.activity.first?.state, .interrupted)
        XCTAssertEqual(restarted.count, 0)
    }

    func testReviewJournalIsBoundedAndDisabledLearningCollectsNoNewTask() throws {
        let file = location(), activity = file.appendingPathExtension("activity.json")
        defer { try? FileManager.default.removeItem(at: file); try? FileManager.default.removeItem(at: activity) }
        let book = LessonBook(file: file)
        for i in 0..<40 {
            book.recordReview("r\(i)", task: String(repeating: "任", count: 500), state: .skipped,
                              reason: String(repeating: "a", count: 500))
        }
        XCTAssertEqual(book.activity.count, 24)
        XCTAssertTrue(book.activity.allSatisfy { $0.task.count <= 200 && $0.reason.count <= 160 })
        XCTAssertLessThanOrEqual(try Data(contentsOf: activity).count, 32_000)
        book.enabled = false
        book.recordReview("disabled", task: "must not collect", state: .skipped, reason: "off")
        XCTAssertFalse(book.activity.contains { $0.id == "disabled" })
    }

    func testReferenceCounterRecordsRealRequestOncePerTask() async throws {
        let book = LessonBook(file: nil)
        book.learn(group: "r:review", task: "test", items: [("a", "always: Check the real result")])
        let model = FakeModel { _ in "DO: wait" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.lessons = book
        _ = try await agent.step()
        _ = try await agent.step()
        XCTAssertEqual(book.lessons.first?.uses, 1)
        XCTAssertNotNil(book.lessons.first?.lastRun)
        XCTAssertEqual(book.lessons.first?.lastTask, agent.task)
    }

    func testLocalCompletionShortcutIsNotCountedAsAModelReference() async throws {
        let book = LessonBook(file: nil)
        book.learn(group: "r:review", task: "test", items: [("a", "always: Check the real result")])
        let model = FakeModel { _ in "DO: done" }
        let agent = AgentLoop(phone: FakeGestures(), screen: FakeScreen(), actor: model, planner: model, trace: nil)
        agent.lessons = book
        agent.frameCompletion = { _ in "Destination found" }
        _ = try await agent.step()
        XCTAssertNil(book.lessons.first?.uses)
    }
}
