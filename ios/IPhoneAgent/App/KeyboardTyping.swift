import Foundation
import UIKit

/// Phase B (specs/004): every reply, report and typed text goes through Lan Agent's keyboard, which puts it straight
/// into the focused field. Phase A on the phone (11-08): with the board attached, all three ways worked and the text
/// landed 0.4 s after the keyboard showed, where the paste hop took 15–40 s and often lost its way.
extension AppModel {
    /// The globe key under every keyboard on this iPhone, bottom left (logs 11-06/11-08 screenshots: 72,1218 of 592x1280).
    static let globeKey = CGPoint(x: 0.122, y: 0.952)

    /// Lan Agent's keyboard on screen for the focused field. Five globe clicks never brought it up (logs(9) 11-08);
    /// holding the globe key opens the keyboard menu (鍵盤設定…, 简体拼音, English (US), 表情符號, 繁體拼音, Lan Agent),
    /// where a click on "Lan Agent" picks it (user 11-08: a click on the globe shows no menu). Hold the globe once,
    /// then click "Lan Agent"; a menu already open is used as it is. Only while a system keyboard shows: without one, the globe's spot
    /// is the app's own control (WeChat's voice button), so nothing is tapped and the caller focuses the field first.
    func showLanAgentKeyboard(tries: Int = 3, appear: Double = 2.5) async -> Bool {
        if keyboardBridge.onScreen() { return true }
        // Live test 11-08: Search's keyboard came up after the opener's 0.8 s, "no keyboard on screen" was decided at
        // once, and "open 时钟" failed with 時鐘 ready to type. A keyboard (or its menu) gets `appear` s to show.
        let deadline = now() + appear
        while now() < deadline {
            if keyboardBridge.onScreen() { return true }
            if let frame = await freshFrame() {
                let rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.3, bottom: 1)
                if CandidatePicker.keyboardUp(in: frame) || CandidatePicker.keyboardMenuOpen(rows: rows) { break }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        for attempt in 1...tries {
            guard let frame = await freshFrame() else { return keyboardBridge.onScreen() }
            let rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.3, bottom: 1)
            if CandidatePicker.keyboardMenuOpen(rows: rows) { return await useKeyboardMenu(rows, attempt) }
            guard CandidatePicker.keyboardUp(in: frame) else {
                if keyboardBridge.onScreen() { return true }
                DebugLog.write("keyboard: no keyboard on screen to switch from")
                return false
            }
            do { try await pointer.longPress(Self.globeKey.x, Self.globeKey.y) } catch { return false }
            if await lanAgentKeyboardUp(within: 0.4) {
                DebugLog.write("keyboard: Lan Agent's keyboard on screen after holding the globe key (try \(attempt))")
                return true
            }
            guard let after = await freshFrame() else { continue }
            let menu = await CandidatePicker.rowsOffMain(in: after, top: 0.3, bottom: 1)
            if CandidatePicker.keyboardMenuOpen(rows: menu) { return await useKeyboardMenu(menu, attempt) }
            DebugLog.write("keyboard: no keyboard menu after holding the globe key (try \(attempt))")  // next try: in place
        }
        DebugLog.write("keyboard: Lan Agent's keyboard did not come up after \(tries) tries (is it added in Settings › Keyboards?)")
        return false
    }

    /// The keyboard menu is open: click "Lan Agent" in it. Without that row (not added, or not read), close the menu
    /// with the globe key once and let the caller fall back, never toggling it open and shut.
    private func useKeyboardMenu(_ rows: [[CandidatePicker.Piece]], _ attempt: Int) async -> Bool {
        guard let entry = CandidatePicker.keyboardMenuEntry(rows: rows) else {
            DebugLog.write("keyboard: the keyboard menu has no Lan Agent row (try \(attempt)); closing it")
            try? await pointer.tap(Self.globeKey.x, Self.globeKey.y)
            return false
        }
        do { try await pointer.tap(entry.x, entry.y) } catch { return false }
        let up = await lanAgentKeyboardUp(within: 4)  // first start of the keyboard: up only after ~2-10 s (logs(11))
        DebugLog.write("keyboard: picked Lan Agent in the keyboard menu (try \(attempt)): \(up ? "on screen" : "not reported")")
        return up
    }

    private func lanAgentKeyboardUp(within seconds: Double) async -> Bool {
        let deadline = now() + seconds
        while now() < deadline {
            if keyboardBridge.onScreen() { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return keyboardBridge.onScreen()
    }

    /// `text` into the focused field by Lan Agent's keyboard; false when the keyboard could not be shown or did not
    /// confirm, and the caller falls back to the old ways (pinyin, paste).
    func typeWithLanAgentKeyboard(_ text: String, enter: Bool = false) async -> Bool {
        guard await showLanAgentKeyboard() else { return false }
        let ok = await keyboardBridge.type(text, enter: enter, within: 4)
        DebugLog.write("keyboard: \(text.count) character(s) \(ok ? "typed" : "not confirmed")")
        // The field takes the text a moment after the keyboard reports it: the board's Return 0.16 s later did not
        // send (logs(11) 11-08); the same Return 9 s later did.
        if ok { try? await Task.sleep(nanoseconds: 600_000_000) }
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
