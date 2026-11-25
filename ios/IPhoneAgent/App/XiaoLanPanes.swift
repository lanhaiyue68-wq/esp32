import UIKit

/// 172 (user 11-25: "我要的是個微和企微都要守候…而且還是要同時兩個都守候"): on the iPad 小藍 watches WeChat and WeCom
/// side by side (iPadOS windowed apps, two tiles), the whole screen shared, both looked at on every pass.
///
/// Which side holds which app, and how wide each is, is read off every frame (user: "不是說每次都固定個人微信就是左邊";
/// "有時候可能左邊寬一些…中間都會有個縫"): the two windows are split at the gap between them, where the wallpaper shows,
/// and each window is told by its tab bar (WeChat: 通讯录 + 发现; WeCom: 工作台, or 邮件 + 文档). A window then reads like
/// a phone screen: everything here works on the window's own picture (its fractions 0–1), and taps are mapped back.
/// Measured on the customer's iPad 9 (11-25, 960 x 1280 frames): the gap 0.494–0.503 wide, the windows from the top to
/// 0.898 (the Dock below); the list title band ~0.058 of the window, row titles from 0.18–0.21 across, the red mark on
/// the avatar's top-right corner ~0.03–0.04 left of and ~0.01 above the title's middle.
@MainActor enum XiaoLanPanes {
    typealias Piece = CandidatePicker.Piece
    enum View: Equatable { case list, chat(String), unknown }

    // MARK: Windows

    /// The windows on the screen, left to right (fractions of the frame): two when a gap splits it, else the whole.
    static func windows(_ px: WatchOCR.Pixels) -> [CGRect] {
        let w = px.w, h = px.h
        guard w > 40, h > 40 else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        func luma(_ x: Int, _ y: Int) -> Int {
            let i = (y * w + x) * 4
            return (Int(px.bytes[i]) * 3 + Int(px.bytes[i + 1]) * 6 + Int(px.bytes[i + 2])) / 10
        }
        // A window's side edge: a sharp change at the same column all the way down (text and avatars never are).
        let ys = stride(from: 0.12, through: 0.85, by: 0.01).map { Int($0 * Double(h)) }
        func edge(_ x: Int) -> Double {
            Double(ys.filter { abs(luma(x, $0) - luma(x - 1, $0)) >= 30 }.count) / Double(ys.count)
        }
        let lo = Int(0.12 * Double(w)), hi = Int(0.88 * Double(w))
        let scored = (lo..<hi).map { (x: $0, s: edge($0)) }.filter { $0.s >= 0.7 }
        // The gap: two such edges close together (the wallpaper between them, 0.3–4% of the width).
        var best: (a: Int, b: Int, s: Double)?
        for e in scored {
            for f in scored where f.x - e.x >= max(2, w * 3 / 1000) && f.x - e.x <= w * 4 / 100 {
                let s = e.s + f.s
                if best == nil || s > best!.s { best = (e.x, f.x, s) }
            }
        }
        guard let gap = best else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        let left = Double(gap.a) / Double(w), right = Double(gap.b) / Double(w)
        let bottom = windowBottom(luma, w: w, h: h, from: 0, to: gap.a)
        return [CGRect(x: 0, y: 0, width: left, height: bottom),
                CGRect(x: right, y: 0, width: 1 - right, height: windowBottom(luma, w: w, h: h, from: gap.b, to: w))]
    }

    /// Where a window ends above the Dock: the first row from 0.75 down that changes sharply nearly all the way across.
    private static func windowBottom(_ luma: (Int, Int) -> Int, w: Int, h: Int, from: Int, to: Int) -> Double {
        let span = to - from
        guard span > 20 else { return 1 }
        let xs = stride(from: from + span / 10, to: to - span / 10, by: max(1, span / 60)).map { $0 }
        var y = Int(0.75 * Double(h))
        while y < h {
            let sharp = xs.filter { abs(luma($0, y) - luma($0, y - 1)) >= 30 }.count
            if Double(sharp) >= 0.7 * Double(xs.count) { return Double(y) / Double(h) }
            y += 1
        }
        return 1
    }

    /// One window's picture, as its own frame.
    static func crop(_ jpeg: Data, _ r: CGRect) -> Data? {
        guard let image = UIImage(data: jpeg)?.cgImage else { return nil }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let rect = CGRect(x: r.minX * full.width, y: r.minY * full.height, width: r.width * full.width,
                          height: r.height * full.height).integral.intersection(full)
        guard !rect.isEmpty, let part = image.cropping(to: rect) else { return nil }
        return UIImage(cgImage: part).jpegData(compressionQuality: 0.92)
    }

    /// A point in a window (its fractions) on the whole screen.
    static func onScreen(_ p: CGPoint, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
    }

    // MARK: What a window shows

    /// The app in a window, by its tab bar (shown on the chat list only).
    static func app(_ rows: [[Piece]]) -> XiaoLanOrders.App? {
        let bar = rows.joined().filter { $0.box.midY > 0.85 }.map(\.text).joined()
        if bar.contains("工作台") || (bar.contains("邮件") && bar.contains("文档")) || (bar.contains("郵件") && bar.contains("文檔")) {
            return .wework
        }
        if (bar.contains("通讯录") || bar.contains("通訊錄")) && (bar.contains("发现") || bar.contains("發現")) { return .wechat }
        return nil
    }

    /// The chat list (its tab bar), a chat (its centred title, no tab bar), or neither.
    static func view(_ rows: [[Piece]]) -> View {
        if app(rows) != nil { return .list }
        if cancelButton(rows) != nil { return .unknown }  // searching: the field's words are no chat's title
        // The first line in the title band: WeCom puts "外部群 | 群主: …" under a group's name (0.071 vs 0.050).
        let lines = rows.map { $0.filter { (0.035...0.09).contains($0.box.midY) && (0.18...0.82).contains($0.box.midX) } }
            .filter { !$0.isEmpty }
            .sorted { ($0.map(\.box.midY).min() ?? 1) < ($1.map(\.box.midY).min() ?? 1) }
        let title = (lines.first ?? []).sorted { $0.box.minX < $1.box.minX }.map(\.text).joined()
            .trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? .unknown : .chat(title)
    }

    /// Where to tap to type: the white field at the bottom of a chat window, found from the bottom up (WeCom's row of
    /// buttons above it, 企业名片 / 快捷回复, is grey-white and left alone). Three columns, two of them white: the hint
    /// text (轻触说话转文字, 发消息或按住…) and WeChat's microphone cover one at most. Tapped left of the middle, on the
    /// hint, clear of the microphone.
    static func inputField(_ px: WatchOCR.Pixels) -> CGPoint? {
        func white(_ y: Double) -> Bool {
            [0.135, 0.50, 0.66].filter { x in
                let (r, g, b) = px.rgb(x, y)
                return r >= 250 && g >= 250 && b >= 250
            }.count >= 2
        }
        let step = 1 / Double(px.h)
        var y = 1 - step, bottom: Double?
        while y > 0.7 {
            if white(y) {
                if bottom == nil { bottom = y }
            } else if let b = bottom {
                if b - y >= 0.015 { return CGPoint(x: 0.30, y: (b + y) / 2) }
                bottom = nil
            }
            y -= step
        }
        return nil
    }

    /// List entries that are no one's chat (WeChat's, and WeCom's own news, team and tools).
    static let notChats: Set<String> = WatchChatOpen.notChats.union(
        ["行业资讯", "行業資訊", "企业微信团队", "企業微信團隊", "企业微信", "通知", "审批", "審批", "打卡", "日程", "会议", "會議",
         "微盘", "微盤", "邮件", "郵件", "汇报", "匯報", "公告", "待办", "待辦"])

    /// A list title as a chat's name: no time read with it, no WeCom tag after it ("外部", "@微信").
    static func listName(_ text: String) -> String {
        var t = WatchChatOpen.withoutTime(text.filter { !$0.isWhitespace })
        for tag in ["外部", "@微信", "＠微信"] where t.hasSuffix(tag) && t.count > tag.count { t = String(t.dropLast(tag.count)) }
        return t
    }

    /// The list rows: a title with a smaller preview line just under it.
    static func entries(_ rows: [[Piece]]) -> [(name: String, box: CGRect)] {
        let body = rows.compactMap { row -> (text: String, box: CGRect)? in
            let pieces = row.filter { (0.12...0.62).contains($0.box.minX) && (0.12...0.92).contains($0.box.midY) }
            guard !pieces.isEmpty else { return nil }
            return (pieces.map(\.text).joined(), pieces.reduce(CGRect.null) { $0.union($1.box) })
        }
        return body.compactMap { t in
            guard body.contains(where: { p in
                (0.015...0.045).contains(p.box.midY - t.box.midY) && abs(p.box.minX - t.box.minX) <= 0.04
            }) else { return nil }
            let name = listName(t.text)
            return name.isEmpty ? nil : (name: name, box: t.box)
        }
    }

    /// Where a row's red mark sits: the avatar's top-right corner, just left of and above the title.
    static func badgeArea(_ title: CGRect) -> CGRect {
        CGRect(x: title.minX - 0.075, y: title.midY - 0.045, width: 0.07, height: 0.05)
    }

    /// The chats with a red mark, top first (fractions of the window): the row to tap.
    static func marked(_ rows: [[Piece]], red: (CGRect) -> Double) -> [(name: String, at: CGPoint)] {
        entries(rows).filter { !notChats.contains($0.name) && red(badgeArea($0.box)) >= WatchChatOpen.badgeShare }
            .sorted { $0.box.midY < $1.box.midY }
            .map { (name: $0.name, at: CGPoint(x: 0.5, y: $0.box.midY)) }
    }

    /// Back from a chat to the list: the arrow at the window's top-left.
    static let back = CGPoint(x: 0.055, y: 0.058)

    // MARK: Search (173, user 11-25: a chat not in view is found by the list's search box, "這不是兩邊都有嗎")

    /// The list's search box.
    static func searchBox(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { p in p.box.midY < 0.25 && ["搜索", "搜尋", "Search"].contains { p.text.contains($0) } }
            .map { CGPoint(x: 0.5, y: $0.box.midY) }
    }

    /// Searching: the 取消 by the search field at the top (no chat has it there).
    static func cancelButton(_ rows: [[Piece]]) -> CGPoint? {
        rows.joined().first { $0.box.midY < 0.13 && ["取消", "Cancel"].contains($0.text.trimmingCharacters(in: .whitespaces)) }
            .map { CGPoint(x: $0.box.midX, y: $0.box.midY) }
    }

    /// The result row named `chat` under the search field, topmost first.
    static func searchResult(_ chat: String, _ rows: [[Piece]]) -> CGPoint? {
        rows.map { row in row.filter { $0.box.minX < 0.75 } }
            .compactMap { row -> (text: String, box: CGRect)? in
                guard !row.isEmpty else { return nil }
                return (listName(row.map(\.text).joined()), row.reduce(CGRect.null) { $0.union($1.box) })
            }
            .filter { (0.12...0.9).contains($0.box.midY) && WatchChatOpen.sameChat(chat, listName: $0.text) }
            .min { $0.box.midY < $1.box.midY }
            .map { CGPoint(x: 0.5, y: $0.box.midY) }
    }
}
