import Foundation

/// The model prompts, kept as plain text in the repository's `prompts/` folder (bundled with the app) so they
/// can be read and tuned without touching Swift. actor/planner = the shared rules + the app-only rules.
///
/// No rebuild needed to change them on the phone: a file dropped into this app's Documents folder (Files ›
/// On My iPhone › the app) wins. `prompts/<name>.md` replaces a bundled prompt at the next app launch;
/// `rules.md` is appended to the planner and the actor on every run.
enum Prompts {
    static let planner = load("planner")
    static let actorServer = load("actor")
    static let appRules = load("app-rules")

    static let actor = actorServer + "\n" + appRules
    static let plannerApp = planner + "\n" + appRules

    private static var documents: URL? { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first }

    /// One prompt: Documents/prompts/<name>.md when present and not empty, else the bundled file; without the
    /// file's final newline.
    static func load(_ name: String) -> String {
        if let url = documents?.appendingPathComponent("prompts/\(name).md"),
           let text = try? String(contentsOf: url, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.hasSuffix("\n") ? String(text.dropLast()) : text
        }
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("prompts/\(name).md is missing from the app bundle")
        }
        return text.hasSuffix("\n") ? String(text.dropLast()) : text
    }

    /// Documents/rules.md, read fresh for every prompt ("" when absent), at most 8000 characters.
    static var userRules: String {
        guard let url = documents?.appendingPathComponent("rules.md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        let rules = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return rules.isEmpty ? "" : "\n\nRules from the user (rules.md). Follow them:\n" + String(rules.prefix(8000))
    }
}
