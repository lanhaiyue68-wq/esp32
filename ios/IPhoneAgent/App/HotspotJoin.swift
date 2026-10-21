import Foundation
import NetworkExtension

/// Being on one Wi-Fi with the board. Firmware v22+ never opens a hotspot and this app never joins a
/// network by itself: idle → joining (sending the phone's Wi-Fi to the board) → verifying (waiting for the
/// board to show up on it) → joined, or failed(reason) while the board waits for its Wi-Fi or the phone is
/// on another one. A new start cancels the old task, so a re-tap always restarts cleanly.
enum JoinState: Equatable {
    case idle, joining, verifying, joined
    case failed(String)

    var busy: Bool { self == .joining || self == .verifying }
}

enum SameWiFi {
    /// Why the phone and the board are not on one Wi-Fi yet; nil when they are. "Same Wi-Fi" is what the
    /// board reports: it is a connected station and this phone's video TCP reached it.
    static func problem(connected: Bool, status: BoardStatus?, boardSSID: String?) -> String? {
        guard connected, let status else { return String(localized: "The board isn't connected over Bluetooth yet.") }
        let ssid = boardSSID ?? ""
        switch status.net ?? "" {
        case "sta" where (status.tcp ?? 0) > 0:
            return nil
        case "sta":
            return String(localized: "The board is on “\(ssid)”. Connect this iPhone to the same Wi-Fi.")
        case "ap":
            return String(localized: "The board still runs old firmware that opens its own hotspot. Update the board to v22; this app no longer joins it.")
        case "off":
            return String(localized: "The board's Wi-Fi is switched off. Send it the Wi-Fi this iPhone is on.")
        default:
            return ssid.isEmpty ? String(localized: "The board has no Wi-Fi yet. Send it the Wi-Fi this iPhone is on.")
                : String(localized: "The board is waiting for “\(ssid)”. Turn that Wi-Fi on or bring the board in range; it joins by itself.")
        }
    }
}

extension AppModel {
    var sameWiFiProblem: String? { SameWiFi.problem(connected: board.connected, status: board.status, boardSSID: board.net?.ssid) }
    var onSameWiFi: Bool { sameWiFiProblem == nil }

    /// Start (or restart) the check. `auto`: the page appeared; skipped once it was tried or is done.
    func startJoin(auto: Bool = false) {
        if auto && join != .idle { return }
        joinTask?.cancel()
        joinTask = Task { [weak self] in await self?.runJoin(seconds: 10) }
    }

    /// The board joins the phone's Wi-Fi (sent over the encrypted BLE link), then the app waits for it there.
    func sendWiFi(ssid: String, pass: String) {
        joinTask?.cancel()
        joinTask = Task { [weak self] in
            guard let self else { return }
            join = .joining
            do {
                try board.writeNet(NetConfig(mode: "sta", ssid: ssid, pass: pass))
            } catch {
                join = .failed(error.localizedDescription)
                return
            }
            say("wifi: sent \(ssid) to the board (password \(pass.count) chars)")
            await runJoin(seconds: 30)  // association, DHCP and the video TCP retry take a while
        }
    }

    private func runJoin(seconds: Int) async {
        if MockMode.on {
            join = .verifying
            try? await Task.sleep(nanoseconds: 800_000_000)
            hotspotSSID = board.net?.ssid ?? "Home Wi-Fi"
            join = .joined
            return mockStartMirroring()
        }
        join = .verifying
        for _ in 0..<(seconds * 2) {
            guard !Task.isCancelled else { return }
            if onSameWiFi { return joined(board.net?.ssid ?? "") }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        let why = sameWiFiProblem ?? ""
        say("wifi: not on one Wi-Fi with the board after \(seconds) s: \(why)")
        join = .failed(why)
    }

    private func joined(_ ssid: String) {
        manualHotspot = nil
        hotspotSSID = ssid
        join = .joined
        say("wifi: same network as the board (\(ssid))")
    }

    /// Poll while the See page is up (and when the app comes back): the phone or the board may have moved.
    func refreshHotspot() async {
        guard !MockMode.on else { return }
        let current = await Hotspot.currentSSID()  // nil without Wi-Fi info access: then only the board can tell
        let ours = board.net?.ssid
        let same = onSameWiFi
        let other = !same && current != nil && current != ours ? current : nil
        if otherWiFi != other { otherWiFi = other }
        if same, hotspotSSID != ours {
            hotspotSSID = ours
            if !join.busy { join = .joined }
            DebugLog.write("wifi: same network as the board (\(ours ?? ""))")
        } else if !same, hotspotSSID != nil || join == .joined {
            hotspotSSID = nil
            if join == .joined { join = .idle }
            DebugLog.write("wifi: not on the board's network")
        }
    }
}
