import SwiftUI
import UIKit

/// 0 · Welcome: the character wakes up and says hello; the disclaimer must be accepted to go on.
struct WelcomePage: View {
    @Binding var accepted: Bool
    @State private var awake = false

    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(mood: awake ? .idle : .sleeping, title: "Hi, I'm Lan Agent",
                       message: "Tell me a task and I'll do it on this iPhone: I see the screen through Screen Mirroring and tap with a USB mouse.")
            Panel {
                DisclosureGroup {
                    Text(Disclaimer.text).font(.footnote).foregroundStyle(.secondary).padding(.top, Space.s)
                } label: {
                    Label("Understand the risks", systemImage: "exclamationmark.shield").font(.body.weight(.semibold))
                }
                Divider().padding(.vertical, Space.m)
                Toggle("I understand and accept", isOn: $accepted)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            awake = true
        }
    }
}

enum Disclaimer {
    static var text: LocalizedStringKey {
        "Lan Agent is experimental software that controls this iPhone on its own. It can tap the wrong thing, send messages, change settings, buy things or delete data. Watch it while it runs and stop it if anything looks wrong. Screenshots of your screen are sent to the model endpoint you choose. You use it at your own risk; the authors accept no liability for any loss or damage."
    }
}

/// 1 · Connect the board: Bluetooth permission, scan, pair (automatically when only one board is found).
struct ConnectPage: View {
    @ObservedObject var board: BoardLink

    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(mood: board.connected ? .success : board.scanning ? .listening : .sleeping,
                       title: "Plug Me In",
                       message: "Connect the board to the USB-C port. I'll find it over Bluetooth; tap Pair when iOS asks.")
            if !board.connected { MiniPhoneDemo(kind: .plugIn) }
            Panel {
                switch board.state {
                case .unauthorized:
                    Label("Bluetooth is not allowed for Lan Agent.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.warning)
                    Button("Open Settings") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        .padding(.top, Space.s)
                case .poweredOff:
                    Label("Turn on Bluetooth in Control Center.", systemImage: "antenna.radiowaves.left.and.right.slash")
                default:
                    boards
                }
            }
        }
        .onAppear { board.scan(); autoPair() }
        .onChange(of: board.state) { _, s in if s == .poweredOn { board.scan() } }
        .onChange(of: board.found) { autoPair() }
    }

    /// Only one board nearby: pair it without asking.
    private func autoPair() {
        if board.found.count == 1, board.pairedID == nil, let f = board.found.first { board.pair(f.id) }
    }

    /// Not connected → Found → Pairing → Connected. A paired board reconnects by itself when it is plugged in.
    @ViewBuilder private var boards: some View {
        if board.connected {
            CheckRow(title: "Connected to \(board.name.isEmpty ? "the board" : board.name)", done: true)
        } else if board.connecting {
            CheckRow(title: "Connecting to the board…", done: false, active: true, waiting: true)
        } else if board.linking {
            CheckRow(title: "Pairing… tap Pair when iOS asks", done: false, active: true, waiting: true)
        } else if board.pairedID == nil, board.found.count == 1, let f = board.found.first {
            CheckRow(title: "Found \(f.name)", done: false, active: true, waiting: true)
        } else if !board.found.isEmpty {
            Text("Choose your board:").font(.subheadline).foregroundStyle(.secondary)
                .padding(.bottom, Space.s)
            ForEach(board.found) { f in
                Button { board.pair(f.id) } label: {
                    HStack {
                        Text(verbatim: f.name)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Space.s)
                }
            }
        } else {
            CheckRow(title: "Searching for the board over Bluetooth…", done: false, active: true, waiting: board.scanning)
        }
        if !board.connected || (board.signalStrength ?? 0) < -80 {
            Text((board.signalStrength ?? 0) < -80
                 ? "Weak signal? Try placing the board right against the side of your phone, or attach its antenna."
                 : "No antenna? Try placing the board right against the side of your phone.")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, Space.s)
        }
        if !board.connected {
            if !board.lastError.isEmpty {
                Text(verbatim: board.lastError).font(.footnote).foregroundStyle(Palette.warning)
            }
        }
    }
}

/// 2 · Let it see the screen: the phone and the board on one Wi-Fi (the board never opens a hotspot; send it the
/// phone's Wi-Fi if it has another one), then Screen Mirroring. The page's one action is the bottom button.
struct SeePage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var board: BoardLink
    @ObservedObject var feed: VideoFeed
    @Binding var onWiFi: Bool
    @Environment(\.scenePhase) private var scenePhase

    init(app: AppModel, board: BoardLink, onWiFi: Binding<Bool>) {
        self.app = app; self.board = board; self.feed = app.feed; self._onWiFi = onWiFi
    }

    private var streaming: Bool { feed.isNative ? feed.watchable : board.connected && board.status?.ap == "streaming" }
    // The board reports a connected station and this phone's video TCP: one Wi-Fi, no SSID access needed.
    private var joined: Bool {
        app.otherWiFi == nil && (onWiFi || app.join == .joined || app.hotspotSSID != nil || streaming || app.onSameWiFi)
    }
    private var failure: String? { if case .failed(let why) = app.join { return why } else { return nil } }

    var body: some View {
        VStack(spacing: Space.xl) {
            if CaptureSource.directAvailable {
                Picker("取屏来源", selection: Binding(get: { feed.source }, set: { app.selectCaptureSource($0) })) {
                    Text("直接取屏").tag(CaptureSource.direct)
                    Text("镜像回传").tag(CaptureSource.mirror)
                }
                .pickerStyle(.segmented)
                .disabled(!app.canChangeCaptureSource)
            }
            if feed.isNative {
                PageHeader(mood: streaming ? .success : .listening, title: "直接读取手机屏幕",
                           message: "通过系统整屏共享读取画面，继续使用现有无线控制。")
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Label(feed.captureReadinessText, systemImage: streaming ? "checkmark.circle.fill" : "rectangle.on.rectangle")
                        Text("请选择共享整个屏幕。切到其他 App 后保持共享和手机解锁。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if feed.sharingActive {
                            Button("停止屏幕共享", role: .destructive) { feed.stopNativeSharing() }
                        } else {
                            Button(feed.requestingSharing ? "等待系统确认…" : "开始共享整个屏幕") { feed.startNativeSharing() }
                                .disabled(feed.requestingSharing)
                            if feed.requestingSharing { Button("取消等待") { feed.stopNativeSharing() } }
                        }
                        LiveFrame(feed: feed, placeholder: false).frame(maxHeight: 240)
                            .accessibilityLabel("直接取屏预览")
                    }
                }
                Text("画面在手机本地处理，仅在原有模型决策时提交截图。此模式无需开启 AirPlay 镜像，也无需 USB 连接。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
            PageHeader(mood: streaming ? .success : (app.join.busy || joined) ? .listening : failure != nil ? .failure : .idle,
                       title: "Let Me See the Screen",
                       message: "Screen Mirroring reaches the board over the Wi-Fi you both use.")
            Panel {
                CheckRow(title: "Same Wi-Fi as the board", done: joined, active: !joined, waiting: app.join.busy && !joined,
                         detail: joined ? nil : app.join == .joining ? "Sending the Wi-Fi to the board…"
                            : app.join == .verifying ? "Waiting for the board on this Wi-Fi…" : failure.map { LocalizedStringKey($0) })
                Divider().padding(.vertical, Space.s)
                CheckRow(title: "Start Screen Mirroring", done: streaming, active: joined && !streaming)
            }
            if !joined {
                Panel {
                    VStack(alignment: .leading, spacing: Space.m) { SendWiFiForm(app: app, board: board) }
                        .textFieldStyle(.roundedBorder)
                }
                Label("The board never opens its own hotspot. Without a shared Wi-Fi it waits.", systemImage: "wifi")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("We're already on the same Wi-Fi") { onWiFi = true }.font(.footnote)
            } else if !streaming {
                Text("Now swipe down from the top-right corner and tap **Screen Mirroring → Lan Agent**.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                MiniPhoneDemo(kind: .controlCenter)
                VStack(spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Screen Mirroring…")
                    }
                    Label("Keep the screen unlocked: locking stops mirroring.", systemImage: "lock.open")
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: joined)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: app.join)
        .task(id: feed.source) {  // Direct capture does not depend on a board video/Wi-Fi session.
            guard !feed.isNative else { return }
            if !joined { app.startJoin(auto: true) }
            while !Task.isCancelled && !streaming {
                await app.refreshHotspot()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !feed.isNative { Task { await app.refreshHotspot() } } }
    }
}

/// The board joins the Wi-Fi this iPhone is on: its name (filled in when iOS tells the app) and password go over
/// the encrypted Bluetooth link; the app keeps neither. Rows only, so it fits a Form section or a Panel.
struct SendWiFiForm: View {
    @ObservedObject var app: AppModel
    @ObservedObject var board: BoardLink
    @State private var ssid = ""
    @State private var pass = ""

    private var name: String { ssid.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        TextField("Wi-Fi name (2.4 GHz)", text: $ssid)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .task { if ssid.isEmpty { ssid = await Hotspot.currentSSID() ?? board.net?.ssid ?? "" } }
        SecureField("Wi-Fi password", text: $pass)
        Button {
            app.sendWiFi(ssid: name, pass: pass)
            pass = ""
        } label: { Label("Send This Wi-Fi to the Board", systemImage: "wifi") }
            .font(.subheadline.weight(.semibold))
            .disabled(name.isEmpty || app.join.busy || !board.connected)
    }
}

/// 3 · Let it act: AssistiveTouch (shown as a demo), then calibration on the grid board (bottom button).
struct ActPage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var board: BoardLink
    @ObservedObject var calibrator: AutoCalibrator
    @ObservedObject var pointer: Pointer

    private var mouse: Bool { MockMode.on || board.status?.usb == "ok" }
    private var mirroring: Bool { MockMode.on || app.feed.watchable }

    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(mood: pointer.calibrated ? .success : calibrator.busy ? .acting : .idle,
                       title: "Let Me Use the Pointer",
                       message: "使用现有控制连接。打开 AssistiveTouch 后，在网格上校准指针。")
            if !pointer.calibrated { MiniPhoneDemo(kind: .assistiveTouch) }
            Panel {
                CheckRow(title: "Mouse connected", done: mouse, active: !mouse, waiting: board.connected && !mouse)
                Divider().padding(.vertical, Space.s)
                CheckRow(title: app.feed.isNative ? "整屏共享已就绪" : "Screen Mirroring on", done: mirroring, active: mouse && !mirroring)
                Divider().padding(.vertical, Space.s)
                CheckRow(title: "Pointer calibrated", done: pointer.calibrated, active: mouse && mirroring && !pointer.calibrated,
                         waiting: calibrator.busy,
                         detail: pointer.quality.map { "Accuracy \(CalibrationText.percent($0))" })
            }
            if !pointer.calibrated {
                Label("Recommended: calibrate before first use.", systemImage: "scope")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.accentColor)
                Text("Tip: in AssistiveTouch › Pointer Devices, set Tracking Speed to the middle and turn Pointer Animations off.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

/// 4 · Give it a brain: an OpenAI-compatible vision model; Test Connection; a first task to try.
struct BrainPage: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(spacing: Space.xl) {
            PageHeader(mood: app.modelOK == true ? .success : app.modelOK == false ? .failure : .thinking,
                       title: "Give Me a Brain",
                       message: "Any OpenAI-compatible vision model works. The key stays in this iPhone's Keychain.")
            if MockMode.on {
                Panel { Label("Demo data simulates the model.", systemImage: "theatermasks") }
            } else {
                ModelFieldsPanel(settings: settings)
            }
            ModelTestTimingView(app: app)
            switch app.modelOK {
            case true?:
                Panel {
                    Label("Connected. Try this first:", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.ok)
                    Text(verbatim: IntentStore.examples[0].prompt).font(.subheadline).foregroundStyle(.secondary)
                        .padding(.top, Space.s)
                }
            case false?:
                Label(app.modelError ?? String(localized: "Could not reach the model. Check the URL and key."), systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Palette.stop).font(.subheadline)
            case nil:
                EmptyView()
            }
        }
    }
}

/// Endpoint and key with placeholders only; the model is picked from the endpoint (nothing personal is built in), as a grouped box.
struct ModelFieldsPanel: View {
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(spacing: Space.xs) {
            Panel { ProviderFields(settings: settings) }
            if let url = settings.provider.keyURL {
                Link("Get an API key", destination: url)
                    .font(.footnote).tint(.secondary).underline()
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
}
