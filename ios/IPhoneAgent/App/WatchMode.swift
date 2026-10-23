import Foundation

/// WeChat watch (守候微信): stay on WeChat, read new messages and answer the ones that call for it. Waiting costs
/// nothing: the mirrored screen is compared on this iPhone every 2 s and the model is only asked when WeChat changed
/// for a few seconds (a new message, a red badge) or, as a safety net, every few minutes.
///
/// A check is split into small steps, each done by what does it reliably (traces(34): one run asked to find, read,
/// remember and answer lost track and went back and forth until it gave up):
/// 1. an agent run opens the chat (the one chosen chat, or the first unread one in scope);
/// 2. one vision call reads the screen into messages (WatchReport.screen);
/// 3. code keeps what is new since the previous look (watchLast), and decides by plain text matching whether a reply is due: a whitelisted
///    sender's @mention of one of the user's own names, or a passphrase (WatchSettings.fires); interject mode may
///    add one light remark to small talk, at most every ten minutes per chat;
/// 4. one text call writes the reply from the recent chat, the user's rules and the chosen knowledge;
/// 5. an agent run types and sends it, with the privacy check on every `type`.
/// Everything read is kept (ReadLog) and, with ChatTool on the computer, reported there (ChatToolLink), which may
/// decide the replies instead. Background audio stays on for the whole watch.
enum WatchSettings {
    static let onlyListedKey = "watchOnlyListedV1", targetsKey = "watchTargetsV1"
    static let instructionKey = "watchInstructionV1", fallbackKey = "watchFallbackV1"
    static let knowledgeKey = "watchKnowledgeV1", privateWordsKey = "watchPrivateWordsV1"
    static let blockNumbersKey = "watchBlockNumbersV1", intervalKey = "watchIntervalMinutesV1"
    static let interjectKey = "watchInterjectV1", sendersKey = "watchSendersV1", passphrasesKey = "watchPassphrasesV1"
    static let myNamesKey = "watchMyNamesV1"
    static let serverOnKey = "watchServerOnV1", serverURLKey = "watchServerURLV1", robotKey = "watchRobotIdV1"
    static let serverRepliesKey = "watchServerRepliesV1"
    static let knowledgeFromComputerKey = "watchKnowledgeComputerV1", computerURLKey = "watchComputerURLV1"
    static let computerTokenKey = "watchComputerTokenV1", computerFilesKey = "watchComputerFilesV1"
    static let defaultInstruction = "用简短、礼貌、自然的中文回复，像真人聊天一样，正面回答对方的问题。"
    static let defaultFallback = "这个我不太确定，稍后再告诉你。"
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
    static var passphrases: [String] { passphrases(from: d.string(forKey: passphrasesKey) ?? defaultPassphrase) }
    /// The names others @ this account by (WeChat nickname, group nicknames): "@蓝" is a mention only if "蓝" is here.
    static var myNames: [String] { names(typed: d.string(forKey: myNamesKey) ?? "", codes: d.string(forKey: passphrasesKey) ?? "") }

    /// A passphrase written as an @ is a mention, not words to look for: "@我" means "when the owner @s this account"
    /// (matched through myNames), "@蓝" also names the account 蓝.
    static func passphrases(from raw: String) -> [String] { lines(raw).filter { !isMention($0) } }

    static func names(typed: String, codes: String) -> [String] {
        let fromCodes = lines(codes).filter(isMention).map(withoutAt).filter { !["我", "me", "自己", "本号"].contains($0) }
        return lines((lines(typed).map(withoutAt) + fromCodes).joined(separator: "\n"))
    }

    private static func isMention(_ s: String) -> Bool { s.hasPrefix("@") || s.hasPrefix("＠") }
    private static func withoutAt(_ s: String) -> String { isMention(s) ? String(s.dropFirst()).trimmingCharacters(in: .whitespaces) : s }
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
        var myNames: [String] = [], interject = false, serverReplies = false, instruction = "", fallback = ""
        /// The one chosen chat stays open between checks: its new messages show up on screen by themselves.
        var single: Bool { onlyListed && targets.count == 1 }
    }

    static var rules: Rules {
        Rules(targets: targets, onlyListed: onlyListed, senders: senders, passphrases: passphrases, myNames: myNames,
              interject: interject, serverReplies: serverReplies, instruction: instruction, fallback: fallback)
    }

    /// A reply is due: the sender is whitelisted (or there is no whitelist) and the text @mentions one of the user's
    /// names or holds a passphrase. Plain text matching, so the model cannot talk itself into or out of it.
    static func fires(_ m: ReadMessage, _ r: Rules) -> Bool {
        let allowed = r.senders.isEmpty || r.senders.contains { m.sender == $0 || m.sender.contains($0) }
        guard allowed else { return false }
        let mention = r.myNames.contains { m.text.contains("@" + $0) || m.text.contains("＠" + $0) }
        return mention || r.passphrases.contains { m.text.contains($0) }
    }

    /// Step 1: open the chat to read. Never replies.
    static func openTask(_ r: Rules) -> String {
        if r.single {
            let chat = r.targets[0]
            return """
            打开微信里的会话“\(chat)”。如果现在已经在这个会话里，什么都不用做，直接完成；否则回到微信聊天列表找到它并打开，列表里没有就用顶部搜索。
            打开后完成，答案写“\(chat)”。不要回复、不要输入任何内容。
            """
        }
        let names = r.targets.map { "“\($0)”" }.joined(separator: "、")
        let scope = r.onlyListed ? "这些会话：\(names)" : "私聊，以及这些群：\(names.isEmpty ? "无" : names)（公众号、订阅号、服务通知、文件传输助手除外）"
        return """
        打开微信，回到聊天列表（底部“微信”标签页）。在\(scope)里，找第一个带红色未读数字或红点的会话并打开。
        打开后完成，答案只写一行 JSON：{"chat":"会话名"}；都没有未读就直接完成，答案写 {"chat":""}。不要回复、不要输入任何内容。
        """
    }

    /// Step 5 (and ChatTool's replies): type the text in the chat and send it.
    static func sendTask(chat: String, text: String, back: Bool = false) -> String {
        """
        在微信会话“\(chat)”里发一条消息。如果现在不在这个会话里，先回到聊天列表找到它并打开（列表里没有就用顶部搜索）。
        点底部输入框，输入下面这段内容并发送，一字不改：
        \(text)
        发送后\(back ? "返回聊天列表" : "停在这个会话里")，然后完成。找不到这个会话就失败，并写明原因。
        """
    }

    /// Step 2: one look at the open chat.
    static func readPrompt(chat: String, myNames: [String]) -> String {
        let mine = myNames.isEmpty ? "" : "我的微信名字是：\(myNames.map { "“\($0)”" }.joined(separator: "、"))。"
        return """
        你在看一张微信聊天界面的截图，会话名是“\(chat)”。\(mine)
        从上到下列出截图里能看清的每条消息（最多 20 条），只输出一行 JSON，不要别的文字：
        {"group":true,"messages":[{"sender":"发言人","text":"消息内容","mine":false}]}
        规则：group 表示这是不是群聊（顶部标题后面有人数就是群）。右侧绿色气泡是我发的：mine=true，sender 写“我”。
        左侧是别人发的：sender 写气泡上方的名字，私聊没有名字时写会话名。text 照抄原文，@ 也照抄；图片写 [图片]，表情写 [表情]，
        语音写 [语音]，文件写 [文件]。气泡下方灰色的引用块（“某某：……”）不是新消息：不要单独列，也不要写进 text。
        时间、系统提示（如“某某加入了群聊”“撤回了一条消息”）不要列。看不清的不要猜。
        """
    }

    /// Step 4: the reply, from the recent chat, the user's rules and the chosen knowledge.
    /// Step 4: what to do about the messages that called for it: a reply to type, or, when the owner asks for
    /// something only the phone can find out or do (who the group owner is, @ someone), a task for the agent.
    static func composePrompt(chat: String, group: Bool, recent: [WatchReport.Line], due: [ReadMessage], r: Rules, knowledge: String,
                              owner: Bool) -> String {
        let history = recent.suffix(20).map { "\($0.mine ? "我" : $0.sender)：\($0.text)" }.joined(separator: "\n")
        let asks = due.map { "\($0.sender)：\($0.text)" }.joined(separator: "\n")
        let tasks = owner
            ? """
              说这话的是主人（白名单里的人）。主人要你在微信里查看或操作才能做到的事（例如看群成员、找出谁是群主、@某人、看群公告），\
              就给出 task：一句完整的中文操作说明，写清要找什么、最后要在这个会话里发出什么（要@人就写“@某某”，执行时会从成员列表里选人，\
              这样才是真的@）。能直接从上面的聊天或知识库回答的，只用 reply。
              """
            : "说这话的不是主人：只能用 reply 回答，不能给 task。"
        return """
        你是用户在微信里的分身，正在替他在\(group ? "群聊" : "私聊")“\(chat)”里回复。\(r.myNames.isEmpty ? "" : "别人用“@\(r.myNames[0])”叫的就是你。")
        最近的聊天（从早到晚）：
        \(history)
        需要你回应的消息：
        \(asks)
        用户对回复的要求：\(r.instruction)
        \(knowledge.isEmpty ? "用户没有给知识库：凭常识自然地回答；具体事实（价格、时间、地址、名单等）不知道就说不知道，或回复：“\(r.fallback)”。"
                             : "知识库（具体事实只能依据它；里面没有的，回复：“\(r.fallback)”）：\n\(knowledge)")
        \(tasks)
        规则：直接回应对方说的话，正面回答问题，像真人一样简短自然；能从上面的聊天里看出答案的就直接说。\(group ? "在群里用 reply 时，开头写“@发言人 ”。" : "")
        不编造，不透露用户的隐私，不承诺金钱和时间，不发链接。不允许的操作（付款、红包、转账、拉人踢人、改群设置、退群、加好友、发文件、打开链接、发朋友圈）一律不做，用 reply 说明做不到。
        只输出一行 JSON：{"reply":"要直接发送的话，不需要就留空","task":"要在微信里执行的操作，不需要就留空"}
        """
    }

    /// The owner's request carried out on the phone; the agent sends the outcome itself (a real @ from the member list).
    static func ownerTask(chat: String, task: String) -> String {
        """
        你在微信会话“\(chat)”里，替主人完成他的指令：\(task)
        做法提示：看群成员和群主：点会话右上角的“…”打开聊天信息，群成员在顶部，点“查看更多群成员”看全部；群主在成员列表里名字旁标着“群主”。
        要@某人：回到这个会话，在底部输入框输入“@”，在弹出的成员列表里找到并点选他（列表顶部可以搜索），再接着输入其余内容，然后发送。
        只能在微信里操作；不准付款、发红包、转账、拉人踢人、改群设置、退群、加好友、发文件、打开链接。
        做完后停在会话“\(chat)”里，然后完成，答案写你做了什么、查到了什么。做不到就失败，并写明原因。
        """
    }

    /// Interject mode: one light remark to small talk, or SKIP.
    static func interjectPrompt(chat: String, recent: [WatchReport.Line], r: Rules) -> String {
        let history = recent.suffix(15).map { "\($0.mine ? "我" : $0.sender)：\($0.text)" }.joined(separator: "\n")
        return """
        你是用户在微信群“\(chat)”里的分身。下面是最近的聊天（从早到晚）：
        \(history)
        判断要不要插一句：只在轻松的闲聊（问候、玩笑、感慨、日常）时插一句简短自然的话；涉及金钱、承诺、隐私、工作业务、争论、
        严肃话题时不插。用户的风格要求：\(r.instruction)
        要插就只输出那一句话；不插就只输出 SKIP。
        """
    }
}

/// One message read from the screen.
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

    init(from decoder: Decoder) throws {  // older log lines or a model may leave fields out
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
    struct Line: Equatable { var sender: String; var text: String; var mine: Bool }
    struct Screen: Equatable { var group: Bool; var lines: [Line] }

    /// The JSON object anywhere in a reply (models sometimes wrap it in words or a code fence).
    static func object(_ reply: String) -> Data? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else { return nil }
        return String(reply[start...end]).data(using: .utf8)
    }

    /// Step 2's reply as lines; nil when it is not the expected JSON.
    static func screen(_ reply: String) -> Screen? {
        struct Row: Decodable { var sender: String?; var text: String?; var mine: Bool? }
        struct Box: Decodable { var group: Bool?; var messages: [Row]? }
        guard let data = object(reply), let box = try? JSONDecoder().decode(Box.self, from: data), let rows = box.messages else { return nil }
        let lines = rows.compactMap { row -> Line? in
            let text = (row.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let mine = row.mine ?? false
            return Line(sender: mine ? "我" : (row.sender ?? "").trimmingCharacters(in: .whitespaces), text: text, mine: mine)
        }
        return Screen(group: box.group ?? false, lines: lines)
    }

    /// Step 1's answer in multi-chat mode: the chat it opened, or nil when nothing was unread.
    static func openedChat(_ answer: String) -> String? {
        struct Box: Decodable { var chat: String? }
        if let data = object(answer), let box = try? JSONDecoder().decode(Box.self, from: data) {
            let chat = (box.chat ?? "").trimmingCharacters(in: .whitespaces)
            return chat.isEmpty ? nil : chat
        }
        return nil
    }

    /// Step 4's answer: the reply and the phone task (either may be empty). A model that ignored the format and wrote
    /// plain words gets them as the reply; broken JSON gives nil rather than braces typed into a chat.
    static func decision(_ answer: String) -> (reply: String, task: String)? {
        struct Box: Decodable { var reply: String?; var task: String? }
        let clean = { (s: String?) in (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        if let data = object(answer) {
            guard let box = try? JSONDecoder().decode(Box.self, from: data) else { return nil }
            return (clean(box.reply), clean(box.task))
        }
        let words = answer.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”'「」"))
        return words.isEmpty || answer.contains("{") ? nil : (words, "")
    }

    /// What is new on screen since the previous look: the lines after the place where the previous look's last lines
    /// (three, else two, else one) show up again, its last occurrence when there are several. Matching a run of lines
    /// rather than single texts catches a message repeated word for word (traces(35): the owner asked the same thing
    /// twice and the second was taken as already read). When the previous lines are gone (scrolled far), every line
    /// not on the previous screen.
    /// The first look at a chat: what nobody answered yet, the messages under this account's last one (the last three
    /// when none of its own is on screen). Opening the chat takes half a minute, and a message sent just after the
    /// watch started (build 22 took it as old and never answered); one answered before sits above "mine".
    static func unanswered(_ lines: [Line]) -> [Line] {
        if let i = lines.lastIndex(where: { $0.mine }) { return Array(lines[(i + 1)...]) }
        return Array(lines.suffix(3))
    }

    static func new(_ lines: [Line], after previous: [Line]) -> [Line] {
        guard !previous.isEmpty else { return lines }
        let cur = lines.map(key), prev = previous.map(key)
        for n in stride(from: min(3, prev.count), through: 1, by: -1) {
            let tail = Array(prev.suffix(n))
            for start in stride(from: cur.count - n, through: 0, by: -1) where Array(cur[start..<(start + n)]) == tail {
                return Array(lines[(start + n)...])
            }
        }
        let seen = Set(prev)
        return lines.filter { !seen.contains(key($0)) }
    }

    /// Sender and the first line of the text without spaces: a quote under a message, read differently from one look
    /// to the next, does not make the same message look new.
    static func key(_ l: Line) -> String {
        let first = l.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? l.text
        return (l.mine ? "我" : l.sender) + "\u{1F}" + first.filter { !$0.isWhitespace }
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
        if !WatchSettings.serverReplies && WatchSettings.myNames.isEmpty {
            return String(localized: "Enter your name in WeChat (what people type after @), so an @mention can be recognized.")
        }
        if WatchSettings.serverOn, ChatToolLink.socketURL(WatchSettings.serverURL, robot: WatchSettings.robotId) == nil {
            return String(localized: "Enter the computer's ChatTool address, like http://192.168.31.85:8881.")
        }
        watching = true
        watchHandled = 0
        watchRead = 0
        watchLast = [:]
        watchInterjectedAt = [:]
        watchRetries = [:]
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
        if !agent.running && !startingAgent {
            keepAwake.stop()
            Task { try? await feed.stream(false) }  // kept on between checks while watching
        }
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
                if let why = PrivacyGuard.check(send.text, words: WatchSettings.privateWords, numbers: WatchSettings.blockNumbers) {
                    DebugLog.write("watch: ChatTool's reply withheld: \(why)")
                } else {
                    _ = await watchRun(WatchSettings.sendTask(chat: send.chat, text: send.text, back: !WatchSettings.rules.single))
                }
                guard watching else { break }
                (baseline, changedAt, quietUntil) = (nil, nil, now() + 6)
            } else {
                let t = now(), frame = feed.frame
                if t < quietUntil {
                    baseline = nil  // after a check the pointer fades and the screen settles: not new messages
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
                let retry = !watchRetries.isEmpty && t - lastCheck >= 20  // a reply that did not go out
                if due || retry || (moved && t - lastCheck >= 15) {
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

    /// One check, in small steps (see WatchSettings): open, read, keep what is new, decide in code, write, send.
    private func watchCheck() async -> Bool {
        let rules = WatchSettings.rules
        guard let opened = await watchRun(WatchSettings.openTask(rules)) else { return false }
        guard let chat = rules.single ? rules.targets[0] : WatchReport.openedChat(opened) else { return true }  // nothing unread
        guard let screen = await readChat(chat) else { return false }

        let firstLook = watchLast[chat] == nil, before = watchLast[chat]
        let fresh = firstLook ? WatchReport.unanswered(screen.lines) : WatchReport.new(screen.lines, after: watchLast[chat] ?? [])
        watchLast[chat] = screen.lines
        if firstLook { DebugLog.write("watch: first look at \(chat): \(fresh.count) of \(screen.lines.count) message(s) not answered yet") }
        var read = fresh.filter { !$0.mine }.map { line in
            ReadMessage(chat: chat, group: screen.group, sender: line.sender, text: line.text,
                        atMe: rules.myNames.contains { line.text.contains("@" + $0) })
        }

        var reply: String?, task: String?
        if !rules.serverReplies && !read.isEmpty {
            let due = read.filter { WatchSettings.fires($0, rules) }
            if !due.isEmpty {
                let knowledge = await watchKnowledge()
                let owner = !rules.senders.isEmpty  // phone tasks only for an explicit whitelist, never for anyone
                if let decided = await decide(WatchSettings.composePrompt(chat: chat, group: screen.group, recent: screen.lines,
                                                                           due: due, r: rules, knowledge: knowledge, owner: owner)) {
                    reply = decided.reply.isEmpty ? nil : decided.reply
                    task = owner && !decided.task.isEmpty ? decided.task : nil
                }
            } else if rules.interject && screen.group && now() - (watchInterjectedAt[chat] ?? 0) >= 600 {
                reply = await compose(WatchSettings.interjectPrompt(chat: chat, recent: screen.lines, r: rules))
                if reply != nil { watchInterjectedAt[chat] = now() }
            }
        }
        var sent = true  // false: what was due did not go out
        if let task {  // the owner asked for something only the phone can do: the agent does it and sends the outcome
            DebugLog.write("watch: owner task in \(chat): \(task)")
            if let done = await watchRun(WatchSettings.ownerTask(chat: chat, task: task)) {
                if let i = read.indices.last { read[i].replied = "【已执行】" + (done.isEmpty ? task : done) }
            } else { sent = false }
        } else if let text = reply {
            if let why = PrivacyGuard.check(text, words: WatchSettings.privateWords, numbers: WatchSettings.blockNumbers) {
                DebugLog.write("watch: reply withheld: \(why)")
            } else if await watchRun(WatchSettings.sendTask(chat: chat, text: text, back: !rules.single)) != nil {
                if let i = read.indices.last { read[i].replied = text }
            } else { sent = false }
        } else if !rules.single {
            try? await pointer.goBack()  // back to the chat list, for the other chats' badges
        }

        if !sent, watching, watchRetries[chat, default: 0] < 2 {
            // Cut off (the screen dropped, a run failed): read these again soon instead of losing them as seen.
            watchRetries[chat, default: 0] += 1
            watchLast[chat] = before
            DebugLog.write("watch: \(chat): the reply did not go out; reading again at the next check")
            return false
        }
        watchRetries[chat] = nil
        ReadLog.append(read)
        watchRead += read.count
        if WatchSettings.serverOn { chatTool.report(read) }
        let outcome = reply == nil && task == nil ? "" : sent ? ", replied" : ", reply not sent"
        DebugLog.write("watch: \(chat): \(read.count) new message(s)\(outcome)")
        return true
    }

    /// Step 2: one vision call on the open chat; logged into the check's trace.
    private func readChat(_ chat: String) async -> WatchReport.Screen? {
        do {
            if !feed.streamOn { try await feed.stream(true) }  // the screen as it is now, not the last frame of the run
            _ = try await feed.currentFrame()
            guard let frame = feed.frame else { return nil }
            let reply = try await settings.client("actor").chat(system: WatchSettings.readPrompt(chat: chat, myNames: WatchSettings.myNames),
                                                                text: "读出这张截图里的消息。", image: frame, maxTokens: 1500, temperature: 0)
            traces.write(frame, kind: "watch read", ["chat": .str(chat), "reply": .str(reply.text)])
            guard let screen = WatchReport.screen(reply.text) else {
                DebugLog.write("watch: could not read \(chat): \(reply.text.prefix(200))")
                return nil
            }
            return screen
        } catch {
            DebugLog.write("watch: reading \(chat) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Step 4: the reply or the owner's phone task, as one JSON line from the planner model.
    private func decide(_ prompt: String) async -> (reply: String, task: String)? {
        do {
            let answer = try await settings.client("planner").chat(system: prompt, text: "按要求只输出那一行 JSON。", image: nil,
                                                                   maxTokens: 500, temperature: 0.4)
            traces.write(kind: "watch decide", ["prompt": .str(String(prompt.suffix(1500))), "reply": .str(answer.text)])
            return WatchReport.decision(answer.text)
        } catch {
            DebugLog.write("watch: deciding the reply failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Interject mode: one text call; nil for SKIP or an empty answer.
    private func compose(_ prompt: String) async -> String? {
        do {
            let reply = try await settings.client("planner").chat(system: prompt, text: "写出要发送的那段话。", image: nil,
                                                                  maxTokens: 400, temperature: 0.6)
            let text = reply.text.trimmingCharacters(in: CharacterSet(charactersIn: " \n\"“”'「」"))
            traces.write(kind: "watch reply", ["prompt": .str(String(prompt.suffix(1500))), "reply": .str(text)])
            return text.isEmpty || text.uppercased() == "SKIP" ? nil : text
        } catch {
            DebugLog.write("watch: writing the reply failed: \(error.localizedDescription)")
            return nil
        }
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
