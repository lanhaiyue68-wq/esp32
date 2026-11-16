import Foundation

enum ModelRequestFailure {
    static func isTimeout(_ error: Error) -> Bool {
        (error as? URLError)?.code == .timedOut
    }

    /// The phone has no way to the server at the moment: no model can answer, and waiting is the cure. Over USB 11-09 the
    /// Wi-Fi went away for a few minutes; one model call failed, the replan after it failed the same way, and the run ended.
    static func isNetworkDown(_ error: Error) -> Bool {
        let codes: Set<Int> = [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
                               NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorDataNotAllowed,
                               NSURLErrorInternationalRoamingOff]
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

    static func message(_ error: Error) -> String {
        if isTimeout(error) {
            return String(localized: "The model request timed out before it finished. Try again or choose a specific vision model instead of automatic routing.")
        }
        return error.localizedDescription
    }
}
