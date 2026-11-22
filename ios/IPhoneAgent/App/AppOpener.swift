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

    /// Misses in a row on the remembered page. Build 116 over the cloud 11-10: the user had the phone in hand while Meituan
    /// was opened, its page did not show it that once, and it was forgotten for good: every open after went through Search
    /// (13 s). Now the page goes after the second miss in a row; an open there clears the count.
    private static let missKey = "appPlaceMissesV1"
    static func missed(_ name: String) -> Int {
        var misses = (UserDefaults.standard.dictionary(forKey: missKey) as? [String: Int]) ?? [:]
        let n = (misses[normalized(name)] ?? 0) + 1
        misses[normalized(name)] = n
        UserDefaults.standard.set(misses, forKey: missKey)
        return n
    }
    static func found(_ name: String) {
        var misses = (UserDefaults.standard.dictionary(forKey: missKey) as? [String: Int]) ?? [:]
        guard misses.removeValue(forKey: normalized(name)) != nil else { return }
        UserDefaults.standard.set(misses, forKey: missKey)
    }
    static var count: Int { all.count }

    /// When the pages were last read again for an app no page knew (see AppOpener.openAppNow).
    private static let readAgainKey = "appPlacesReadAgainAtV1"
    static func mayReadAgain(now: Date = Date(), every: Double = 3 * 86_400) -> Bool {
        now.timeIntervalSince1970 - UserDefaults.standard.double(forKey: readAgainKey) >= every
    }
    /// A remembered app missing from its page: the apps were moved, and the pages are read again at most this often (s).
    static let rereadAfterMiss = 600.0
    static func readAgainNow(now: Date = Date()) { UserDefaults.standard.set(now.timeIntervalSince1970, forKey: readAgainKey) }
    /// The learning page's "重新記 App 位置": the next open reads the pages at once (no wait since the last read).
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: mappedKey)
        UserDefaults.standard.removeObject(forKey: readAgainKey)
    }

    /// User 11-09: "盡量走ocr的方式看app在哪邊位置，然後記住這個位置下次就可以直接打開". The Home Screen's pages were read
    /// once for the names under their icons; pages count from the leftmost. An app on none of them goes through Search.
    private static let mappedKey = "appPlacesMappedV1"
    static var mapped: Bool {
        get { UserDefaults.standard.bool(forKey: mappedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mappedKey) }
    }

    /// Apps opened since the app started: one of these is on the phone, whatever Search says now (over USB 11-09: Weather
    /// opened, then "not on this phone" two minutes later, and the task stopped there).
    private static var opened: Set<String> = []
    static func noteOpened(_ name: String) { for v in AppNames.variants(name) { opened.insert(normalized(v)) } }
    static func wasOpened(_ name: String) -> Bool { AppNames.variants(name).contains { opened.contains(normalized($0)) } }

    /// D105, z6 on 140: WeChat's icon at (0.617, 0.722) was tapped 32 times in 19 opens and none opened it (from the
    /// corner the pointer landed off it, and with frames at 0.8–1.3 fps it was not seen to be put right); Search opened it
    /// every time: 19 opens took 506 s, 26.6 s each, against 7–9 s for the other apps. User 11-18 ("点不中就改搜索没毛病，
    /// 但是不要永久改搜索"; 142's z6: one bad open of 抖音 sent every later one through Search, 10–15 s against 6 s by its
    /// icon): an app whose icon was tapped twice for nothing is opened by Search the next time only; the time after, its
    /// icon again.
    /// D150b, user 11-19 ("板子动作也优化一下加速"): on 145 WeChat's icon missed again on every other open, each miss two
    /// taps for nothing before Search (26–30 s an open, against 12–13 s by Search alone). Still never Search for good:
    /// an icon missed again in a row is left for 1, then 2, then 4 opens by Search, and the first icon that opens the app
    /// puts it back to the icon every time.
    private static var searchLeft: [String: Int] = [:]
    private static var iconMisses: [String: Int] = [:]
    static func searchOpens(afterMisses n: Int) -> Int { n <= 0 ? 0 : min(4, 1 << min(n - 1, 2)) }

    static func noteIcon(_ name: String, missed: Bool) {
        let keys = AppNames.variants(name).map { normalized($0) }
        let streak = missed ? (keys.compactMap { iconMisses[$0] }.max() ?? 0) + 1 : 0
        for k in keys {
            iconMisses[k] = streak == 0 ? nil : streak
            searchLeft[k] = missed ? searchOpens(afterMisses: streak) : nil
        }
    }
    /// True while opens by Search are left after an icon was missed: this open goes by Search.
    static func takeSearchFirst(_ name: String) -> Bool {
        let keys = AppNames.variants(name).map { normalized($0) }
        guard let left = keys.compactMap({ searchLeft[$0] }).max(), left > 0 else { return false }
        for k in keys { searchLeft[k] = left - 1 }
        return true
    }

    /// A place that turned out wrong goes, alone: reading all the pages again cost 30-55 s each time, for WeChat, which is
    /// on no page at all (three times over USB 11-09). Next time Search is the way.
    static func forget(_ name: String) {
        var places = all
        for v in AppNames.variants(name) { places[normalized(v)] = nil }
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// A folder open on the Home Screen: a few short names in the panel in the middle, and nothing else but the clock. It
    /// closes with a tap outside it (user 11-09); going Home from it took 34 s and opened the keyboard's language menu.
    static func looksLikeOpenFolder(_ rows: [[CandidatePicker.Piece]]) -> Bool {
        let pieces = rows.flatMap { $0 }.filter { $0.box.midY > 0.07 }
        guard (3...20).contains(pieces.count) else { return false }
        return pieces.allSatisfy { piece in
            (0.12...0.88).contains(piece.box.midX) && (0.2...0.75).contains(piece.box.midY)
                && piece.text.filter { !$0.isWhitespace }.count <= 8
        }
    }

    /// The names under the icons of a page, read.
    static func names(_ rows: [[CandidatePicker.Piece]]) -> [CandidatePicker.Piece] {
        rows.flatMap { $0 }.filter { piece in
            let text = piece.text.filter { !$0.isWhitespace }
            return (1...12).contains(text.count) && (0.08...0.86).contains(piece.box.midY) && !text.allSatisfy { $0.isNumber || $0 == "°" }
                && !isPill(piece)  // D40: the Search pill is on every page, it names none
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
        let web = header(["建議", "建议", "suggestions"])
        if let app = header(["app"]), let under = hits.first(where: { $0.box.midY > app }) {
            hit = under
        } else if let app = header(["app"]), let part = pieces.sorted(by: { $0.box.midY < $1.box.midY }).first(where: { piece in
            // Under the App header, part of the name is enough: "open 高德" for 高德地圖.
            let text = normalized(piece.text)
            return piece.box.midY > app && piece.box.midY < (web ?? 0.55) && text.count >= 2 && text != "app"
                && wants.contains { text.contains($0) || $0.contains(text) }
        }) {
            hit = part
        } else if let web {
            hit = hits.first { $0.box.midY < web }
        } else {
            hit = hits.first
        }
        return hit.map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The Search pill above the dock (iOS 16+), by its label.
    static func searchPill(in rows: [[CandidatePicker.Piece]]) -> CGPoint? {
        rows.flatMap { $0 }.first(where: isPill).map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }
    private static func isPill(_ piece: CandidatePicker.Piece) -> Bool {
        let text = normalized(piece.text)  // its magnifier can be read as a letter in front ("Q 搜尋")
        return text.count <= 8 && ["搜索", "搜尋", "search"].contains { text.hasSuffix($0) }
            && piece.box.midY > 0.7 && abs(piece.box.midX - 0.5) < 0.12
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
        "通讯录": ("聯絡人", "Contacts"), "微信": ("WeChat", "WeChat"), "浏览器": ("Safari", "Safari"), "录音机": ("語音備忘錄", "Voice Memos"),
        // D40: on the Traditional phone of 11-16 京东 reads "JD" under its icon; Search for 京東 found nothing, 4 s each time.
        "京东": ("JD", "JD")]

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
    /// D218: a name in plain letters (WeChat, Safari, JD), which the board's own keyboard types as it is.
    static func plainLetters(_ s: String) -> Bool {
        !s.isEmpty && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == " ") }
    }

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
        if try await openAppNow(name) {
            AppPlaces.noteOpened(name)
            return true
        }
        if AppPlaces.wasOpened(name) { throw DeviceError(message: "\(name) did not open this time, but it is on this phone") }
        return false
    }

    private func openAppNow(_ name: String) async throws -> Bool {
        let started = now()
        defer { DebugLog.write(String(format: "open %@: %.1f s", name, now() - started)) }
        // The page goHome read to know it was home is the page in front: no second look (build 116).
        var rows: [[CandidatePicker.Piece]]
        if let seen = try await pointer.goHomeRows() {
            rows = seen
        } else {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let read = await homeRows(top: 0.02) else { return try await bySearch(name) }
            rows = read
        }
        // D105: an icon tapped twice for nothing the last time: Search this time (the icon again next time).
        if AppPlaces.takeSearchFirst(name) {
            DebugLog.write("open \(name): its icon was missed last time; Search this time")
            if try await bySearch(name) { return true }
            AppPlaces.noteIcon(name, missed: false)
            guard let read = await homeRows(top: 0.02) else { return false }
            rows = read
        }
        // D21, 134 over the cloud 11-15 (z6): home never came (the Today View), and the page in front was its Screen Time
        // widget, which lists 天氣, WeChat, 行事曆 by name: "open 微信: the page in front" tapped WeChat there and opened
        // Settings › Screen Time, eleven times. A name is tapped as an icon only on a page that looks like the Home Screen.
        if AppPlaces.looksLikeHome(rows), let spot = AppPlaces.label(name, in: rows),
           try await tapIcon(spot, name: name, on: "the page in front") { return true }
        // Not read yet (or the last read got nothing): read the pages, at most every 10 minutes, so a hot phone whose read
        // fails is not made to try again on every open.
        if !AppPlaces.mapped, AppPlaces.looksLikeHome(rows), AppPlaces.mayReadAgain(every: AppPlaces.rereadAfterMiss) {
            AppPlaces.readAgainNow()
            try await mapHomeScreen()
            guard let now = await homeRows(top: 0.02) else { return try await bySearch(name) }
            rows = now
            if let spot = AppPlaces.label(name, in: rows), try await tapIcon(spot, name: name, on: "the page in front") { return true }
        }
        if let target = AppPlaces.page(of: name) {
            if let current = AppPlaces.page(showing: rows), target != current {
                for _ in 0..<abs(target - current) {
                    try await swipePage(next: target > current)
                }
                if let now = await homeRows(top: 0.02), let spot = AppPlaces.label(name, in: now),
                   try await tapIcon(spot, name: name, on: "page \(target + 1), as remembered") {
                    AppPlaces.found(name)
                    return true
                }
            } else if AppPlaces.page(showing: rows) == nil {
                // The page in front was not recognised: it is on a page all the same, so look through them.
                if try await openFromPages(name) { return true }
            }
            // 129 over the cloud 11-13 (g1): the user had moved the apps to the first two pages; the pages remembered were
            // the old ones, and with the Home Screen coming back on another page than the first, 抖音, 淘宝, 拼多多 and
            // 高德 went to page 3, were not there, and opened by Search (22-26 s each, against ~7 s by the icon). A
            // remembered app missing from its page means the apps were moved: read the pages again now (at most every
            // 10 minutes), then open it from what they show.
            if AppPlaces.mayReadAgain(every: AppPlaces.rereadAfterMiss) {
                AppPlaces.readAgainNow()
                DebugLog.write("open \(name): not on page \(target + 1) as remembered; the apps were moved, reading the Home Screen pages again")
                // 131 over the cloud 11-13 (g4): the places were cleared first, the phone was hot and the read got no page
                // ("0 Home Screen page(s) read, 0 names known", 57 s): every app after that went through Search (淘宝 105 s).
                // What is read replaces what was known, name by name; a read that gets nothing loses nothing.
                try await pointer.goHome()
                try await mapHomeScreen()
                try await pointer.goHome()
                if let now = AppPlaces.page(of: name), now != target { return try await openAppNow(name) }
            }
            if AppPlaces.missed(name) >= 2 {
                DebugLog.write("open \(name): not on page \(target + 1) twice in a row; Search from now on")
                AppPlaces.forget(name)
                AppPlaces.found(name)
            } else {
                DebugLog.write("open \(name): not on page \(target + 1) this time; Search this time, the page is kept")
            }
            try await pointer.goHome()
        }
        // D40, user 11-16 ("我不是給他把軟件都放一個頁面了嗎"): on 136, D23 installed 京东 and iOS put it on a page of its own;
        // the Home Screen came back to that page every time, it had only JD on it, no page was known, and all 177 opens of
        // y1 went through Search (10-19 s each, against ~7 s by the icon). A Home Screen page that no read knows means the
        // pages changed: read them again (at most every 10 minutes), then go to the app's page.
        if AppPlaces.looksLikeHome(rows), !AppPlaces.names(rows).isEmpty, AppPlaces.page(showing: rows) == nil,
           AppPlaces.mayReadAgain(every: AppPlaces.rereadAfterMiss) {
            AppPlaces.readAgainNow()
            DebugLog.write("open \(name): the Home Screen page in front is one no read knows; reading the pages again")
            try await mapHomeScreen()
            try await pointer.goHome()
            if AppPlaces.page(of: name) != nil { return try await openAppNow(name) }
        }
        // User 11-12: "爲什麽現在打開抖音還是搜索，爲什麽不是點桌面". The pages were read once (11-09); 抖音 was on none read
        // then and went through Search every time (13–26 s, against ~6 s by its icon), though it was on a page. An app
        // Search opens and no page knows makes the pages be read again, at most once in three days.
        if AppPlaces.page(of: name) == nil, AppPlaces.mapped, AppPlaces.looksLikeHome(rows), AppPlaces.mayReadAgain() {
            AppPlaces.readAgainNow()
            DebugLog.write("open \(name): on no page read so far; reading the Home Screen pages again")
            try await mapHomeScreen()
            try await pointer.goHome()
            if AppPlaces.page(of: name) != nil { return try await openAppNow(name) }
        }
        return try await bySearch(name)
    }

    /// Search; the pages only when Search itself would not work. An app Search does not list is not on the phone (a made-up
    /// name spent 248 s on Search, Safari's suggestions and the pages, over USB 11-09).
    private func bySearch(_ name: String) async throws -> Bool {
        switch try await openBySearch(name) {
        case .opened: return true
        case .absent:
            try await pointer.goHome()
            return false
        case .unusable: return try await openFromPages(name, lastResort: true)  // D74: nothing after it
        }
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
        // 131 (g4): a read that got no page left "mapped" set, and with no name known every app went through Search for
        // the three days until the next read. Only a read that got a page counts.
        if page > 0 { AppPlaces.mapped = true }
        DebugLog.write(String(format: "open: %ld Home Screen page(s) read, %ld names known, %.1f s", page, AppPlaces.count, now() - began))
    }

    /// To the next page, and until it has stopped sliding: a page read in mid-slide was missed (page 3, over USB 11-09).
    private func swipePage(next: Bool) async throws {
        // From the margin: a press on an icon can open it (a swipe from an App Library tile opened Pinduoduo, 11-09).
        try await pointer.swipe(next ? 0.97 : Pointer.leftMargin, 0.5, next ? 0.15 : 0.85, 0.5, hold: false)
        try? await Task.sleep(nanoseconds: 700_000_000)
        await feed.settled(quiet: 0.5, least: 0.1, most: 2)
    }

    /// Only when Search would not work (no keyboard came): the pages to the right up to the App Library, then to the left.
    private func openFromPages(_ name: String, lastResort: Bool = false) async throws -> Bool {
        try await pointer.goHome()
        var (sawHome, readFailed) = (false, false)
        paging: for next in [true, false] {
            for _ in 0..<6 {
                try await swipePage(next: next)
                guard let rows = await homeRows(top: 0.02) else { readFailed = true; break paging }
                if let spot = AppPlaces.label(name, in: rows), !AppPlaces.inLibrary(rows) {
                    return try await tapIcon(spot, name: name, on: "a page, paging")
                }
                if AppPlaces.looksLikeHome(rows) || AppPlaces.inLibrary(rows) { sawHome = true }
                if AppPlaces.inLibrary(rows) || !AppPlaces.looksLikeHome(rows) { break }  // the App Library, or Today's widgets
            }
        }
        // D74, h06 on 138: Codex tapped JD on the Home Screen and 京东 opened; it then said "open 京东", home did not come
        // back (its search box was taken for a search screen six times over), Search took no name, and the pages "read"
        // were 京东's own: the app was "not on this phone", the owner was asked to install it, and the task ended. Only
        // pages that were read and looked like the Home Screen say an app is not there.
        guard !lastResort || Self.absentFromPages(sawHome: sawHome, readFailed: readFailed) else {
            throw DeviceError(message: Self.noHomeToLookIn(name))
        }
        return false
    }

    static func absentFromPages(sawHome: Bool, readFailed: Bool) -> Bool { sawHome && !readFailed }

    static func noHomeToLookIn(_ name: String) -> String {
        name + " did not open this time: the Home Screen did not come up to look for it (Search took no name, and no Home "
            + "Screen page was read), which does not mean it is not on this phone. If it is the app in front, go on in it; "
            + "otherwise go home and open it again."
    }

    /// True once the app has left the Home Screen: a tap that missed reported success, and the model then found itself on
    /// the Home Screen (8 of 27 opens, over USB 11-09). A second try goes through the eye.
    private func tapIcon(_ label: CGPoint, name: String, on place: String) async throws -> Bool {
        DebugLog.write("open \(name): \(place)")
        let icon = AppPlaces.icon(above: label)
        for aimed in [false, true] {
            let home = feed.frame.flatMap(Vision.look)
            try await pointer.tap(icon.x, icon.y, aim: aimed)
            if await Self.leftHome(home, within: 0.9, look: { [weak self] in self?.feed.frame.flatMap(Vision.look) }) {
                // A whole new screen within the 0.9 s it used to wait: the app is coming up, no need to read the page.
                await feed.settled(quiet: 0.8, least: 0.2, most: 4)
                AppPlaces.noteIcon(name, missed: false)
                return true
            }
            guard let rows = await homeRows(top: 0.02), AppPlaces.looksLikeHome(rows), AppPlaces.label(name, in: rows) != nil else {
                await feed.settled(quiet: 0.8, least: 0.2, most: 4)  // an app coming up: the model looks at it once it has
                AppPlaces.noteIcon(name, missed: false)
                return true
            }
            DebugLog.write("open \(name): still on the Home Screen after the tap")
        }
        AppPlaces.noteIcon(name, missed: true)
        return false
    }

    /// Whether the screen became another one than `home` (a look of the Home Screen) within `within` s, checked every
    /// 0.15 s. Opening an app waited 0.9 s and then read the page to see it had gone (build 115: ~2.9 s from the tap).
    /// A pointer or a badge moves too few cells to count. Unknown (no look): false, and the page is read as before.
    static func leftHome(_ home: [UInt8]?, within: Double, look: () -> [UInt8]?) async -> Bool {
        guard let home else {
            try? await Task.sleep(nanoseconds: UInt64(within * 1e9))
            return false
        }
        let started = now()
        while now() - started < within {
            try? await Task.sleep(nanoseconds: 150_000_000)
            if let shown = look(), !Vision.sameScreen(home, shown) { return true }
        }
        return false
    }

    private enum SearchOutcome { case opened, absent, unusable }

    private func openBySearch(_ name: String) async throws -> SearchOutcome {
        // Measured over USB 11-09: Cmd+Space opens Search from the Home Screen (not from inside an app), its last words
        // selected and with the keyboard last used. The pill or a pull down only if it does not come.
        try await pointer.key("cmd+space")
        try? await Task.sleep(nanoseconds: 700_000_000)
        // D20: on the slow phone of 11-15 (z2 21:08, 日历) Search was taken for absent after 0.7 s; it is looked for up to
        // 1.4 s more before the pill or a pull down.
        var shown = await homeRows(top: 0.02)
        let askedAt = now()
        while let rows = shown, !AppPlaces.inSearch(rows), !AppPlaces.keyboardShown(rows), now() - askedAt < 1.4 {
            try? await Task.sleep(nanoseconds: 350_000_000)
            shown = await homeRows(top: 0.02)
        }
        if let rows = shown, !AppPlaces.inSearch(rows), !AppPlaces.keyboardShown(rows) {
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
        // D218, 157 over USB (11-22): on a Traditional phone 微信 was searched as 微信 (its name there is WeChat), and
        // Pilot's keyboard said "已填入：微信" while Spotlight's field stayed empty; "wechat" typed by the board's own
        // keyboard was taken at once. A name in plain letters goes in by the board.
        if AppNames.plainLetters(typed) {
            try await pointer.key("cmd+a")
            try await pointer.key("backspace")
            try await pointer.typeQuick(typed)
        } else {
            guard await showLanAgentKeyboard() else {
                DebugLog.write("open \(name): Search did not take the name")
                return .unusable
            }
            try await pointer.key("cmd+a")
            try await pointer.key("backspace")
            guard await keyboardBridge.type(typed, enter: false, within: 4) else {
                DebugLog.write("open \(name): Search did not take the name")
                return .unusable
            }
        }
        // The results come a moment later; a Return before them opens nothing (over USB, 11-09).
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        var rows: [[CandidatePicker.Piece]] = []
        if let frame = await freshFrame() { rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.02, bottom: 0.7) }
        // D20, 134 over the cloud 11-15 (y5, y6, z1, z2): Search had grown slow. Frames caught over USB (z2 21:14): typed at
        // :39.5, the box said "Safari" at :40.8 with the Siri suggestions still under it, the read at :41.1 found nothing,
        // and "Safari — 打開" came at :41.3. Safari and 備忘錄 were "not on this phone" three times in a row, and four runs
        // of 50 things failed. The results are looked for every 0.4 s for up to 4 s more.
        let waitedFrom = now()
        while !AppPlaces.returnOpens(rows), AppPlaces.searchResult(name, in: rows) == nil, now() - waitedFrom < 4 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if let frame = await freshFrame() { rows = await CandidatePicker.rowsOffMain(in: frame, top: 0.02, bottom: 0.7) }
        }
        if now() - waitedFrom >= 0.4 { DebugLog.write(String(format: "open %@: Search's results looked for %.1f s more", name, now() - waitedFrom)) }
        if AppPlaces.returnOpens(rows) {
            // The keyboard's own Return: the board's Enter does nothing with it up.
            if await !keyboardBridge.type("", enter: true, within: 3) { try await pointer.key("enter") }
            DebugLog.write("open \(name): Return, Search says it opens")
        } else if let spot = AppPlaces.searchResult(name, in: rows) {
            try await pointer.tap(spot.x, spot.y)
            DebugLog.write("open \(name): tapped its Search result")
        } else {
            DebugLog.write("open \(name): not in Search's results")
            return .absent
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if let after = await homeRows(top: 0.02), AppPlaces.inSearch(after) || AppPlaces.looksLikeHome(after) {
            DebugLog.write("open \(name): Search is still up after opening; not opened")
            return .unusable
        }
        await feed.settled(quiet: 0.8, least: 0.2, most: 4)
        return .opened
    }

    private func homeRows(top: Double = 0.07) async -> [[CandidatePicker.Piece]]? {
        guard let frame = await freshFrame() else { return nil }
        return await CandidatePicker.rowsOffMain(in: frame, top: top, bottom: 1)
    }
}
