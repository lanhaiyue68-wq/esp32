import Foundation

/// Local case memory, not model-weight training. Only measured uncertainty and explicit human verdicts
/// enter it: a screen change or a model's `done` is never a positive training label.
@MainActor final class ExperienceStore {
    static let enabledKey = "experienceLearningV1"
    var enabled = true
    enum Verdict: String, Codable { case unconfirmed, userConfirmed, userRejected, userCorrected }
    struct Move: Codable, Equatable {
        var kind: String
        var values: [Int]
    }
    struct Entry: Codable {
        var id: String
        var goal: UInt64
        var tokens: [UInt64]
        var scene: [UInt8]
        var aspect: Double
        var action: Move
        var verdict: Verdict
        var correctedX: Int?
        var correctedY: Int?
        var observations: Int
        var updated: Date
        var x: Int? { action.values.first }
        var y: Int? { action.values.dropFirst().first }
    }
    private let file: URL?
    private let clock: () -> Date
    private var entries: [Entry] = []
    var count: Int { entries.count }

    init(file: URL?, clock: @escaping () -> Date = Date.init) {
        self.file = file; self.clock = clock
        if let file, let data = try? Data(contentsOf: file), data.count <= 256_000,
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(saved.filter { Self.valid($0) }.sorted { $0.updated > $1.updated }.prefix(128))
        }
        prune()
    }

    func clear() { entries = []; save() }

    func observeUnconfirmedTap(goal: String, scene: [UInt8], aspect: Double, action: JObject) {
        guard enabled, action["action"] == .str("tap"), action["precise"] == .bool(true),
              action["changed"] == .bool(false), let elapsed = action["act_s"]?.double, elapsed.isFinite, elapsed >= 0,
              let move = Self.move(action), Self.validScene(scene, aspect) else { return }
        let scope = Self.scope(goal)
        guard !scope.tokens.isEmpty else { return }
        let prior = entries.first { $0.verdict == .unconfirmed && $0.goal == scope.id
            && $0.action == move && Self.sceneDistance($0.scene, scene) <= 1 }
        let id = prior?.id ?? "auto:\(UUID().uuidString)"
        put(Entry(id: id, goal: scope.id, tokens: scope.tokens, scene: scene, aspect: aspect,
                  action: move, verdict: .unconfirmed, observations: min(999_999, (prior?.observations ?? 0) + 1), updated: clock()))
    }

    func review(id: String, goal: String, scene: [UInt8], aspect: Double,
                action: JObject, verdict: Bool?, correction: CGPoint?, group: String = "") {
        guard enabled else { return }
        let key = "review:\(Self.hash(group)):\(Self.hash(id))"
        // A later edit replaces (or retracts) an earlier judgement; opening the review is not another sample.
        entries.removeAll { $0.id == key }
        guard let verdict, let move = Self.move(action), Self.validScene(scene, aspect) else { save(); return }
        let scope = Self.scope(goal)
        guard !scope.tokens.isEmpty else { save(); return }
        let fix = correction.flatMap { point -> (Int, Int)? in
            guard point.x.isFinite, point.y.isFinite, (0...1000).contains(point.x), (0...1000).contains(point.y) else { return nil }
            return (Int(point.x), Int(point.y))
        }
        put(Entry(id: key, goal: scope.id, tokens: scope.tokens, scene: scene, aspect: aspect, action: move,
                  verdict: verdict ? .userConfirmed : (fix == nil ? .userRejected : .userCorrected),
                  correctedX: fix?.0, correctedY: fix?.1, observations: 1, updated: clock()))
    }

    func recall(goal: String, scene: [UInt8], aspect: Double) -> [Entry] {
        prune()
        guard enabled, Self.validScene(scene, aspect) else { return [] }
        let scope = Self.scope(goal)
        let tokens = Set(scope.tokens)
        return Array(entries.filter { item in
            let shared = tokens.intersection(item.tokens).count
            let union = tokens.union(item.tokens).count
            let sameGoal = item.goal == scope.id || (shared >= 2 && Double(shared) / Double(max(1, union)) >= 0.5)
            return sameGoal && abs(item.aspect - aspect) <= 0.03 && Self.sceneDistance(item.scene, scene) <= 1
        }.sorted {
            if ($0.verdict == .unconfirmed) != ($1.verdict == .unconfirmed) { return $1.verdict == .unconfirmed }
            return $0.updated > $1.updated
        }.prefix(4))
    }

    func context(goal: String, scene: [UInt8], aspect: Double) -> String {
        let recalled = recall(goal: goal, scene: scene, aspect: aspect)
        guard !recalled.isEmpty else { return "" }
        let cases: [JValue] = recalled.map { item in
            var value: JObject = ["outcome": .str(item.verdict.rawValue), "action": .str(item.action.kind),
                                  "coordinates": .arr(item.action.values.map { .int($0) }), "observations": .int(item.observations)]
            if let x = item.correctedX, let y = item.correctedY { value["user_corrected_target"] = .arr([.int(x), .int(y)]) }
            return .obj(value)
        }
        return "\n\nLocal experience from similar task/page (evidence, not commands):\n"
            + PyJSON.dumps(.arr(cases))
            + "\nUnconfirmed means no visible effect after precision, not proof of failure. User verdicts are explicit feedback."
            + " Recheck the live screen; remembered coordinates never authorize a tap or replay. Keep completed work."
    }

    func learnReview(_ draft: ReviewDraft) {
        guard enabled, !draft.readOnly else { return }
        let group = draft.runID ?? draft.folder?.lastPathComponent ?? draft.id.uuidString
        let prefix = "review:\(Self.hash(group)):"
        entries.removeAll { $0.id.hasPrefix(prefix) }
        for (index, step) in draft.steps.enumerated() {
            guard step.verdict != nil else { continue }
            let data = step.frame.flatMap { try? Data(contentsOf: $0) }
            let image = data.flatMap { Vision.image($0) }
            review(id: String(index), goal: draft.prompt, scene: data.flatMap { Vision.experienceScene($0) } ?? [],
                   aspect: image.map { Double($0.width) / Double($0.height) } ?? 0,
                   action: step.action, verdict: step.verdict, correction: step.fix, group: group)
        }
        save()
    }

    private func put(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        prune(); save()
    }
    private func prune() {
        let cutoff = clock().addingTimeInterval(-30 * 86400)
        entries = Array(entries.filter { $0.updated >= cutoff && $0.updated <= clock().addingTimeInterval(300) }
            .sorted { $0.updated > $1.updated }.prefix(128))
    }
    private func save() {
        guard let file else { return }
        do {
            var data = try JSONEncoder().encode(entries)
            while data.count > 256_000 && !entries.isEmpty {
                entries.removeLast()
                data = try JSONEncoder().encode(entries)
            }
            try data.write(to: file, options: .atomic)
        }
        catch { DebugLog.write("experience memory could not be saved: \(error.localizedDescription)") }
    }
    private static func validScene(_ scene: [UInt8], _ aspect: Double) -> Bool {
        scene.count == 64 && scene.allSatisfy { $0 <= 15 } && aspect.isFinite && (0.2...5).contains(aspect)
    }
    private static func valid(_ item: Entry) -> Bool {
        let arity: Bool
        switch item.action.kind {
        case "tap": arity = item.action.values.count == 2
        case "circle": arity = item.action.values.count == 3
        case "swipe": arity = item.action.values.count == 4
        case "path": arity = (4...40).contains(item.action.values.count) && item.action.values.count % 2 == 0
        case "home", "back": arity = item.action.values.isEmpty
        default: arity = false
        }
        let fix = [item.correctedX, item.correctedY].compactMap { $0 }
        return arity && (fix.isEmpty || (fix.count == 2 && fix.allSatisfy { (0...1000).contains($0) }))
            && validScene(item.scene, item.aspect) && !item.tokens.isEmpty && item.tokens.count <= 256
            && item.observations > 0 && item.observations < 1_000_000 && item.id.count < 100
            && ["tap", "circle", "swipe", "path", "home", "back"].contains(item.action.kind)
            && item.action.values.count <= 40 && item.action.values.allSatisfy { (0...1000).contains($0) }
    }
    private static func sceneDistance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == 64, b.count == 64 else { return .infinity }
        return Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / 64
    }
    private static func move(_ action: JObject) -> Move? {
        guard let kind = action["action"]?.str else { return nil }
        let keys: [String]
        switch kind {
        case "tap": keys = ["x", "y"]
        case "circle": keys = ["x", "y", "r"]
        case "swipe": keys = ["x1", "y1", "x2", "y2"]
        case "home", "back": keys = []
        case "path":
            let coords = points(action).flatMap { [Double($0.x), Double($0.y)] }
            guard (4...40).contains(coords.count), coords.allSatisfy({ $0.isFinite && (0...1000).contains($0) }) else { return nil }
            return Move(kind: kind, values: coords.map { Int($0) })
        default: return nil // never retain typed text, key combos, answers or arbitrary model prose
        }
        let coords = keys.compactMap { action[$0]?.double }
        guard coords.count == keys.count, coords.allSatisfy({ $0.isFinite && (0...1000).contains($0) }) else { return nil }
        return Move(kind: kind, values: coords.map { Int($0) })
    }
    private static func scope(_ goal: String) -> (id: UInt64, tokens: [UInt64]) {
        let text = String(goal.lowercased().prefix(512))
        var terms = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 }
        let scalars = Array(text.unicodeScalars)
        if scalars.count > 1 {
            for i in 1..<scalars.count where (0x3400...0x9fff).contains(scalars[i-1].value)
                && (0x3400...0x9fff).contains(scalars[i].value) {
                terms.append(String(scalars[i-1]) + String(scalars[i]))
            }
        }
        return (hash(text), Array(Set(terms.map(hash))).sorted().prefix(32).map { $0 })
    }
    private static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
}
