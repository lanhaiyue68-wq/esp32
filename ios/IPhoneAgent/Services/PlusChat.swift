import Foundation

/// Phase C (specs/004-codex-style-agent §2.1–2.2): ChatGPT Plus, signed in the way Codex is, as the planner — the
/// "commander" that splits a task into steps and replans when stuck. Every step is still acted by the fast model
/// (Doubao): Plus has a quota, a watch asks hundreds of times an hour, the planner a few times a task.
/// Until 11-08 every run planned with Doubao (865 calls in logs(12), none to Plus): sign-in was only tested in phase A.
/// Any failure — not signed in, the quota, the network, a changed backend — plans with `fallback` instead, logged, and
/// Plus rests a while (half an hour after a 429, two minutes otherwise) before it is tried again.
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
    private var restUntil = 0.0
    private(set) var lastUsedPlus = false
    var model: String { lastUsedPlus ? "plus:\(plusModel)" : fallback.model }

    init(model: String, fallback: ChatModel, tokens: @escaping () -> ChatGPTPlus.Tokens? = { ChatGPTPlus.saved },
         save: @escaping (ChatGPTPlus.Tokens) -> Void = { ChatGPTPlus.save($0) },
         ask: @escaping Ask = { try await ChatGPTPlus.ask($0, model: $1, system: $2, prompt: $3, image: $4) }) {
        self.plusModel = model; self.fallback = fallback; self.tokens = tokens; self.save = save; self.askPlus = ask
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
        return PlusChat(model: model, fallback: fallback)
    }

    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        if now() >= restUntil, let signedIn = tokens() {
            do {
                let (answer, fresh) = try await askPlus(signedIn, plusModel, system, text, image)
                if fresh != signedIn { save(fresh) }
                guard !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatGPTPlus.Failure(message: "empty answer")
                }
                lastUsedPlus = true
                DebugLog.write("plus planner: \(plusModel) first token \(answer.firstTokenMs ?? -1) ms, total \(answer.totalMs) ms")
                return ChatResult(text: answer.text, firstToken: answer.firstTokenMs.map { Double($0) / 1000 },
                                  total: Double(answer.totalMs) / 1000, finishReason: "stop")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let message = error.localizedDescription
                let rest: Double = message.contains("HTTP 429") ? 1800 : 120
                restUntil = now() + rest
                DebugLog.write("plus planner: \(message.prefix(160)); \(fallback.model) plans for \(Int(rest / 60)) min")
            }
        }
        lastUsedPlus = false
        return try await fallback.chat(system: system, text: text, image: image, maxTokens: maxTokens, temperature: temperature)
    }
}
