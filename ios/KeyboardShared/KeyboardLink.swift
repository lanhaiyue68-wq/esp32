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
}
