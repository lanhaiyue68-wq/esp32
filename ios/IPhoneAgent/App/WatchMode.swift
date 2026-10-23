import Foundation

/// WeChat watch (守候微信): stay on WeChat, read new messages and answer the ones that call for it. Waiting costs
/// nothing: the mirrored screen is compared on this iPhone every 2 s and the model is only asked when WeChat changed
/// for a few seconds (a new message moves the chat list, a red badge appears) or, as a safety net, every few minutes.
/// Each check is an ordinary run (trace, lessons, review) built from the user's choices. A reply is triggered only
/// by an @mention or a passphrase from the whitelisted people (or, in interject mode, a light remark on small talk);
/// everything else is only read and kept (ReadLog). With ChatTool on the computer, what was read is reported there
/// and ChatTool may decide the replies (ChatToolLink). Background audio stays on for the whole watch.
enum WatchSettings {
    static let onlyListedKey = "watchOnlyListedV1", targetsKey = "watchTargetsV1"
    static let instructionKey = "watchInstructionV1", fallbackKey = "watchFallbackV1"
    static let knowledgeKey = "watchKnowledgeV1", privateWordsKey = "watchPrivateWordsV1"
    static let blockNumbersKey = "watchBlockNumbersV1", intervalKey = "watchIntervalMinutesV1"
    static let interjectKey = "watchInterjectV1", sendersKey = "watchSendersV1", passphrasesKey = "watchPassphrasesV1"
    static let serverOnKey = "watchServerOnV1", serverURLKey = "watchServerURLV1", robotKey = "watchRobotIdV1"
    static let serverRepliesKey = "watchServerRepliesV1"
    static let knowledgeFromComputerKey = "watchKnowledgeComputerV1", computerURLKey = "watchComputerURLV1"
    static let computerTokenKey = "watchComputerTokenV1", computerFilesKey = "watchComputerFilesV1"
    static let defaultInstruction = "用简短、礼貌、自然的中文回复，像真人聊天一样，不要长篇大论。"
    static let defaultFallback = "收到，我稍后回复您。"
    static let defaultPassphrase = "天王盖地虎"
    static let defaultRobot = "lan_agent_iphone"

    private static var d: UserDefaults { .standard }
    static var onlyListed: Bool { d.object(forKey: onlyListedKey) as? Bool ?? true }
    static var targets: [String] { lines(d.string(forKey: targetsKey) ?? "") }
    static var instruction: String { text(instructionKey, defaultInstruction) }
    static var fallback: String { text(fallbackKey, defaultFallback) }
    static var knowledgeFiles: [String] { lines(d.string(forKey: knowledgeKey) ?? "") }
    static var privateWords: [String] { lines(d.string(forKey: privateWordsKey) ?? "") }
    static var blockNumbers: Bool { d.object(forKey: blockNumbersKey) as? Bool ?? true }
    static var intervalMinutes: Int { min(60, max(1, d.object(forKey: intervalKey) as? Int ?? 5)) }
    static var interject: Bool { d.bool(forKey: interjectKey) }
    static var senders: [String] { lines(d.string(forKey: sendersKey) ?? "") }
    static var passphrases: [String] { lines(d.string(forKey: passphrasesKey) ?? defaultPassphrase) }
    static var serverOn: Bool { d.bool(forKey: serverOnKey) }
    static var serverURL: String { text(serverURLKey, "") }
    static var robotId: String { text(robotKey, defaultRobot) }
    /// ChatTool decides the replies; this iPhone only reads, reports and types what it is told.
    static var serverReplies: Bool { serverOn && d.bool(forKey: serverRepliesKey) }
    static var knowledgeFromComputer: Bool { d.bool(forKey: knowledgeFromComputerKey) }
    static var computerURL: String { text(computerURLKey, "") }
    static var computerToken: String { text(computerTokenKey, "") }
    static var computerFiles: [String] { lines(d.string(forKey: computerFilesKey) ?? "") }

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

    struct Rules {
        var targets: [String] = [], onlyListed = true, senders: [String] = [], passphrases: [String] = []
        var interject = false, serverReplies = false, instruction = "", fallback = "", knowledge = false
    }

    static var rules: Rules {
        Rules(targets: targets, onlyListed: onlyListed, senders: senders, passphrases: passphrases, interject: interject,
              serverReplies: serverReplies, instruction: instruction, fallback: fallback, knowledge: false)
    }

    /// The run's task, in the user's language: which chats, what triggers a reply, how, and the fixed safety rules.
    /// It always ends with the messages read as JSON (WatchReport), which is how reading and learning are kept.
    static func task(_ r: Rules) -> String {
        let names = r.targets.map { "“\($0)”" }.joined(separator: "、")
        let scope = r.onlyListed
            ? "2. 只看这些会话：\(names)。它们之外的未读会话一律不打开。"
            : "2. 看私聊里的未读消息；群聊只看这些：\(names.isEmpty ? "无" : names)。公众号、订阅号、服务通知、文件传输助手不打开。"
        let who = r.senders.isEmpty ? "会话里的人" : r.senders.map { "“\($0)”" }.joined(separator: "、")
        let codes = r.passphrases.map { "“\($0)”" }.joined(separator: "、")
        var reply: String
        if r.serverReplies {
            reply = "4. 不要自己回复任何消息：回复由电脑上的 ChatTool 决定。只读取并记录。"
        } else {
            reply = "4. 回复的条件：只有\(who)在消息里@你\(codes.isEmpty ? "" : "，或消息里出现暗号\(codes)")时，才回复那条消息；"
                + "其他消息不回复，只读取并记录（读屏学习）。"
            if r.interject {
                reply += "插嘴模式：遇到闲聊、问候、玩笑这类无关紧要的消息，可以简短自然地插一句；涉及金钱、承诺、隐私、工作业务的一律不插嘴，每个会话最多插一句。"
            }
            reply += "\n   回复按用户的要求：\(r.instruction)"
        }
        let source = r.knowledge
            ? "5. 回复内容只能依据用户选定的知识库；知识库里没有答案时，回复：“\(r.fallback)”。不要编造。"
            : "5. 用户没有选定知识库：只做礼貌、通用的回复；需要具体信息（价格、地址、时间、承诺等）时，回复：“\(r.fallback)”。不要编造。"
        return """
        守候微信：替用户读微信里的新消息，在需要时回复。
        1. 如果当前不在微信的聊天列表（底部“微信”标签页），先打开微信回到聊天列表。
        \(scope)
        3. 在要看的会话里，找带红色未读数字或红点的，从上往下逐个打开，读完新消息；都没有未读就直接完成。
        \(reply)
        \(source)
        6. 不透露用户的任何隐私，不把一个会话里的内容发到别的会话；不点红包、转账、付款、链接和文件；对方要钱、要验证码、要隐私的，不回复。
        7. 每个会话处理完都返回聊天列表。全部处理完再完成，完成的答案只写一行 JSON，列出这次读到的新消息：
        {"messages":[{"chat":"会话名","group":true,"sender":"发言人","text":"消息内容","atMe":false,"replied":"你发出的回复，没有就留空"}]}
        没有新消息就写 {"messages":[]}。
        """
    }

    /// A ChatTool "send message" command as a task: open that chat, type the text, send it.
    static func sendTask(chat: String, text: String) -> String {
        """
        在微信里给“\(chat)”发一条消息。
        1. 打开微信，在聊天列表找到“\(chat)”并打开；列表里没有就用顶部搜索找到它。
        2. 在输入框输入下面这段内容并发送，一字不改：
        \(text)
        3. 发完返回聊天列表，然后完成，答案写 {"messages":[]}。找不到这个会话就失败，并写明原因。
        """
    }
}

/// One message read from the screen, as the check reports it in its done answer.
struct ReadMessage: Codable, Equatable {
    var chat: String
    var group: Bool
    var sender: String
    var text: String
    var atMe: Bool
    var replied: String
    var at: Date?

    enum CodingKeys: String, CodingKey { case chat, group, sender, text, atMe, replied, at }

    init(chat: String, group: Bool, sender: String, text: String, atMe: Bool = false, replied: String = "", at: Date? = nil) {
        self.chat = chat
        self.group = group
        self.sender = sender
        self.text = text
        self.atMe = atMe
        self.replied = replied
        self.at = at
    }

    init(from decoder: Decoder) throws {  // the model may leave fields out
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chat = (try? c.decode(String.self, forKey: .chat)) ?? ""
        group = (try? c.decode(Bool.self, forKey: .group)) ?? false
        sender = (try? c.decode(String.self, forKey: .sender)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        atMe = (try? c.decode(Bool.self, forKey: .atMe)) ?? false
        replied = (try? c.decode(String.self, forKey: .replied)) ?? ""
        at = try? c.decode(Date.self, forKey: .at)
    }
}

enum WatchReport {
    /// The messages in a done answer: the JSON object anywhere in it; nothing if it has none.
    static func parse(_ answer: String) -> [ReadMessage] {
        guard let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"), start < end,
              let data = String(answer[start...end]).data(using: .utf8) else { return [] }
        struct Box: Decodable { var messages: [ReadMessage]? }
        let list = (try? JSONDecoder().decode(Box.self, from: data))?.messages ?? []
        return list.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

/// What watch read, one JSON line per message in Documents/readlog/<day>.jsonl (visible in Files), and the summaries
/// the user asks for next to it. Reading without replying is how the agent learns a chat.
enum ReadLog {
    static var folder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("readlog", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func append(_ messages: [ReadMessage], at date: Date = Date(), in dir: URL? = folder) {
        guard let dir, !messages.isEmpty else { return }
        let url = dir.appendingPathComponent(day(date) + ".jsonl")
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        var lines = Data()
        for var m in messages {
            m.at = m.at ?? date
            if let row = try? enc.encode(m) { lines.append(row); lines.append(0x0A) }
        }
        if let h = try? FileHandle(forWritingTo: url) {
            _ = h.seekToEndOfFile()
            h.write(lines)
            try? h.close()
        } else {
            try? lines.write(to: url, options: .atomic)
        }
    }

    static func messages(on date: Date = Date(), in dir: URL? = folder) -> [ReadMessage] {
        guard let dir, let text = try? String(contentsOf: dir.appendingPathComponent(day(date) + ".jsonl"), encoding: .utf8)
        else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? dec.decode(ReadMessage.self, from: Data($0.utf8)) }
    }

    static let summaryPrompt = """
    你帮用户总结他今天在微信里收到的消息。按会话分组，每组几句话：谁说了什么要点、有没有需要用户亲自处理的事（问价、约时间、要东西、\
    要钱等）、Agent 已经替他回复了什么。最后单列“需要你处理”的清单。用简体中文，简洁，不要编造消息里没有的内容。
    """

    /// The day's messages as text for the summary, newest last, at most `limit` characters.
    static func summaryInput(_ messages: [ReadMessage], limit: Int = 12_000) -> String {
        let lines = messages.map { m in
            "[\(m.group ? "群" : "私聊")·\(m.chat)] \(m.sender)：\(m.text)" + (m.replied.isEmpty ? "" : "（已回复：\(m.replied)）")
        }
        var out = lines.joined(separator: "\n")
        if out.count > limit { out = "（较早的消息已省略）\n" + String(out.suffix(limit)) }
        return out
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
        if WatchSettings.serverOn, ChatToolLink.socketURL(WatchSettings.serverURL, robot: WatchSettings.robotId) == nil {
            return String(localized: "Enter the computer's ChatTool address, like http://192.168.31.85:8881.")
        }
        watching = true
        watchHandled = 0
        watchStatus = String(localized: "Starting…")
        keepAwake.start()
        if WatchSettings.serverOn { chatTool.connect(server: WatchSettings.serverURL, robot: WatchSettings.robotId) }
        watchJob = Task { [weak self] in await self?.watchLoop() }
        DebugLog.write("watch: started")
        return nil
    }

    func stopWatch(_ why: String) {
        guard watching else { return }
        watching = false
        watchJob?.cancel()
        watchJob = nil
        chatTool.disconnect()
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
            } else if let send = chatTool.nextCommand() {
                watchStatus = String(localized: "Sending ChatTool's reply to \(send.chat)…")
                DebugLog.write("watch: ChatTool asks to send to \(send.chat)")
                _ = await watchRun(WatchSettings.sendTask(chat: send.chat, text: send.text))
                guard watching else { break }
                (baseline, changedAt, quietUntil) = (nil, nil, now() + 6)
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

    /// One check: read (and answer what triggers a reply); keep what was read and report it to ChatTool.
    private func watchCheck() async -> Bool {
        let knowledge = await watchKnowledge()
        var rules = WatchSettings.rules
        rules.knowledge = !knowledge.isEmpty
        guard let answer = await watchRun(WatchSettings.task(rules), reference: knowledge) else { return false }
        let read = WatchReport.parse(answer)
        ReadLog.append(read)
        watchRead += read.count
        if WatchSettings.serverOn { chatTool.report(read) }
        if !read.isEmpty { DebugLog.write("watch: read \(read.count) message(s), replied to \(read.filter { !$0.replied.isEmpty }.count)") }
        return true
    }

    /// An ordinary run with the privacy check on every `type`; the done answer, or nil when it did not finish.
    private func watchRun(_ task: String, reference: String = "") async -> String? {
        let words = WatchSettings.privateWords, numbers = WatchSettings.blockNumbers
        agent.steps = []  // a start that fails leaves no steps, not the previous check's
        await run(task, reference: reference, outgoing: { PrivacyGuard.check($0, words: words, numbers: numbers) })
        while agent.running || startingAgent {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        guard let last = agent.steps.last, last["action"]?.str == "done" else { return nil }
        watchHandled += 1
        return last["answer"]?.str ?? ""
    }

    /// The chosen knowledge: files on this iPhone, or the ones chosen on the computer (kept from the last good fetch
    /// when the computer is out of reach).
    private func watchKnowledge() async -> String {
        guard WatchSettings.knowledgeFromComputer else { return KnowledgeBase.text(WatchSettings.knowledgeFiles).text }
        let names = WatchSettings.computerFiles
        guard !names.isEmpty else { return "" }
        do {
            let text = try await ComputerKnowledge.content(server: WatchSettings.computerURL, token: WatchSettings.computerToken, names: names)
            computerKnowledgeCache = text
            return text
        } catch {
            DebugLog.write("watch: computer knowledge unavailable (\(error.localizedDescription)); using the last copy")
            return computerKnowledgeCache
        }
    }

    /// Today's read messages summarized by the model; also saved next to them as summary-<day>.md.
    func summarizeToday() async -> String {
        let today = ReadLog.messages()
        guard !today.isEmpty else { return String(localized: "Nothing has been read today yet.") }
        do {
            let reply = try await settings.client("planner").chat(system: ReadLog.summaryPrompt, text: ReadLog.summaryInput(today),
                                                                  image: nil, maxTokens: 1200, temperature: 0.2)
            if let dir = ReadLog.folder {
                try? reply.text.write(to: dir.appendingPathComponent("summary-\(ReadLog.day(Date())).md"), atomically: true, encoding: .utf8)
            }
            return reply.text
        } catch {
            return String(localized: "Could not summarize: \(error.localizedDescription)")
        }
    }
}
