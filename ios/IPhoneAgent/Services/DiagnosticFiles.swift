import Foundation

/// Only app-owned diagnostic files; preferences, calibration and task data are outside this scope.
struct DiagnosticFiles {
    struct Policy {
        var maxRuns = 20
        var maxAge: TimeInterval = 7 * 86400
        var maxBytes = 80 * 1024 * 1024
        var videoBytes = 8 * 1024 * 1024
        var videoFrames = 120
        var videoInterval = 1.0  // s between stored frames: every frame wrote 4.3 GB in 9 hours (iOS's report of 11-09)
        var imageBytes = 12 * 1024 * 1024
        var exportBytes = 20 * 1024 * 1024
        var reportBytes = 5 * 1024 * 1024
        var reportCount = 10
    }
    struct Usage { var bytes = 0; var runs = 0 }
    let documents: URL
    let temporary: URL
    var policy = Policy()
    let root: URL
    init(documents: URL, temporary: URL, policy: Policy = Policy(), traceRoot: URL? = nil) {
        self.documents = documents; self.temporary = temporary; self.policy = policy
        self.root = traceRoot ?? documents.appendingPathComponent("traces")
    }
    private let fm = FileManager.default
    private let cacheNames = ["esp32-agent-logs.zip", "traces.zip", "iPhone-Agent-runs.zip", "diagnostic-export", "iPhone-Agent-runs"]
    private func children(_ folder: URL) -> [URL] {
        guard !isLink(folder) else { return [] }
        return ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .fileSizeKey])) ?? [])
            .filter { !isLink($0) }
    }
    private func isLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    private func bytes(_ url: URL) -> Int {
        guard !isLink(url) else { return 0 }
        if isDirectory(url) { return children(url).reduce(0) { $0 + bytes($1) } }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
    private func runFolders() -> [URL] {
        children(root).filter {
            isDirectory($0) && $0.lastPathComponent.range(of: #"^\d{8}-\d{6}(?:-[A-Za-z0-9-]+)?$"#, options: .regularExpression) != nil
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    private func reports() -> [URL] {
        children(documents.appendingPathComponent("diagnostics")).filter { !isDirectory($0) && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func maintainReports(now: Date = Date()) throws {
        let files = reports()
        var count = files.count, size = files.reduce(0) { $0 + bytes($1) }
        for file in files.reversed() {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            if count > policy.reportCount || size > policy.reportBytes || now.timeIntervalSince(date) > policy.maxAge {
                let n = bytes(file); try fm.removeItem(at: file); size -= n; count -= 1
            }
        }
    }
    func usage() -> Usage {
        let runs = runFolders()
        let extras = ["debug.log", "debug.1.log"].map { documents.appendingPathComponent($0) }
            + cacheNames.map { temporary.appendingPathComponent($0) }
        return Usage(bytes: (runs + extras + reports()).reduce(0) { $0 + bytes($1) }, runs: runs.count)
    }
    private func trimImages(_ folder: URL, byteLimit: Int, countLimit: Int = Int.max) throws {
        var images = children(folder).filter { !isDirectory($0) && $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var size = images.reduce(0) { $0 + bytes($1) }
        while (size > byteLimit || images.count > countLimit), !images.isEmpty {
            let old = images.removeFirst(), n = bytes(old)
            try fm.removeItem(at: old); size -= n
        }
    }
    /// Run at launch, between runs and periodically while recording. The active folder is never deleted.
    @discardableResult func maintain(active: URL? = nil, now: Date = Date()) throws -> Usage {
        let folders = runFolders()
        for folder in folders {
            try trimImages(folder.appendingPathComponent("video"), byteLimit: policy.videoBytes, countLimit: policy.videoFrames)
            try trimImages(folder, byteLimit: policy.imageBytes)
        }
        var remaining = folders.count, size = folders.reduce(0) { $0 + bytes($1) }
        // 133 over the cloud 11-14: runs of 20 to 50 things left ~20 MB of pictures each, so only the last three stayed
        // and the steps of the afternoon's failures were gone by evening. Over the size limit, older runs (all but the
        // newest two) lose their pictures first and keep steps.jsonl (a few MB); whole folders go only after that.
        for folder in folders.dropFirst(2).reversed()
        where size > policy.maxBytes && folder.standardizedFileURL != active?.standardizedFileURL {
            let before = bytes(folder)
            try trimImages(folder.appendingPathComponent("video"), byteLimit: 0)
            try trimImages(folder, byteLimit: 0)
            size -= before - bytes(folder)
        }
        for folder in folders.reversed() {
            guard folder.standardizedFileURL != active?.standardizedFileURL else { continue }
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
            // Folder names retain the run's start time even if an old review later updates its mtime.
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd-HHmmss"
            let date = formatter.date(from: String(folder.lastPathComponent.prefix(15))) ?? modified
            if remaining > policy.maxRuns || size > policy.maxBytes || now.timeIntervalSince(date) > policy.maxAge {
                let n = bytes(folder); try fm.removeItem(at: folder); remaining -= 1; size -= n
            }
        }
        for name in cacheNames {
            let url = temporary.appendingPathComponent(name)
            guard !isLink(url), let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  now.timeIntervalSince(date) > 86400 else { continue }
            try fm.removeItem(at: url)
        }
        try maintainReports(now: now)
        return usage()
    }
    /// Text-log deletion is serialized separately by DebugLog.clear(). Unknown files are never removed.
    func clear(active: URL? = nil) throws {
        for report in reports() { try fm.removeItem(at: report) }
        for folder in runFolders() where folder.standardizedFileURL != active?.standardizedFileURL { try fm.removeItem(at: folder) }
        for name in cacheNames {
            let url = temporary.appendingPathComponent(name)
            if !isLink(url), fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        }
    }
    /// A bounded diagnostic snapshot, not a copy of Documents. Recording frames are omitted by default.
    func exportStage() throws -> URL {
        let stage = temporary.appendingPathComponent("diagnostic-export")
        guard !isLink(stage) else { throw DeviceError(message: "Invalid diagnostics folder") }
        if fm.fileExists(atPath: stage.path) { try fm.removeItem(at: stage) }
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        var remaining = max(0, policy.exportBytes - min(512, policy.exportBytes)), copied = 0, omitted = 0
        func copy(_ source: URL, to target: URL) throws {
            guard !isLink(source), !isDirectory(source), fm.fileExists(atPath: source.path) else { return }
            let n = bytes(source)
            guard n <= remaining else { omitted += 1; return }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target); remaining -= n; copied += 1
        }
        for name in ["debug.log", "debug.1.log"] { try copy(documents.appendingPathComponent(name), to: stage.appendingPathComponent(name)) }
        for report in reports().prefix(policy.reportCount) { try copy(report, to: stage.appendingPathComponent("diagnostics").appendingPathComponent(report.lastPathComponent)) }
        let folders = Array(runFolders().prefix(policy.maxRuns))
        for folder in folders {
            let destination = stage.appendingPathComponent("traces").appendingPathComponent(folder.lastPathComponent)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for name in ["steps.jsonl", "metrics.json", "review.json"] { try copy(folder.appendingPathComponent(name), to: destination.appendingPathComponent(name)) }
        }
        for folder in folders {
            let images = children(folder).filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            for image in images { try copy(image, to: stage.appendingPathComponent("traces").appendingPathComponent(folder.lastPathComponent).appendingPathComponent(image.lastPathComponent)) }
        }
        let manifest: [String: Any] = ["format": 1, "recentRunLimit": policy.maxRuns, "includedRuns": folders.count, "payloadLimitBytes": policy.exportBytes,
            "copiedFiles": copied, "omittedFiles": omitted, "videoIncluded": false, "note": "Bounded retained run history; text records precede images. Video and files exceeding the payload budget are omitted."]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        if data.count <= policy.exportBytes { try data.write(to: stage.appendingPathComponent("manifest.json")) }
        return stage
    }
}
