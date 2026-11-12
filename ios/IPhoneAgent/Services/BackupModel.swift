import Foundation

/// User 11-12: "再有一個候選的可以填大模型 api 的，就像豆包那樣" and "也要支持 Claude，可以不用，但是要有". A backup
/// planner the user fills in: any OpenAI-compatible endpoint (like 豆包), or Claude with an Anthropic API key.
/// Planning goes Codex account 1 → account 2 → this → the model in Settings (豆包).
/// Claude's Pro/Max subscription sign-in is for Anthropic's own apps and Claude Code only, so Claude is an API key here.
enum BackupModel {
    enum Kind: String, CaseIterable { case off, openAI, claude }
    static let kindKey = "backupPlannerKind", baseURLKey = "backupPlannerBaseURL", modelKey = "backupPlannerModel"
    static let keyAccount = "backup-planner-api-key"
    static let claudeBaseURL = "https://api.anthropic.com"
    static let claudeDefaultModel = "claude-opus-5-5"

    static var kind: Kind { Kind(rawValue: UserDefaults.standard.string(forKey: kindKey) ?? "") ?? .off }
    static var baseURL: String { UserDefaults.standard.string(forKey: baseURLKey) ?? "" }
    static var model: String { UserDefaults.standard.string(forKey: modelKey) ?? "" }
    static var apiKey: String { Keychain.get(keyAccount) ?? "" }

    static func saveKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed, for: keyAccount)
        if !trimmed.isEmpty { DebugLog.redact([trimmed]) }  // never in debug.log
    }

    /// The backup as a model to plan with; nil when it is off or not filled in.
    @MainActor static func client() -> ChatModel? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { DebugLog.redact([key]) }
        switch kind {
        case .off:
            return nil
        case .openAI:
            let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard URL(string: base)?.host != nil, !name.isEmpty else { return nil }
            return LLMClient(baseURL: base, model: name, apiKey: key)
        case .claude:
            guard !key.isEmpty else { return nil }
            return ClaudeChat(model: name.isEmpty ? claudeDefaultModel : name, apiKey: key)
        }
    }
}

/// Claude through Anthropic's Messages API with the user's API key (console.anthropic.com). Plain HTTP: Swift has no
/// official Anthropic SDK. API version 2026-10-21, which refuses temperature, so none is sent. On the models that take
/// it, the server-side refusal fallback ("default") is on: a declined request is re-run on a fallback model.
@MainActor final class ClaudeChat: ChatModel {
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let fallbackModels: Set<String> = ["claude-fable-5-2", "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5",
                                              "claude-sonnet-5-5"]
    let model: String
    private let apiKey: String
    private let base: String

    init(model: String, apiKey: String, base: String = BackupModel.claudeBaseURL) {
        self.model = model
        self.apiKey = apiKey
        var b = base
        while b.hasSuffix("/") { b.removeLast() }
        self.base = b
    }

    /// The request body: system, then one user turn with the screen (JPEG) and the text.
    nonisolated static func body(model: String, system: String, text: String, image: Data?) -> [String: Any] {
        var content: [[String: Any]] = []
        if let image {
            content.append(["type": "image",
                            "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]])
        }
        content.append(["type": "text", "text": text])
        // Thinking is on for the current models and counts against max_tokens: not lowballed (a planner's short
        // answer still fits; the API stops when the answer ends).
        var body: [String: Any] = ["model": model, "max_tokens": 16000, "system": system,
                                   "messages": [["role": "user", "content": content]]]
        if fallbackModels.contains(model) { body["fallbacks"] = "default" }
        return body
    }

    /// The text blocks of a Messages response (thinking blocks left out) and its stop reason.
    nonisolated static func text(_ data: Data) -> (text: String, stop: String?) {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ("", nil) }
        let blocks = o["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        return (text, o["stop_reason"] as? String)
    }

    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        guard let url = URL(string: base + "/v1/messages") else { throw LLMError(message: "Claude: bad address \(base)") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if Self.fallbackModels.contains(model) { request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(model: model, system: system, text: text, image: image))
        request.timeoutInterval = 90
        LLMClient.requests += 1
        let started = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 429: rate limit or no credit left; 529: overloaded. Either way the next model in line plans.
        guard status == 200 else {
            throw LLMError(message: "Claude HTTP \(status)：\(String(data: data.prefix(300), encoding: .utf8) ?? "")")
        }
        let (answer, stop) = Self.text(data)
        if stop == "refusal" { throw LLMError(message: "Claude declined this request (refusal)") }
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError(message: "Claude: empty answer (\(stop ?? "no stop reason"))")
        }
        let total = Date().timeIntervalSince(started)
        DebugLog.write(String(format: "claude: %@ answered in %.1f s (%@)", model, total, stop ?? "-"))
        return ChatResult(text: answer, firstToken: nil, total: total, finishReason: stop == "max_tokens" ? "length" : "stop")
    }
}

/// Models tried in order, the first that answers (the backup, then 豆包). One that failed rests a while (`rests`).
@MainActor final class ModelChain: ChatModel {
    let models: [ChatModel]
    private let rests: [PlusRest?]
    private(set) var lastUsed: ChatModel?
    var model: String { (lastUsed ?? models.first)?.model ?? "" }

    init(_ models: [ChatModel], rests: [PlusRest?] = []) {
        self.models = models
        self.rests = models.indices.map { $0 < rests.count ? rests[$0] : nil }
    }

    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult {
        var lastError: Error?
        for (i, m) in models.enumerated() {
            if let rest = rests[i], rest.resting, i < models.count - 1 { continue }
            do {
                let result = try await m.chat(system: system, text: text, image: image, maxTokens: maxTokens, temperature: temperature)
                rests[i]?.succeeded()
                lastUsed = m
                return result
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
                rests[i]?.failed(error.localizedDescription, networkDown: ModelRequestFailure.isNetworkDown(error), quiet: true)
                if i < models.count - 1 {
                    DebugLog.write("planner: \(m.model) failed (\(error.localizedDescription.prefix(120))); \(models[i + 1].model) plans")
                }
            }
        }
        throw lastError ?? LLMError(message: "no model to plan with")
    }
}
