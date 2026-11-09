import Foundation

/// Phase C (specs/004-codex-style-agent §2.1–2.2): ChatGPT Plus, signed in the way Codex is, as the planner — the
/// "commander" that splits a task into steps and replans when stuck. Every step is still acted by the fast model
/// (Doubao): Plus has a quota, a watch asks hundreds of times an hour, the planner a few times a task.
/// Until 11-08 every run planned with Doubao (865 calls in logs(12), none to Plus): sign-in was only tested in phase A.
/// Any failure — not signed in, the quota, the network, a changed backend — plans with `fallback` instead, logged, and
/// Plus rests a while (half an hour after a 429, from two minutes up to half an hour otherwise) before it is tried again.
@MainActor final class PlusChat: ChatModel {
    static let enabledKey = "plusPlanner", modelKey = "plusPlannerModel"
    /// Answered in 2.4–3.4 s on this account in phase A (logs 11-07).
    static let defaultModel = "gpt-6.1-terra"

    typealias Ask = (ChatGPTPlus.Tokens, String, String, String, Data?) async throws -> (ChatGPTPlus.Answer, ChatGPTPlus.Tokens)

    let plusModel: String
    let fallback: ChatModel
    private let tokens: () -> ChatGPTPlus.Tokens?
    private let save: (ChatGPTPlus.Tokens) -> Void
    private let askPlus: Ask
    private let rest: PlusRest
    private(set) var lastUsedPlus = false
    var model: String { lastUsedPlus ? "plus:\(plusModel)" : fallback.model }

    init(model: String, fallback: ChatModel, tokens: @escaping () -> ChatGPTPlus.Tokens? = { ChatGPTPlus.saved },
         save: @escaping (ChatGPTPlus.Tokens) -> Void = { ChatGPTPlus.save($0) },
         ask: @escaping Ask = { try await ChatGPTPlus.ask($0, model: $1, system: $2, prompt: $3, image: $4) },
         rest: PlusRest = PlusRest()) {
        self.plusModel = model; self.fallback = fallback; self.tokens = tokens; self.save = save; self.askPlus = ask
        self.rest = rest
    }

    /// The planner for a run: Plus when it is switched on and signed in, else the given model.
    static func planner(fallback: ChatModel, defaults: UserDefaults = .standard) -> ChatModel {
        let on = defaults.object(forKey: enabledKey) as? Bool ?? true
        guard on, ChatGPTPlus.saved != nil else {
            DebugLog.write("planner: \(fallback.model) (Plus \(on ? "not signed in" : "switched off"))")
            return fallback
        }
        let model = defaults.string(forKey: modelKey).flatMap { $0.isEmpty ? nil : $0 } ?? defaultModel
        DebugLog.write("planner: ChatGPT Plus \(model), \(fallback.model) if it fails")
        return PlusChat(model: model, fallback: fallback, rest: .shared)
    }

    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        if !rest.resting, let signedIn = tokens() {
            do {
                let (answer, fresh) = try await askPlus(signedIn, plusModel, system, text, image)
                if fresh != signedIn { save(fresh) }
                guard !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatGPTPlus.Failure(message: "empty answer")
                }
                lastUsedPlus = true
                rest.succeeded()
                DebugLog.write("plus planner: \(plusModel) first token \(answer.firstTokenMs ?? -1) ms, total \(answer.totalMs) ms")
                return ChatResult(text: answer.text, firstToken: answer.firstTokenMs.map { Double($0) / 1000 },
                                  total: Double(answer.totalMs) / 1000, finishReason: "stop")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }  // a stopped run says nothing about Plus
                let message = error.localizedDescription
                let seconds = rest.failed(message)
                DebugLog.write("plus planner: \(message.prefix(160)); \(fallback.model) plans for \(Int(seconds / 60)) min")
            }
        }
        lastUsedPlus = false
        return try await fallback.chat(system: system, text: text, image: image, maxTokens: maxTokens, temperature: temperature)
    }
}

/// How long Plus rests. It outlives a run: every run used to start by waiting 76 s for a Plus that could not be reached
/// (11-08 20:04Z on: 57 timeouts in a row, a third of the time of a long task, and nobody could tell).
@MainActor final class PlusRest {
    static let shared = PlusRest()
    private(set) var failures = 0
    private(set) var lastError = ""
    private var until = 0.0
    /// Said to the user the moment Codex drops out.
    var onFailure: ((String) -> Void)?

    var resting: Bool { now() < until }
    /// Where things stand, for the test channel and for the start of a run.
    var summary: String { failures == 0 ? "ok" : "unreachable (\(failures) in a row): \(lastError.prefix(80))" }

    /// The seconds Plus now rests.
    @discardableResult
    func failed(_ message: String) -> Double {
        failures += 1
        lastError = message
        let seconds = Self.restSeconds(failures: failures, message: message)
        until = now() + seconds
        onFailure?("Codex 連不上（\(message.prefix(40))），接下來 \(Int(seconds / 60)) 分鐘由豆包規劃")
        return seconds
    }

    func succeeded() { failures = 0; lastError = ""; until = 0 }

    nonisolated static func restSeconds(failures: Int, message: String) -> Double {
        if message.contains("HTTP 429") { return 1800 }
        return failures <= 1 ? 120 : failures == 2 ? 600 : 1800
    }
}
