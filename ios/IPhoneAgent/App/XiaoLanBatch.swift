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

    static func pick(_ lines: [WatchReport.Line], history: [WatchReport.Line]?, opened: Opened, firstSinceLaunch: Bool = false,
                     seen: Set<String> = [], isEcho: (WatchReport.Line) -> Bool = { _ in false }) -> Pick {
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
            guard let start else {
                return Pick(lines: [], anchored: false, why: "nothing on the window goes on from the last line read")
            }
            return Pick(lines: after(start.index, sure: start.sure), anchored: true, why: "after the last line read")
        }
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
