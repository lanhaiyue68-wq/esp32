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

        case ("POST", "/watch"):
            if body["on"] as? Bool == true {
                if let problem = startWatch() { return .json(["error": .str(problem)], status: 409) }
            } else {
                stopWatch("test channel")
            }
            return .json(["watching": .bool(watching)])

        case ("POST", "/release"):
            keepAwake.hold = false
            if !agent.running, !startingAgent, !watching { keepAwake.stop() }
            return .json(["released": .bool(true)])

        case ("POST", "/board"):
            do { return .json(["reply": .str(try await board.commands.send(text("cmd")))]) }
            catch { return .json(["error": .str(error.localizedDescription)], status: 500) }

        case ("POST", "/gesture"):
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
            "planner": .str(PlusRest.shared.summary),
            "foreground": .bool(UIApplication.shared.applicationState == .active),
            "keyboard": .bool(keyboardBridge.onScreen()),
            "takeover": .int(agent.takeover),
        ]
        if feed.updated > 0 { status["frame_age_s"] = .num(((now() - feed.updated) * 10).rounded() / 10) }
        if let last = agent.steps.last { status["last"] = .obj(last) }
        return status
    }
}
