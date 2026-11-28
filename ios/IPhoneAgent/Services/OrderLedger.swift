import Foundation

/// 199 (user 11-28, after a customer's friend's kernel 「从来话到回执」: 「這次一起做吧」, 「我們要做的就是既快又準」; the
/// two phones are its hands, the server its brain): what each order came to, kept on the device as the kernel's
/// 发送账 — every order a line: its number, what was asked, how it ended, and a picture of the screen when it did not
/// go — and the rules it gives a hand: an order heard twice is not done twice, an order like one done (or half done,
/// or not known how it ended) in the last 30 minutes is not done again blind, and a risky step (a group made, people
/// added, a message forwarded) waits a random turn. None of it slows a reply: a line written, a picture only on a
/// failure, a wait only for the risky orders.
enum OrderOutcome: String, Codable {
    case done, failed, partial, unknown
    /// What a step's reason starts with when something may have been done already (198: 「群建好了，但…」 reported as a
    /// failure while the group was there; sent again, a second group would have been made).
    static let partialMark = "【部分完成】", unknownMark = "【结果不明】"
    static func of(ok: Bool, reason: String) -> OrderOutcome {
        if ok { return .done }
        if reason.hasPrefix(partialMark) { return .partial }
        if reason.hasPrefix(unknownMark) { return .unknown }
        return .failed
    }
    var mark: String {
        switch self {
        case .done: return "✓"
        case .failed: return "✗"
        case .partial: return "◐"
        case .unknown: return "?"
        }
    }
}

struct LedgerEntry: Codable, Equatable {
    var id: String          // the order's number and its chat
    var messageId: String
    var app: String
    var type: Int
    var label: String
    var chat: String
    var what: String        // its words, the first 60 characters
    var contentKey: String  // app, type, chat and the order as sent: the same order sent again has the same key
    var received: Double
    var finished: Double?
    var outcome: OrderOutcome?
    var reason = ""
    var evidence: String?   // Documents/ledger/<file>: the screen when it did not go
}

@MainActor enum OrderLedger {
    nonisolated static let keep = 500
    static let alikeWindow = 1800.0  // 30 minutes
    static var entries: [LedgerEntry] = load()
    /// The screen when an order did not go (the watch sets it: its live frame).
    static var evidence: (() -> Data?)?
    /// Off in unit tests: nothing written to Documents.
    static var writes = true

    nonisolated static var file: URL { documents.appendingPathComponent("ledger.jsonl") }
    nonisolated static var folder: URL { documents.appendingPathComponent("ledger", isDirectory: true) }
    private nonisolated static var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func entryID(_ c: ChatToolLink.Command) -> String { c.key + "|" + c.chat }
    static func contentKey(_ c: ChatToolLink.Command) -> String { "\(c.app.rawValue)|\(c.type)|\(c.chat)|\(canonical(c.raw))" }

    /// An order's JSON with its keys sorted: the same order sent twice reads the same, whatever order its fields came in.
    nonisolated static func canonical(_ raw: String) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return raw }
        return text
    }

    nonisolated static func load() -> [LedgerEntry] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return Array(text.split(separator: "\n").compactMap { try? decoder.decode(LedgerEntry.self, from: Data($0.utf8)) }.suffix(keep))
    }

    private static func save() {
        guard writes else { return }
        let encoder = JSONEncoder()
        let lines = entries.suffix(keep).compactMap { (try? encoder.encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// An order queued: its line (once).
    static func received(_ c: ChatToolLink.Command, label: String, now t: Double) {
        let id = entryID(c)
        guard !entries.contains(where: { $0.id == id }) else { return }
        let words = [c.text, c.quote].filter { !$0.isEmpty }.joined(separator: " / ")
        entries.append(LedgerEntry(id: id, messageId: c.messageId, app: c.app.rawValue, type: c.type, label: label, chat: c.chat,
                                   what: String(words.prefix(60)), contentKey: contentKey(c), received: t))
        if entries.count > keep { entries.removeFirst(entries.count - keep) }
        save()
    }

    /// An order ended: how, why, and (not done) the screen then.
    static func finished(_ c: ChatToolLink.Command, outcome: OrderOutcome, reason: String, now t: Double) {
        guard let i = entries.lastIndex(where: { $0.id == entryID(c) }) else { return }
        entries[i].finished = t
        entries[i].outcome = outcome
        entries[i].reason = String(reason.prefix(200))
        if outcome != .done, writes, let jpeg = evidence?() {
            let tag = String(entries[i].messageId.filter { $0.isLetter || $0.isNumber }.suffix(12))
            let name = "\(Int(t))-\(tag).jpg"
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? jpeg.write(to: folder.appendingPathComponent(name))) != nil { entries[i].evidence = name }
            pruneEvidence()
        }
        save()
    }

    /// Pictures kept for the lines kept, at most 100.
    private static func pruneEvidence() {
        let kept = Set(entries.compactMap(\.evidence).suffix(100))
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for n in names where !kept.contains(n) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(n)) }
    }

    /// The same risky order (another number, the same chat and words) done, half done or not known how it ended — or
    /// still going — in the last 30 minutes; nil when there is none.
    static func alike(_ c: ChatToolLink.Command, now t: Double) -> LedgerEntry? {
        guard RiskPace.types.contains(c.type) else { return nil }
        let key = contentKey(c)
        return entries.last { e in
            e.contentKey == key && e.messageId != c.messageId && t - e.received < alikeWindow && e.outcome != .failed
        }
    }

    /// The newest lines, newest first, as words for the 守候 page and the test channel.
    static func lines(_ n: Int = 50) -> [String] {
        entries.suffix(n).reversed().map { e in
            let when = DateFormatter.localizedString(from: Date(timeIntervalSince1970: e.received), dateStyle: .none, timeStyle: .medium)
            let took = e.finished.map { String(format: " %.0fs", $0 - e.received) } ?? " …"
            return "\(e.outcome?.mark ?? "…") \(when) \(e.label) · \(e.chat)\(took)" + (e.reason.isEmpty ? "" : "：\(e.reason)")
                + (e.evidence.map { " [\($0)]" } ?? "")
        }
    }
}

/// 199 (the kernel's 「设备占用 排队等候」「令牌持锁」): the iPad is one hand's at a time. A gesture by hand (the test
/// channel) holds it for 20 s; the watch parks between its steps meanwhile, and the gesture waits for that (8 s at most).
@MainActor enum DeviceLock {
    static var handUntil = 0.0
    static var parked = false
    static var heldByHand: Bool { Date().timeIntervalSince1970 < handUntil }
    static func hand(_ seconds: Double = 20) { handUntil = Date().timeIntervalSince1970 + seconds }
}

/// 199 (Echo 198 11-28 18:36: a group made and renamed right after a run of orders, then WeChat on the iPad logged out
/// and asked for its QR code — as on 197 at 02:09, pulling people in): the risky orders of an app — groups, people,
/// forwards, friends — one at a time, a random 45–120 s apart, at most 8 an hour. One not due yet waits in the queue
/// (the orders after it go on); it is not a failure.
@MainActor enum RiskPace {
    static let types: Set<Int> = [205, 206, 207, 212, 213, 219, 220, 225, 227, 228, 234, 236, 241, 243]
    static let perHour = 8
    static let gap: ClosedRange<Double> = 45...120
    static var began: [String: [Double]] = [:]
    static var nextAt: [String: Double] = [:]

    static func due(_ c: ChatToolLink.Command, at t: Double) -> Bool {
        guard types.contains(c.type) else { return true }
        let k = c.app.rawValue
        return t >= (nextAt[k] ?? 0) && (began[k] ?? []).filter({ t - $0 < 3600 }).count < perHour
    }

    static func start(_ c: ChatToolLink.Command, at t: Double, random: (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        guard types.contains(c.type) else { return }
        let k = c.app.rawValue
        began[k] = (began[k] ?? []).filter { t - $0 < 3600 } + [t]
        nextAt[k] = t + random(gap)
    }
}
