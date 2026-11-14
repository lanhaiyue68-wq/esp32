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
            // User 11-15: an app the task needs and the phone lacks is asked about through the cloud (install_app).
            let install: (String) async -> Bool? = { [weak self] app in await self?.cloud.askInstall(app, for: task.id) }
            Task { await self.run(task.instruction, approveSend: task.approval ? approve : nil, askHelp: false, askInstall: install) }
        }
        cloud.outcome = { [weak self] task in
            guard let self, self.agent.task == task.instruction else {
                return CloudBridge.Outcome(status: "failed", answer: CloudBridge.said(false, "任务没有开始"), error: "did_not_start", steps: 0)
            }
            return CloudBridge.outcome(of: self.agent.steps)
        }
        cloud.stop = { [weak self] in await self?.stopAgent() }
        cloud.destination = { [weak self] in self?.agent.approvalPlace }
        cloud.mask = { await ShotPrivacy.masked($0) }
        // The screen the run finished on, not the Home Screen it goes back to after (11-10: half of each picture was Home).
        cloud.lastScreen = { [weak self] in
            guard let self else { return nil }
            return self.agent.shots.keys.max().flatMap { self.agent.shots[$0] } ?? self.feed.frame
        }
        // Turned on later: the app must keep living in the background to hear the cloud.
        cloudSink = cloud.$enabled.sink { [weak self] on in
            guard on, let self else { return }
            self.keepAwake.hold = true
            self.keepAwake.start()
            // Build 121, 11-11: speech recognition was asked for only when a watch started, so a phone that only takes
            // cloud tasks never heard a video's words (listen gave subtitles alone). Asked here too, with the app in front.
            Task { @MainActor in ScreenListener.authorize() }
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
            "thermal": ["nominal", "fair", "serious", "critical"][min(3, ProcessInfo.processInfo.thermalState.rawValue)],
        ]
    }
}
