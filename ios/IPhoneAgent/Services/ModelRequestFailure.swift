import CFNetwork
import Foundation

enum ModelRequestFailure {
    static func isTimeout(_ error: Error) -> Bool {
        (error as? URLError)?.code == .timedOut
    }

    /// The phone has no way to the server at the moment: no model can answer, and waiting is the cure. Over USB 11-09 the
    /// Wi-Fi went away for a few minutes; one model call failed, the replan after it failed the same way, and the run ended.
    /// D171, h07 over the cloud 11-19 (148): the phone's network dropped for ~90 s; two calls said 网络连接已中断 and were
    /// waited out, the next said TLS错误导致安全连接失败 (a handshake cut by the same drop), counted as the model's error,
    /// and the replan after it hit it again and ended the run; 13 s later the next task ran. A failed secure connection
    /// is waited for as well (a lasting one still ends at offlineWaitLimit).
    static func isNetworkDown(_ error: Error) -> Bool {
        let codes: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
                               NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorDataNotAllowed,
                               NSURLErrorInternationalRoamingOff, NSURLErrorSecureConnectionFailed]
        var current: NSError? = error as NSError
        for _ in 0..<3 {
            guard let e = current else { return false }
            if e.domain == NSURLErrorDomain, codes.contains(e.code) { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// D47, 136 over the cloud 11-16 (z5, z6): Doubao answered HTTP 403 AccountOverdueError on every call. Asking it again
    /// does nothing until the owner pays or fixes the key: an overdue account, a wrong key, or a model not opened.
    static func isAccountClosed(_ error: Error) -> Bool {
        accountClosed(error.localizedDescription)
    }

    static func accountClosed(_ message: String) -> Bool {
        ["AccountOverdue", "HTTP 401", "AuthenticationError", "insufficient_quota", "ModelNotOpen"].contains { message.contains($0) }
    }

    /// D92, 138 over the cloud 11-17: from 11:16 every call to Doubao and to Codex failed after 5.1 s, "网络连接已中断"
    /// (z3 at 50 minutes, z4-z6 and every task after). The phone's traffic went through a proxy app's listener on the
    /// phone itself (127.0.0.1:1082), and it did not answer ("Socket is not connected", 0 bytes sent). The cloud, on the
    /// LAN, still worked: the owner saw "no network" on a phone that looked connected, and was not told what to do. With
    /// the network down and a proxy on the phone itself, the proxy is named.
    static func localProxy() -> String? {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
        return localProxy(in: settings)
    }

    /// The first proxy on the phone itself (127.x, localhost, ::1) in system proxy settings, its scoped ones (a VPN's) too.
    static func localProxy(in settings: [String: Any]) -> String? {
        var all = [settings]
        if let scoped = settings["__SCOPED__"] as? [String: Any] { all += scoped.values.compactMap { $0 as? [String: Any] } }
        let kinds = [("HTTPSEnable", "HTTPSProxy", "HTTPSPort"), ("HTTPEnable", "HTTPProxy", "HTTPPort"),
                     ("SOCKSEnable", "SOCKSProxy", "SOCKSPort")]
        for s in all {
            for (on, host, port) in kinds {
                guard (s[on] as? NSNumber)?.boolValue == true, let h = s[host] as? String,
                      h.hasPrefix("127.") || ["localhost", "::1"].contains(h.lowercased()) else { continue }
                return (s[port] as? NSNumber).map { "\(h):\($0.intValue)" } ?? h
            }
        }
        return nil
    }

    static func proxyDown(_ proxy: String) -> String {
        "连不上模型：这台手机的网络要经过手机上的代理 App（\(proxy)），它没有响应。请打开代理 App 重新连接或换个节点，再试一次。"
    }

    static func message(_ error: Error) -> String {
        if isNetworkDown(error), let proxy = localProxy() { return proxyDown(proxy) }  // D92
        if isTimeout(error) {
            return String(localized: "The model request timed out before it finished. Try again or choose a specific vision model instead of automatic routing.")
        }
        return error.localizedDescription
    }
}
