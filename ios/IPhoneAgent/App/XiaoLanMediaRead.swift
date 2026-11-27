#if XIAOLAN
import Foundation
import UIKit

/// 188: one voice note, video, picture, file or link read in a chat, opened and looked at before it is reported.
struct MediaJob {
    var app: XiaoLanOrders.App
    var side: Int
    var chat: String
    var group: Bool
    var sender: String
    var kind: XiaoLanMediaFind.Kind
    var text: String  // the line as read, or the list preview's (「[语音] 7"」)
    var atMe: Bool
    /// Which of its kind on the window, from the bottom (0: the newest), when several came together.
    var rank = 0
}

/// Frames grabbed while a video plays (main actor only).
@MainActor private final class FrameBox { var frames: [Data] = [] }

/// 188 (user 11-27): 「鏈接點開看，比如抖音快手小紅書鏈接就直接點開…圖片要會看内容，影片要看是什麽還要知道説了什麽，
/// 文件要打開看…語音也要轉文字看到…給別人回消息要引用那條消息回復」. How each opens and closes was measured on the
/// iPad, both apps side by side (docs/plan-188-media.md); where to click comes from XiaoLanMediaFind. A voice note is
/// never played and 「取消转换」 never clicked (user's rule); a picture is never clicked blind (no words to find it by:
/// the chat as it shows goes to the model).
extension AppModel {
    /// The media read in paneRead: each opened, looked at, closed and reported (what was seen, or why not, so the line
    /// is never lost), the other window waiting meanwhile.
    func paneMediaRun(_ state: inout PaneWatchState) async {
        guard !state.media.isEmpty else { return }
        let jobs = state.media
        state.media.removeAll()
        for job in jobs {
            let began = now()
            watchStatus = "看\(XiaoLanMediaFind.label(job.kind))：\(job.chat)…"
            let got = await paneMedia(job)
            // 188 (大藍's joinVoiceText): the words a voice note was turned into show as a line under it next time:
            // kept, so that line is not a new message
            let said = "语音转文字："
            if job.kind == .voice, let seen = got.seen, seen.hasPrefix(said) {
                let key = "\(job.app.rawValue)|\(job.chat)"
                state.echoes[key, default: []].append(String(seen.dropFirst(said.count)))
                if (state.echoes[key]?.count ?? 0) > 20 { state.echoes[key]?.removeFirst() }
                // 189 (N30: 「有优惠吗？」, the words under WeCom's note, went to the server as a line of their own in the
                // same read, and the note after them: two answers): its words reported as a line already, not again
                if state.reportedLines[XiaoLanSelf.plain(String(seen.dropFirst(said.count)))] != nil {
                    DebugLog.write("watch: \(job.app.rawValue): \(job.chat): the voice note's words were reported as a line already; not again")
                    continue
                }
            }
            let text = XiaoLanMediaFind.report(job.text, kind: job.kind, seen: got.seen, failed: got.why)
            let message = ReadMessage(chat: job.chat, group: job.group, sender: job.sender, text: text, atMe: job.atMe)
            ReadLog.append([message])
            watchRead += 1
            (job.app == .wework ? weworkTool : chatTool).report([message])
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): \(job.kind.rawValue) "
                + (got.seen == nil ? "not read (\(got.why ?? "-"))" : "read") + " in \(Int(now() - began)) s; reported")
        }
    }

    func paneMedia(_ job: MediaJob) async -> (seen: String?, why: String?) {
        guard let look = await paneMediaChat(job) else { return (nil, "「\(job.chat)」已经不在窗口里") }
        switch job.kind {
        case .voice: return await paneMediaVoice(job, look)
        case .video: return await paneMediaVideo(job, look)
        case .image: return await paneMediaImage(job, look)
        case .file: return await paneMediaFile(job, look)
        case .link: return await paneMediaLink(job, look)
        }
    }

    // MARK: the chat, back to it, a menu closed

    private func isJobChat(_ l: PaneLook, _ job: MediaJob) -> Bool {
        if case .chat(let t) = l.view { return WatchChatOpen.sameChat(WatchOCR.titled(t).name, listName: job.chat) }
        return false
    }

    /// The job's chat on its window now; nil: another page or chat shows there.
    private func paneMediaChat(_ job: MediaJob, after since: Double? = nil) async -> PaneLook? {
        guard let l = await paneLooks(after: since, side: job.side).first(where: { $0.side == job.side }), isJobChat(l, job) else { return nil }
        return l
    }

    /// Back to the job's chat from a page over it (a file's page, a web page): the window's back arrow, up to `most`
    /// times, until the chat shows. Its list showing, nothing more is clicked.
    @discardableResult
    private func paneMediaBack(_ job: MediaJob, most: Int = 3) async -> Bool {
        for _ in 0..<most {
            guard let l = await paneLooks(after: now(), side: job.side).first(where: { $0.side == job.side }) else { return false }
            if isJobChat(l, job) { return true }
            if l.view == .list { return false }
            guard await paneBackClick(l, job.app.rawValue) else { return false }
        }
        let back = await paneMediaChat(job, after: now()) != nil
        if !back { DebugLog.write("watch: \(job.app.rawValue): \(job.chat): not back on the chat after \(most) back(s)") }
        return back
    }

    /// A long-press menu closed by a click on a bare spot of the chat's right edge; none found, nothing clicked.
    private func paneMediaCloseMenu(_ menu: PaneLook) async {
        guard let spot = XiaoLanMediaFind.blankSpot(menu.rows) else {
            DebugLog.write("watch: a long-press menu open, no bare spot to close it by; left")
            return
        }
        _ = await paneTap(spot, in: menu.rect, wide: 0.02, tall: 0.01)
    }

    /// Pictures (a picture, a video's frames, a web page) to the model; nil: no model, or it said nothing.
    /// 191 (user 11-27: 「搞一個程序，可以自動切換這個模型」): the models of the one key switched by themselves. One
    /// picture: the quick model set in Settings (Seed-2.0-mini) first; a video's frames (three or more): the stronger
    /// sibling (Seed-2.1-lite, Settings.strongerClient) first. One failing, answering nothing, or saying it cannot see
    /// (XiaoLanMediaFind.unsure): the other asked once; both unsure, the longer answer kept.
    func paneMediaLook(_ images: [Data], ask: String) async -> String? {
        guard !images.isEmpty else { return nil }
        let quick: LLMClient?
        do { quick = try await settings.client("actor") } catch {
            DebugLog.write("watch: media: no quick model: \(error.localizedDescription)")
            quick = nil
        }
        let strong = await settings.strongerClient()
        var order = [quick, strong].compactMap { $0 }
        if images.count >= 3, let strong { order = [strong] + [quick].compactMap { $0 } }
        if order.count == 2, order[0].model == order[1].model { order.removeLast() }
        guard !order.isEmpty else {
            DebugLog.write("watch: media: the model did not look: no model set")
            return nil
        }
        var kept: [String] = []
        for (i, client) in order.enumerated() {
            let started = now()
            do {
                let r = try await client.chat(system: XiaoLanMediaFind.lookSystem, text: ask, images: images, maxTokens: 400)
                let t = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                DebugLog.write(String(format: "watch: media: %@ looked at %ld picture(s) in %.1f s", client.model, images.count, now() - started))
                if !t.isEmpty, !XiaoLanMediaFind.unsure(t) { return t }
                if !t.isEmpty { kept.append(t) }
                DebugLog.write("watch: media: \(client.model) answered nothing sure\(i + 1 < order.count ? "; the other model asked" : "")")
            } catch {
                DebugLog.write("watch: media: \(client.model) did not look: \(error.localizedDescription)\(i + 1 < order.count ? "; the other model asked" : "")")
            }
        }
        return kept.max { $0.count < $1.count }
    }

    // MARK: each kind

    /// WeChat: 「转文字」 beside the note. WeCom: the note long-pressed, 「转文字」 in its menu. The words come under the
    /// bubble in a few seconds: what is new on the window then (read twice alike, or the last after 10 s).
    private func paneMediaVoice(_ job: MediaJob, _ look: PaneLook) async -> (seen: String?, why: String?) {
        let before = Array(look.rows.joined())
        // 189 (N30): turned into words already (by the app, or before): those words, nothing clicked
        if let words = XiaoLanMediaFind.convertedWords(before, seconds: XiaoLanMediaFind.noteSeconds(job.text), rank: job.rank) {
            return ("语音转文字：\(words)", nil)
        }
        if job.app == .wechat {
            guard let button = XiaoLanMediaFind.pick(XiaoLanMediaFind.voiceButtons(look.rows), rank: job.rank) else {
                return (nil, "语音旁边没看到「转文字」（可能已经转过）")
            }
            guard await paneTap(button, in: look.rect, wide: 0.03, tall: 0.008) else { return (nil, "「转文字」没点到") }
        } else {
            guard let bubble = XiaoLanMediaFind.pick(XiaoLanMediaFind.voiceSpots(look.rows), rank: job.rank) else {
                return (nil, "没找到语音的泡泡")
            }
            let s = XiaoLanPanes.onScreen(bubble, in: look.rect)
            pointer.aimLoosely(0.03 * Double(look.rect.width), 0.008)
            do { try await pointer.longPress(Double(s.x), Double(s.y), seconds: 0.8) } catch { return (nil, "长按语音失败") }
            guard let menu = await paneLook(job.side, after: now(), tries: 4, until: { l in
                XiaoLanMediaFind.menuItem(l.rows, "转文字") != nil || XiaoLanMediaFind.menuItem(l.rows, "引用") != nil
            }) else { return (nil, "长按语音后没看到菜单") }
            // 转文字 only where its words are read: a place learned or measured could be 取消转换's (never clicked)
            guard let item = XiaoLanMediaFind.menuItem(menu.rows, "转文字") else {
                await paneMediaCloseMenu(menu)
                return (nil, "语音菜单里没有「转文字」（可能已经转过）")
            }
            guard await paneTap(item, in: menu.rect, wide: 0.03, tall: 0.008) else {
                await paneMediaCloseMenu(menu)
                return (nil, "「转文字」没点到")
            }
        }
        var last = ""
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let l = await paneMediaChat(job, after: now()) else { return (nil, "转文字时聊天被换掉了") }
            let words = XiaoLanMediaFind.added(before: before, after: Array(l.rows.joined()),
                                               seconds: XiaoLanMediaFind.noteSeconds(job.text), rank: job.rank)  // 189 (N27/N28)
            if !words.isEmpty && words == last { break }
            last = words
        }
        return last.isEmpty ? (nil, "点了「转文字」，但没读到转出来的字") : ("语音转文字：\(last)", nil)
    }

    /// The thumbnail clicked (over its length label): the player fills the window and plays. Watched and listened to
    /// for its length (three minutes at most): three frames to the model, the sound and subtitles to text
    /// (ScreenListener). Closed: WeCom's ✕ at the top left, WeChat's player dragged down.
    private func paneMediaVideo(_ job: MediaJob, _ look: PaneLook) async -> (seen: String?, why: String?) {
        guard let label = XiaoLanMediaFind.pick(XiaoLanMediaFind.videoLabels(look.rows), rank: job.rank) else {
            return (nil, "没找到视频（缩略图上的时长）")
        }
        guard await paneTap(XiaoLanMediaFind.videoSpot(label), in: look.rect, wide: 0.04, tall: 0.03) else { return (nil, "视频没点到") }
        // 188 night (Echo 188, 11-27 07:09: the player opened, but each of 6 looks first waited for a still screen — a
        // playing video never is — for its full 2.5 s, and the controls with the time had hidden by then; 13 s, "没看到
        // 播放进度"): looked at with no such wait; no time on the second look and the chat gone, one click on the player
        // shows its controls
        var opened: PaneLook?, away: PaneLook?
        for attempt in 0..<4 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let l = await paneLooks(side: job.side).first(where: { $0.side == job.side }) else { continue }
            if XiaoLanMediaFind.playerLength(l.rows) != nil { opened = l; break }
            if !isJobChat(l, job) { away = l }
            if attempt == 1, !isJobChat(l, job) { _ = await paneTap(CGPoint(x: 0.5, y: 0.45), in: l.rect, wide: 0.1, tall: 0.05) }
        }
        // 189 (N34, Echo 189, 11-27 13:12 首爾: WeCom's player opened over 蓝海乐 but its time was never read; 「视频没有
        // 打开」 and closed unseen): the player up (the chat gone) with no time read is watched for the thumbnail's length
        // (10 s when none was read)
        var length = opened.flatMap { XiaoLanMediaFind.playerLength($0.rows) }
        if length == nil, let a = away, await paneMediaChat(job, after: now()) == nil {
            let guess = XiaoLanMediaFind.clockSeconds(job.text) ?? 10
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): the player is up, its time not read; watched for \(guess) s")
            opened = a
            length = guess
        }
        guard let player = opened, let length else {
            if await paneMediaChat(job, after: now()) == nil { await paneMediaCloseVideo(job, rect: look.rect) }
            return (nil, "视频没有打开（没看到播放进度）")
        }
        let span = max(1, min(length, XiaoLanMediaFind.videoMost))
        let rect = player.rect
        let box = FrameBox()
        box.frames.append(player.crop)
        let grab = Task { @MainActor [weak self] in
            for k in 1...2 {
                try? await Task.sleep(nanoseconds: UInt64(Double(span) * Double(k) / 3.0 * 1_000_000_000))
                guard !Task.isCancelled, let frame = self?.feed.frame, let crop = XiaoLanPanes.crop(frame, rect) else { return }
                box.frames.append(crop)
            }
        }
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a video of \(length) s; watched and listened to for \(span) s")
        let heard = await ScreenListener.listen(seconds: Double(span), frame: { self.feed.frame })
        grab.cancel()
        let saw = await paneMediaLook(box.frames, ask: "这是聊天里一个视频（\(length)秒）播放时按时间先后的几张截图，说明视频画面里是什么。")
        await paneMediaCloseVideo(job, rect: rect)
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard saw != nil || !words.isEmpty else { return (nil, "视频打开了，但画面和声音都没读到") }
        var parts = ["时长 \(XiaoLanMediaFind.clock(length))" + (length > span ? "（只看了前 \(span / 60) 分钟）" : "")]
        if let saw { parts.append("画面：\(saw)") }
        if !words.isEmpty { parts.append("说了：\(words)") }
        return (parts.joined(separator: "；"), nil)
    }

    private func paneMediaCloseVideo(_ job: MediaJob, rect: CGRect) async {
        if job.app == .wework {
            // the ✕ where it worked on this device, else where it was measured; learned or forgotten by what it did
            let width = Double(rect.width)
            let at = XiaoLanSpots.point(.playerClose, app: .wework, width: width) ?? XiaoLanMediaFind.weworkPlayerClose
            _ = await paneSeenTap(XiaoLanPanes.onScreen(at, in: rect), half: (0.015, 0.012))
            if await paneMediaChat(job, after: now()) != nil {
                XiaoLanSpots.learn(.playerClose, app: .wework, width: width, at: at)
                return
            }
            XiaoLanSpots.missed(.playerClose, app: .wework, width: width)
        } else {
            let a = XiaoLanPanes.onScreen(CGPoint(x: 0.5, y: 0.35), in: rect)
            let b = XiaoLanPanes.onScreen(CGPoint(x: 0.5, y: 0.75), in: rect)
            do { try await pointer.swipe(Double(a.x), Double(a.y), Double(b.x), Double(b.y), hold: false) } catch {
                DebugLog.write("watch: wechat: the player not dragged down: \(error.localizedDescription)")
            }
        }
        if await paneMediaChat(job, after: now()) == nil {
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): the player still up after its close; back")
            await paneMediaBack(job, most: 2)
        }
    }

    /// The picture found as a block beside its sender's avatar (XiaoLanMediaFind.pictureBlocks), clicked: the viewer
    /// fills the window, larger than the thumbnail, its words readable (measured 11-27 on both apps); looked at by the
    /// model, its words read, then closed by one click on its bare part (learned per device). Not found, or not opened:
    /// the chat as it shows goes to the model instead, nothing clicked.
    private func paneMediaImage(_ job: MediaJob, _ look: PaneLook) async -> (seen: String?, why: String?) {
        let thumb = "这是聊天窗口的截图。只说明最下面（最新）那张别人发来的图片的内容，不要复述聊天文字。"
        func fromThumbnail(_ why: String) async -> (seen: String?, why: String?) {
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): picture \(why); the chat's thumbnail looked at instead")
            guard let saw = await paneMediaLook([look.crop], ask: thumb) else { return (nil, "大模型没有看图（没设模型或调用失败）") }
            return ("图片内容：\(saw)", nil)
        }
        let words = look.rows.joined().map { WatchOCR.Piece(text: $0.text, box: $0.box, kind: .other) }
        guard let px = WatchOCR.Pixels(look.crop),
              let block = XiaoLanMediaFind.pick(XiaoLanMediaFind.pictureBlocks(px, pieces: words, top: 0.09, bottom: 0.93), rank: job.rank)
        else { return await fromThumbnail("not found as a block") }
        let width = Double(look.rect.width)
        let author = XiaoLanMediaFind.cardAuthor(look.rows, in: block)  // 191: a 视频号 card's
        _ = await paneMediaKeyboardDown(job)
        guard await paneTap(CGPoint(x: block.midX, y: block.midY), in: look.rect, wide: Double(block.width) / 3, tall: Double(block.height) / 3),
              let viewer = await paneLook(job.side, after: now(), tries: 6, until: { !self.isJobChat($0, job) }), !isJobChat(viewer, job)
        else { return await fromThumbnail("not opened") }
        try? await Task.sleep(nanoseconds: 800_000_000)  // the full picture loads
        let shown = await paneLooks(after: now(), side: job.side).first { $0.side == job.side } ?? viewer
        if let author, XiaoLanMediaFind.channelsPlayer(shown.rows, author: author) {
            return await paneMediaChannels(job, shown, author: author)
        }
        let text = XiaoLanMediaFind.pageText(shown.rows, from: 0.06, most: 300)
        let saw = await paneMediaLook([shown.crop], ask: "这是聊天里点开放大的一张图片，说明图片的内容。")
        // one click on its bare part closes it (where it worked here, else where it was measured); else the back
        if let at = XiaoLanSpots.point(.imageClose, app: job.app, width: width) {
            _ = await paneTap(at, in: shown.rect, wide: 0.05, tall: 0.03)
            if await paneMediaChat(job, after: now()) != nil {
                XiaoLanSpots.learn(.imageClose, app: job.app, width: width, at: at)
            } else {
                XiaoLanSpots.missed(.imageClose, app: job.app, width: width)
                await paneMediaBack(job)
            }
        } else {
            await paneMediaBack(job)
        }
        guard saw != nil || !text.isEmpty else { return (nil, "图片打开了，但没看出内容（没设模型或调用失败）") }
        var parts: [String] = []
        if let saw { parts.append("图片内容：\(saw)") }
        if !text.isEmpty { parts.append("图上文字：\(text)") }
        return (parts.joined(separator: "；"), nil)
    }

    /// 191 (N37, measured 11-27 15:18: a 视频号 card clicked, its player over the window, black, playing by itself, no
    /// time shown; its words at the bottom — the title 「楼下录口播呢…」, the author, the counts — and 「<」 at the top
    /// left): watched and listened to, then back by 「<」.
    private func paneMediaChannels(_ job: MediaJob, _ player: PaneLook, author: String) async -> (seen: String?, why: String?) {
        let title = XiaoLanMediaFind.pageText(player.rows.map { row in row.filter { Double($0.box.midY) > 0.75 } }, from: 0.75, most: 200)
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a 视频号 video of \(author); watched and listened to for \(XiaoLanMediaFind.pageVideoMost) s")
        let watched = await paneMediaWatch(rect: player.rect, seconds: XiaoLanMediaFind.pageVideoMost)
        let saw = await paneMediaLook([player.crop] + watched.frames,
                                      ask: "这是聊天里点开的一个视频号视频播放时按时间先后的几张截图，说明视频画面里是什么。")
        await paneMediaBack(job)
        var parts = ["视频号（\(author)）"]
        if !title.isEmpty { parts.append("标题和文字：\(title)") }
        if let saw { parts.append("画面：\(saw)") }
        if !watched.heard.isEmpty { parts.append("说了：\(watched.heard)") }
        guard parts.count > 1 else { return (nil, "视频号视频打开了，但画面和声音都没读到（\(author)）") }
        return (parts.joined(separator: "；"), nil)
    }

    /// WeCom: the card opens a preview on the window, 「关闭」 at its top left. WeChat: the file's page (预览, 下载) →
    /// 预览 → a sheet rising, whose ∨ at the top left once makes it the whole page; two backs to the chat. The words
    /// read off the page (OCR) are its content.
    private func paneMediaFile(_ job: MediaJob, _ look: PaneLook) async -> (seen: String?, why: String?) {
        guard let card = XiaoLanMediaFind.fileCard(look.rows, hint: job.text) else { return (nil, "没找到文件卡片") }
        guard await paneTap(card, in: look.rect, wide: 0.1, tall: 0.01) else { return (nil, "文件没点到") }
        var words = ""
        let width = Double(look.rect.width)
        if job.app == .wework {
            guard let page = await paneLook(job.side, after: now(), tries: 8, until: { XiaoLanMediaFind.button($0.rows, "关闭", bottom: 0.12) != nil }),
                  XiaoLanMediaFind.button(page.rows, "关闭", bottom: 0.12) != nil else {
                await paneMediaBack(job)
                return (nil, "文件没有打开")
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)  // the document draws
            let shown = await paneLooks(after: now(), side: job.side).first { $0.side == job.side } ?? page
            words = XiaoLanMediaFind.pageText(shown.rows, from: 0.08)
            // 关闭 where its words are read (kept for this device), else where it was learned or measured
            let found = XiaoLanMediaFind.button(shown.rows, "关闭", bottom: 0.12)
            if let close = found ?? XiaoLanSpots.point(.fileClose, app: .wework, width: width) {
                _ = await paneTap(close, in: shown.rect, wide: 0.03, tall: 0.01)
                if await paneMediaChat(job, after: now()) != nil {
                    XiaoLanSpots.learn(.fileClose, app: .wework, width: width, at: close)
                } else {
                    if found == nil { XiaoLanSpots.missed(.fileClose, app: .wework, width: width) }
                    await paneMediaBack(job)
                }
            } else {
                await paneMediaBack(job)
            }
        } else {
            guard let info = await paneLook(job.side, after: now(), tries: 8, until: { XiaoLanMediaFind.button($0.rows, "预览", top: 0.4) != nil }),
                  let preview = XiaoLanMediaFind.button(info.rows, "预览", top: 0.4) else {
                await paneMediaBack(job)
                return (nil, "文件没有打开（没看到「预览」）")
            }
            XiaoLanSpots.learn(.filePreview, app: .wechat, width: width, at: preview)  // where WeChat's file page puts it here
            if await paneTap(preview, in: info.rect, wide: 0.04, tall: 0.01),
               let sheet = await paneLook(job.side, after: now(), tries: 6, until: { XiaoLanMediaFind.button($0.rows, "预览", bottom: 0.3) != nil }),
               let title = XiaoLanMediaFind.button(sheet.rows, "预览", bottom: 0.3) {
                // 188 night (Echo 188, 11-27 06:05: the ∨ closed a preview already shown in full, and the file's page was
                // read instead): what the preview shows is read first; the ∨ only when it shows little, and its page kept
                // only when it shows more
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                let first = await paneLooks(after: now(), side: job.side).first { $0.side == job.side } ?? sheet
                words = XiaoLanMediaFind.pageText(first.rows, from: Double(title.y) + 0.03)
                if words.split(separator: "\n").count < 3 {
                    let grow = XiaoLanSpots.point(.sheetGrow, app: .wechat, width: width).map { Double($0.x) } ?? XiaoLanMediaFind.wechatSheetGrow
                    _ = await paneTap(CGPoint(x: grow, y: Double(title.y)), in: sheet.rect, wide: 0.02, tall: 0.01)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let shown = await paneLooks(after: now(), side: job.side).first { $0.side == job.side } ?? first
                    let more = XiaoLanMediaFind.pageText(shown.rows, from: 0.08)
                    let filePage = more.contains("文件大小") && more.contains("下载")
                    if !filePage, more.count > words.count { words = more }
                }
            }
            await paneMediaBack(job)
        }
        let name = XiaoLanMediaFind.fileName(job.text) ?? ""
        let named = name.isEmpty ? "" : "文件名：\(name)；"
        guard !words.isEmpty else { return (nil, "\(named)文件打开了，但没读到里面的字") }
        return ("\(named)内容：\(words)", nil)
    }

    /// The address's own line clicked: the app's browser over the chat; its words and a look by the model, then back
    /// (up to three backs). 191 (Echo 190, 11-27 首爾 15:06–15:18, the owner's four shares measured by hand):
    /// - N29: 小藍's keyboard left up after a reply took the link's first click (the second opened it): put down first,
    ///   and a click that opens nothing is made once more on the address's start;
    /// - N38: the line clicked is the job's own (its address read alike), not the rank's (Kuaishou's report, Xiaohongshu's
    ///   line clicked);
    /// - N37: a folded share (「…更多」) opened to its full text and its blue address clicked there; an address WeChat left
    ///   unlinked (Kuaishou's, black even in the full text) copied by WeChat's 「复制」 and opened in Safari;
    /// - a page that only sends you to the app (Douyin's 「抱歉出错了」) opened in Safari by its ··· 「用默认浏览器打开」; a
    ///   page with a video (Xiaohongshu's) started by a click on it, watched and listened to.
    private func paneMediaLink(_ job: MediaJob, _ look: PaneLook) async -> (seen: String?, why: String?) {
        var chat = look
        if await paneMediaKeyboardDown(job), let again = await paneMediaChat(job, after: now()) { chat = again }
        guard var piece = XiaoLanMediaFind.linkLine(chat.rows, text: job.text, rank: job.rank) else {
            return (nil, "没在聊天里找到网址")
        }
        let url = XiaoLanMediaFind.url(in: job.text) ?? XiaoLanMediaFind.url(in: piece.text) ?? ""
        if let more = XiaoLanMediaFind.moreSpot(chat.rows, from: piece) {
            let r = await paneMediaFolded(job, chat, more: more, url: url)
            await paneMediaEnsureChat(job)
            return r
        }
        var opened: PaneLook?
        for attempt in 0..<2 {
            let first = attempt == 0
            let spot = first ? CGPoint(x: Double(piece.box.midX), y: Double(piece.box.midY)) : XiaoLanMediaFind.addressStart(piece)
            let wide = first ? min(0.2, Double(piece.box.width) / 2) : min(0.01, Double(piece.box.width) / 8)
            guard await paneTap(spot, in: chat.rect, wide: wide, tall: 0.006) else { return (nil, "网址没点到") }
            if let p = await paneLook(job.side, after: now(), tries: first ? 8 : 6, until: { !self.isJobChat($0, job) }),
               !isJobChat(p, job) {
                opened = p
                break
            }
            guard first, let again = await paneMediaChat(job, after: now()),
                  let next = XiaoLanMediaFind.linkLine(again.rows, text: job.text, rank: job.rank) else { break }
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): the link's click opened nothing (\(url)); clicked again on its start")
            (chat, piece) = (again, next)
        }
        guard let page = opened else { return await paneMediaCopyToSafari(job, chat, piece, url: url) }
        let r = await paneMediaPage(job, page, url: url)
        await paneMediaEnsureChat(job)
        return r
    }

    /// 191 (N29): 小藍's keyboard put down before a message is clicked; true when it was up.
    private func paneMediaKeyboardDown(_ job: MediaJob) async -> Bool {
        guard keyboardBridge.onScreen() else { return false }
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): 小藍's keyboard up before a message's click; put down first")
        _ = await keyboardBridge.type("", enter: false, within: 1.5, dismiss: true)
        _ = await smallKeyboard(up: false, within: 1.0)
        return true
    }

    /// 191: back on the job's chat — back arrows (paneMediaBack), then a full text (white, no title bar) closed by a
    /// click on its bare bottom. A list, or anything with a title bar, is left alone.
    private func paneMediaEnsureChat(_ job: MediaJob) async {
        if await paneMediaChat(job, after: now()) != nil { return }
        if await paneMediaBack(job) { return }
        guard let l = await paneLooks(after: now(), side: job.side).first(where: { $0.side == job.side }), !isJobChat(l, job),
              l.view != .list, !l.rows.joined().contains(where: { Double($0.box.midY) < 0.08 }) else { return }
        _ = await paneTap(CGPoint(x: 0.5, y: 0.9), in: l.rect, wide: 0.05, tall: 0.02)
        if await paneMediaChat(job, after: now()) == nil {
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): not back on the chat after a message's full text")
        }
    }

    /// 191 (N37, measured 11-27 15:12–15:16): 「更多」 opens the whole message over the window (white, no title bar).
    /// Douyin's address there is blue, a link, and opens its page; Kuaishou's is black, plain words, and a click on it
    /// only closes the text: then WeChat's own copy of the message goes to Safari.
    private func paneMediaFolded(_ job: MediaJob, _ chat: PaneLook, more: CGPoint, url: String) async -> (seen: String?, why: String?) {
        guard await paneTap(more, in: chat.rect, wide: 0.006, tall: 0.005),
              let opened = await paneLook(job.side, after: now(), tries: 6, until: { !self.isJobChat($0, job) }), !isJobChat(opened, job) else {
            return (nil, "点了「更多」，全文没有打开")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let full = await paneLooks(after: now(), side: job.side).first { $0.side == job.side } ?? opened
        let words = XiaoLanMediaFind.pageText(full.rows, from: 0.02, most: 400)
        let address = XiaoLanMediaFind.url(in: words) ?? url
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a folded message opened to its full text (\(address))")
        func withWords(_ r: (seen: String?, why: String?)) -> (seen: String?, why: String?) {
            guard !words.isEmpty else { return r }
            if let seen = r.seen { return ("全文：\(words)；\(seen)", nil) }
            return (nil, "\(r.why ?? "")（全文：\(words)）")
        }
        guard let line = Array(full.rows.joined()).first(where: { $0.text.range(of: "http", options: .caseInsensitive) != nil }) else {
            await paneMediaEnsureChat(job)
            return words.isEmpty ? (nil, "全文没读到字") : ("全文：\(words)（里面没有网址）", nil)
        }
        let before = Set(full.rows.joined().map(\.text))
        guard await paneTap(XiaoLanMediaFind.addressStart(line), in: full.rect, wide: 0.006, tall: 0.005) else {
            return withWords((nil, "全文里的网址没点到"))
        }
        // a page over it (none of the full text's words), or the chat again (no link there: the click closed the text)
        let after = await paneLook(job.side, after: now(), tries: 8, until: { l in
            self.isJobChat(l, job) || (!l.rows.isEmpty && !l.rows.joined().contains { before.contains($0.text) })
        })
        if let page = after, !isJobChat(page, job), !page.rows.joined().contains(where: { before.contains($0.text) }) {
            return withWords(await paneMediaPage(job, page, url: address))
        }
        await paneMediaEnsureChat(job)
        guard let again = await paneMediaChat(job, after: now()),
              let piece = XiaoLanMediaFind.linkLine(again.rows, text: job.text, rank: job.rank) else {
            return withWords((nil, "全文里的网址点不开，回聊天后没找到那条消息"))
        }
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): the full text's address is no link (\(address)); copied instead")
        return withWords(await paneMediaCopyToSafari(job, again, piece, url: address))
    }

    /// A link's page opened over the chat: read (WeChat's blocked or app-only page: in Safari), then back.
    private func paneMediaPage(_ job: MediaJob, _ page: PaneLook, url: String) async -> (seen: String?, why: String?) {
        try? await Task.sleep(nanoseconds: 2_500_000_000)  // the page loads
        let shown = await paneLooks(after: now(), side: job.side).first { $0.side == job.side } ?? page
        // 188 (user 11-27: 「出現現在這個畫面就複製下來去瀏覽器看」): WeChat would not open it → Safari
        if job.app == .wechat, XiaoLanMediaFind.linkBlocked(shown.rows) {
            return await paneMediaSafari(job, shown, url: url)
        }
        // 191 (user 11-27: 「點開過后…右上角那個三個點…選擇那個瀏覽器打開」)
        if job.app == .wechat, XiaoLanMediaFind.appOnlyPage(shown.rows) {
            return await paneMediaDefaultBrowser(job, shown, url: url)
        }
        let words = XiaoLanMediaFind.pageText(shown.rows, from: 0.04, most: 500)
        var parts: [String] = []
        var frames = [shown.crop]
        // 191 (user 11-27: 「中間有一個那個播放的按鈕，你點一下它就可以播放」)
        if let spot = XiaoLanMediaFind.pageVideoSpot(shown.rows) {
            _ = await paneTap(spot, in: shown.rect, wide: 0.05, tall: 0.03)
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a video on the page; played, watched and listened to for \(XiaoLanMediaFind.pageVideoMost) s")
            let watched = await paneMediaWatch(rect: shown.rect, seconds: XiaoLanMediaFind.pageVideoMost)
            frames += watched.frames
            if !watched.heard.isEmpty { parts.append("视频说了：\(watched.heard)") }
        }
        let saw = await paneMediaLook(frames, ask: "这是聊天里点开的链接网页（\(url)）的截图（有视频时是播放中按时间先后的几张），说明网页的标题和主要内容。")
        await paneMediaBack(job)
        if let saw { parts.insert("网页：\(saw)", at: 0) }
        if !words.isEmpty { parts.append("网页文字：\(words)") }
        guard !parts.isEmpty else { return (nil, "网页打开了，但没读到内容（\(url)）") }
        return (parts.joined(separator: "；"), nil)
    }

    /// Watched and listened to for `seconds`: the sound and subtitles to text (ScreenListener), two frames of `rect` on
    /// the way.
    private func paneMediaWatch(rect: CGRect, seconds: Int) async -> (heard: String, frames: [Data]) {
        let box = FrameBox()
        let grab = Task { @MainActor [weak self] in
            for k in 1...2 {
                try? await Task.sleep(nanoseconds: UInt64(Double(seconds) * Double(k) / 3.0 * 1_000_000_000))
                guard !Task.isCancelled, let frame = self?.feed.frame, let crop = XiaoLanPanes.crop(frame, rect) else { return }
                box.frames.append(crop)
            }
        }
        let heard = await ScreenListener.listen(seconds: Double(seconds), frame: { self.feed.frame })
        grab.cancel()
        return (heard.trimmingCharacters(in: .whitespacesAndNewlines), box.frames)
    }

    /// 191 (measured 11-27 15:12, Douyin's 「抱歉出错了」 page): its ··· at the window's top right; 「用默认浏览器打开」 at
    /// the end of the menu's first row, its label cut by the window's edge, its icon over it; Safari over the whole
    /// screen ~5 s after, the page there with its player (「00:00 / 03:01」). Read there (paneSafariRead).
    private func paneMediaDefaultBrowser(_ job: MediaJob, _ page: PaneLook, url: String) async -> (seen: String?, why: String?) {
        let title = page.rows.joined().filter { Double($0.box.midY) < 0.09 }.min { $0.box.midY < $1.box.midY }
        let dots = CGPoint(x: 0.93, y: title.map { Double($0.box.midY) } ?? 0.06)
        guard await paneTap(dots, in: page.rect, wide: 0.01, tall: 0.006),
              let menu = await paneLook(job.side, after: now(), tries: 5, until: { XiaoLanMediaFind.defaultBrowserItem($0.rows) != nil }),
              let item = XiaoLanMediaFind.defaultBrowserItem(menu.rows) else {
            await paneMediaCancelSheet(job)
            await paneMediaBack(job)
            return (nil, "网页要在 App 里看，「···」里没找到「用默认浏览器打开」（\(url)）")
        }
        let icon = CGPoint(x: min(Double(item.box.minX) + 0.03, 0.97), y: Double(item.box.midY) - 0.045)
        _ = await paneTap(icon, in: menu.rect, wide: 0.01, tall: 0.01)
        guard let shown = await paneSafariFrame(most: 10) else {
            await paneMediaCancelSheet(job)
            await paneMediaBack(job)
            return (nil, "点了「用默认浏览器打开」，Safari 没有出来（\(url)）")
        }
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a page only for its app, opened in Safari by ··· (\(url))")
        return await paneSafariRead(job, url: url, shown: shown)
    }

    /// A ··· sheet left up: its 「取消」.
    private func paneMediaCancelSheet(_ job: MediaJob) async {
        guard let l = await paneLooks(after: now(), side: job.side).first(where: { $0.side == job.side }),
              let cancel = XiaoLanMediaFind.button(l.rows, "取消") else { return }
        _ = await paneTap(cancel, in: l.rect, wide: 0.03, tall: 0.008)
    }

    /// WeChat's 「如需浏览，请长按网址复制后使用浏览器访问」 (measured 11-27): the address pressed long, 「打开链接」 in its
    /// menu opens Safari over the whole screen (no copying needed; copying works too: from 「https」, Shift+Cmd+→,
    /// Cmd+C). Read there — its words, a look by the model, and a video on it played and listened to — then WeChat and
    /// WeCom called back side by side (paneRecall: 辅助触控 → the Dock's WeCom → WeChat) and the page closed by its ✕.
    private func paneMediaSafari(_ job: MediaJob, _ page: PaneLook, url: String) async -> (seen: String?, why: String?) {
        let width = Double(page.rect.width)
        guard let address = XiaoLanMediaFind.addressLine(page.rows) else {
            await paneMediaClosePage(job)
            return (nil, "微信挡了这个链接，页面上没找到网址（\(url)）")
        }
        let pressed = CGPoint(x: address.box.midX, y: address.box.midY)
        let s = XiaoLanPanes.onScreen(pressed, in: page.rect)
        pointer.aimLoosely(0.05 * Double(page.rect.width), 0.008)
        do { try await pointer.longPress(Double(s.x), Double(s.y), seconds: 0.9) } catch {
            await paneMediaClosePage(job)
            return (nil, "微信挡了这个链接，长按网址失败")
        }
        let menu = await paneLook(job.side, after: now(), tries: 4, until: { XiaoLanMediaFind.menuItem($0.rows, "打开链接") != nil })
        let found = menu.flatMap { XiaoLanMediaFind.menuItem($0.rows, "打开链接") }
        // a missed 打开链接 opens 翻译 or 搜一搜 at worst (nothing is lost): the learned or measured place is tried
        guard let open = found ?? XiaoLanSpots.point(.menuOpenLink, app: .wechat, width: width, from: pressed) else {
            await paneMediaClosePage(job)
            return (nil, "微信挡了这个链接，长按网址后没看到「打开链接」")
        }
        _ = await paneTap(open, in: page.rect, wide: 0.03, tall: 0.008)
        // Safari over the whole screen within ~8 s, its page loaded ~4 s after (measured 11-27)
        guard let shown = await paneSafariFrame() else {
            if found == nil { XiaoLanSpots.missed(.menuOpenLink, app: .wechat, width: width) }
            await paneMediaClosePage(job)
            return (nil, "微信挡了这个链接，点「打开链接」后 Safari 没有出来（\(url)）")
        }
        if let taught = XiaoLanSpots.taught(.menuOpenLink, found: open, from: pressed) {
            XiaoLanSpots.learn(.menuOpenLink, app: .wechat, width: width, at: taught)
        }
        DebugLog.write("watch: wechat: \(job.chat): a link WeChat would not open, opened in Safari (\(url))")
        return await paneSafariRead(job, url: url, shown: shown)
    }

    /// Safari over the screen (its name, or with `link` its domain, at the top), looked for each second; nil after `most`.
    private func paneSafariFrame(link: String? = nil, most: Int = 8) async -> Data? {
        for _ in 0..<most {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let f = feed.frame else { continue }
            let top = await CandidatePicker.rowsOffMain(in: f, top: 0, bottom: 0.08)
            if XiaoLanMediaFind.safariShown(top, link: link) { return f }
        }
        return nil
    }

    /// 191 (N29, N37; user 188: 「點不開就複製鏈接到瀏覽器打開看」): the address WeChat or WeCom left unopened (Kuaishou's,
    /// never a link in WeChat). Its message pressed long, 「复制」 in the bubble's menu (the app's own copy of the whole
    /// message: an address is never copied off the OCR), the address taken from that copy, and Safari opened on it by
    /// Echo. Nothing is read unless the pasteboard took a new copy. iOS asks the first time (「允许粘贴」); after that
    /// 设置 › Echo › 从其他 App 粘贴 shows, set to 允许 (it is not listed before the first ask).
    private func paneMediaCopyToSafari(_ job: MediaJob, _ chat: PaneLook, _ piece: CandidatePicker.Piece, url: String) async -> (seen: String?, why: String?) {
        let failed = "点了网址没有打开（\(url)）"
        let pressed = XiaoLanPanes.onScreen(CGPoint(x: piece.box.midX, y: piece.box.midY), in: chat.rect)
        let before = await MainActor.run { UIPasteboard.general.changeCount }
        pointer.aimLoosely(0.03 * Double(chat.rect.width), 0.008)
        do { try await pointer.longPress(Double(pressed.x), Double(pressed.y), seconds: 0.8) } catch {
            return (nil, failed + "，长按网址也失败")
        }
        guard let menu = await paneLook(job.side, after: now(), tries: 4, until: { XiaoLanMediaFind.copyItem($0.rows) != nil }),
              let copy = XiaoLanMediaFind.copyItem(menu.rows) else {
            if let l = await paneLooks(after: now(), side: job.side).first(where: { $0.side == job.side }) { await paneMediaCloseMenu(l) }
            return (nil, failed + "，长按后没看到「复制」")
        }
        guard await paneTap(copy, in: menu.rect, wide: 0.02, tall: 0.008) else {
            await paneMediaCloseMenu(menu)
            return (nil, failed + "，「复制」没点到")
        }
        var copied = false
        for _ in 0..<6 where !copied {
            try? await Task.sleep(nanoseconds: 250_000_000)
            copied = await MainActor.run { UIPasteboard.general.changeCount } != before
        }
        guard copied else { return (nil, failed + "，复制网址没成功") }
        let copiedText = await MainActor.run { UIPasteboard.general.string }
        guard let copiedText else {
            return (nil, failed + "，复制了但小蓝读不到剪贴板（iPad 设置 › Echo › 从其他 App 粘贴 › 允许）")
        }
        guard let address = XiaoLanMediaFind.url(in: copiedText), let start = XiaoLanMediaFind.safariURL(address) else {
            return (nil, failed + "，复制的消息里没有网址")
        }
        // x-safari- not taken: the plain address (the default browser, Safari unless changed)
        var safari = await UIApplication.shared.open(start)
        if !safari, let plain = URL(string: String(start.absoluteString.dropFirst("x-safari-".count))) {
            safari = await UIApplication.shared.open(plain)
        }
        guard safari else { return (nil, failed + "，小蓝打不开 Safari") }
        guard let shown = await paneSafariFrame(link: address, most: 10) else {
            await paneBackSideBySide(job)
            return (nil, failed + "，Safari 没有出来")
        }
        DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a link not opened in the chat, copied and opened in Safari (\(address))")
        return await paneSafariRead(job, url: address, shown: shown)
    }

    /// Safari's page read (its loading ~4 s waited for): a video on it played and listened to, its words, a look by the
    /// model; then WeChat and WeCom called back side by side and WeChat's page, if one, closed.
    private func paneSafariRead(_ job: MediaJob, url: String, shown: Data) async -> (seen: String?, why: String?) {
        var rows: [[CandidatePicker.Piece]] = []
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let frame: Data? = feed.frame ?? shown
        if let f = frame { rows = await CandidatePicker.rowsOffMain(in: f, top: 0.06, bottom: 1) }
        var parts: [String] = []
        // a video on the page (its time 「00:01/01:42」): played from its ▶ (left of the time) and listened to
        if let length = XiaoLanMediaFind.playerLength(rows),
           let time = rows.joined().first(where: { $0.text.contains("/") && XiaoLanMediaFind.playerLength([[$0]]) != nil }) {
            let span = max(1, min(length, XiaoLanMediaFind.videoMost))
            let play = CGPoint(x: max(0.01, Double(time.box.minX) - 0.025), y: Double(time.box.midY))
            pointer.aimLoosely(0.012, 0.008)
            try? await pointer.tap(Double(play.x), Double(play.y), aim: false)
            DebugLog.write("watch: \(job.app.rawValue): \(job.chat): a video of \(length) s in Safari; played and listened to for \(span) s")
            let heard = await ScreenListener.listen(seconds: Double(span), frame: { self.feed.frame })
            let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append("视频时长 \(XiaoLanMediaFind.clock(length))" + (length > span ? "（只听了前 \(span / 60) 分钟）" : ""))
            if !words.isEmpty { parts.append("视频说了：\(words)") }
        }
        let saw = await paneMediaLook(frame.map { [$0] } ?? [], ask: "这是聊天里一个链接在 Safari 打开后的截图（\(url)），说明网页的标题和主要内容。")
        let text = XiaoLanMediaFind.pageText(rows, from: 0.06, most: 500)
        if let saw { parts.insert("网页（Safari）：\(saw)", at: 0) }
        if !text.isEmpty { parts.append("网页文字：\(text)") }
        // back side by side, then WeChat's page closed
        // 188 night (Echo 188, 11-27 06:18: both windows came back, but WeChat's showed the blocked page — no tab bar, no
        // chat — so its app was not told, "not called back", the second try missed the Dock, the page was never closed
        // and every WeChat order after failed: "屏幕上没有微信的窗口"): the page closed first, then both looked for
        // 191 (measured 11-27: three tabs left after one test, each 打开 a new one): its tab closed
        try? await pointer.key("cmd+w")
        try? await Task.sleep(nanoseconds: 300_000_000)
        await paneBackSideBySide(job)
        guard !parts.isEmpty else { return (nil, "Safari 打开了，但没读到内容（\(url)）") }
        return (parts.joined(separator: "；"), nil)
    }

    /// After Safari: WeChat and WeCom called back side by side, the job's web page (if one is over the chat) closed;
    /// both not seen, called back once more.
    private func paneBackSideBySide(_ job: MediaJob) async {
        _ = await paneRecall(attempt: 1)
        await paneMediaClosePage(job)
        let told = Set(await paneLooks(after: now()).compactMap { XiaoLanPanes.toldApp($0.rows, crop: $0.crop) })
        if !(told.contains(.wechat) && told.contains(.wework)) {
            DebugLog.write("watch: \(job.app.rawValue): after Safari only \(told.map { "\($0)" }.sorted().joined(separator: ", ")) seen; called back once more")
            if await paneRecall(attempt: 2) { await paneMediaClosePage(job) }
        }
    }

    /// WeChat's web page closed by its ✕ (top left: where it worked here, else where it was measured), the chat under it.
    private func paneMediaClosePage(_ job: MediaJob) async {
        guard let l = await paneLooks(after: now(), side: job.side).first(where: { $0.side == job.side }), !isJobChat(l, job) else { return }
        let width = Double(l.rect.width)
        guard let at = XiaoLanSpots.point(.pageClose, app: job.app, width: width) else { await paneMediaBack(job); return }
        _ = await paneTap(at, in: l.rect, wide: 0.03, tall: 0.012)
        if await paneMediaChat(job, after: now()) != nil {
            XiaoLanSpots.learn(.pageClose, app: job.app, width: width, at: at)
        } else {
            XiaoLanSpots.missed(.pageClose, app: job.app, width: width)
            await paneMediaBack(job)
        }
    }

    // MARK: a reply quoting its line

    /// 188 (user 11-27: 「給別人回消息要引用那條消息回復」): the line answered long-pressed and 「引用」 clicked, so the
    /// reply goes as its quote (WeChat: the field empty, 小藍's keyboard up; WeCom: the field holding 「@名字」, 简体拼音
    /// up). False: nothing quoted (a menu opened is closed), the reply goes plain.
    func paneQuote(_ quote: String, _ look: PaneLook, _ who: String) async -> Bool {
        // 188: a voice note, video, picture, file or link is quoted by its own place on the window
        let media = XiaoLanMediaFind.mediaQuoteSpot(look.rows, WatchOCR.Pixels(look.crop), quote: quote)
        guard let spot = media ?? XiaoLanMediaFind.quoteSpot(look.rows, quote: quote) else {
            DebugLog.write("watch: \(who): the line to quote (「\(quote.prefix(20))」) is not on the window; replied without a quote")
            return false
        }
        let s = XiaoLanPanes.onScreen(spot, in: look.rect)
        pointer.aimLoosely(0.04 * Double(look.rect.width), 0.008)
        do { try await pointer.longPress(Double(s.x), Double(s.y), seconds: 0.8) } catch {
            DebugLog.write("watch: \(who): the long press to quote failed: \(error.localizedDescription)")
            return false
        }
        // 引用 only where its words are read: WeChat's menu has 删除 beside it, so a learned or measured place is never
        // clicked blind (it is kept, for the record and /spots)
        guard let menu = await paneLook(look.side, after: now(), tries: 4, until: { XiaoLanMediaFind.menuItem($0.rows, "引用") != nil }),
              let item = XiaoLanMediaFind.menuItem(menu.rows, "引用") else {
            if let l = await paneLooks(side: look.side).first(where: { $0.side == look.side }) { await paneMediaCloseMenu(l) }
            DebugLog.write("watch: \(who): no 引用 after the long press; replied without a quote")
            return false
        }
        guard await paneTap(item, in: menu.rect, wide: 0.03, tall: 0.008) else {
            await paneMediaCloseMenu(menu)
            return false
        }
        let app = XiaoLanPanes.chatApp(look.rows)
        if let taught = XiaoLanSpots.taught(.menuQuote, found: item, from: spot) {
            XiaoLanSpots.learn(.menuQuote, app: app, width: Double(look.rect.width), at: taught)
        }
        let bar = await paneLook(look.side, after: now(), tries: 4, until: { XiaoLanMediaFind.quoteBar($0.rows, quote: quote) != nil })
        let shown = bar.map { XiaoLanMediaFind.quoteBar($0.rows, quote: quote) != nil } ?? false
        DebugLog.write("watch: \(who): 「\(quote.prefix(20))」 quoted" + (shown ? "" : " (its bar not seen)"))
        return true
    }

    // MARK: test channel

    /// POST /media {"do":"read"}: one kind read on the chat open on `side`, as the watch would (watch off).
    func paneMediaTest(side: Int, kind: XiaoLanMediaFind.Kind, text: String) async -> (seen: String?, why: String?) {
        guard let l = await paneLooks(side: side).first(where: { $0.side == side }), case .chat(let t) = l.view else {
            return (nil, "那一边没有打开聊天")
        }
        let titled = WatchOCR.titled(t)
        let job = MediaJob(app: XiaoLanPanes.chatApp(l.rows), side: side, chat: titled.name, group: titled.group, sender: "",
                           kind: kind, text: text, atMe: false)
        return await paneMedia(job)
    }

    /// POST /media {"do":"quote"}: the line quoted on `side` (nothing typed or sent).
    func paneQuoteTest(side: Int, quote: String) async -> Bool {
        guard let l = await paneLooks(side: side).first(where: { $0.side == side }) else { return false }
        return await paneQuote(quote, l, "test")
    }
}
#endif
