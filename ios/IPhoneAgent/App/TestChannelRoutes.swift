import Foundation
import UIKit

/// What the USB test channel (TestChannel) can ask of the app: tasks like the Home screen's, gestures like the agent's,
/// the board's own commands, and the screen as the app sees it.
extension AppModel {
    func answerTestChannel(_ request: TestChannel.Request) async -> TestChannel.Response {
        // The channel must outlive a run: without the audio iOS suspends the app, and the channel with it, when one ends.
        if !keepAwake.hold {
            keepAwake.hold = true
            keepAwake.start()
            DebugLog.write("test channel: in use; background audio held on")
        }
        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        func number(_ key: String) -> Double { (body[key] as? NSNumber)?.doubleValue ?? 0 }
        func text(_ key: String) -> String { body[key] as? String ?? "" }
        if request.method == "POST" { DebugLog.write("test channel: \(request.path) \(text("do"))") }

        switch (request.method, request.path) {
        case ("GET", "/status"):
            return .json(testChannelStatus())

        case ("GET", "/frame"):
            guard let frame = feed.frame else { return .json(["error": .str("no frame: is the whole screen shared?")], status: 404) }
            return .init(status: 200, type: "image/jpeg", body: frame)

        case ("GET", "/ocr"):
            guard let frame = feed.frame else { return .json(["error": .str("no frame")], status: 404) }
            let read = await CandidatePicker.rowsOffMain(in: frame, top: 0.02, bottom: 1)
            let keyboard = await CandidatePicker.keyboardUpOffMain(in: frame)
            let rows = read.map { row in
                JValue.arr(row.map { .str(String(format: "%@ @%.3f,%.3f %.3fx%.3f", $0.text, $0.box.midX, $0.box.midY, $0.box.width, $0.box.height)) })
            }
            return .json(["rows": .arr(rows), "home": .bool(AppPlaces.looksLikeHome(read)),
                          "search": .bool(AppPlaces.inSearch(read)),
                          "keyboard": .bool(keyboard)])

        case ("GET", "/steps"):
            let from = Int(request.query["from"] ?? "") ?? 0
            let steps = agent.steps.dropFirst(max(0, from)).map { JValue.obj($0) }
            return .json(["count": .int(agent.steps.count), "steps": .arr(Array(steps))])

        case ("POST", "/run"):
            let task = text("task")
            guard !task.isEmpty else { return .json(["error": .str("no task")], status: 400) }
            guard !agent.running, !startingAgent else { return .json(["error": .str("a run is on")], status: 409) }
            let hints = body["hints"] as? [String]
            Task { [weak self] in await self?.run(task, hints: hints) }
            return .json(["started": .bool(true)])

        case ("POST", "/stop"):
            await stopAgent()
            return .json(["stopped": .bool(true)])

        case ("POST", "/share"):
            if !feed.restartCapture() { feed.startNativeSharing() }
            return .json(["status": .str(feed.nativeStatus)])

        case ("POST", "/servers"):
            // 169 (user 11-25: "做測試，把那個服務器地址填一下"): the order servers set from the computer over USB, e.g.
            // the mock servers on it. Only the keys given change; restart the watch to use them.
            let d = UserDefaults.standard
            for (key, field) in [(WatchSettings.serverURLKey, "serverURL"), (WatchSettings.robotKey, "robot"),
                                 (WatchSettings.weworkURLKey, "weworkURL"), (WatchSettings.weworkCodeKey, "weworkCode")]
            where body[field] is String {
                d.set(text(field), forKey: key)
            }
            for (key, field) in [(WatchSettings.serverOnKey, "serverOn"), (WatchSettings.weworkOnKey, "weworkOn")] {
                if let on = body[field] as? Bool { d.set(on, forKey: key) }
            }
            return .json(["serverOn": .bool(WatchSettings.serverOn), "serverURL": .str(WatchSettings.serverURL),
                          "robot": .str(WatchSettings.robotId), "weworkOn": .bool(WatchSettings.weworkOn),
                          "weworkURL": .str(WatchSettings.weworkURL), "weworkCode": .str(WatchSettings.weworkCode)])

        case ("POST", "/padstep"):
            // 171: try another iPad pace (counts a report, 2…127; 0 back to the default) without a new build; recalibrate
            // after. 174: "pace" (ms a report, v37 boards; 0 back to the default) and "ratio" (slow units a fast one).
            UserDefaults.standard.set(Int(number("n")), forKey: CommandChannel.padStepKey)
            if body["pace"] != nil { UserDefaults.standard.set(Int(number("pace")), forKey: CommandChannel.padPaceKey) }
            if number("ratio") > 0 { CommandChannel.padSlowRatio = number("ratio") }
            return .json(["padStep": .num(Double(CommandChannel.padStep)), "pace": .num(Double(CommandChannel.padPaceMs)),
                          "slowRatio": .num(CommandChannel.padSlowRatio)])

        case ("POST", "/calibrate"):
            // 171: the Calibrate button, from the computer (it moves the iPad's pointer: only with the user there).
            calibrator.calibrate(why: "test channel")
            return .json(["started": .bool(true)])

        case ("POST", "/watch"):
            if body["on"] as? Bool == true {
                if let problem = startWatch() { return .json(["error": .str(problem)], status: 409) }
            } else {
                stopWatch("test channel")
            }
            return .json(["watching": .bool(watching)])

        case ("POST", "/tapfast"):
            // Test 11-12: the first stop inside the target is clicked without correcting (Pointer.aimLoosely), on or off,
            // so one build can be compared with itself.
            let on = body["on"] as? Bool ?? true
            UserDefaults.standard.set(on, forKey: "tapTargetToleranceV1")
            return .json(["tapfast": .bool(on)])

        case ("POST", "/hot"):
            // Test only: the phone counts as critical-hot, so the cloud's next task is put off (retry_pending, device_hot).
            if body["on"] as? Bool == true { cloud.hot = { true } } else { cloud.hot = { ProcessInfo.processInfo.thermalState == .critical } }
            DebugLog.write("test channel: hot \(body["on"] as? Bool == true ? "on" : "off")")
            return .json(["hot": .bool(cloud.hot())])

        case ("POST", "/lead"):
            // 193: the lead model set from the computer ({"lead":"codex"|"doubao"}), as the settings page does
            // 197: {"planner":"codex"|"doubao"} sets the planning order's lead on its own
            if let lead = LeadModel(rawValue: text("lead")) { LeadModel.current = lead }
            if let planner = LeadModel(rawValue: text("planner")) { LeadModel.planner = planner }
            return .json(["lead": .str(LeadModel.current.rawValue), "planner": .str(LeadModel.planner.rawValue)])

        case ("POST", "/media"):
            // 188: reading voice notes, videos, pictures, files and links, tried by hand: "set" turns kinds (and "quote")
            // on or off; "read" opens one kind on the chat open on `side` and says what was seen; "quote" long-presses
            // the line `text` and clicks 引用 (nothing typed or sent). Either of the last two only with the watch off.
            switch text("do") {
            case "set":
                for k in XiaoLanMediaFind.Kind.allCases { if let on = body[k.rawValue] as? Bool { MediaSettings.set(k, on) } }
                if let on = body["quote"] as? Bool { MediaSettings.quoteOn = on }
            case "read", "quote":
                #if XIAOLAN
                guard !watching else { return .json(["error": .str("the watch is on: turn it off first")], status: 409) }
                if text("do") == "quote" {
                    let quoted = await paneQuoteTest(side: Int(number("side")), quote: text("text"))
                    return .json(["quoted": .bool(quoted)])
                }
                guard let kind = XiaoLanMediaFind.Kind(rawValue: text("kind")) else {
                    return .json(["error": .str("kind: voice, video, image, file or link")], status: 400)
                }
                let got = await paneMediaTest(side: Int(number("side")), kind: kind, text: text("text"))
                return .json(["seen": got.seen.map { JValue.str($0) } ?? .null, "why": got.why.map { JValue.str($0) } ?? .null])
                #else
                return .json(["error": .str("小藍 only")], status: 404)
                #endif
            default:
                break
            }
            var flags: JObject = ["quote": .bool(MediaSettings.quoteOn)]
            for k in XiaoLanMediaFind.Kind.allCases { flags[k.rawValue] = .bool(MediaSettings.on(k)) }
            return .json(flags)

        case ("GET", "/spots"), ("POST", "/spots"):
            // 188: the places of WeChat's and WeCom's buttons learned on this device (XiaoLanSpots); {"reset":true}
            // forgets them, so they are found again (another device, the windows' widths changed).
            if body["reset"] as? Bool == true { XiaoLanSpots.reset() }
            var spots: JObject = [:]
            for (k, v) in XiaoLanSpots.learnedAll().sorted(by: { $0.key < $1.key }) { spots[k] = .arr(v.map { JValue.num($0) }) }
            return .json(["device": .str(XiaoLanSpots.deviceModel), "learned": .obj(spots)])

        case ("POST", "/release"):
            keepAwake.hold = false
            if !agent.running, !startingAgent, !watching { keepAwake.stop() }
            return .json(["released": .bool(true)])

        case ("POST", "/board"):
            DeviceLock.hand()  // 199: a hand on the board: the watch parks between its steps first
            for _ in 0..<40 where watching && !DeviceLock.parked { try? await Task.sleep(nanoseconds: 200_000_000) }
            do { return .json(["reply": .str(try await board.commands.send(text("cmd")))]) }
            catch { return .json(["error": .str(error.localizedDescription)], status: 500) }

        case ("GET", "/reads"):
            // 202: what 爬樓 and 跟圈 read and kept (ReadStore), newest first
            return .json(["lines": .arr(ReadStore.lines(300).map { JValue.str($0) })])

        case ("GET", "/ledger"):
            // 199: the 发送账 (OrderLedger), newest first
            return .json(["lines": .arr(OrderLedger.lines(200).map { JValue.str($0) })])

        case ("POST", "/gesture"):
            DeviceLock.hand()  // 199 (Echo 198 11-28 17:58: a tap by hand raced the watch's own): the watch parks first
            for _ in 0..<40 where watching && !DeviceLock.parked { try? await Task.sleep(nanoseconds: 200_000_000) }
            let began = now()
            do {
                var reply: JObject = [:]
                pointer.lastArrival = nil
                switch text("do") {
                case "tap": try await pointer.tap(number("x"), number("y"), aim: body["aim"] as? Bool ?? false)
                case "longpress": try await pointer.longPress(number("x"), number("y"), seconds: body["seconds"] == nil ? 0.8 : number("seconds"))
                case "swipe": try await pointer.swipe(number("x1"), number("y1"), number("x2"), number("y2"), hold: false)
                case "home": try await pointer.goHome()
                case "key": try await pointer.key(text("combo"))
                case "type": reply["typed"] = .bool(await typeWithLanAgentKeyboard(text("text"), enter: body["enter"] as? Bool ?? false))
                case "keyboard": reply["up"] = .bool(await showLanAgentKeyboard())
                case "open": reply["opened"] = .bool(try await openApp(text("app")))
                case "voicetest":
                    // SPIKE 157 (throwaway, see VoiceProbe): hold WeChat's 按住说话 while the clip plays; the release sends it.
                    let mode = text("mode")
                    try await pointer.longPress(number("x"), number("y"), seconds: 1.0) { await VoiceProbe.play(mode: mode) }
                    reply["played_s"] = .num(VoiceProbe.lastPlayed)
                    reply["route"] = .str(VoiceProbe.lastRoute)
                    if mode == "speaker" { _ = keepAwake.start() }  // the category went back to .playback; the silence goes on
                default: return .json(["error": .str("unknown gesture")], status: 400)
                }
                reply["ms"] = .int(Int((now() - began) * 1000))
                if let seen = pointer.lastArrival { reply["eye"] = .str("\(seen)") }
                return .json(reply)
            } catch {
                return .json(["error": .str(error.localizedDescription)], status: 500)
            }

        default:
            return .json(["error": .str("no such route")], status: 404)
        }
    }

    private func testChannelStatus() -> JObject {
        var status: JObject = [
            "build": .str(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"),
            "running": .bool(agent.running),
            "starting": .bool(startingAgent),
            "task": .str(agent.task),
            "steps": .int(agent.steps.count),
            "plan": .str(String(agent.plan.prefix(400))),
            "board": .bool(board.commands.connected),
            "sharing": .bool(feed.sharingActive),
            "watchable": .bool(feed.watchable),
            "capture": .str(feed.nativeStatus),
            "watching": .bool(watching),
            "calibrated": .bool(pointer.calibrated),
            "planner": .str(PlusRest.summaryAll),
            "foreground": .bool(UIApplication.shared.applicationState == .active),
            "keyboard": .bool(keyboardBridge.onScreen()),
            "takeover": .int(agent.takeover),
            "lead": .str(LeadModel.current.rawValue),  // 193
            "planner_lead": .str(LeadModel.planner.rawValue),  // 197
        ]
        if feed.updated > 0 { status["frame_age_s"] = .num(((now() - feed.updated) * 10).rounded() / 10) }
        if let last = agent.steps.last { status["last"] = .obj(last) }
        return status
    }
}
