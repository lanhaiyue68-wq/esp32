import Foundation

/// Tasks from the cloud. Customer spec of 11-10 (个人 AI 总调度与多设备助理系统, §6.2, §9, §4.4): the phone registers as
/// a device, says what it can do now, takes a task, runs it with the agent it already has, and reports back. The
/// protocol is in docs/cloud-bridge-protocol.md; tools/cloud-mock/mock_cloud.py serves it for testing. Off until the user
/// turns it on (§4.4 kill switch); the token lives in the Keychain, never in code (§9.4).
@MainActor final class CloudBridge: ObservableObject {
    struct CloudTask: Equatable {
        let id: String
        let instruction: String
        let approval: Bool     // a message waits for approval before it is sent (§0.6, §13.3)
        let screenshot: Bool   // the last screen goes with the result (§6.2: only when asked)
    }
    struct Outcome: Equatable {
        var status: String     // succeeded | failed | cancelled
        var answer: String
        var error: String?
        var steps: Int
    }

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "cloud.enabled"); state = enabled ? "正在连接…" : "已关闭" } }
    @Published var server: String { didSet { defaults.set(server.trimmingCharacters(in: .whitespaces), forKey: "cloud.server") } }
    @Published var device: String { didSet { defaults.set(device, forKey: "cloud.device") } }
    @Published var token: String { didSet { Keychain.set(token, for: "cloud-device-token"); DebugLog.redact([token]) } }
    @Published private(set) var state = "已关闭"
    @Published private(set) var current: CloudTask?

    /// The app: what the phone can do now, starting, watching and stopping a run, its last screen.
    var capabilities: () -> [String: String] = { [:] }
    var start: (CloudTask, @escaping (String) async -> Bool) -> Void = { _, _ in }
    var running: () -> Bool = { false }
    var outcome: (CloudTask) -> Outcome = { _ in Outcome(status: "failed", answer: "", error: "no run", steps: 0) }
    var stop: () async -> Void = {}
    var lastScreen: () -> Data? = { nil }
    /// The network; tests pass their own. (method, path, body) → (HTTP status, body)
    var send: (String, String, [String: Any]?) async throws -> (Int, Data)

    private let defaults: UserDefaults
    private var finished: [String: [String: Any]] = [:]   // task id → its last event, so a task is never run twice
    private var lastProgress = 0.0
    private var startedAt = 0.0
    /// A run takes a moment to start: not over before this.
    var startGrace = 10.0
    static let heartbeat = 5.0
    static let approvalWait = 600.0
    static let keep = 100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "cloud.enabled")
        server = defaults.string(forKey: "cloud.server") ?? ""
        device = defaults.string(forKey: "cloud.device") ?? "home_iphone_01"
        token = Keychain.get("cloud-device-token") ?? ""
        if let data = defaults.data(forKey: "cloud.finished"),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] { finished = saved }
        send = { _, _, _ in throw URLError(.badURL) }
        state = enabled ? "正在连接…" : "已关闭"
        send = { [weak self] method, path, body in
            guard let self else { throw URLError(.cancelled) }
            return try await Self.http(base: self.server, token: self.token, method: method, path: path, body: body)
        }
    }

    var configured: Bool { !server.isEmpty && !device.isEmpty && !token.isEmpty }

    /// For as long as the app lives.
    func loop() async {
        while !Task.isCancelled {
            await tick()
            try? await Task.sleep(nanoseconds: UInt64(Self.heartbeat * 1e9))
        }
    }

    /// One heartbeat: say what the phone can do, take a task or a cancel, report how the current one goes.
    func tick() async {
        guard enabled else {
            if current != nil { await stop(); await finish(cancelledBy: "turned off on the phone") }
            return
        }
        guard configured else { state = "请填写服务器、设备编号和密钥"; return }
        var beat: [String: Any] = ["device_id": device, "capabilities": capabilities(), "timestamp": Self.stamp(),
                                   "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"]
        if let current { beat["running_task_id"] = current.id }
        let reply: [String: Any]
        do {
            let (code, data) = try await send("POST", "/api/v1/devices/\(Self.escaped(device))/heartbeat", beat)
            guard (200..<300).contains(code) else { state = "服务器回复 HTTP \(code)"; return }
            reply = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            state = current == nil ? "已连接，等待任务" : "执行中：\(current!.instruction.prefix(30))"
        } catch {
            state = "连不上服务器：\(error.localizedDescription)"
            return
        }
        if let current, (reply["cancel"] as? [String])?.contains(current.id) == true {
            await stop()
            await finish(cancelledBy: "cancelled from the cloud")
            return
        }
        if current != nil {
            await follow()
        } else if let task = Self.task(from: reply["task"]) {
            await take(task)
        }
    }

    /// Build 116 over the cloud 11-10: after about 34 minutes of tasks back to back, on the charger, the phone reached
    /// "critical": iOS held the app 14 times for 5-16 s, sharing broke once, and a 93-second task took 226. A task that
    /// comes then is put off (retry_pending, device_hot) until the phone is cooler, at most coolingLimit for each task.
    var hot: () -> Bool = { ProcessInfo.processInfo.thermalState == .critical }
    /// Device numbers blacked out of the picture before it leaves the phone (ShotPrivacy); as is in tests.
    var mask: (Data) async -> Data = { $0 }
    private var hotSince: [String: Double] = [:]
    static let coolingLimit = 300.0

    private func take(_ task: CloudTask) async {
        if let last = finished[task.id] {  // §9.4 idempotency: done before, say so again
            await report(task.id, last)
            return
        }
        if hot() {
            let first = hotSince[task.id] == nil
            let since = hotSince[task.id] ?? now()
            hotSince[task.id] = since
            if now() - since < Self.coolingLimit {
                if first { DebugLog.write("cloud: the phone is hot (critical); task \(task.id) waits to cool down") }
                await report(task.id, ["status": "retry_pending", "error_code": "device_hot", "detail": "the phone is too hot; it takes the task once it is cooler"])
                return
            }
            DebugLog.write("cloud: still hot after \(Int(Self.coolingLimit)) s; task \(task.id) runs all the same")
        }
        hotSince[task.id] = nil
        let missing = capabilities().filter { ["screen_capture", "hid_board", "pointer"].contains($0.key) && $0.value != "available" }
        if running() || !missing.isEmpty {
            let why = running() ? "busy" : "unavailable: " + missing.keys.sorted().joined(separator: ", ")
            await report(task.id, ["status": "retry_pending", "error_code": running() ? "device_busy" : "capability_unavailable", "detail": why])
            return
        }
        await report(task.id, ["status": "accepted"])
        current = task
        startedAt = now()
        lastProgress = now()
        start(task, { [weak self] text in await self?.approve(text, for: task.id) ?? false })
        DebugLog.write("cloud: task \(task.id) started: \(task.instruction.prefix(80))")
        await report(task.id, ["status": "running"])
    }

    /// While it runs: progress now and then; when it is over, the outcome.
    private func follow() async {
        guard let task = current else { return }
        if running() || now() - startedAt < startGrace {
            if now() - lastProgress >= 15 {
                lastProgress = now()
                await report(task.id, ["status": "running", "progress": ["steps": outcome(task).steps]])
            }
            return
        }
        let result = outcome(task)
        var event: [String: Any] = ["status": result.status, "result": ["answer": result.answer, "steps": result.steps]]
        if let error = result.error { event["error_code"] = error }
        if task.screenshot, let jpeg = lastScreen() { event["screenshot_jpeg_base64"] = await mask(jpeg).base64EncodedString() }
        await finish(task, event)
    }

    private func finish(cancelledBy why: String) async {
        guard let task = current else { return }
        await finish(task, ["status": "cancelled", "error_code": why])
    }

    private func finish(_ task: CloudTask, _ event: [String: Any]) async {
        current = nil
        var kept = event
        kept.removeValue(forKey: "screenshot_jpeg_base64")
        kept["timestamp"] = Self.stamp()
        finished[task.id] = kept
        if finished.count > Self.keep, let oldest = finished.min(by: { ($0.value["timestamp"] as? String ?? "") < ($1.value["timestamp"] as? String ?? "") })?.key {
            finished.removeValue(forKey: oldest)
        }
        if let data = try? JSONSerialization.data(withJSONObject: finished) { defaults.set(data, forKey: "cloud.finished") }
        DebugLog.write("cloud: task \(task.id) \(event["status"] ?? "?")")
        await report(task.id, event)
    }

    /// Before a message goes: say what would be sent, then wait for the cloud's answer (rejected after 10 minutes).
    /// Where the message would go (AgentLoop.approvalPlace), sent with the approval request.
    var destination: (() -> String?)?

    func approve(_ text: String, for id: String) async -> Bool {
        guard current?.approval ?? true else { return true }
        var request: [String: Any] = ["action": "send_message", "text": text]
        if let place = destination?(), !place.isEmpty { request["destination"] = place }  // the chat title on screen
        return await waitApproval(id, request)
    }

    /// User 11-15: an app the task needs is not on the phone: the owner is asked whether to install it, always (whether
    /// or not the task's messages wait for approval). No answer in 10 minutes is a no.
    func askInstall(_ app: String, for id: String) async -> Bool {
        await waitApproval(id, ["action": "install_app", "app": app, "text": "手机上没有“\(app)”，要下载安装吗？"])
    }

    /// D28, user 11-15: before 发布 in a video or post app the owner is asked, always. No answer in 10 minutes is a no.
    func askPublish(_ question: String, for id: String) async -> Bool {
        await waitApproval(id, ["action": "publish_post", "text": question])
    }

    private func waitApproval(_ id: String, _ request: [String: Any]) async -> Bool {
        await report(id, ["status": "waiting_approval", "approval_request": request])
        let until = now() + Self.approvalWait
        while now() < until, !Task.isCancelled {
            if let reply = try? await send("GET", "/api/v1/tasks/\(Self.escaped(id))", nil), (200..<300).contains(reply.0),
               let task = try? JSONSerialization.jsonObject(with: reply.1) as? [String: Any] {
                switch task["approval"] as? String {
                case "approved": await report(id, ["status": "running", "approval": "approved"]); return true
                case "rejected": return false
                default: if task["status"] as? String == "cancelled" { return false }
                }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        return false
    }

    private func report(_ id: String, _ event: [String: Any]) async {
        var body = event
        body["task_id"] = id
        body["device_id"] = device
        body["timestamp"] = Self.stamp()
        do {
            let (code, _) = try await send("POST", "/api/v1/tasks/\(Self.escaped(id))/events", body)
            if !(200..<300).contains(code) { DebugLog.write("cloud: event \(event["status"] ?? "?") for \(id): HTTP \(code)") }
        } catch {
            DebugLog.write("cloud: event \(event["status"] ?? "?") for \(id) not sent: \(error.localizedDescription)")
        }
    }

    static func task(from value: Any?) -> CloudTask? {
        guard let t = value as? [String: Any], let id = t["task_id"] as? String, !id.isEmpty else { return nil }
        let input = t["input"] as? [String: Any] ?? [:]
        guard let text = (input["instruction"] as? String ?? t["instruction"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return CloudTask(id: id, instruction: text,
                         approval: t["requires_approval_before_external_action"] as? Bool ?? true,
                         screenshot: input["want_screenshot"] as? Bool ?? false)
    }

    /// The run's end, for the cloud: the agent's last record.
    static func outcome(of steps: [JObject], rejected: Bool = false) -> Outcome {
        let moves = steps.filter { $0["action"]?.str != "plan" }.count
        guard let last = steps.last else { return Outcome(status: "failed", answer: said(false, "没有做任何一步"), error: "no_steps", steps: 0) }
        switch last["action"]?.str {
        case "done":
            let answer = last["answer"]?.str ?? ""
            if last["approval"]?.str == "rejected" {
                return Outcome(status: "cancelled", answer: said(false, answer.isEmpty ? "消息没有获批准，没有发送" : answer),
                               error: "not_approved", steps: moves)
            }
            return Outcome(status: "succeeded", answer: said(true, answer.isEmpty ? "已完成" : answer), error: nil, steps: moves)
        case "stopped": return Outcome(status: "cancelled", answer: said(false, "任务被停止了"), error: "stopped", steps: moves)
        default:
            let reason = last["reason"]?.str ?? last["action"]?.str ?? "unknown"
            // B7, 122 over the cloud 11-12: 9 of 11 parts were found and written down when the steps ran out, and the
            // answer was only "失败：步骤用完了还没做完". What was found goes back with the failure.
            let found = foundNotes(steps)
            if !found.isEmpty {
                return Outcome(status: "failed", answer: said(false, "部分失败：" + failureWords(reason) + "。已查到：" + found.joined(separator: "；")),
                               error: String(reason.prefix(300)), steps: moves)
            }
            return Outcome(status: "failed", answer: said(false, failureWords(reason)), error: String(reason.prefix(300)), steps: moves)
        }
    }

    /// User 11-11: "不論成功失敗都要反饋，告訴我成功還是失敗". A failed task came back with an empty answer and its reason
    /// in English in another field (121 over the cloud: "kept going back and forth between two screens").
    /// User 11-11: the customers are on the mainland: what goes back is Simplified (the phone's own screens and a goal
    /// written in Traditional made answers like "深圳明天（11/12 週四）最高溫 28°").
    /// User 11-12 (124 in 测试群): a success says no "成功", it is just the result; only a failure is labeled
    /// ("失败：…", "部分失败：…"). A "成功：" the model wrote itself is taken off too.
    nonisolated static func said(_ ok: Bool, _ text: String) -> String {
        var t = AppNames.hans(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if t.hasPrefix("失败") || t.hasPrefix("部分失败") { return t }
        for label in ["成功（未经核实）：", "成功：", "成功:", "成功，"] where t.hasPrefix(label) {
            t = String(t.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        // 122 over the cloud: a goal of seven parts was "成功" with "电池电量百分比未能核实" in it. An answer that says a
        // part was not found or not checked is not a success.
        // "（未能核实）" in front only says the check could not confirm it: reported as such, not as a failure.
        let marker = "（未能核实）"
        let checked = !t.hasPrefix(marker)
        let body = checked ? t : String(t.dropFirst(marker.count))
        // 133 over the cloud 11-14 (x4, y1): "（未能核實）部分失败：…" went out as "部分失败：部分失败：…".
        if body.hasPrefix("失败") || body.hasPrefix("部分失败") { return body }
        // 123 over the cloud 11-12: "成功：口播语音转写无法获取：两次 listen 均未识别到…" was a success.
        let unsure = ["未能核实", "未能确认", "无法确认", "未能读到", "没能", "待确认", "未能查到", "查不到",
                      "无法获取", "未能获取", "获取不到", "无法识别", "未识别到", "没有识别出", "无法提取", "拿不到",
                      "未能完成", "没有完成", "打不开", "找不到"]
        if ok, unsure.contains(where: { body.contains($0) }) { return "部分失败：" + body }
        if !ok { return "失败：" + body }
        if body.isEmpty { return "已完成" }
        return checked ? body : "（未经核实）" + body
    }

    /// What a run wrote down with note, in order, each once.
    nonisolated static func foundNotes(_ steps: [JObject]) -> [String] {
        var found: [String] = []
        for s in steps where s["action"]?.str == "note" {
            let text = (s["text"]?.str ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, !found.contains(text) { found.append(text) }
        }
        return found
    }

    /// Why a run stopped, in words for the user: the loop's own reasons in Chinese, a model's Chinese reason as it is.
    nonisolated static func failureWords(_ reason: String?) -> String {
        let r = (reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let known: [(String, String)] = [
            ("back and forth", "在几个画面之间来回打转，没能做完"), ("leaving the same screen", "在几个画面之间来回打转，没能做完"),
            ("step limit", "步骤用完了还没做完"), ("errors in a row", "连续出错，停下了"),
            ("claimed done", "几次说做完了，其实没做到"), ("lost the phone screen", "看不到手机画面（屏幕共享断了）"),
            ("is not on this phone", "这台手机没有装这个 App"), ("not_approved", "消息没有获批准，没有发送"),
            ("stopped", "任务被停止了"), ("timed out", "超时了还没做完"),
            ("nothing got on", "卡住了，换了几种做法都没有进展"),
            // 123 over the cloud 11-12: Doubao's account ran out ("LLM HTTP 403: AccountOverdueError").
            ("accountoverdue", "模型服务账户欠费，请先充值再试"),
        ]
        if let hit = known.first(where: { r.lowercased().contains($0.0) }) { return hit.1 }
        if r.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) { return r }
        return r.isEmpty ? "没能做完" : "没能做完（\(r.prefix(80))）"
    }

    static func stamp() -> String { ISO8601DateFormatter().string(from: Date()) }
    static func escaped(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? s }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    static func http(base: String, token: String, method: String, path: String, body: [String: Any]?) async throws -> (Int, Data) {
        let root = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let url = URL(string: root + path), url.scheme == "https" || url.scheme == "http" else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
