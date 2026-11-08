import Foundation

/// The screen feed is gone; acting now would be guessing.
struct BlindError: LocalizedError {
    var reason = "lost the phone screen: reconnect Screen Mirroring"
    var errorDescription: String? { reason }
}

struct InputNeedsVerification: LocalizedError {
    let expected: String
    let remaining: String
    var fieldMayBeComplete = false
    var errorDescription: String? {
        fieldMayBeComplete
            ? "Text was entered but local OCR could not confirm it. Inspect the CURRENT input field for \(expected). "
              + "Do not clear, retype, or paste over correct text. If it is already correct, send it once; "
              + "otherwise explicitly correct only the visible mistake before sending."
            : "Inspect the Pinyin candidates for \(expected); do not assume the first candidate is correct."
    }
}

/// What AgentLoop does on the phone (Pointer, or a fake in tests).
@MainActor protocol Gestures: AnyObject {
    var device: HIDDevice { get }
    func tap(_ x: Double, _ y: Double, aim: Bool) async throws
    func swipe(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, hold: Bool) async throws
    func drag(_ points: [CGPoint], hold: Bool) async throws
    func type(_ text: String) async throws
    func key(_ combo: String) async throws
    func goHome() async throws
    func goBack() async throws
    func reset() async throws
    func typeQuick(_ text: String) async throws
}

extension Gestures {
    func typeQuick(_ text: String) async throws { try await type(text) }
}

extension Pointer: Gestures {}

/// See-think-act loop: a planner model writes the plan, an actor model picks each step. Port of agent.py.
@MainActor final class AgentLoop: ObservableObject {
    struct Planned {
        var act: JObject
        var shot: Data?  // every action of one reply is drawn on the same screenshot
    }

    let phone: Gestures?
    let screen: ScreenSource?
    var actor: ChatModel?, planner: ChatModel?
    let trace: TraceStore?
    let maxSteps: Int, maxFailures: Int
    var metrics: Metrics?
    var experience: ExperienceStore?
    /// The user's corrections from earlier runs, as sentences for the planner and the actor (LessonBook).
    var lessons: LessonBook?
    var routes: RouteBook?
    /// Off for a run whose route depends on what is on screen: WeChat watch's unread check learned "tap 主人蓝海乐"
    /// and replayed it at every check, unread or not, so it kept opening and leaving that chat (logs 11-06, build87).
    var learnedRoutes = true
    /// Learned buttons (send, back), found again by their look; see ControlBook.
    var controls: ControlBook?
    private var sendTap: (point: CGPoint, frame: Data)?  // this run's send tap and the screen it was made on
    private var backMissed = false                        // the last back swipe changed nothing
    private var actFrame: Data?                           // the screen just before the latest action

    private var replayedRoute: String?  // the learned route this run started with
    private var learnedThrough = -1
    private var lessonRun = UUID().uuidString
    /// Plans dropped in a row because the screen moved while the model answered. A plan goes ahead when the
    /// model, looking at a newer screen, chose the same spot again (a live clock icon, a video or an animated
    /// background never hold still), or after two drops when nothing changed where it lands; after five, the
    /// planner looks again.
    private var staleRun = 0
    /// The plan dropped last time, to see whether the next look chose the same spot.
    private var lastStale: JObject?
    /// After a back-and-forth (see bounce): the move that would start it again (`stop`, refused) and its partner.
    /// Any other move ends it; refusing `stop` three times hands the run to the user.
    private var bounceGuard: (stop: JObject, other: JObject)?
    private var bounceRefused = 0
    /// "done" claims turned down because this run has not made what the task asks for (see unmadeResult).
    private var doneRejected = 0
    /// A Home flick that changed nothing gets one keyboard alternative, never another identical flick.
    private var homeRecoveryTried = false

    @Published private(set) var task = ""
    @Published private(set) var plan = ""
    /// The planner (Codex) as the backstop (user 11-08: "codex要做的是兜底…如果豆包api做不好就讓codex去做"). Its plan
    /// is a list of parts, each a result the screen can show; the executor (Doubao) works on one at a time. When the
    /// executor stalls, spends 20 steps on one part, or gives up, Codex looks again and drives itself until that part
    /// is done. A finished run's whole way is remembered (RouteBook recipe) and followed the next time, without asking
    /// the planner ("做完之後記住做的路徑，下次就可以快速做出來").
    private(set) var parts: [String] = []
    private(set) var partIndex = 0
    private(set) var doneParts: [String] = []
    private(set) var takeover = 0
    private var stepsInPart = 0, rescued = false
    /// How this task was done the last time it finished (nil: never, or a fixed plan such as watching WeChat).
    private(set) var recipe: RouteBook.Recipe?
    @Published var steps: [JObject] = []
    @Published private(set) var shots: [Int: Data] = [:]  // step index -> screenshot the model decided on
    @Published private(set) var running = false
    private var pointerAt = CGPoint.zero  // last pointer position (screen fractions)
    /// When the last gesture ended: the model never decides on a frame from before it.
    private(set) var lastActed = 0.0
    /// Awaited before every look and every gesture (the app holds the run while its own UI is in front).
    var gate: (() async throws -> Void)?
    static let maxTokens = ["planner": 1500, "actor": 1000]
    private var job: Task<Void, Never>?
    var onFinish: (() -> Void)?
    /// Paused for the board to come back (a line for the UI), or nil when going on.
    /// Recovery from a lost link: the link state (from the app), each stage as it changes (nil = live again),
    /// and what to redo once live (stream on, fresh frame, release, re-home).
    var link: (() -> Recovery.Link)?
    var onRecover: ((Recovery.Stage?) -> Void)?
    var restore: (() async throws -> Void)?
    var recoveryLimit = Recovery.limit
    var onStep: (() -> Void)?
    /// What the agent is busy with between steps, for the Dynamic Island (looking, thinking, about to act).
    var onDoing: ((Doing) -> Void)?
    enum Doing { case looking, waiting, planning, thinking, retrying, acting(JObject) }
    /// Hints from a saved intent's checklist, appended to the actor's system prompt (empty = the original prompt).
    var hints: [String] = []
    /// Reference text the user chose for this run (WeChat watch: the selected knowledge files), appended to the
    /// planner and actor prompts. Empty for ordinary runs.
    var reference = ""
    /// Phase B (specs/004): text typed by Lan Agent's keyboard into the focused field (true when it confirmed);
    /// whether that keyboard is on screen; and opening an app by name. Nil in tests and demo data.
    var keyboardType: ((String) async -> Bool)?
    var ourKeyboardOnScreen: (() -> Bool)?
    var openApp: ((String) async throws -> Bool)?
    /// Give the model the screen's text with positions (off in tests whose fake frames carry no text).
    var readsScreenText = false

    /// The screen's text pieces, top to bottom and left to right, as `"text" x y` lines (0-1000); nil when none.
    /// At most `limit` lines, so a long list or chat does not crowd the prompt.
    static func screenText(_ rows: [[CandidatePicker.Piece]], limit: Int = 45) -> String? {
        func readsBefore(_ a: CandidatePicker.Piece, _ b: CandidatePicker.Piece) -> Bool {
            let dy: CGFloat = a.box.midY - b.box.midY
            if abs(dy) > 0.008 { return dy < 0 }   // another line: the higher one first
            return a.box.midX < b.box.midX         // the same line: left to right
        }
        let shown: [CandidatePicker.Piece] = rows.flatMap { $0 }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let pieces = Array(shown.sorted(by: readsBefore).prefix(limit))
        guard !pieces.isEmpty else { return nil }
        var lines: [String] = []
        for piece in pieces {
            let text = piece.text.replacingOccurrences(of: "\"", with: "'")
            let x = Int((piece.box.midX * 1000).rounded()), y = Int((piece.box.midY * 1000).rounded())
            lines.append("\"\(text)\" \(x) \(y)")
        }
        return lines.joined(separator: "\n")
    }
    /// A fixed plan (WeChat watch's open and send tasks, whose steps never change): used as is, without the
    /// planner's call. Empty for ordinary runs.
    var presetPlan = ""
    /// Begin an authorized phone task with the actor; the planner remains available for recovery.
    var directStart = false
    /// Navigation-only completion from a verified frame; message reading still checks the destination.
    var frameCompletion: ((Data) -> String?)?
    /// WeChat watch: fewer steps than maxSteps, and no pause for help (nobody is at the phone; a stuck task fails
    /// and the watch goes on). nil for ordinary runs.
    var stepLimit: Int?
    /// WeChat watch: text goes in without a model look per phrase (typeFast). Off for ordinary runs.
    var fastText = false
    /// Puts a reply on the pasteboard with Lan Agent in front for a moment (AppModel.hopToPaste); nil in tests.
    var pasteHop: ((String) async -> PasteHopResult)?
    private var pasteHopOff = false  // a hop got lost once in this run: the rest of it types
    private var lastTap: CGPoint?    // the last tap (0-1), the input box when a type follows
    /// WeChat watch send: the target chat's row (0-1) when this frame is the chat list showing it once; nil otherwise.
    var rowTarget: ((Data) -> CGPoint?)?
    /// WeChat watch send: a reply pasted and seen in the box is sent with Return at once (no look to find 发送).
    var returnSends = false
    /// Where this run typed: the input box (0-1), for WeChat watch to send the next reply without a run.
    private(set) var typedInto: CGPoint?
    /// Whether this run's strokes have left a line yet; nil until one is checked.
    private var inkSeen: Bool?
    private var returnSent = false  // typeFast sent the message with Return: the run is done
    /// WeChat watch: a `type` with no keyboard on screen is refused and the next tap aims (logs27: the tap on the
    /// input box landed above it, and "nihaoya" was typed seven times into nothing while the model said the box was
    /// focused). Refused twice in a row, it goes through, in case the keyboard is one the check does not know.
    var keyboardGuard = false
    private var noKeyboard = 0
    private var aimNext = false  // the next tap finds the pointer on screen first
    /// WeChat watch: text this run typed and then sent (Return, or a tap on 发送 at the bottom right). Typing it again
    /// is refused: logs28's phone task sent "你好" to 测试群 twice and was typing it a third time.
    private var sentTexts: Set<String> = []
    private var sendCorrections = 0
    /// What this run sent, for a run that ended without "done" (build 67: an @ went out, the model kept looking until
    /// the step limit, and the owner was told "这个我没弄成").
    var sent: [String] { sentTexts.sorted() }
    /// A single-message task gets this many read-only looks to verify a send; no confirmation means failure. nil: off.
    var endAfterSend: Int?
    /// Unsupported quick-Pinyin keyboards seen across runs; OCR uncertainty never disables normal typing.
    var pinyinMisses = 0
    private var quietSinceSend = 0
    private var pendingInput: String?
    /// Text already entered by a quick send, handed over for visual inspection without retyping.
    var inputToInspect: String?
    /// A destination-specific receipt, independent of the actor's next navigation/action guess.
    var sendReceipt: ((String) async -> Bool)?
    /// How often each text showed on screen when this run first typed it. Shown more often later, it was sent or is
    /// still in the box: typing it again is refused (60 on the PC harness: the model sent with WeChat's green 发送
    /// next to the box, which the tap check above missed, typed the text again, and left it in the box).
    private var typedBase: [String: Int] = [:]
    private var unsent: String?  // typed, not sent yet
    private var boxCleared = false  // a send run emptied the box before its first type
    /// Taps that did nothing: each one after which the next stroke still left no line. A spot in here twice is
    /// refused: traces(44) tapped the New Board button at the bottom right a dozen times as if it were the pen.
    private var deadTaps: [JObject] = []
    /// Checked before every `type`: a reason refuses the text (it is never typed) and goes into the steps, so the
    /// model rewrites it. WeChat watch uses it so private details never leave the phone.
    var outgoingGuard: ((String) -> String?)?
    /// "Needs your help": asked when the actor gives up or errors repeat; nil = end the run as before.
    var onHelp: ((String) async -> HelpChoice)?
    private var helpAsked = 0
    enum HelpChoice { case resume, skip, stop }

    init(phone: Gestures?, screen: ScreenSource?, actor: ChatModel?, planner: ChatModel?, trace: TraceStore?,
         maxSteps: Int = 40, maxFailures: Int = 3) {
        self.phone = phone; self.screen = screen; self.actor = actor; self.planner = planner
        self.trace = trace; self.maxSteps = maxSteps; self.maxFailures = maxFailures
    }

    /// traceStarted: the caller already opened the run's trace folder (so a failed start is logged too).
    func start(_ task: String, traceStarted: Bool = false) throws {
        if running { throw DeviceError(message: "agent already running") }
        guard screen?.live == true else { throw DeviceError(message: "no phone screen: start Screen Mirroring first") }
        self.task = task; plan = ""; steps = []; shots = [:]
        pointerAt = .zero
        lastActed = 0
        learnedThrough = -1
        helpAsked = 0
        staleRun = 0
        lastStale = nil
        bounceGuard = nil
        bounceRefused = 0
        doneRejected = 0
        if !traceStarted { trace?.start(task: task) }
        running = true
        job = Task { [weak self] in
            await self?.run()
            self?.running = false
            self?.onFinish?()
        }
    }

    func stop() {
        if let job { job.cancel() } else { running = false }  // a shown (demo) run has no job
        if let device = phone?.device {
            Task { do { try await device.abort() } catch { DebugLog.write("stop failed: \(error.localizedDescription)") } }
        }
    }

    func clear() throws {
        if running { throw DeviceError(message: "stop the agent first") }
        task = ""; plan = ""; steps = []; shots = [:]
    }

    private func record(_ shot: Data? = nil, _ step: JObject) {
        if let shot { shots[steps.count] = shot }
        steps.append(JObject([("t", .num(now())), ("shot", .bool(shot != nil))]).merging(step))
        trace?.write(kind: "step", step)
        // What each step did, on the computer too (build 69: "kept going back and forth between two screens", and the
        // log held only timings).
        let fields = ["x", "y", "text", "key", "reason", "answer"].compactMap { k -> String? in
            guard let v = step[k] else { return nil }
            let s = v.str ?? v.double.map { String(format: "%.0f", $0) } ?? ""
            return s.isEmpty ? nil : "\(k) \(s.prefix(40))"
        }
        DebugLog.write("act \(steps.count): \(step["action"]?.str ?? "?") \(fields.joined(separator: ", "))")
        onStep?()
    }

    /// The board or mirroring went away mid-run: pause ("waiting for the board") until the screen is live
    /// again, up to `reconnectWait` s, instead of failing the run.
    /// The screen is gone (board, hotspot or mirroring lost): pause the run until it is back, in stages.
    /// Returns how many seconds it took, or nil if the screen was there all along. Never ends the run for a
    /// lost link before Recovery.limit.
    func waitForScreen(poll: Double = 0.5) async throws -> Double? {
        guard let screen, !screen.live else { return nil }
        var recovery = Recovery(at: now(), limit: recoveryLimit)
        var shown: Recovery.Stage?
        var lastProbe = -Double.infinity
        defer { if shown != nil { onRecover?(nil) } }
        while true {
            try Task.checkCancellation()
            let state = link?() ?? Recovery.Link(connected: phone?.device.connected ?? true, sta: nil,
                                        ap: screen.live ? "streaming" : nil, frameAt: screen.live ? now() : 0)
            if state.connected, state.ap == "streaming", now() - lastProbe >= 10 {
                lastProbe = now()
                do {
                    try await screen.requireFrame(after: recovery.started)
                    try await restore?()
                    return now() - recovery.started
                } catch is CancellationError { throw CancellationError() }
                catch { DebugLog.write("recover: frame not yet verified: \(error.localizedDescription)") }
            }
            switch recovery.next(state, at: now()) {
            case .live where screen.live:
                try await restore?()
                await screen.settled()
                return now() - recovery.started
            case .live: break
            case .wait(let stage):
                if stage != shown { shown = stage; onRecover?(stage) }
            case .giveUp(let reason):
                throw BlindError(reason: reason)
            }
            try await Task.sleep(nanoseconds: UInt64(poll * 1e9))
        }
    }

    private func ask(_ role: String, _ llm: ChatModel, _ system: String, _ prompt: String,
                     temperature: Double = 0, retryTimeout: Bool = true) async throws -> (String, Double, Data?) {
        try await gate?()
        var prompt = prompt
        if let lost = try await waitForScreen() {
            record(nil, ["action": .str("reconnected"), "reason": .str(String(format: "connection lost for %.0f s and restored", lost))])
            prompt += "\n\nNote: the connection was lost and restored; re-check the screen before acting."
            try await gate?()  // the user may have opened this app while it was paused
        }
        guard let screen, screen.live else { throw BlindError() }  // never let the model act blind
        try await screen.requireFrame(after: nil)
        let frame = screen.frame, started = now()
        if role == "actor", let frame, let answer = frameCompletion?(frame) {
            DebugLog.write("agent: navigation title found locally; handing off to message verification")
            return ("THINK: The navigation destination is visible; read and verify it next.\nDO: done \(answer)", 0, frame)
        }
        // Retrieve against the very frame sent with this request, after freshness/recovery checks.
        if let frame, let scene = Vision.experienceScene(frame), let image = Vision.image(frame) {
            let aspect = Double(image.width) / Double(image.height)
            prompt += experience?.context(goal: task, scene: scene, aspect: aspect) ?? ""
            if role == "actor" {
                let example: JObject = ["action": .str("circle"), "x": .int(500), "y": .int(450), "r": .int(180)]
                if let bounds = Actions.drawingBounds(example, aspect: aspect) {
                    prompt += String(format: "\n\nScreen width/height = %.4f. Circle R is in width units; vertical radius = R * %.4f."
                        + " For example, circle 500 450 180 covers x 320..680, y %.0f..%.0f. Place parts using these actual bounds.",
                        aspect, aspect, bounds.minY, bounds.maxY)
                }
                for step in steps.suffix(8) {
                    if let b = Actions.drawingBounds(step, aspect: aspect) {
                        prompt += String(format: "\nRecent circle %@ has bounds x %.0f..%.0f, y %.0f..%.0f (0-1000 screen units).",
                            PyJSON.dumps(Actions.key(step)), b.minX, b.maxX, b.minY, b.maxY)
                    }
                }
            }
        }
        onDoing?(retryTimeout ? .waiting : .retrying)
        let reporting = llm as? ModelProgressReporting
        reporting?.onProgress = { [weak self] progress in
            switch progress {
            case .waiting: self?.onDoing?(retryTimeout ? .waiting : .retrying)
            case .receiving: self?.onDoing?(role == "planner" ? .planning : .thinking)
            }
        }
        defer { reporting?.onProgress = nil }
        let reply: ChatResult
        do {
            let quoted = lessons?.relevant(to: task).filter { system.contains($0.text) } ?? []
            lessons?.markUsed(quoted, run: trace?.dir?.lastPathComponent ?? lessonRun, task: task)
            reply = try await llm.chat(system: system, text: prompt, image: frame,
                                       maxTokens: Self.maxTokens[role] ?? 1000, temperature: temperature)
        } catch {
            guard retryTimeout, ModelRequestFailure.isTimeout(error), !Task.isCancelled else { throw error }
            DebugLog.write("model request timed out (\(role)); retrying once with a fresh screen")
            onDoing?(.retrying)
            try await Task.sleep(for: .seconds(2))
            // Re-enter the gate and screen checks before retrying; no gesture is repeated.
            return try await ask(role, llm, system, prompt, temperature: temperature, retryTimeout: false)
        }
        let seconds = ((now() - started) * 100).rounded() / 100
        metrics?.llm(first: reply.firstToken, total: reply.total)
        var rec: JObject = ["role": .str(role), "model": .str(llm.model), "prompt": .str(prompt),
                            "reply": .str(reply.text), "seconds": .num(seconds)]
        if let first = reply.firstToken { rec["first_token_s"] = .num((first * 100).rounded() / 100) }
        if lastActed > 0 { rec["frame_after_action_s"] = .num(((screen.capturedAt - lastActed) * 100).rounded() / 100) }
        trace?.write(frame, kind: "llm", rec.merging(reply.diagnostics))
        return (reply.text, seconds, frame)
    }

    /// A lost board or mirror is not the agent's fault. VideoReadinessError says so directly; a bare
    /// DeviceError counts only once the screen is gone. A connected but undecodable mirror still counts.
    static func isLinkLoss(_ error: Error, screenLive: Bool?) -> Bool {
        if let video = error as? VideoReadinessError { return [.boardDisconnected, .mirroringDisconnected].contains(video) }
        return error is DeviceError && screenLive == false
    }

    /// A drawing or typing task is not done until this run has drawn or typed: a picture or text already on the
    /// screen (an old board, an earlier note, an app's opening animation) is not this run's result. nil = may finish.
    /// Only clear drawing/typing requests are checked, so other tasks are never held back.
    static func unmadeResult(task: String, steps: [JObject]) -> String? {
        let did = Set(steps.compactMap { $0["action"]?.str })
        if did.contains("takeover") { return nil }  // the user did part of it by hand
        let t = task.lowercased()
        let draws = t.range(of: #"[画畫](?=[一个個两兩三几幾只隻张張条條朵幅颗顆棵出上下画畫圆圓圈线線笑星心])"#,
                            options: .regularExpression) != nil
            || t.range(of: #"\b(draw|sketch)\b"#, options: .regularExpression) != nil  // not "drawer"
        if draws, did.isDisjoint(with: ["circle", "path"]) {
            return "Nothing has been drawn in this run yet; a drawing already on screen is from before and does not count. "
                + "Start a new blank canvas (a new board, note or page in this app) and draw it there."
        }
        // A message to send word for word must be typed in this run: the same words in a bubble above are an earlier
        // message (logs(19): an identical reply was "already sent", and the new message went unanswered). Only when
        // nothing was typed at all: a turned-down "done" after a message was sent made it send again (traces(32)).
        if task.contains("一字不改"), did.isDisjoint(with: ["type", "compose"]) {
            return "Nothing has been typed in this run; a bubble with the same words above is an earlier message, not "
                + "this one. Tap the input box, type the message and send it."
        }
        return nil
    }

    /// Actions that move the screen somewhere (a back-and-forth is made of these).
    private static let moving: Set<String> = ["tap", "swipe", "back", "home", "key"]

    /// The plan closes a back-and-forth: the last moves went A, B, A and this one is B again (enter a chat, go back,
    /// enter, go back). Each of them changes the screen, so `repeating` never sees it. Returns A.
    static func bounce(_ act: JObject, after steps: [JObject]) -> JObject? {
        guard moving.contains(act["action"]?.str ?? "") else { return nil }
        let moves = Array(steps.filter { moving.contains($0["action"]?.str ?? "") }.suffix(3))
        guard moves.count == 3, sameSpot(act, moves[1]), sameSpot(moves[2], moves[0]), !sameSpot(moves[0], moves[1])
        else { return nil }
        return moves[0]
    }

    // No app's layout is written into these: the agent works out which control it is by trying, and what worked is
    // learned from the run that got there (any app, not only the ones someone described).
    static let noInkReason = "The stroke left no line on the canvas: no drawing tool is active, so the drag only moved the "
        + "canvas. Look at the controls on screen and work out which one is the drawing tool (a button you already tried that "
        + "changed nothing is not it), select it, then draw again. It is not done until lines show."
    static let sentAgainReason = "Not typed: this run already typed this text and sent it. Look for its bubble: if it "
        + "shows, the task is done, finish with done. If it is still in the input box, tap 发送 instead; never type it again."
    static let sendVerificationReason = "This run already issued the send command for the requested message. "
        + "Do not send it again, type anything, or navigate away. Inspect the CURRENT requested chat and confirm that "
        + "the newly sent message matches the original Goal; an older matching bubble is not confirmation. "
        + "Only wait, done after verification, or fail if the result cannot be verified. If the Goal also asks for "
        + "something to be brought back (a reply, a result), read it on screen and put it in the done answer: the "
        + "program delivers the answer, so never go back to WeChat yourself."

    /// The text as typed, for telling a repeat: quotes and spaces the model adds around it do not count.
    /// A run's outcome from what it sent, in the {"send": …} form WatchReport.sendAnswer reads.
    static func sentAnswer(_ sent: [String]) -> String {
        let words = sent.filter { $0.count > 1 }.map { "“\($0)”" }.joined(separator: "、")
        let text = words.isEmpty ? "消息已按要求发出" : "已发出\(words)"
        return #"{"send":""# + text.replacingOccurrences(of: "\"", with: "") + #""}"#
    }

    static func typedKey(_ text: String) -> String {
        text.filter { !$0.isWhitespace && !"\"'“”‘’「」".contains($0) }
    }

    /// A tap on the keyboard's bottom-right key, while a keyboard is up (0-1000): 发送 / 换行 below the backspace key
    /// (0.80–0.83) and above the globe and microphone (0.93–).
    static func onReturnKey(_ act: JObject) -> Bool {
        guard act["action"]?.str == "tap", let x = act["x"]?.double, let y = act["y"]?.double else { return false }
        return x >= 760 && (845...925).contains(y)
    }

    /// Return, or a tap where 发送 sits (next to the box, or the keyboard's bottom-right key).
    static func sends(_ act: JObject) -> Bool {
        switch act["action"]?.str {
        case "key": return ["enter", "return"].contains(act["combo"]?.str?.lowercased() ?? "")
        case "tap": return (act["x"]?.double ?? 0) >= 800 && (act["y"]?.double ?? 0) >= 400  // 发送 by the box: ~0.49
        default: return false
        }
    }

    static let noKeyboardReason = "Not typed: no keyboard is on screen, so the input box is not focused (the last tap "
        + "missed it). Tap the input box again (this tap is aimed) and type only once the keyboard shows."
    /// Where a tap that changed nothing is tried next, in screen fractions: up first (misses land low near the top,
    /// live test 11-08), then down, left, right. Each stays within sameSpot's 0.03, so the count goes on.
    static let deadTapNudges: [(Double, Double)] = [(0, -0.025), (0, 0.025), (-0.025, 0), (0.025, 0)]

    static let deadTapReason = "Refused: tapping this spot already did nothing twice (the screen did not change, or the next "
        + "stroke still left no line). It is not the control you want: look at what else is on screen and try a different one."

    /// The tap since the previous stroke (the try at picking a tool), if there was one.
    static func tapBeforeStroke(_ steps: [JObject]) -> JObject? {
        for s in steps.reversed() {
            switch s["action"]?.str ?? "" {
            case "tap": return s
            case "no ink": return nil  // two strokes with no tap between: no tool was tried
            default: continue
            }
        }
        return nil
    }

    /// The points a stroke goes through, 0-1 of the screen, for checking it left a line.
    private func strokePoints(_ act: JObject) -> [CGPoint] {
        func p(_ k: String) -> Double { (act[k]?.double ?? 0) / 1000 }
        switch act["action"]?.str {
        case "circle": return circle(p("x"), p("y"), p("r"), aspect: screen?.aspect ?? 9 / 19.5, n: 36)
        case "path": return points(act).map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) }
        default: return []
        }
    }

    /// The share of a stroke's points where a line newly shows: clearly darker than before (a pen, black or in colour;
    /// the canvas's grey dots moving do not count). A stroke without a pen selected only pans the canvas and leaves
    /// none (logs(14): two smileys "drawn" on an empty board, both taken as done). nil when it cannot be told.
    static func inkShare(before: Data?, after: Data?, stroke: [CGPoint]) -> Double? {
        guard let before, let after, let a = Vision.image(before), let b = Vision.image(after),
              a.width == b.width, a.height == b.height, stroke.count >= 2 else { return nil }
        let w = a.width / 2, h = a.height / 2, reach = 4  // a line within 8 px of where it was aimed
        let ga = Vision.gray(a, w, h), gb = Vision.gray(b, w, h)
        var samples = 0, inked = 0
        for pt in stroke {
            let x = Int(Double(pt.x) * Double(w)), y = Int(Double(pt.y) * Double(h))
            guard x >= reach, y >= reach, x < w - reach, y < h - reach else { continue }
            samples += 1
            var darkBefore = 255, darkAfter = 255
            for dy in -reach...reach { for dx in -reach...reach {
                let i = (y + dy) * w + x + dx
                darkBefore = min(darkBefore, Int(ga.px[i]))
                darkAfter = min(darkAfter, Int(gb.px[i]))
            } }
            if darkAfter < 150 && darkAfter < darkBefore - 80 { inked += 1 }
        }
        return samples == 0 ? nil : Double(inked) / Double(samples)
    }

    static let loopReason = "this move starts again a back-and-forth this run already went through twice; the move that "
        + "left was the mistake. Stay on this screen and do the task here."

    /// A move that leaves the current screen: back, home, or a tap on the back arrow at the top left.
    static func leaves(_ act: JObject) -> Bool {
        switch act["action"]?.str {
        case "back", "home": return true
        case "tap": return (act["x"]?.double ?? 1000) <= 150 && (act["y"]?.double ?? 1000) <= 130
        default: return false
        }
    }

    /// Two plans aim at the same place: the same action landing within 3% of the screen of each other (a model
    /// rarely names the exact same pixel twice), or the same text or key for actions without a place.
    static func sameSpot(_ a: JObject, _ b: JObject) -> Bool {
        guard a["action"] == b["action"] else { return false }
        let (pa, pb) = (pointerPath(a), pointerPath(b))
        guard pa.count == pb.count else { return false }
        if pa.isEmpty { return Actions.sameTarget(a, b) }
        return zip(pa, pb).allSatisfy { abs($0.x - $1.x) <= 0.03 && abs($0.y - $1.y) <= 0.03 }
    }

    /// A 3-point path with one wide, roughly even bend (a smile, an arc) is drawn as a smooth curve: models keep
    /// sending three points for a curve, and the straight joins came out as a V. Sharp or lopsided bends stay.
    static func isGentleBend(_ pts: [CGPoint], aspect: Double) -> Bool {
        guard pts.count == 3, aspect.isFinite, aspect > 0 else { return false }
        let sy = 1 / aspect  // a y unit is this many x units tall
        let (ax, ay) = (Double(pts[0].x - pts[1].x), Double(pts[0].y - pts[1].y) * sy)
        let (bx, by) = (Double(pts[2].x - pts[1].x), Double(pts[2].y - pts[1].y) * sy)
        let (la, lb) = (hypot(ax, ay), hypot(bx, by))
        guard la > 0, lb > 0, max(la, lb) / min(la, lb) <= 2 else { return false }
        return (ax * bx + ay * by) / (la * lb) <= 0  // the bend is 90° or wider
    }

    func run() async {
        var failures = 0
        (pasteHopOff, lastTap, typedInto, inkSeen, deadTaps, returnSent) = (false, nil, nil, nil, [], false)
        (noKeyboard, aimNext, sentTexts, unsent, boxCleared, typedBase) = (0, false, [], nil, false, [:])
        sendCorrections = 0
        quietSinceSend = 0
        pendingInput = inputToInspect
        if let inputToInspect { unsent = inputToInspect }
        homeRecoveryTried = false
        // What this run was taught, in the exported trace: the system prompts themselves are not recorded.
        let applied = lessons?.relevant(to: task) ?? []
        lessonRun = UUID().uuidString
        if !applied.isEmpty || !Prompts.userRules.isEmpty {
            trace?.write(kind: "lessons", ["lessons": .arr(applied.map { .str($0.text) }), "rules_md": .bool(!Prompts.userRules.isEmpty)])
            DebugLog.write("lessons: \(applied.count) applied, rules.md \(Prompts.userRules.isEmpty ? "absent" : "used")")
        }
        replayedRoute = nil
        (parts, partIndex, doneParts, takeover, stepsInPart, rescued) = ([], 0, [], 0, 0, false)
        recipe = presetPlan.isEmpty && learnedRoutes ? routes?.recipe(for: task) : nil
        (sendTap, backMissed, actFrame) = (nil, false, nil)
        do {
            do { try await replay() }
            catch let e where e is CancellationError || Task.isCancelled { throw e }
            catch { DebugLog.write("route: replay stopped by \(error.localizedDescription); the model takes over") }
            if presetPlan.isEmpty, !directStart, let recipe {
                plan = Self.rememberedPlan(recipe)
                record(nil, ["action": .str("plan"), "plan": .str(plan), "plan_zh": .str(""), "think_s": .num(0),
                             "source": .str("remembered")])
                DebugLog.write("plan: remembered from a run that finished (\(recipe.lines.count) steps); the planner is not asked")
            } else if !presetPlan.isEmpty || directStart {
                plan = presetPlan.isEmpty ? """
                Work from the CURRENT screen and the original Goal; keep completed work.
                Choose the next action from what is visible, then inspect its result before continuing.
                If the route is unclear or progress stops, request replan rather than guessing or repeating moves.
                Finish only after checking the visible result against the Goal, using its required answer format.
                """ + (recipe.map { "\n\n" + Self.rememberedPlan($0) } ?? "") : presetPlan
                record(nil, ["action": .str("plan"), "plan": .str(plan), "plan_zh": .str(""), "think_s": .num(0),
                             "source": .str(presetPlan.isEmpty ? "direct start" : "fixed plan")])
            } else {
                try await replan()
            }
            let budget = Self.stepBudget(plan: plan, base: stepLimit ?? maxSteps)
            if budget > (stepLimit ?? maxSteps) { DebugLog.write("run: \(budget) steps for a plan of several parts") }
            for _ in 0..<budget {
                do {
                    if try await step() {
                        if try await rescue() { continue }
                        guard steps.last?["action"]?.str == "fail", try await askForHelp() else { return finish() }
                        continue
                    }
                    failures = 0
                    if parts.count >= 2 {
                        stepsInPart += 1
                        if stepsInPart >= Self.partSteps {
                            record(nil, ["action": .str("part stalled"),
                                         "reason": .str("part \(partIndex + 1) not done after \(Self.partSteps) steps")])
                            try await replan(stuck: true)
                        }
                    }
                    if let n = endAfterSend, !sentTexts.isEmpty, unsent == nil {
                        quietSinceSend += 1
                        if quietSinceSend > n {
                            record(nil, ["action": .str("fail"),
                                         "reason": .str("could not verify the sent message; not sending again to avoid duplicates")])
                            return finish()
                        }
                    }
                } catch let e as BlindError {
                    record(nil, ["action": .str("paused"), "reason": .str(e.reason)])
                    guard try await askForHelp() else { return finish() }
                    continue
                } catch let e where e is CancellationError || Task.isCancelled {
                    throw e
                } catch {  // a bad reply or a dropped link: recover, don't crash
                    record(nil, ["action": .str("hiccup"), "reason": .str(String(error.localizedDescription.prefix(300)))])
                    let linkLost = Self.isLinkLoss(error, screenLive: screen?.live)  // the next look waits for it (waitForScreen)
                    failures += linkLost ? 0 : 1  // a lost link is not the agent's fault
                    if failures >= maxFailures {
                        record(nil, ["action": .str("fail"), "reason": .str("\(failures) errors in a row")])
                        guard try await askForHelp() else { return finish() }
                        failures = 0
                        continue
                    }
                    await screen?.settled()
                    if error is BoardTimeout || error is DeviceError {
                        // An unacknowledged action may have completed. Observe its result before replanning;
                        // reset tracking, but never replay the original relative move/click/text.
                        if phone?.device.connected == true { try await phone?.device.abort() }
                        try await screen?.requireFrame(after: nil)
                        try await phone?.reset()
                    }
                    try await replan(stuck: true)
                }
            }
            record(nil, ["action": .str("fail"), "reason": .str("step limit reached")])
        } catch let e where e is CancellationError || Task.isCancelled {
            record(nil, ["action": .str("stopped")])
        } catch let e as BlindError {
            record(nil, ["action": .str("fail"), "reason": .str(e.reason)])
        } catch {  // e.g. the planner itself is unreachable
            record(nil, ["action": .str("error"), "reason": .str(ModelRequestFailure.message(error))])
        }
        finish()
    }

    /// Pauses for the user (at most twice a run). True = go on from the current screen with a new plan.
    private func askForHelp() async throws -> Bool {
        guard let onHelp, helpAsked < 2, stepLimit == nil else { return false }
        helpAsked += 1
        let reason = steps.last?["reason"]?.str ?? ""
        record(nil, ["action": .str("help"), "reason": .str(reason)])
        let choice = await onHelp(reason)
        try Task.checkCancellation()
        switch choice {
        case .stop:
            record(nil, ["action": .str("stopped")])
            return false
        case .resume:
            record(nil, ["action": .str("takeover"), "reason": .str("the user did this part by hand: \(reason)")])
        case .skip:
            record(nil, ["action": .str("skipped"), "reason": .str("the user asked to skip this step: \(reason)")])
        }
        await screen?.settled()
        try await replan(stuck: true)
        return true
    }

    /// The actor's system prompt: the original, plus this task's hints, the user's lessons and rules.md.
    var actorPrompt: String { Prompts.actor + "\n" + AssistiveTouchSpots.rule + taught }

    /// The planner gets the same: a plan that ignores them makes the actor ignore them too.
    var plannerPrompt: String { Prompts.plannerApp + "\n" + AssistiveTouchSpots.rule + taught }

    private var taught: String {
        (hints.isEmpty ? "" : "\n\nHints for this task:\n" + hints.map { "- " + $0 }.joined(separator: "\n"))
            + (lessons?.context(task: task) ?? "") + Prompts.userRules
            + (reference.isEmpty ? "" : "\n\nKnowledge base chosen by the user. Base every reply on it; when it does not "
               + "cover the question, use the user's fallback reply instead of guessing. Never send anything from "
               + "outside it about the user, and never copy one chat's content into another chat:\n" + reference)
    }

    private func finish() {
        if let metrics { trace?.writeMetrics(metrics.snapshot()) }
        if let routes, learnedRoutes, steps.last?["action"]?.str == "done" {
            let run = (task: self.task, steps: self.steps, shots: self.shots, aspect: screen?.aspect ?? 0, used: replayedRoute,
                       recipe: presetPlan.isEmpty)
            Task { await routes.learn(task: run.task, steps: run.steps, shots: run.shots, aspect: run.aspect, replayed: run.used,
                                      recipe: run.recipe) }
        }
        // A run that sent by tapping and ended done: that spot is this screen's send button, by its look.
        if let controls, steps.last?["action"]?.str == "done", !sentTexts.isEmpty, let tap = sendTap {
            controls.learn("send", at: tap.point, on: tap.frame)
        }
        sendTap = nil
    }

    /// Walk a learned route (RouteBook) without the model while each screen is the one it was learned on, tapping
    /// each step's label where it is now. The first screen that differs, a missing label or a step that changes
    /// nothing hands the run to the model from there; the replayed steps are in its recent actions.
    func replay() async throws {
        guard let routes, learnedRoutes, phone != nil, let first = screen?.frame, let scene = Vision.experienceScene(first),
              let entry = routes.entry(task: task, scene: scene, aspect: screen?.aspect ?? 0) else { return }
        let route = entry.route, from = entry.from
        replayedRoute = route.id
        if from > 0 { DebugLog.write("route: joined at step \(from + 1) of \(route.steps.count), the screen this run starts on") }
        var walked = 0, stop = ""
        walk: for step in route.steps[from...] {
            try Task.checkCancellation()
            try await gate?()
            guard let shown = screen?.frame, let here = Vision.experienceScene(shown),
                  RouteBook.sceneDistance(here, step.scene) <= 1 else { stop = "the screen differs"; break }
            var act: JObject = ["action": .str(step.action), "source": .str("route")]
            switch step.action {
            case "tap":
                var x = Double(step.values[0]), y = Double(step.values[1])
                if let anchor = step.anchor {
                    let was = CGPoint(x: (x - Double(step.offsetX ?? 0)) / 1000, y: (y - Double(step.offsetY ?? 0)) / 1000)
                    guard let spot = RouteBook.find(anchor, near: was, in: shown) else { stop = "“\(anchor)” is not on screen"; break walk }
                    x = min(1000, max(0, spot.x * 1000 + Double(step.offsetX ?? 0)))
                    y = min(1000, max(0, spot.y * 1000 + Double(step.offsetY ?? 0)))
                }
                act["x"] = .num(x.rounded())
                act["y"] = .num(y.rounded())
            case "swipe":
                for (k, v) in zip(["x1", "y1", "x2", "y2"], step.values) { act[k] = .num(Double(v)) }
            default: break
            }
            onDoing?(.acting(act))
            let started = now()
            try await perform(act)
            lastActed = now()
            act["act_s"] = .num(((lastActed - started) * 100).rounded() / 100)
            record(shown, act)
            _ = try await settle()
            let changed = Vision.changed(shown, screen?.frame, ignore: pointerPath(act))
            steps[steps.count - 1]["changed"] = .bool(changed)
            guard changed else { stop = "a step changed nothing"; break }
            walked += 1
        }
        if walked < route.steps.count - from { routes.missed(route.id) }
        DebugLog.write("route: replayed \(walked)/\(route.steps.count - from) learned steps without the model"
                       + (stop.isEmpty ? "" : "; stopped: \(stop)"))
    }

    /// One see-think-act round (one or more actions). Returns true when the task is over.
    func step() async throws -> Bool {
        var timing = Metrics.Step()
        let acts = try await nextActions()
        timing.llmMs = (acts[0].act["think_s"]?.double ?? 0) * 1000
        let seen = acts[0].shot
        var spots = [pointerAt]  // where the pointer was and goes: pointer moves are not screen changes
        let stuck = repeating(acts[0].act)
        let drawing = Set(["circle", "path"])
        let startsDrawing = drawing.contains(acts[0].act["action"]?.str ?? "")
            && !drawing.contains(steps.last?["action"]?.str ?? "")
        defer { metrics?.step(timing) }
        for (i, planned) in acts.enumerated() {
            var act = planned.act
            if Self.onReturnKey(act), let shown = screen?.frame, CandidatePicker.keyboardUp(in: shown) {
                // The keyboard's bottom-right key (发送 / 换行 / 前往) is Return, which the board's keyboard presses
                // without the pointer. As a tap it waited for a seen pointer, which the dark keyboard hides: every
                // send was withheld until "3 errors in a row" (logs 11-06: 76 s, 16 model calls, nothing sent).
                DebugLog.write("tap on the keyboard's Return key: pressing Return instead")
                act["action"] = .str("key")
                act["combo"] = .str("enter")
                for k in ["x", "y", "precise"] { act[k] = nil }
            }
            if act["action"]?.str == "tap", let rowTarget, let shown = screen?.frame, let row = rowTarget(shown),
               let y = act["y"]?.double, (140...880).contains(y), abs(y / 1000 - row.y) > 0.025 {
                // A tap into the chat list body while this run's chat is listed once, read on this phone: its row.
                // logs 11-06: "the 主人蓝海乐 row is visible", tapped 小柳 and then another group, back twice.
                DebugLog.write(String(format: "tap on the chat list moved to the target chat's row (y %.3f → %.3f)", y / 1000, row.y))
                act["x"] = .int(Int((row.x * 1000).rounded()))
                act["y"] = .int(Int((row.y * 1000).rounded()))
            }
            if let controls, let shown = screen?.frame {
                func use(_ hit: ControlBook.Hit, _ role: String) {
                    act["action"] = .str("tap")
                    act["x"] = .int(Int((Double(hit.point.x) * 1000).rounded()))
                    act["y"] = .int(Int((Double(hit.point.y) * 1000).rounded()))
                    act["learned"] = .str(role)
                    act["control"] = .str(hit.id)
                }
                if act["action"]?.str == "back", let hit = controls.find("back", in: shown) {
                    // Here the back swipe did nothing before and this button worked: tap it, no swipe first.
                    DebugLog.write(String(format: "back: tapping the learned back button at (%.3f, %.3f)", hit.point.x, hit.point.y))
                    use(hit, "back")
                } else if act["action"]?.str == "tap", unsent != nil, let x = act["x"]?.double, let y = act["y"]?.double,
                          let hit = controls.find("send", in: shown),
                          Self.sends(act) || hypot(x / 1000 - Double(hit.point.x), y / 1000 - Double(hit.point.y)) <= 0.12 {
                    // The send button found by how it looked when a send went out, not the model's guess of it.
                    DebugLog.write(String(format: "send: the learned send button at (%.3f, %.3f), score %.2f", hit.point.x, hit.point.y, hit.score))
                    use(hit, "send")
                }
            }
            let name = act["action"]?.str ?? ""
            var justSent: String?
            if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil, !["wait", "done", "fail"].contains(name) {
                record(planned.shot, ["action": .str("send verification"), "reason": .str(Self.sendVerificationReason)])
                return false
            }
            if i > 0, ["tap", "done", "fail"].contains(name) {
                // Inspect drawing/typing before a later UI tap or a terminal claim about its result.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                return false
            }
            if name == "replan" || stuck {
                if stuck { act["performed"] = .bool(false) }
                record(planned.shot, act)
                try await replan(stuck: true) // preserve recovery reason and completed work in the planner context
                return false
            }
            if i == 0 {
                // traces(33): enter the chat, decide the avatar is wrong, go back, enter, go back... twice is enough.
                // The leaving move (back) is the one refused, so the run stays where it can do the task.
                if let guarded = bounceGuard, Self.sameSpot(guarded.stop, act) {
                    bounceRefused += 1
                    if bounceRefused >= 3 {
                        record(planned.shot, ["action": .str("fail"), "reason": .str("kept going back and forth between two screens")])
                        return true
                    }
                    record(planned.shot, ["action": .str("loop"), "reason": .str(Self.loopReason)])
                    return false
                }
                if bounceGuard == nil, let first = Self.bounce(act, after: steps) {
                    if Self.leaves(act) {  // this move restarts the circle: refuse it now
                        bounceGuard = (stop: act, other: first)
                        bounceRefused = 1
                        record(planned.shot, ["action": .str("loop"), "reason": .str(Self.loopReason)])
                        return false
                    }
                    bounceGuard = (stop: first, other: act)  // go ahead, but not back again
                    DebugLog.write("loop: back and forth twice; going on, the move back is refused from now on")
                }
            }
            let unsentReason: String? = endAfterSend != nil && unsent != nil
                ? "The requested message still awaits sending. Inspect the current draft, correct any visible mistake, send once, then verify a NEW matching message before claiming done."
                : nil
            if name == "done", let missing = unsentReason ?? (inkSeen == false ? Self.noInkReason : Self.unmadeResult(task: task, steps: steps)) {
                doneRejected += 1
                if doneRejected >= 3 {  // it keeps claiming a result it did not make: stop and ask the user
                    record(planned.shot, ["action": .str("fail"), "reason": .str("claimed done 3 times without doing it: " + missing)])
                    return true
                }
                record(planned.shot, ["action": .str("done rejected"), "reason": .str(missing)])
                return false
            }
            if name == "done", partFinished(act, shot: planned.shot) { return false }
            if name != "done" && name != "fail" {
                try await gate?()
                try await screen?.requireFrame(after: nil)
                // Home and wait do not use coordinates or the current focus. Animation cannot make their target stale.
                if i == 0, !["home", "wait"].contains(name), act["home_recovery"] != .bool(true), seen != screen?.frame,
                   Vision.changed(seen, screen?.frame, ignore: spots, caret: true) {
                    staleRun += 1
                    // Coordinates read off a screen that moved under them are never sent. But some screens never hold
                    // still (a live clock icon, a video, an animated background): when the model, looking again at a
                    // newer screen, picks the same spot, the change did not move the target. An action with a target
                    // goes ahead at once when nothing changed where it lands (a new bubble, the keyboard rising elsewhere):
                    // each drop is another model call, 7–15 s each when the model was slow (logs 11-08: 4 drops in one
                    // report). Without a target (typing, keys) that waits for two drops as before.
                    let again = lastStale.map { Self.sameSpot($0, act) } ?? false
                    let target = pointerPath(act)
                    let safe = again || ((staleRun > 2 || !target.isEmpty)
                        && !Vision.changedNear(seen, screen?.frame, around: target))
                    if !safe {
                        lastStale = act
                        if staleRun >= 5 {  // it keeps moving right there: let the planner look afresh
                            staleRun = 0
                            lastStale = nil
                            record(screen?.frame, ["action": .str("stale plan"),
                                                   "reason": .str("the screen keeps changing where the action would land; planning again")])
                            try await replan(stuck: true)
                            return false
                        }
                        record(screen?.frame, ["action": .str("stale plan"), "reason": .str("screen changed while the model was responding; inspect again")])
                        if staleRun > 2 { await screen?.settled() }
                        return false
                    }
                    DebugLog.write(again ? "stale plan \(staleRun) in a row: the newer look chose the same spot; acting"
                                         : "stale plan \(staleRun) in a row: nothing changed where this action lands; acting")
                }
                staleRun = 0
                lastStale = nil
                if name == "type", let refused = outgoingGuard?(act["text"]?.str ?? "") {
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(refused)])  // never typed
                    return false
                }
                if name == "type", let pendingInput {
                    record(planned.shot, ["action": .str("blocked"),
                        "reason": .str("Text was already entered: \(pendingInput). Inspect the current field. "
                            + "Do not clear, retype, or paste over correct text; send it once if correct. "
                            + "Only use explicit correction keys if a visible mistake needs fixing.")])
                    return false
                }
                // Lan Agent's keyboard has no letter keys to see, but it reports itself: a field it is up for is focused.
                if name == "type", keyboardGuard, noKeyboard < 2, let shown = screen?.frame, Vision.image(shown) != nil,
                   !CandidatePicker.keyboardUp(in: shown), ourKeyboardOnScreen?() != true {
                    noKeyboard += 1
                    aimNext = true
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.noKeyboardReason)])  // never typed
                    return false
                }
                if name == "type", keyboardGuard, sentTexts.contains(Self.typedKey(act["text"]?.str ?? "")) {
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.sentAgainReason)])  // never typed
                    return false
                }
                if name == "type", keyboardGuard, let shown = screen?.frame {
                    let text = act["text"]?.str ?? "", key = Self.typedKey(text), count = CandidatePicker.shows(text, in: shown)
                    if let base = typedBase[key], count > base {
                        record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.sentAgainReason)])  // never typed
                        return false
                    }
                    if typedBase[key] == nil { typedBase[key] = count }
                }
                if name == "type" { noKeyboard = 0; unsent = act["text"]?.str ?? ""; quietSinceSend = 0 }
                if name == "tap" {
                    let dead = deadTaps.filter({ Self.sameSpot($0, act) }).count
                    if dead > Self.deadTapNudges.count {
                        record(planned.shot, ["action": .str("refused"), "reason": .str(Self.deadTapReason)])
                        return false
                    }
                    if dead > 0, let x = act["x"]?.double, let y = act["y"]?.double {
                        // Live test 11-08: the alarm's ✓ was missed by 0.027 down, and the same spot was clicked again
                        // and again. User: where it takes repeated clicks, click around that spot until it is found.
                        let (dx, dy) = Self.deadTapNudges[dead - 1]
                        act["x"] = .num(min(max(x + dx * 1000, 0), 1000))
                        act["y"] = .num(min(max(y + dy * 1000, 0), 1000))
                        act["nudged"] = .int(dead)
                        DebugLog.write(String(format: "tap (%.0f, %.0f) did nothing %ld time(s); trying (%+.3f, %+.3f) off it", x, y, dead, dx, dy))
                    }
                }
                onDoing?(.acting(act))  // the thought (on the first act) names the target
                let started = now()
                if name == "tap", missed || aimNext || (unsent != nil && Self.sends(act)) {
                    act["precise"] = .bool(true) // a pending message's first send also requires a verified landing
                }
                if name == "path", act["smooth"] == nil, Self.isGentleBend(points(act), aspect: screen?.aspect ?? 9 / 19.5) {
                    act["smooth"] = .bool(true)  // recorded, so the review and the next look know it was a curve
                }
                momentum = name == "swipe"
                actFrame = screen?.frame
                do { try await perform(act) }
                catch let input as InputNeedsVerification {
                    if input.fieldMayBeComplete { pendingInput = input.expected }
                    lastActed = now()
                    record(planned.shot, ["action": .str("compose"), "expected": .str(input.expected),
                                          "remaining": .str(input.remaining), "reason": .str(input.localizedDescription),
                                          "field_may_be_complete": .bool(input.fieldMayBeComplete)])
                    timing.frameMs += try await settle()
                    return false // inspect candidates before any further action in the batch
                }
                // A rejected command did not send anything. Commit only after the gesture succeeds.
                if name == "key", ["cmd+a", "backspace", "delete"].contains(act["combo"]?.str?.lowercased() ?? "") {
                    pendingInput = nil
                }
                if let text = unsent, Self.sends(act) || act["learned"] == .str("send") {
                    if name == "tap", let x = act["x"]?.double, let y = act["y"]?.double, let before = actFrame {
                        sendTap = (CGPoint(x: x / 1000, y: y / 1000), before)  // learned at the end if the run is done
                    }
                    sentTexts.insert(Self.typedKey(text)); unsent = nil; pendingInput = nil; quietSinceSend = 0
                    justSent = text
                }
                lastActed = now()
                let s = lastActed - started
                timing.hidMs += s * 1000
                act["act_s"] = .num((s * 100).rounded() / 100)
                spots += pointerPath(act)
                pointerAt = spots.last!
                if let guarded = bounceGuard, !Self.sameSpot(guarded.stop, act), !Self.sameSpot(guarded.other, act) {
                    (bounceGuard, bounceRefused) = (nil, 0)  // the run moved on from the back-and-forth
                }
            }
            record(planned.shot, act)
            if name == "done" || name == "fail" { return true }
            if returnSent {  // sent and checked: nothing is left to look at or tap
                record(nil, ["action": .str("done"), "answer": .str("sent with Return")])
                return true
            }
            if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil {
                // The rest of a type/send/navigation batch was planned before the send. Drop it and verify afresh.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                if let text = justSent, let sendReceipt {
                    let confirmed = await sendReceipt(text)
                    try Task.checkCancellation()
                    if confirmed {
                        record(screen?.frame, ["action": .str("done"), "answer": .str("sent message verified after the original request"),
                                               "source": .str("send receipt")])
                        return true
                    }
                }
                if name == "tap", let text = justSent, sendCorrections < 2, let before = seen, let after = screen?.frame {
                    var recovery: String?
                    if let draft = CandidatePicker.mistypedDraft(text, before: before, after: after) {
                        recovery = "The send tap added a letter to the SAME input field: \(draft). Correct only the visible extra characters."
                    } else if CandidatePicker.unchangedDraft(text, before: before, after: after) {
                        // A second frame must still show that same complete draft. A transient/unknown result
                        // or a new matching bubble keeps the existing send protection.
                        let confirmation = now()
                        await screen?.afterAction(since: confirmation)
                        try await screen?.requireFrame(after: confirmation)
                        if let checked = screen?.frame, CandidatePicker.unchangedDraft(text, before: before, after: checked) {
                            recovery = "The SAME input field still contains the complete correct draft in two post-action observations. Keep it unchanged and correct the send control's landing."
                        }
                    }
                    if let recovery {
                        sendCorrections += 1
                        sentTexts.remove(Self.typedKey(text)); unsent = text; pendingInput = text; quietSinceSend = 0
                        aimNext = true
                        record(screen?.frame, ["action": .str("send missed"), "reason": .str(recovery
                            + " No new matching message is visible. Send once with visual aim, then verify. Do not retype or replace correct text.")])
                    }
                }
                return false
            }
            if startsDrawing, drawing.contains(name) {
                // A first stroke may pan a canvas if the drawing tool was not actually active.
                // Observe it before spending the rest of the batch on the same mistaken state.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                if let share = Self.inkShare(before: seen, after: screen?.frame, stroke: strokePoints(act)) {
                    if share < 0.25 {
                        inkSeen = inkSeen ?? false
                        if let tap = Self.tapBeforeStroke(steps) { deadTaps.append(tap) }  // that tap picked no pen
                        record(screen?.frame, ["action": .str("no ink"), "reason": .str(Self.noInkReason)])
                    } else {
                        inkSeen = true
                    }
                }
                return false
            }
            let following = i < acts.count - 1 ? acts[i + 1].act["action"]?.str : nil
            if name == "tap", following != nil {
                // A tap may open a page, change tools or undo content. The rest of this plan was made on the
                // pre-tap screenshot; inspect its result before issuing another tap, typing or drawing.
                // Independent strokes and type-then-key batches still run together.
                timing.frameMs += try await settle()
                steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
                noteDeadTap()
                return false
            }
        }
        timing.frameMs += try await settle()
        // feedback for the next round
        steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
        noteDeadTap()
        return false
    }

    /// A tap that changed nothing on screen counts as dead, like one before a stroke that left no line: the same spot
    /// twice is refused, so the agent tries another control instead of the same one again and again.
    private func noteDeadTap() {
        noteLearnedControls()
        guard let last = steps.last, last["action"]?.str == "tap", last["changed"] == .bool(false) else { return }
        deadTaps.append(last)
    }

    /// Learned buttons from what this action did: a learned spot that changed nothing is counted against it; the
    /// first top-of-screen tap that worked right after a back swipe did nothing is learned as this screen's back.
    private func noteLearnedControls() {
        guard let controls, let last = steps.last, let changed = last["changed"]?.bool else { return }
        if let id = last["control"]?.str {
            if !changed { controls.failed(id) } else if last["learned"] == .str("back") { controls.worked(id) }
        }
        switch last["action"]?.str {
        case "back":
            backMissed = !changed
        case "tap":
            if backMissed, changed, last["learned"] == nil, let x = last["x"]?.double, let y = last["y"]?.double,
               y <= 150, let before = actFrame {
                controls.learn("back", at: CGPoint(x: x / 1000, y: y / 1000), on: before)
            }
            backMissed = false
        default:
            break
        }
    }

    /// Text in without a model look per phrase. A paste when iOS lets this app fill the pasteboard and the text then
    /// newly shows on screen (read on this phone); uncertain input stays for inspection. Else pinyin,
    /// each candidate found on the candidate row (CandidatePicker) and tapped. A candidate not found that way is left
    /// to the model as before (InputNeedsVerification, a "compose" step).
    private func typeFast(_ text: String) async throws {
        guard let phone else { return }
        if typedInto == nil { typedInto = lastTap }
        if returnSends && !boxCleared {  // a draft, or text a swipe across the keyboard typed, would join the reply
            boxCleared = true             // (PC harness: 你好 left in 测试群's box; 给我们发微吧 from a home flick)
            try await phone.key("cmd+a")
            try await phone.key("backspace")
        }
        // Lan Agent's keyboard first: exact text in place, no pinyin candidates and no app switch (phase B).
        if Pasteboard.needed(text), let keyboardType, await keyboardType(text) {
            if returnSends {
                try await phone.key("enter")
                returnSent = true
                return DebugLog.write("type: typed by Lan Agent's keyboard, sent with Return")
            }
            return DebugLog.write("type: typed by Lan Agent's keyboard")
        }
        if Pasteboard.needed(text), try await typedQuickly(text, phone: phone) {
            if returnSends {
                try await phone.key("enter")
                returnSent = true
                return DebugLog.write("type: typed as pinyin, seen in the field, sent with Return")
            }
            return DebugLog.write("type: typed as pinyin and seen in the field")
        }
        if Pasteboard.needed(text) || Pasteboard.prefersExact(text), !pasteHopOff {
            let hop = await pasteHop?(text) ?? (Pasteboard.put(text) ? .filled : .refused)
            if hop == .lost {  // no further typing or sending when the app switch lost its destination
                pasteHopOff = true
                throw BlindError(reason: "paste target could not be verified after switching apps; no text was pasted")
            }
            if hop == .filled {
                // A missing keyboard or uncertain OCR does not prove the paste missed. Keep the field and inspect
                // it rather than deleting a potentially correct result and issuing another paste (logs34).
                let pasted = try await pasteChecked(text, phone: phone)
                if pasted {
                    if returnSends {  // checked: exactly this text is in the box. The run ends here: a look at the
                        // empty box afterwards tapped "发送" on the keyboard's space bar (logs(20)).
                        try await phone.key("enter")
                        returnSent = true
                        return DebugLog.write("type: pasted, seen in the field, sent with Return")
                    }
                    return DebugLog.write("type: pasted and seen in the field")
                }
                trace?.write(screen?.frame, kind: "input verification", ["method": .str("paste"), "verified": .bool(false)])
                throw InputNeedsVerification(expected: text, remaining: "", fieldMayBeComplete: true)
            } else {
                DebugLog.write("type: the pasteboard refused the text")
            }
        }
        guard !Pasteboard.requiresPaste(text) else {
            throw DeviceError(message: "Exact paste is unavailable for this text. Keyboard fallback cannot preserve it safely; no replacement text was typed.")
        }
        var rest = text
        while true {
            do { return try await phone.type(rest) }
            catch let input as InputNeedsVerification {
                // Like a person: of the candidates, the longest that starts the phrase; the keyboard keeps the rest of
                // the pinyin open for the next pick. Whole six-character phrases are often not offered (logs(15)).
                var left = input.expected
                while !left.isEmpty {
                    guard let frame = await freshFrame(), let pick = CandidatePicker.longestStart(of: left, in: frame) else {
                        throw InputNeedsVerification(expected: left, remaining: input.remaining)
                    }
                    try await phone.tap(pick.spot.x, pick.spot.y, aim: false)
                    DebugLog.write("type: picked “\(pick.text)” on the candidate row")
                    left = String(left.dropFirst(pick.text.count))
                }
                if input.remaining.isEmpty { return }
                rest = input.remaining
            }
        }
    }

    /// Pinyin with the first candidate per chunk and one look at the end; true when the whole text newly shows.
    /// Uncertain text stays in the field for the next model look. Never on the 9-key pinyin keyboard, which
    /// turns letters into digit keys ("nihao" came out as 你哄啊).
    private func typedQuickly(_ text: String, phone: Gestures) async throws -> Bool {
        // Repeatedly unsupported keyboards use paste first until the next watch starts.
        guard !Pasteboard.prefersExact(text), pinyinMisses < 2, let start = await freshFrame() else { return false }
        if CandidatePicker.nineKey(in: start) {
            pinyinMisses += 1
            DebugLog.write("type: the keyboard is 9-key pinyin; switch to the full pinyin keyboard (拼音-全键盘) in iOS Settings")
            return false
        }
        let before = CandidatePicker.shows(text, in: start)
        try await phone.typeQuick(text)
        var after = await freshFrame()
        if let shown = after, CandidatePicker.shows(text, in: shown) <= before {  // the frame may predate the last key
            try? await Task.sleep(nanoseconds: 600_000_000)
            after = await freshFrame()
        }
        if let shown = after, CandidatePicker.shows(text, in: shown) > before { return true }
        trace?.write(after, kind: "input verification", ["method": .str("pinyin"), "verified": .bool(false)])
        DebugLog.write("type: pinyin unconfirmed; kept the field for inspection")
        throw InputNeedsVerification(expected: text, remaining: "", fieldMayBeComplete: true)
    }

    /// Cmd+V, answering iOS's paste prompt if it comes up, and true when the text newly shows on screen (looked at
    /// twice: the first frame may come from before the paste).
    private func pasteChecked(_ text: String, phone: Gestures) async throws -> Bool {
        let before = await freshFrame().map { CandidatePicker.count(text, in: $0) } ?? 0
        try await phone.key("cmd+v")
        var after = await freshFrame()
        if let shown = after, let allow = CandidatePicker.allowPaste(in: shown) {  // iOS asks: allow, once
            try await phone.tap(allow.x, allow.y, aim: false)
            DebugLog.write("type: iOS asked to allow the paste; allowed")
            after = await freshFrame()
        }
        if let shown = after, CandidatePicker.count(text, in: shown) <= before {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            after = await freshFrame()
        }
        return after.map { CandidatePicker.count(text, in: $0) > before } ?? false
    }

    /// The screen a moment after the last keys, for reading text on it.
    private func freshFrame() async -> Data? {
        let since = now()
        try? await Task.sleep(nanoseconds: 300_000_000)
        await screen?.afterAction(since: since)
        return screen?.frame
    }

    /// The last action was a swipe: a scrolled list coasts on after the finger lifts, and a look taken meanwhile
    /// was out of date by the time the model answered ("stale plan" again and again in traces(39)).
    private var momentum = false

    private func settle() async throws -> Double {
        let started = now()
        onDoing?(.looking)
        if momentum { momentum = false; try await Task.sleep(nanoseconds: 700_000_000) }
        await screen?.afterAction(since: lastActed)
        do {
            try await screen?.requireFrame(after: lastActed)
        } catch where screen?.live == false && !(error is CancellationError) {
            // The screen dropped right after the move: not this step's failure. The next look pauses for it
            // (waitForScreen), then goes on from here.
            DebugLog.write("frame after the move: the screen is gone; the next look waits for it")
        }
        return (now() - started) * 1000
    }

    private static let observedActions: Set<String> = ["tap", "swipe", "back", "home", "key", "type", "path", "circle", "compose", "open"]
    /// Planner and guard records never erase the result of the last actual gesture.
    private var lastObservedAction: JObject? {
        steps.last { Self.observedActions.contains($0["action"]?.str ?? "") && $0["performed"] != .bool(false) }
    }
    private var missed: Bool { lastObservedAction?["changed"] == .bool(false) }

    /// True when the actor picks the same action as its last limit-1 moves and the last one did nothing.
    /// Repeating a move that still changes the screen (e.g. scrolling down a long list) is progress, not a loop.
    func repeating(_ act: JObject, limit: Int = 3) -> Bool {
        if recoveringSend(act) { return false }
        if act["action"] == .str("tap"), act["precise"] == .bool(true),
           lastObservedAction?["precise"] != .bool(true) {
            return false // this bounded delivery-mode retry must execute before the generic loop guard
        }
        let moves = steps.filter {
            Self.observedActions.contains($0["action"]?.str ?? "") && $0["performed"] != .bool(false)
        }.suffix(limit - 1)
        return moves.count == limit - 1 && moves.allSatisfy { Actions.sameTarget($0, act) }
            && moves.last?["changed"] != .bool(true)
    }

    private func recoveringSend(_ act: JObject) -> Bool {
        aimNext && unsent != nil && (1...2).contains(sendCorrections) && act["action"] == .str("tap") && Self.sends(act)
    }

    /// Each part of a plan gets its own steps (specs/004 §2.1): the alarm + sun + group message task spent all 40 on
    /// the alarm (live test 11-08). 20 a part, never fewer than `base`, at most 100.
    static func stepBudget(plan: String, base: Int) -> Int {
        let parts = Self.parts(of: plan).count
        guard parts >= 2 else { return base }
        return max(base, min(parts * 20, 100))
    }

    /// The numbered lines of a plan ("1. ...", "2) ...", "3、..."), trimmed.
    static func parts(of plan: String) -> [String] {
        plan.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^\d{1,2}\s*[.)、．]"#, options: .regularExpression) != nil }
    }

    static let partSteps = 20       // steps on one part before Codex looks and drives
    static let takeoverSteps = 15   // steps Codex drives after a stall, until its part is done

    /// What the executor is told about its part (nothing for a plan of one part or a fixed plan).
    private var partFocus: String {
        guard parts.count >= 2, planner != nil, partIndex < parts.count else { return "" }
        var text = "Current part (\(partIndex + 1) of \(parts.count)): \(parts[partIndex])\n"
        if !doneParts.isEmpty { text += "Already done: " + doneParts.joined(separator: " | ") + "\n" }
        return text + "Work on the current part only. When it is finished on the screen, answer done with what it achieved;"
            + " then the next part begins.\n\n"
    }

    /// The executor's (or Codex's) "done" on a plan of several parts: the next part begins, the last one ends the run.
    /// A part Codex rescued is done: the executor takes the next one. True: the run goes on.
    private func partFinished(_ act: JObject, shot: Data?) -> Bool {
        guard parts.count >= 2, partIndex < parts.count else { return false }
        let n = partIndex + 1
        doneParts.append(parts[partIndex])
        record(shot, ["action": .str("part done"), "part": .int(n), "by": .str(act["by"]?.str ?? "actor")])
        (partIndex, stepsInPart) = (partIndex + 1, 0)
        if act["by"]?.str == "planner" { takeover = 0 }
        return partIndex < parts.count
    }

    /// The executor gave up: Codex takes over once before the user is asked. Never after a message went out (it must
    /// not go twice), nor when Codex itself gave up.
    private func rescue() async throws -> Bool {
        guard let last = steps.last, last["action"]?.str == "fail", last["by"]?.str == "actor",
              planner != nil, !rescued, sentTexts.isEmpty else { return false }
        rescued = true
        try await replan(stuck: true)
        return true
    }

    /// A remembered way as the plan: its steps as hints, not numbered parts.
    static func rememberedPlan(_ recipe: RouteBook.Recipe) -> String {
        "Do it the way it was done before; adapt any text, time or name to this goal, and look at each result:\n"
            + recipe.lines.map { "- " + $0 }.joined(separator: "\n")
    }

    func replan(stuck: Bool = false) async throws {
        guard let planner else { throw LLMError(message: "no planner model") }
        var prompt = "Goal: \(task)"
        if stuck {
            let last = steps.last ?? JObject()
            prompt += "\n\nThe previous plan got stuck (last event: \(pyStr(last["action"])) \(last["reason"]?.str ?? "")):"
                + "\n\(plan)\nLook at the current screen and plan from here, another way if needed."
                + "\nKeep steps that already succeeded; resume from the current screen."
                + "\n\nRecent actions:\n\(recentActions)"
            if !doneParts.isEmpty {
                prompt += "\n\nAlready done and checked on the screen (never redo): " + doneParts.joined(separator: " | ")
                    + "\nPlan only what is left."
            }
        }
        let (reply, seconds, frame) = try await ask("planner", planner, plannerPrompt, prompt)
        let (en, zh) = Actions.parsePlan(reply)
        plan = en
        (parts, partIndex, stepsInPart) = (Self.parts(of: en), 0, 0)
        record(frame, ["action": .str(stuck ? "replan (stuck)" : "plan"), "plan": .str(en), "plan_zh": .str(zh),
                       "think_s": .num(seconds)])
        if stuck {
            takeover = Self.takeoverSteps
            record(nil, ["action": .str("planner drives"),
                         "reason": .str("the executor did not get on: Codex drives until this part is done, at most \(Self.takeoverSteps) steps")])
        }
    }

    private var recentActions: String {
        // actions and their effect only: echoing earlier thoughts makes the model repeat them instead of looking
        let hidden: Set<String> = ["t", "plan", "plan_zh", "think_s", "act_s", "shot", "thought", "thought_zh", "changed", "by"]
        let history = steps.suffix(8).filter { $0["plan"] == nil }.map { s -> String in
            let effect = s["changed"] == .bool(true) ? " -> screen changed"
                : s["changed"] == .bool(false) ? " -> screen did NOT change" : ""
            return String(PyJSON.dumps(s.without(hidden)).prefix(300)) + effect
        }.joined(separator: "\n")
        return history.isEmpty ? "(none)" : history
    }

    func nextActions() async throws -> [Planned] {
        guard let actor else { throw LLMError(message: "no actor model") }
        let index = steps.count - 1
        if index > learnedThrough, let last = steps.last {
            learnedThrough = index
            if let frame = shots[index] ?? screen?.frame, let scene = Vision.experienceScene(frame), let image = Vision.image(frame) {
                experience?.observeUnconfirmedTap(goal: task, scene: scene,
                    aspect: Double(image.width) / Double(image.height), action: last)
            }
        }
        var prompt = "Goal: \(task)\n\nPlan:\n\(plan)\n\n\(partFocus)Recent actions:\n\(recentActions)\n\nNext action?"
        let driving = takeover > 0 && planner != nil
        if driving { takeover -= 1 }
        if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil { prompt += "\n\n" + Self.sendVerificationReason }
        if let controls, let shown = screen?.frame {
            if unsent != nil, let hit = controls.find("send", in: shown) {
                prompt += "\n\nLearned on this phone: this screen's send button is at x \(Int(Double(hit.point.x) * 1000)), "
                    + "y \(Int(Double(hit.point.y) * 1000)); a message went out from there before. Tap it there once the text is complete."
            }
            if let hit = controls.find("back", in: shown) {
                prompt += "\n\nLearned on this phone: on this screen the back swipe does nothing; to go back, tap the back "
                    + "button at x \(Int(Double(hit.point.x) * 1000)), y \(Int(Double(hit.point.y) * 1000))."
            }
        }
        // Phase B (specs/004): the text read on this phone with where it is, so a labelled control is tapped where it
        // really is instead of where the model estimates it from the picture.
        if readsScreenText, let shown = screen?.frame,
           let list = Self.screenText(CandidatePicker.rows(in: shown, top: 0.055, bottom: 1)) {
            prompt += "\n\nText read on this screen (\"text\" x y, 0-1000; tap these coordinates for a labelled control):\n" + list
        }
        if ourKeyboardOnScreen?() == true {
            prompt += "\n\nThe keyboard on screen is the app's own (\"Lan Agent 輸入法\"): the field is focused, use type."
        }
        var reply = ""
        for attempt in 0..<3 {  // retry unparseable replies, a little less deterministically
            let (text, seconds, frame) = try await ask("actor", driving ? planner ?? actor : actor, actorPrompt, prompt,
                                                       temperature: 0.4 * Double(attempt))
            reply = text
            var acts: [JObject]
            do { acts = try Actions.parseActions(text) } catch {
                if driving {  // Codex answered with no action: Doubao goes on rather than Codex being asked again and again
                    takeover = 0
                    DebugLog.write("takeover: Codex's reply held no action; the executor goes on")
                    return try await nextActions()
                }
                prompt += "\n\nYour previous reply could not be parsed (\(String(error.localizedDescription.prefix(160))))."
                    + " No action from that reply was executed."
                    + " Reply with one brief THINK line followed immediately by valid DO lines; no extra explanation."
                continue
            }
            if missed, let last = lastObservedAction, acts[0]["action"] == .str("home"),
               last["action"] == .str("home") || last["home_recovery"] == .bool(true) {
                if !homeRecoveryTried {
                    homeRecoveryTried = true
                    return [Planned(act: ["action": .str("key"), "combo": .str("cmd+h"), "home_recovery": .bool(true),
                                          "reason": .str("Home changed nothing; trying keyboard Home once"),
                                          "think_s": .num(seconds)], shot: frame)]
                }
                return [Planned(act: ["action": .str("fail"),
                                      "reason": .str("Home changed nothing after the keyboard fallback; the Home route could not be verified"),
                                      "think_s": .num(seconds)], shot: frame)]
            }
            if missed, let last = lastObservedAction, Actions.sameTarget(acts[0], last), !recoveringSend(acts[0]) {
                if acts[0]["action"] == .str("tap") {
                    if last["precise"] == .bool(true) {
                        let reason = "tap target unchanged after a precision retry; inspect another route, keep completed work"
                        return [Planned(act: ["action": .str("replan"), "reason": .str(reason), "think_s": .num(seconds)], shot: frame)]
                    }
                    // The reply is syntactically valid. Spend one closed-loop aim attempt rather than asking
                    // the model the same question three times and misreporting it as a parsing failure.
                    acts[0]["precise"] = .bool(true)
                    acts[0]["think_s"] = .num(seconds)
                    return [Planned(act: acts[0], shot: frame)]
                }
                prompt += "\n\nYou just proposed \(PyJSON.dumps(Actions.key(acts[0]))) again, but it changed nothing last "
                    + "time. Choose a different action (another position, a shorter swipe, or another way)."
                continue
            }
            acts[0]["think_s"] = .num(seconds)
            for i in acts.indices { acts[i]["by"] = .str(driving ? "planner" : "actor") }
            return acts.map { Planned(act: $0, shot: frame) }
        }
        throw Actions.ParseError(message: "actor gave no valid action: \(reply.prefix(200))")
    }

    private func perform(_ a: JObject) async throws {
        guard let phone else { throw DeviceError(message: "no phone") }
        func p(_ k: String) -> Double { (a[k]?.double ?? 0) / 1000 }
        switch a["action"]?.str {
        case "tap":
            lastTap = CGPoint(x: p("x"), y: p("y"))
            try await phone.tap(p("x"), p("y"), aim: (a["precise"]?.bool ?? false) || missed || aimNext)
            aimNext = false
        case "swipe": try await phone.swipe(p("x1"), p("y1"), p("x2"), p("y2"), hold: true)
        case "path":
            let pts = a["smooth"]?.bool == true ? smoothCurve(points(a)) : points(a)
            try await phone.drag(pts.map { CGPoint(x: $0.x / 1000, y: $0.y / 1000) }, hold: true)
        case "circle":
            // A small circle (an eye) came out as an open arc, its first or last bit lost: go a quarter turn
            // further so the ends overlap.
            try await phone.drag(circle(p("x"), p("y"), p("r"), aspect: screen?.aspect ?? 9 / 19.5,
                                        extra: p("r") < 0.06 ? 0.25 : 0), hold: true)
        case "type":
            let text = a["text"]?.str ?? ""
            if fastText || Pasteboard.prefersExact(text) || (Pasteboard.needed(text) && keyboardType != nil) {
                try await typeFast(text)
            } else { try await phone.type(text) }
        case "key": try await phone.key(a["combo"]?.str ?? "")
        case "home": try await phone.goHome()
        case "back": try await phone.goBack()
        case "open":
            let app = a["app"]?.str ?? ""
            guard let openApp else { throw DeviceError(message: "Opening apps by name is not available here; use the Home Screen.") }
            guard try await openApp(app) else {
                throw DeviceError(message: "Could not open \(app): it was neither on the first Home Screen pages nor in Search under this name.")
            }
        case "wait": break
        case let other: throw Actions.ParseError(message: "unknown action \(other ?? "nil")")
        }
    }

    /// Show a run without running it (demo data).
    func showMock(task: String, plan: String, steps: [JObject], running: Bool) {
        self.task = task
        self.plan = plan
        self.steps = steps
        self.running = running
    }

    /// Python's str() of a value in an f-string (None for a missing key).
    private func pyStr(_ v: JValue?) -> String {
        guard let v else { return "None" }
        if case .str(let s) = v { return s }
        return PyJSON.dumps(v)
    }
}
