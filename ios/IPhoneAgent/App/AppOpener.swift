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

    /// The centre of the label that reads `name` (an app's name under its icon) in any of its forms (时钟, 時鐘, Clock),
    /// the topmost if several.
    static func label(_ name: String, in rows: [[CandidatePicker.Piece]], below top: Double = 0.07) -> CGPoint? {
        let wants = Set(AppNames.variants(name).map(normalized).filter { !$0.isEmpty })
        guard !wants.isEmpty else { return nil }
        return rows.flatMap { $0 }
            .filter { wants.contains(normalized($0.text)) && $0.box.midY > top }
            .min { $0.box.midY < $1.box.midY }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The icon above a Home Screen label: its centre sits about 0.04 of the screen higher.
    static func icon(above label: CGPoint) -> CGPoint { CGPoint(x: label.x, y: max(0.05, label.y - 0.04)) }

    /// The App Library (past the last Home Screen page), by the search field at its top. build104 live 11-08: the page
    /// scan swiped into it and looked for icon labels it does not show (美團 sat in its corner), then gave up.
    static let libraryTitles: Set<String> = ["app資料庫", "app资源库", "applibrary"]
    static func inLibrary(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        rows.flatMap { $0 }.contains { libraryTitles.contains(normalized($0.text)) && $0.box.midY < 0.15 }
    }
    static func libraryField(in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        rows.flatMap { $0 }.first { libraryTitles.contains(normalized($0.text)) && $0.box.midY < 0.15 }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// A Home Screen page: its Search pill, or a grid of short app names. build104 live 11-08: the board's flick up
    /// left the app switcher open (an app's card) and Search was swiped open on it, every time, for 30 s.
    static func looksLikeHome(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        guard !inLibrary(rows) else { return false }
        if searchPill(in: rows) != nil { return true }
        let names = rows.flatMap { $0 }.filter { piece in
            let text = piece.text.filter { !$0.isWhitespace }
            return (1...8).contains(text.count) && (0.1...0.9).contains(piece.box.midY) && !text.allSatisfy(\.isNumber)
        }
        return names.count >= 8
    }

    /// The Search pill above the dock (iOS 16+), by its label.
    static func searchPill(in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        rows.flatMap { $0 }
            .first { ["搜索", "搜尋", "search"].contains(normalized($0.text)) && $0.box.midY > 0.7 }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }
}

/// An app's name as the phone shows it. The model names apps in Simplified Chinese; the test phone runs in Traditional
/// Chinese (live test 11-08: "open 时钟" and "open 无边记" each spent ~30 s on pages and Search and found nothing,
/// twice in one run). Character conversion covers most names; Taiwan names that differ, and English, come from here.
enum AppNames {
    static let aliases: [String: (tw: String?, en: String)] = [
        "时钟": ("時鐘", "Clock"), "无边记": ("無邊記", "Freeform"), "设置": ("設定", "Settings"),
        "信息": ("訊息", "Messages"), "日历": ("行事曆", "Calendar"), "计算器": ("計算機", "Calculator"),
        "快捷指令": ("捷徑", "Shortcuts"), "文件": ("檔案", "Files"), "备忘录": ("備忘錄", "Notes"),
        "相机": ("相機", "Camera"), "照片": (nil, "Photos"), "天气": ("天氣", "Weather"), "地图": ("地圖", "Maps"),
        "提醒事项": ("提醒事項", "Reminders"), "电话": ("電話", "Phone"), "邮件": ("郵件", "Mail"),
        "音乐": ("音樂", "Music"), "钱包": ("錢包", "Wallet"), "健康": (nil, "Health"), "翻译": ("翻譯", "Translate"),
        "指南针": ("指南針", "Compass"), "图书": ("書籍", "Books"), "播客": ("Podcast", "Podcasts"),
        "通讯录": ("聯絡人", "Contacts"), "微信": (nil, "WeChat"), "浏览器": (nil, "Safari"), "录音机": ("語音備忘錄", "Voice Memos")]

    static func hant(_ s: String) -> String { s.applyingTransform(StringTransform(rawValue: "Hans-Hant"), reverse: false) ?? s }
    static func hans(_ s: String) -> String { s.applyingTransform(StringTransform(rawValue: "Hant-Hans"), reverse: false) ?? s }

    /// The Simplified name this one stands for: itself, its character conversion, or the name whose alias it is.
    private static func base(_ name: String) -> String {
        let simple = hans(name)
        if aliases[simple] != nil { return simple }
        let key = AppPlaces.normalized(name)
        return aliases.first { AppPlaces.normalized($0.value.en) == key || $0.value.tw.map(AppPlaces.normalized) == key }?.key ?? simple
    }

    /// Every form the phone may show, the given one first.
    static func variants(_ name: String) -> [String] {
        let b = base(name), alias = aliases[b]
        var out: [String] = []
        for v in [name, alias?.tw, hant(b), b, alias?.en].compactMap({ $0 }) where !v.isEmpty && !out.contains(v) { out.append(v) }
        return out
    }

    /// The form to type into Search: the phone's own language.
    static func searchName(_ name: String, language: String = Locale.preferredLanguages.first ?? "") -> String {
        let b = base(name), alias = aliases[b], l = language.lowercased()
        if l.hasPrefix("zh-hant") || l.hasPrefix("zh-tw") || l.hasPrefix("zh-hk") || l.hasPrefix("zh-mo") { return alias?.tw ?? hant(b) }
        if l.hasPrefix("zh") { return b }
        if l.hasPrefix("en") { return alias?.en ?? name }
        return name
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
            for page in 0..<6 {
                if page > 0 { try await swipePages(1) }
                guard let rows = await homeRows(top: 0.02) else { break }
                if AppPlaces.inLibrary(rows) {
                    DebugLog.write("open \(name): reached the App Library after \(page) page(s); searching there")
                    return try await openFromLibrary(name, rows: rows)
                }
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
        let typed = AppNames.searchName(name)
        if typed != name { DebugLog.write("open \(name): searching for \(typed), the phone's own name") }
        guard await showLanAgentKeyboard(), await keyboardBridge.type(typed, enter: false, within: 4) else {
            DebugLog.write("open \(name): Search did not take the name; trying the App Library")
            try await firstHomePage()
            for _ in 0..<6 {
                try await swipePages(1)
                if let rows = await homeRows(top: 0.02), AppPlaces.inLibrary(rows) {
                    return try await openFromLibrary(name, rows: rows)
                }
            }
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
        for attempt in 1...3 {
            try await pointer.goHome()
            try? await Task.sleep(nanoseconds: 700_000_000)
            try await pointer.goHome()
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let rows = await homeRows(top: 0.02) else { return }
            if AppPlaces.looksLikeHome(rows) { return }
            // The app switcher (the flick was read as a swipe and hold): an empty spot at its top goes home.
            DebugLog.write("open: not a Home Screen after going home (try \(attempt)); tapping the empty top")
            try await pointer.tap(0.5, 0.05)
            try? await Task.sleep(nanoseconds: 700_000_000)
            if let rows = await homeRows(top: 0.02), AppPlaces.looksLikeHome(rows) { return }
        }
        DebugLog.write("open: no Home Screen seen after three tries")
    }

    private func swipePages(_ count: Int) async throws {
        for _ in 0..<count {
            try await pointer.swipe(0.85, 0.5, 0.15, 0.5, hold: false)
            try? await Task.sleep(nanoseconds: 700_000_000)
        }
    }

    private func homeRows(top: Double = 0.07) async -> [[CandidatePicker.Piece]]? {
        guard let frame = await freshFrame() else { return nil }
        return CandidatePicker.rows(in: frame, top: top, bottom: 1)
    }

    /// The App Library's own search: it lists only apps (no web suggestions), so the result with the name is tapped.
    private func openFromLibrary(_ name: String, rows: [[CandidatePicker.Piece]]) async throws -> Bool {
        let field = AppPlaces.libraryField(in: rows) ?? CGPoint(x: 0.5, y: 0.075)
        try await pointer.tap(field.x, field.y)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let typed = AppNames.searchName(name)
        guard await showLanAgentKeyboard(), await keyboardBridge.type(typed, enter: false, within: 4) else {
            DebugLog.write("open \(name): the App Library's search did not take the name")
            return false
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if let frame = await freshFrame(),
           let spot = AppPlaces.label(name, in: CandidatePicker.rows(in: frame, top: 0.12, bottom: 0.6), below: 0.12) {
            try await pointer.tap(spot.x, spot.y)
            DebugLog.write("open \(name): tapped its App Library result")
        } else {
            try await pointer.key("enter")
            DebugLog.write("open \(name): no App Library result named exactly so; Return for the top one")
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if AppPlaces.place(for: name) == nil { AppPlaces.set(AppPlace(page: nil, x: 0, y: 0), for: name) }
        return true
    }
}
