import XCTest
@testable import IPhoneAgent

final class DiagnosticFilesTests: XCTestCase {
    private var sandbox: URL!
    private var storage: DiagnosticFiles!
    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        storage = DiagnosticFiles(documents: sandbox.appendingPathComponent("Documents"), temporary: sandbox.appendingPathComponent("tmp"))
        try FileManager.default.createDirectory(at: storage.temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: sandbox) }
    @discardableResult private func put(_ path: String, bytes: Int = 10, date: Date = Date()) throws -> URL {
        let url = sandbox.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 65, count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        return url
    }
    private func run(_ name: String, bytes: Int = 10, date: Date = Date()) throws -> URL {
        let file = try put("Documents/traces/\(name)/steps.jsonl", bytes: bytes, date: date)
        let folder = file.deletingLastPathComponent()
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder.path)
        return folder
    }
    /// A run's folder name is its start time and the age limit reads it: names fixed in October expired in November.
    private func recent(_ hoursAgo: Int) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date().addingTimeInterval(-Double(hoursAgo) * 3600))
    }
    func testOldestCompletedRunsAreRemovedAtCountLimit() throws {
        storage.policy.maxRuns = 2
        let old = try run(recent(3)); _ = try run(recent(2)); _ = try run(recent(1))
        let usage = try storage.maintain()
        XCTAssertEqual(usage.runs, 2); XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }
    func testByteBudgetRemovesOldestUntilItFits() throws {
        storage.policy.maxBytes = 25
        _ = try run(recent(2), bytes: 20); _ = try run(recent(1), bytes: 20)
        XCTAssertLessThanOrEqual(try storage.maintain().bytes, 25)
        XCTAssertEqual(storage.usage().runs, 1)
    }
    func testAgeLimitPreservesAnActiveRun() throws {
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let old = try run("20261020-000000", date: date), active = try run("20261021-000000", date: date)
        _ = try storage.maintain(active: active, now: date.addingTimeInterval(8 * 86400))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
    }
    func testVideoRingIsBoundedAndKeepsNewest() throws {
        storage.policy.videoFrames = 2; storage.policy.videoBytes = 2; storage.policy.videoInterval = 05
        let active = try run("20261021-000000")
        for n in 1...4 { _ = try put("Documents/traces/20261021-000000/video/00\(n).jpg", bytes: 10) }
        _ = try storage.maintain(active: active)
        let files = try FileManager.default.contentsOfDirectory(atPath: active.appendingPathComponent("video").path)
        XCTAssertEqual(files.sorted(), ["003.jpg", "004.jpg"])
    }
    func testScreenshotBudgetPreservesRecentEvidence() throws {
        storage.policy.imageBytes = 25
        let active = try run("20261021-000000")
        for n in 1...4 { _ = try put("Documents/traces/20261021-000000/00\(n).jpg", bytes: 10) }
        _ = try storage.maintain(active: active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: active.appendingPathComponent("001.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.appendingPathComponent("004.jpg").path))
    }
    func testClearPreservesPreferencesKnowledgeAndActiveRun() throws {
        let old = try run("20261020-000000"), active = try run("20261021-000000")
        let learned = try put("Documents/knowledge/notes.txt"), calibration = try put("Library/calibration.json")
        let cache = try put("tmp/esp32-agent-logs.zip"), unrelated = try put("tmp/unrelated.txt")
        try storage.clear(active: active)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        for u in [active, learned, calibration, unrelated] { XCTAssertTrue(FileManager.default.fileExists(atPath: u.path)) }
    }
    func testCleanupNeverFollowsASymlinkOutsideDiagnostics() throws {
        let outside = try put("outside/keep.txt")
        try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: storage.root.appendingPathComponent("20261020-000000"), withDestinationURL: outside.deletingLastPathComponent())
        storage.policy.maxRuns = 0
        _ = try storage.maintain(); try storage.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    func testDefaultExportRetainsTaskEvidenceAfterFiveInternalRunsAndNoVideo() throws {
        for n in 1...7 { _ = try run("2026102\(n)-000000"); _ = try put("Documents/traces/2026102\(n)-000000/video/1.jpg") }
        _ = try put("Documents/debug.log"); _ = try put("Documents/private.txt")
        let stage = try storage.exportStage()
        let folders = try FileManager.default.contentsOfDirectory(atPath: stage.appendingPathComponent("traces").path)
        XCTAssertEqual(folders.count, 7); XCTAssertTrue(folders.contains("20261021-000000"),
            "an owner's failed task must survive subsequent navigation/report runs")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.appendingPathComponent("private.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.appendingPathComponent("traces/20261027-000000/video").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.appendingPathComponent("manifest.json").path))
    }
    func testExportHasPayloadBudgetAndLeavesOriginalEvidenceAlone() throws {
        storage.policy.exportBytes = 1024
        let source = try put("Documents/traces/20261021-000000/001.jpg", bytes: 2000)
        _ = try run("20261021-000000")
        let stage = try storage.exportStage()
        let items = FileManager.default.enumerator(at: stage, includingPropertiesForKeys: [.fileSizeKey])?.compactMap { $0 as? URL } ?? []
        let size = items.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        XCTAssertLessThanOrEqual(size, 1024); XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    @MainActor func testRapidRestartsDoNotAppendToTheSameRun() throws {
        let trace = TraceStore(root: storage.root)
        trace.start(task: "first"); let first = try XCTUnwrap(trace.dir)
        trace.start(task: "second"); let second = try XCTUnwrap(trace.dir)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue((try String(contentsOf: first.appendingPathComponent("steps.jsonl"), encoding: .utf8)).contains("first"))
        XCTAssertFalse((try String(contentsOf: second.appendingPathComponent("steps.jsonl"), encoding: .utf8)).contains("first"))
    }
    @MainActor func testPerRunTextLogIsBoundedAndKeepsTaskAndLatestEvent() throws {
        let trace = TraceStore(root: storage.root)
        trace.start(task: "keep task")
        for n in 0..<30 { trace.write(kind: "test", ["payload": .str(String(repeating: "x", count: 100_000)), "index": .int(n)]) }
        let file = try XCTUnwrap(trace.dir).appendingPathComponent("steps.jsonl")
        let data = try Data(contentsOf: file), text = String(decoding: data, as: UTF8.self)
        XCTAssertLessThanOrEqual(data.count, 2 * 1024 * 1024)
        XCTAssertTrue(text.contains("keep task")); XCTAssertTrue(text.contains("29"))
        for line in text.split(separator: "\n") { XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8))) }
    }
    func testSystemDiagnosticReportsAlsoHaveABudgetAndAreCleared() throws {
        storage.policy.reportCount = 2; storage.policy.reportBytes = 25
        for n in 1...4 { _ = try put("Documents/diagnostics/100-\(n).json", bytes: 10) }
        try storage.maintainReports()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.appendingPathComponent("Documents/diagnostics").path).sorted(), ["100-3.json", "100-4.json"])
        try storage.clear()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.appendingPathComponent("Documents/diagnostics").path).count, 0)
    }
    func testAnExplicitCustomTraceRootDoesNotTouchItsSibling() throws {
        let sibling = try run("20261020-000000")
        let custom = sandbox.appendingPathComponent("Documents/custom-traces")
        let isolated = DiagnosticFiles(documents: storage.documents, temporary: storage.temporary, traceRoot: custom)
        try isolated.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }
    func testExpiredExportCacheIsClearedAutomatically() throws {
        let now = Date(), file = try put("tmp/esp32-agent-logs.zip", date: Date().addingTimeInterval(-2 * 86400))
        _ = try storage.maintain(now: now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
