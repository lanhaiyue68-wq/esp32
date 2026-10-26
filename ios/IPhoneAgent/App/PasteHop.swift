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
        let result = await PasteRoundTrip.perform(text, isActive: {
            UIApplication.shared.applicationState == .active
        }, previousApp: {
            try await self.pointer.previousApp()
        }, nextApp: {
            try await self.pointer.nextApp()
            returnedAt = now()
            guard await self.waitForState(.background, within: 3) else {
                throw DeviceError(message: "paste hop did not leave Lan Agent")
            }
            try await Task.sleep(nanoseconds: 600_000_000)
        }, waitForAgent: {
            await self.waitForState(.active, within: 2.5)
        }, put: { Pasteboard.put($0) }, verifySource: {
            await self.feed.afterAction(since: returnedAt)
            do { try await self.feed.requireFrame(after: returnedAt) } catch {
                DebugLog.write("paste hop: return frame freshness unverified")
                return false
            }
            guard UIApplication.shared.applicationState == .background, let returned = self.feed.frame else { return false }
            let matched = PasteRoundTrip.matchesSource(source, returned)
            self.agent.trace?.write(returned, kind: "paste target", ["stage": .str("return"), "matched": .bool(matched)])
            return matched
        })
        DebugLog.write("paste hop: \(result), original target \(result == .lost ? "unverified" : "verified")")
        return result
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
