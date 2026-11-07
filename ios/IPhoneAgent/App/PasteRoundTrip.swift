import Foundation

/// The app-switching boundary of a paste. A paste is allowed only after the original screen is restored.
@MainActor enum PasteRoundTrip {
    static func perform(_ text: String, isActive: () -> Bool,
                        previousApp: () async throws -> Void, nextApp: () async throws -> Void,
                        waitForAgent: () async -> Bool, put: (String) -> Bool,
                        verifySource: () async -> Bool,
                        reopenSource: (() async throws -> Void)? = nil,
                        openAgent: (() async throws -> Void)? = nil) async -> PasteHopResult {
        guard !Task.isCancelled, !isActive() else { return .lost }
        do {
            var hops = 0
            for attempt in 0..<2 {
                try Task.checkCancellation()
                if attempt == 1, reopenSource != nil, let openAgent {
                    // A second swipe goes further into whatever apps were used last (logs 11-07: after the phone task
                    // opened Clock and a drawing app, 6 hops in a row never reached Lan Agent and the result was never
                    // sent). Search opens it whatever the order; the source is reopened directly, so no swipe to undo.
                    DebugLog.write("paste hop: Lan Agent is not the previous app; opening it through Search")
                    try await openAgent()
                } else {
                    try await previousApp()
                }
                hops += 1
                if await waitForAgent(), isActive() { break }
            }
            guard !Task.isCancelled, isActive() else {
                DebugLog.write("paste hop: Lan Agent not reached after \(hops) switches")
                return .lost
            }
            let filled = put(text)
            // Undo every switch, including switches through an unrelated app, or open the source app directly when it
            // can be (WeChat): reversed swipes stopped in Claude when it sat between them (logs 11-06). Filling the
            // clipboard alone is insufficient: Cmd+V is allowed only when a fresh frame confirms the original destination.
            if let reopenSource {
                try Task.checkCancellation()
                try await reopenSource()
            } else {
                for _ in 0..<hops {
                    try Task.checkCancellation()
                    try await nextApp()
                }
            }
            guard !Task.isCancelled, !isActive(), await verifySource() else { return .lost }
            return filled ? .filled : .refused
        } catch {
            return .lost
        }
    }

    static func matchesSource(_ before: Data, _ after: Data) -> Bool {
        guard let a = Vision.image(before), let b = Vision.image(after),
              a.width == b.width, a.height == b.height else { return false }
        // Ignore the status bar, input field and keyboard. Match readable content as well as layout: two dark chat apps can
        // otherwise have almost identical coarse images. Unreadable screens cannot authorize a paste.
        // Pieces that are only a number are not compared: the back button's unread count changes by itself during the
        // few seconds away (logs 11-06: 321 → 322 refused the right chat). A banner over the title still refuses this
        // frame; the caller looks again once it has gone.
        func words(_ data: Data) -> String {
            CandidatePicker.rows(in: data, top: 0.06, bottom: 0.48).flatMap { $0 }
                .map { CandidatePicker.bare($0.text) }
                .filter { !$0.allSatisfy(\.isNumber) }  // unread counts (and pieces with no letters)
                .joined().lowercased()
        }
        let source = words(before)
        guard source.count >= 2, source == words(after) else {
            DebugLog.write("paste hop: stable content text not matched")
            return false
        }
        let x = Vision.gray(a, 24, 48).px, y = Vision.gray(b, 24, 48).px
        var total = 0, changed = 0, count = 0
        for row in 3..<23 {
            for col in 0..<24 {
                let i = row * 24 + col, difference = abs(Int(x[i]) - Int(y[i]))
                total += difference
                if difference > 35 { changed += 1 }
                count += 1
            }
        }
        let matched = Double(total) / Double(count) <= 8 && Double(changed) / Double(count) <= 0.05
        if !matched { DebugLog.write("paste hop: stable content layout not matched") }
        return matched
    }
}
