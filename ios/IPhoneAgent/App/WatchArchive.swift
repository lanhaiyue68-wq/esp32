import Foundation

/// One thing in a watched group to open and describe (群收录, user 11-12): a picture, a video, a link, a file, a card.
struct ArchiveItem: Codable, Equatable {
    var chat: String
    var sender: String
    var kind: String      // image, video, channels, link, file, card
    var text: String      // as it was read: "[图片]", "[链接] 标题", "[文件]"
    var at: Date
    var summary: String?  // what was seen when it was opened
    var ok: Bool?
    var calls: Int?       // model calls it took
}

/// 群收录 (user 11-12, from the customer): in the groups on the watch's list, every picture, video, link, file and
/// forwarded card is opened and described when the phone is idle (the owner's work always first; at most `dailyLimit`
/// a day). Once a day the planner keeps what is worth knowing (行业经验、资源链接、使用心得) out of the day's messages
/// and those descriptions, drops the chatter, and the result goes to the customer's server (POST /api/v1/knowledge,
/// the cloud's address and token). The phone is only a buffer: a day the server took is deleted from it; with no
/// server a raw day is kept 7 days, a distilled one until it goes up.
enum WatchArchive {
    static var folder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent("archive", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Opened a day at most (user: the cost is not known yet; the count of model calls is kept to see it).
    static let dailyLimitKey = "archiveDailyLimitV1"
    static var dailyLimit: Int {
        let set = UserDefaults.standard.integer(forKey: dailyLimitKey)
        return set > 0 ? set : 100
    }

    static let lastDistillKey = "archiveLastDistilledDayV1"
    static let rawDays = 7

    /// What kind of thing a read line is to open; nil: talk, a voice (written out already), a sticker.
    static func kind(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let starts = { (marks: [String]) in marks.contains { t.hasPrefix($0) } }
        if starts(["[图片]", "[圖片]", "[Image]", "[Photo]"]) { return "image" }
        if starts(["[视频号]", "[視頻號]"]) { return "channels" }
        if starts(["[视频]", "[視頻]", "[影片]", "[Video]"]) { return "video" }
        if starts(["[文件]", "[檔案]", "[File]"]) { return "file" }
        if starts(["[链接]", "[連結]", "[Link]"])
            || t.range(of: #"https?://|douyin\.com|xhslink\.com|xiaohongshu\.com|kuaishou\.com|mp\.weixin\.qq\.com"#,
                       options: .regularExpression) != nil { return "link" }
        if starts(["[聊天记录]", "[聊天記錄]", "[小程序]", "[公众号]", "[公眾號]", "[文章]", "[音乐]", "[音樂]"]) { return "card" }
        return nil
    }

    static func name(_ kind: String) -> String {
        ["image": "图片", "video": "视频", "channels": "视频号视频", "file": "文件", "link": "链接", "card": "转发的卡片"][kind] ?? "消息"
    }

    // MARK: the queue

    static func queue() -> [ArchiveItem] {
        guard let url = folder?.appendingPathComponent("queue.json"), let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([ArchiveItem].self, from: data)) ?? []
    }

    static func save(_ items: [ArchiveItem]) {
        guard let url = folder?.appendingPathComponent("queue.json") else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(items) { try? data.write(to: url, options: .atomic) }
    }

    /// New messages of a listed chat: what is to be opened goes in line, the oldest first. Not the owner's: what the
    /// owner sends is answered as the owner's (and a picture of theirs asked about is opened then).
    static func enqueue(_ messages: [ReadMessage], owners: [String], at date: Date = Date()) -> Int {
        let found = messages.compactMap { m -> ArchiveItem? in
            guard !owners.contains(m.sender), let what = Self.kind(m.text) else { return nil }
            return ArchiveItem(chat: m.chat, sender: m.sender, kind: what, text: m.text, at: m.at ?? date)
        }
        guard !found.isEmpty else { return 0 }
        var items = queue()
        for item in found where !items.contains(where: { $0.chat == item.chat && $0.sender == item.sender && $0.text == item.text
                                                        && abs($0.at.timeIntervalSince(item.at)) < 120 }) {
            items.append(item)
        }
        save(Array(items.suffix(300)))  // a busy day cannot grow it without end
        return found.count
    }

    /// The oldest waiting item, taken off the line.
    static func next() -> ArchiveItem? {
        var items = queue()
        guard !items.isEmpty else { return nil }
        let first = items.removeFirst()
        save(items)
        return first
    }

    // MARK: what was opened

    static func dayFile(_ day: String) -> URL? { folder?.appendingPathComponent("opened-\(day).jsonl") }

    static func record(_ item: ArchiveItem, at date: Date = Date()) {
        guard let url = dayFile(ReadLog.day(date)) else { return }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        guard var row = try? enc.encode(item) else { return }
        row.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            _ = h.seekToEndOfFile()
            h.write(row)
            try? h.close()
        } else {
            try? row.write(to: url, options: .atomic)
        }
    }

    static func opened(on day: String) -> [ArchiveItem] {
        guard let url = dayFile(day), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? dec.decode(ArchiveItem.self, from: Data($0.utf8)) }
    }

    static func openedToday(_ date: Date = Date()) -> Int { opened(on: ReadLog.day(date)).count }

    /// The read-only task that opens one item.
    static func openTask(_ item: ArchiveItem) -> String {
        """
        这是微信群收录的只读任务：在微信会话“\(item.chat)”里找到 \(item.sender) 发的那条\(name(item.kind))（读到的样子：\(item.text)），点开看，看完关掉。
        只看不动：不要发消息、转发、评论、点赞、收藏、关注、下单、付款、登录，不要修改或删除任何东西。遇到登录、付款或安全验证就停下，答案写“需要人工”。
        图片：说明图里是什么，把图上的文字抄出来；看完把图片往下拖一下就会关掉。
        视频、视频号：从头播放，用 listen 听它讲了什么（最多 120 秒），写出要点。
        链接、文章、转发的聊天记录：读标题、作者和正文要点，里面有资源链接就原样写出来。
        文件：点开预览，要下载才能看就点下载，读出文件名和主要内容。
        找不到这条消息就失败并写明原因。做完只写一行 JSON {"send":"内容摘要（不超过 300 字）"}：程序只做记录，不会发给任何人。
        """
    }

    // MARK: once a day

    /// When the day's work (distilling, uploading) was last tried: once an hour at most.
    static var dailyTriedAt = 0.0

    static func date(_ day: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    /// Days distilled and not yet taken by the server.
    static func knowledgeDays() -> [String] {
        guard let dir = folder else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).compactMap { name -> String? in
            guard name.hasPrefix("knowledge-"), name.hasSuffix(".json") else { return nil }
            return name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression).map { String(name[$0]) }
        }.sorted()
    }

    /// The days before today with something read or opened and not yet distilled (the last two at most: the first time,
    /// weeks of old reading would each be a call).
    static func daysToDistill(today: Date = Date()) -> [String] {
        let todayName = ReadLog.day(today)
        let last = max(UserDefaults.standard.string(forKey: lastDistillKey) ?? "",
                       ReadLog.day(today.addingTimeInterval(-3 * 86_400)))
        var days = Set<String>()
        for dir in [folder, ReadLog.folder].compactMap({ $0 }) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
                guard let day = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression).map({ String(name[$0]) }),
                      name.hasSuffix(".jsonl"), day < todayName, day > last else { continue }
                days.insert(day)
            }
        }
        return days.sorted()
    }

    static let distillPrompt = """
    你帮主人整理微信群的收录记录，挑出值得放进知识库的“干货”：行业经验、做法和技巧、资源链接、工具和产品的使用心得、\
    有用的数据和结论。闲聊、问候、表情、广告、重复的内容和与业务无关的话一律不要。
    每条干货写成独立的一条知识，用简体中文：title 一句话标题，content 把要点写清楚（谁的经验、在什么情况下、怎么做、结果），\
    links 是原文里出现的资源链接（没有就空数组），source 写来源群和发言人。群里的说法没查证，不要改成肯定的语气；\
    价格、新闻这类会过期的内容在 content 里写上日期。不要编造记录里没有的内容。
    只输出 JSON 数组，例如 [{"title":"…","content":"…","links":["…"],"source":"测试群·张三"}]；一条干货都没有就输出 []。
    """

    /// One day's messages of the listed chats and what was opened, as the planner's input, at most `limit` characters.
    static func distillInput(day: String, messages: [ReadMessage], opened: [ArchiveItem], limit: Int = 16_000) -> String {
        var lines = ["日期：\(day)"]
        lines += messages.map { "[\($0.chat)] \($0.sender)：\($0.text)" }
        lines += opened.compactMap { item in
            guard item.ok == true, let summary = item.summary, !summary.isEmpty else { return nil }
            return "[\(item.chat)] \(item.sender) 发的\(name(item.kind))，点开看到：\(summary)"
        }
        let out = lines.joined(separator: "\n")
        return out.count > limit ? String(out.prefix(limit)) + "\n（后面的记录太长，已省略）" : out
    }

    /// The planner's JSON array as items; nil when it is not one (the day is tried again the next time).
    static func knowledge(_ reply: String) -> [[String: Any]]? {
        guard let start = reply.firstIndex(of: "["), let end = reply.lastIndex(of: "]"), start < end,
              let data = String(reply[start...end]).data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return list.filter { ($0["title"] as? String).map { !$0.isEmpty } ?? false }
    }

    /// The day's distilled knowledge, kept on the phone until the server has it.
    static func knowledgeFile(_ day: String) -> URL? { folder?.appendingPathComponent("knowledge-\(day).json") }

    /// What the server gets (docs/cloud-bridge-protocol.md §6).
    static func uploadBody(day: String, device: String, items: [[String: Any]]) -> [String: Any] {
        ["date": day, "device_id": device, "source": "wechat_group_archive", "items": items]
    }

    /// After the server took a day: its raw messages, its opened items and its knowledge go from the phone.
    static func forget(day: String) {
        for url in [dayFile(day), knowledgeFile(day), ReadLog.folder?.appendingPathComponent(day + ".jsonl")].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// No server: raw days older than a week go; distilled days stay until they go up.
    static func prune(today: Date = Date()) {
        let oldest = ReadLog.day(today.addingTimeInterval(-Double(rawDays) * 86_400))
        for dir in [folder, ReadLog.folder].compactMap({ $0 }) {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".jsonl") {
                guard let day = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression).map({ String(name[$0]) }),
                      day < oldest else { continue }
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }
}
