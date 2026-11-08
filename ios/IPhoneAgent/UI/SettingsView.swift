import SwiftUI
import UIKit

/// Settings: Model, Board, Calibration, Language, Diagnostics, About. Logs and raw metrics live one level down.
struct SettingsView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject var board: BoardLink
    @AppStorage(MockMode.key) private var demoData = false
    @AppStorage(DebugLog.computerKey) private var toComputer = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ModelSettingsView(app: app, settings: settings) } label: {
                        row("Model", "brain", .pink, value: app.modelReady ? (MockMode.on ? "Demo" : settings.currentModel ?? String(localized: "Auto")) : nil)
                    }
                    NavigationLink { BoardSettingsView(app: app, board: board) } label: {
                        row("Board", "cable.connector", .blue,
                            value: board.connected ? board.name : String(localized: "Not connected"))
                    }
                    CalibrationRow(app: app, calibrator: app.calibrator, pointer: app.pointer)
                    Button { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) } label: {
                        HStack {
                            SettingsLabel(title: "Language", symbol: "globe", color: .indigo)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                } footer: {
                    Text("Lan Agent follows your iPhone's language. To change it just for this app, open Settings › Lan Agent › Language.")
                }
                Section {
                    Button { UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!) } label: {
                        HStack {
                            SettingsLabel(title: "Notifications", symbol: "bell.badge.fill", color: .red)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                } header: {
                    Text("Runs")
                } footer: {
                    Text("Run diagnostics are cleaned automatically. Manage saved logs, recent video frames and export files in Logs and Cache.")
                }
                Section {
                    NavigationLink { PhaseATestView(app: app, bridge: app.keyboardBridge) } label: {
                        SettingsLabel(title: "新架構測試（階段 A）", symbol: "keyboard", color: .indigo)
                    }
                } footer: {
                    Text("Lan Agent 輸入法、ChatGPT Plus 登入的可行性測試")
                }
                Section {
                    NavigationLink { DiagnosticsView(app: app, metrics: app.metrics, board: board, feed: app.feed) } label: {
                        SettingsLabel(title: "Diagnostics", symbol: "waveform.path.ecg", color: .green)
                    }
                    Toggle(isOn: $demoData) { SettingsLabel(title: "Demo data", symbol: "theatermasks", color: .purple) }
                    Button { settings.onboarded = false; app.setupPage = .welcome } label: {
                        SettingsLabel(title: "Run setup again", symbol: "arrow.counterclockwise", color: .gray)
                    }
                    .tint(.primary)
                } footer: {
                    Text("Demo data fakes a board, a finished run and the whole setup, to try the app without hardware. Takes effect after you quit and reopen the app.")
                }
                Section {
                    NavigationLink { LearningView(app: app) } label: {
                        SettingsLabel(title: "Learning", symbol: "brain.head.profile", color: .purple)
                    }
                    NavigationLink { PrivacySettingsView(app: app, runs: app.runs) } label: {
                        SettingsLabel(title: "Privacy", symbol: "hand.raised.fill", color: .blue)
                    }
                    NavigationLink { LogsView(app: app) } label: {
                        SettingsLabel(title: "Logs and Cache", symbol: "externaldrive", color: .orange)
                    }
                    // Apart from Demo data: next to it, it was switched on by mistake (logs(30) were all a demo run).
                    Toggle(isOn: $toComputer) { SettingsLabel(title: "Send logs to the computer", symbol: "cable.connector", color: .teal) }
                    NavigationLink { AboutView(app: app) } label: {
                        SettingsLabel(title: "About", symbol: "info", color: .gray)
                    }
                } footer: {
                    Text("Send logs to the computer passes this app's debug lines through the board to the computer on its cable, which may then start or stop a run; leave it off unless you are testing.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ color: Color, value: String?) -> some View {
        HStack {
            SettingsLabel(title: title, symbol: symbol, color: color)
            Spacer()
            Text(verbatim: value ?? String(localized: "Not set up")).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Settings › Model: base URL and key (placeholders only), Test Connection, and an Advanced disclosure with
/// the model override (empty = first model from GET {base}/models), per-role models and request tweaks.
struct BoardSettingsView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var board: BoardLink

    var body: some View {
        List {
            Section {
                HStack(spacing: Space.l) {
                    AgentFace(mood: board.connected ? .idle : .sleeping).frame(width: 52, height: 58)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: board.name.isEmpty ? "Lan Agent" : board.name).font(.headline)
                        Text(board.connected ? "Connected" : board.pairedID != nil ? "Connecting…" : "Not paired")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Space.xs)
                if board.connected, let s = board.status {
                    ValueRow(title: "Mouse", value: s.usb ?? "–")
                    ValueRow(title: "Mirroring", value: s.ap ?? "–")
                }
            }
            if board.pairedID == nil || !board.connected {
                Section {
                    ForEach(board.found.filter { $0.id != board.pairedID }) { f in
                        Button { Haptics.tick(); board.pair(f.id) } label: {
                            LabeledContent { Text(verbatim: "\(f.rssi) dBm") } label: { Text(verbatim: f.name) }
                        }
                        .tint(.primary)
                    }
                    Button { board.scan() } label: {
                        HStack {
                            Text(board.scanning ? "Scanning…" : "Scan for Boards")
                            if board.scanning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(board.scanning)
                } header: {
                    Text("Nearby")
                }
            }
            Section {
                ValueRow(title: "Board Wi-Fi", value: board.net?.ssid.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Not set"))
                ValueRow(title: "Status", value: app.join == .joining ? String(localized: "Sending…")
                         : app.sameWiFiProblem ?? String(localized: "Same Wi-Fi as this iPhone"))
                SendWiFiForm(app: app, board: board)
            } header: {
                Text("Wi-Fi")
            } footer: {
                Text("The board never opens its own hotspot. It joins the Wi-Fi sent here and waits while that Wi-Fi is out of range. Keep this iPhone on the same Wi-Fi for Screen Mirroring.")
            }
            if board.pairedID != nil {
                Section {
                    Button("Unpair Board", role: .destructive) { Task { await board.unpair() } }
                    Button("Forget in This App", role: .destructive) { board.forget() }
                } footer: {
                    Text("Unpair erases the bonds on the board. iOS keeps its own: also tap (i) next to \"Lan Agent\" in Settings › Bluetooth and choose Forget This Device.")
                }
            }
        }
        .navigationTitle("Board")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.refreshHotspot() }
    }
}

/// Settings › Calibration: one tap calibrates on the grid board; accuracy and span in a small second line.
struct CalibrationRow: View {
    @ObservedObject var app: AppModel
    @ObservedObject var calibrator: AutoCalibrator
    @ObservedObject var pointer: Pointer

    private var ready: Bool { MockMode.on || calibrator.boardReady }

    var body: some View {
        Button { calibrator.calibrate() } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calibration")
                        if let span = pointer.span {
                            Text(verbatim: "\(pointer.quality.map(CalibrationText.percent) ?? "–") · \(span.w) × \(span.h)")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } icon: { SettingsIcon(symbol: "scope", color: .orange) }
                Spacer()
                if ready {
                    Text("Calibrate").foregroundStyle(Color.accentColor)
                } else {
                    Text("Connect the board").foregroundStyle(.secondary)
                }
            }
        }
        .tint(.primary)
        .disabled(!ready || calibrator.busy)
        // user 11-08: the hand proven with numbers — 20 spots tapped like a task, each real touch measured
        Button { calibrator.testAccuracy() } label: {
            Label { Text("準度測試（點 20 個位置）") } icon: { SettingsIcon(symbol: "target", color: .green) }
        }
        .tint(.primary)
        .disabled(!ready || calibrator.busy || !pointer.calibrated)
    }
}
