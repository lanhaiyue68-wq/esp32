import Foundation

/// Debug traces: one folder per agent run (Documents/traces/<date>) with every model call, the screenshot it
/// saw, step timings and a metrics.json snapshot. Port of debug.py; Documents is shared with Finder/devicectl.
@MainActor final class TraceStore {
    let root: URL
    private(set) var dir: URL?
    private var n = 0
    private var recording = false
    private var lastVideo = -Double.infinity
    private var videoFiles: [(URL, Int)] = []
    private var imageFiles: [(URL, Int)] = []
    private var lastCleanup = Date.distantPast
    var diagnostics: DiagnosticFiles {
        DiagnosticFiles(documents: root.deletingLastPathComponent(), temporary: FileManager.default.temporaryDirectory, traceRoot: root)
    }

    init(root: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("traces")) {
        self.root = root
        do { _ = try diagnostics.maintain() } catch { DebugLog.write("diagnostic cleanup: \(error.localizedDescription)") }
    }

    func start(task: String) {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        let name = f.string(from: Date())
        var d = root.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: d.path) { d = root.appendingPathComponent(name + "-" + String(UUID().uuidString.prefix(8))) }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        dir = d
        n = 0
        recording = true
        videoFiles = []; imageFiles = []
        cleanup()
        write(kind: "task", ["task": .str(task)])
    }

    func write(_ frame: Data? = nil, kind: String, _ record: JObject) {
        guard let dir else { return }
        n += 1
        var line = JObject([("n", .int(n)), ("t", .num(now())), ("kind", .str(kind))]).merging(record)
        if let frame, frame.count <= diagnostics.policy.imageBytes {
            let name = String(format: "%03d.jpg", n)
            line["frame"] = .str(name)
            let file = dir.appendingPathComponent(name)
            try? frame.write(to: file)
            imageFiles.append((file, frame.count))
            trim(&imageFiles, bytes: diagnostics.policy.imageBytes)
        }
        append(PyJSON.dumps(line, ascii: false) + "\n", to: dir.appendingPathComponent("steps.jsonl"))
        if Date().timeIntervalSince(lastCleanup) >= 60 { cleanup() }
    }

    func writeMetrics(_ metrics: [String: Any]) {
        guard let dir, JSONSerialization.isValidJSONObject(metrics),
              let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: dir.appendingPathComponent("metrics.json"))
    }

    /// Video is a ring of recent frames; it cannot grow for the entire lifetime of a run.
    func writeVideo(_ jpeg: Data) {
        let policy = diagnostics.policy
        guard recording, let dir, jpeg.count <= policy.videoBytes, now() - lastVideo >= policy.videoInterval else { return }
        lastVideo = now()
        let video = dir.appendingPathComponent("video")
        try? FileManager.default.createDirectory(at: video, withIntermediateDirectories: true)
        let file = video.appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
        if let i = videoFiles.firstIndex(where: { $0.0 == file }) { videoFiles.remove(at: i) }
        do { try jpeg.write(to: file); videoFiles.append((file, jpeg.count)) } catch { return }
        trim(&videoFiles, bytes: policy.videoBytes, count: policy.videoFrames)
        if Date().timeIntervalSince(lastCleanup) >= 60 { cleanup() }
    }

    private func trim(_ files: inout [(URL, Int)], bytes: Int, count: Int = Int.max) {
        var size = files.reduce(0) { $0 + $1.1 }
        while (size > bytes || files.count > count), !files.isEmpty {
            let old = files.removeFirst(); size -= old.1
            try? FileManager.default.removeItem(at: old.0)
        }
    }

    func finish() { recording = false; cleanup() }
    private func cleanup() {
        lastCleanup = Date()
        do { _ = try diagnostics.maintain(active: recording ? dir : nil) }
        catch { DebugLog.write("diagnostic cleanup: \(error.localizedDescription)") }
    }

    func runs() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.filter(\.hasDirectoryPath).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// All traces zipped (via a coordinated read "for uploading"), for the share sheet.
    nonisolated static func zip(_ folder: URL, name: String = "traces.zip") throws -> URL {
        var result: URL?, failure: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordError) { tmp in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: out)
            do { try FileManager.default.copyItem(at: tmp, to: out); result = out } catch { failure = error }
        }
        if let e = coordError ?? failure { throw e }
        guard let result else { throw DeviceError(message: "zip failed") }
        return result
    }

    private func append(_ text: String, to url: URL) {
        let limit = 2 * 1024 * 1024
        let data = Data(text.utf8)
        guard data.count <= limit else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: url)
        }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit,
              let all = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = all.split(separator: "\n").map(String.init)
        guard let task = lines.first else { return }
        var kept: [String] = [], bytes = task.utf8.count + 1
        for line in lines.dropFirst().reversed() {
            guard bytes + line.utf8.count + 1 <= limit else { break }
            kept.append(line); bytes += line.utf8.count + 1
        }
        try? Data(([task] + Array(kept.reversed())).joined(separator: "\n").appending("\n").utf8).write(to: url, options: .atomic)
    }
}
