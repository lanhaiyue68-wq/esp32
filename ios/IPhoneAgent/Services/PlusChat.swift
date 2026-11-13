import Foundation

/// Phase C (specs/004-codex-style-agent §2.1–2.2): ChatGPT Plus, signed in the way Codex is, as the planner — the
/// "commander" that splits a task into steps and replans when stuck. Every step is still acted by the fast model
/// (Doubao): Plus has a quota, a watch asks hundreds of times an hour, the planner a few times a task.
/// Until 11-08 every run planned with Doubao (865 calls in logs(12), none to Plus): sign-in was only tested in phase A.
/// Any failure — not signed in, the quota, the network, a changed backend — plans with `fallback` instead, logged, and
/// Plus rests a while (half an hour after a 429, from two minutes up to half an hour otherwise) before it is tried again.
/// User 11-12: "登錄兩個 codex，一個額度用完自動切換另一個": with a second account signed in, a failing account rests
/// and the other one plans; Doubao only when none can.
@MainActor final class PlusChat: ChatModel {
    static let enabledKey = "plusPlanner", modelKey = "plusPlannerModel"
    /// Answered in 2.4–3.4 s on this account in phase A (logs 11-07).
    static let defaultModel = "gpt-6.1-terra"

    typealias Ask = (ChatGPTPlus.Tokens, String, String, String, Data?) async throws -> (ChatGPTPlus.Answer, ChatGPTPlus.Tokens)

    /// One signed-in account: its tokens, where fresh ones go, and how long it rests after a failure.
    struct Account {
        let name: String
        let tokens: () -> ChatGPTPlus.Tokens?
        let save: (ChatGPTPlus.Tokens) -> Void
        let rest: PlusRest
        /// The models this account listed when last read, and how to read them again (nil: it is not read; tests).
        var listed: () -> [String] = { [] }
        var readModels: ((ChatGPTPlus.Tokens) async throws -> [String])? = nil
    }

    /// The planner's model when this account lists it (or nothing is known yet), else the account's own first one.
    nonisolated static func model(for listed: [String], preferred: String) -> String {
        listed.isEmpty || listed.contains(preferred) ? preferred : listed[0]
    }

    /// The account's own "this model is not for you" (not a 400 about one request, a picture too big).
    nonisolated static func modelRefused(_ message: String) -> Bool {
        message.contains("HTTP 400") && message.contains("model") && message.contains("not supported")
    }

    let plusModel: String
    let fallback: ChatModel
    private let accounts: [Account]
    private let askPlus: Ask
    private(set) var lastUsedPlus = false
    /// The account that answered last ("1", "2"); nil when the fallback did.
    private(set) var lastAccount: String?
    /// The model that answered last (an account's own when it cannot use `plusModel`).
    private(set) var lastPlusModel: String?
    var model: String { lastUsedPlus ? "plus:\(lastPlusModel ?? plusModel)" : fallback.model }
    /// Who plans when no account can, as the user is told ("豆包", or the backup first).
    var fallbackLabel = "豆包"

    /// `tokens`, `save` and `rest` are account 1; `second` is account 2 (none unless given).
    init(model: String, fallback: ChatModel, tokens: @escaping () -> ChatGPTPlus.Tokens? = { ChatGPTPlus.saved(slot: 0) },
         save: @escaping (ChatGPTPlus.Tokens) -> Void = { ChatGPTPlus.save($0, slot: 0) },
         ask: @escaping Ask = { try await ChatGPTPlus.ask($0, model: $1, system: $2, prompt: $3, image: $4) },
         rest: PlusRest? = nil, second: Account? = nil, listed: @escaping () -> [String] = { [] },
         readModels: ((ChatGPTPlus.Tokens) async throws -> [String])? = nil) {
        self.plusModel = model; self.fallback = fallback; self.askPlus = ask
        self.accounts = [Account(name: "1", tokens: tokens, save: save, rest: rest ?? PlusRest(), listed: listed,
                                 readModels: readModels)] + (second.map { [$0] } ?? [])
    }

    /// Account 2 as signed in on this phone.
    static var secondAccount: Account {
        Account(name: "2", tokens: { ChatGPTPlus.saved(slot: 1) }, save: { ChatGPTPlus.save($0, slot: 1) }, rest: .second,
                listed: { ChatGPTPlus.listedModels(slot: 1) }, readModels: { try await ChatGPTPlus.readModels($0, slot: 1) })
    }

    /// The planner for a run: Plus when it is switched on and signed in, else the given model.
    static func planner(fallback doubao: ChatModel, defaults: UserDefaults = .standard) -> ChatModel {
        let on = defaults.object(forKey: enabledKey) as? Bool ?? true
        // User 11-12: a backup model the user filled in plans before the model in Settings (豆包).
        let backup = BackupModel.client()
        let fallback: ChatModel = backup.map { ModelChain([$0, doubao], rests: [.backup, nil]) } ?? doubao
        if let backup { DebugLog.write("planner: backup \(backup.model), then \(doubao.model)") }
        guard on, ChatGPTPlus.saved != nil else {
            DebugLog.write("planner: \(fallback.model) (Plus \(on ? "not signed in" : "switched off"))")
            return fallback
        }
        let model = defaults.string(forKey: modelKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
        let two = ChatGPTPlus.saved(slot: 0) != nil && ChatGPTPlus.saved(slot: 1) != nil
        DebugLog.write("planner: ChatGPT Plus \(model)\(two ? " (2 accounts)" : ""), \(fallback.model) if it fails")
        let plus = PlusChat(model: model, fallback: fallback, rest: .shared, second: secondAccount,
                            listed: { ChatGPTPlus.listedModels(slot: 0) }, readModels: { try await ChatGPTPlus.readModels($0, slot: 0) })
        if backup != nil { plus.fallbackLabel = "候補模型" }
        return plus
    }

    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        let say = accounts[0].rest.onFailure  // RunSession tells the user through account 1's (the shared one)
        let named = accounts.count > 1 && accounts.dropFirst().contains { $0.tokens() != nil }
        var failed: [String] = []  // accounts that failed on this call
        for account in accounts {
            guard !account.rest.resting, let signedIn = account.tokens() else { continue }
            var asked = Self.model(for: account.listed(), preferred: plusModel)
            do {
                let reply: (ChatGPTPlus.Answer, ChatGPTPlus.Tokens)
                do {
                    reply = try await askPlus(signedIn, asked, system, text, image)
                } catch let refused where Self.modelRefused(refused.localizedDescription) && account.readModels != nil {
                    // User 11-14: "默認就一個6.1luna" — account 1's plan lists gpt-6-luna first and no gpt-6.1-* (11-13 log),
                    // not gpt-6.1-terra, and since 11-13
                    // it was put to rest each time (6 hours from 132's first fix) while it could plan. Its own models
                    // are read and its own first one is asked, once; it is used from then on.
                    guard let read = account.readModels else { throw refused }
                    let ownList = try await read(signedIn)
                    let own = Self.model(for: ownList, preferred: plusModel)
                    guard own != asked else { throw refused }
                    DebugLog.write("plus planner (account \(account.name)): \(asked) is not for this account; asking \(own)")
                    asked = own
                    reply = try await askPlus(signedIn, asked, system, text, image)
                }
                let (answer, fresh) = reply
                if fresh != signedIn { account.save(fresh) }
                guard !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatGPTPlus.Failure(message: "empty answer")
                }
                lastUsedPlus = true
                lastAccount = account.name
                lastPlusModel = asked
                account.rest.succeeded()
                if !failed.isEmpty { say?("Codex 帳號 \(failed.joined(separator: "、")) 不能用，已改用帳號 \(account.name)") }
                DebugLog.write("plus planner: \(asked)\(named ? " (account \(account.name))" : "") first token \(answer.firstTokenMs ?? -1) ms, total \(answer.totalMs) ms, effort \(ChatGPTPlus.reasoningEffort ?? "default")")
                return ChatResult(text: answer.text, firstToken: answer.firstTokenMs.map { Double($0) / 1000 },
                                  total: Double(answer.totalMs) / 1000, finishReason: "stop")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }  // a stopped run says nothing about Plus
                let message = error.localizedDescription
                let down = ModelRequestFailure.isNetworkDown(error)
                // Said once below, when no account is left: account 1's quota said alone while account 2 answers
                // would be wrong.
                let seconds = account.rest.failed(message, networkDown: down, quiet: true)
                failed.append(account.name)
                DebugLog.write("plus planner\(named ? " (account \(account.name))" : ""): \(message.prefix(160)); it rests \(Int(seconds / 60)) min")
                if down { break }  // no network: another account cannot do better
            }
        }
        if !failed.isEmpty {
            let back = accounts.map(\.rest.secondsLeft).filter { $0 > 0 }.min() ?? 0
            let who = named ? "（帳號 \(failed.joined(separator: "、"))）" : ""
            say?("Codex 連不上\(who)，接下來 \(max(1, Int(back / 60))) 分鐘由\(fallbackLabel)規劃")
            DebugLog.write("plus planner: no account can plan; \(fallback.model) plans")
        }
        lastUsedPlus = false
        lastAccount = nil
        return try await fallback.chat(system: system, text: text, image: image, maxTokens: maxTokens, temperature: temperature)
    }
}

/// How long Plus rests. It outlives a run: every run used to start by waiting 76 s for a Plus that could not be reached
/// (11-08 20:04Z on: 57 timeouts in a row, a third of the time of a long task, and nobody could tell).
@MainActor final class PlusRest {
    static let shared = PlusRest()
    /// Account 2's (user 11-12): it rests on its own.
    static let second = PlusRest()
    /// The backup planner's (BackupModel): a wrong key or no credit is not asked every step.
    static let backup = PlusRest()
    private(set) var failures = 0
    private(set) var lastError = ""
    private var until = 0.0
    /// Said to the user the moment Codex drops out.
    var onFailure: ((String) -> Void)?

    var resting: Bool { now() < until }
    var secondsLeft: Double { max(0, until - now()) }
    /// Where things stand, for the test channel and for the start of a run.
    var summary: String { failures == 0 ? "ok" : "unreachable (\(failures) in a row): \(lastError.prefix(80))" }

    /// No signed-in account can plan now (account 2 counts only when it is signed in).
    static var allDown: Bool {
        shared.failures > 0 && (ChatGPTPlus.saved(slot: 1) == nil || second.failures > 0)
    }
    /// Both accounts, for the start of a run and the test channel.
    static var summaryAll: String {
        ChatGPTPlus.saved(slot: 1) == nil ? shared.summary : "account 1 \(shared.summary); account 2 \(second.summary)"
    }

    /// The seconds Plus now rests.
    /// A network that is down for a moment says nothing about Codex: over USB 11-09 a Wi-Fi drop of a few minutes put it to
    /// rest for 2, then 10 minutes, and the next tasks ran without it. It rests a minute, and the next real failure is still a first.
    static let offlineRest = 60.0

    /// quiet: the caller tells the user (PlusChat, once for all accounts).
    @discardableResult
    func failed(_ message: String, networkDown: Bool = false, quiet: Bool = false) -> Double {
        if networkDown {
            lastError = message
            until = now() + Self.offlineRest
            return Self.offlineRest
        }
        failures += 1
        lastError = message
        let seconds = Self.restSeconds(failures: failures, message: message)
        until = now() + seconds
        if !quiet { onFailure?("Codex 連不上（\(message.prefix(40))），接下來 \(Int(seconds / 60)) 分鐘由豆包規劃") }
        return seconds
    }

    func succeeded() { failures = 0; lastError = ""; until = 0 }

    /// 131 over the cloud 11-13 (user: "账号1有问题，这种情况你让他自动切2"): account 1 answered "the 'gpt-6.1-terra' model
    /// is not supported when using Codex with a ChatGPT account" and was asked again every 2-10 minutes before account 2;
    /// account 2 at its limit said it would reset in 8 minutes (resets_at) and rested 30. An account that cannot use the
    /// model rests 6 hours, so account 2 plans straight away; one at its limit rests until it says it resets.
    nonisolated static func restSeconds(failures: Int, message: String, at: Double = Date().timeIntervalSince1970) -> Double {
        let unusable = 6 * 3600.0
        if message.contains("HTTP 429") {
            if let r = message.range(of: #""resets_at"\s*:\s*\d{9,11}"#, options: .regularExpression),
               let resets = Double(String(message[r].filter { $0.isNumber })) {
                return min(max(resets - at + 30, 60), unusable)
            }
            return 1800
        }
        // Only the account's own "this model is not for you": a 400 about one request (a picture too big) is that request's.
        if message.contains("HTTP 400"), message.contains("model"), message.contains("not supported") { return unusable }
        return failures <= 1 ? 120 : failures == 2 ? 600 : 1800
    }
}
