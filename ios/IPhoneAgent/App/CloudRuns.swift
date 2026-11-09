import Combine
import Foundation
import UIKit

/// The cloud's tasks go to the same agent as a task typed on the phone (customer spec 11-10, §6.2: reuse the entry the
/// app already has). What the phone can do is said item by item, never inferred from being online (§4.4).
extension AppModel {
    func connectCloud() {
        cloud.capabilities = { [weak self] in self?.cloudCapabilities() ?? [:] }
        cloud.running = { [weak self] in (self?.agent.running ?? false) || (self?.startingAgent ?? false) }
        cloud.start = { [weak self] task, approve in
            guard let self else { return }
            Task { await self.run(task.instruction, approveSend: task.approval ? approve : nil) }
        }
        cloud.outcome = { [weak self] task in
            guard let self, self.agent.task == task.instruction else {
                return CloudBridge.Outcome(status: "failed", answer: "", error: "did_not_start", steps: 0)
            }
            return CloudBridge.outcome(of: self.agent.steps)
        }
        cloud.stop = { [weak self] in await self?.stopAgent() }
        cloud.lastScreen = { [weak self] in self?.feed.frame }
        // Turned on later: the app must keep living in the background to hear the cloud.
        cloudSink = cloud.$enabled.sink { [weak self] on in
            guard on, let self else { return }
            self.keepAwake.hold = true
            self.keepAwake.start()
        }
        Task { [weak self] in await self?.cloud.loop() }
    }

    /// available / unavailable / unknown, each on its own.
    func cloudCapabilities() -> [String: String] {
        func say(_ ok: Bool?) -> String { ok.map { $0 ? "available" : "unavailable" } ?? "unknown" }
        let fresh = feed.updated > 0 ? now() - feed.updated < 10 : nil
        return [
            "screen_capture": say(feed.sharingActive ? (fresh ?? false) : false),
            "hid_board": say(board.commands.connected),
            "pointer": say(pointer.calibrated),
            "model": say(settings.isConfigured),
            "app_foreground": say(UIApplication.shared.applicationState == .active),
            "agent": agent.running || startingAgent ? "busy" : "idle",
        ]
    }
}
