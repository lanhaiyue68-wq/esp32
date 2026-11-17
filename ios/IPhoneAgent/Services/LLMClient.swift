import Foundation

struct ChatResult {
    var text: String
    var firstToken: Double?  // seconds until the first streamed token
    var total: Double
    var finishReason: String?       // "stop", "length" (max tokens hit), …
    var usage: [String: Int] = [:]  // prompt_tokens, completion_tokens, … when the server sends them
    var reasoningChars = 0          // reasoning_content the model wrote (not part of `text`)
    var rawChars = 0                // content before trimming
    var responseSeconds: Double?  // time to HTTP headers, including server queue time
    var retried = false             // the first reply was empty

    /// For the trace and the debug log: why a reply came back empty or cut.
    var diagnostics: JObject {
        var d: JObject = ["finish_reason": .str(finishReason ?? "-"), "reasoning_chars": .int(reasoningChars),
                          "raw_chars": .int(rawChars)]
        if !usage.isEmpty { d["usage"] = .obj(JObject(usage.sorted { $0.key < $1.key }.map { ($0.key, .int($0.value)) })) }
        if retried { d["retried_empty"] = .bool(true) }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reasoningChars > 0 {
            d["note"] = .str("empty content, reasoning only")
        }
        return d
    }
}

/// A chat model the agent can ask (LLMClient, or a fake in tests).
@MainActor protocol ChatModel: AnyObject {
    var model: String { get }
    func chat(system: String, text: String, image: Data?, maxTokens: Int, temperature: Double) async throws -> ChatResult
}

struct LLMError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Client for any OpenAI-compatible chat endpoint (vision models). Port of llm.py, with streaming:
/// Cloudflare cuts requests that send nothing for ~100 s, so replies are streamed (SSE). A server that
/// ignores `stream` and answers with plain JSON works too.
@MainActor final class LLMClient: ChatModel, ModelProgressReporting {
    /// Model requests made since launch; WeChat watch logs how many each stage made.
    static var requests = 0
    var onProgress: ((ModelResponseProgress) -> Void)?
    static let tokenParams = ["max_tokens", "max_completion_tokens"]
    /// D25: the most output a server took (learned from its 400 about the limit), per model; asks stay under it.
    static var tokenCeiling: [String: Int] = [:]
    /// D25: the 30000-token room of a big goal's final answer streams for longer than the 60 s of the usual session.
    private lazy var longSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 240
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// D25: a 400 about the output limit ("max_tokens must be less than or equal to 16384"): the largest number in it under
    /// what was asked (at least 1000), or 8192 when it names none; nil for any other 400.
    static func ceiling(from error: String, asked: Int) -> Int? {
        let e = error.lowercased()
        let aboutTokens = e.contains("max_tokens") || e.contains("max_completion_tokens") || e.contains("max_output_tokens")
            || (e.contains("maximum") && e.contains("token"))
        guard aboutTokens, asked > 1000 else { return nil }
        let numbers = e.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            .filter { $0 >= 1000 && $0 < asked }
        return numbers.max() ?? min(8192, asked - 1)
    }

    let model: String
    let baseURL: URL
    private let apiKey: String
    private let extra: [String: Any]
    private(set) var tokenParam: String
    private var auto: Bool
    private let session: URLSession

    init(baseURL: String, model: String, apiKey: String = "", extra: [String: Any] = [:],
         tokenParam: String = "auto", session: URLSession? = nil) {
        var trimmed = baseURL
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.baseURL = URL(string: trimmed) ?? URL(string: "http://invalid")!
        self.model = model
        self.apiKey = apiKey
        self.extra = extra
        // "auto": send max_tokens; switch for good if the server asks for max_completion_tokens
        if Self.tokenParams.contains(tokenParam) { (self.tokenParam, auto) = (tokenParam, false) }
        else { (self.tokenParam, auto) = ("max_tokens", true) }
        self.session = session ?? {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30  // no byte for this long = hung; the agent retries
            config.timeoutIntervalForResource = 60  // a step answers in seconds with thinking off; a hang retries sooner
            config.urlCache = nil  // a model's answer is never asked twice (iOS's disk-write report of 11-09: CFNetwork's cache)
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: config)
        }()
    }

    func chat(system: String, text: String, image: Data? = nil, maxTokens: Int = 600,
              temperature: Double = 0) async throws -> ChatResult {
        try await chat(system: system, text: text, images: image.map { [$0] } ?? [], maxTokens: maxTokens,
                       temperature: temperature)
    }

    /// Several screenshots in order (a demonstration's keyframes), then the text. An empty reply is asked once more.
    func chat(system: String, text: String, images: [Data], maxTokens: Int = 600,
              temperature: Double = 0) async throws -> ChatResult {
        let first = try await once(system: system, text: text, images: images, maxTokens: maxTokens, temperature: temperature)
        guard first.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return first }
        DebugLog.write("llm: empty reply (finish \(first.finishReason ?? "-"), reasoning \(first.reasoningChars) chars); asking once more")
        var again = try await once(system: system, text: text, images: images, maxTokens: maxTokens, temperature: temperature)
        again.retried = true
        again.total += first.total
        return again
    }

    private func once(system: String, text: String, images: [Data], maxTokens: Int,
                      temperature: Double) async throws -> ChatResult {
        onProgress?(.waiting)
        var content: [[String: Any]] = images.map {
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + $0.base64EncodedString()]]
        }
        content.append(["type": "text", "text": text])
        var body: [String: Any] = ["model": model, "temperature": temperature]
        extra.forEach { body[$0.key] = $0.value }
        body["messages"] = [["role": "system", "content": system], ["role": "user", "content": content]]
        body["stream"] = true

        let started = now()
        let kb = images.reduce(0) { $0 + $1.count } / 1024
        Self.requests += 1
        DebugLog.write("llm → \(model): \(images.count) image(s) \(kb) KB, \(text.count) chars")
        var status = 0, result: ChatResult?, errorText = ""
        do {
            // D101: the system prompt from Ark's prefix cache when it can be; nil: the old way.
            if let cached = try await prefixReply(system: system, text: text, images: images, maxTokens: maxTokens,
                                                  temperature: temperature, started: started) {
                (status, result) = (200, cached)
            } else {
                (status, result, errorText) = try await post(body, maxTokens: maxTokens, started: started)
            }
            if status == 400 && auto && errorText.contains("max_completion_tokens") {
                (tokenParam, auto) = ("max_completion_tokens", false)
                (status, result, errorText) = try await post(body, maxTokens: maxTokens, started: started)
            }
            if status == 400, let ceiling = Self.ceiling(from: errorText, asked: min(maxTokens, Self.tokenCeiling[model] ?? maxTokens)) {
                Self.tokenCeiling[model] = ceiling
                DebugLog.write("llm: \(model) takes at most \(ceiling) output tokens; asking again with that")
                (status, result, errorText) = try await post(body, maxTokens: maxTokens, started: started)
            }
        } catch {
            DebugLog.write(String(format: "llm ✗ %@ after %.1f s: %@", model, now() - started, error.localizedDescription))
            throw error
        }
        guard (200..<300).contains(status), var result else {
            DebugLog.write(String(format: "llm ✗ HTTP %d after %.1f s: %@", status, now() - started, String(errorText.prefix(200))))
            throw LLMError(message: "LLM HTTP \(status): \(errorText.prefix(300))")
        }
        result.total = now() - started
        DebugLog.write(String(format: "llm ← HTTP %d, first token %@, total %.1f s, %d chars", status,
                              result.firstToken.map { String(format: "%.1f s", $0) } ?? "-", result.total, result.text.count)
                       + " " + PyJSON.dumps(.obj(result.diagnostics)))
        if result.reasoningChars > 2000 {  // the usual reason a step takes 30+ s
            DebugLog.write("llm: \(model) reasoned \(result.reasoningChars) chars before answering; for speed turn "
                           + "thinking off in Extra body JSON, e.g. {\"enable_thinking\": false}")
        }
        return result
    }

    // MARK: D101, Ark's prefix cache

    /// D101, user 11-17 ("能在保证不会降低出错和速度的情况下省一点"): Doubao bills every input token, and every step sends
    /// the same system prompt (the rules of all apps, ~9200 of ~20000 tokens a step). With Cache turned on for the model
    /// in the Ark console, a prefix cache bills those at a fifth (0.00016 against 0.0008 元/千 tokens). ark_cache_probe on
    /// 11-17: 9211 of 9242 tokens from the cache, no reasoning, 1.8–2.0 s against 1.9–2.4 s; with a screenshot, streamed
    /// and temperature 0, 9225 of 10530 in 2.6 s, as the old way. The model reads the same words, thinking off and the
    /// same temperature as before. Ark refuses `store: false` with caching, so a step is kept 10 minutes only (kept
    /// tokens are billed by the hour: ~0.00006 元 a step against ~0.006 saved). chat/completions alone never read a
    /// cache (probe: 0 of 10530 twice, also after a Responses prefix of the same words). The first step on a system
    /// prompt goes the old way while its cache is made beside it, so no step waits for the cache. A refusal, a reply
    /// that reasoned, or two misses in a row turn it off for this client; a lost network is a lost network either way.
    static var prefixCaching = true
    private var prefixes: [Int: (id: String, until: Double)] = [:]
    private var making: Set<Int> = []
    private(set) var cacheOff: String?
    private var cacheMisses = 0

    static func cachesPrefix(baseURL: URL, model: String, system: String) -> Bool {
        prefixCaching && (baseURL.host ?? "").hasSuffix("volces.com") && model.lowercased().hasPrefix("doubao") && system.count >= 2000
    }

    private func prefixReply(system: String, text: String, images: [Data], maxTokens: Int, temperature: Double,
                             started: Double) async throws -> ChatResult? {
        guard cacheOff == nil, Self.cachesPrefix(baseURL: baseURL, model: model, system: system) else { return nil }
        let key = system.hashValue
        guard let prefix = prefixes[key], prefix.until > now() else {
            makePrefix(system)  // beside this step, which goes the old way
            return nil
        }
        do {
            let (status, reply, error) = try await respond(on: prefix.id, text: text, images: images, maxTokens: maxTokens,
                                                           temperature: temperature, started: started)
            if let reply { return checked(reply, system: system) }
            // A prefix that ran out or is unknown is made again; anything else turns the cache off.
            if status == 404 || error.contains("previous_response") {
                prefixes[key] = nil
                makePrefix(system)
            } else {
                turnOff("HTTP \(status): \(error.prefix(160))")
            }
            return nil
        } catch let e where e is CancellationError || Task.isCancelled || ModelRequestFailure.isNetworkDown(e) {
            throw e
        } catch {
            turnOff(error.localizedDescription)
            return nil
        }
    }

    private func turnOff(_ why: String) {
        cacheOff = why
        DebugLog.write("llm: prefix cache off (\(why)); the old way from now on")
    }

    private func checked(_ reply: ChatResult, system: String) -> ChatResult {
        let cached = reply.usage["cached_tokens"] ?? 0, input = reply.usage["prompt_tokens"] ?? 0
        if (reply.usage["reasoning_tokens"] ?? 0) > 0 || reply.reasoningChars > 0 {
            turnOff("the reply reasoned")
        } else if cached == 0 {
            cacheMisses += 1
            prefixes[system.hashValue] = nil  // made again next time
            if cacheMisses >= 2 { turnOff("nothing came from the cache twice in a row") }
        } else {
            cacheMisses = 0
        }
        DebugLog.write("llm: prefix cache: \(cached) of \(input) input tokens")
        return reply
    }

    /// Makes the cache of this system prompt in the background (it lives an hour: kept tokens are billed by the hour).
    /// A lost network only waits for the next step; a refusal turns the cache off.
    private func makePrefix(_ system: String) {
        let key = system.hashValue
        guard !making.contains(key) else { return }
        making.insert(key)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.making.remove(key) }
            do {
                let id = try await self.prefixID(system)
                self.prefixes[key] = (id, now() + 3600 - 120)
            } catch let e where ModelRequestFailure.isNetworkDown(e) || e is CancellationError {
                DebugLog.write("llm: prefix cache not made yet (\(e.localizedDescription)); next step tries again")
            } catch {
                self.turnOff(error.localizedDescription)
            }
        }
    }

    /// POST responses for the cache of this system prompt: its id.
    private func prefixID(_ system: String) async throws -> String {
        var body: [String: Any] = ["model": model, "caching": ["type": "enabled", "prefix": true] as [String: Any],
                                   "expire_at": Int(Date().timeIntervalSince1970) + 3600,
                                   "input": [["role": "system", "content": system]]]
        if let thinking = extra["thinking"] { body["thinking"] = thinking }
        var request = URLRequest(url: baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard status == 200, let id = json?["id"] as? String else {
            throw LLMError(message: "prefix cache not made: HTTP \(status) \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        DebugLog.write("llm: prefix cache made for a system prompt of \(system.count) characters")
        return id
    }

    /// One step on the cached prefix (Responses API), streamed: (status, the reply or nil, error text).
    private func respond(on prefix: String, text: String, images: [Data], maxTokens: Int, temperature: Double,
                         started: Double) async throws -> (Int, ChatResult?, String) {
        var content: [[String: Any]] = images.map {
            ["type": "input_image", "image_url": "data:image/jpeg;base64," + $0.base64EncodedString()]
        }
        content.append(["type": "input_text", "text": text])
        let asked = min(maxTokens, Self.tokenCeiling[model] ?? maxTokens)
        var body: [String: Any] = ["model": model, "caching": ["type": "enabled"], "previous_response_id": prefix,
                                   "expire_at": Int(Date().timeIntervalSince1970) + 600,
                                   "temperature": temperature, "max_output_tokens": asked, "stream": true,
                                   "input": [["role": "user", "content": content] as [String: Any]]]
        if let thinking = extra["thinking"] { body["thinking"] = thinking }
        var request = URLRequest(url: baseURL.appendingPathComponent("responses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await (asked > 4000 ? longSession : session).bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        DebugLog.write(String(format: "llm   headers: HTTP %d %@ after %.1f s (prefix cache)", status, type, now() - started))
        guard (200..<300).contains(status) else {
            var raw = Data()
            for try await b in bytes { raw.append(b) }
            return (status, nil, String(decoding: raw, as: UTF8.self))
        }
        var result = ChatResult(text: "", firstToken: nil, total: 0)
        result.responseSeconds = now() - started
        var reported = false, ended = false
        var length = 0, checkedAt = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let event = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any],
                  let kind = event["type"] as? String else { continue }
            switch kind {
            case "response.output_text.delta":
                guard let piece = event["delta"] as? String, !piece.isEmpty else { continue }
                if !reported { reported = true; onProgress?(.receiving) }
                if result.firstToken == nil { result.firstToken = now() - started }
                result.text += piece
                length += piece.count
                if length - checkedAt >= 1500 {
                    checkedAt = length
                    if let kept = Self.goingRound(result.text) {
                        DebugLog.write("llm: the reply goes round and round (\(length) characters); cut there")
                        result.text = kept
                        result.finishReason = "loop"
                        ended = true
                    }
                }
            case "response.completed", "response.incomplete":
                Self.noteResponse(event["response"] as? [String: Any], into: &result)
                result.finishReason = kind == "response.completed" ? "stop" : "length"
                ended = true
            case "response.failed", "error":
                let response = event["response"] as? [String: Any]
                let detail = (response?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any])
                return (500, nil, (detail?["message"] as? String) ?? kind)
            default:
                if kind.hasPrefix("response.reasoning"), let piece = event["delta"] as? String { result.reasoningChars += piece.count }
            }
            if ended { break }
        }
        result.rawChars = result.text.count
        return (status, result, "")
    }

    /// The usage of a Responses reply, in the names the rest of the app reads (prompt_tokens, completion_tokens), with
    /// cached_tokens and reasoning_tokens.
    static func noteResponse(_ response: [String: Any]?, into result: inout ChatResult) {
        guard let usage = response?["usage"] as? [String: Any] else { return }
        var u: [String: Int] = [:]
        u["prompt_tokens"] = usage["input_tokens"] as? Int
        u["completion_tokens"] = usage["output_tokens"] as? Int
        u["total_tokens"] = usage["total_tokens"] as? Int
        u["cached_tokens"] = (usage["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int
        u["reasoning_tokens"] = (usage["output_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? Int
        result.usage = u
    }

    /// The first model id from GET {base}/models.
    static func firstModel(baseURL: String, apiKey: String) async throws -> String {
        guard let id = try await models(baseURL: baseURL, apiKey: apiKey).first else {
            throw LLMError(message: "the endpoint lists no models; type a model id in Settings › Model")
        }
        return id
    }

    /// The model ids from GET {base}/models (OpenAI list format: {"data": [{"id": ...}]}), in the endpoint's order.
    static func models(baseURL: String, apiKey: String) async throws -> [String] {
        var trimmed = baseURL
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let base = URL(string: trimmed) else { throw LLMError(message: "invalid base URL") }
        var request = URLRequest(url: base.appendingPathComponent("models"), timeoutInterval: 20)
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw LLMError(message: "GET /models: HTTP \(status) \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let list = (json?["data"] as? [[String: Any]]) ?? (json?["models"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return list.compactMap { ($0["id"] ?? $0["name"]) as? String }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func post(_ body: [String: Any], maxTokens: Int, started: Double) async throws
        -> (Int, ChatResult?, String) {
        var body = body
        let asked = min(maxTokens, Self.tokenCeiling[model] ?? maxTokens)
        body[tokenParam] = asked
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await (asked > 4000 ? longSession : session).bytes(for: request)
        let responseSeconds = now() - started
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        DebugLog.write(String(format: "llm   headers: HTTP %d %@ after %.1f s", status, type, now() - started))
        guard (200..<300).contains(status) else {
            var raw = Data()
            for try await b in bytes { raw.append(b) }
            return (status, nil, String(decoding: raw, as: UTF8.self))
        }
        if !type.contains("text/event-stream") {  // a plain JSON answer
            var raw = Data()
            for try await b in bytes { raw.append(b) }
            var result = try Self.message(raw)
            result.responseSeconds = responseSeconds
            if !result.text.isEmpty || result.reasoningChars > 0 { onProgress?(.receiving) }
            return (status, result, "")
        }
        var result = ChatResult(text: "", firstToken: nil, total: 0)
        result.responseSeconds = responseSeconds
        var reportedReceiving = false
        var length = 0, checkedAt = 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let json = (try? JSONSerialization.jsonObject(with: Data(payload.utf8))) as? [String: Any] else { continue }
            try Self.checkError(json)
            let choice = (json["choices"] as? [[String: Any]])?.first
            let delta = choice?["delta"] as? [String: Any]
            Self.note(json, choice, into: &result)
            let reasoning = Self.reasoning(delta)
            if !reportedReceiving, !reasoning.isEmpty || !(delta?["content"] as? String ?? "").isEmpty {
                reportedReceiving = true
                onProgress?(.receiving)
            }
            result.reasoningChars += reasoning.count
            guard let piece = delta?["content"] as? String, !piece.isEmpty else { continue }
            if result.firstToken == nil { result.firstToken = now() - started }
            result.text += piece
            length += piece.count
            if length - checkedAt >= 1500 {
                checkedAt = length
                if let kept = Self.goingRound(result.text) {
                    DebugLog.write("llm: the reply goes round and round (\(length) characters); cut there")
                    result.text = kept
                    result.finishReason = "loop"
                    break
                }
            }
        }
        result.rawChars = result.text.count
        return (status, result, "")
    }

    /// D43, y1 on 136: one of Doubao's replies ran on for 169 s and 107035 characters, up to the 30000-token ceiling of a
    /// big goal (D25), and the step waited for all of it. A reply of 3000+ characters whose last 200 already came twice
    /// before (or that is one or two characters over and over) is going round: what came before the repeats is kept.
    static func goingRound(_ text: String) -> String? {
        guard text.count >= 3000 else { return nil }
        let tail = String(text.suffix(200))
        let body = text.startIndex..<text.index(text.endIndex, offsetBy: -200)
        if Set(tail).count <= 3 {
            let mark = String(tail.prefix(20))
            return text.range(of: mark).map { String(text[..<$0.lowerBound]) } ?? String(text[body])
        }
        guard let first = text.range(of: tail, range: body),
              text.range(of: tail, range: first.upperBound..<body.upperBound) != nil else { return nil }
        return String(text[..<first.upperBound])
    }

    /// choices[0].message of a non-streamed reply.
    static func message(_ raw: Data) throws -> ChatResult {
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        if let json { try Self.checkError(json) }
        let choice = (json?["choices"] as? [[String: Any]])?.first
        guard let json, let msg = choice?["message"] as? [String: Any] else {
            throw LLMError(message: "bad LLM reply: \(String(decoding: raw.prefix(200), as: UTF8.self))")
        }
        var result = ChatResult(text: msg["content"] as? String ?? "", firstToken: nil, total: 0)
        note(json, choice, into: &result)
        result.reasoningChars = reasoning(msg).count
        result.rawChars = result.text.count
        return result
    }

    /// Providers can report errors inside an HTTP 200 stream or JSON response.
    private static func checkError(_ json: [String: Any]) throws {
        guard let error = json["error"] else { return }
        let message = (error as? [String: Any])?["message"] as? String ?? (error as? String) ?? "Provider error"
        throw LLMError(message: String(message.prefix(300)))
    }

    /// finish_reason and usage, from whichever event carries them.
    private static func note(_ json: [String: Any], _ choice: [String: Any]?, into result: inout ChatResult) {
        if let reason = choice?["finish_reason"] as? String { result.finishReason = reason }
        if let usage = json["usage"] as? [String: Any] {
            result.usage = usage.compactMapValues { $0 as? Int }
            // D101: what came from a cache on the server (prompt_tokens_details), kept so the trace shows it.
            if let cached = (usage["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int {
                result.usage["cached_tokens"] = cached
            }
        }
    }

    /// Reasoning text (vLLM/DeepSeek `reasoning_content`, others `reasoning`).
    private static func reasoning(_ part: [String: Any]?) -> String {
        part?["reasoning_content"] as? String ?? part?["reasoning"] as? String ?? ""
    }
}
