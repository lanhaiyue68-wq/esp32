import Foundation
import Network
import UIKit

/// What the agent and the pointer need from the screen (VideoFeed, or a fake in tests). Port of screen.py.
@MainActor protocol ScreenSource: AnyObject {
    var live: Bool { get }
    var frame: Data? { get }
    var updated: Double { get }
    var capturedAt: Double { get }
    var aspect: Double { get }
    /// After a gesture that ended at `since`: wait until the screen shows its result (and fetch it, in snap mode).
    func afterAction(since: Double) async
    func requireFrame(after: Double?) async throws
}

enum FrameFreshness {
    /// Recovery policy for the delayed background hook. Other callers still force recovery when necessary.
    static func needsDecoderRefresh(decodedAt: Double, transitionAt: Double, usable: Bool) -> Bool {
        !(usable && decodedAt > transitionAt)
    }

    static func usable(frameAt: Double, decodedMs: Int, latestMs: Int?, statusAt: Double,
                       at: Double, after: Double?, broken: Bool) -> Bool {
        // A frame "from the future" pairs an old stream's board time with a new clock offset (the board rebooted).
        guard !broken, frameAt > 0, frameAt <= at + 0.5, at - statusAt <= 3 else { return false }
        let boundary = after ?? (at - 1)
        if frameAt >= boundary && at - frameAt <= 1 { return true }
        // A quiet screen is valid only when a new heartbeat proves we decoded the board's latest AU.
        return statusAt >= boundary && decodedMs > 0 && latestMs == decodedMs
    }
}

enum VideoReadinessError: LocalizedError, Equatable {
    case boardDisconnected, mirroringDisconnected, decoderUnavailable, checkTimedOut

    var errorDescription: String? {
        switch self {
        case .checkTimedOut:
            return String(localized: "Checking the mirrored screen took too long. Wait a few seconds and start again; if it keeps happening, stop mirroring in Control Center and select Lan Agent again.")
        case .boardDisconnected:
            return String(localized: "The board is disconnected. Reconnect it before starting.")
        case .mirroringDisconnected:
            return String(localized: "Screen Mirroring is not streaming. Connect to Lan Agent in Control Center, wait for the preview, then start again.")
        case .decoderUnavailable:
            return String(localized: "Screen Mirroring is connected, but no decodable screen is available. In Control Center, stop mirroring and select Lan Agent again. Wait for the preview, then start again.")
        }
    }
}

/// How a run gets its frames: the live stream (`stream on`, the default: a frame in under a second), or one
/// snap after each action (`stream off`; waits for the board's whole GOP, often 20-30 s).
enum FrameMode: String {
    case stream, snap
    static let key = "frameModeV2"  // V2: drops the old saved "snap" left by earlier automatic fallbacks
    /// A command timeout switches the current run to snap; not saved, so the next run streams again.
    static var fallback: FrameMode?
    static var current: FrameMode {
        get { fallback ?? FrameMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .stream }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key); fallback = nil }
    }
}

extension ScreenSource {
    func afterAction(since: Double) async { await settled() }
    func requireFrame(after: Double? = nil) async throws {
        try Task.checkCancellation()
        guard live, frame != nil else { throw BlindError() }
    }

    /// Wait until the screen stops changing (AirPlay only sends frames on change). Mid-animation frames are big and
    /// can reach us late over BLE, so a gap is only "quiet" once it also covers the last frame's transport lag.
    func settled(quiet: Double = 0.5, least: Double = 0.3, most: Double = 4) async {
        let started = now()
        try? await Task.sleep(nanoseconds: UInt64(least * 1e9))
        while now() - updated < quiet + lag && now() - started < most {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// How late the shown frame arrived after the board got it (0 when unknown), capped.
    private var lag: Double { capturedAt > 0 ? min(max(updated - capturedAt, 0), 1) : 0 }

    /// The first frame captured after `since` (received, when capture times are unknown), or nil if none in time.
    func fresh(since: Double, timeout: Double = 0.8) async -> Data? {
        let deadline = now() + timeout
        while (capturedAt > 0 ? capturedAt : updated) <= since {
            if Task.isCancelled { return nil }
            if now() > deadline { return nil }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return frame
    }
}

/// The phone's screen, mirrored over AirPlay to the board and forwarded over BLE, as JPEG frames.
@MainActor final class VideoFeed: ObservableObject, ScreenSource {
    @Published private(set) var frame: Data?
    @Published private(set) var size = CGSize.zero
    @Published private(set) var note = ""  // last decoder problem, shown in Diagnostics
    private(set) var updated = 0.0
    /// When the board received the shown frame, in local time (≈; see `boardClock`).
    private(set) var capturedAt = 0.0
    /// When the board last forwarded a live (not snapshot) unit: the stream is flowing on its link.
    private var liveUnitAt = -Double.infinity
    /// The stream is flowing and whole: a frame after an action is on its way. A snapshot would resend the whole
    /// GOP (MBs) ahead of it on the same link and put the picture a minute behind (traces(38): 73 s, then timeouts).
    private var flowing: Bool { !broken && now() - liveUnitAt < 2 }
    /// A decode error or a lost chunk since the last good frame: the shown frame is stale until the next IDR.
    private(set) var broken = false
    private var clockOffset: Double?  // local s − board s, the smallest seen (≈ the link latency)
    private var statusAt = 0.0
    private var latestBoardMs: Int?
    private var decodedBoardMs = 0
    var mirroring = false  // board status says ap == streaming
    var metrics: Metrics?
    weak var device: HIDDevice?

    private var assembler = VideoAssembler()
    private let decoder = H264Decoder()
    let tcp = VideoTCP()  // video over the board's Wi-Fi when it is reachable

    init() {
        tcp.onChunk = { [weak self] in self?.receive($0) }
        decoder.onFrame = { [weak self] f in DispatchQueue.main.async { self?.publish(f) } }
        decoder.onError = { [weak self] msg in
            DispatchQueue.main.async {
                let bg = UIApplication.shared.applicationState == .background
                self?.note = bg ? "\(msg) [in background]" : msg
                self?.metrics?.decodeError(background: bg)
                self?.broken = true
            }
        }
    }

    var live: Bool { mirroring && frame != nil && !broken && (device?.connected ?? false) }

    /// Safe metadata for early failures too: no screenshots, Wi-Fi credentials or video tokens.
    var diagnostics: JObject {
        let t = now()
        return ["connected": .bool(device?.connected == true), "mirroring": .bool(mirroring),
                "stream_on": .bool(streamOn), "has_frame": .bool(frame != nil), "broken": .bool(broken),
                "decoded_ms": .int(decodedBoardMs), "latest_board_ms": latestBoardMs.map { .int($0) } ?? .null,
                "status_age_s": statusAt > 0 ? .num(max(0, t - statusAt)) : .null,
                "frame_age_s": capturedAt > 0 ? .num(max(0, t - capturedAt)) : .null,
                "decoder_note": .str(String(note.prefix(200)))]
    }

    /// Run this in the foreground before going Home: a connected mirror may have no complete GOP
    /// for a newly opened decoder. Streaming waits for a usable frame before attempting one snapshot;
    /// snap-per-step mode keeps the stream off, as the user chose, and goes straight to a snapshot.
    /// The user is looking at the app meanwhile, so the snapshot gets `snapLimit` s and no second try.
    @discardableResult
    func prepareForRun(snapMode: Bool = false, wait: Double = 3, snapLimit: Double = 10) async throws -> String {
        try Task.checkCancellation()
        guard device?.connected == true else { throw VideoReadinessError.boardDisconnected }
        guard mirroring else { throw VideoReadinessError.mirroringDisconnected }
        if snapMode {
            if streamOn { try await stream(false) }
        } else {
            try await stream(true)
            if metrics?.board?.sta == 1, metrics?.board?.tcp == 0 {
                // The board is on Wi-Fi but this phone's video link is not (it is reconnecting, see VideoTCP.update):
                // until it is, the video crawls over BLE a minute behind and the check below fails (logs(11)).
                let deadline = now() + 8
                while metrics?.board?.tcp == 0, now() < deadline { try await Task.sleep(nanoseconds: 300_000_000) }
                DebugLog.write("start: Wi-Fi video \(metrics?.board?.tcp == 0 ? "still not back after 8 s" : "back")")
            }
        }
        do {
            return try await currentFrame(wait: wait, snapLimit: snapLimit)
        } catch is BoardTimeout {
            throw VideoReadinessError.checkTimedOut
        }
    }

    /// Seconds to keep watching for a usable frame after the board answers "no video" or a snapshot ends
    /// before the latest image, before giving up: the stream or the next status usually settles it.
    var noVideoGrace: Double = 8
    private var refreshedAt = -Double.infinity

    /// Decode the cached GOP again in a fresh session (see H264Decoder.refresh): far faster than a snapshot,
    /// and it works when the board's own buffer has overflowed. True when that gives a usable frame.
    @discardableResult
    func refreshDecoder(_ why: String, afterTransition: Double? = nil) async -> Bool {
        if let afterTransition,
           !FrameFreshness.needsDecoderRefresh(decodedAt: updated, transitionAt: afterTransition, usable: usable()) {
            DebugLog.write("decoder: kept live session (usable frame decoded after background)")
            return true
        }
        guard now() - refreshedAt > 2 else { return usable() }  // the app's background hook may just have done it
        refreshedAt = now()
        let began = now()
        let n = await withCheckedContinuation { c in decoder.queue.async { [decoder] in c.resume(returning: decoder.refresh()) } }
        try? await Task.sleep(nanoseconds: 30_000_000)  // let the replayed frame reach the main queue
        if n > 0 {
            DebugLog.write(String(format: "decoder: refreshed (%@); decoded the GOP again (%d units, %.0f ms)",
                                  why, n, (now() - began) * 1000))
        }
        return n > 0 && usable()
    }

    /// Waits (bounded) for a usable frame: new live frames, or the next status proving the decoded image is the
    /// board's latest.
    private func recovered(within seconds: Double, after boundary: Double? = nil) async -> Bool {
        let deadline = now() + seconds
        while true {
            if Task.isCancelled { return false }
            if usable(after: boundary) { return true }
            if now() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func status(_ s: BoardStatus) {
        statusAt = now()
        latestBoardMs = s.video_ms
        if let up = s.up { boardClock(ms: up) }
    }

    private func usable(after: Double? = nil) -> Bool {
        live && FrameFreshness.usable(frameAt: capturedAt, decodedMs: decodedBoardMs, latestMs: latestBoardMs,
                                     statusAt: statusAt, at: now(), after: after, broken: broken)
    }

    func requireFrame(after: Double? = nil) async throws {
        try Task.checkCancellation()
        guard device?.connected == true, mirroring else { throw BlindError() }
        if usable(after: after) { return }
        try await currentFrame()
        guard usable(after: after) else { throw BlindError(reason: "screen freshness could not be verified; reconnect Screen Mirroring") }
    }

    /// Frame width / height (portrait iPhone as a fallback).
    var aspect: Double { size.width > 0 && size.height > 0 ? size.width / size.height : 9 / 19.5 }

    /// One `video` notify from BoardLink.
    func receive(_ chunk: Data) {
        metrics?.videoBytes(chunk.count)
        let (dropsBefore, restartsBefore) = (assembler.drops, assembler.restarts)
        let unit = assembler.add(chunk)
        if assembler.drops > dropsBefore { metrics?.videoDrops(assembler.drops - dropsBefore); broken = true }
        if assembler.restarts > restartsBefore { broken = true }  // waits for the next key unit; nothing was lost
        guard let unit else { return }
        if unit.config {
            fed.removeAll(); fedOrder.removeAll()  // a decoder starting over takes everything after it
        } else if !unit.snap {
            let key = UInt64(unit.boardMs) << 32 | UInt64(unit.data.count)
            if fed.contains(key) { return }  // resent after a reconnect (a resumed stream starts at the last one): decoded
            fed.insert(key); fedOrder.append(key)
            if fedOrder.count > 512 { fed.remove(fedOrder.removeFirst()) }
            tcp.fed(unit.boardMs)
        }
        if !unit.snap { boardClock(ms: Int(unit.boardMs)); liveUnitAt = now() }  // snap units are resent late: their ages say nothing
        if unit.idr { metrics?.idrSeen() }
        decoder.queue.async { [decoder] in decoder.decode(unit) }
    }

    /// The link (re)connected: chunk numbering starts over, and nothing of the old stream may come back, neither
    /// a decode still in the queue nor its cached GOP (refreshDecoder would replay it as if it were current).
    func resetStream() {
        assembler.reset(); clockOffset = nil; statusAt = 0; latestBoardMs = nil
        decodedBoardMs = 0; frame = nil; updated = 0; capturedAt = 0; broken = false; liveUnitAt = -.infinity
        fed.removeAll(); fedOrder.removeAll(); tcp.fed(0)
        generation += 1
        let g = generation
        decoder.queue.async { [decoder] in decoder.reset(generation: g) }
    }

    /// Bumped by resetStream; a decoded frame from an earlier stream is dropped in publish.
    private var generation = 0
    /// Live units decoded lately (board time and size), so a resumed stream's first, repeated units are skipped.
    private var fed: Set<UInt64> = [], fedOrder: [UInt64] = []

    /// A board timestamp (status `up`, or a streamed unit) just arrived: keep the smallest offset.
    func boardClock(ms: Int) {
        let offset = now() - Double(ms) / 1000
        clockOffset = min(clockOffset ?? offset, offset)
    }

    /// Show a still frame (demo data).
    func show(_ jpeg: Data, width: Int, height: Int) {
        publish(H264Decoder.Frame(jpeg: jpeg, width: width, height: height, decodeMs: 4.2,
                                  unit: AccessUnit(data: Data(), idr: false, config: false, snap: false, boardMs: 0),
                                  generation: generation))
    }

    private func publish(_ f: H264Decoder.Frame) {
        guard f.generation == generation else { return }  // decoded from the stream before the last reconnect
        frame = f.jpeg
        decodedBoardMs = Int(f.unit.boardMs)
        updated = now()
        capturedAt = clockOffset.map { Double(f.unit.boardMs) / 1000 + $0 } ?? updated
        broken = false
        if size.width != CGFloat(f.width) || size.height != CGFloat(f.height) {
            size = CGSize(width: f.width, height: f.height)
        }
        metrics?.frameDecoded(ms: f.decodeMs)
    }

    /// The app asked the board to forward the stream (`stream on`).
    private(set) var streamOn = false

    /// Seconds a snap may take: the buffered GOP over the measured BLE rate, doubled, 8 to 20 s. A GOP of a few MB
    /// over BLE needed minutes, and a run waiting that long without a word looked frozen (build 20): past 20 s the
    /// snap fails and the run's recovery (waitForScreen) takes over, on screen.
    var snapTimeout: Double {
        let gopBytes = Double(metrics?.board?.gop ?? 0)
        let kbps = max(metrics?.bleKbps ?? 0, metrics?.board?.ble?.kbps ?? 0, 40)
        return min(20, max(8, gopBytes * 8 / 1000 / kbps * 2 + 3))
    }

    /// A current frame for the model. While the board streams, the live stream has it: use a frame younger than
    /// one second, or wait for verified current pixels. AirPlay only sends frames on change, so when none comes, the board says
    /// the phone isn't sending either (status fps ~0) and nothing was lost since the last good frame, the screen
    /// is unchanged and the last frame is still current. If the phone IS sending but nothing reaches us, the
    /// board-to-app path is stuck: never hand the model that stale frame. Snap only as a fallback, retried once
    /// with a longer timeout: it resends the whole GOP since the last IDR, and some iPhones (iOS 26 here) send
    /// an IDR only every few minutes, so that GOP is huge or gone ("err no video"). Returns where the frame came
    /// from, for the log.
    /// Before snapping, the cached GOP is decoded again: after the app went to the background iOS has dropped the
    /// decoder, and a still screen sends nothing that would reveal it. "err no video" or a snapshot that ends before
    /// the latest image get `noVideoGrace` s for the stream to catch up before the user is told to restart mirroring.
    /// `snapLimit` caps the snapshot (no second try) when someone is waiting on screen.
    @discardableResult
    func currentFrame(wait: Double = 3, snapLimit: Double? = nil) async throws -> String {
        try Task.checkCancellation()
        guard device?.connected == true else { throw VideoReadinessError.boardDisconnected }
        guard mirroring else { throw VideoReadinessError.mirroringDisconnected }
        if streamOn && mirroring {
            if usable() { return "live" }
            // A new heartbeat can verify the decoded image without any new pixels on a quiet screen.
            // Recheck the same full freshness policy while waiting, before its proof ages out.
            if await recovered(within: wait) { return "live (waited)" }
            try Task.checkCancellation()
            if await refreshDecoder("frame not current") { return "cached GOP" }
            if flowing, await recovered(within: 8) { return "live (caught up)" }
        }
        DebugLog.write(String(format: "frame: no current frame; asking the board for a snapshot (up to %.0f s)", snapLimit.map { min(snapTimeout, $0) } ?? snapTimeout))
        do {
            do {
                try await snap(timeout: snapLimit.map { min(snapTimeout, $0) })
            } catch is BoardTimeout where snapLimit == nil {
                DebugLog.write("snap timed out; retrying once with a longer timeout")
                try await snap(timeout: snapTimeout * 1.5)
            }
        } catch let error as DeviceError where error.message.hasPrefix("err no video") || error.message.hasPrefix("err ble send failed") {
            // A live frame may have arrived while the snapshot command was in flight. "ble send failed": the board's
            // Wi-Fi video dropped mid-snapshot (traces(37) failed the start on it); the reconnect brings the stream back.
            if usable() { return "live (recovered during snap)" }
            if await recovered(within: noVideoGrace) { return "live (recovered)" }
            guard device?.connected == true else { throw VideoReadinessError.boardDisconnected }
            throw mirroring ? VideoReadinessError.decoderUnavailable : VideoReadinessError.mirroringDisconnected
        }
        if usable() { return "snap" }
        if await recovered(within: noVideoGrace) { return "snap, then live" }
        throw BlindError(reason: "board replied but no verified current video frame was decoded")
    }

    /// Ask the board for the current GOP and wait until it is decoded. Returns the latency in ms.
    @discardableResult
    func snap(timeout: Double? = nil) async throws -> Double {
        guard let device else { throw DeviceError(message: "board not connected") }
        let started = now()
        if let channel = device as? CommandChannel {
            try await channel.send("snap", timeout: timeout ?? snapTimeout)
        } else {
            try await device.send("snap")
        }
        await withCheckedContinuation { c in decoder.queue.async { c.resume() } }  // the GOP is decoded
        try? await Task.sleep(nanoseconds: 30_000_000)  // let the last frame reach the main queue
        try Task.checkCancellation()
        guard updated >= started, !broken else { throw BlindError(reason: "snapshot did not decode a new frame") }
        let ms = (now() - started) * 1000
        metrics?.snapLatency(ms)
        return ms
    }

    func stream(_ on: Bool) async throws {
        try await device?.send("stream \(on ? "on" : "off")")
        streamOn = on
    }

    /// The model must never see a frame from before the action that ended at `since`. Stream: let the screen
    /// settle, then wait (bounded) for a frame captured after the action; none while the stream is healthy means
    /// the screen did not change, but a broken stream (waiting for an IDR) needs a snap. Snap: give the UI a moment,
    /// snap, and snap once more if the GOP still ends before the action.
    func afterAction(since: Double) async {
        let began = now()
        defer {
            DebugLog.write(String(format: "frame wait: after action %.0f ms, verified %@", (now() - began) * 1000,
                                  usable(after: since) ? "yes" : "no"))
        }
        do {
            if FrameMode.current == .snap {
                try await Task.sleep(nanoseconds: 700_000_000)
                try await currentFrame()
                guard capturedAt < since else { return }
                DebugLog.write(String(format: "frame: snap ends %.1f s before the action; snapping again", since - capturedAt))
                try await Task.sleep(nanoseconds: 500_000_000)
                try await currentFrame()
            } else {
                await settled()
                if Task.isCancelled { return }
                if await recovered(within: 1.5, after: since) {
                    if capturedAt < since { DebugLog.write("frame: latest board image verified unchanged") }
                    return
                }
                if Task.isCancelled { return }
                if await refreshDecoder("stale after an action"), usable(after: since) { return }
                if flowing {
                    if await recovered(within: 4, after: since) { return }
                    return DebugLog.write("frame: no newer frame on a flowing stream; the screen did not change")
                }
                DebugLog.write("frame: stream stale (waiting for an IDR); snapping")
                try await snap()
            }
        } catch {
            broken = true
            DebugLog.write("frame after action failed: \(error.localizedDescription)")
        }
        if capturedAt < since { DebugLog.write(String(format: "frame: still %.1f s older than the action", since - capturedAt)) }
    }

    /// The link dropped: the board forgets `stream on`.
    func linkLost() { streamOn = false; statusAt = 0; broken = true }
}


/// Video over the board's Wi-Fi (TCP port 7001, firmware v12+): the same chunks as the BLE video notifies, each
/// with its u16 LE length in front. Far more bandwidth than BLE (a busy screen mirrors at ~450 kbps, BLE carries
/// ~250-300), so frames stop arriving seconds late. The board sends video here while a client is connected and over
/// BLE otherwise; chunks from either go to the same VideoFeed.receive. Needs the phone on the board's network and
/// the Local Network permission (asked once).
final class VideoTCP: @unchecked Sendable {
    var onChunk: (@MainActor (Data) -> Void)?
    private let queue = DispatchQueue(label: "video-tcp")
    private var conn: NWConnection?  // on `queue` only
    private var host: String?
    private var token: String?
    private var failedAt = Date.distantPast
    private var startedAt: Date?    // when `conn` was opened
    private let fedLock = NSLock()
    private var lastFedMs: UInt32 = 0
    private var resumes = false     // the board resumes a stream after a reconnect (firmware v29)

    /// The newest live unit decoded (0: none). A reconnect asks the board to go on from just before it, so units the
    /// dropped socket swallowed still arrive and the decoder needs no new IDR (logs(15): "restart mirroring").
    func fed(_ ms: UInt32) { fedLock.lock(); lastFedMs = ms; fedLock.unlock() }
    private var resumeAfter: UInt32 {
        fedLock.lock(); defer { fedLock.unlock() }
        return resumes && lastFedMs > 1 ? lastFedMs - 1 : 0
    }
    private var readyAt: Date?      // when `conn` came up
    private var boardLostAt: Date?  // since when the board has said it has no Wi-Fi client while `conn` is up

    /// The board's IP from each status (about once a second): connects, or reconnects after a drop or a new IP.
    /// `boardHasClient` is the board's own view (status `tcp`). It saying 0 for 2 s while this side has held a
    /// connection for a while means the socket is half-open (the phone's Wi-Fi dropped and came back): it never
    /// delivers another byte and nothing here notices, so the video went over BLE at a third of the rate it needs,
    /// a minute behind, and every start failed until the app was relaunched (esp32-agent-logs(11)). Start over.
    func update(ip: String?, token: String? = nil, boardHasClient: Bool? = nil, boardResumes: Bool = false) {
        fedLock.lock(); resumes = boardResumes; fedLock.unlock()
        queue.async {
            if self.token != token { self.conn?.cancel(); self.conn = nil; self.host = nil; self.token = token }
            if boardHasClient == false, let c = self.conn, let ready = self.readyAt, Date().timeIntervalSince(ready) > 4 {
                let since = self.boardLostAt ?? Date()
                self.boardLostAt = since
                if Date().timeIntervalSince(since) >= 2 {
                    DebugLog.write("video tcp: the board has no connection from this phone; reconnecting")
                    c.cancel()
                    (self.conn, self.host, self.readyAt, self.boardLostAt) = (nil, nil, nil, nil)
                }
            } else {
                self.boardLostAt = nil
            }
            if self.readyAt == nil, let c = self.conn, let started = self.startedAt, Date().timeIntervalSince(started) > 8 {
                DebugLog.write("video tcp: no connection after 8 s; trying again")  // stuck connecting after a network change
                c.cancel()
                (self.conn, self.host) = (nil, nil)
            }
            self.connect(ip)
        }
    }

    private func connect(_ ip: String?) {
        guard let ip, !ip.isEmpty, ip != "0.0.0.0", let token, token.count == 32 else {
            conn?.cancel()
            (conn, host) = (nil, nil)
            return
        }
        if ip == host, conn != nil { return }
        if conn == nil, Date().timeIntervalSince(failedAt) < 2 { return }  // the phone may not be on that network
        conn?.cancel()
        (host, startedAt, readyAt, boardLostAt) = (ip, Date(), nil, nil)
        let c = NWConnection(host: NWEndpoint.Host(ip), port: 7001, using: .tcp)
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let after = self?.resumeAfter ?? 0
                c.send(content: Data((token + (after > 0 ? " \(after)" : "") + "\n").utf8), completion: .contentProcessed { [weak self] error in
                    if error != nil { self?.drop(c) }
                })
                if self?.conn === c { self?.readyAt = Date() }
                DebugLog.write("video tcp: connected to \(ip):7001")
            case .failed(let error): DebugLog.write("video tcp: failed: \(error)"); self?.drop(c)
            case .waiting(let error): DebugLog.write("video tcp: waiting: \(error)"); self?.drop(c)
            default: break
            }
        }
        conn = c
        c.start(queue: queue)
        read(c)
    }

    /// On `queue`. The next status update reconnects (after a 2 s pause: the board holds the video ~10 s for it).
    private func drop(_ c: NWConnection) {
        c.cancel()
        guard conn === c else { return }
        (conn, host, failedAt) = (nil, nil, Date())
    }

    private func read(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 2, maximumLength: 2) { [weak self] head, _, done, error in
            guard let self else { return }
            guard let head, head.count == 2, error == nil, !done else { return self.drop(c) }
            let n = Int(head[head.startIndex]) | Int(head[head.startIndex + 1]) << 8
            c.receive(minimumIncompleteLength: n, maximumLength: n) { [weak self] body, _, done, error in
                guard let self else { return }
                guard let body, body.count == n, error == nil else { return self.drop(c) }
                let deliver = self.onChunk
                Task { @MainActor in deliver?(body) }
                if done { self.drop(c) } else { self.read(c) }
            }
        }
    }
}
