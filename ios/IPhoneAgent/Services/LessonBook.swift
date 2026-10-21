import Foundation

/// What the user taught in Review, kept as their own sentences and handed to the planner and the actor on
/// every later run of a similar task, whatever app it is in. One wrong run is fine; the same mistake twice
/// is not. Human lessons: step notes, steps the user added, accepted AI hints. A note that starts with
/// "通用：", "通用:", "always:" or "全部：" applies to every task.
///
/// Self-learned lessons: after every run the model reviews its own steps (`reflectionPrompt`) and keeps at
/// most three concrete lessons drawn from evidence (no screen change, retries, replans, errors, the route
/// that worked), never a claim that the task succeeded. They rank below the human ones, and marking a step
/// of that run wrong in Review drops them: the user's correction replaces what the model believed.
/// A lesson learned again is not stored twice: the kept one is reinforced (`seen`). At the cap, the self-learned
/// lessons that no run has used or re-learned for longest go first, not simply the oldest.
@MainActor final class LessonBook {
    struct Lesson: Codable, Equatable {
        var id: String      // "<run>:review:<step>", "<run>:hint:<n>", "<run>:auto:<n>": re-learning a run replaces them
        var task: String
        var text: String
        var general: Bool
        var updated: Date
        var auto: Bool?     // self-learned; nil in files from before self-learning
        var used: Date? = nil      // when a run was last given it
        var seen: Int? = nil       // how many runs drew it (nil = 1)
        var from: [String]? = nil  // the runs (groups) that drew it; correcting any of them drops it
    }

    static let limit = 200
    private let file: URL?
    private let clock: () -> Date
    private(set) var lessons: [Lesson] = []
    var enabled = true
    var count: Int { lessons.count }

    init(file: URL?, clock: @escaping () -> Date = Date.init) {
        self.file = file; self.clock = clock
        if let file, let data = try? Data(contentsOf: file), data.count <= 512_000,
           let saved = try? JSONDecoder().decode([Lesson].self, from: data) {
            lessons = Array(saved.sorted { $0.updated > $1.updated }.prefix(Self.limit))
        }
    }

    func clear() { lessons = []; save() }

    /// Replace everything learned from one run (`group`, usually the run ID) with `items` (id suffix, text).
    func learn(group: String, task: String, items: [(String, String)], auto: Bool = false) {
        guard enabled, !group.isEmpty else { return }
        lessons.removeAll { $0.id.hasPrefix(group + ":") }
        for (key, raw) in items {
            let (text, general) = auto ? (raw.trimmingCharacters(in: .whitespacesAndNewlines), false) : Self.parse(raw)
            guard !text.isEmpty else { continue }
            let clipped = String(text.prefix(400))
            if auto, let i = lessons.firstIndex(where: { Self.sameLesson($0.text, clipped) }) {
                // Learned again, or the user already said it: reinforce the kept one instead of storing a copy.
                guard lessons[i].auto == true, !(lessons[i].from ?? []).contains(group) else { continue }  // or this run said it twice
                lessons[i].text = clipped  // the latest wording
                lessons[i].updated = clock()
                lessons[i].seen = (lessons[i].seen ?? 1) + 1
                var runs = lessons[i].from ?? []
                if !runs.contains(group) { runs.append(group) }
                lessons[i].from = runs
                continue
            }
            lessons.insert(Lesson(id: "\(group):\(key)", task: task, text: clipped, general: general,
                                  updated: clock(), auto: auto ? true : nil, from: auto ? [group] : nil), at: 0)
        }
        // Self-learned lessons never crowd out the user's: at most autoLimit of them. Those kept are the ones a run
        // used or learned again most recently, so a lesson that keeps helping outlives one that never came up.
        let autos = lessons.filter { $0.auto == true }
        if autos.count > Self.autoLimit {
            let keep = Set(autos.sorted(by: Self.fresher).prefix(Self.autoLimit).map(\.id))
            lessons.removeAll { $0.auto == true && !keep.contains($0.id) }
        }
        lessons = Array(lessons.prefix(Self.limit))
        save()
    }

    static let autoLimit = 60

    /// The lessons a run was given: they count as in use, so the cap drops the ones nobody needs any more first.
    func markUsed(_ picked: [Lesson]) {
        let ids = Set(picked.map(\.id))
        guard enabled, !ids.isEmpty else { return }
        let t = clock()
        for i in lessons.indices where ids.contains(lessons[i].id) { lessons[i].used = t }
        save()
    }

    /// Most recently learned, re-learned or used first; then the most often learned.
    static func fresher(_ a: Lesson, _ b: Lesson) -> Bool {
        let (ta, tb) = (max(a.updated, a.used ?? .distantPast), max(b.updated, b.used ?? .distantPast))
        return ta != tb ? ta > tb : (a.seen ?? 1) > (b.seen ?? 1)
    }

    /// The same lesson in slightly other words: character pairs without spaces and punctuation, mostly shared.
    /// A changed comma or a word more is recognised; lessons about different things stay apart.
    static func sameLesson(_ a: String, _ b: String) -> Bool {
        func pairs(_ s: String) -> Set<String> {
            let c = Array(s.lowercased().filter { $0.isLetter || $0.isNumber })
            return c.count < 2 ? Set([String(c)]) : Set((0..<(c.count - 1)).map { String(c[$0...$0 + 1]) })
        }
        let (x, y) = (pairs(a), pairs(b))
        guard !x.isEmpty, !y.isEmpty, x != [""], y != [""] else { return false }
        return Double(x.intersection(y).count) / Double(x.union(y).count) >= 0.7
    }

    /// The user's notes and added steps in a reviewed run.
    func learnReview(_ draft: ReviewDraft) {
        guard !draft.readOnly, let run = draft.runID else { return }
        var items: [(String, String)] = []
        for step in draft.steps {
            let what = StepText.title(step.action)
            if step.inserted, let text = step.action["text"]?.str, !text.isEmpty {
                items.append((step.id.uuidString, text))
            } else if !step.note.isEmpty {
                items.append((step.id.uuidString, step.verdict == false ? "\(step.note)（上次在“\(what)”这一步做错了）" : step.note))
            }
        }
        learn(group: run + ":review", task: draft.prompt, items: items)
        if draft.steps.contains(where: { $0.verdict == false }) {
            forget(group: run + ":auto")  // the user corrected this run: what the model drew from it may be wrong
        }
    }

    func forget(group: String) {
        let before = lessons.count
        lessons.removeAll { $0.id.hasPrefix(group + ":") || ($0.from ?? []).contains(group) }
        if lessons.count != before { save() }
    }

    // MARK: - self-learning

    static let reflectionPrompt = """
    You review one finished run of an AI agent that operates an iPhone with a mouse pointer, so that it never makes \
    the same mistake twice. Find the deviations in the steps: a tap or gesture that did not change the screen, a \
    wrong target, steps that had to be repeated, undone or replanned, stale or failed actions, errors, requests for \
    help, a result that was not the agent's own work. For each, write the correction for next time, in the form \
    "<app> <screen or control>: do not <what went wrong>; instead <what to do>". When the run itself fixed the \
    mistake later, the "instead" part is the fix that worked. Never turn a mistake into a rule: a lesson must not \
    tell the agent to repeat what went wrong. Never state that the task succeeded or looked right: the agent's own \
    "done" is not proof. Do not invent screens or buttons that are not in the steps. If there was no deviation, \
    you may keep one lesson about the route through the apps that worked. Write in the language of the task, at \
    most 3 lessons, one line each, starting with "LESSON:"; reply NONE if nothing reliable can be learned.
    """

    /// The run as text for the reviewer: actions without the plan, short thoughts, what changed and why it stopped.
    static func reflectionInput(task: String, steps: [JObject]) -> String {
        var lines = ["Task: \(task)", "Steps:"]
        for (i, s) in steps.suffix(40).enumerated() {
            var line = "\(i + 1). " + PyJSON.dumps(Actions.key(s).without(["plan", "plan_zh"]), ascii: false)
            if let t = s["thought"]?.str { line += " (thought: \(t.prefix(150)))" }
            if s["changed"]?.bool == false { line += " (screen did not change)" }
            if let r = s["reason"]?.str, !r.isEmpty { line += " (reason: \(r.prefix(150)))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    static func parseLessons(_ reply: String) -> [String] {
        let lessons = reply.split(separator: "\n").compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("LESSON:") else { return nil }
            let text = line.dropFirst(7).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return Array(lessons.prefix(3))
    }

    /// After a run: keep what the model learned from its own steps (replacing an earlier review of the same run).
    func learnFromRun(_ run: String, task: String, lessons found: [String]) {
        learn(group: run + ":auto", task: task, items: found.enumerated().map { ("\($0.offset)", $0.element) }, auto: true)
    }

    /// Accepted "Optimize with AI" hints: they now reach every similar task, saved as an intent or not.
    func learnHints(_ hints: [String], task: String, run: String?) {
        learn(group: (run ?? "hints") + ":hint", task: task, items: hints.enumerated().map { ("\($0.offset)", $0.element) })
    }

    /// Lessons for this task: the user's (general ones first, then the most similar tasks', newest first among
    /// equals), then at most four self-learned ones.
    func relevant(to task: String, max: Int = 10) -> [Lesson] {
        guard enabled else { return [] }
        return ranked(task, lessons.filter { $0.auto != true }, max: max) + ranked(task, lessons.filter { $0.auto == true }, max: 4)
    }

    private func ranked(_ task: String, _ pool: [Lesson], max: Int) -> [Lesson] {
        let words = Self.tokens(task)
        let scored = pool.compactMap { l -> (Lesson, Int)? in
            if l.general { return (l, 1000) }
            let shared = words.intersection(Self.tokens(l.task)).count
            let need = Swift.max(2, Swift.min(words.count, Self.tokens(l.task).count) / 3)
            return shared >= need ? (l, shared) : nil
        }
        var seen = Set<String>(), out: [Lesson] = []
        for (l, _) in scored.sorted(by: { $0.1 != $1.1 ? $0.1 > $1.1 : Self.fresher($0.0, $1.0) })
        where seen.insert(l.text).inserted {
            out.append(l)
            if out.count == max { break }
        }
        return out
    }

    /// Appended to the planner's and the actor's system prompts.
    func context(task: String) -> String {
        let picked = relevant(to: task)
        let human = picked.filter { $0.auto != true }, own = picked.filter { $0.auto == true }
        var out = ""
        if !human.isEmpty {
            out += "\n\nLessons from this user's corrections of earlier runs. Follow them; they override your habits:\n"
                + human.map { "- " + $0.text }.joined(separator: "\n")
        }
        if !own.isEmpty {
            out += "\n\nLessons you drew from your own earlier runs of similar tasks (less certain; the user's lessons win):\n"
                + own.map { "- " + $0.text }.joined(separator: "\n")
        }
        return out
    }

    /// Chinese/Japanese as character pairs, other scripts as lowercased words.
    static func tokens(_ s: String) -> Set<String> {
        var out = Set<String>(), run: [Character] = [], runIsCJK = false
        func flush() {
            if runIsCJK {
                if run.count == 1 { out.insert(String(run)) }
                for i in 0..<Swift.max(0, run.count - 1) { out.insert(String(run[i...i + 1])) }
            } else if run.count > 1 {
                out.insert(String(run).lowercased())
            }
            run = []
        }
        for ch in s {
            let cjk = ch.unicodeScalars.contains { (0x3040...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
            guard cjk || ch.isLetter || ch.isNumber else { flush(); continue }
            if !run.isEmpty && cjk != runIsCJK { flush() }
            runIsCJK = cjk
            run.append(ch)
        }
        flush()
        return out
    }

    static func parse(_ raw: String) -> (String, Bool) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for mark in ["通用：", "通用:", "全部：", "全部:", "always:", "Always:"] where text.hasPrefix(mark) {
            return (String(text.dropFirst(mark.count)).trimmingCharacters(in: .whitespaces), true)
        }
        return (text, false)
    }

    private func save() {
        guard let file else { return }
        try? JSONEncoder().encode(lessons).write(to: file, options: .atomic)
    }
}
