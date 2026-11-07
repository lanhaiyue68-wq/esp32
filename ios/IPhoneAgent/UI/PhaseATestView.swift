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
    @State private var signedIn = ChatGPTPlus.saved != nil
    @State private var signingIn = false
    @State private var models: [String] = []
    @State private var model = ChatGPTPlus.fallbackModel
    @State private var answer = ""
    @State private var asking = false

    private enum Send { case none, keyboard, board }

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
                LabeledContent("狀態", value: signedIn ? "已登入" : "未登入")
                if let code {
                    LabeledContent("一次性代碼", value: code.userCode)
                    Button("打開登入頁（代碼已複製）") { UIApplication.shared.open(code.verificationURL) }
                }
                Button(signingIn ? "等待你在網頁上登入…" : "登入 ChatGPT") { signIn() }.disabled(signingIn)
                Button("讀取我能用的模型") { loadModels() }.disabled(!signedIn)
                Picker("模型", selection: $model) {
                    ForEach(models.isEmpty ? [model] : models, id: \.self) { Text($0).tag($0) }
                }
                Button(asking ? "詢問中…" : "用目前畫面問一次") { askOnce() }.disabled(!signedIn || asking)
                if !plusStatus.isEmpty { Text(plusStatus).font(.callout) }
                if !answer.isEmpty { Text(answer).font(.callout).textSelection(.enabled) }
                if signedIn {
                    Button("登出", role: .destructive) { ChatGPTPlus.save(nil); signedIn = false; models = [] }
                }
            } header: {
                Text("ChatGPT Plus")
            } footer: {
                Text("照官方 Codex 的方式登入和使用 Plus 額度。這不是 OpenAI 正式開放給其他 App 的方式，可能隨時失效，"
                     + "也可能影響帳號；你已同意承擔這個風險（2026-11-08）。登入憑證只存在這支手機的鑰匙圈。")
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
        Task { @MainActor in
            do {
                let c = try await ChatGPTPlus.requestDeviceCode()
                code = c
                UIPasteboard.general.string = c.userCode  // Lan Agent is in front: allowed
                plusStatus = "請按「打開登入頁」，登入 ChatGPT 後貼上代碼 \(c.userCode)，再回到這裡"
                DebugLog.write("phase A plus: device code issued")
                let tokens = try await ChatGPTPlus.waitForSignIn(c)
                signedIn = true
                code = nil
                plusStatus = "✅ 已登入" + (tokens.accountID == nil ? "（沒有讀到帳號 id）" : "")
                DebugLog.write("phase A plus: signed in, account id \(tokens.accountID == nil ? "missing" : "present")")
                loadModels()
            } catch {
                plusStatus = "❌ \(error.localizedDescription)"
                DebugLog.write("phase A plus: sign-in failed: \(error.localizedDescription)")
            }
            signingIn = false
        }
    }

    private func loadModels() {
        guard let tokens = ChatGPTPlus.saved else { return }
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
        guard let tokens = ChatGPTPlus.saved else { return }
        asking = true
        answer = ""
        Task { @MainActor in
            do {
                let (a, _) = try await ChatGPTPlus.ask(tokens, model: model,
                                                       prompt: "用一句中文說：這張 iPhone 截圖是什麼畫面？", image: app.feed.frame)
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
