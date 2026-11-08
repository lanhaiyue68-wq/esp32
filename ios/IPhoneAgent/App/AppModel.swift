import Combine
import Foundation
import UIKit

/// Wires the board, the screen feed, the pointer, the agent and the metrics together.
@MainActor final class AppModel: ObservableObject {
    /// One per process: the UI, App Intents (also when iOS launches the app in the background) and widgets use it.
    static let shared = AppModel()

    struct LogLine: Identifiable {
        let id = UUID()
        let time = Date()
        let text: String
    }

    let settings = Settings()
    let board = BoardLink(mock: MockMode.on)
    let feed = VideoFeed(source: MockMode.on ? .mirror : .preferred)
    let metrics = Metrics()
    let traces = MockMode.on
        ? TraceStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("demo-traces"))
        : TraceStore()
    let intents = IntentStore()
    private(set) lazy var runs = RunStore(traces: traces)
    let pointer: Pointer
    let agent: AgentLoop
    @Published private(set) var log: [LogLine] = []
    @Published var refreshingStatus = false
    @Published var statusRefreshError: String?
    private var lastStatusRefresh = 0.0
    @Published var modelError: String?
    @Published var modelTestStarted: Date?
    @Published var modelTestSeconds: Double?
    @Published var modelFirstTokenSeconds: Double?
    @Published var modelResponseSeconds: Double?
    @Published var modelOK: Bool?  // last LLM ping result
    @Published var hotspotSSID: String?
    @Published var otherWiFi: String?  // the phone is on this network, not the board's
    /// The character's mood during and right after a run; nil = resting (idle or sleeping, see `mood`).
    @Published var runMood: Mood?
    @Published var tab = AppTab.agent
    /// Setup page to show (onboarding, or a Home status chip deep link); nil = hidden.
    @Published var setupPage: SetupPage?
    /// The review editor on screen (after a run, a recording, or editing an intent).
    @Published var review: ReviewDraft?
    /// Paused for the user: why (nil = not paused), and whether they are doing it by hand right now.
    @Published var help: String?
    @Published var recovering: Recovery.Stage?  // the run is paused for a lost link (board, hotspot, mirroring)
    var recoverySince = Date()
    @Published var takingOver = false
    @Published var departing = false  // the character's take-off before a run
    let runStartGate = RunStartGate()
    @Published var startingAgent = false
    /// A banner on Home: the app could not leave by itself (swipe up), or the run waits while the app is in front.
    @Published var homeHint: String?
    var resumeAsked = 0.0  // when Continue was tapped in the app
    let live = LiveActivityController()
    let notifier = Notifier()
    private(set) lazy var recorder = DemoRecorder(app: self)
    var mockJob: Task<Void, Never>?
    @Published var mockMirroring = false
    var moodReset: Task<Void, Never>?
    var helpWait: CheckedContinuation<AgentLoop.HelpChoice, Never>?
    var currentIntent: SavedTask?
    var lastTask = ""
    var runStarted = Date()
    private var settingsSink: AnyCancellable?
    var videoSink: AnyCancellable?
    var videoDir: URL?
    private(set) lazy var calibrator = AutoCalibrator(app: self)
    let probe = TouchProbe()
    private var lastStatus = ""
    private var lastTick = now()
    private var notStreamingSince: Double?

    /// The board's AirPlay state into feed.mirroring. "connected" is the session with no video for a few seconds (a
    /// still screen, a busy Wi-Fi): firmware before v30 said so after 3 s, flipping back and forth, and every run
    /// stopped as if mirroring were gone (logs(16)). It counts as lost after 10 s of it, or at once when the session
    /// itself is gone ("idle").
    func noteMirroring(_ ap: String?) {
        guard !feed.isNative else { return }
        if ap == "streaming" { (notStreamingSince, feed.mirroring) = (nil, true); return }
        if ap == "connected", feed.mirroring {
            let since = notStreamingSince ?? now()
            notStreamingSince = since
            if now() - since < 10 { return }
        }
        notStreamingSince = nil
        feed.mirroring = false
    }
    private var lastStreamLog = 0.0
    private var timers: [Task<Void, Never>] = []
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Silence during a run, so iOS never suspends the app (and its Wi-Fi video) while it works in the background.
    let keepAwake = BackgroundAudio()
    let keyboardBridge = KeyboardBridge()  // Lan Agent's keyboard asks it for text over 127.0.0.1 (specs/004)
    let testChannel = TestChannel()        // tasks and gestures from the USB computer, with the token on the phone
    /// WeChat watch (WatchMode.swift): waiting on WeChat, a short run whenever new messages show up.
    @Published var watching = false
    @Published var watchStatus = ""
    @Published var watchHandled = 0
    @Published var watchRead = 0  // messages read since the watch started (ReadLog keeps them)
    var watchJob: Task<Void, Never>?
    /// ChatTool on the computer (ChatToolLink.swift), connected while watching with it switched on.
    let chatTool = ChatToolLink()
    var computerKnowledgeCache = ""  // the last knowledge fetched from the computer, for when it is out of reach
    /// Per chat: the last 20 messages seen, to tell what is new (WatchReport.new, as ChatTool keeps them). Kept
    /// across watches and launches, so a new watch takes up where the last one stopped.
    var watchLast: [String: [WatchReport.Line]] = [:] { didSet { WatchReport.saveLooks(watchLast) } }
    var pasteHopping = false  // Lan Agent is in front for a paste (hopToPaste): not a reason to hold the run
    var afterPhoneTask = false  // a phone task just ran (maybe in another app): the walk back skips blind back taps
    var watchStartedAt = 0.0    // when Start was tapped: a report pending then may open WeChat directly
    var watchAnswered: [String: Double] = [:]  // a message answered, by WatchReport.answerKey: when
    var watchInterjectedAt: [String: Double] = [:]  // per chat: the last interjection, at most one per ten minutes
    var watchSelfOpened: (chat: String, at: Double)?  // a chat this watch opened from its red number (its badge is gone now)
    var watchRetries: [String: Int] = [:]  // per chat: replies that did not go out, read again at the next check
    var watchTaskReply = WatchTaskReply.saved() { didSet { WatchTaskReply.save(watchTaskReply) } }
    var watchTaskReplyFailures = 0
    var watchLastTask: [String: String] = [:]  // per chat: the owner's last phone task, for "再去做一遍"
    let watchListReturn = WatchListReturn()
    var lastWidgetReload = 0.0

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        pointer = Pointer(device: board.commands, calibrationFile: support.appendingPathComponent("calibration.json"),
                          screen: feed)
        agent = AgentLoop(phone: pointer, screen: feed, actor: nil, planner: nil, trace: traces)
        if !MockMode.on {
            let memory = ExperienceStore(file: support.appendingPathComponent("experience-v1.json"))
            memory.enabled = UserDefaults.standard.object(forKey: ExperienceStore.enabledKey) as? Bool ?? true
            agent.experience = memory
            let lessons = LessonBook(file: support.appendingPathComponent("lessons-v1.json"))
            lessons.enabled = memory.enabled  // one switch: Settings › Privacy › Learn from operation feedback
            // Self-learned lessons up to build84 matched unrelated tasks and piled up "don't" rules with coordinates
            // (logs43–46); drop them once. The user's own corrections stay.
            if !UserDefaults.standard.bool(forKey: "selfLessonsReset85") {
                lessons.dropSelfLearned()
                UserDefaults.standard.set(true, forKey: "selfLessonsReset85")
            }
            agent.lessons = lessons
            let routes = RouteBook(file: support.appendingPathComponent("routes-v1.json"))
            routes.enabled = memory.enabled
            agent.routes = routes
            let controls = ControlBook(file: support.appendingPathComponent("controls-v1.json"))
            controls.enabled = memory.enabled
            agent.controls = controls
        }
        agent.metrics = metrics
        feed.device = board.commands
        feed.metrics = metrics
        keyboardBridge.start()
        testChannel.handle = { [weak self] request in
            await self?.answerTestChannel(request) ?? .json(["error": .str("not ready")], status: 503)
        }
        testChannel.start()
        if TestChannel.token() != nil {  // testing is on: the channel must live once the app is in the background
            keepAwake.hold = true
            keepAwake.start()
        }

        let say: (String) -> Void = { [weak self] in self?.say($0) }
        board.log = say
        board.commands.log = say
        pointer.log = say
        pointer.screenAspect = { DeviceScreen.aspect }
        pointer.locate = { [weak self] jpeg in await self?.locatePointer(jpeg) }
        DebugLog.relay = { [weak self] line in
            guard DebugLog.toComputer else { return }
            // DebugLog.write runs on any thread (MetricKit delivers crash reports on a background queue).
            let relay = { MainActor.assumeIsolated { if !MockMode.on { self?.board.commands.relayLog(line) } } }
            Thread.isMainThread ? relay() : DispatchQueue.main.async(execute: relay)
        }
        board.commands.onAppCommand = { [weak self] line in if DebugLog.toComputer { self?.handleAppCommand(line) } }
        DebugLog.write("app launched \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "")"
                       + " (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? ""))")
        DebugLog.write("capture: \(feed.source.rawValue), iOS \(UIDevice.current.systemVersion)")
        settingsSink = settings.$configurationRevision.dropFirst().sink { [weak self] _ in
            self?.modelOK = nil
            self?.modelError = nil
            self?.modelTestSeconds = nil
            self?.modelFirstTokenSeconds = nil
            self?.modelResponseSeconds = nil
        }
        board.onVideo = { [weak self] in self?.feed.receive($0) }
        board.onStatus = { [weak self] s in
            self?.statusRefreshError = nil
            self?.noteMirroring(s.ap)
            if self?.feed.isNative == false { self?.feed.tcp.update(ip: s.ip, token: self?.board.net?.video_token, boardHasClient: s.tcp.map { $0 > 0 },
                                  boardResumes: (s.fw.flatMap { Int($0.dropFirst()) } ?? 0) >= 29)
            }
            self?.feed.status(s)
            self?.metrics.status(s)
            self?.logStatus(s)
        }
        board.onLinkUp = { [weak self] in
            guard let self else { return }
            feed.resetStream()
            metrics.mtu = board.mtu
            if feed.isNative {
                Task { [weak self] in try? await self?.board.commands.send("stream off") }
                return
            }
            if agent.running && !MockMode.on && FrameMode.current == .stream {  // the board forgot `stream on`: the paused run needs the screen back
                Task { [weak self] in
                    do { try await self?.feed.stream(true); DebugLog.write("recover: BLE back, stream on again") } catch {
                        DebugLog.write("recover: stream on after reconnect failed: \(error.localizedDescription)")
                    }
                }
            }
        }
        board.onLinkDown = { [weak self] in self?.feed.linkLost() }
        board.commands.onTimeout = { [weak self] command in await self?.commandTimedOut(command) }
        DebugLog.write("frame mode: \(FrameMode.current.rawValue)")
        board.commands.onTiming = { [weak self] name, ms in self?.metrics.hidMs[name] = ms }
        agent.onFinish = { [weak self] in self?.agentFinished() }
        agent.onStep = { [weak self] in self?.stepped() }
        agent.onDoing = { [weak self] d in self?.doing(d) }
        agent.onHelp = { [weak self] reason in await self?.needsHelp(reason) ?? .stop }
        agent.gate = { [weak self] in try await self?.holdWhileInFront() }
        agent.pasteHop = { [weak self] text in await self?.hopToPaste(text) ?? .lost }
        // Phase B (specs/004): typing by Lan Agent's keyboard, opening apps by name, the screen's text for the model.
        agent.keyboardType = { [weak self] text in await self?.typeWithLanAgentKeyboard(text) ?? false }
        agent.keyboardReturn = { [weak self] in await self?.keyboardBridge.type("", enter: true, within: 4) ?? false }
        agent.ourKeyboardOnScreen = { [weak self] in self?.keyboardBridge.onScreen() ?? false }
        agent.openApp = { [weak self] name in try await self?.openApp(name) ?? false }
        agent.readsScreenText = !MockMode.on
        agent.plannerLeadsUnknown = !MockMode.on
        AgentControl.handle = { [weak self] command in await self?.control(command) }
        AgentRequests.handle = { [weak self] request in await self?.handle(request) ?? AgentRequests.unavailable }
        notifier.onAction = { [weak self] action, run in self?.notificationAction(action, run: run) }
        wireRecovery()

        timers.append(Task { [weak self] in
            await self?.board.commands.keepAwake(screenLive: {
                guard let feed = self?.feed else { return false }
                // A still direct-captured screen is never "live" (that needs a confirmation within 2 s): it was never
                // nudged, could lock, and the watch went blind after 3 minutes. Sharing on is what counts.
                return feed.isNative ? feed.watchable : feed.live
            })
        })
        timers.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        })
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.metrics.enteredBackground(); DebugLog.write("app: background")
                self?.refreshDecoderSoon()
            }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.metrics.enteredForeground(); DebugLog.write("app: foreground") }
        }
        if MockMode.on { startMock() }
        runs.reload()
        handleLaunchArguments()
        publishWidget()
    }

    /// Every second: metrics; a suspension note; the stream's numbers every 10 s while a run goes.
    private func tick() {
        if feed.isNative { feed.objectWillChange.send() } // Readiness expires even if the system stops callbacks.
        let before = metrics.suspensions, gap = now() - lastTick
        metrics.tick()
        lastTick = now()
        publishWidget()
        if metrics.suspensions > before { DebugLog.write(String(format: "app: resumed after %.0f s suspended", gap)) }
        if agent.running, now() - lastStreamLog >= 10 {
            lastStreamLog = now()
            if feed.isNative {
                DebugLog.write(String(format: "capture: direct, converted %.1f fps, pixel age %.2f s, proof age %.2f s, %@",
                                      metrics.fps, feed.capturedAt > 0 ? now() - feed.capturedAt : -1,
                                      feed.confirmedAt > 0 ? now() - feed.confirmedAt : -1, feed.nativeStatus))
                return
            }
            let s = board.status
            DebugLog.write(String(format: "stream: decoded %.1f fps, BLE in %.0f kbps (board %.0f kbps out, AirPlay %.0f kbps %.1f fps), frame age %.1f s, drops %d",
                                  metrics.fps, metrics.bleKbps, s?.ble?.kbps ?? 0, s?.kbps ?? 0, s?.fps ?? 0,
                                  feed.updated > 0 ? now() - feed.updated : -1, metrics.drops))
        }
    }

    /// A command timed out: video may be starving the board's control traffic. Stop the stream and run
    /// snap-per-step for the rest of this run (the next run streams again).
    private func commandTimedOut(_ command: String) async {
        guard !feed.isNative else {
            DebugLog.write("cmd timeout during direct capture: \(command.prefix(30))")
            return
        }
        DebugLog.write("cmd timeout on '\(command.prefix(30))': stream off, snap-per-step for this run")
        FrameMode.fallback = .snap
        if feed.streamOn { _ = try? await feed.stream(false) }
    }

    func setFrameMode(_ mode: FrameMode) {
        guard !feed.isNative else { return }
        FrameMode.current = mode
        say("frame mode: \(mode.rawValue)")
        if mode == .stream && agent.running { Task { try? await feed.stream(true) } }
        if mode == .snap && feed.streamOn { Task { try? await feed.stream(false) } }
    }

    var canChangeCaptureSource: Bool {
        !startingAgent && !agent.running && !watching && !calibrator.busy && !recorder.recording
    }

    func selectCaptureSource(_ source: CaptureSource) {
        guard canChangeCaptureSource else { return }
        feed.selectSource(source)
        if feed.isNative {
            joinTask?.cancel()
            Task { [weak self] in try? await self?.board.commands.send("stream off") }
        }
    }

    /// The run paused for the board (line) or goes on (nil).
    /// Board status changes go to the debug log (not every identical notify).
    private func logStatus(_ s: BoardStatus) {
        let line = "board status: ap \(s.ap ?? "-") usb \(s.usb ?? "-") sta \(s.sta.map(String.init) ?? "-")"
            + " screen \(s.w.map(String.init) ?? "-")x\(s.h.map(String.init) ?? "-") rst \(s.rst ?? "-")"
        guard line != lastStatus else { return }
        lastStatus = line
        DebugLog.write(line)
        if let up = s.up, up < 30_000 {  // a link drop that is really the board rebooting (crash, brownout, ...)
            DebugLog.write("board: booted \(up / 1000) s ago (reset: \(s.rst ?? "?"), heap \((s.heap ?? 0) / 1024) KB)")
        }
    }

    /// The character's mood right now.
    var mood: Mood { runMood ?? (board.connected ? .idle : .sleeping) }

    /// The model endpoint is filled in (demo data simulates one).
    var modelReady: Bool {
        MockMode.on || (settings.isConfigured && settings.currentModel != nil
            && (settings.provider == .others || !settings.apiKey.isEmpty))
    }

    /// iOS drops the video decoder when the app goes to the background and says so only at the next frame, which a
    /// still Home Screen never sends. During a run, rebuild it from the cached GOP shortly after leaving.
    private func refreshDecoderSoon() {
        guard !feed.isNative else { return }
        guard agent.running || startingAgent else { return }
        let transitionAt = now()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, self.agent.running || self.startingAgent else { return }
            await self.feed.refreshDecoder("app in background", afterTransition: transitionAt)
        }
    }

    func clearLog() { log.removeAll() }

    func say(_ text: String) {
        log = Array((log + [LogLine(text: text)]).suffix(200))
        DebugLog.write(text)
    }

    // MARK: - setup and diagnostics

    /// The one-tap join of the board's Wi-Fi (state machine in HotspotJoin.swift).
    @Published var join = JoinState.idle
    var joinTask: Task<Void, Never>?

    /// Set when one-tap join failed: the user joins in Settings with the shown password.
    @Published var manualHotspot: NetConfig?

    func bench(kb: Int = 256) async {
        do {
            let reply = try await board.commands.send("bench \(kb)")
            let ms = Double(reply.split(separator: " ").first ?? "") ?? 0
            metrics.benchKbps = ms > 0 ? Double(kb) * 8 * 1024 / ms : nil
            say(String(format: "BLE bench: %d KB in %.0f ms", kb, ms))
        } catch {
            say("bench: \(error.localizedDescription)")
        }
    }

    func snapTest() async {
        do { say(String(format: "snap -> decoded in %.0f ms", try await feed.snap())) } catch {
            say("snap: \(error.localizedDescription)")
        }
    }

    /// Shared by pull-to-refresh and character interactions; rapid pokes coalesce.
    func refreshHomeStatus() async {
        guard !refreshingStatus, now() - lastStatusRefresh > 2 else { return }
        refreshingStatus = true
        statusRefreshError = nil
        defer { refreshingStatus = false; lastStatusRefresh = now(); publishWidget() }
        do {
            try await board.refreshStatus()
            runs.reload()
            say("Home status refreshed")
        } catch is CancellationError {
            return
        } catch {
            statusRefreshError = error.localizedDescription
            say("Home status refresh: \(error.localizedDescription)")
        }
    }

    func pingLLM() async {
        guard modelTestStarted == nil else { return }
        if MockMode.on {
            try? await Task.sleep(nanoseconds: 900_000_000)
            modelOK = true
            return say("LLM ok (demo data)")
        }
        let started = now()
        let revision = settings.configurationRevision
        modelError = nil
        modelOK = nil
        modelTestSeconds = nil
        modelFirstTokenSeconds = nil
        modelResponseSeconds = nil
        modelTestStarted = Date()
        defer {
            modelTestStarted = nil
            if revision == settings.configurationRevision { modelTestSeconds = now() - started }
        }
        do {
            let client = try await settings.client("actor")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64)).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            }.jpegData(compressionQuality: 0.8)
            let r = try await client.chat(system: "Name the dominant color in the image. Reply with one English word.",
                                          text: "What color is this image?", image: image, maxTokens: 600, temperature: 0)
            guard revision == settings.configurationRevision else { return }
            modelFirstTokenSeconds = r.firstToken
            modelResponseSeconds = r.responseSeconds
            try ModelConnectionCheck.validate(r)
            metrics.llmPingMs = (now() - started) * 1000
            metrics.llm(first: r.firstToken, total: r.total)
            modelOK = true
            say(String(format: "LLM ok in %.0f ms: %@", metrics.llmPingMs ?? 0, String(r.text.prefix(40))))
        } catch {
            guard revision == settings.configurationRevision else { return }
            modelOK = false
            modelError = ModelRequestFailure.message(error)
            say("LLM: \(error.localizedDescription)")
        }
    }

    /// Ping the LLM every 2 s for `seconds` (switch to another app meanwhile) and report what survived.
    func backgroundTest(seconds: Double = 600) async {
        let id = UIApplication.shared.beginBackgroundTask(withName: "bgtest")
        defer { UIApplication.shared.endBackgroundTask(id) }
        guard let client = try? await settings.client("actor") else { return say("background test: no model") }
        let started = now()
        var ok = 0, failed = 0, decodedBefore = metrics.decodeErrors
        say("background test: \(Int(seconds)) s, switch to another app now")
        try? await feed.stream(true)
        while now() - started < seconds && !Task.isCancelled {
            do { _ = try await client.chat(system: "Reply with OK.", text: "ping", image: nil, maxTokens: 600, temperature: 0); ok += 1 }
            catch { failed += 1 }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        try? await feed.stream(false)
        decodedBefore = metrics.decodeErrors - decodedBefore
        say("background test: LLM \(ok) ok / \(failed) failed, decode errors \(decodedBefore), "
            + "suspensions \(metrics.suspensions), background alive \(Int(metrics.backgroundAlive)) s")
    }
}
