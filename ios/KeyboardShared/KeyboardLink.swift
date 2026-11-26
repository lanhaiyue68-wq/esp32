import Foundation

/// The line protocol between Lan Agent and its keyboard (LanAgentKeyboard) over 127.0.0.1. No App Group: the app is
/// installed through 全能簽, whose re-signing does not carry one. One short TCP exchange per request:
///   keyboard → app  `HELLO 1` (full access on) · `NEXT` (anything to type?) · `DONE <id> 1` (typed it)
///   app → keyboard  one line of JSON `{"id":…,"text":…,"enter":…}` for NEXT, else `OK` / `NONE`
enum KeyboardLink {
    static let port: UInt16 = 47_820

    /// Text the keyboard should put into the focused field; `enter` adds a return after it (WeChat sends on return).
    struct Job: Codable, Equatable {
        var id: String
        var text: String
        var enter: Bool
        /// 185 (B10, Echo 184, 11-26: on the iPad a tap on WeChat's chat background never put 小藍 down): the keyboard
        /// puts itself down after the job (dismissKeyboard). Absent in older apps' jobs.
        var dismiss: Bool? = nil
    }

    enum Request: Equatable {
        case hello(fullAccess: Bool)
        case next
        case done(id: String, ok: Bool)
    }

    static func line(_ request: Request) -> String {
        switch request {
        case .hello(let full): return "HELLO \(full ? 1 : 0)\n"
        case .next: return "NEXT\n"
        case .done(let id, let ok): return "DONE \(id) \(ok ? 1 : 0)\n"
        }
    }

    static func request(_ line: String) -> Request? {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").map(String.init)
        switch parts.first {
        case "HELLO" where parts.count == 2: return .hello(fullAccess: parts[1] == "1")
        case "NEXT" where parts.count == 1: return .next
        case "DONE" where parts.count == 3 && !parts[1].isEmpty: return .done(id: parts[1], ok: parts[2] == "1")
        default: return nil
        }
    }

    static func line(_ job: Job?) -> String {
        guard let job, let data = try? JSONEncoder().encode(job), let json = String(data: data, encoding: .utf8)
        else { return "NONE\n" }
        return json + "\n"
    }

    static func job(_ line: String) -> Job? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Job.self, from: data)
    }

    /// 185: how long after the text its return goes (Echo 184, 11-26: at once, WeChat took it for a new line and sent
    /// nothing; 183's ~0.8 s sent), and how long after the return the field is looked at again.
    static let returnDelay = 0.8
    static let sentCheckDelay = 0.35
    /// 188 (B41): the field is looked at again this often, for this long after the return, before "not sent".
    static let sentCheckEvery = 0.15, sentCheckWindow = 1.5

    /// 185: after the return, the field still holds `text` (a new line after it at most): it was not sent.
    static func stillHolds(_ text: String, before: String?) -> Bool {
        var b = before ?? ""
        while b.hasSuffix("\n") || b.hasSuffix(" ") { b.removeLast() }
        guard !b.isEmpty else { return false }
        if b.hasSuffix(text) { return true }
        return text.hasSuffix(b) && b.count >= min(text.count, 8)
    }

    /// 185: the field holds exactly `text` (what it shows before and after the cursor). A field that shows nothing at
    /// all around the cursor (the app gives no context) counts as holding it: sent as before. Anything else there, words
    /// dictated into it (iOS 语音控制, 11-26) or left from before, and it is not sent.
    static func fieldMatches(_ text: String, before: String?, after: String?) -> Bool {
        let b = before ?? "", a = after ?? ""
        if b.isEmpty && a.isEmpty { return true }
        guard a.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // iOS may hand only the end of a long field (its last sentence): that end being this text's end is enough.
        if text.hasSuffix(b) { return b.count >= min(text.count, 8) }
        guard b.hasSuffix(text) else { return false }
        return b.dropLast(text.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
