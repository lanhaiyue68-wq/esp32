import XCTest
@testable import IPhoneAgent

@MainActor final class ExperienceTests: XCTestCase {
    private let scene = Array(repeating: UInt8(12), count: 64)
    private let tap: JObject = ["action": .str("tap"), "x": .int(345), "y": .int(935)]

    func testUnconfirmedPrecisionResultSurvivesRelaunchAndIsRecalled() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let first = ExperienceStore(file: file)
        first.observeUnconfirmedTap(goal: "打开白板画一个笑脸", scene: scene, aspect: 0.46,
                                   action: tap.merging(["precise": .bool(true), "changed": .bool(false), "act_s": .num(1)]))
        let again = ExperienceStore(file: file)
        let recalled = again.recall(goal: "打开白板画一个笑脸", scene: scene, aspect: 0.46)
        XCTAssertEqual(recalled.count, 1)
        XCTAssertEqual(recalled.first?.verdict, .unconfirmed)
        XCTAssertEqual(recalled.first?.x, 345)
    }

    func testScreenChangeAndModelDoneAreNotLearnedAsSuccess() {
        let store = ExperienceStore(file: nil)
        for changed in [true, false] {
            store.observeUnconfirmedTap(goal: "open settings", scene: scene, aspect: 0.46,
                                       action: tap.merging(["changed": .bool(changed), "act_s": .num(1)]))
        }
        store.observeUnconfirmedTap(goal: "open settings", scene: scene, aspect: 0.46,
                                   action: ["action": .str("done"), "answer": .str("success")])
        XCTAssertEqual(store.count, 0)
    }

    func testPlannedButUnexecutedPrecisionRetryIsNotLearned() {
        let store = ExperienceStore(file: nil)
        store.observeUnconfirmedTap(goal: "open settings", scene: scene, aspect: 0.46,
                                   action: tap.merging(["precise": .bool(true), "changed": .bool(false)]))
        XCTAssertEqual(store.count, 0)
    }

    func testDifferentPageTaskAndOrientationDoNotRecallCoordinates() {
        let store = ExperienceStore(file: nil)
        store.review(id: "a", goal: "打开白板画一个笑脸", scene: scene, aspect: 0.46,
                     action: tap, verdict: true, correction: nil)
        XCTAssertTrue(store.recall(goal: "send an email", scene: scene, aspect: 0.46).isEmpty)
        XCTAssertTrue(store.recall(goal: "打开白板画一个笑脸", scene: Array(repeating: 2, count: 64), aspect: 0.46).isEmpty)
        XCTAssertTrue(store.recall(goal: "打开白板画一个笑脸", scene: scene, aspect: 2.1).isEmpty)
    }

    func testReviewCanCorrectAndRetractTheSameExperience() {
        let store = ExperienceStore(file: nil)
        store.review(id: "run:1", goal: "open settings", scene: scene, aspect: 0.46,
                     action: tap, verdict: false, correction: CGPoint(x: 400, y: 900))
        var items = store.recall(goal: "open settings", scene: scene, aspect: 0.46)
        XCTAssertEqual(items.first?.verdict, .userCorrected)
        XCTAssertEqual(items.first?.correctedX, 400)
        store.review(id: "run:1", goal: "open settings", scene: scene, aspect: 0.46,
                     action: tap, verdict: true, correction: nil)
        items = store.recall(goal: "open settings", scene: scene, aspect: 0.46)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.verdict, .userConfirmed)
        store.review(id: "run:1", goal: "open settings", scene: scene, aspect: 0.46,
                     action: tap, verdict: nil, correction: nil)
        XCTAssertEqual(store.count, 0)
    }

    func testNoTypedContentOrRawTaskIsSaved() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExperienceStore(file: file)
        store.review(id: "typing", goal: "private task", scene: scene, aspect: 0.46,
                     action: ["action": .str("type"), "text": .str("private text")], verdict: true, correction: nil)
        XCTAssertEqual(store.count, 0)
        store.review(id: "tap", goal: "private task", scene: scene, aspect: 0.46,
                     action: tap, verdict: true, correction: nil)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("private task"))
        XCTAssertFalse(text.contains("private text"))
    }

    func testRepeatedObservationUpdatesOneCaseAndClearPersists() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = ExperienceStore(file: file)
        let action = tap.merging(["precise": .bool(true), "changed": .bool(false), "act_s": .num(1)])
        for _ in 0..<5 { store.observeUnconfirmedTap(goal: "open settings", scene: scene, aspect: 0.46, action: action) }
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.recall(goal: "open settings", scene: scene, aspect: 0.46).first?.observations, 5)
        store.clear()
        XCTAssertEqual(ExperienceStore(file: file).count, 0)
    }
}
