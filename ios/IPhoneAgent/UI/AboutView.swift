import SwiftUI

/// Settings › About: version, acknowledgements, disclaimer and the text logs.
struct AboutView: View {
    @ObservedObject var app: AppModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "1.0") (\(info?["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: Space.m) {
                    Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text(verbatim: "Lan Agent").font(.title2.bold())
                    Text("Version \(version)").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s)
                .listRowBackground(Color.clear)
            }
            Section {
                NavigationLink { AcknowledgementsView() } label: {
                    SettingsLabel(title: "Acknowledgements", symbol: "heart.fill", color: .pink)
                }
                NavigationLink { DisclaimerView() } label: {
                    SettingsLabel(title: "Disclaimer", symbol: "exclamationmark.shield.fill", color: .orange)
                }
            } footer: {
                Text("No data leaves this iPhone except the requests to the model endpoint you set up and, when you switch them on, to ChatTool and the knowledge base on your computer.")
            }
            Section {
                NavigationLink { LogsView(app: app) } label: {
                    SettingsLabel(title: "Logs", symbol: "text.alignleft", color: .gray)
                }
            } footer: {
                Text("When something goes wrong, export all logs here and send the zip to your support contact: it holds the debug log, the runs and any crash reports iOS gave the app.")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcknowledgementsView: View {
    private let items: [(name: String, license: String, note: LocalizedStringKey)] = [
        ("UxPlay", "GPL-3.0", "The board's AirPlay receiver is ported from UxPlay."),
        ("Arduino-ESP32 / ESP-IDF", "LGPL-2.1 / Apache-2.0", "Espressif's frameworks for the board firmware."),
        ("NimBLE", "Apache-2.0", "The board's Bluetooth LE stack."),
        ("TinyUSB", "MIT", "The board's USB mouse and keyboard."),
    ]

    var body: some View {
        List {
            ForEach(items, id: \.name) { item in
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text(verbatim: item.name).font(.headline)
                        Spacer()
                        Text(verbatim: item.license).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(item.note).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, Space.xs)
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                PokeableFace(mood: .idle).frame(width: 64, height: 72)
                Text(Disclaimer.text).font(.body)
            }
            .padding(Space.xl)
        }
        .navigationTitle("Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The app's text log, newest first; copyable.
struct LogsView: View {
    @ObservedObject var app: AppModel
    @State private var shareURL: URL?
    @State private var exporting = false
    @State private var clearing = false
    @State private var confirmClear = false
    @State private var diskBytes = 0
    @State private var diskRuns = 0
    @State private var cleanupMessage: String?
    private var idle: Bool { !app.agent.running && !app.startingAgent && !app.watching && !app.recorder.recording }
    private var storage: DiagnosticFiles { app.traces.diagnostics }
    private func refreshUsage() {
        let usage = storage.usage(); diskBytes = usage.bytes; diskRuns = usage.runs
    }

    var body: some View {
        List {
            Section {
                Button { exportAll() } label: {
                    HStack {
                        Label("Export recent logs", systemImage: "archivebox")
                        Spacer()
                        if exporting { ProgressView() }
                    }
                }
                .disabled(exporting || clearing || !idle)
                if FileManager.default.fileExists(atPath: DebugLog.url.path) {
                    ShareLink(item: DebugLog.url) { Label("Share debug log", systemImage: "doc.text.magnifyingglass") }
                }
            } footer: {
                Text("Exports the latest 5 runs and text logs, up to 20 MB before compression. Video is omitted. Stop watching or running a task before exporting.")
            }
            Section {
                LabeledContent("Diagnostic storage", value: ByteCountFormatter.string(fromByteCount: Int64(diskBytes), countStyle: .file))
                LabeledContent("Saved runs", value: String(diskRuns))
                Button("Clear logs and diagnostic cache", role: .destructive) { confirmClear = true }
                    .disabled(!idle || exporting || clearing)
                if let cleanupMessage { Text(verbatim: cleanupMessage).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Automatic cleanup")
            } footer: {
                Text("Keeps up to 20 runs for 7 days within 80 MB. Each run keeps at most 8 MB / 120 recent video frames and 12 MB of step images. Old export files expire after 1 day. Clearing keeps model settings, board pairing, calibration, knowledge and learned cases. Stop watching or running a task to clear.")
            }
            if app.log.isEmpty {
                Text("Nothing logged yet.").foregroundStyle(.secondary)
            }
            ForEach(app.log.reversed()) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.time, format: .dateTime.hour().minute().second()).font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: line.text).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .listStyle(.plain)
        .sheet(item: $shareURL) { ShareSheet(items: [$0]) }
        .navigationTitle("Logs and Cache")
        .onAppear { refreshUsage() }
        .confirmationDialog("Clear logs and diagnostic cache?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { clearDiagnostics() }
        } message: {
            Text("Deletes saved diagnostic runs, screenshots, video frames and old export files. Your setup and knowledge are kept.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: app.log.map { "\($0.time.formatted(.iso8601)) \($0.text)" }.joined(separator: "\n"))
            }
        }
    }

    private func clearDiagnostics() {
        guard idle, !exporting, !clearing else { return }
        clearing = true; shareURL = nil
        defer { clearing = false; refreshUsage() }
        do {
            try storage.clear()
            try DebugLog.clear()
            app.clearLog()
            app.runs.reload()
            cleanupMessage = String(localized: "Logs and diagnostic cache cleared.")
        } catch { cleanupMessage = error.localizedDescription }
    }

    /// Snapshot selected diagnostics; arbitrary Documents files and lifetime video are never copied.
    private func exportAll() {
        guard idle, !exporting, !clearing else { return }
        exporting = true; shareURL = nil
        let files = storage
        _ = DebugLog.tail(0) // flush before taking the snapshot
        Task {
            let result = await Task.detached {
                Result {
                    _ = try files.maintain()
                    let stage = try files.exportStage()
                    defer { try? FileManager.default.removeItem(at: stage) }
                    return try TraceStore.zip(stage, name: "esp32-agent-logs.zip")
                }
            }.value
            exporting = false; refreshUsage()
            switch result {
            case .success(let url): shareURL = url
            case .failure(let e): app.say("export: \(e.localizedDescription)")
            }
        }
    }
}
