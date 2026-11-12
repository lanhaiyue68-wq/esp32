import SwiftUI
import UIKit

/// Phase A of the new design (specs/004-codex-style-agent): two feasibility tests on this phone before anything is
/// built on them. 1) Lan Agent's keyboard types text the app hands it. 2) ChatGPT Plus answers from inside the app.
/// Every result is also written to the debug log, so a shared log shows what happened.
struct PhaseATestView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var bridge: KeyboardBridge
    @State private var keyboardResult = ""
    @State private var keyboardTesting = false
    @State private var code: ChatGPTPlus.DeviceCode?
    @State private var plusStatus = ""
    /// User 11-12: two Codex accounts; when one has no quota left the other plans. The one shown here.
    @State private var slot = 0
    @State private var signedIn = ChatGPTPlus.saved(slot: 0) != nil
    @State private var signingIn = false
    @State private var models: [String] = []
    @AppStorage(PlusChat.modelKey) private var model = PlusChat.defaultModel  // the test's and the commander's
    @AppStorage(PlusChat.enabledKey) private var plusPlanner = true
    @State private var answer = ""
    @State private var asking = false
    @AppStorage(BackupModel.kindKey) private var backupKind = BackupModel.Kind.off.rawValue
    @AppStorage(BackupModel.baseURLKey) private var backupBase = ""
    @AppStorage(BackupModel.modelKey) private var backupModel = ""
    @State private var backupKey = BackupModel.apiKey
    @State private var backupTesting = false
    @State private var backupStatus = ""

    private enum Send { case none, keyboard, board }

    private func testBackup() {
        guard let backup = BackupModel.client() else {
            backupStatus = backupKind == BackupModel.Kind.openAI.rawValue ? "請填好網址和模型名稱" : "請填好 API 金鑰"
            return
        }
        backupTesting = true
        backupStatus = ""
        Task { @MainActor in
            do {
                let r = try await backup.chat(system: "Answer in one short sentence.", text: "用一句中文說你是哪個模型。",
                                              image: nil, maxTokens: 200, temperature: 0)
                backupStatus = "✅ \(r.text.prefix(120))（\(backup.model)，\(String(format: "%.1f", r.total)) 秒）"
                DebugLog.write("backup planner test: \(backup.model) answered in \(String(format: "%.1f", r.total)) s")
            } catch {
                backupStatus = "❌ \(error.localizedDescription.prefix(300))"
                DebugLog.write("backup planner test failed: \(error.localizedDescription.prefix(200))")
            }
            backupTesting = false
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("本機服務", value: bridge.listening ? "已開啟" : "未開啟")
                LabeledContent("輸入法上次連線", value: bridge.lastSeen.map { $0.formatted(date: .omitted, time: .standard) } ?? "還沒連過")
                LabeledContent("允許完整取用", value: bridge.fullAccess.map { $0 ? "已開啟" : "未開啟" } ?? "未知")
                Button("① 排入測試文字") { runKeyboard(.none) }.disabled(keyboardTesting)
                Button("② 排入，由輸入法送出") { runKeyboard(.keyboard) }.disabled(keyboardTesting)
                Button("③ 排入，填完由開發板按 Enter") { runKeyboard(.board) }.disabled(keyboardTesting)
                if !keyboardResult.isEmpty { Text(keyboardResult).font(.callout) }
            } header: {
                Text("Lan Agent 輸入法")
            } footer: {
                Text("第一次先到 設定 › 一般 › 鍵盤 › 鍵盤 › 新增鍵盤，加入「Lan Agent」，再點進去打開「允許完整取用」。\n"
                     + "測試：按上面任一個按鈕，90 秒內到微信點輸入框，按地球鍵切到 Lan Agent 輸入法，字會自動填進去。"
                     + "請在開發板接著的時候測，看輸入法會不會被藏起來。")
            }

            Section {
                Picker("帳號", selection: $slot) {
                    ForEach(0..<ChatGPTPlus.accounts, id: \.self) { Text("帳號 \($0 + 1)").tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(signingIn)
                .onChange(of: slot) { _ in
                    signedIn = ChatGPTPlus.saved(slot: slot) != nil
                    code = nil
                    models = []
                    plusStatus = ""
                    answer = ""
                }
                LabeledContent("狀態", value: signedIn ? "已登入" : "未登入")
                LabeledContent("兩個帳號", value: (0..<ChatGPTPlus.accounts)
                    .map { "帳號 \($0 + 1)：\(ChatGPTPlus.saved(slot: $0) == nil ? "未登入" : "已登入")" }.joined(separator: "，"))
                if let code {
                    LabeledContent("一次性代碼", value: code.userCode)
                    Button("打開登入頁（代碼已複製）") { UIApplication.shared.open(code.verificationURL) }
                }
                Button(signingIn ? "等待你在網頁上登入…" : "登入 ChatGPT（帳號 \(slot + 1)）") { signIn() }.disabled(signingIn)
                Button("讀取我能用的模型") { loadModels() }.disabled(!signedIn)
                Picker("模型", selection: $model) {
                    ForEach(models.isEmpty ? [model] : models, id: \.self) { Text($0).tag($0) }
                }
                Button(asking ? "詢問中…" : "用目前畫面問一次") { askOnce() }.disabled(!signedIn || asking)
                Toggle("用 Plus 當總指揮（規劃者）", isOn: $plusPlanner)
                Text(plusPlanner && ChatGPTPlus.saved != nil
                     ? "任務的規劃與卡住時重新規劃用 \(model)；每一步的操作仍用設定裡的模型。先用帳號 1，帳號 1 額度用完或出錯時自動換帳號 2，兩個都不行才改用設定裡的模型。"
                     : "規劃用設定裡的模型。").font(.footnote).foregroundStyle(.secondary)
                if !plusStatus.isEmpty { Text(plusStatus).font(.callout) }
                if !answer.isEmpty { Text(answer).font(.callout).textSelection(.enabled) }
                if signedIn {
                    Button("登出帳號 \(slot + 1)", role: .destructive) { ChatGPTPlus.save(nil, slot: slot); signedIn = false; models = [] }
                }
            } header: {
                Text("ChatGPT Plus")
            } footer: {
                Text("照官方 Codex 的方式登入和使用 Plus 額度。這不是 OpenAI 正式開放給其他 App 的方式，可能隨時失效，"
                     + "也可能影響帳號；你已同意承擔這個風險（2026-11-08）。登入憑證只存在這支手機的鑰匙圈。")
            }

            // User 11-12: "再有一個候選的可以填大模型 api 的，就像豆包那樣"; "也要支持 Claude，可以不用，但是要有".
            Section {
                Picker("候補模型", selection: $backupKind) {
                    Text("不用").tag(BackupModel.Kind.off.rawValue)
                    Text("OpenAI 相容（像豆包）").tag(BackupModel.Kind.openAI.rawValue)
                    Text("Claude（API 金鑰）").tag(BackupModel.Kind.claude.rawValue)
                }
                if backupKind == BackupModel.Kind.openAI.rawValue {
                    TextField("網址，例如 https://ark.cn-beijing.volces.com/api/v3", text: $backupBase)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                if backupKind != BackupModel.Kind.off.rawValue {
                    TextField(backupKind == BackupModel.Kind.claude.rawValue ? "模型（空白 = \(BackupModel.claudeDefaultModel)）" : "模型名稱",
                              text: $backupModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API 金鑰", text: $backupKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onChange(of: backupKey) { BackupModel.saveKey($0) }
                    Button(backupTesting ? "測試中…" : "測試一次") { testBackup() }.disabled(backupTesting)
                    if !backupStatus.isEmpty { Text(backupStatus).font(.callout).textSelection(.enabled) }
                }
            } header: {
                Text("候補規劃模型")
            } footer: {
                Text("規劃順序：Codex 帳號 1 → 帳號 2 → 這個候補模型 → 設定裡的模型（豆包）。前面的不能用才輪到下一個。"
                     + "Claude 用 console.anthropic.com 申請的 API 金鑰（按用量計費）；Claude 的 Pro／Max 訂閱只能在官方 App 和 Claude Code 使用，不能在這裡登入。"
                     + "金鑰只存在這支手機的鑰匙圈。")
            }
        }
        .navigationTitle("新架構測試（階段 A）")
        .onAppear { bridge.start() }
    }

    private func runKeyboard(_ send: Send) {
        keyboardTesting = true
        keyboardResult = "已排入。請在 90 秒內：打開微信 → 點輸入框 → 切到 Lan Agent 輸入法"
        let keptAwake = app.keepAwake.start()  // the app keeps running while you are in WeChat
        Task { @MainActor in
            let text = "Lan Agent 輸入法測試：中文直接填入 ✅ \(Date().formatted(date: .omitted, time: .shortened))"
            let ok = await bridge.type(text, enter: send == .keyboard, within: 90)
            var result = ok ? "✅ 輸入法已填入" : "❌ 90 秒內輸入法沒有來拿字"
            if ok, send == .keyboard { result += "（輸入法已按換行）" }
            if ok, send == .board {
                try? await Task.sleep(nanoseconds: 600_000_000)
                do { try await app.pointer.key("enter"); result += "，開發板已按 Enter" }
                catch { result += "，開發板按 Enter 失敗：\(error.localizedDescription)" }
            }
            DebugLog.write("phase A keyboard test (\(send)): \(result)")
            keyboardResult = result
            if keptAwake, !app.watching, !app.agent.running { app.keepAwake.stop() }
            keyboardTesting = false
        }
    }

    private func signIn() {
        signingIn = true
        plusStatus = "取得登入代碼中…"
        let into = slot  // the account this sign-in is for
        Task { @MainActor in
            do {
                let c = try await ChatGPTPlus.requestDeviceCode()
                code = c
                UIPasteboard.general.string = c.userCode  // Lan Agent is in front: allowed
                plusStatus = "登入頁已打開（代碼 \(c.userCode) 已複製）：登入 ChatGPT 後貼上代碼，再回到這裡；沒跳出來就按「打開登入頁」"
                DebugLog.write("phase A plus: device code issued")
                // User 11-12: "登出後點登錄不跳轉網頁": the page waited for a second button. It opens by itself now.
                _ = await UIApplication.shared.open(c.verificationURL)
                let tokens = try await ChatGPTPlus.waitForSignIn(c)
                ChatGPTPlus.save(tokens, slot: into)
                signedIn = slot == into
                code = nil
                plusStatus = "✅ 帳號 \(into + 1) 已登入" + (tokens.accountID == nil ? "（沒有讀到帳號 id）" : "")
                DebugLog.write("phase A plus: account \(into + 1) signed in, account id \(tokens.accountID == nil ? "missing" : "present")")
                loadModels()
            } catch {
                // User 11-12: three sign-ins failed with only "TLS错误导致安全连接失败" and no page: the phone could not
                // reach auth.openai.com at all (its proxy), not the account. Said so.
                let unreachable = [URLError.secureConnectionFailed, .cannotConnectToHost, .cannotFindHost, .timedOut,
                                   .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed]
                    .contains((error as? URLError)?.code ?? .unknown)
                plusStatus = unreachable
                    ? "❌ 手機連不上 OpenAI（auth.openai.com），跟帳號無關：請檢查網路或代理／VPN 節點，用 Safari 打得開 chatgpt.com 再登入。（\(error.localizedDescription)）"
                    : "❌ \(error.localizedDescription)"
                DebugLog.write("phase A plus: sign-in failed: \(error.localizedDescription)")
            }
            signingIn = false
        }
    }

    private func loadModels() {
        guard let tokens = ChatGPTPlus.saved(slot: slot) else { return }
        Task { @MainActor in
            do {
                let list = try await ChatGPTPlus.models(tokens)
                models = list
                if let first = list.first, !list.contains(model) { model = first }
                plusStatus = "可用模型 \(list.count) 個"
                DebugLog.write("phase A plus: models \(list.prefix(12).joined(separator: ", "))")
            } catch {
                plusStatus = "❌ \(error.localizedDescription)"
                DebugLog.write("phase A plus: models failed: \(error.localizedDescription)")
            }
        }
    }

    private func askOnce() {
        let from = slot
        guard let tokens = ChatGPTPlus.saved(slot: from) else { return }
        asking = true
        answer = ""
        Task { @MainActor in
            do {
                let (a, fresh) = try await ChatGPTPlus.ask(tokens, model: model,
                                                           prompt: "用一句中文說：這張 iPhone 截圖是什麼畫面？", image: app.feed.frame)
                if fresh != tokens { ChatGPTPlus.save(fresh, slot: from) }
                var lines = ["✅ \(a.text)",
                             "模型 \(a.model)，第一個字 \(a.firstTokenMs.map { "\($0) ms" } ?? "—")，全部 \(a.totalMs) ms"]
                if !a.quota.isEmpty {
                    lines.append("額度：" + a.quota.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "，"))
                }
                answer = lines.joined(separator: "\n")
                DebugLog.write("phase A plus: \(a.model) first token \(a.firstTokenMs ?? -1) ms, total \(a.totalMs) ms, quota \(a.quota)")
            } catch {
                answer = "❌ \(error.localizedDescription)"
                DebugLog.write("phase A plus: ask failed (\(model)): \(error.localizedDescription)")
            }
            asking = false
        }
    }
}
