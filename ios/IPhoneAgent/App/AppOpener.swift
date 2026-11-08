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
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: mappedKey)
    }

    /// User 11-09: "盡量走ocr的方式看app在哪邊位置，然後記住這個位置下次就可以直接打開". The Home Screen's pages were read
    /// once for the names under their icons; pages count from the leftmost. An app on none of them goes through Search.
    private static let mappedKey = "appPlacesMappedV1"
    static var mapped: Bool {
        get { UserDefaults.standard.bool(forKey: mappedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mappedKey) }
    }

    /// The names under the icons of a page, read.
    static func names(_ rows: [[CandidatePicker.Piece]]) -> [CandidatePicker.Piece] {
        rows.flatMap { $0 }.filter { piece in
            let text = piece.text.filter { !$0.isWhitespace }
            return (1...12).contains(text.count) && (0.1...0.86).contains(piece.box.midY) && !text.allSatisfy { $0.isNumber || $0 == "°" }
        }
    }

    static func learnPage(_ page: Int, _ rows: [[CandidatePicker.Piece]]) {
        var places = all
        for piece in names(rows) { places[normalized(piece.text)] = AppPlace(page: page, x: piece.box.midX, y: piece.box.midY) }
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// The page an app was seen on, under any of its names (时钟, 時鐘, Clock).
    static func page(of name: String) -> Int? {
        let places = all
        return AppNames.variants(name).compactMap { places[normalized($0)]?.page }.first
    }

    /// Which page is in front: the page most of the names read here were seen on.
    static func page(showing rows: [[CandidatePicker.Piece]]) -> Int? {
        let places = all
        var votes: [Int: Int] = [:]
        for piece in names(rows) {
            if let page = places[normalized(piece.text)]?.page { votes[page, default: 0] += 1 }
        }
        return votes.max { $0.value < $1.value }?.key
    }

    static func normalized(_ name: String) -> String { name.lowercased().filter { !$0.isWhitespace } }

    /// The centre of the label that reads `name` (an app's name under its icon) in any of its forms (时钟, 時鐘, Clock),
    /// the topmost if several.
    static func label(_ name: String, in rows: [[CandidatePicker.Piece]], below top: Double = 0.07) -> CGPoint? {
        let wants = Set(AppNames.variants(name).map(normalized).filter { !$0.isEmpty })
        guard !wants.isEmpty else { return nil }
        let hits = rows.flatMap { $0 }.filter { wants.contains(normalized($0.text)) && $0.box.midY > top }
        guard let first = hits.min(by: { $0.box.midY < $1.box.midY }) else { return nil }
        // An icon's own letters read too (美团 in its icon at y 0.122, 美团 under it at 0.177): the name under it.
        let under = hits.filter { abs($0.box.midX - first.box.midX) < 0.03 && $0.box.midY - first.box.midY < 0.1 }
            .max { $0.box.midY < $1.box.midY } ?? first
        return CGPoint(x: under.box.midX, y: under.box.midY)
    }

    /// The icon above a Home Screen label: its centre sits about 0.04 of the screen higher.
    static func icon(above label: CGPoint) -> CGPoint { CGPoint(x: label.x, y: max(0.05, label.y - 0.04)) }

    /// The App Library (past the last Home Screen page), by the search field at its top. build104 live 11-08: the page
    /// scan swiped into it and looked for icon labels it does not show (美團 sat in its corner), then gave up.
    static let libraryTitles: Set<String> = ["app資料庫", "app资源库", "applibrary"]
    private static func isLibraryField(_ piece: CandidatePicker.Piece) -> Bool {
        let text = normalized(piece.text)  // its magnifier can be read as a letter in front ("Q App 資料庫")
        return piece.box.midY < 0.15 && libraryTitles.contains { text.contains($0) }
    }
    static func inLibrary(_ rows: [[CandidatePicker.Piece]]) -> Bool { rows.flatMap { $0 }.contains(where: isLibraryField) }
    static func libraryField(in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        rows.flatMap { $0 }.first(where: isLibraryField).map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// Home Screen Search is open: its section headers.
    static let searchHeaders = ["siri建議", "siri建议", "sirisuggestions", "最佳搜尋結果", "最佳搜索结果", "tophit", "顯示較多", "显示更多", "showmore",
                                "在app中搜尋", "在app中搜索", "searchinapp", "搜尋appstore", "搜索appstore"]
    static func inSearch(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let pieces = rows.flatMap { $0 }
        if pieces.contains(where: { piece in
            let text = normalized(piece.text)
            return searchHeaders.contains { text.contains($0) }
        }) { return true }
        // No results yet: its field above a keyboard, its magnifier read as a Q ("Q瀏覽器").
        return keyboardShown(rows) && pieces.contains { $0.text.hasPrefix("Q") && (0.5...0.65).contains($0.box.midY) && $0.box.midX < 0.5 }
    }

    /// A Home Screen page: its Search pill, or names in the four icon columns. Apps have many short labels too (the
    /// app switcher shows them on its cards), and a flick on the Home Screen opens the switcher: so not just "many".
    static func looksLikeHome(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        guard !inLibrary(rows), !inSearch(rows) else { return false }
        if searchPill(in: rows) != nil { return true }
        let columns = [0.15, 0.38, 0.62, 0.85]
        let names = rows.flatMap { $0 }.filter { piece in
            let text = piece.text.filter { !$0.isWhitespace }
            return (1...8).contains(text.count) && (0.1...0.9).contains(piece.box.midY) && !text.allSatisfy(\.isNumber)
        }
        let placed = names.compactMap { name in columns.firstIndex { abs($0 - Double(name.box.midX)) < 0.05 } }
        return placed.count >= 8 && Set(placed).count == 4 && placed.count * 10 >= names.count * 9
    }

    /// The app in Search's results, read from the phone: under the "App" header, or as the top hit above the web
    /// suggestions (建議: Safari's row, which also reads the name). The field is lower, above the keyboard. For 美團 the top
    /// hit was a text message with a login code, and Return opened that.
    static func searchResult(_ name: String, in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        let pieces = rows.flatMap { $0 }
        func header(_ names: [String]) -> CGFloat? {
            pieces.filter { names.contains(normalized($0.text)) }.map(\.box.midY).min()
        }
        let wants = Set(AppNames.variants(name).map(normalized).filter { !$0.isEmpty })
        let hits = pieces.filter { wants.contains(normalized($0.text)) && (0.07...0.55).contains($0.box.midY) }
            .sorted { $0.box.midY < $1.box.midY }
        let hit: CandidatePicker.Piece?
        if let app = header(["app"]), let under = hits.first(where: { $0.box.midY > app }) {
            hit = under
        } else if let web = header(["建議", "建议", "suggestions"]) {
            hit = hits.first { $0.box.midY < web }
        } else {
            hit = hits.first
        }
        return hit.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The Search pill above the dock (iOS 16+), by its label.
    static func searchPill(in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        rows.flatMap { $0 }.first { piece in
            let text = normalized(piece.text)  // its magnifier can be read as a letter in front ("Q 搜尋")
            return text.count <= 8 && ["搜索", "搜尋", "search"].contains { text.hasSuffix($0) }
                && piece.box.midY > 0.7 && abs(piece.box.midX - 0.5) < 0.12
        }.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// Lan Agent's keyboard, read: it has no letter keys for CandidatePicker to see.
    static func keyboardShown(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let keys = rows.flatMap { $0 }.filter { $0.box.midY > 0.6 }.map { normalized($0.text) }
        return keys.contains { ["換行", "换行", "空格", "下一個", "下一个"].contains($0) } || keys.contains { $0.hasPrefix("lanagent輸入法") || $0.hasPrefix("lanagent输入法") }
    }

    /// Search's field says what Return would do: "設定 — 打開".
    static func returnOpens(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        rows.flatMap { $0 }.contains { piece in
            let text = normalized(piece.text)
            return (0.5...0.65).contains(piece.box.midY) && ["打開", "打开", "—open", "｜open"].contains { text.contains($0) }  // "QSafari｜打開）e."
        }
    }
}

/// An app's name as the phone shows it. The model names apps in Simplified Chinese; the test phone runs in Traditional
/// Chinese (live test 11-08: "open 时钟" and "open 无边记" each spent ~30 s on pages and Search and found nothing,
/// twice in one run). Character conversion covers most names; Taiwan names that differ, and English, come from here.
enum AppNames {
    /// What the phone's own language means for names on its screen. build105 live 11-08: a search for 无边记 found
    /// nothing on a phone that says 無邊記.
    static var languageNote: String {
        guard let language = Locale.preferredLanguages.first?.lowercased(), language.hasPrefix("zh") else { return "" }
        let traditional = language.contains("hant") || language.contains("-tw") || language.contains("-hk") || language.contains("-mo")
        return traditional
            ? "\nThis phone's language is Traditional Chinese: apps and labels read in Traditional (無邊記, 時鐘, 備忘錄). Type names in Traditional when searching."
            : "\nThis phone's language is Simplified Chinese: apps and labels read in Simplified (无边记, 时钟, 备忘录). Type names in Simplified when searching."
    }

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
        // An app that has one name everywhere, asked for by it: "Safari" was typed as 瀏覽器 (over USB, 11-09).
        if let alias = aliases[base(name)], alias.tw == nil, alias.en.lowercased() == name.lowercased() { return name }
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
        try await pointer.goHome()
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard var rows = await homeRows(top: 0.02) else { return try await openBySearch(name) }
        if let spot = AppPlaces.label(name, in: rows) { return try await tapIcon(spot, name: name, on: "the page in front") }
        if !AppPlaces.mapped, AppPlaces.looksLikeHome(rows) {
            try await mapHomeScreen()
            guard let now = await homeRows(top: 0.02) else { return try await openBySearch(name) }
            rows = now
            if let spot = AppPlaces.label(name, in: rows) { return try await tapIcon(spot, name: name, on: "the page in front") }
        }
        if let target = AppPlaces.page(of: name), let current = AppPlaces.page(showing: rows), target != current {
            for _ in 0..<abs(target - current) {
                try await swipePage(next: target > current)
            }
            if let now = await homeRows(top: 0.02), let spot = AppPlaces.label(name, in: now) {
                return try await tapIcon(spot, name: name, on: "page \(target + 1), as remembered")
            }
            DebugLog.write("open \(name): not on page \(target + 1) any more; the pages are read again next time")
            AppPlaces.mapped = false
            try await pointer.goHome()
        }
        if try await openBySearch(name) { return true }
        return try await openFromPages(name)
    }

    /// Read every Home Screen page once: to the leftmost, then right up to the App Library.
    private func mapHomeScreen() async throws {
        let began = now()
        for _ in 0..<8 {
            try await swipePage(next: false)
            guard let rows = await homeRows(top: 0.02) else { return }
            if !AppPlaces.looksLikeHome(rows) {  // Today's widgets, left of the first page
                try await swipePage(next: true)
                break
            }
        }
        var page = 0
        while page < 12 {
            guard var rows = await homeRows(top: 0.02) else { return }
            if !AppPlaces.inLibrary(rows), !AppPlaces.looksLikeHome(rows) {  // still sliding?
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard let again = await homeRows(top: 0.02) else { return }
                rows = again
            }
            if AppPlaces.inLibrary(rows) || !AppPlaces.looksLikeHome(rows) {
                try await swipePage(next: false)
                break
            }
            AppPlaces.learnPage(page, rows)
            page += 1
            try await swipePage(next: true)
        }
        AppPlaces.mapped = true
        DebugLog.write(String(format: "open: %ld Home Screen page(s) read, %ld names known, %.1f s", page, AppPlaces.count, now() - began))
    }

    private func swipePage(next: Bool) async throws {
        try await pointer.swipe(next ? 0.85 : 0.15, 0.5, next ? 0.15 : 0.85, 0.5, hold: false)
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    /// Only when Search would not work (no keyboard came): the pages to the right up to the App Library, then to the left.
    private func openFromPages(_ name: String) async throws -> Bool {
        try await pointer.goHome()
        for next in [true, false] {
            for _ in 0..<6 {
                try await swipePage(next: next)
                guard let rows = await homeRows(top: 0.02) else { return false }
                if let spot = AppPlaces.label(name, in: rows), !AppPlaces.inLibrary(rows) {
                    return try await tapIcon(spot, name: name, on: "a page, paging")
                }
                if AppPlaces.inLibrary(rows) || !AppPlaces.looksLikeHome(rows) { break }  // the App Library, or Today's widgets
            }
        }
        return false
    }

    private func tapIcon(_ label: CGPoint, name: String, on place: String) async throws -> Bool {
        DebugLog.write("open \(name): \(place)")
        let icon = AppPlaces.icon(above: label)
        try await pointer.tap(icon.x, icon.y)
        try? await Task.sleep(nanoseconds: 900_000_000)  // the app opens
        return true
    }

    private func openBySearch(_ name: String) async throws -> Bool {
        // Measured over USB 11-09: Cmd+Space opens Search from the Home Screen (not from inside an app), its last words
        // selected and with the keyboard last used. The pill or a pull down only if it does not come.
        try await pointer.key("cmd+space")
        try? await Task.sleep(nanoseconds: 700_000_000)
        if let rows = await homeRows(top: 0.02), !AppPlaces.inSearch(rows), !AppPlaces.keyboardShown(rows) {
            DebugLog.write("open \(name): Cmd+Space brought no Search; the pill or a pull down")
            if let pill = AppPlaces.searchPill(in: rows) {
                try await pointer.tap(pill.x, pill.y)
            } else {
                try await pointer.swipe(0.5, 0.3, 0.5, 0.55, hold: false)
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        let typed = AppNames.searchName(name)
        if typed != name { DebugLog.write("open \(name): searching for \(typed), the phone's own name") }
        guard await showLanAgentKeyboard() else {
            DebugLog.write("open \(name): Search did not take the name")
            return false
        }
        try await pointer.key("cmd+a")
        try await pointer.key("backspace")
        guard await keyboardBridge.type(typed, enter: false, within: 4) else {
            DebugLog.write("open \(name): Search did not take the name")
            return false
        }
        // The results come a moment later; a Return before them opens nothing (over USB, 11-09).
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let rows = await freshFrame().map { CandidatePicker.rows(in: $0, top: 0.02, bottom: 0.7) } ?? []
        if AppPlaces.returnOpens(rows) {
            // The keyboard's own Return: the board's Enter does nothing with it up.
            if await !keyboardBridge.type("", enter: true, within: 3) { try await pointer.key("enter") }
            DebugLog.write("open \(name): Return, Search says it opens")
        } else if let spot = AppPlaces.searchResult(name, in: rows) {
            try await pointer.tap(spot.x, spot.y)
            DebugLog.write("open \(name): tapped its Search result")
        } else {
            DebugLog.write("open \(name): not in Search's results")
            return false
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        return true
    }

    private func homeRows(top: Double = 0.07) async -> [[CandidatePicker.Piece]]? {
        guard let frame = await freshFrame() else { return nil }
        return CandidatePicker.rows(in: frame, top: top, bottom: 1)
    }
}
