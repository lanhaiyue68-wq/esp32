import Foundation

/// 202 (user 11-28: 「跟圈、爬樓…你要能記住你爬的東西…你不能光爬呀，到最後啥也沒記住啊」; 201 sent what 515 read to
/// the server and kept only where to stop): every line a climb (515) or a friend's 朋友圈 (260) read kept on the iPad,
/// in Documents/reads.jsonl — each once (a line read again is not added twice), the newest 5000 — shown on 小藍's
/// 指令記錄 page and over the test channel.
struct ReadItem: Codable, Equatable {
    var kind: String     // 爬楼 or 跟圈
    var app: String
    var place: String    // the chat climbed, the friend whose 朋友圈 was read
    var key: String      // what makes it the same line next time
    var readAt: Double
    var time: String     // when it was said or posted, as shown
    var sender: String
    var text: String
}

@MainActor enum ReadStore {
    nonisolated static let keep = 5000
    static var items: [ReadItem] = load()
    /// Off in unit tests: nothing written to Documents.
    static var writes = true

    nonisolated static var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("reads.jsonl")
    }

    nonisolated static func load() -> [ReadItem] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return Array(text.split(separator: "\n").compactMap { try? decoder.decode(ReadItem.self, from: Data($0.utf8)) }.suffix(keep))
    }

    private static func id(_ i: ReadItem) -> String { [i.kind, i.app, i.place, i.key].joined(separator: "|") }

    /// The items not kept yet added; how many were new.
    @discardableResult static func add(_ new: [ReadItem]) -> Int {
        var known = Set(items.map(id))
        var added: [ReadItem] = []
        for i in new where !i.text.isEmpty && known.insert(id(i)).inserted { added.append(i) }
        guard !added.isEmpty else { return 0 }
        items += added
        if items.count > keep { items.removeFirst(items.count - keep) }
        if writes {
            let encoder = JSONEncoder()
            let lines = items.compactMap { (try? encoder.encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
            try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        return added.count
    }

    /// The newest kept lines as words, newest first.
    static func lines(_ n: Int = 40) -> [String] {
        items.suffix(n).reversed().map { i in
            "\(i.kind) · \(i.place)" + (i.time.isEmpty ? "" : " · \(i.time)") + "｜\(i.sender)：\(i.text.prefix(80))"
        }
    }
}
