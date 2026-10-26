import Foundation

/// The app-switching boundary of a paste. A paste is allowed only after the original screen is restored.
@MainActor enum PasteRoundTrip {
    static func perform(_ text: String, isActive: () -> Bool,
                        previousApp: () async throws -> Void, nextApp: () async throws -> Void,
                        waitForAgent: () async -> Bool, put: (String) -> Bool,
                        verifySource: () async -> Bool) async -> PasteHopResult {
        guard !Task.isCancelled, !isActive() else { return .lost }
        do {
            var hops = 0
            for _ in 0..<2 {
                try Task.checkCancellation()
                try await previousApp()
                hops += 1
                if await waitForAgent(), isActive() { break }
            }
            guard !Task.isCancelled, isActive() else { return .lost }
            let filled = put(text)
            // Undo every switch, including switches through an unrelated app. Filling the clipboard alone is
            // insufficient: Cmd+V is allowed only when a fresh frame confirms the original destination.
            for _ in 0..<hops {
                try Task.checkCancellation()
                try await nextApp()
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
        // Ignore the status bar and keyboard. Match readable content as well as layout: two dark chat apps can
        // otherwise have almost identical coarse images. Unreadable screens cannot authorize a paste.
        func words(_ data: Data) -> String {
            CandidatePicker.bare(CandidatePicker.rows(in: data, top: 0.06, bottom: 0.6)
                .flatMap { $0 }.map(\.text).joined()).lowercased()
        }
        let source = words(before)
        guard source.count >= 2, source == words(after) else { return false }
        let x = Vision.gray(a, 24, 48).px, y = Vision.gray(b, 24, 48).px
        var total = 0, changed = 0, count = 0
        for row in 3..<29 {
            for col in 0..<24 {
                let i = row * 24 + col, difference = abs(Int(x[i]) - Int(y[i]))
                total += difference
                if difference > 35 { changed += 1 }
                count += 1
            }
        }
        return Double(total) / Double(count) <= 8 && Double(changed) / Double(count) <= 0.05
    }
}
