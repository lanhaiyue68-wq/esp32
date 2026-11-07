import Foundation
import UIKit

/// Where an app was found on the Home Screen (page from the first, centre of its name label), or that it is opened
/// through search (in the dock, a folder or the App Library: no label found on the first pages).
struct AppPlace: Codable, Equatable {
    var page: Int?
    var x: Double
    var y: Double
    var bySearch: Bool { page == nil }
}

/// Learned app places (phase B, specs/004): the first time an app is opened its Home Screen page and spot are kept,
/// so the next time goes straight there. Local only: app names and positions.
enum AppPlaces {
    private static let key = "appPlacesV1"

    static var all: [String: AppPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let places = try? JSONDecoder().decode([String: AppPlace].self, from: data) else { return [:] }
        return places
    }

    static func set(_ place: AppPlace?, for name: String) {
        var places = all
        places[normalized(name)] = place
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func place(for name: String) -> AppPlace? { all[normalized(name)] }
    static var count: Int { all.count }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func normalized(_ name: String) -> String { name.lowercased().filter { !$0.isWhitespace } }

    /// The centre of the label that reads exactly `name` (an app's name under its icon), the topmost if several.
    static func label(_ name: String, in rows: [[CandidatePicker.Piece]], below top: Double = 0.07) -> CGPoint? {
        let want = normalized(name)
        guard !want.isEmpty else { return nil }
        return rows.flatMap { $0 }
            .filter { normalized($0.text) == want && $0.box.midY > top }
            .min { $0.box.midY < $1.box.midY }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The icon above a Home Screen label: its centre sits about 0.04 of the screen higher.
    static func icon(above label: CGPoint) -> CGPoint { CGPoint(x: label.x, y: max(0.05, label.y - 0.04)) }

    /// The Search pill above the dock (iOS 16+), by its label.
    static func searchPill(in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        rows.flatMap { $0 }
            .first { ["搜索", "搜尋", "search"].contains(normalized($0.text)) && $0.box.midY > 0.7 }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }
}

extension AppModel {
    /// Opens `name` the fastest sure way: its learned Home Screen spot, else the first Home Screen pages read for its
    /// label (and learned), else Search typed by Lan Agent's keyboard. True once a tap or search opened something;
    /// the agent's next look checks it is the right app. Opening Clock took the model ~20 steps (logs 11-08: pinyin
    /// typed 始终 for 时钟, then Google results, then the App Store).
    func openApp(_ name: String) async throws -> Bool {
        let started = now()
        defer { DebugLog.write(String(format: "open %@: %.1f s", name, now() - started)) }
        try await firstHomePage()
        if let place = AppPlaces.place(for: name), let page = place.page {
            try await swipePages(page)
            // Its label anywhere on the learned page: tapped where it is now (and the spot updated).
            if let rows = await homeRows(), let spot = AppPlaces.label(name, in: rows) {
                let moved: Bool = abs(spot.x - place.x) + abs(spot.y - place.y) > 0.06
                DebugLog.write("open \(name): learned page \(page + 1)" + (moved ? ", moved on it" : ""))
                return try await tapIcon(spot, name: name, page: page)
            }
            DebugLog.write("open \(name): not on its learned page any more; looking again")
            try await firstHomePage()
        }
        if AppPlaces.place(for: name)?.bySearch != true {
            for page in 0..<4 {
                if page > 0 { try await swipePages(1) }
                guard let rows = await homeRows() else { break }
                if let spot = AppPlaces.label(name, in: rows) {
                    DebugLog.write("open \(name): found on Home Screen page \(page + 1); learned")
                    return try await tapIcon(spot, name: name, page: page)
                }
            }
            try await firstHomePage()
        }
        return try await openBySearch(name)
    }

    private func tapIcon(_ label: CGPoint, name: String, page: Int) async throws -> Bool {
        let icon = AppPlaces.icon(above: label)
        try await pointer.tap(icon.x, icon.y)
        AppPlaces.set(AppPlace(page: page, x: label.x, y: label.y), for: name)
        try? await Task.sleep(nanoseconds: 900_000_000)  // the app opens
        return true
    }

    private func openBySearch(_ name: String) async throws -> Bool {
        if let rows = await homeRows(), let pill = AppPlaces.searchPill(in: rows) {
            try await pointer.tap(pill.x, pill.y)
        } else {
            try await pointer.swipe(0.5, 0.32, 0.5, 0.62, hold: false)  // swipe down on the Home Screen: Search
        }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard await showLanAgentKeyboard(), await keyboardBridge.type(name, enter: false, within: 4) else {
            DebugLog.write("open \(name): Search did not take the name")
            return false
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // the results
        // The result named exactly so, read between the top and the keyboard: not the search field, which holds the
        // typed name too (at the top, or just above the keyboard).
        if let frame = await freshFrame(),
           let spot = AppPlaces.label(name, in: CandidatePicker.rows(in: frame, top: 0.12, bottom: 0.5), below: 0.12) {
            try await pointer.tap(spot.x, spot.y)
            DebugLog.write("open \(name): tapped its Search result")
        } else {
            try await pointer.key("enter")  // another display name: Return opens the top hit
            DebugLog.write("open \(name): no result named exactly so; Return for the top hit")
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if AppPlaces.place(for: name) == nil { AppPlaces.set(AppPlace(page: nil, x: 0, y: 0), for: name) }
        return true
    }

    /// Home twice: the first leaves the app, the second goes to the first Home Screen page.
    private func firstHomePage() async throws {
        try await pointer.goHome()
        try? await Task.sleep(nanoseconds: 700_000_000)
        try await pointer.goHome()
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private func swipePages(_ count: Int) async throws {
        for _ in 0..<count {
            try await pointer.swipe(0.85, 0.5, 0.15, 0.5, hold: false)
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    private func homeRows() async -> [[CandidatePicker.Piece]]? {
        guard let frame = await freshFrame() else { return nil }
        return CandidatePicker.rows(in: frame, top: 0.07, bottom: 1)
    }
}
