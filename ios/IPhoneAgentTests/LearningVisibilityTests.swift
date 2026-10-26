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
}
