import SwiftUI

/// 小藍 iPad 版's own screens (162; user 11-25: "你這個完全就是大藍"). Laid out like Android 小藍 (Echo · 小藍,
/// worktool-lan-watch LanWatchActivity): three tabs, 守候 / 工具箱 / 設定, with both engines' watch — personal WeChat
/// (智微兔's orders and the reply watch) and WeCom (智企微行's orders). The board, screen and calibration controls are
/// Pilot's own (StatusChips, CalibrateButton, SettingsView), shown here. Only the XiaoLan target shows these (RootView).
struct XiaoLanRoot: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: Settings
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            XiaoLanWatchTab(app: app, board: app.board, chat: app.chatTool, wework: app.weworkTool)
                .tabItem { Label("守候", systemImage: "text.bubble") }
                .tag(0)
            XiaoLanToolbox(app: app)
                .tabItem { Label("工具箱", systemImage: "square.grid.2x2") }
                .tag(1)
            XiaoLanSettingsTab(app: app, settings: settings)
                .tabItem { Label("設定", systemImage: "link") }
                .tag(2)
        }
    }
}

/// 守候: the watch card (start / stop), both order links, the record, and the way to WeChat and WeCom.
struct XiaoLanWatchTab: View {
    @ObservedObject var app: AppModel
    @ObservedObject var board: BoardLink
    @ObservedObject var chat: ChatToolLink
    @ObservedObject var wework: ChatToolLink
    @AppStorage(WatchSettings.serverOnKey) private var serverOn = false
    @AppStorage(WatchSettings.weworkOnKey) private var weworkOn = false
    @State private var problem: String?
    @State private var watchSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("微信守候").font(.subheadline).foregroundStyle(.secondary)
                        Text(app.watching ? "守候中" : "尚未開始").font(.largeTitle.bold())
                        if !app.watchStatus.isEmpty { Text(verbatim: app.watchStatus).font(.subheadline) }
                        Text(app.watching ? "已讀 \(app.watchRead) 則訊息。伺服器和工具箱的指令會依序執行。"
                                          : "開始後 Echo 會看著微信，伺服器（個微、企微）和工具箱的指令也在這時執行。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            if app.watching {
                                Task { await app.stopAgent() }
                            } else {
                                problem = app.startWatch()
                            }
                        } label: {
                            Text(app.watching ? "停止守候" : "開始守候").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(app.watching ? .red : .accentColor)
                        if let problem { Text(verbatim: problem).font(.footnote).foregroundStyle(.red) }
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    StatusChips(app: app, board: board, pointer: app.pointer, calibrator: app.calibrator)
                    CalibrateButton(calibrator: app.calibrator, board: board, pointer: app.pointer)
                } header: {
                    Text("開發板與畫面")
                } footer: {
                    Text("點橘色的項目完成設定。校準時請讓 Echo 留在最前面、打開共享整個螢幕。")
                }
                Section("指令連線") {
                    XiaoLanLinkRow(title: "個人微信（智微兔指令）", link: chat, on: serverOn)
                    XiaoLanLinkRow(title: "企業微信（智企微行指令）", link: wework, on: weworkOn)
                    NavigationLink {
                        XiaoLanHistory(chat: chat, wework: wework)
                    } label: {
                        XiaoLanRow(title: "指令記錄", detail: "伺服器和工具箱的指令做了什麼、讀到什麼", icon: "list.bullet.rectangle")
                    }
                }
                Section("常用") {
                    Button { watchSettings = true } label: {
                        XiaoLanRow(title: "守候設定", detail: "守候哪些會話、主人權限、接話、回覆規則與隱私", icon: "person.2")
                    }
                    Button { open("weixin://") } label: {
                        XiaoLanRow(title: "打開微信", detail: "守候開始後回到微信", icon: "message")
                    }
                    Button { open("wxwork://") } label: {
                        XiaoLanRow(title: "打開企業微信", detail: "企業微信的指令在這裡執行", icon: "building.2")
                    }
                }
            }
            .navigationTitle("Echo")
            .sheet(isPresented: $watchSettings) { WatchView(app: app) }
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { UIApplication.shared.open(u) }
    }
}

struct XiaoLanRow: View {
    var title: String
    var detail: String
    var icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 28).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct XiaoLanLinkRow: View {
    var title: String
    @ObservedObject var link: ChatToolLink
    var on: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Group {
                if !on {
                    Text("未開啟：到「設定」填伺服器位址")
                } else {
                    switch link.state {
                    case .off: Text("開始守候時連線")
                    case .connecting: Text("連線中…")
                    case .connected: Text("已連線 · 待執行 \(link.pending.count) 則")
                    case .waiting(let why): Text("連不上：\(why)")
                    }
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 指令記錄: both links' records, newest first.
struct XiaoLanHistory: View {
    @ObservedObject var chat: ChatToolLink
    @ObservedObject var wework: ChatToolLink

    var body: some View {
        List {
            // 199 (the kernel's 三本账 / 巡检看板): every order's line, both apps, newest first; redrawn as the records change
            Section {
                lines(Array(OrderLedger.lines(50).reversed()))
            } header: {
                Text("發送賬（✓ 成功 · ✗ 失敗 · ◐ 部分完成 · ? 結果不明）")
            } footer: {
                Text("失敗或不明的指令會存一張當下畫面，在「檔案 › 我的 iPad › Echo › ledger」，檔名寫在那一行最後。同樣的建群、拉人、轉發 30 分鐘內不會重做；這類動作之間會隨機隔 45–120 秒。")
            }
            Section("個人微信") { lines(chat.history) }
            Section("企業微信") { lines(wework.history) }
        }
        .navigationTitle("指令記錄")
    }

    @ViewBuilder private func lines(_ all: [String]) -> some View {
        if all.isEmpty {
            Text("還沒有記錄").foregroundStyle(.secondary)
        } else {
            ForEach(Array(all.reversed().enumerated()), id: \.offset) { _, line in
                Text(verbatim: line).font(.footnote).textSelection(.enabled)
            }
        }
    }
}

/// 工具箱: search, the common three, then every order by use.
struct XiaoLanToolbox: View {
    @ObservedObject var app: AppModel
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section("常用操作") { ForEach(XiaoLanTools.common) { link($0) } }
                }
                ForEach(XiaoLanTools.groups) { group in
                    let tools = group.tools.filter { XiaoLanTools.matches($0, query) }
                    if !tools.isEmpty {
                        Section(group.title) { ForEach(tools) { link($0) } }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜尋工具，例如發檔案、群成員")
            .navigationTitle("工具箱")
        }
    }

    private func link(_ tool: XiaoLanTools.Tool) -> some View {
        NavigationLink {
            XiaoLanToolForm(app: app, tool: tool)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                Text(tool.hint).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// One order typed by hand: its fields, which app, and 執行 (queued for watch).
struct XiaoLanToolForm: View {
    @ObservedObject var app: AppModel
    let tool: XiaoLanTools.Tool
    @State private var appChoice = XiaoLanOrders.App.wechat
    @State private var values: [String: String] = [:]
    @State private var toggles: [String: Bool] = [:]
    @State private var message: String?

    var body: some View {
        Form {
            if tool.apps.count > 1 {
                Picker("在哪裡做", selection: $appChoice) {
                    Text("微信").tag(XiaoLanOrders.App.wechat)
                    Text("企業微信").tag(XiaoLanOrders.App.wework)
                }
                .pickerStyle(.segmented)
            }
            let fields = XiaoLanTools.fields(tool.type, appChoice)
            if fields.isEmpty {
                Text("這個操作不用填寫。").foregroundStyle(.secondary)
            }
            ForEach(fields) { field in
                switch field.kind {
                case .toggle:
                    Toggle(field.label, isOn: Binding(get: { toggles[field.key] ?? false }, set: { toggles[field.key] = $0 }))
                case .long, .lines:
                    TextField(field.label, text: binding(field.key), axis: .vertical).lineLimit(2...8)
                case .text, .list:
                    TextField(field.label, text: binding(field.key))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Section {
                Button("執行") { run() }.disabled(!app.watching)
                if !app.watching { Text("要先在「守候」開始守候，指令才會執行。").font(.footnote).foregroundStyle(.secondary) }
                if let message { Text(verbatim: message).font(.footnote) }
            } footer: {
                Text("只在測試群測試；看到微信的安全提示就停止守候。")
            }
        }
        .navigationTitle(XiaoLanOrders.label(tool.type, appChoice) ?? tool.title)
        .onAppear { appChoice = tool.apps.first ?? .wechat }
    }

    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0 })
    }

    private func run() {
        let item = XiaoLanTools.order(tool.type, app: appChoice, values: values, toggles: toggles)
        let link = appChoice == .wework ? app.weworkTool : app.chatTool
        if let why = link.enqueueLocal(item) {
            message = "沒有排入：" + why
        } else {
            message = "已排入，守候中會依序執行；結果看「守候 › 指令記錄」。"
        }
    }
}

/// 設定: the two order servers, the board / screen / calibration (Pilot's settings), and the version.
struct XiaoLanSettingsTab: View {
    @ObservedObject var app: AppModel
    @ObservedObject var settings: Settings
    @AppStorage(WatchSettings.serverOnKey) private var serverOn = false
    @AppStorage(WatchSettings.serverURLKey) private var serverURL = ""
    @AppStorage(WatchSettings.robotKey) private var robot = WatchSettings.defaultRobot
    @AppStorage(WatchSettings.weworkOnKey) private var weworkOn = false
    @AppStorage(WatchSettings.wechatOffKey) private var wechatOff = false  // 200
    @AppStorage(WatchSettings.weworkURLKey) private var weworkURL = ""
    @AppStorage(WatchSettings.weworkCodeKey) private var weworkCode = ""
    @AppStorage(LeadModel.key) private var lead = LeadModel.codex.rawValue  // 193
    @AppStorage(LeadModel.plannerKey) private var plannerLead = LeadModel.codex.rawValue  // 197
    @AppStorage(AutoAccept.wechatKey) private var acceptWeChat = false  // 198
    @AppStorage(AutoAccept.weworkKey) private var acceptWeCom = false
    @AppStorage(AutoAccept.perMinuteKey) private var acceptPerMinute = AutoAccept.defaultPerMinute
    @State private var advanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("接個人微信的指令", isOn: $serverOn)
                    if serverOn {
                        TextField("伺服器位址，例如 http://192.168.31.85:18971/zwt", text: $serverURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        TextField("機器人 ID", text: $robot).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: {
                    Text("個人微信（智微兔）")
                } footer: {
                    Text("改了位址要重新開始守候才會用新的。")
                }
                Section {
                    // 200 (user 11-28: 「你怎麽還是亂動個微啊」)
                    Toggle("暫停守候個人微信（不看、不點、不叫回）", isOn: $wechatOff)
                    Toggle("接企業微信的指令", isOn: $weworkOn)
                    if weworkOn {
                        TextField("伺服器位址，例如 http://192.168.31.85:18970/qiwei", text: $weworkURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        TextField("機器人編號", text: $weworkCode).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                } header: {
                    Text("企業微信（智企微行）")
                }
                // 193 (user 11-27: 「Codex 為主（豆包副）或豆包為主（Codex 副），隨時互換」)
                Section {
                    Picker("看圖、看影片", selection: $lead) {
                        ForEach(LeadModel.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                    // 197 (user 11-28: 規劃豆包不太行): planning a new order chooses on its own
                    Picker("學新指令（規劃）", selection: $plannerLead) {
                        ForEach(LeadModel.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
                    }
                } header: {
                    Text("主模型")
                } footer: {
                    Text("主模型先做；失敗、沒回答、看不清或額度用完才換副模型。每一步找點擊位置固定用豆包（要快）；守候、讀訊息、發訊息都是固定步驟，不用模型。")
                }
                // 198 (user 11-28: 「自動通過好友…加一個頻率和開關…企微和個微各一個」)
                Section {
                    Toggle("微信：自動通過好友", isOn: $acceptWeChat)
                    Toggle("企業微信：自動通過客戶", isOn: $acceptWeCom)
                    Stepper("每分鐘最多通過 \(acceptPerMinute) 個", value: $acceptPerMinute, in: 1...30)
                } header: {
                    Text("自動通過好友申請")
                } footer: {
                    Text("守候時看到「通訊錄」的紅點就去通過：從最早申請的（最下面）開始往上，每一個之間的間隔是隨機的。關掉的那一邊不會去動。")
                }
                Section("開發板、畫面與模型") {
                    Button { advanced = true } label: {
                        XiaoLanRow(title: "進階設定", detail: "開發板、共享螢幕、校準、模型與隱私", icon: "gearshape")
                    }
                }
                Section("關於") {
                    LabeledContent("Echo 版本", value: Self.version)
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $advanced) { SettingsView(app: app, settings: settings, board: app.board) }
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
