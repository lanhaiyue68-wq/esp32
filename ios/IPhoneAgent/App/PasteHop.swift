import UIKit

/// iOS keeps the pasteboard from an app in the background (since iOS 9: build 25 pasted what the user had copied, an
/// API key), so text goes onto it with Lan Agent in front for a moment. Reverse the app switches and verify the
/// original target screen before allowing a paste there.
extension AppModel {
    func hopToPaste(_ text: String) async -> PasteHopResult {
        guard UIApplication.shared.applicationState == .background else { return .lost }
        // The caller may just have cleared a failed Pinyin attempt. A merely recent frame can still contain that
        // temporary text, which made the same chat look different after returning from Lan Agent (logs33).
        let sourceAt = now()
        await feed.afterAction(since: sourceAt)
        do { try await feed.requireFrame(after: sourceAt) } catch {
            DebugLog.write("paste hop: source frame freshness unverified")
            return .lost
        }
        guard let source = feed.frame, Vision.image(source) != nil else { return .lost }
        agent.trace?.write(source, kind: "paste target", ["stage": .str("source")])
        pasteHopping = true
        defer { pasteHopping = false }
        var returnedAt = now()
        // A watched WeChat chat (its title read on this phone) is reopened by WeChat's URL scheme, which brings back the
        // same chat. Reversed swipes depend on the app order: with Claude used last they stopped in Claude, the check
        // refused, and the reply fell to a 65 s model run that failed the same way (logs 11-06, build89).
        var reopen: (() async throws -> Void)?
        let sourceChat = WatchReport.navigationChat(in: source, targets: WatchSettings.rules.targets)
        if sourceChat != nil {
            reopen = {
                guard let url = URL(string: "weixin://"), await UIApplication.shared.open(url) else {
                    throw DeviceError(message: "WeChat did not open")
                }
                returnedAt = now()
                guard await self.waitForState(.background, within: 3) else {
                    throw DeviceError(message: "paste hop did not leave Lan Agent")
                }
                try await Task.sleep(nanoseconds: 600_000_000)  // WeChat redraws
            }
        }
        let result = await PasteRoundTrip.perform(text, isActive: {
            UIApplication.shared.applicationState == .active
        }, previousApp: {
            try await self.pointer.previousApp()
        }, nextApp: {
            try await self.pointer.nextApp()
            returnedAt = now()
            if !(await self.waitForState(.background, within: 3)) {
                // After a few seconds in the app reached, iOS moves it to the front of the app order: the original app
                // is then behind Lan Agent and the reverse swipe does nothing (logs 11-06: 8 s in Lan Agent, stuck).
                // The forward swipe reaches it; the source check below still decides whether it is the right screen.
                DebugLog.write("paste hop: reverse swipe stayed in Lan Agent; swiping the other way")
                try await self.pointer.previousApp()
                returnedAt = now()
                guard await self.waitForState(.background, within: 3) else {
                    throw DeviceError(message: "paste hop did not leave Lan Agent")
                }
            }
            try await Task.sleep(nanoseconds: 600_000_000)
        }, waitForAgent: {
            await self.waitForState(.active, within: 2.5)
        }, put: { Pasteboard.put($0) }, verifySource: {
            // WeChat's banners for other chats cover the title for a few seconds (logs 11-06: 2 of 4 hops refused the
            // right chat). Look again 2 and 4 s later; every look is a fresh frame held to the same strict match.
            for attempt in 0..<3 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                let since = attempt == 0 ? returnedAt : now()
                await self.feed.afterAction(since: since)
                do { try await self.feed.requireFrame(after: since) } catch {
                    DebugLog.write("paste hop: return frame freshness unverified")
                    return false
                }
                guard !Task.isCancelled, UIApplication.shared.applicationState == .background,
                      let returned = self.feed.frame else { return false }
                // Reopened WeChat: the same watched chat by its title is the destination even when the keyboard went
                // down and the messages moved (logs 11-06: 2 of 5 URL returns refused by the content match).
                let byTitle = sourceChat != nil
                    && WatchReport.navigationChat(in: returned, targets: WatchSettings.rules.targets) == sourceChat
                let matched = byTitle || PasteRoundTrip.matchesSource(source, returned)
                self.agent.trace?.write(returned, kind: "paste target",
                                        ["stage": .str("return"), "matched": .bool(matched), "look": .int(attempt + 1)])
                if matched {
                    if byTitle, !CandidatePicker.keyboardUp(in: returned), !self.keyboardBridge.onScreen() {  // ours shows no letter keys
                        DebugLog.write("paste hop: back in \(sourceChat ?? "") without the keyboard; tapping the input box")
                        try? await self.pointer.tap(0.45, 0.925)  // WeChat's box above the home bar
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    }
                    return true
                }
            }
            return false
        }, reopenSource: reopen, openAgent: sourceChat == nil ? nil : {
            try await self.openLanAgentBySearch()
        })
        DebugLog.write("paste hop: \(result), original target \(result == .lost ? "unverified" : "verified")"
                       + (reopen == nil ? "" : " (WeChat reopened by its URL)"))
        return result
    }

    /// Lan Agent to the front whatever the app order: Home, swipe down on the Home Screen for Search, type its name
    /// (plain letters, which the board's keyboard types), Return opens the top hit.
    func openLanAgentBySearch() async throws {
        try await pointer.goHome()
        try await Task.sleep(nanoseconds: 800_000_000)
        try await pointer.swipe(0.5, 0.32, 0.5, 0.62, hold: false)
        try await Task.sleep(nanoseconds: 900_000_000)
        try await pointer.type("Lan Agent")
        try await Task.sleep(nanoseconds: 700_000_000)
        try await pointer.key("enter")
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
            if Task.isCancelled || now() > deadline { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !Task.isCancelled
    }
}
