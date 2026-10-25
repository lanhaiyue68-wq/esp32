import UIKit

/// iOS keeps the pasteboard from an app in the background (since iOS 9: build 25 pasted what the user had copied, an
/// API key), so a reply goes onto it with Lan Agent in front for a moment. The swipe right along the home bar brings
/// Lan Agent back (it is the app used before WeChat), it fills the pasteboard and opens WeChat again, where the agent
/// pastes. Lan Agent never stays in front; nothing is pasted unless the pasteboard took this very text.
extension AppModel {
    func hopToPaste(_ text: String) async -> PasteHopResult {
        if UIApplication.shared.applicationState == .active { return Pasteboard.put(text) ? .filled : .refused }
        pasteHopping = true
        defer { pasteHopping = false }
        var front = false
        for attempt in 1...2 where !front {
            do { try await pointer.previousApp() } catch { return .lost }
            front = await waitForState(.active, within: 2.5)
            if !front { DebugLog.write("paste hop: Lan Agent did not come to the front (try \(attempt))") }
        }
        guard front else { return .lost }
        let filled = Pasteboard.put(text)
        guard let wechat = URL(string: "weixin://"), await UIApplication.shared.open(wechat),
              await waitForState(.background, within: 3) else {
            DebugLog.write("paste hop: WeChat did not come back")
            return .lost
        }
        try? await Task.sleep(nanoseconds: 600_000_000)  // WeChat redraws the chat
        DebugLog.write("paste hop: pasteboard \(filled ? "filled" : "refused"), back in WeChat")
        return filled ? .filled : .refused
    }

    /// WeChat to the front from wherever a task left the phone: Lan Agent first (the app switch back, as the paste's
    /// hop), then weixin://. `seesWeChat` ends it early when the switch back already landed in WeChat.
    func hopToWeChat(seesWeChat: () async -> Bool) async -> Bool {
        if UIApplication.shared.applicationState != .active {
            var front = false
            for _ in 1...2 where !front {
                do { try await pointer.previousApp() } catch { return false }
                front = await waitForState(.active, within: 2.5)
                if !front, await seesWeChat() { return true }
            }
            guard front else { return false }
        }
        guard let wechat = URL(string: "weixin://"), await UIApplication.shared.open(wechat),
              await waitForState(.background, within: 3) else { return false }
        try? await Task.sleep(nanoseconds: 600_000_000)  // WeChat redraws
        return true
    }

    private func waitForState(_ state: UIApplication.State, within seconds: Double) async -> Bool {
        let deadline = now() + seconds
        while UIApplication.shared.applicationState != state {
            if now() > deadline { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return true
    }
}
