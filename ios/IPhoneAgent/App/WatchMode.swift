import Foundation

/// WeChat watch (守候微信): stay on WeChat and answer new messages for the user. Waiting costs nothing: the mirrored
/// screen is compared on this iPhone every 2 s and the model is only asked when WeChat changed for a few seconds
/// (a new message moves the chat list, a red badge appears) or, as a safety net, every few minutes. Each check is
/// an ordinary run (trace, lessons, review) built from the user's choices: which chats or groups, how to reply,
/// which knowledge files, what must never be sent. Background audio stays on for the whole watch.
enum WatchSettings {
    static let onlyListedKey = "watchOnlyListedV1", targetsKey = "watchTargetsV1"
    static let instructionKey = "watchInstructionV1", fallbackKey = "watchFallbackV1"
    static let knowledgeKey = "watchKnowledgeV1", privateWordsKey = "watchPrivateWordsV1"
    static let blockNumbersKey = "watchBlockNumbersV1", intervalKey = "watchIntervalMinutesV1"
    static let defaultInstruction = "用简短、礼貌、自然的中文回复，像真人聊天一样，不要长篇大论。"
    static let defaultFallback = "收到，我稍后回复您。"

    private static var d: UserDefaults { .standard }
    static var onlyListed: Bool { d.object(forKey: onlyListedKey) as? Bool ?? true }
    static var targets: [String] { lines(d.string(forKey: targetsKey) ?? "") }
    static var instruction: String { text(instructionKey, defaultInstruction) }
    static var fallback: String { text(fallbackKey, defaultFallback) }
    static var knowledgeFiles: [String] { lines(d.string(forKey: knowledgeKey) ?? "") }
    static var privateWords: [String] { lines(d.string(forKey: privateWordsKey) ?? "") }
    static var blockNumbers: Bool { d.object(forKey: blockNumbersKey) as? Bool ?? true }
    static var intervalMinutes: Int { min(60, max(1, d.object(forKey: intervalKey) as? Int ?? 5)) }

    private static func text(_ key: String, _ fallback: String) -> String {
        let t = (d.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    /// One name per line (commas and 、 also separate), trimmed, without empties or repeats.
    static func lines(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: CharacterSet(charactersIn: "\n,，、;；"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The run's task, in the user's language: who to answer, how, and the fixed safety rules.
    static func task(targets: [String], onlyListed: Bool, instruction: String, fallback: String, knowledge: Bool) -> String {
        let names = targets.map { "“\($0)”" }.joined(separator: "、")
        let who = onlyListed
            ? "2. 只处理这些会话：\(names)。它们之外的未读会话一律不打开、不回复。"
            : "2. 处理私聊里的未读消息；群聊只处理这些：\(names.isEmpty ? "无" : names)。公众号、订阅号、服务通知、文件传输助手不打开、不回复。"
        let source = knowledge
            ? "5. 回复内容只能依据用户选定的知识库；知识库里没有答案时，回复：“\(fallback)”。不要编造。"
            : "5. 用户没有选定知识库：只做礼貌、通用的回复；需要具体信息（价格、地址、时间、承诺等）时，回复：“\(fallback)”。不要编造。"
        return """
        守候微信：替用户处理微信里的新消息。
        1. 如果当前不在微信的聊天列表（底部“微信”标签页），先打开微信回到聊天列表。
        \(who)
        3. 在要处理的会话里，找带红色未读数字或红点的，从上往下逐个打开；都没有未读就直接完成，答案写“没有新消息”。在群里只回复@你或明显在问你的消息。
        4. 读完对方发来的新消息，按用户的要求回复：\(instruction)
        \(source)
        6. 不透露用户的任何隐私，不把一个会话里的内容发到别的会话；不点红包、转账、付款、链接和文件；对方要钱、要验证码、要隐私的，不回复，在答案里写出是谁、什么事。
        7. 每个会话回复完都返回聊天列表；全部处理完再完成，答案简要列出回复了谁。
        """
    }
}

/// The files the user drops into Documents/knowledge (Files › On My iPhone › Lan Agent › knowledge); replies use
/// only the ones switched on in WeChat watch, up to `limit` characters in all.
enum KnowledgeBase {
    static let limit = 6000

    static var folder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("knowledge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)  // shows up in Files
        return dir
    }

    static func files() -> [String] {
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { ["md", "txt"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted()
    }

    /// The selected files, each under its name, cut at `limit` characters.
    static func text(_ selected: [String], in dir: URL? = folder, limit: Int = limit) -> (text: String, truncated: Bool) {
        guard let dir else { return ("", false) }
        var out = ""
        for name in selected.sorted() {
            guard let body = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) else { continue }
            out += "## \(name)\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.count > limit ? (String(out.prefix(limit)), true) : (out, false)
    }
}

/// Checked before anything is typed in WeChat watch: the user's private words and, unless switched off, anything
/// that looks like a phone, ID or bank card number or an email. A hit refuses the text, so it is never sent.
enum PrivacyGuard {
    static let patterns: [(label: String, regex: String)] = [
        ("手机号", #"(?<!\d)1[3-9]\d{9}(?!\d)"#),
        ("韩国手机号", #"(?<!\d)01[016789]\d{7,8}(?!\d)"#),
        ("身份证号", #"(?<!\d)\d{17}[\dXx](?!\d)"#),
        ("银行卡号", #"(?<!\d)\d{16,19}(?!\d)"#),
        ("邮箱", #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
    ]

    /// Why `text` must not be sent, or nil. The reason never repeats the private word itself (it goes into the trace).
    static func check(_ text: String, words: [String], numbers: Bool) -> String? {
        for (i, word) in words.enumerated() where text.localizedCaseInsensitiveContains(word) {
            return "这段回复包含用户设为隐私的内容（第 \(i + 1) 项），已拦下没有发送。改写回复，完全不要提到它。"
        }
        guard numbers else { return nil }
        let digits = text.replacingOccurrences(of: #"(?<=\d)[ \-–—.](?=\d)"#, with: "", options: .regularExpression)
        for p in patterns where digits.range(of: p.regex, options: .regularExpression) != nil {
            return "这段回复像是包含\(p.label)，已拦下没有发送。改写回复，不要包含任何号码或隐私信息。"
        }
        return nil
    }
}

extension AppModel {
    /// Start watching. Checked like a Shortcuts run: once it is away there is no screen to fix things on.
    /// Returns why it cannot start, or nil.
    func startWatch() -> String? {
        guard !watching else { return nil }
        if !MockMode.on {
            guard settings.isConfigured else { return String(localized: "Set up the model in Settings first.") }
            guard pointer.calibrated else { return String(localized: "Calibrate the pointer in Lan Agent first.") }
            guard board.connected, feed.mirroring else {
                return String(localized: "The board or Screen Mirroring isn't ready. Connect the board and start Screen Mirroring.")
            }
        }
        if WatchSettings.onlyListed && WatchSettings.targets.isEmpty {
            return String(localized: "Add at least one chat or group to reply to, or turn off “Only these chats”.")
        }
        watching = true
        watchHandled = 0
        watchStatus = String(localized: "Starting…")
        keepAwake.start()
        watchJob = Task { [weak self] in await self?.watchLoop() }
        DebugLog.write("watch: started")
        return nil
    }

    func stopWatch(_ why: String) {
        guard watching else { return }
        watching = false
        watchJob?.cancel()
        watchJob = nil
        watchStatus = String(localized: "Stopped: \(why)")
        DebugLog.write("watch: stopped (\(why))")
        if !agent.running && !startingAgent { keepAwake.stop() }
    }

    private var watchIdleLine: String { String(localized: "Watching WeChat · handled \(watchHandled) times") }

    private func watchLoop() async {
        var baseline: Data?, changedAt: Double?, lastCheck = -Double.infinity, quietUntil = 0.0, failures = 0
        while watching && !Task.isCancelled {
            if agent.running || startingAgent || help != nil {
                baseline = nil  // a check (or a question to the user) is under way
            } else if !MockMode.on && !(board.connected && feed.mirroring) {
                watchStatus = String(localized: "Waiting for the board and Screen Mirroring…")
                baseline = nil
            } else {
                let t = now(), frame = feed.frame
                if t < quietUntil {
                    baseline = nil  // after a check the pointer fades and the list settles: not new messages
                } else if baseline == nil {
                    baseline = frame
                    changedAt = nil
                }
                var moved = false
                if let b = baseline, frame != b, Vision.changed(b, frame) {
                    if let c = changedAt { moved = t - c >= 2 } else { changedAt = t }  // lasting, not a passing banner
                } else {
                    changedAt = nil
                }
                let due = t - lastCheck >= Double(WatchSettings.intervalMinutes) * 60
                if due || (moved && t - lastCheck >= 20) {
                    lastCheck = t
                    watchStatus = moved ? String(localized: "New activity on WeChat; handling it…") : String(localized: "Regular check…")
                    DebugLog.write("watch: check (\(moved ? "screen changed" : "interval"))")
                    let ok = await watchCheck()
                    guard watching else { break }
                    failures = ok ? 0 : failures + 1
                    if failures >= 3 {
                        notifier.post(.failed, title: String(localized: "WeChat watch stopped"),
                                      body: String(localized: "Three checks in a row did not finish."), run: runID)
                        stopWatch(String(localized: "three checks in a row did not finish"))
                        break
                    }
                    (baseline, changedAt, quietUntil) = (nil, nil, now() + 6)
                }
                if changedAt == nil { watchStatus = watchIdleLine }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    /// One check: an ordinary run with the user's choices; true when it ended with done.
    private func watchCheck() async -> Bool {
        let knowledge = KnowledgeBase.text(WatchSettings.knowledgeFiles).text
        let task = WatchSettings.task(targets: WatchSettings.targets, onlyListed: WatchSettings.onlyListed,
                                      instruction: WatchSettings.instruction, fallback: WatchSettings.fallback,
                                      knowledge: !knowledge.isEmpty)
        let words = WatchSettings.privateWords, numbers = WatchSettings.blockNumbers
        agent.steps = []  // a start that fails leaves no steps, not the previous check's
        await run(task, reference: knowledge, outgoing: { PrivacyGuard.check($0, words: words, numbers: numbers) })
        while agent.running || startingAgent {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let done = agent.steps.last?["action"]?.str == "done"
        if done { watchHandled += 1 }
        return done
    }
}
