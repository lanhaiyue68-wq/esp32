import CoreGraphics
import Foundation

/// Learned routes: the navigation a finished run took, replayed on the next similar task without asking the model.
/// Lessons only add advice to the prompt, so every run still looked and thought at each step and nothing got faster
/// (logs43–46). A route keeps the taps, swipes, Home and Back up to the first typing: a replay never types, sends or
/// draws. Each step remembers the screen it was taken on and, for a tap, the text label under it, so the replay taps
/// that label where it is now and stops at the first screen that differs; the model carries on from there.
/// Local only: short screen labels (app and chat names) and coarse screen signatures, never screenshots.
@MainActor final class RouteBook: ObservableObject {
    struct Step: Codable, Equatable {
        var action: String                 // tap, swipe, home, back
        var values: [Int]                  // screen coordinates, 0-1000
        var scene: [UInt8]                 // Vision.experienceScene of the screen the step was taken on
        var anchor: String?                // the text label under a tap
        var offsetX: Int?, offsetY: Int?   // the tap minus the label's centre, 0-1000
    }
    struct Route: Codable, Equatable {
        var id: String
        var task: String
        var aspect: Double
        var steps: [Step]
        var successes: Int
        var misses: Int
        var updated: Date
    }

    static let limit = 64
    static let maxSteps = 12
    /// Labels a replay never taps: what they do cannot be undone or costs money.
    static let unsafeLabels = ["发送", "付款", "支付", "转账", "红包", "删除", "购买", "确认支付", "退出群聊",
                               "send", "pay", "delete", "buy", "purchase"]

    @Published private(set) var routes: [Route] = []
    /// The whole way a finished run did its task, as short lines ("open 时钟", "tap “+”", "type “0800”"), for the next
    /// similar task: the executor follows it instead of finding the way again, and the planner is not asked (user
    /// 11-08: "做完之後記住做的路徑，下次就可以快速做出來"). Unlike a route it goes past typing; it is never replayed
    /// blind, the model reads it and still looks at each screen. Local only, like the routes.
    struct Recipe: Codable, Equatable {
        var task: String
        var lines: [String]
        var updated: Date
    }
    @Published private(set) var recipes: [Recipe] = []
    static let recipeLines = 30
    var enabled = true
    var clock: () -> Date = Date.init
    private let file: URL?

    init(file: URL?) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Route].self, from: data) {
            routes = saved.filter { !$0.steps.isEmpty }
        }
        if let recipeFile, let data = try? Data(contentsOf: recipeFile), let saved = try? JSONDecoder().decode([Recipe].self, from: data) {
            recipes = saved
        }
        prune()
    }

    var count: Int { routes.count }
    func clear() { routes = []; recipes = []; save() }
    private var recipeFile: URL? { file?.deletingLastPathComponent().appendingPathComponent("recipes-v1.json") }

    /// The way the newest similar task was done. An app the old task named must be named by this one too ("go to Claude"
    /// is not the way into ChatGPT). A chat or a label it named and this one does not is the same way to another place
    /// (user 11-10: "方法都是一样的，只是换了个群"): the old name is taken out, so a reply to 蓝海乐 cannot follow the way
    /// into 测试群, and the model goes where this goal says.
    func recipe(for task: String) -> Recipe? {
        guard enabled else { return nil }
        prune()
        let wanted = task.lowercased()
        for recipe in recipes where Self.similar(recipe.task, task) {
            let named = recipe.task.lowercased()
            let apps = recipe.lines.filter { $0.hasPrefix("open ") }.map { String($0.dropFirst(5)).lowercased() }
            guard apps.allSatisfy({ !named.contains($0) || wanted.contains($0) }) else { continue }
            let elsewhere = Self.names(in: recipe.lines).filter { !apps.contains($0) && named.contains($0) && !wanted.contains($0) }
            guard !elsewhere.isEmpty else { return recipe }
            var adapted = recipe
            adapted.lines = recipe.lines.map { line in
                elsewhere.reduce(line) { $0.replacingOccurrences(of: $1, with: Self.otherPlace, options: .caseInsensitive) }
            }
            return adapted
        }
        return nil
    }

    static let otherPlace = "[the one this goal names]"

    func storeRecipe(task: String, lines: [String]) {
        guard enabled, !lines.isEmpty else { return }
        let key = String(task.prefix(512))
        recipes.removeAll { Self.similar($0.task, key) }
        recipes.insert(Recipe(task: key, lines: lines, updated: clock()), at: 0)
        prune(); save()
    }

    /// The apps opened and the labels tapped in a recipe, lowercased.
    nonisolated static func names(in lines: [String]) -> [String] {
        lines.compactMap { line -> String? in
            if line.hasPrefix("open ") { return String(line.dropFirst(5)).lowercased() }
            guard line.hasPrefix("tap “"), let end = line.firstIndex(of: "”") else { return nil }
            return String(line[line.index(line.startIndex, offsetBy: 5)..<end]).lowercased()
        }.filter { !$0.isEmpty }
    }

    /// What a gesture was for, from the thought that chose it: "tap 860 936" alone told the executor nothing, and it
    /// typed over the last note instead of starting a new one (over USB, 11-09).
    nonisolated static func purpose(_ step: JObject) -> String {
        guard var thought = step["thought"]?.str?.trimmingCharacters(in: .whitespacesAndNewlines), !thought.isEmpty else { return "" }
        for mark in [", so ", "，所以", "所以", "，先", "; "] {
            if let range = thought.range(of: mark, options: .backwards) { thought = String(thought[range.upperBound...]); break }
        }
        return " (" + thought.prefix(70).replacingOccurrences(of: "\n", with: " ") + ")"
    }

    /// The whole way of a finished run: every action that did something, in order (what changed nothing is left out).
    nonisolated static func recipe(steps: [JObject], shots: [Int: Data],
                                   label: (Data, CGPoint) -> (text: String, centre: CGPoint)?) -> [String]? {
        guard steps.last?["action"]?.str == "done" else { return nil }
        var lines: [String] = []
        for (i, s) in steps.enumerated() where s["changed"] != .bool(false) && s["performed"] != .bool(false) {
            func n(_ k: String) -> Int { Int((s[k]?.double ?? 0).rounded()) }
            switch s["action"]?.str ?? "" {
            case "open": lines.append("open " + (s["app"]?.str ?? ""))
            case "tap":
                if let shot = shots[i], let found = label(shot, CGPoint(x: Double(n("x")) / 1000, y: Double(n("y")) / 1000)),
                   found.text.filter({ !$0.isWhitespace }).count >= 2 {
                    lines.append("tap “\(found.text)”" + purpose(s))
                } else {
                    lines.append("tap \(n("x")) \(n("y"))" + purpose(s))
                }
            case "type": lines.append("type “\(s["text"]?.str ?? "")”")
            case "compose": lines.append("type “\(s["expected"]?.str ?? "")”")
            case "key": lines.append("key " + (s["combo"]?.str ?? ""))
            case "swipe": lines.append("swipe \(n("x1")) \(n("y1")) \(n("x2")) \(n("y2"))" + purpose(s))
            case "circle", "path": lines.append("draw (\(s["action"]?.str ?? ""))")
            case "home", "back", "wait": lines.append(s["action"]?.str ?? "")
            default: break
            }
        }
        return lines.isEmpty ? nil : Array(lines.suffix(recipeLines))
    }

    /// The route for this task that starts on this screen. A label the old task named (an app, a chat) must be named
    /// by this task too: "go to Claude" must not replay into ChatGPT, nor a reply to 蓝海乐 into 测试群.
    func match(task: String, scene: [UInt8], aspect: Double) -> Route? {
        guard enabled else { return nil }
        prune()
        let wanted = task.lowercased()
        return routes.first { route in
            guard let first = route.steps.first, abs(route.aspect - aspect) <= 0.03,
                  Self.sceneDistance(first.scene, scene) <= 1, Self.similar(route.task, task) else { return false }
            let named = route.task.lowercased()
            return route.steps.compactMap(\.anchor).allSatisfy { !named.contains($0.lowercased()) || wanted.contains($0.lowercased()) }
        }
    }

    /// The route for this task and the step to join it at: its start on this screen, or a later step taken on this
    /// screen when this run began further along (logs 11-06: "go to Claude" was learned from inside WeChat, the next
    /// one started on the Home Screen, so it never replayed and the model worked the way out again).
    func entry(task: String, scene: [UInt8], aspect: Double) -> (route: Route, from: Int)? {
        guard enabled else { return nil }
        if let route = match(task: task, scene: scene, aspect: aspect) { return (route, 0) }
        let wanted = task.lowercased()
        for route in routes where abs(route.aspect - aspect) <= 0.03 && Self.similar(route.task, task) {
            let named = route.task.lowercased()
            guard route.steps.compactMap(\.anchor).allSatisfy({ !named.contains($0.lowercased()) || wanted.contains($0.lowercased()) })
            else { continue }
            if let k = route.steps.indices.dropFirst().first(where: { Self.sceneDistance(route.steps[$0].scene, scene) <= 1 }) {
                return (route, k)
            }
        }
        return nil
    }

    /// A finished run: keep its route, and credit the route it replayed.
    func learn(task: String, steps: [JObject], shots: [Int: Data], aspect: Double, replayed: String?,
               recipe: Bool = true) async {
        guard enabled, steps.last?["action"]?.str == "done" else { return }
        if let replayed, let i = routes.firstIndex(where: { $0.id == replayed }) { routes[i].successes += 1 }
        if recipe, let lines = await Task.detached(priority: .utility, operation: {
            Self.recipe(steps: steps, shots: shots, label: CandidatePicker.label)
        }).value {
            storeRecipe(task: task, lines: lines)
        }
        let found = await Task.detached(priority: .utility) {
            Self.route(steps: steps, shots: shots, label: CandidatePicker.label)
        }.value
        guard enabled, let found else { save(); return }
        store(task: task, aspect: aspect, steps: found)
    }

    /// A replay that stopped before its end: after repeated misses with no more successes, it is dropped.
    func missed(_ id: String) {
        guard let i = routes.firstIndex(where: { $0.id == id }) else { return }
        routes[i].misses += 1
        if routes[i].misses >= 3 && routes[i].misses > routes[i].successes { routes.remove(at: i) }
        save()
    }

    func store(task: String, aspect: Double, steps: [Step]) {
        guard let first = steps.first else { return }
        let key = String(task.prefix(512))
        let old = routes.firstIndex { Self.similar($0.task, key) && abs($0.aspect - aspect) <= 0.03
            && Self.sceneDistance($0.steps[0].scene, first.scene) <= 1 }
        var route = Route(id: UUID().uuidString, task: key, aspect: aspect, steps: steps, successes: 0, misses: 0, updated: clock())
        if let old {
            if Self.sameMoves(routes[old].steps, steps) { route.id = routes[old].id; route.successes = routes[old].successes }
            routes.remove(at: old)
        }
        routes.insert(route, at: 0)
        prune(); save()
    }

    /// The navigation of a finished run, from its start up to the first typing, without detours.
    /// `label`: the text label under a point of a frame, with its centre (on-device text recognition).
    nonisolated static func route(steps: [JObject], shots: [Int: Data],
                                  label: (Data, CGPoint) -> (text: String, centre: CGPoint)?) -> [Step]? {
        guard steps.last?["action"]?.str == "done" else { return nil }
        var out: [Step] = []
        for (i, s) in steps.enumerated() {
            let name = s["action"]?.str ?? ""
            if ["type", "key", "path", "circle", "compose", "send missed", "open"].contains(name) { break }  // open: by name, never replayed
            guard ["tap", "swipe", "home", "back"].contains(name), s["changed"] != .bool(false),
                  s["performed"] != .bool(false), let shot = shots[i], let scene = Vision.experienceScene(shot) else { continue }
            let keys = name == "tap" ? ["x", "y"] : name == "swipe" ? ["x1", "y1", "x2", "y2"] : []
            let values = keys.compactMap { s[$0]?.double }.map { Int($0.rounded()) }
            guard values.count == keys.count, values.allSatisfy({ (0...1000).contains($0) }) else { break }
            var step = Step(action: name, values: values, scene: scene)
            if name == "tap", let found = label(shot, CGPoint(x: Double(values[0]) / 1000, y: Double(values[1]) / 1000)) {
                let text = found.text.lowercased()
                if unsafeLabels.contains(where: { text.contains($0) }) { break }
                // A time or a count changes by the next run ("20:20" stopped every replay of a route, logs 11-06).
                let bare = text.filter { !$0.isWhitespace }
                if !bare.isEmpty, bare.allSatisfy({ $0.isNumber || ":.-/+".contains($0) }) { break }
                // One character read under a tap ("它", logs 11-07) is a fragment of a message, not a control's name.
                if bare.count < 2 { break }
                step.anchor = found.text
                step.offsetX = values[0] - Int((found.centre.x * 1000).rounded())
                step.offsetY = values[1] - Int((found.centre.y * 1000).rounded())
            }
            out.append(step)
        }
        // A step taken on the same screen as an earlier one means everything in between was a detour.
        var i = 0
        while i < out.count {
            if let j = out.indices.last(where: { $0 > i && sceneDistance(out[$0].scene, out[i].scene) <= 0.5 }) {
                out.removeSubrange(i..<j)
            }
            i += 1
        }
        return out.isEmpty ? nil : Array(out.prefix(maxSteps))
    }

    /// Where `anchor` is now on this frame: the matching label nearest to where it was.
    nonisolated static func find(_ anchor: String, near: CGPoint, in frame: Data) -> CGPoint? {
        CandidatePicker.rows(in: frame, top: 0, bottom: 1).flatMap { $0 }.filter { $0.text == anchor || $0.text.contains(anchor) }
            .min { hypot($0.box.midX - near.x, $0.box.midY - near.y) < hypot($1.box.midX - near.x, $1.box.midY - near.y) }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    nonisolated static func sceneDistance(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == 64, b.count == 64 else { return .infinity }
        return Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / 64
    }

    /// The same task, or the same wording with other details (a different reply text, another time).
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let x = LessonBook.tokens(a), y = LessonBook.tokens(b)
        let shared = x.intersection(y).count
        return shared >= 3 && Double(shared) / Double(max(1, x.union(y).count)) >= 0.5
    }

    private static func sameMoves(_ a: [Step], _ b: [Step]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.action == $1.action && $0.anchor == $1.anchor }
    }

    private func prune() {
        let cutoff = clock().addingTimeInterval(-30 * 86400)
        routes = Array(routes.filter { $0.updated >= cutoff }.prefix(Self.limit))
        recipes = Array(recipes.filter { $0.updated >= cutoff }.prefix(Self.limit))
    }

    private func save() {
        guard let file else { return }
        if let recipeFile { try? JSONEncoder().encode(recipes).write(to: recipeFile, options: .atomic) }
        do { try JSONEncoder().encode(routes).write(to: file, options: .atomic) }
        catch { DebugLog.write("routes could not be saved: \(error.localizedDescription)") }
    }
}
