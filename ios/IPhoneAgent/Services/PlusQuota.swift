import Foundation

/// User 11-11: how much of Codex (ChatGPT Plus) is left. Every answer from Codex carries it in x-codex-* headers
/// (seen on the phone: primary = the 5-hour window, 300 minutes; secondary = the week, 10080 minutes; used percent and
/// when each resets). Kept from the last answer (or refusal) and shown in Settings; nothing is asked just to read it.
struct PlusQuota: Codable, Equatable {
    struct Window: Codable, Equatable {
        var minutes: Int
        var usedPercent: Int
        var resetAt: Double?  // seconds since 1970
    }

    var short: Window?   // primary
    var long: Window?    // secondary
    var plan: String?
    var seenAt: Double

    static let key = "plusQuotaV1"

    /// From the response headers (keys lowercased); nil when they say nothing of the quota.
    init?(headers: [String: String], now: Double = Date().timeIntervalSince1970) {
        func window(_ name: String, minutes: Int) -> Window? {
            guard let used = headers["x-codex-\(name)-used-percent"].flatMap(Double.init) else { return nil }
            let at = headers["x-codex-\(name)-reset-at"].flatMap(Double.init)
                ?? headers["x-codex-\(name)-reset-after-seconds"].flatMap(Double.init).map { now + $0 }
            return Window(minutes: headers["x-codex-\(name)-window-minutes"].flatMap { Int($0) } ?? minutes,
                          usedPercent: min(max(Int(used.rounded()), 0), 100), resetAt: at)
        }
        short = window("primary", minutes: 300)
        long = window("secondary", minutes: 10080)
        guard short != nil || long != nil else { return nil }
        plan = headers["x-codex-plan-type"]
        seenAt = now
    }

    static var saved: PlusQuota? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(PlusQuota.self, from: $0) }
    }

    static func save(_ quota: PlusQuota) {
        if let data = try? JSONEncoder().encode(quota) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// "5 小时额度：剩 99%，4 小时 54 分后重置". A window whose reset time has passed is full again.
    static func line(_ w: Window, now: Double = Date().timeIntervalSince1970) -> String {
        let name = w.minutes % 1440 == 0 ? (w.minutes == 10080 ? "本周" : "\(w.minutes / 1440) 天") : "\(max(w.minutes / 60, 1)) 小时"
        guard let at = w.resetAt else { return "\(name)额度：剩 \(100 - w.usedPercent)%" }
        if at <= now { return "\(name)额度：已重置（剩 100%）" }
        let left = Int(at - now)
        let when: String
        if left < 3600 { when = "\(max(left / 60, 1)) 分后" }
        else if left < 86400 { when = "\(left / 3600) 小时 \(left % 3600 / 60) 分后" }
        else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 EEE HH:mm"
            when = f.string(from: Date(timeIntervalSince1970: at))
        }
        return "\(name)额度：剩 \(100 - w.usedPercent)%，\(when)重置"
    }

    /// Both windows, one a line, and when this was read.
    func lines(now: Double = Date().timeIntervalSince1970) -> [String] {
        var out = [short, long].compactMap { $0.map { Self.line($0, now: now) } }
        let ago = Int(now - seenAt)
        out.append(ago < 60 ? "刚刚更新" : ago < 3600 ? "\(ago / 60) 分钟前更新" : ago < 86400 ? "\(ago / 3600) 小时前更新" : "\(ago / 86400) 天前更新")
        return out
    }
}
