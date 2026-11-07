import Foundation

/// Phase A test (specs/004): ChatGPT Plus quota from inside the app, signed in and called the way the official Codex
/// CLI does it (openai/codex rust-v0.167.0: codex-rs/login/src/device_code_auth.rs, login/src/server.rs,
/// codex-api/src/common.rs, models-manager/models.json). This is not an interface OpenAI offers to other apps: it
/// may stop working at any time, and the user accepted the account risk (2026-11-08).
enum ChatGPTPlus {
    static let issuer = "https://auth.openai.com"
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"   // login/src/auth/mod.rs CLIENT_ID
    static let codexBase = "https://chatgpt.com/backend-api/codex"
    static let clientVersion = "0.167.0"
    static let fallbackModel = "gpt-5.6-sol"
    private static let keychainAccount = "chatgpt-plus-tokens"

    struct DeviceCode: Equatable {
        let verificationURL: URL
        let userCode: String
        let deviceAuthID: String
        let interval: Double
    }

    struct Tokens: Codable, Equatable {
        var idToken: String
        var accessToken: String
        var refreshToken: String
        var accountID: String?
    }

    struct Answer {
        let text: String
        let model: String
        let firstTokenMs: Int?
        let totalMs: Int
        let quota: [String: String]   // x-codex-* response headers (usage and limits)
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: - stored sign-in

    static var saved: Tokens? {
        Keychain.get(keychainAccount).flatMap { try? JSONDecoder().decode(Tokens.self, from: Data($0.utf8)) }
    }

    static func save(_ tokens: Tokens?) {
        let text = tokens.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        Keychain.set(text, for: keychainAccount)
    }

    // MARK: - device-code sign-in

    static func requestDeviceCode() async throws -> DeviceCode {
        let data = try await post("\(issuer)/api/accounts/deviceauth/usercode", json: ["client_id": clientID])
        guard let parsed = parseUserCode(data), let url = URL(string: "\(issuer)/codex/device") else {
            throw Failure(message: "登入代碼的回應看不懂：\(String(data: data.prefix(300), encoding: .utf8) ?? "")")
        }
        return DeviceCode(verificationURL: url, userCode: parsed.code, deviceAuthID: parsed.id, interval: parsed.interval)
    }

    /// {"device_auth_id":…, "user_code"|"usercode":…, "interval": "5"} (the interval arrives as text).
    static func parseUserCode(_ data: Data) -> (id: String, code: String, interval: Double)? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = o["device_auth_id"] as? String,
              let code = (o["user_code"] ?? o["usercode"]) as? String else { return nil }
        let interval = (o["interval"] as? String).flatMap(Double.init) ?? (o["interval"] as? Double) ?? 5
        return (id, code, max(1, interval))
    }

    /// Polls until the user has entered the code on the page (403/404 while waiting), then exchanges it for tokens.
    static func waitForSignIn(_ code: DeviceCode, timeout: Double = 900) async throws -> Tokens {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let (data, status) = try await send("\(issuer)/api/accounts/deviceauth/token",
                                                json: ["device_auth_id": code.deviceAuthID, "user_code": code.userCode])
            if status == 200 {
                guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let authCode = o["authorization_code"] as? String, let verifier = o["code_verifier"] as? String
                else { throw Failure(message: "登入完成的回應看不懂") }
                return try await exchange(code: authCode, verifier: verifier)
            }
            guard status == 403 || status == 404 else {
                throw Failure(message: "登入失敗 HTTP \(status)：\(String(data: data.prefix(300), encoding: .utf8) ?? "")")
            }
            try await Task.sleep(nanoseconds: UInt64(code.interval * 1e9))
        }
        throw Failure(message: "15 分鐘內沒有完成登入")
    }

    static func exchange(code: String, verifier: String) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([("grant_type", "authorization_code"), ("code", code),
                                     ("redirect_uri", "\(issuer)/deviceauth/callback"), ("client_id", clientID),
                                     ("code_verifier", verifier)])
        return try await tokens(from: request, keeping: nil)
    }

    static func refresh(_ old: Tokens) async throws -> Tokens {
        var request = URLRequest(url: URL(string: "\(issuer)/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": old.refreshToken,
            "scope": "openid profile email"])
        return try await tokens(from: request, keeping: old)
    }

    private static func tokens(from request: URLRequest, keeping old: Tokens?) async throws -> Tokens {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let access = o["access_token"] as? String else {
            throw Failure(message: "換取登入憑證失敗 HTTP \(status)：\(String(data: data.prefix(300), encoding: .utf8) ?? "")")
        }
        let id = (o["id_token"] as? String) ?? old?.idToken ?? ""
        let tokens = Tokens(idToken: id, accessToken: access,
                            refreshToken: (o["refresh_token"] as? String) ?? old?.refreshToken ?? "",
                            accountID: accountID(idToken: id) ?? old?.accountID)
        save(tokens)
        return tokens
    }

    /// The ChatGPT account id in the id token: {"https://api.openai.com/auth": {"chatgpt_account_id": …}}.
    static func accountID(idToken: String) -> String? {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let auth = claims["https://api.openai.com/auth"] as? [String: Any] else { return nil }
        return auth["chatgpt_account_id"] as? String
    }

    static func formBody(_ pairs: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(pairs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }

    // MARK: - the Codex backend

    /// The models this account may use, as the official client lists them (visible ones first).
    static func models(_ tokens: Tokens) async throws -> [String] {
        var request = authorized(URLRequest(url: URL(string: "\(codexBase)/models?client_version=\(clientVersion)")!), tokens)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Failure(message: "讀取模型清單失敗 HTTP \(status)：\(String(data: data.prefix(300), encoding: .utf8) ?? "")")
        }
        return modelSlugs(data)
    }

    /// {"models":[{"slug":…, "visibility":"list"|"hide"}]} → the listed slugs, then the hidden ones.
    static func modelSlugs(_ data: Data) -> [String] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let items = o["models"] as? [[String: Any]] else { return [] }
        let listed = items.filter { ($0["visibility"] as? String) != "hide" }.compactMap { $0["slug"] as? String }
        let hidden = items.filter { ($0["visibility"] as? String) == "hide" }.compactMap { $0["slug"] as? String }
        return listed + hidden
    }

    /// One question with an optional screenshot, streamed; refreshes the sign-in once when it has expired.
    static func ask(_ tokens: Tokens, model: String, prompt: String, image: Data?) async throws -> (Answer, Tokens) {
        do {
            return (try await askOnce(tokens, model: model, prompt: prompt, image: image), tokens)
        } catch let failure as Failure where failure.message.hasPrefix("HTTP 401") {
            let fresh = try await refresh(tokens)
            return (try await askOnce(fresh, model: model, prompt: prompt, image: image), fresh)
        }
    }

    private static func askOnce(_ tokens: Tokens, model: String, prompt: String, image: Data?) async throws -> Answer {
        var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
        if let image { content.append(["type": "input_image", "image_url": "data:image/jpeg;base64,\(image.base64EncodedString())"]) }
        let body: [String: Any] = [
            "model": model, "stream": true,
            "input": [
                ["type": "message", "role": "developer",
                 "content": [["type": "input_text", "text": "You are Lan Agent, an assistant that operates an iPhone. Answer briefly."]]],
                ["type": "message", "role": "user", "content": content],
            ],
            "tool_choice": "auto", "parallel_tool_calls": false, "store": false, "include": [String](),
        ]
        var request = authorized(URLRequest(url: URL(string: "\(codexBase)/responses")!), tokens)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 90

        let started = Date()
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard status == 200 else {
            var raw = Data()
            for try await byte in bytes { raw.append(byte); if raw.count > 1500 { break } }
            throw Failure(message: "HTTP \(status)：\(String(data: raw, encoding: .utf8) ?? "")")
        }
        var quota: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let k = key as? String, k.lowercased().hasPrefix("x-codex") { quota[k.lowercased()] = "\(value)" }
        }
        var stream = SSE()
        var firstTokenMs: Int?
        for try await line in bytes.lines {
            let before = stream.text.count
            stream.feed(line)
            if firstTokenMs == nil, stream.text.count > before { firstTokenMs = Int(Date().timeIntervalSince(started) * 1000) }
            if stream.done { break }
        }
        if let error = stream.error { throw Failure(message: "模型回報錯誤：\(error)") }
        return Answer(text: stream.text, model: model, firstTokenMs: firstTokenMs,
                      totalMs: Int(Date().timeIntervalSince(started) * 1000), quota: quota)
    }

    /// The Responses stream: text deltas until completed, or an error.
    struct SSE {
        private(set) var text = ""
        private(set) var done = false
        private(set) var error: String?

        mutating func feed(_ line: String) {
            guard line.hasPrefix("data:") else { return }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]" else { done = true; return }
            guard let data = payload.data(using: .utf8),
                  let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = event["type"] as? String else { return }
            switch type {
            case "response.output_text.delta":
                text += (event["delta"] as? String) ?? ""
            case "response.completed":
                done = true
            case "response.failed", "error":
                let response = event["response"] as? [String: Any]
                let detail = (response?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any])
                error = (detail?["message"] as? String) ?? (event["message"] as? String) ?? type
                done = true
            default: break
            }
        }
    }

    private static func authorized(_ base: URLRequest, _ tokens: Tokens) -> URLRequest {
        var request = base
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        if let account = tokens.accountID { request.setValue(account, forHTTPHeaderField: "chatgpt-account-id") }
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        request.setValue("codex_cli_rs/\(clientVersion) (iOS; Lan Agent)", forHTTPHeaderField: "User-Agent")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "session_id")
        return request
    }

    private static func post(_ url: String, json: [String: String]) async throws -> Data {
        let (data, status) = try await send(url, json: json)
        guard status == 200 else {
            throw Failure(message: "HTTP \(status)：\(String(data: data.prefix(300), encoding: .utf8) ?? "")")
        }
        return data
    }

    private static func send(_ url: String, json: [String: String]) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
