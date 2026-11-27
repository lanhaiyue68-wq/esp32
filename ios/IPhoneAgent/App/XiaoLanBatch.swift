import Foundation

/// 193 (user 11-27, said many times: 「紅點上的數字是幾就只處理最新那幾條，舊訊息一律不回、不點開」; Echo 192 18:03–18:41:
/// lines read long before were answered and opened again — N52 a list preview not matching, N61 media from the whole
/// window, N60 a file card split in two taking a place, N46 no number read and the old guess taken): the one place that
/// says which lines on a chat's window are this time's new ones. What is reported, what media is opened and which
/// questions quoting a message are looked into all come from these lines; nothing else picks lines.
/// - opened by its red mark, its number read: the newest that many lines of others after my last line;
/// - its number not read (a bare dot, or not told apart): what came after the last line read here, and only after my
///   last line; neither on the window: its newest line alone;
/// - open on the window as a line comes in, back on it after a message was looked at, or opened again for its list
///   line (no mark): only what follows the last line read here; nothing going on from it, nothing new.
@MainActor enum XiaoLanBatch {
    enum Opened: Equatable {
        case mark(Int?)  // by its red mark, the number on it when read
        case live        // open on its window (a line came in there, no mark), or back on it after a message's look
        case missed      // opened again for its list line, no mark
    }

    struct Pick { var lines: [WatchReport.Line]; var anchored: Bool; var why: String }

    /// `avatarTops`: the tops of others' avatars on the window, lowest first (XiaoLanMediaFind.avatarTops); `previewY`:
    /// where the line the list's preview showed when the mark was read starts. With them a mark's number counts
    /// messages by their avatars, from that line down (a line OCR gave no words never pulls in an older one; one that
    /// came in after the mark was read is among them).
    static func pick(_ lines: [WatchReport.Line], history: [WatchReport.Line]?, opened: Opened, firstSinceLaunch: Bool = false,
                     seen: Set<String> = [], isEcho: (WatchReport.Line) -> Bool = { _ in false },
                     avatarTops: [Double]? = nil, previewY: Double? = nil, justRead: Bool = false) -> Pick {
        let mineAt = lines.lastIndex { $0.mine }
        let afterMine = mineAt.map { $0 + 1 } ?? 0
        let start = anchor(lines, history: history ?? [])
        func after(_ from: Int, sure: Bool) -> [WatchReport.Line] {
            let tail = Array(lines[min(from, lines.count)...])
            return sure ? tail : tail.filter { !XiaoLanSelf.readBefore($0.text, known: seen) }
        }
        switch opened {
        case .mark(let n?) where n > 0:
            let others = lines[min(afterMine, lines.count)...].filter { !$0.mine && !isEcho($0) }
            // 193 (Echo 193 11-27 21:14): counted by avatars when n of them show above the ones that came after the preview
            if let tops = avatarTops {
                let later = previewY.map { py in tops.filter { $0 > py + 0.005 }.count } ?? 0
                if tops.count >= later + n {
                    let cut = tops[later + n - 1] - 0.008
                    return Pick(lines: others.filter { ($0.y ?? 1) >= cut }, anchored: start != nil,
                                why: "its red mark said \(n), counted by avatars" + (later > 0 ? " (\(later) more came after its preview)" : ""))
                }
            }
            return Pick(lines: Array(others.suffix(n)), anchored: start != nil, why: "its red mark said \(n)")
        case .mark:
            if let start {
                return Pick(lines: after(max(start.index, afterMine), sure: start.sure), anchored: true,
                            why: "no number read on its mark: what came after the last line read")
            }
            if mineAt != nil {
                return Pick(lines: Array(lines[afterMine...].suffix(5)), anchored: false,
                            why: "no number read on its mark: what came after my last line")
            }
            return Pick(lines: Array(lines.filter { !$0.mine && !isEcho($0) }.suffix(1)), anchored: false,
                        why: "no number read on its mark, nothing read before or mine on the window: its newest line")
        case .live, .missed:
            if firstSinceLaunch { return Pick(lines: [], anchored: start != nil, why: "open when watching started, no red mark") }
            // 196 (N88; user 11-28 chose 「回覆前再讀一次」): read again right after a read, before any answer, the last
            // lines of that read are surely still on the window: what comes after them, wherever they are, is new
            if justRead, let end = readEnd(lines, history: history ?? []) {
                return Pick(lines: Array(lines[end...]), anchored: true, why: "read again right after its read")
            }
            guard let start else {
                return Pick(lines: [], anchored: false, why: "nothing on the window goes on from the last line read")
            }
            // 193 (N71, Echo 193 11-27 21:29: 蓝海乐 read with no mark, the last line read found only by an older line of
            // the history (not sure); a lone 「1」 above my two old replies — never read before, OCR had given it no
            // words — was taken for new and answered): found not surely, what is new comes after my last line too
            let from = start.sure ? start.index : max(start.index, afterMine)
            return Pick(lines: after(from, sure: start.sure), anchored: true, why: "after the last line read")
        }
    }

    /// 196 (N88): where the last lines of a read just made (up to three, at least two) show, one after another, on the
    /// window, the lowest such place: the index after them; nil: not shown so.
    static func readEnd(_ lines: [WatchReport.Line], history: [WatchReport.Line]) -> Int? {
        func key(_ l: WatchReport.Line) -> String { XiaoLanSelf.plain(l.text) + (l.mine ? "|me" : "") }
        let k = min(3, history.count)
        guard k >= 2, lines.count >= k else { return nil }
        let want = history.suffix(k).map(key), cur = lines.map(key)
        for i in stride(from: cur.count - k, through: 0, by: -1) where Array(cur[i..<(i + k)]) == want { return i + k }
        return nil
    }

    /// Where the new lines start on the window: after the history's end at its top or anywhere on it (sure); else
    /// after the newest of the history's last eight lines long enough to know (three characters or more) that shows,
    /// the history's later lines right after it skipped (not sure: lines read before are left out of what follows too).
    /// 193 (N52: the history ended on a voice note, 「3"」, too short to find, and its words had come in under it).
    static func anchor(_ lines: [WatchReport.Line], history: [WatchReport.Line]) -> (index: Int, sure: Bool)? {
        guard !history.isEmpty, !lines.isEmpty else { return nil }
        func key(_ l: WatchReport.Line) -> String { XiaoLanSelf.plain(l.text) + (l.mine ? "|me" : "") }
        // the history's end at the window's top (WatchReport.new's way, up to two lines down): two lines or more, or one
        // long one — a single short line (「[语音] 3"」) matches older lines too (N52: the window's third line, an older
        // note of the same length, was taken for the history's end, and the picture and notes after it for new)
        let cur = lines.map(key), old = history.map(key)
        var best: (end: Int, run: Int)?
        for skip in 0...min(2, cur.count) {
            for run in stride(from: min(old.count, cur.count - skip), through: 1, by: -1)
            where Array(old.suffix(run)) == Array(cur[skip..<(skip + run)]) {
                if run > (best?.run ?? 0) { best = (skip + run, run) }
                break
            }
        }
        if let best, best.run >= 2 || XiaoLanSelf.plain(history[history.count - 1].text).count >= 6 { return (best.end, true) }
        if let after = XiaoLanSelf.afterAnchor(lines, history: history) { return (lines.count - after.count, true) }
        for k in stride(from: history.count - 1, through: max(0, history.count - 8), by: -1)
        where XiaoLanSelf.plain(history[k].text).count >= 3 {
            let want = key(history[k])
            guard let i = lines.lastIndex(where: { key($0) == want }) else { continue }
            let later = Set(history[(k + 1)...].map(key))
            var j = i + 1
            while j < lines.count, later.contains(key(lines[j])) { j += 1 }
            return (j, false)
        }
        return nil
    }
}
