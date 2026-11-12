import Foundation

/// The screen feed is gone; acting now would be guessing.
struct BlindError: LocalizedError {
    var reason = "lost the phone screen: reconnect Screen Mirroring"
    /// Sharing is on and only a new frame is late: looking again is the fix, there is nothing for the user to do.
    var sharingOn = false
    var errorDescription: String? { reason }
}

/// The app is on no Home Screen page and Search lists no such app.
struct AppNotOnPhone: LocalizedError {
    let name: String
    var errorDescription: String? { name + " is not on this phone" }
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
    /// Press and hold (Pointer.longPress): WeChat's message menu (复制, 转发), an icon's menu.
    func longPress(_ x: Double, _ y: Double, seconds: Double) async throws
    /// The next tap is for something this big (half width and height, 0-1): Pointer clicks a first stop inside it.
    func aimLoosely(_ halfX: Double, _ halfY: Double)
    func goBack() async throws
    func reset() async throws
    func typeQuick(_ text: String) async throws
    func answerSharingQuestion() async throws -> Bool
}

extension Gestures {
    func typeQuick(_ text: String) async throws { try await type(text) }
    func answerSharingQuestion() async throws -> Bool { false }
    /// Fakes in tests: a long press is recorded as a tap there.
    func longPress(_ x: Double, _ y: Double, seconds: Double) async throws { try await tap(x, y, aim: false) }
    func aimLoosely(_ halfX: Double, _ halfY: Double) {}
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
    /// What the agent read and wrote down in this run (a price, a title, a name). A task across apps forgot what it had
    /// read in the last one and went back for it, ten times over (over USB 11-09): this goes with every look.
    private(set) var notes: [String] = []
    /// The text read on the screen the last reply was made on (with where it is): what a tap lands on, and how big it is.
    private var readRows: [[CandidatePicker.Piece]] = []
    /// How often each way off a screen was taken from that screen, in this run.
    private var departures: [(look: [UInt8], move: JObject, times: Int)] = []
    private var circleRefused = 0
    private var deadRefused = 0
    private var untypedSearches = 0  // searches refused because nothing was typed (twice at most per run)
    private var blindLooks = 0
    private(set) var takeover = 0
    private var stepsInPart = 0, rescued = false, troubles = 0
    /// 124 over the cloud 11-12 (g05): every type was refused, the part stalled, a new plan was made, and again, for ten
    /// minutes and ~290 steps with nothing on the screen moving. New plans in a row with nothing noted or finished between
    /// them; at stallLimit the run ends with what it found.
    private var stallsNoProgress = 0
    static let stallLimit = 3
    /// 125 stress test 11-12 (t06): typing was refused 110 times while Codex drove and new plans came 40 times, none of
    /// them through the executor's stall count. Refusals since the last note, part done or message sent; at refusalLimit
    /// the run ends with what it found.
    private var refusalsNoProgress = 0
    static let refusalLimit = 25
    /// 124 over the cloud 11-12 (e02): 行事曆 did not open, the model gave up, and 视频号, Bluetooth and Weather were never
    /// tried. In a goal of three parts or more, this many single things may fail and be written down; the run goes on.
    private var itemFailsLeft = 2
    static let oneThingFailedReason = "Not ended: one part could not be done; it is noted as 未能完成. Go on with the "
        + "other parts, then done, saying which part failed and why. Fail only if none of the rest can be done."
    /// The texts sent as messages into a chat (not a search's Return): only these are never typed again.
    private var messageSent: Set<String> = []
    /// Times the "added to the cart" toast came up in this run, and whether it showed on the last screen read.
    private var cartAdds = 0, cartToastShown = false
    static func addedToCart(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let text = AppNames.hans(rows.joined().map(\.text).joined())
        return ["加购成功", "已加入购物车", "成功加入购物车", "加入购物车成功", "已加购", "已添加到购物车"].contains { text.contains($0) }
    }
    static func cartNote(_ n: Int) -> String {
        "购物车：第\(n)次看到加购成功的提示，这一件已经加进去了（这次任务一共加了\(n)次）。同一件不要再点加入购物车，每点一次就多一件；目标要几件就只加几次。"
    }

    /// A text already sent that this one is: the same, or (4 characters or more) inside it or holding it.
    static func sameMessage(_ typed: String, in sent: Set<String>) -> String? {
        guard !typed.isEmpty else { return nil }
        if sent.contains(typed) { return typed }
        return sent.first { s in min(s.count, typed.count) >= 4 && (s.contains(typed) || typed.contains(s)) }
    }

    static func sentNote(_ text: String, to place: String?) -> String {
        "已在" + (place.map { "“\($0)”" } ?? "聊天里") + "发出：" + String(text.prefix(80))
    }
    private var sendIsMessage = false
    /// How many notes there were when the current part began, and the last part whose "done" was sent back once for
    /// having nothing written down (B8).
    private var notesAtPart = 0, emptyPartRefused = -1
    /// The screen just before the last paste (B4: what the paste put in is read against it).
    private var pasteFrame: Data?
    /// Opens of the app the run is already in, refused (once a run).
    private var sameAppRefused = 0
    /// The app a picture is shown full screen in, after that refusal: the next Home or open of it taps the picture's
    /// middle instead. 124 over the cloud 11-12 (g06) and in the watch: after the refusal the model went Home and opened
    /// WeChat again, WeChat came back on the same Seoul screenshot, and both models took it for Weather until the run failed.
    private var pictureIn: String?
    /// A listen heard what an earlier one did: the video started over, and listening again is refused.
    private var listenedAll = false
    static let videoLoopedNote = "（视频已经从头重播：这次听到的和前面基本相同，口播已经听全。不要再 listen，直接用上面听到的内容作答。）"

    static func repeatsHeard(_ new: String, before: [String]) -> Bool {
        func grams(_ s: String) -> Set<String> {
            let c = Array(s.filter { !$0.isWhitespace && !$0.isPunctuation })
            guard c.count > 1 else { return [] }
            return Set((0..<(c.count - 1)).map { String(c[$0...($0 + 1)]) })
        }
        let now = grams(new)
        guard now.count >= 20 else { return false }
        return before.contains { old in
            let was = grams(old)
            return !was.isEmpty && Double(now.intersection(was).count) / Double(now.count) >= 0.6
        }
    }
    /// The app a run is in when it starts without opening one: a task the WeChat watch gives starts in WeChat.
    private var startApp: String? { task.contains("微信会话") ? "微信" : nil }
    /// User 11-09: "未知的内容由codex先去完整走一遍并学会，然后后面交给豆包干". A task the phone has not done before is driven
    /// by the planner from the start and its way remembered; from then on the executor follows that way, and the planner
    /// comes only when it stalls. Fixed plans (watching WeChat) are not tasks of this kind.
    var plannerLeadsUnknown = false
    /// A finished task is looked at once more before it is reported (see wrongClaim). Fixed flows keep their own checks.
    var verifiesDone = false
    private var checksLeft = 2
    private var plannerLeads = false
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
    /// The keyboard's own Return while Lan Agent's keyboard is up: WeChat sends on it, and the board's Enter did
    /// nothing there (build104 live 11-08: "收到" stayed in the box twice). True when the keyboard pressed it.
    var keyboardReturn: (() async -> Bool)?
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
    /// What a paste would put in (UIPasteboard, set by AppModel): it is held for approval like typed text.
    var pasteboard: () -> String? = { nil }
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
    /// The chat titles each sent text went to (read at the send; none when the title did not read).
    private var sentPlaces: [String: Set<String>] = [:]
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
    private var pendingRefused = 0
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
    /// What the video on screen says (speech to text) and the subtitles it shows, for up to so many seconds (AppModel's
    /// listenToScreen). nil in tests and where it is not wired.
    var listen: ((Double) async -> String)?
    /// "Needs your help": asked when the actor gives up or errors repeat; nil = end the run as before.
    var onHelp: ((String) async -> HelpChoice)?
    private var helpAsked = 0
    /// A task from the cloud: nobody is at the phone to answer "needs your help". Build 116 over the cloud 11-10: six tasks
    /// asked, and each stood "running" until the cloud gave up on it (up to 9 minutes). It fails at once, saying why.
    var noHelp = false
    /// The answer the done check last refused, for a run that then gives up (see the fail below).
    private var rejectedAnswer: String?
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
        if ["blocked", "refused", "loop"].contains(step["action"]?.str ?? "") { refusalsNoProgress += 1 }
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

    /// Apps a goal may name to go into, with the words a model's thought uses for them.
    static let goalApps: [(name: String, also: [String])] = [
        ("拼多多", ["pinduoduo", "pdd"]), ("淘宝", ["taobao"]), ("京东", ["jd.com", "jingdong"]), ("美团", ["meituan"]),
        ("抖音", ["douyin", "tiktok"]), ("小红书", ["xiaohongshu", "rednote"]), ("快手", ["kuaishou"]),
        ("微信", ["wechat", "weixin"]), ("备忘录", ["notes"]), ("日历", ["calendar"]), ("设置", ["settings"]),
        ("天气", ["weather"]), ("股市", ["stocks"]), ("计算器", ["calculator"]), ("时钟", ["clock", "alarm"]),
        ("提醒事项", ["reminders"]), ("高德", ["amap", "gaode"]), ("safari", ["浏览器"]),
    ]

    /// 123 over the cloud 11-12: a goal of nine parts in seven apps followed a remembered way, did only the weather, and
    /// finished with made-up results for the other eight (拼多多 ¥3.9, a 验证群 message nobody sent); the check said OK.
    /// An app the goal names that this run never went into cannot have given a result. nil = may finish.
    static func unvisitedReason(task: String, steps: [JObject]) -> String? {
        let missing = unvisitedApps(task: task, steps: steps)
        guard !missing.isEmpty else { return nil }
        return "This run never went into " + missing.joined(separator: "、") + ": whatever the answer says about them is not "
            + "from this run. Open each of them now and read it there, or answer that those parts were not done."
    }

    static func unvisitedApps(task: String, steps: [JObject]) -> [String] {
        if steps.contains(where: { $0["action"]?.str == "takeover" }) { return [] }  // the user did part of it by hand
        let goal = AppNames.hans(task).lowercased().replacingOccurrences(
            of: #"(不要|不用|不必|别|勿|禁止)[^，,。；;！!？?\n]*"#, with: " ", options: .regularExpression)
        // Only what the model did and said while doing it: not the plan, nor this check's own words.
        let acted: Set<String> = ["open", "tap", "type", "note", "swipe", "key", "hold", "listen", "press", "back", "home", "wait", "path"]
        var said: [String] = []
        for s in steps where acted.contains(s["action"]?.str ?? "") {
            for key in ["thought", "thought_zh", "app", "text"] { if let v = s[key]?.str { said.append(v) } }
        }
        let seen = AppNames.hans(said.joined(separator: "\n")).lowercased()
        var missing: [String] = []
        for app in goalApps where goal.contains(app.name) {
            var words: [String] = [app.name]
            words += app.also
            words += AppNames.variants(app.name).map { AppNames.hans($0).lowercased() }
            if !words.contains(where: { !$0.isEmpty && seen.contains($0) }) { missing.append(app.name) }
        }
        return missing
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

    /// A tap on Lan Agent keyboard's Return key: the last of its one row of keys, lower right.
    static func onOurReturnKey(_ act: JObject) -> Bool {
        guard act["action"]?.str == "tap", let x = act["x"]?.double, let y = act["y"]?.double else { return false }
        return x >= 760 && y >= 700
    }

    /// Return, or a tap where 发送 sits (next to the box, or the keyboard's bottom-right key).
    /// cmd+v and the like: something goes into the box that was not typed.
    static func pastes(_ act: JObject) -> Bool {
        guard act["action"]?.str == "key" else { return false }
        return ["cmd+v", "command+v", "ctrl+v", "control+v"].contains((act["combo"]?.str ?? "").lowercased().filter { !$0.isWhitespace })
    }

    /// What a paste puts in, as approval is asked for it (unreadable: said so, and still asked).
    static func pastedText(_ board: String?) -> String {
        let text = (board ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? pastePlaceholder : String(text.prefix(300))
    }

    static let pastePlaceholder = "（粘贴的内容）"

    /// The app in front by what this run did: the last one it opened, unless it went Home or opened one by its icon
    /// since; with no open at all, the one it started in. nil: not known.
    /// Apps that send nothing to anyone: what is typed there stays on the phone.
    static let localApps = ["备忘录", "notes", "提醒事项", "reminders", "日历", "行事历", "calendar", "计算器", "calculator",
                            "时钟", "clock", "天气", "weather", "设置", "设定", "settings", "文件", "档案", "files", "股市", "stocks",
                            "计算机"]

    static func inLocalApp(_ steps: [JObject]) -> Bool {
        guard let app = appInFront(steps, startedIn: nil) else { return false }
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return localApps.contains { name == $0 || name.hasPrefix($0) }
    }

    static func appInFront(_ steps: [JObject], startedIn: String?) -> String? {
        for s in steps.reversed() {
            switch s["action"]?.str {
            case "open": return s["app"]?.str
            case "home": return nil
            case "tap" where opensByIcon(s): return nil
            default: continue
            }
        }
        return startedIn
    }

    static func stillInAppReason(_ app: String) -> String {
        // 125 in 测试群 11-12: the model sees a step's first 300 characters (recentActions), and how to close the picture
        // came after them. Short, the way out first.
        "Refused: still in \(app), never left it: nothing to open. This is a picture or video \(app) shows full screen "
            + "(a screenshot of another app is only a picture). Note what you need from it, then drag it down to close it."
    }

    /// Whether a text sent before would go where it went already: the title read now among those it was sent to. No
    /// title now, or none read at those sends: taken as the same chat (refused rather than sent twice).
    static func samePlace(_ places: Set<String>, _ title: String?) -> Bool {
        guard let title, !places.isEmpty else { return true }
        return places.contains { WatchReport.sameChatTitle($0, title) }
    }

    /// A "done" of a goal in numbered parts that answers it all: numbered as far as the goal's last part or the one
    /// before it (the last is often "整理成一段话告诉我"), or "全部" with at least half of them numbered.
    static func answersWholeGoal(_ answer: String, task: String) -> Bool {
        let want = goalParts(task)
        guard want >= 2 else { return false }
        let text = AppNames.hans(answer)
        let got = goalParts(text)
        return got >= want - 1 || (text.contains("全部") && got * 2 >= want)
    }

    /// How many numbered parts a goal written on one line has ("1. …；2. …；3. …"), counted 1, 2, 3… in order (a price
    /// "13.5" or a time is not a part). 123 over the cloud 11-12: a goal of nine parts started on its remembered way, a
    /// plan with no numbered lines, and had the base 55 steps instead of 180.
    static func goalParts(_ goal: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: #"(?:^|[：:；;，,。\n])\s*(\d{1,2})\s*[.)、．]"#) else { return 0 }
        let ns = goal as NSString
        let numbers = re.matches(in: goal, range: NSRange(location: 0, length: ns.length))
            .compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        var n = 0
        for k in numbers where k == n + 1 { n = k }
        return n
    }

    /// B4 (122 over the cloud 11-11): the clipboard cannot be read from the background, and the approval showed only
    /// "（粘贴的内容）". What the paste put in is read off the screen: the words after it that were nowhere before it
    /// (the input box grows and the chat moves up, but its words stay the same), keys and short marks left out.
    static func newWords(before: [[CandidatePicker.Piece]], after: [[CandidatePicker.Piece]]) -> String {
        let key = { (s: String) in AppPlaces.normalized(s) }
        let old = Set(before.joined().map { key($0.text) })
        let fresh = after.joined().filter { piece in
            let k = key(piece.text)
            return piece.box.midY > 0.12 && k.count >= 2 && !old.contains(k) && !CandidatePicker.keyLabels.contains(piece.text)
                && !["發送", "send", "return", "換行"].contains(k)
        }.sorted { abs($0.box.midY - $1.box.midY) > 0.01 ? $0.box.midY < $1.box.midY : $0.box.minX < $1.box.minX }
        return String(fresh.map(\.text).joined(separator: " ").prefix(300))
    }

    static func sends(_ act: JObject) -> Bool {
        switch act["action"]?.str {
        case "key": return ["enter", "return"].contains(act["combo"]?.str?.lowercased() ?? "")
        case "tap": return (act["x"]?.double ?? 0) >= 800 && (act["y"]?.double ?? 0) >= 400  // 发送 by the box: ~0.49
        default: return false
        }
    }

    static let noKeyboardReason = "Not typed: no keyboard is on screen, so the input box is not focused (the last tap "
        + "missed it). Tap the input box again (this tap is aimed) and type only once the keyboard shows."
    static let waitLimit = 3        // waits in a row that changed nothing
    static let blindLookLimit = 10  // looks of about 6 s each with sharing on before the user is asked
    static let blindLooksBeforeCancel = 2
    static let refusalsInARow = 3
    static let offlineWaitLimit = 24  // waits of 5 s for the network before the user is asked
    private var offlineWaits = 0
    private var sendBlocks = 0
    /// Looks at where a message would go before it is sent (the fast model; nil: no look).
    var sendChecker: ChatModel?
    /// Checks a finished run's answer (the fast model; nil: the planner). Over the proxy Codex took ~12 s to its first
    /// word for a one-line OK (11-10); Doubao 1.3 s.
    var doneChecker: ChatModel?
    /// Set for a task the cloud gave: asked before each message is sent; false stops the run with nothing sent.
    var approveSend: ((String) async -> Bool)?
    /// The chat title read at the top when approval was asked (shown with it: 121 r05's message was approved for 测试群
    /// while it sat in 验证群).
    private(set) var approvalPlace: String?
    private var approvedTexts: Set<String> = []
    static let notApprovedAnswer = "没有发送：这条消息未获批准。"

    static let wrongPlaceReason = "Not sent: this is not where the goal says to send. Go to the conversation the goal names "
        + "(back to the list, or search for it), then type and send there. Seen: "

    static let sendCheck = """
    An agent on an iPhone is about to send a message. You get the goal and the screen now.
    Reply with exactly one line: OK, or NO: where it is instead, in a few words.
    Say NO only when the conversation open on the screen (its name is at the top) is clearly not the one the goal says to send to.
    Never judge the message itself.
    """

    /// The goal sends a message somewhere: a check before each send is worth its seconds.
    static func asksToSend(_ task: String) -> Bool {
        let t = task.lowercased()
        let verbs = ["發", "发", "傳給", "传给", "回覆", "回复", "send", "reply"]
        let places = ["群", "給", "给", "聊天", "訊息", "消息", "message", "chat"]
        return verbs.contains { t.contains($0) } && places.contains { t.contains($0) }
    }

    static let untypedSearchReason = "Not searched: nothing was typed in this app yet. Words already in a search box (often grey) "
        + "are the app's own suggestion, not your search. Tap the box, type the words the goal asks for, then search."

    /// A search started (Return, or a tap the model says is the search button) in a goal that searches, with nothing
    /// typed or pressed since the app was opened (by open, or by its icon).
    static func searchesUntyped(_ act: JObject, after steps: [JObject], task: String) -> Bool {
        let goal = task.lowercased()
        guard ["搜尋", "搜索", "搜寻", "search"].contains(where: { goal.contains($0) }) else { return false }
        let submits: Bool
        switch act["action"]?.str {
        case "key": submits = sends(act)
        case "tap":
            let t = (act["thought"]?.str ?? "").lowercased()
            submits = ["搜尋", "搜索", "搜寻", "search"].contains { t.contains($0) }
                && ["按鈕", "按钮", "button", "執行", "执行"].contains { t.contains($0) }
        default: submits = false
        }
        guard submits else { return false }
        for step in steps.reversed() {
            switch step["action"]?.str {
            case "type", "press", "compose": return false
            case "open": return true
            default: if opensByIcon(step) { return true }
            }
        }
        return true
    }

    /// The goal posts something others see (a message, a reply, a comment, a post). What it says not to do is not counted:
    /// "不要留言" asks for no comment.
    static func publishes(_ task: String) -> Bool {
        let t = task.lowercased().replacingOccurrences(
            of: #"(不要|不用|不必|別|别|勿|禁止|don't|do not|never)[^，,。.；;！!？?\n]*"#, with: " ", options: .regularExpression)
        // Build 120 on the phone, 11-11: "影片是誰發的", "評論、收藏、轉發各是多少" were read as sending, and a news
        // site typed in Safari and a search on 小紅書 were held for approval (one task cancelled). But "在测试群发你好"
        // sends: a 发 still counts, except inside words that only read or name something.
        let said = ["發一", "发一", "發個", "发个", "發條", "发条", "發訊息", "发讯息", "發消息", "发消息", "發信息", "发信息",
                    "發到", "发到", "發給", "发给", "發送", "发送", "傳給", "传给", "轉發給", "转发给", "轉發到", "转发到",
                    "回覆", "回复", "留言", "發評論", "发评论", "寫評論", "写评论", "評論一", "评论一", "發表評論", "发表评论",
                    "發帖", "发帖", "發文", "发文", "發布到", "发布到", "發朋友圈", "发朋友圈", "說一聲", "说一声",
                    "說一句", "说一句", "傳送", "传送",
                    "send ", "reply ", "post a", "comment on", "leave a comment"]
        if said.contains(where: { t.contains($0) }) { return true }
        // "跟我說一下天氣" and "告訴我" ask this phone, they send nothing; "跟他說", "告訴大家", "評論：好看" send.
        if t.range(of: #"(跟|对|對|和|向)(?!我)[^，,。.；;！!？?\n]{1,12}[说說]|告[訴诉](?!我)|(評論|评论|(?<!我)[說说])[：:「“"]"#,
                   options: .regularExpression) != nil { return true }
        var rest = t
        for word in [#"[誰谁]?[發发]的"#,  // who posted it, what they posted
                     #"[轉转][發发](?![給给到這这一那該该])"#,  // the share count, not "转发给/转发这条"
                     #"[發发][布佈表](?![到一這这])"#,  // 发布时间, 发表于
                     #"(開|开|出|批|沙|爆|自|激|研|散|揮|挥|蒸|奮|奋|頒|颁|引|啟|启|收|头)[發发]"#,
                     #"[發发](現|现|生|票|貨|货|展|音|燒|烧|型|揮|挥|明|光|行|起|射|電|电|財|财|胖|呆|愁|抖|麻|熱|热|炎|病|作|育|芽|酵|達|达|覺|觉|放|售|件)"#] {
            rest = rest.replacingOccurrences(of: word, with: " ", options: .regularExpression)
        }
        return rest.contains("發") || rest.contains("发")
    }

    /// Every message a goal gives: each part in quotes, or else the words after a colon. 121 over the cloud 11-11:
    /// "先發「k02第一句」，再發「k02第二句」" asked approval for the first only; the second, read as words the goal names
    /// that are not its message (like a chat's name), went out unasked.
    static func messageParts(_ task: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"[「“"]([^」”"]+)[」”"]"#) else { return [] }
        let ns = task as NSString
        let matches = re.matches(in: task, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return messagePart(task).map { [$0] } ?? [] }
        // 125 stress test 11-12 (t06): every quoted part was a message, so “蓝牙耳机” searched in 淘宝 asked for approval
        // as one, and then could not be typed into 拼多多's search, 110 times. A quoted part is a message only when a way
        // of saying "send" comes right before it (发“…”, 内容是“…”, 回复“…”), not 搜索“…”.
        return matches.filter { m in
            let start = max(0, m.range.location - 6)
            let before = ns.substring(with: NSRange(location: start, length: m.range.location - start))
            return sayWords.contains { before.contains($0) }
        }.map { ns.substring(with: $0.range(at: 1)) }
    }

    static let sayWords = ["发", "發", "说", "說", "回复", "回覆", "留言", "评论", "評論", "写", "寫", "讯息", "訊息", "消息",
                           "内容", "內容", "话", "話"]

    /// The words a goal gives as the message: after a colon, or in quotes (nil: none given).
    static func messagePart(_ task: String) -> String? {
        if let r = task.range(of: #"[「“"]([^」”"]+)[」”"]"#, options: .regularExpression) {
            return String(task[r].dropFirst().dropLast())
        }
        // Only a colon after a way of saying "send" gives the message (發一則訊息：…, 留言：…): 121 over the cloud 11-11,
        // "幫我做這六件事：1. 查深圳明天的最高溫；…" made the list's first item the message, and 深圳 typed in Weather's search
        // was held for approval.
        let said = ["发", "發", "说", "說", "回复", "回覆", "留言", "评论", "評論", "写", "寫", "讯息", "訊息", "消息", "内容", "內容", "话", "話"]
        for colon in task.indices where task[colon] == "：" || task[colon] == ":" {
            let before = String(task[..<colon].suffix(8))
            guard said.contains(where: { before.contains($0) }) else { continue }
            let rest = task[task.index(after: colon)...].prefix { !"。；;\n".contains($0) }
            let message = rest.trimmingCharacters(in: .whitespaces)
            return message.isEmpty ? nil : message
        }
        return nil
    }

    /// Whether text about to go out with Return waits for the cloud's approval: a message, a reply, a post. Words the
    /// goal itself names, searched or opened in a goal that posts nothing, are not one; nor, in a goal that gives its
    /// message, words it names that are not that message (the chat's name searched for).
    /// chatApp: the app in front is one that sends messages (see inChatApp). Build 118, 11-10: 高德 searched 下水徑地鐵站, a
    /// station it knew from before, in a goal that posts nothing; it was held as a message and the task was cancelled.
    static func needsApproval(_ text: String, task: String, chatApp: Bool = true) -> Bool {
        func key(_ s: String) -> String { AppNames.hans(typedKey(s)).lowercased() }
        // Build 121 over the cloud 11-11: the goal said www.sina.com.cn, Codex typed https://www.sina.com.cn in Safari
        // (opened by its icon, so the app was unknown), and the address was held as a message. An address is compared
        // without its scheme, www. and closing slash.
        let typed = key(text).replacingOccurrences(of: #"^(https?://)?(www\.)?|/$"#, with: "", options: .regularExpression)
        let goal = key(task)
        // The same day: "進新浪網" without an address; a learned route opened Safari by its icon again. A web address
        // typed for a goal that names a browser and posts nothing goes to the address bar, not to a chat.
        if key(text).range(of: #"^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}(/\S*)?$"#, options: .regularExpression) != nil,
           goal.range(of: #"safari|chrome|浏览器|瀏覽器|网址|網址|网站|網站|网页|網頁"#, options: .regularExpression) != nil,
           !publishes(task) { return false }
        guard !typed.isEmpty, goal.contains(typed) || takenFrom(typed, goal) else { return chatApp || publishes(task) }
        guard publishes(task) else { return false }
        let messages = messageParts(task).map(key).filter { !$0.isEmpty }
        // A goal that posts but gives no message ("整理成一段話發到测试群"): its own words typed in a chat app may be the
        // message; typed in 天气 or 淘宝 they are searches.
        guard !messages.isEmpty else { return chatApp }
        return messages.contains { $0.contains(typed) || typed.contains($0) }
    }

    static let chatApps = ["微信", "wechat", "qq", "企业微信", "钉钉", "飞书", "信息", "messages", "短信", "telegram", "whatsapp", "line"]

    /// Apps a goal names that send no messages (Simplified, as AppNames.hans writes them).
    static let namedApps = ["高德", "地图", "天气", "计算器", "计算机", "股市", "safari", "浏览器", "淘宝", "拼多多", "美团",
                            "抖音", "小红书", "快手", "备忘录", "日历", "行事历", "时钟", "设置", "设定", "京东", "百度"]

    /// Whether the app opened last in this run sends messages. No app opened by name: the goal's own apps decide (build
    /// 121 over the cloud 11-11: a learned route opens its app by the icon, and 下水径 typed in 高德 and an address
    /// typed in Safari were held as messages); a goal that names none, or names a chat app, may be in one.
    static func inChatApp(_ steps: [JObject], task: String = "") -> Bool {
        guard let app = steps.last(where: { $0["action"]?.str == "open" })?["app"]?.str else {
            let goal = AppNames.hans(task).lowercased()
            if ["微信", "wechat", "企业微信", "钉钉", "飞书", "短信", "imessage", "telegram", "whatsapp"].contains(where: { goal.contains($0) }) {
                return true
            }
            return !namedApps.contains { goal.contains($0) }
        }
        let name = AppNames.hans(app).lowercased().filter { !$0.isWhitespace }
        return chatApps.contains { name == $0 || name.contains($0) && $0.count >= 2 }
    }

    /// The goal's own words, a little shortened or reworded: its characters in the goal's order, with one in ten (at least
    /// one, none in a word under four) left out or added. Build 116 over the cloud 11-10: 深圳灣公園附近停車場, the goal's 深圳灣公園附近的停車場 without
    /// its 的, was held as a message, refused, and the search task ended "not approved".
    static func takenFrom(_ typed: String, _ goal: String) -> Bool {
        let t = Array(typed), g = Array(goal)
        guard t.count >= 2 else { return false }
        var at = 0, strays = 0
        for c in t {
            if let i = g[at...].firstIndex(of: c) { at = i + 1 } else { strays += 1 }
        }
        return strays <= (t.count >= 4 ? max(1, t.count / 10) : 0)
    }

    /// Where a message would go now, if that is not where the goal says (nil: fine, or the check could not be made).
    /// Where a message would go, as far as the screen says it without a model.
    enum ChatCheck: Equatable { case right, wrong(String), unknown }

    /// The groups a goal names, each with the words before it (测试群 in "在微信打開测试群", "發到测试群"): the title at
    /// the top must end one of them.
    static func namedGroups(_ task: String) -> [String] {
        let pattern = #"[\p{Han}A-Za-z0-9]{1,10}群"#
        let all = (try? NSRegularExpression(pattern: pattern))?
            .matches(in: task, range: NSRange(task.startIndex..., in: task))
            .compactMap { Range($0.range, in: task).map { String(task[$0]) } } ?? []
        let generic = ["微信群", "这个群", "這個群", "那个群", "那個群", "一个群", "一個群", "两个群", "兩個群", "各个群", "各個群"]
        return all.filter { name in !generic.contains { name.hasSuffix($0) } }
    }

    static func chatCheck(seen: String?, task: String, steps: [JObject]) -> ChatCheck {
        let groups = namedGroups(task)
        guard !groups.isEmpty else { return .unknown }
        func key(_ s: String) -> String {
            AppNames.hans(s.replacingOccurrences(of: #"[（(][^)）]*[)）]"#, with: "", options: .regularExpression))
                .lowercased().filter { $0.isLetter || $0.isNumber }
        }
        if let seen {
            let t = key(seen)
            if t.count >= 2, groups.contains(where: { key($0).hasSuffix(t) }) { return .right }
            return .wrong("the chat at the top is “\(seen)”, not the group the goal names")
        }
        if let app = steps.last(where: { $0["action"]?.str == "open" })?["app"]?.str,
           !inChatApp([["action": .str("open"), "app": .str(app)]]) {
            return .wrong("this is \(app), not a chat: no chat title at the top")
        }
        return .unknown
    }

    private func wrongPlace(frame: Data?) async -> String? {
        guard let model = sendChecker else { return nil }
        do {
            let reply = try await model.chat(system: Self.sendCheck, text: "Goal: \(task)\n\nThe image is the screen now.",
                                             image: frame, maxTokens: 80, temperature: 0).text
            trace?.write(kind: "send check", ["reply": .str(String(reply.prefix(300)))])
            DebugLog.write("send check: \(reply.prefix(160))")
            return Self.wrongness(reply)
        } catch {
            DebugLog.write("send check failed: \(error.localizedDescription)")
            return nil
        }
    }
    static let leaveLimit = 2       // times the same way off the same screen is taken; the next is refused

    static let waitReason = "Refused: you waited several times and nothing changed, so more waiting will not help. Change "
        + "the method now: reload, go back, or another way to the same result. A website that stays blank is not reachable "
        + "from here: type another search site in the address bar (www.baidu.com, cn.bing.com)."
    static let circleReason = "Refused: you already left this same screen this way twice and came back to it. Leaving does "
        + "not make it go away. Deal with what is on it: a sheet or permission prompt belongs to the app, answer it with the "
        + "smallest choice (不允許, 不分享, 稍後, 關閉, Not Now), then go on. If what the goal asks for is already done or on "
        + "this screen, finish: answer done."
    static let openFailedReason = " is not on this phone: it is not on the Home Screen and Search does not list it as an app. "
        + "Do not search the web for it and do not try again; if the goal needs it, stop with fail and say so."

    /// True when this is the third time the same way off this screen is taken: it comes back each time (a contacts sheet
    /// left and reopened for 300 s, over USB 11-09). Counts this one. Another way off, or another app, is another move.
    func circling(_ act: JObject, on look: [UInt8]) -> Bool {
        guard ["home", "back", "open"].contains(act["action"]?.str ?? "") || Self.leaves(act) else { return false }
        let move = Actions.key(act)
        if let i = departures.firstIndex(where: { Actions.key($0.move) == move && Vision.sameScreen($0.look, look) }) {
            departures[i].times += 1
            return departures[i].times > Self.leaveLimit
        }
        departures.append((look, act, 1))
        return false
    }

    /// True when this many waits in a row changed nothing.
    static func waitedEnough(_ steps: [JObject]) -> Bool {
        let recent = steps.filter { !["refused", "stale plan"].contains($0["action"]?.str ?? "") }.suffix(waitLimit)
        return recent.count == waitLimit && recent.allSatisfy { $0["action"]?.str == "wait" && $0["changed"] == .bool(false) }
    }

    /// Build 118 without Codex, 11-10: Weather opened at the bottom of the page, the forecast was above, and the models
    /// swiped "up to bring the forecast in" 25 times: at the end of a page that way nothing moves.
    static let endReachedReason = "Refused: the last two swipes this way moved nothing: the page is at its end that way. "
        + "What you look for is the other way. To see what is above (the top of the page, earlier rows) move the finger down: "
        + "swipe 500 300 500 750. To see what is below, move it up: swipe 500 750 500 300. Or it is on another tab or page."

    static func swipedToTheEnd(_ act: JObject, after steps: [JObject]) -> Bool {
        guard let y1 = act["y1"]?.double, let y2 = act["y2"]?.double, abs(y2 - y1) > 100 else { return false }
        let last = steps.filter { !["refused", "stale plan", "loop"].contains($0["action"]?.str ?? "") }.suffix(2)
        return last.count == 2 && last.allSatisfy { s in
            guard s["action"]?.str == "swipe", let a = s["y1"]?.double, let b = s["y2"]?.double else { return false }
            return (b - a) * (y2 - y1) > 0 && (s["changed"] == .bool(false) || s["scrolled"] == .bool(false))
        }
    }

    static let deadTapReason = "Refused: tapping this spot already did nothing twice (the screen did not change, or the next "
        + "stroke still left no line). It is not the control you want: look at what else is on screen and try a different one. "
        + "Text you just typed is submitted with: key enter."

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
        + "left was the mistake. Stay on this screen and do the task here. If what the goal asks for is already done, answer done."

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
        pendingRefused = 0
        untypedSearches = 0
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
        (parts, partIndex, doneParts, takeover, stepsInPart, rescued, troubles) = ([], 0, [], 0, 0, false, 0)
        (stallsNoProgress, messageSent, sendIsMessage, itemFailsLeft, refusalsNoProgress) = (0, [], false, 2, 0)
        (cartAdds, cartToastShown) = (0, false)
        (notes, departures, circleRefused, blindLooks, deadRefused, offlineWaits, sendBlocks) = ([], [], 0, 0, 0, 0, 0)
        (notesAtPart, emptyPartRefused, pasteFrame, sameAppRefused, pictureIn, listenedAll) = (0, -1, nil, 0, nil, false)
        sentPlaces = [:]
        approvedTexts = []
        checksLeft = 2
        rejectedAnswer = nil
        recipe = presetPlan.isEmpty && learnedRoutes ? routes?.recipe(for: task) : nil
        plannerLeads = plannerLeadsUnknown && presetPlan.isEmpty && learnedRoutes && recipe == nil && planner != nil
        if plannerLeads { DebugLog.write("run: not done before; the planner does it and it is remembered") }
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
            let budget = Self.stepBudget(plan: plan, base: stepLimit ?? maxSteps, goal: presetPlan.isEmpty ? task : "")
            if budget > (stepLimit ?? maxSteps) { DebugLog.write("run: \(budget) steps for a plan of several parts") }
            for _ in 0..<budget {
                do {
                    let recordsBefore = steps.count
                    if try await step() {
                        if try await rescue() { continue }
                        guard steps.last?["action"]?.str == "fail", try await askForHelp() else { return finish() }
                        continue
                    }
                    failures = 0
                    blindLooks = 0
                    offlineWaits = 0
                    if refusalsNoProgress >= Self.refusalLimit {
                        record(nil, ["action": .str("fail"),
                                     "reason": .str("stuck: refused \(refusalsNoProgress) times and nothing got on")])
                        return finish()
                    }
                    // build104 live 11-08: a one-part task (a smiley) spent all 50 steps with 9 strokes that left no ink and
                    // Codex never came, because only plans of several parts had this budget. Every task the planner or the
                    // user gave gets it (fixed flows such as watching WeChat keep their own); steps Codex drives don't count.
                    if presetPlan.isEmpty, planner != nil, takeover == 0, !plannerLeads {
                        stepsInPart += 1
                        troubles += steps.dropFirst(recordsBefore).filter(Self.isTrouble).count
                        let gestures = steps.suffix(Self.swipesInARow + 2).filter { $0["action"]?.str != "stale plan" }
                        let swiping = gestures.count >= Self.swipesInARow
                            && gestures.suffix(Self.swipesInARow).allSatisfy { $0["action"]?.str == "swipe" }
                        if stepsInPart >= Self.partSteps || troubles >= Self.troubleLimit || swiping {
                            record(nil, ["action": .str("part stalled"),
                                         "reason": .str((parts.count >= 2 ? "part \(partIndex + 1)" : "the task")
                                                        + " not getting on: \(stepsInPart) steps, \(troubles) failed, swiping \(swiping)")])
                            troubles = 0
                            stallsNoProgress += 1
                            if stallsNoProgress >= Self.stallLimit {
                                record(nil, ["action": .str("fail"),
                                             "reason": .str("stuck: \(stallsNoProgress) new plans in a row and nothing got on")])
                                return finish()
                            }
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
                    // Over USB 11-09: a run stopped to ask the user to share the screen, while it was being shared.
                    if e.sharingOn, blindLooks < Self.blindLookLimit {
                        blindLooks += 1
                        DebugLog.write("run: no new frame yet with sharing on (\(blindLooks)); looking again")
                        // The pointer answers this right after a click near the clock. Whatever else brought the question
                        // up (Pointer.cancelSharing), it stays until answered, and frames also stop by themselves for up to 10 s.
                        if blindLooks == Self.blindLooksBeforeCancel, (try? await phone?.answerSharingQuestion()) == true {
                            record(nil, ["action": .str("sharing question"),
                                         "reason": .str("frames came back after tapping Cancel on whether to stop sharing the screen")])
                        }
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    record(nil, ["action": .str("paused"), "reason": .str(e.reason)])
                    guard try await askForHelp() else { return finish() }
                    continue
                } catch let e where e is CancellationError || Task.isCancelled {
                    throw e
                } catch {  // a bad reply or a dropped link: recover, don't crash
                    record(nil, ["action": .str("hiccup"), "reason": .str(String(error.localizedDescription.prefix(300)))])
                    let linkLost = Self.isLinkLoss(error, screenLive: screen?.live)  // the next look waits for it (waitForScreen)
                    let offline = ModelRequestFailure.isNetworkDown(error)
                    failures += linkLost || offline ? 0 : 1  // a lost link is not the agent's fault
                    if offline {
                        offlineWaits += 1
                        if offlineWaits > Self.offlineWaitLimit {
                            record(nil, ["action": .str("fail"), "reason": .str("the phone has had no network for \(Self.offlineWaitLimit * 5) s")])
                            guard try await askForHelp() else { return finish() }
                            offlineWaits = 0
                            continue
                        }
                        DebugLog.write("run: no network (\(error.localizedDescription)); waiting 5 s, then the same step again (\(offlineWaits))")
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                        continue
                    }
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
                    do { try await replan(stuck: true) }
                    catch let e where ModelRequestFailure.isNetworkDown(e) {
                        DebugLog.write("run: no network for the new plan (\(e.localizedDescription)); the next step tries again")
                    }
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
        guard let onHelp, helpAsked < 2, stepLimit == nil, !noHelp else { return false }
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
        // build104 live 11-08: after the user's answer the next refused done stopped the run again at once (the count
        // of refusals went on from 3). The user's answer starts the count again.
        doneRejected = 0
        await screen?.settled()
        try await replan(stuck: true)
        return true
    }

    /// The actor's system prompt: the original, plus this task's hints, the user's lessons and rules.md.
    var actorPrompt: String { Prompts.actor + "\n" + AssistiveTouchSpots.rule + AppNames.languageNote + taught }

    /// The planner gets the same: a plan that ignores them makes the actor ignore them too.
    var plannerPrompt: String { Prompts.plannerApp + "\n" + AssistiveTouchSpots.rule + AppNames.languageNote + taught }

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
        let replied = try await nextActions()
        timing.llmMs = (replied[0].act["think_s"]?.double ?? 0) * 1000
        for planned in replied where planned.act["action"]?.str == "note" {  // nothing on the phone moves: kept, and shown from here on
            if let text = planned.act["text"]?.str, !text.isEmpty, !notes.contains(text) {
                notes.append(text)
                (stallsNoProgress, refusalsNoProgress) = (0, 0)
                gotOn()
            }
            record(planned.shot, planned.act)
        }
        let acts = replied.filter { $0.act["action"]?.str != "note" }
        guard !acts.isEmpty else { return false }
        let seen = acts[0].shot
        var spots = [pointerAt]  // where the pointer was and goes: pointer moves are not screen changes
        let stuck = repeating(acts[0].act)
        let drawing = Set(["circle", "path"])
        let startsDrawing = drawing.contains(acts[0].act["action"]?.str ?? "")
            && !drawing.contains(steps.last?["action"]?.str ?? "")
        defer { metrics?.step(timing) }
        for (i, planned) in acts.enumerated() {
            var act = planned.act
            if act["action"]?.str == "swipe" { act = Self.safeSwipe(act, after: steps) }
            // Over USB 11-10 one reply opened WeChat twice, 18 s each.
            if i > 0, act["action"]?.str == "open", acts[i - 1].act["action"]?.str == "open", acts[i - 1].act["app"] == act["app"] { continue }
            // 123 on the phone 11-12 (W2 again): a Weather screenshot opened full screen from 测试群 was taken for the
            // Weather app, and WeChat was "opened" twice through Search (13 s, 19 s), then the run went round in circles.
            // A run that has not left the app it is in has nothing to open: refused once, saying what it looks at.
            if act["action"]?.str == "listen", listenedAll {
                record(planned.shot, ["action": .str("refused"), "reason": .str("Refused: the video has started over and "
                    + "all it says is in the notes. Answer now with done.")])
                return false
            }
            if let pic = pictureIn {
                pictureIn = nil
                let what = act["action"]?.str ?? ""
                let reopens = what == "open"
                    && AppNames.variants(pic).map(AppNames.hans).contains(AppNames.hans(act["app"]?.str ?? ""))
                if what == "home" || reopens {
                    // 125 in 测试群 11-12: a tap in the middle came after the model had closed the picture itself, landed
                    // on another screenshot in the chat and opened it. A drag down closes a picture and only scrolls a chat.
                    DebugLog.write("picture: \(what) right after the still-in-\(pic) refusal; dragging the picture down instead")
                    act = ["action": .str("swipe"), "x1": .num(500), "y1": .num(350), "x2": .num(500), "y2": .num(800),
                           "picture_close": .bool(true),
                           "thought": .str("A picture shown full screen in \(pic): dragging it down closes it.")]
                }
            }
            if act["action"]?.str == "open", sameAppRefused == 0, let inApp = Self.appInFront(steps, startedIn: startApp),
               AppNames.variants(inApp).map(AppNames.hans).contains(AppNames.hans(act["app"]?.str ?? "")) {
                sameAppRefused += 1
                pictureIn = inApp
                record(planned.shot, ["action": .str("refused"), "reason": .str(Self.stillInAppReason(inApp))])
                return false
            }
            let ourKeyboard = ourKeyboardOnScreen?() == true
            if ourKeyboard ? Self.onOurReturnKey(act) : (Self.onReturnKey(act) && screen?.frame.map({ CandidatePicker.keyboardUp(in: $0) }) == true) {
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
            // Out of checks, it gave up instead of answering again: over the cloud 11-10 the check twice took a note's first
            // line, its title in Notes, for "only its body", and the run waited for help until it timed out. What it read
            // goes out marked as not checked, as a third done would.
            if act["action"]?.str == "fail", checksLeft == 0, let answer = rejectedAnswer, endAfterSend == nil, presetPlan.isEmpty,
               parts.count < 2 || partIndex >= parts.count - 1 {
                DebugLog.write("done check: it gave up after two refusals; its answer goes out as not checked")
                act["action"] = .str("done")
                act["answer"] = .str(answer)
                act["reason"] = nil
            }
            let name = act["action"]?.str ?? ""
            var justSent: String?
            if endAfterSend != nil, !sentTexts.isEmpty, unsent == nil, !["wait", "done", "fail"].contains(name) {
                record(planned.shot, ["action": .str("send verification"), "reason": .str(Self.sendVerificationReason)])
                return false
            }
            if i > 0, ["done", "fail"].contains(name) || (name == "tap" && acts[i - 1].act["action"]?.str != "tap") {
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
                if name == "wait", endAfterSend == nil, Self.waitedEnough(steps) {
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.waitReason)])
                    return false
                }
                if endAfterSend == nil, let shot = planned.shot, let look = Vision.look(shot), circling(act, on: look) {
                    circleRefused += 1
                    if circleRefused >= 3 { return try await changeOfPlan(planned.shot, "kept leaving the same screen and coming back to it") }
                    record(planned.shot, ["action": .str("loop"), "reason": .str(Self.circleReason)])
                    return false
                }
                // traces(33): enter the chat, decide the avatar is wrong, go back, enter, go back... twice is enough.
                // The leaving move (back) is the one refused, so the run stays where it can do the task.
                if let guarded = bounceGuard, Self.sameSpot(guarded.stop, act) {
                    bounceRefused += 1
                    if bounceRefused >= 3 {
                        (bounceGuard, bounceRefused) = (nil, 0)
                        return try await changeOfPlan(planned.shot, "kept going back and forth between two screens")
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
            // The task's own checks (drawn, sent) are for the done that ends it: build104 live 11-08, part 1 (the alarm)
            // was done three times and refused each time as "nothing has been drawn" (that was part 2), and the run stopped.
            // 124 over the cloud 11-12 (e03): Codex drove through parts 2-4 and answered all nine things in its "done";
            // it was taken as part 2 only, part 3 (send to 验证群, already sent) began, and the run went round in circles
            // and failed with the answer lost. A done that answers the whole goal is checked as the end of the task.
            let coversGoal = name == "done" && parts.count >= 2 && partIndex < parts.count - 1
                && Self.answersWholeGoal(act["answer"]?.str ?? "", task: task)
            let endsTask = parts.count < 2 || partIndex >= parts.count - 1 || coversGoal
            var unvisited: String?  // only for a task given in words (not the watch's fixed ways)
            if name == "done", endsTask, presetPlan.isEmpty, !keyboardGuard { unvisited = Self.unvisitedReason(task: task, steps: steps) }
            if name == "done", endsTask, let missing = unsentReason ?? (inkSeen == false ? Self.noInkReason : Self.unmadeResult(task: task, steps: steps)) ?? unvisited {
                doneRejected += 1
                if doneRejected >= 3 {  // it keeps claiming a result it did not make: stop and ask the user
                    record(planned.shot, ["action": .str("fail"), "reason": .str("claimed done 3 times without doing it: " + missing)])
                    return true
                }
                record(planned.shot, ["action": .str("done rejected"), "reason": .str(missing)])
                return false
            }
            if name == "done", endsTask, verifiesDone, presetPlan.isEmpty, endAfterSend == nil {
                if checksLeft > 0 {
                    let answer = act["answer"]?.str ?? "", frame = screen?.frame ?? planned.shot
                    let wrong = await wrongClaim(answer, frame: frame)
                    var stands = false  // no await inside && (the build 116 CI error was one inside ??)
                    if wrong != nil, answer == rejectedAnswer { stands = await confirmedBySecondModel(answer, frame: frame) }
                    if let wrong, !stands {
                        checksLeft -= 1
                        rejectedAnswer = act["answer"]?.str
                        record(planned.shot, ["action": .str("done rejected"), "reason": .str(wrong)])
                        return false
                    }
                } else if let answer = act["answer"]?.str {  // told twice and it stands by it: reported, but not as checked
                    act["answer"] = .str("（未能核實）" + answer)
                }
            }
            if name == "done", !coversGoal, partFinished(act, shot: planned.shot) { return false }
            if name == "fail", itemFailsLeft > 0, presetPlan.isEmpty, Self.goalParts(task) >= 3 {
                itemFailsLeft -= 1
                let line = "未能完成：" + String((act["reason"]?.str ?? "").prefix(120))
                if !notes.contains(line) { notes.append(line) }
                record(planned.shot, ["action": .str("fail refused"), "reason": .str(Self.oneThingFailedReason)])
                return false
            }
            if name != "done" && name != "fail" {
                try await gate?()
                try await screen?.requireFrame(after: nil)
                // Home and wait do not use coordinates or the current focus. Animation cannot make their target stale.
                if i == 0, !["home", "wait", "listen"].contains(name), act["home_recovery"] != .bool(true), seen != screen?.frame,
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
                    // A video behind the controls changes everything and every word stays: ~29 s a step (over USB 11-09).
                    var safe = again || ((staleRun > 2 || !target.isEmpty)
                        && !Vision.changedNear(seen, screen?.frame, around: target))
                    if !safe {
                        let (was, now) = (seen ?? Data(), screen?.frame ?? Data())
                        safe = Self.sameWords(await CandidatePicker.rowsOffMain(in: was, top: 0.055, bottom: 1),
                                              await CandidatePicker.rowsOffMain(in: now, top: 0.055, bottom: 1))
                    }
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
                    // build105 live 11-08: a search for 无边记 (the phone says 無邊記) found nothing, and every new word
                    // was refused as "already entered", 30 times, until the steps ran out. Only the same words are
                    // refused, twice; other words replace what is in the field.
                    if Self.typedKey(act["text"]?.str ?? "") == Self.typedKey(pendingInput), pendingRefused < 2 {
                        pendingRefused += 1
                        record(planned.shot, ["action": .str("blocked"),
                            "reason": .str("Text was already entered: \(pendingInput). Inspect the current field. "
                                + "Do not clear, retype, or paste over correct text; send it once if correct. "
                                + "Only use explicit correction keys if a visible mistake needs fixing.")])
                        return false
                    }
                    try await phone?.key("cmd+a")
                    try await phone?.key("backspace")
                    self.pendingInput = nil
                    pendingRefused = 0
                }
                // Lan Agent's keyboard has no letter keys to see, but it reports itself: a field it is up for is focused.
                if name == "type", keyboardGuard, noKeyboard < 2, let shown = screen?.frame, Vision.image(shown) != nil,
                   !CandidatePicker.keyboardUp(in: shown), ourKeyboardOnScreen?() != true {
                    noKeyboard += 1
                    aimNext = true
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.noKeyboardReason)])  // never typed
                    return false
                }
                // 123 over the cloud 11-12: the sorted temperatures went into 验证群 twice; this check was the watch's
                // only, and the text, approved once, was not asked about again. Every run: the same text again only into
                // another chat, read off the title (not read: refused).
                // 124 over the cloud 11-12 (g05): 雨伞 searched in 淘宝 was "sent" by its Return, and typing it into 拼多多's
                // search box was refused ~290 times. Only a message sent into a chat is never typed again.
                // 125 stress test 11-12 (u05): "125压力测试艾特" went out, then "@蓝海乐 125压力测试艾特" was typed and went
                // out too: the same message with more around it is the same message.
                let typedNow = Self.typedKey(act["text"]?.str ?? "")
                let sentMatch = Self.sameMessage(typedNow, in: messageSent)
                    ?? (Self.inChatApp(steps, task: task) ? Self.sameMessage(typedNow, in: sentTexts) : nil)
                if name == "type", let sent = sentMatch,
                   keyboardGuard || Self.samePlace(sentPlaces[sent] ?? [], screen?.frame.flatMap { WatchReport.navigationTitle(in: $0) }) {
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
                // What a button does can change with what was typed: a search button that did nothing may be the right one now
                // (over USB 11-09 it missed twice, the word was typed again, and it stayed refused).
                if name == "type" { noKeyboard = 0; unsent = act["text"]?.str ?? ""; quietSinceSend = 0; deadTaps = []; deadRefused = 0 }
                // Build 121 over the cloud 11-11: a 抖音 share link was pasted into 测试群 (cmd+v) and sent with Return with
                // no approval asked: only typed text was held. What is pasted counts as typed.
                if Self.pastes(act) { unsent = Self.pastedText(pasteboard()); quietSinceSend = 0; pasteFrame = screen?.frame ?? planned.shot }
                // The tap after one that changed nothing goes through the eye (missed: aimed), so it lands on the spot.
                // Moving it around the spot moved it off the button (淘寶's 加入購物車, 10 clicks above it, over USB 11-09).
                if name == "swipe", Self.swipedToTheEnd(act, after: steps) {
                    deadRefused += 1
                    if deadRefused >= Self.refusalsInARow {
                        deadRefused = 0
                        return try await changeOfPlan(planned.shot, "kept swiping a way that moves nothing")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.endReachedReason)])
                    return false
                }
                if name == "tap", deadTaps.filter({ Self.sameSpot($0, act) }).count >= 2 {
                    // Over USB 11-09 a run was refused here 48 times in a row, one model call each, up to its step limit.
                    deadRefused += 1
                    if deadRefused >= Self.refusalsInARow {
                        deadRefused = 0
                        return try await changeOfPlan(planned.shot, "kept tapping a spot that does nothing")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.deadTapReason)])
                    return false
                }
                if name == "tap", Self.tapsInARow(steps, like: act) >= Self.sameTapLimit {
                    deadRefused += 1
                    if deadRefused >= Self.refusalsInARow {
                        deadRefused = 0
                        return try await changeOfPlan(planned.shot, "kept tapping a spot that does nothing")
                    }
                    record(planned.shot, ["action": .str("refused"), "reason": .str(Self.sameTapReason)])
                    return false
                }
                // Over USB 11-10 淘寶's box showed a suggestion (保温水壶, grey) and the model searched it as if it had typed
                // 保溫杯: the price it found was for the wrong thing. A search in an app where nothing was typed is refused.
                if untypedSearches < 2, Self.searchesUntyped(act, after: steps, task: task) {
                    untypedSearches += 1
                    record(planned.shot, ["action": .str("blocked"), "reason": .str(Self.untypedSearchReason)])
                    return false
                }
                // Over USB 11-10 the way into 测试群 was followed for 验证群: WeChat opened on the last chat and the message went
                // there. Before a message goes, something looks at where it would go.
                // 121 over the cloud 11-11: the model's look said OK to 小红书's comment box and to 验证群 for a goal that named
                // 测试群, then NO, then OK again for the same screen; and it blocked a search's Return in 拼多多. Only a message
                // is checked, and when the goal names a group the title at the top decides, read off the screen.
                let sending = unsent != nil && (Self.sends(act) || act["learned"] == .str("send"))
                // 125 stress test 11-12 (s03): a new note's first line "压力测试比价" (part of the goal's message
                // "125压力测试比价完成") and then its body were each taken for that message by their Return in 備忘錄,
                // "about to send into the wrong place", and the run failed. In an app that sends nothing to anyone,
                // Return is a new line or a search.
                let isMessage = sending && !Self.inLocalApp(steps)
                    && Self.needsApproval(unsent ?? "", task: task, chatApp: Self.inChatApp(steps, task: task))
                let sendFrame = screen?.frame ?? planned.shot
                var seenTitle = isMessage ? sendFrame.flatMap { WatchReport.navigationTitle(in: $0) } : nil
                if isMessage, seenTitle == nil {
                    // B5, 122 over the cloud 11-11: the approval went out with no destination twice (q08, q11). A banner
                    // or a frame caught mid-change: one more look, a moment later.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    seenTitle = screen?.frame.flatMap { WatchReport.navigationTitle(in: $0) }
                }
                approvalPlace = seenTitle
                if sending { sendIsMessage = isMessage }
                var wrongSpot: String?
                if isMessage, endAfterSend == nil, Self.asksToSend(task) {
                    switch Self.chatCheck(seen: seenTitle, task: task, steps: steps) {
                    case .right: wrongSpot = nil
                    case .wrong(let why): wrongSpot = why
                    case .unknown: wrongSpot = await wrongPlace(frame: sendFrame)
                    }
                }
                if let wrong = wrongSpot {
                    sendBlocks += 1
                    if sendBlocks >= 2 {
                        sendBlocks = 0
                        return try await changeOfPlan(planned.shot, "about to send into the wrong place: \(wrong)")
                    }
                    record(planned.shot, ["action": .str("send blocked"), "reason": .str(Self.wrongPlaceReason + wrong)])
                    return false
                }
                // Customer spec 11-10 (§0.6, §13.3): a message from a task the cloud gave waits for approval before it goes.
                // Over Wi-Fi 11-10 a search (行事曆, www.163.com, 牙刷) was held for approval too: what the goal itself
                // names, in a goal that posts nothing, is not a message.
                if let text = unsent, let approveSend, Self.sends(act) || act["learned"] == .str("send"),
                   Self.needsApproval(text, task: task, chatApp: Self.inChatApp(steps, task: task)), !approvedTexts.contains(Self.typedKey(text)) {
                    var shown = text  // what the approval shows: a paste, as read off the screen (B4)
                    if text == Self.pastePlaceholder, let before = pasteFrame, let current = screen?.frame ?? planned.shot {
                        let beforeRows = await CandidatePicker.rowsOffMain(in: before, top: 0.05, bottom: 1)
                        let afterRows = await CandidatePicker.rowsOffMain(in: current, top: 0.05, bottom: 1)
                        let words = Self.newWords(before: beforeRows, after: afterRows)
                        if !words.isEmpty { shown = "（粘贴）" + words }
                    }
                    record(planned.shot, ["action": .str("waiting approval"), "reason": .str("about to send: " + String(shown.prefix(120)))])
                    let approved = await approveSend(shown)
                    try Task.checkCancellation()
                    guard approved else {
                        // The draft stays in the box otherwise, and the next task found it there (x11, 11-10: 17 deletes).
                        try? await phone?.key("cmd+a")
                        try? await phone?.key("backspace")
                        unsent = nil
                        // The picture the cloud gets is this step's: the box once it is empty, not the draft still in it (11-10).
                        let cleared = await freshFrame()
                        record(cleared ?? screen?.frame, ["action": .str("done"), "answer": .str(Self.notApprovedAnswer), "approval": .str("rejected")])
                        return true
                    }
                    approvedTexts.insert(Self.typedKey(text))
                }
                // #17 (122, 11-11): a like, a follow or a 收藏 shows to others like a message, and went unasked. A tap the
                // model says does one is refused in a goal that says not to, and waits for approval in a task from the cloud.
                if name == "tap", let what = Self.publicTap(act) {
                    if Self.forbids(task, what) {
                        record(planned.shot, ["action": .str("refused"),
                                              "reason": .str("Refused: the goal says not to \(what). Do not tap it; go on with the rest of the goal.")])
                        return false
                    }
                    if let approveSend, !approvedTexts.contains("tap:" + what) {
                        record(planned.shot, ["action": .str("waiting approval"), "reason": .str("about to tap: " + what)])
                        let approved = await approveSend("（\(what)）")
                        try Task.checkCancellation()
                        guard approved else {
                            record(planned.shot, ["action": .str("done"), "answer": .str("没有\(what)：未获批准。"), "approval": .str("rejected")])
                            return true
                        }
                        approvedTexts.insert("tap:" + what)
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
                catch let absent as AppNotOnPhone {
                    record(planned.shot, ["action": .str("open failed"), "app": .str(absent.name), "reason": .str(absent.name + Self.openFailedReason)])
                    return false
                }
                catch let keys as KeysNotOnScreen {
                    record(planned.shot, ["action": .str("press failed"), "reason": .str(keys.localizedDescription)])
                    return false
                }
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
                    if sendIsMessage {
                        messageSent.insert(Self.typedKey(text))
                        // 125 over the cloud 11-12 (k03): both messages went out, then "look at both groups once more"
                        // went back and forth with nothing written down, the loop guard ended it, and what it found
                        // said nothing of the sends. A message sent is written down, where it went and what it said.
                        let line = Self.sentNote(text, to: approvalPlace)
                        if !notes.contains(line) {
                            notes.append(line)
                            (stallsNoProgress, refusalsNoProgress) = (0, 0)
                            gotOn()
                        }
                    }
                    sendIsMessage = false
                    if let place = approvalPlace { sentPlaces[Self.typedKey(text), default: []].insert(place) }
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
                // The keys of a calculator, a number pad, several checkboxes: the next tap still fits while the screen
                // is the same one (over USB 11-09: 1234 x 5678, one key per model call, 293 s and no answer).
                if following == "tap", let was = seen.flatMap(Vision.look), let now = screen?.frame.flatMap(Vision.look),
                   Vision.sameScreen(was, now) { continue }
                // A tap into a text field and the typing after it (build 116): Codex answered one action at a time, ~12 s
                // a look, and the typing waited a whole look to see the keyboard (11-10). With a keyboard up, it goes on.
                if following == "type", await keyboardNowUp() {
                    DebugLog.write("tap then type in one reply: a keyboard is up, typing")
                    continue
                }
                return false
            }
        }
        timing.frameMs += try await settle()
        // feedback for the next round
        steps[steps.count - 1]["changed"] = .bool(Vision.changed(seen, screen?.frame, ignore: spots))
        // A swipe from the margin over a page that moves by itself (Weather's sky) "changed" the screen without scrolling it:
        // over USB 11-10, 20 swipes on Beijing's forecast and the run ran out of time. The words tell whether it scrolled.
        if let last = steps.last, last["action"]?.str == "swipe", last["x1"]?.int == Self.marginX, let was = seen, let shown = screen?.frame {
            let before = await CandidatePicker.rowsOffMain(in: was, top: 0.055, bottom: 1)
            let after = await CandidatePicker.rowsOffMain(in: shown, top: 0.055, bottom: 1)
            if Self.sameWords(before, after) { steps[steps.count - 1]["scrolled"] = .bool(false) }
        }
        noteDeadTap()
        return false
    }

    private func keyboardNowUp() async -> Bool {
        if ourKeyboardOnScreen?() == true { return true }
        guard let shown = screen?.frame else { return false }
        return await CandidatePicker.keyboardUpOffMain(in: shown)
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
                if ourKeyboardOnScreen?() == true, let keyboardReturn, await keyboardReturn() {} else { try await phone.key("enter") }
                returnSent = true
                return DebugLog.write("type: typed by Lan Agent's keyboard, sent with Return")
            }
            return DebugLog.write("type: typed by Lan Agent's keyboard")
        }
        if Pasteboard.needed(text), try await typedQuickly(text, phone: phone) {
            if returnSends {
                if ourKeyboardOnScreen?() == true, let keyboardReturn, await keyboardReturn() {} else { try await phone.key("enter") }
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
    /// the alarm (live test 11-08). 20 a part, never fewer than `base`, at most 240: 122 over the cloud 11-12, goals
    /// of 9 to 15 parts ran out at 100 (4 of 5 failures of the big ones), each part taking 10 to 15 steps.
    static func stepBudget(plan: String, base: Int, goal: String = "") -> Int {
        let parts = max(Self.parts(of: plan).count, goalParts(goal))
        guard parts >= 2 else { return base }
        return max(base, min(parts * 20, 240))
    }

    /// A part that asks to find something out (记下, 查, 看, 是什么, 多少…), as against one that does something (send,
    /// open, sum up what was found).
    static func readsSomething(_ part: String) -> Bool {
        let p = AppNames.hans(part)
        let words = ["记下", "记录", "查", "看", "读", "多少", "几", "是什么", "是不是", "是否", "星期", "温度", "价格", "作者",
                     "标题", "名称", "名字", "点赞数", "版本", "电量"]
        return words.contains { p.contains($0) }
    }

    /// What a tap does that others see (点赞, 关注, 收藏), by the model's own words for it, or nil. What it says it will
    /// not do, and counts or tabs it only reads (点赞数, 已关注, Douyin's 关注 tab), are not the tap.
    static func publicTap(_ act: JObject) -> String? {
        guard act["action"]?.str == "tap" else { return nil }
        var t = AppNames.hans(((act["thought"]?.str ?? "") + " " + (act["thought_zh"]?.str ?? "")).lowercased())
        t = t.replacingOccurrences(of: #"(不要|不用|避免|别|勿|以免|而不是|don't|do not|avoid|not |without|instead of)[^，,。.；;]*"#,
                                   with: " ", options: .regularExpression)
        let like = #"点赞按钮|点个赞|给[^，,。]{0,8}点赞|点赞(这|该|视频|笔记|一下)|点击点赞|tap (the )?(heart|like)\b|like button|\blike (it|this|the video|the post|the note)"#
        let follow = #"加关注|点关注|关注按钮|点击关注(?!页|栏|tab)|关注(他|她|作者|博主|这个|该)|follow button|\bfollow (him|her|the author|this|the account)"#
        let keep = #"收藏按钮|点击收藏|收藏(这|该|一下|视频|笔记)|加入收藏|bookmark (it|this|the)|save (it|this) to"#
        for (pattern, what) in [(like, "点赞"), (follow, "关注"), (keep, "收藏")]
        where t.range(of: pattern, options: .regularExpression) != nil { return what }
        return nil
    }

    /// The goal says not to do this (不要点赞, 别关注…).
    static func forbids(_ task: String, _ what: String) -> Bool {
        AppNames.hans(task).range(of: #"(不要|不用|不必|别|勿|禁止|不能)[^，,。；;！!？?\n]{0,30}"# + what, options: .regularExpression) != nil
    }

    static let emptyPartReason = "This part asks to find something out, but nothing was written down for it. Write what you "
        + "found with note (or note that it could not be found and why), then finish the part."

    /// 122.2 over the cloud 11-12: Weather's city row was tapped 11 times in a row (13 steps, 43 s): the pointer was not
    /// seen over its moving sky and no tap counted as one that did nothing. The same spot three times in a row, with
    /// nothing else between, is enough: the next is refused.
    static let sameTapLimit = 3
    static let sameTapReason = "Refused: this spot was just tapped 3 times in a row and the task did not get on. It is not "
        + "the control you want: look at what else is on the screen, scroll, or go another way."

    /// How many taps in a row, up to now, aimed at the same spot as `act` (notes, stale plans and refusals between
    /// them do not count as something else).
    static func tapsInARow(_ steps: [JObject], like act: JObject) -> Int {
        var n = 0
        for s in steps.reversed() {
            let name = s["action"]?.str ?? ""
            if ["stale plan", "note", "refused"].contains(name) { continue }
            guard name == "tap", sameSpot(s, act) else { break }
            n += 1
        }
        return n
    }

    /// 122 on the phone 11-12: "2027 年 1 月 1 日是星期几" was answered 星期三; it is a Friday. A date the goal names gets
    /// its weekday worked out here, not by the model.
    static func dateFacts(in goal: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"(\d{4})\s*(?:年|-|/|\.)\s*(\d{1,2})\s*(?:月|-|/|\.)\s*(\d{1,2})"#) else { return "" }
        let calendar = Calendar(identifier: .gregorian)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.dateFormat = "yyyy-MM-dd, EEEE"
        let zh = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        let ns = goal as NSString
        var said: [String] = []
        for m in re.matches(in: goal, range: NSRange(location: 0, length: ns.length)) {
            guard let y = Int(ns.substring(with: m.range(at: 1))), let mo = Int(ns.substring(with: m.range(at: 2))),
                  let d = Int(ns.substring(with: m.range(at: 3))), (1...12).contains(mo), (1...31).contains(d),
                  let date = calendar.date(from: DateComponents(year: y, month: mo, day: d)),
                  calendar.component(.day, from: date) == d else { continue }
            let line = "\(f.string(from: date)) (\(zh[calendar.component(.weekday, from: date) - 1]))"
            if !said.contains(line) { said.append(line) }
        }
        return said.isEmpty ? "" : " Dates in the goal: " + said.joined(separator: "; ") + "."
    }

    /// The numbered lines of a plan ("1. ...", "2) ...", "3、..."), trimmed.
    static func parts(of plan: String) -> [String] {
        plan.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^\d{1,2}\s*[.)、．]"#, options: .regularExpression) != nil }
    }

    static let partSteps = 20       // steps on one part before Codex looks and drives
    static let troubleLimit = 3     // or this many steps that plainly failed
    static let swipesInARow = 5     // or this many swipes in a row (a wheel: 14 wrong swipes, then one tap by Codex)

    /// A step that plainly failed: it changed nothing, or was refused, or a stroke left no ink.
    static func isTrouble(_ step: JObject) -> Bool {
        step["changed"] == .bool(false)
            || ["no ink", "blocked", "done rejected", "refused", "loop", "open failed"].contains(step["action"]?.str ?? "")
    }

    /// Whether two screens read the same: most of what was read still reads, in the same place (a video or an animation
    /// behind it moves; on a list that scrolled the words are the same and their places are not).
    static func sameWords(_ a: [[CandidatePicker.Piece]], _ b: [[CandidatePicker.Piece]]) -> Bool {
        func words(_ rows: [[CandidatePicker.Piece]]) -> [CandidatePicker.Piece] { rows.flatMap { $0 }.filter { AppPlaces.normalized($0.text).count >= 2 } }
        let (x, y) = (words(a), words(b))
        guard x.count >= 3, !y.isEmpty else { return false }
        let kept = x.filter { p in
            y.contains { AppPlaces.normalized($0.text) == AppPlaces.normalized(p.text) && abs($0.box.midX - p.box.midX) < 0.02 && abs($0.box.midY - p.box.midY) < 0.01 }
        }
        return kept.count * 10 >= max(x.count, y.count) * 7
    }

    /// A guard saw the run go round: Codex looks afresh once, another way. If it goes round again the run stops. True: it stopped.
    private func changeOfPlan(_ shot: Data?, _ why: String) async throws -> Bool {
        guard !rescued else {
            record(shot, ["action": .str("fail"), "reason": .str(why)])
            return true
        }
        rescued = true
        circleRefused = 0
        record(shot, ["action": .str("loop"), "reason": .str(why)])
        try await replan(stuck: true)
        // The new plan starts clean. Build 118, 11-11: Weather's map was opened twice by mistake, Codex planned "close the
        // map, open the list on the right", and its first move, closing the map, was refused as the old circle; the run
        // failed. A second circle under the new plan still fails (rescued).
        gotOn()
        return false
    }

    static let takeoverSteps = 15   // steps Codex drives after a stall, until its part is done

    /// What the executor is told about its part (nothing for a plan of one part or a fixed plan).
    private var partFocus: String {
        guard parts.count >= 2, planner != nil, partIndex < parts.count else { return "" }
        var text = "Current part (\(partIndex + 1) of \(parts.count)): \(parts[partIndex])\n"
        if !doneParts.isEmpty { text += "Already done, with what it found: " + doneParts.joined(separator: " | ") + "\n" }
        return text + "Work on the current part only. When it is finished on the screen, answer done with what it achieved;"
            + " then the next part begins.\n\n"
    }

    /// Something was found or finished: coming back to a screen from here is the work, not a circle. A task of several
    /// parts goes back and forth by nature, and the guard stopped runs with the first part done (e01, f02, f06 on 11-09).
    private func gotOn() {
        (departures, circleRefused, bounceGuard, bounceRefused, deadRefused) = ([], 0, nil, 0, 0)
    }

    /// A list is scrolled from the screen's margin: a press that starts on a button can click it (over USB 11-09 three
    /// swipes each moved a permission sheet a step on). Measured in Settings: from the margin it scrolls the same. Not from
    /// the floating bars at the bottom either. What the margin does not move (a time picker) gets the model's own spot.
    static let marginX = 40

    static func safeSwipe(_ act: JObject, after steps: [JObject]) -> JObject {
        guard let x1 = act["x1"]?.double, let y1 = act["y1"]?.double, let x2 = act["x2"]?.double, let y2 = act["y2"]?.double,
              abs(x2 - x1) < 100, abs(y2 - y1) > 100 else { return act }
        if let last = steps.last(where: { $0["action"]?.str != "stale plan" }), last["action"]?.str == "swipe",
           last["changed"] == .bool(false) || last["scrolled"] == .bool(false) { return act }
        let shift = max(0, max(y1, y2) - 800)
        var safe = act
        safe["x1"] = .int(marginX); safe["x2"] = .int(marginX)
        safe["y1"] = .int(Int(y1 - shift)); safe["y2"] = .int(Int(y2 - shift))
        return safe
    }

    static let doneCheck = """
    You check another agent's finished work on an iPhone. You get the goal, its answer, what it did and noted, and the screen now.
    Reply with exactly one line: OK, or NO: what is wrong, in a few words.
    Say NO only for one of these:
    - Something the goal asks for was not done or is missing from the answer.
    - A value in the answer (date, number, price, name, count) differs from the notes or from what the screen shows.
    - The answer reports something from an app the steps never opened.
    - The answer says something was sent or saved, the screen is where it would show, and it does not show.
    - The goal names no city or place and the answer is for a city an app kept from before, not the phone's own location.
    - A cart or order on the screen holds more of an item than the goal asked for (×3 for one cup), or the answer leaves out how many.
    The screen may have moved on: what was noted or done earlier stands unless the screen contradicts it. Work out dates from today's date. Never judge style or wording, nor the answer's language.
    A note, memo or document has no separate title field: its first line is its title.
    In a list of days (a 10-day forecast), today's row is first and tomorrow is the row right under it; a weekday name further down is a later week. An answer for "tomorrow" read off a lower row is wrong.
    An app counts as opened when a step opened it, or tapped its icon (a tap that says it opens the app).
    Simplified and traditional Chinese of the same words are the same (压力测试 = 壓力測試). A value that moves by itself (a live price, a time, a count) may differ a little from the screen now: that is not wrong.
    A message the steps typed and then sent with enter counts as sent, unless that chat is on the screen and it is not there.
    """

    /// The models have no clock. Over USB 11-09, today the 9th: a check said next Wednesday was the 25th and threw out the right
    /// answer, the 18th, and the run went on to "today is 2025-06-03" and its step limit.
    static func todayLine(_ date: Date = Date(), goal: String = "") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd, EEEE"
        // Build 117 on the phone: the check worked a weekday out wrong from a forecast. The next two days are given too.
        let day = { (n: Int) in f.string(from: Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: date) ?? date) }
        return "Today is \(f.string(from: date)). Tomorrow is \(day(1)); the day after is \(day(2))." + dateFacts(in: goal)
    }

    /// Over USB 11-09, 5 of 14 "done" were wrong: a Pinduoduo price from an app never opened, a message never sent, the 17th
    /// read off a screen saying the 16th. The model's word is not the result: something else looks. What it says, or nil when
    /// nothing is wrong or the check itself failed (a check must not stop the work).
    private func wrongClaim(_ answer: String, frame: Data?) async -> String? {
        guard let model = doneChecker ?? planner ?? actor else { return nil }
        let prompt = checkPrompt(answer)
        do {
            let reply = try await model.chat(system: Self.doneCheck, text: prompt, image: frame, maxTokens: 120, temperature: 0).text
            trace?.write(kind: "done check", ["reply": .str(String(reply.prefix(300)))])
            DebugLog.write("done check: \(reply.prefix(160))")
            return Self.wrongness(reply)
        } catch {
            DebugLog.write("done check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func checkPrompt(_ answer: String) -> String {
        Self.checkPrompt(goal: task, today: Self.todayLine(goal: task), answer: answer, did: Self.whatItDid(steps), notes: notes,
                         sent: sent, parts: parts.count)
    }

    /// Build 121 over the cloud 11-11: goals of 7 and 8 parts were answered right and reported "（未能核實）": the check saw
    /// only the last screen (高德, 验证群), so the battery read in Settings and the message sent to 测试群 earlier were "not
    /// on screen", twice. What it wrote down and what it sent go with the check now, and why the screen cannot show them.
    static func checkPrompt(goal: String, today: String, answer: String, did: String, notes: [String], sent: [String],
                            parts: Int) -> String {
        var text = "Goal: \(goal)\n\(today)\n\nIts answer: \(answer)\n\nWhat it did:\n\(did)"
        if !notes.isEmpty {
            text += "\n\nWhat it wrote down while it worked (read off earlier screens):\n" + notes.map { "- " + $0 }.joined(separator: "\n")
        }
        if !sent.isEmpty { text += "\n\nMessages it sent in this run and saw go out: " + sent.joined(separator: "、") }
        if parts > 1 {
            text += "\n\nThis goal has \(parts) parts done one after another, and the screen shows only where the last one ended. "
                + "A value or a send from an earlier part is checked against what it did and wrote down above, not against this "
                + "screen: call it wrong only when this screen or those lines contradict it."
        }
        return text + "\n\nThe image is the screen now."
    }

    /// The same answer again after the quick check refused it: the check may be the one that is wrong. Build 117 on the
    /// phone, 11-10: it worked out today as Monday from a forecast, and once took the second headline for the first; right
    /// answers were reported "not checked" or cost a round. The planner (Codex) looks once; only its OK counts, so a
    /// failed call changes nothing.
    private func confirmedBySecondModel(_ answer: String, frame: Data?) async -> Bool {
        guard let second = planner, second !== (doneChecker ?? planner ?? actor) else { return false }
        do {
            let reply = try await second.chat(system: Self.doneCheck, text: checkPrompt(answer), image: frame, maxTokens: 120, temperature: 0).text
            trace?.write(kind: "done check (second)", ["reply": .str(String(reply.prefix(300)))])
            DebugLog.write("done check (second model): \(reply.prefix(160))")
            return Self.wrongness(reply) == nil
        } catch {
            DebugLog.write("done check (second model) failed: \(error.localizedDescription)")
            return false
        }
    }

    static func wrongness(_ reply: String) -> String? {
        let line = reply.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
        guard line.range(of: #"^NO\b"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        let why = line.dropFirst(2).trimmingCharacters(in: CharacterSet(charactersIn: " :：,，-"))
        return "A check of the finished work says: " + (why.isEmpty ? "the answer is not supported" : why)
            + ". Fix it on the phone or correct the answer, then finish again."
    }

    /// The executor's (or Codex's) "done" on a plan of several parts: the next part begins, the last one ends the run.
    /// A part Codex rescued is done: the executor takes the next one. True: the run goes on.
    private func partFinished(_ act: JObject, shot: Data?) -> Bool {
        guard parts.count >= 2, partIndex < parts.count else { return false }
        let n = partIndex + 1
        // What a part found is what the next one needs: a price read in one app goes into a message in another.
        let found = String((act["answer"]?.str ?? "").prefix(300))
        // B8, 122 over the cloud 11-12: the 视频号 part of an 11-part goal was finished with nothing found or written
        // down, and its result was simply missing. A part that asks to find something out is sent back once.
        if found.isEmpty, notes.count == notesAtPart, emptyPartRefused != partIndex, Self.readsSomething(parts[partIndex]) {
            emptyPartRefused = partIndex
            record(shot, ["action": .str("part not done"), "part": .int(n), "reason": .str(Self.emptyPartReason)])
            return true
        }
        doneParts.append(found.isEmpty ? parts[partIndex] : parts[partIndex] + " -> " + found)
        record(shot, ["action": .str("part done"), "part": .int(n), "by": .str(act["by"]?.str ?? "actor")])
        gotOn()
        (stallsNoProgress, refusalsNoProgress) = (0, 0)
        (partIndex, stepsInPart, notesAtPart) = (partIndex + 1, 0, notes.count)
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

    /// What a run did, for the check: every app opened, text typed and note, and the last taps. Over USB 11-10 50 calculator
    /// taps pushed the opening of 淘寶 and 拼多多 out of the last 40 lines, and the check said they were never opened.
    static func whatItDid(_ steps: [JObject], taps: Int = 20) -> String {
        let tapIndices = steps.indices.filter { steps[$0]["action"]?.str == "tap" }
        let kept = Set(tapIndices.suffix(taps))
        return steps.indices.compactMap { i -> String? in
            let s = steps[i]
            switch s["action"]?.str {
            case "open": return "opened " + (s["app"]?.str ?? "?")
            case "type": return "typed " + String((s["text"]?.str ?? "").prefix(80))
            case "press": return "pressed the keys " + String((s["text"]?.str ?? "").prefix(80))
            case "note": return "noted " + String((s["text"]?.str ?? "").prefix(200))
            case "listen": return "listened to the video and read its subtitles (the text is in the notes)"
            case "hold": return "long-pressed at (\(s["x"]?.int ?? 0), \(s["y"]?.int ?? 0))"
            case "key" where sends(s): return "pressed enter"
            // Over USB 11-10 拼多多 was opened by its icon on the Home Screen, and the check said it never was: that tap
            // had dropped out of the last 20 and its words were cut at 60.
            case "tap" where opensByIcon(s): return "tapped " + String((s["thought"]?.str ?? "").prefix(120))
            // Over USB 11-09 a note was reopened from the list, twice, and the check said it never was: it saw no taps.
            case "tap" where kept.contains(i): return "tapped " + String((s["thought"]?.str ?? "").prefix(60))
            default: return nil
            }
        }.joined(separator: "\n")
    }

    /// A tap that says it opens an app by its icon (the Home Screen), in the model's own words.
    static func opensByIcon(_ step: JObject) -> Bool {
        guard step["action"]?.str == "tap", let t = step["thought"]?.str?.lowercased() else { return false }
        let icon = ["圖示", "图示", "圖標", "图标", "icon", "主畫面", "主画面", "主屏", "home screen"].contains { t.contains($0) }
        let opens = ["打開", "打开", "開啟", "开启", "啟動", "启动", "open", "launch"].contains { t.contains($0) }
        return icon && opens
    }

    /// A remembered way as the plan: its steps as hints, not numbered parts.
    static func rememberedPlan(_ recipe: RouteBook.Recipe) -> String {
        "Do it the way it was done before; adapt any text, time or name to this goal. Where the next steps are clear, "
            + "answer several DO lines at once (each step costs seconds of thinking), and look at the result. "
            + "The earlier run may have begun somewhere else (already inside a chat or a page): before typing, check that the "
            + "screen is where this goal says (the title at the top), and go there first if it is not:\n"
            + recipe.lines.map { "- " + $0 }.joined(separator: "\n")
    }

    func replan(stuck: Bool = false) async throws {
        guard let planner else { throw LLMError(message: "no planner model") }
        var prompt = "Goal: \(task)\n\(Self.todayLine(goal: task))"
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
        prompt += notesText
        let (reply, seconds, frame) = try await ask("planner", planner, plannerPrompt, prompt)
        let (en, zh) = Actions.parsePlan(reply)
        // build105 live 11-08: Plus timed out, and the fallback answered {"action":"search",...}, which became the plan.
        if !plan.isEmpty, en.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            DebugLog.write("plan: the reply was not a plan; keeping the last one")
        } else {
            plan = en
            (parts, partIndex, stepsInPart) = (Self.parts(of: en), 0, 0)
        }
        record(frame, ["action": .str(stuck ? "replan (stuck)" : "plan"), "plan": .str(en), "plan_zh": .str(zh),
                       "think_s": .num(seconds)])
        if stuck {
            takeover = Self.takeoverSteps
            record(nil, ["action": .str("planner drives"),
                         "reason": .str("the executor did not get on: Codex drives until this part is done, at most \(Self.takeoverSteps) steps")])
        }
    }

    /// The notes, for a prompt ("" when there are none).
    private var notesText: String {
        notes.isEmpty ? "" : "\n\nYour notes from this run (already read: use them, never go back to read these again):\n"
            + notes.map { "- " + $0 }.joined(separator: "\n")
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
        var prompt = "Goal: \(task)\n\(Self.todayLine(goal: task))\n\nPlan:\n\(plan)\n\n\(partFocus)Recent actions:\n\(recentActions)\(notesText)\n\nNext action?"
        let driving = (plannerLeads || takeover > 0) && planner != nil
        if takeover > 0 { takeover -= 1 }
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
        if readsScreenText, let shown = screen?.frame {
            readRows = await CandidatePicker.rowsOffMain(in: shown, top: 0.055, bottom: 1)
        } else {
            readRows = []
        }
        // 125 stress test 11-12 (s01): 加入购物车 was tapped again and again and the cart held ×5 of a cup the goal asked
        // for once. Each time the "added" toast comes up it is written down, and the model is told at once.
        let cartToast = Self.addedToCart(readRows)
        if cartToast, !cartToastShown {
            cartAdds += 1
            let line = Self.cartNote(cartAdds)
            notes.append(line)
            gotOn()
            prompt += "\n\n" + line
        }
        cartToastShown = cartToast
        if readsScreenText, let list = Self.screenText(readRows) {
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
                    (takeover, plannerLeads) = (0, false)
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

    /// Half the size of the text a tap lands on (a little smaller than its box): the tap is surely on it inside that.
    /// 122.1 on the phone: only 10 of 60 taps used it; the model aims at a button's middle, its label's box is smaller,
    /// so a tap up to 1.2% outside the text counts as on it (122.2).
    static func textHalf(at p: CGPoint, in rows: [[CandidatePicker.Piece]]) -> (x: Double, y: Double)? {
        for piece in rows.joined() where piece.box.insetBy(dx: -0.012, dy: -0.012).contains(p) {
            let hx = Double(piece.box.width) / 2 * 0.8, hy = Double(piece.box.height) / 2 * 0.8
            return hx > 0.008 || hy > 0.008 ? (hx, hy) : nil
        }
        return nil
    }

    private func perform(_ a: JObject) async throws {
        guard let phone else { throw DeviceError(message: "no phone") }
        func p(_ k: String) -> Double { (a[k]?.double ?? 0) / 1000 }
        switch a["action"]?.str {
        case "tap":
            lastTap = CGPoint(x: p("x"), y: p("y"))
            if let half = Self.textHalf(at: CGPoint(x: p("x"), y: p("y")), in: readRows) { phone.aimLoosely(half.x, half.y) }
            try await phone.tap(p("x"), p("y"), aim: (a["precise"]?.bool ?? false) || missed || aimNext)
            aimNext = false
        case "swipe": try await phone.swipe(p("x1"), p("y1"), p("x2"), p("y2"), hold: true)
        case "hold": try await phone.longPress(p("x"), p("y"), seconds: 0.8)
        case "listen":
            // User 11-11: a video's spoken words (口播文案) and what it is about, from WeChat, 抖音, 视频号.
            guard let listen else { throw DeviceError(message: "Listening is not available here.") }
            let seconds = min(max(a["seconds"]?.double ?? 60, 5), 180)
            let earlier = notes.filter { $0.hasPrefix("听到和字幕") }
            let heard = await listen(seconds)
            notes.append("听到和字幕（\(Int(seconds)) 秒）：" + String(heard.prefix(4000)))
            // 124 on the phone 11-12 (h07): a short 抖音 video plays round and round, and it was listened to six times
            // over. Heard again is heard all.
            if Self.repeatsHeard(heard, before: earlier) {
                listenedAll = true
                notes.append(Self.videoLoopedNote)
            }
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
        case "key":
            let combo = a["combo"]?.str ?? ""
            if ["enter", "return"].contains(combo.lowercased()), ourKeyboardOnScreen?() == true,
               let keyboardReturn, await keyboardReturn() { break }
            try await phone.key(combo)
        case "press":
            guard let shown = screen?.frame else { throw DeviceError(message: "no screen to find the keys on") }
            // Over USB 11-10 Calculator took typed sums at once (128*0.85= gave 108.8, esc cleared it), while reading its
            // keys found 9 of 19 labels and three cloud tasks gave up there. Typed first; the read keys only if nothing changed.
            if let typed = Self.typedKeys(Self.keyTokens(a["text"]?.str ?? "")) {
                for piece in typed {
                    if piece == "esc" { try await phone.key("esc") } else { try await phone.type(piece) }
                }
                if let after = await freshFrame(), Vision.changed(shown, after) {
                    DebugLog.write("press: typed \(typed.joined(separator: " ")) on the keyboard")
                    break
                }
                DebugLog.write("press: typing changed nothing; tapping the keys")
            }
            let rows = await CandidatePicker.rowsOffMain(in: shown, top: 0.1, bottom: 1)
            let found = Self.keySpots(a["text"]?.str ?? "", in: rows.flatMap { $0 })
            guard found.missing.isEmpty, !found.spots.isEmpty else {
                throw KeysNotOnScreen(missing: found.missing, seen: Self.keysSeen(rows.flatMap { $0 }))
            }
            for spot in found.spots {
                try await phone.tap(Double(spot.x), Double(spot.y), aim: false)
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        case "home": try await phone.goHome()
        case "back": try await phone.goBack()
        case "open":
            let app = a["app"]?.str ?? ""
            guard let openApp else { throw DeviceError(message: "Opening apps by name is not available here; use the Home Screen.") }
            guard try await openApp(app) else { throw AppNotOnPhone(name: app) }
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
