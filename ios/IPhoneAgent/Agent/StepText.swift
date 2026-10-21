import Foundation

/// Human words for a recorded step, for the replay player, the Live Activity and Home.
enum StepText {
    static func title(_ s: JObject) -> String {
        let n = { (k: String) in s[k]?.int ?? Int(s[k]?.double ?? 0) }
        switch s["action"]?.str {
        case "plan": return String(localized: "Made a plan")
        case "replan (stuck)", "replan": return String(localized: "Made a new plan")
        case "tap": return String(localized: "Tap at \(n("x")), \(n("y"))")
        case "swipe": return String(localized: "Swipe")
        case "path": return String(localized: "Draw a path")
        case "circle": return String(localized: "Draw a circle")
        case "type": return String(localized: "Type “\(s["text"]?.str ?? "")”")
        case "key": return String(localized: "Press \(s["combo"]?.str ?? "")")
        case "home": return String(localized: "Go to the Home Screen")
        case "back": return String(localized: "Go back")
        case "wait": return String(localized: "Wait")
        case "done": return String(localized: "Done")
        case "done rejected": return String(localized: "Not done yet")
        case "fail": return String(localized: "Gave up")
        case "stopped": return String(localized: "Stopped")
        case "hiccup": return String(localized: "Hiccup, retrying")
        case "reconnected": return String(localized: "Reconnected")
        case "error": return String(localized: "Error")
        case "help": return String(localized: "Asked for your help")
        case "takeover": return String(localized: "You took over")
        case "skipped": return String(localized: "Skipped")
        case "note": return String(localized: "Note")
        default: return s["action"]?.str ?? ""
        }
    }

    /// The model's own words if it gave any, else the action.
    static func line(_ s: JObject) -> String {
        if let t = s["thought"]?.str, !t.isEmpty { return t }
        if let a = s["answer"]?.str ?? s["reason"]?.str.map(userReason), !a.isEmpty { return "\(title(s)): \(a)" }
        return title(s)
    }

    /// What the user reads for a reason (help, notifications, the Live Activity): the agent's own English
    /// diagnostics become plain words in the app's language. The trace keeps the original. Anything else (the
    /// model's own words, recovery reasons that are localized already) is shown as it is.
    static func userReason(_ reason: String) -> String {
        let blind = ["lost the phone screen", "screen freshness could not be verified", "board replied but no verified",
                     "snapshot did not decode"]
        if blind.contains(where: { reason.hasPrefix($0) }) {
            return String(localized: "I can't see the iPhone screen clearly. Check Screen Mirroring; if it keeps happening, stop it in Control Center and select ESP32 again.")
        }
        if reason.hasPrefix("claimed done 3 times") {
            return String(localized: "It said it was done three times without doing it in this run. Look at the screen, then go on or stop.")
        }
        if reason.hasSuffix(" errors in a row"), let n = Int(reason.prefix { $0.isNumber }) {
            return String(localized: "Went wrong \(n) times in a row.")
        }
        if reason == "step limit reached" { return String(localized: "Reached the step limit.") }
        return reason
    }

    static func symbol(_ name: String?) -> String {
        switch name {
        case "plan", "replan (stuck)": return "list.bullet.clipboard"
        case "tap": return "hand.tap"
        case "swipe", "path", "circle": return "hand.draw"
        case "type": return "keyboard"
        case "key": return "command"
        case "home": return "house"
        case "back": return "chevron.backward"
        case "wait": return "hourglass"
        case "done": return "checkmark.circle.fill"
        case "stopped": return "stop.circle"
        case "help", "takeover": return "hand.raised"
        case "skipped": return "forward"
        case "note": return "text.bubble"
        case "reconnected": return "arrow.triangle.2.circlepath"
        default: return "exclamationmark.triangle"
        }
    }

    static let notMoves: Set<String> = ["plan", "replan (stuck)", "hiccup", "stopped", "error", "fail", "done", "help",
                                        "takeover", "skipped", "note", "reconnected", "done rejected"]
}

/// How a run ended.
enum Outcome {
    case running, done, failed, stopped

    init(last: String?, running: Bool) {
        if running { self = .running; return }
        switch last {
        case "done": self = .done
        case "stopped": self = .stopped
        default: self = .failed
        }
    }

    var mood: Mood {
        switch self {
        case .running: return .thinking
        case .done: return .success
        case .failed: return .failure
        case .stopped: return .idle
        }
    }
}
