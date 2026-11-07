import Foundation
import UIKit

/// Phase B (specs/004): every reply, report and typed text goes through Lan Agent's keyboard, which puts it straight
/// into the focused field. Phase A on the phone (11-08): with the board attached, all three ways worked and the text
/// landed 0.4 s after the keyboard showed, where the paste hop took 15–40 s and often lost its way.
extension AppModel {
    /// The globe key under every keyboard on this iPhone, bottom left (logs 11-06/11-08 screenshots: 72,1218 of 592x1280).
    static let globeKey = CGPoint(x: 0.122, y: 0.952)

    /// Lan Agent's keyboard on screen for the focused field: the globe key cycles keyboards until it reports in, at
    /// most `taps` times. Only while a system keyboard shows: without one, the globe's spot is the app's own control
    /// (WeChat's voice button), so nothing is tapped and the caller focuses the field first.
    func showLanAgentKeyboard(taps: Int = 5) async -> Bool {
        if keyboardBridge.onScreen() { return true }
        for attempt in 1...taps {
            guard let frame = await freshFrame(), CandidatePicker.keyboardUp(in: frame) else {
                if keyboardBridge.onScreen() { return true }
                DebugLog.write("keyboard: no keyboard on screen to switch from")
                return false
            }
            do { try await pointer.tap(Self.globeKey.x, Self.globeKey.y) } catch { return false }
            let deadline = now() + 1.4
            while now() < deadline {
                if keyboardBridge.onScreen() {
                    DebugLog.write("keyboard: Lan Agent's keyboard on screen after \(attempt) globe tap(s)")
                    return true
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        DebugLog.write("keyboard: Lan Agent's keyboard did not come up after \(taps) globe taps (is it added in Settings › Keyboards?)")
        return false
    }

    /// `text` into the focused field by Lan Agent's keyboard; false when the keyboard could not be shown or did not
    /// confirm, and the caller falls back to the old ways (pinyin, paste).
    func typeWithLanAgentKeyboard(_ text: String) async -> Bool {
        guard await showLanAgentKeyboard() else { return false }
        let ok = await keyboardBridge.type(text, enter: false, within: 4)
        DebugLog.write("keyboard: \(text.count) character(s) \(ok ? "typed" : "not confirmed")")
        return ok
    }

    /// A frame captured after this moment (the screen as it is now).
    func freshFrame() async -> Data? {
        let since = now()
        try? await Task.sleep(nanoseconds: 250_000_000)
        await feed.afterAction(since: since)
        return feed.frame
    }
}
