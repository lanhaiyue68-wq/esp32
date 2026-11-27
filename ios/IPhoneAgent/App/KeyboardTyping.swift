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
        // D84, y5 on 138 (item 43): iOS held Lan Agent for 5–8 s at a time (y6: 63 times in 43 minutes, thermal serious),
        // so Lan Agent's keyboard, on screen, got no answer and said "連不上 Lan Agent"; it was not taken for a keyboard,
        // the text went in as pinyin (猫 came out 毛), and Codex read "連不上" and gave the item up. Our keyboard on
        // screen gets 8 s to ask again before anything else is tried.
        if let frame = await freshFrame(),
           CandidatePicker.ourKeyboardShown(rows: await CandidatePicker.rowsOffMain(in: frame, top: 0.55, bottom: 1)) {
            if await lanAgentKeyboardUp(within: 8) {
                DebugLog.write("keyboard: Lan Agent's keyboard was on screen and asked again")
                return true
            }
            DebugLog.write("keyboard: Lan Agent's keyboard is on screen and did not ask for 8 s")
        }
        // Live test 11-08: Search's keyboard came up after the opener's 0.8 s, "no keyboard on screen" was decided at
        // once, and "open 时钟" failed with 時鐘 ready to type. A keyboard (or its menu) gets `appear` s to show.
        let deadline = now() + appear
        while now() < deadline {
            if keyboardBridge.onScreen() { return true }
            if let frame = await freshFrame() {
                let rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.3, bottom: 1)
                if CandidatePicker.keyboardUp(in: frame) || CandidatePicker.keyboardMenuOpen(rows: rows)
                    || XiaoLanPanes.keyboardTop(rows) != nil { break }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        for attempt in 1...tries {
            guard let frame = await freshFrame() else { return keyboardBridge.onScreen() }
            let rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.3, bottom: 1)
            if CandidatePicker.keyboardMenuOpen(rows: rows) { return await useKeyboardMenu(rows, attempt) }
            // 187 (B35, Echo 186, 11-26: the iPad's 简体拼音 — keys read "1 q", a ".?123" key, a row of candidates over
            // it — was on screen and "no keyboard on screen to switch from" three times): its keys as the chat windows tell
            // them (one Latin letter with the digit over it, or a row of digits) count too.
            guard CandidatePicker.keyboardUp(in: frame) || XiaoLanPanes.keyboardTop(rows) != nil else {
                if keyboardBridge.onScreen() { return true }
                DebugLog.write("keyboard: no keyboard on screen to switch from")
                return false
            }
            if await dockInTheWay() { return false }  // 189 (N14)
            // 184 (Echo 183, 11-26, iPad: from 简体拼音 one click on the globe went straight to 小藍, twice; held, the
            // globe's menu was missed once and its 小藍 row clicked at an estimate the next time): on an iPad the globe is
            // clicked first, up to three times round the keyboards, 小藍 looked for after each; the menu after that.
            if attempt == 1, CommandChannel.onPad() {
                for click in 1...3 {
                    do { try await pointer.tap(Self.globeKey.x, Self.globeKey.y) } catch { break }
                    if await lanAgentKeyboardUp(within: 1.2) {
                        DebugLog.write("keyboard: Lan Agent's keyboard on screen after \(click) globe click(s)")
                        return true
                    }
                }
                DebugLog.write("keyboard: three globe clicks did not bring Lan Agent's keyboard; its menu next")
                continue
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

    /// 189 (N14, Echo 188 night, 11-27: after a trip to Safari the Dock stayed up at the screen's bottom, and the globe key
    /// was clicked at its estimate (0.122, 0.952) three times, in the Dock's row; the keyboard over it took the clicks, but
    /// an icon there would have opened another app over the windows): the Dock's icons in view (not under a keyboard),
    /// the pointer goes up out of its way first (no click); the Dock still in view, the globe key is not clicked.
    private func dockInTheWay() async -> Bool {
        guard CommandChannel.onPad(), let frame = await freshFrame(), let px = WatchOCR.Pixels(frame) else { return false }
        let icons = XiaoLanRecall.dockIcons(px)
        guard icons.wechat != nil || icons.wework != nil else { return false }
        DebugLog.write("keyboard: the Dock is up at the screen's bottom; the pointer up out of its way before the globe key")
        try? await pointer.point(0.5, 0.45, aim: false, rehome: false)
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard let again = await freshFrame(), let px2 = WatchOCR.Pixels(again) else { return true }
        let still = XiaoLanRecall.dockIcons(px2)
        guard still.wechat != nil || still.wework != nil else { return false }
        DebugLog.write("keyboard: the Dock is still up; the globe key not clicked at its estimate")
        return true
    }

    /// The keyboard menu is open: click "Lan Agent" in it. Without that row (not added, or not read), close the menu
    /// with the globe key once and let the caller fall back, never toggling it open and shut.
    /// D180, n15 over the cloud 11-20 (148): twice the menu was taken for open with no Lan Agent row (thermal serious, the
    /// frames 4 s old, the main thread held 4-5 s), closed at once, and the globe's click went on to the next keyboard:
    /// "shouerlvyou" went in as letters, and the search never ran. Lan Agent was picked from the same menu minutes
    /// before and after. A menu without the row is looked at once more, on a fresh frame, before it is closed.
    private func useKeyboardMenu(_ rows: [[CandidatePicker.Piece]], _ attempt: Int) async -> Bool {
        var found = CandidatePicker.keyboardMenuEntry(rows: rows)
        if found == nil {
            try? await Task.sleep(nanoseconds: 800_000_000)
            if let again = await freshFrame() {
                found = CandidatePicker.keyboardMenuEntry(rows: await CandidatePicker.rowsOffMain(in: again, top: 0.3, bottom: 1))
                if found != nil { DebugLog.write("keyboard: the Lan Agent row showed on a second look (try \(attempt))") }
            }
        }
        guard let entry = found else {
            // 183: what the menu read, for the next miss (11-26 the iPad's 小藍 — Echo row was not matched).
            let read = rows.map { $0.map(\.text).joined() }.filter { !$0.isEmpty }.suffix(12).joined(separator: " | ")
            DebugLog.write("keyboard: the keyboard menu has no Lan Agent row (try \(attempt)); closing it; read: \(read)")
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
