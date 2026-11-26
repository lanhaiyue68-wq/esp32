import Foundation
import CoreGraphics

/// 188 (user 11-27: 「把這些咱們做的都記住，包括各個按鈕的位置，文件打開的位置，都記在程式裏面…以後換設備了還要能夠
/// 第一時間學習位置，這樣能最快的打開各個地方的按鈕」): where each button of WeChat's and WeCom's pages is.
/// - The places measured on the customer's iPad 9 on 11-27 (docs/plan-188-media.md) are the defaults, kept here in code.
/// - A place that worked on this device (found by its words, or a click there did what it should) is learned, per
///   device model, app and window width, and used first next time; one that missed twice in a row is forgotten, so on
///   another device or another width the place is found again (by its words, or the default tried and checked).
/// Points are fractions of the window (its crop). A `relative` place is an offset from where the long press was (a
/// menu opens by the pressed line).
enum XiaoLanSpots {
    enum Name: String, CaseIterable {
        case playerClose      // the video player's ✕ at the top left (WeCom; WeChat's player is dragged down)
        case pageClose        // a web page's ✕ at the top left (WeChat's 「如需浏览」 page)
        case sheetGrow        // WeChat's file preview sheet: its ∨ left of the title 「预览」 (x; y is the title's)
        case imageClose       // a bare spot of the picture viewer: one click closes it
        case fileClose        // WeCom's file preview 「关闭」
        case filePreview      // WeChat's file page 「预览」
        case menuQuote        // 「引用」 in a message's long-press menu (relative)
        case menuVoiceText    // 「转文字」 in a voice note's long-press menu (relative)
        case menuOpenLink     // 「打开链接」 in a web page's long-press menu (relative)

        var relative: Bool { self == .menuQuote || self == .menuVoiceText || self == .menuOpenLink }
    }

    struct Spot: Equatable {
        var x: Double, y: Double
        var hits = 0, misses = 0
        var learned = false
        var point: CGPoint { CGPoint(x: x, y: y) }
    }

    /// Measured on the customer's iPad 9 (iPadOS 27, WeChat left ~0.49 of the screen, WeCom right ~0.495), 11-27,
    /// turned from screen into window fractions.
    static let defaults: [String: (Double, Double)] = [
        "wework.playerClose": (0.05, 0.053),      // screen (0.529, 0.053)
        "wechat.pageClose": (0.067, 0.052),       // screen (0.033, 0.052)
        "wework.pageClose": (0.02, 0.05),         // WeCom's browser 「<」, screen (0.505, 0.05)
        "wechat.sheetGrow": (0.071, 0),           // screen x 0.035
        "wechat.imageClose": (0.49, 0.15),        // screen (0.24, 0.15)
        "wework.imageClose": (0.495, 0.22),       // screen (0.75, 0.22)
        "wework.fileClose": (0.055, 0.054),       // screen (0.532, 0.054)
        "wechat.filePreview": (0.484, 0.68),      // screen (0.237, 0.68)
        "wechat.menuQuote": (-0.16, -0.055),      // pressed (0.145, 0.614), 引用 (0.067, 0.559)
        "wework.menuQuote": (0.137, -0.117),      // pressed (0.610, 0.760), 引用 (0.678, 0.643)
        "wechat.menuOpenLink": (0.10, 0.05),      // pressed (0.30, 0.252), 打开链接 (0.349, 0.302)
    ]

    static var store: UserDefaults = .standard
    static let storeKey = "xiaolanSpotsV1"

    static let deviceModel: String = {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }()

    /// The window's width as a share of the screen, in steps of 0.05 (a place at a fixed distance from a window's
    /// corner is another fraction of a wider window).
    static func widthStep(_ width: Double) -> Int { Int((width * 20).rounded()) }

    static func key(_ name: Name, app: XiaoLanOrders.App, width: Double, model: String = deviceModel) -> String {
        "\(model)|\(app.rawValue)|\(name.rawValue)|w\(widthStep(width))"
    }

    static func learnedAll() -> [String: [Double]] { store.dictionary(forKey: storeKey) as? [String: [Double]] ?? [:] }

    /// Learned on this device at this width, else the measured default; nil: neither (it is found by its words only).
    static func spot(_ name: Name, app: XiaoLanOrders.App, width: Double, model: String = deviceModel) -> Spot? {
        if let v = learnedAll()[key(name, app: app, width: width, model: model)], v.count == 4 {
            return Spot(x: v[0], y: v[1], hits: Int(v[2]), misses: Int(v[3]), learned: true)
        }
        return defaults["\(app.rawValue).\(name.rawValue)"].map { Spot(x: $0.0, y: $0.1) }
    }

    /// A click there did what it should: kept (averaged with what was learned before, the newest counting most).
    static func learn(_ name: Name, app: XiaoLanOrders.App, width: Double, at p: CGPoint, model: String = deviceModel) {
        let k = key(name, app: app, width: width, model: model)
        var all = learnedAll()
        var (x, y, hits) = (Double(p.x), Double(p.y), 1.0)
        if let v = all[k], v.count == 4 {
            let w = min(v[2], 4)  // the newest place counts at least a fifth
            (x, y, hits) = ((v[0] * w + x) / (w + 1), (v[1] * w + y) / (w + 1), v[2] + 1)
        }
        all[k] = [x, y, hits, 0]
        store.set(all, forKey: storeKey)
    }

    /// A click there did not do what it should: two in a row and the learned place is forgotten (found again next time).
    static func missed(_ name: Name, app: XiaoLanOrders.App, width: Double, model: String = deviceModel) {
        let k = key(name, app: app, width: width, model: model)
        var all = learnedAll()
        guard let v = all[k], v.count == 4 else { return }
        if v[3] >= 1 { all[k] = nil } else { all[k] = [v[0], v[1], v[2], v[3] + 1] }
        store.set(all, forKey: storeKey)
    }

    /// Every place learned on this device forgotten (test channel POST /spots {"reset":true}): found again from scratch.
    static func reset() { store.removeObject(forKey: storeKey) }

    /// The point to click: a relative place added to the pressed spot.
    static func point(_ name: Name, app: XiaoLanOrders.App, width: Double, from pressed: CGPoint? = nil) -> CGPoint? {
        guard let s = spot(name, app: app, width: width) else { return nil }
        guard name.relative else { return s.point }
        guard let pressed else { return nil }
        return CGPoint(x: Double(pressed.x) + s.x, y: Double(pressed.y) + s.y)
    }

    /// What a found point teaches: the point itself, or its offset from the pressed spot.
    static func taught(_ name: Name, found p: CGPoint, from pressed: CGPoint? = nil) -> CGPoint? {
        guard name.relative else { return p }
        guard let pressed else { return nil }
        return CGPoint(x: Double(p.x - pressed.x), y: Double(p.y - pressed.y))
    }
}

/// 188: which order goes next and which mark is opened next, by when things came (pure: tested).
enum PaneTurns {
    /// Of each link's earliest waiting turn, the earliest (its index and turn); nil when one asked earlier still waits
    /// for its QA reply (that one goes first) or nothing waits.
    static func next(firsts: [Int?], asking: [Int?]) -> (index: Int, turn: Int)? {
        let waiting = firsts.enumerated().compactMap { i, f in f.map { (index: i, turn: $0) } }
        guard let best = waiting.min(by: { $0.turn < $1.turn }) else { return nil }
        if let earlier = asking.compactMap({ $0 }).min(), earlier < best.turn { return nil }
        return best
    }

    /// The mark to open first in a window: the one first seen earliest; seen together, the lower row (its chat's last
    /// line is older).
    static func first(_ marks: [(name: String, at: CGPoint)], seen: (String) -> Double) -> (name: String, at: CGPoint)? {
        marks.min { a, b in
            let (sa, sb) = (seen(a.name), seen(b.name))
            return sa != sb ? sa < sb : a.at.y > b.at.y
        }
    }
}
