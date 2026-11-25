import Foundation

/// Lan Agent as a ChatTool robot (D:\AIProjects\my-first-peoject\chattool-apk-recovery, local-backend/server.py): one
/// WebSocket to ws://<computer>:8881/webserver/wechat/<robotId>. What watch reads goes up in the robot's own message
/// format (stored, shown in ChatTool's dashboard, used for its digests and group commands); ChatTool's "send
/// message" packets (type 203) come down and watch types them, through the same privacy check as its own replies.
///
/// 小藍 iPad 版 (161) speaks the rest of the personal robot's socket protocol (the 智微兔 engine Android 小藍 carries,
/// worktool-lan-watch/work/legacy-personal: WeworkMessageListBean / ExecCallbackBean), so the same link also works with
/// our relay (…/relay/zwt) and the mock on the computer (127.0.0.1:18971/zwt):
/// - socketType 2 from the server = a list of orders under one messageId; answered at once with socketType 1 (receipt).
/// - socketType 0 = heartbeat, sent every 30 s (the server answers type 11).
/// - socketType 3 = an order's result: rawMsg (the order as received), errorCode (0 done), errorReason, runTime (start,
///   ms), timeCost (s), successList / failList (chats). `type` is added so the mock can match it.
/// The link itself answers 201 stop and 304 clear (both empty the queue), 303 test and 305 remove; 202 (the server's
/// receive pump) is ignored, watch reads on its own schedule. Every other order Android 小藍's engines take is queued for
/// watch (XiaoLanOrders turns it into a task); reads send their data back as socketType 2 beans (`sendData`).
/// The WeCom engine (智企微行) is the same protocol on …/webserver/wework/<code>: a second link with `app: .wework`.
@MainActor final class ChatToolLink: ObservableObject {
    enum State: Equatable { case off, connecting, connected, waiting(String) }
    /// One chat to type into. An order naming several chats becomes several commands sharing `key`.
    struct Command: Equatable {
        var chat: String
        var text: String
        var type = ChatToolLink.sendMessage
        var messageId = ""
        var key = ""
        var at: [String] = []
        var quote = ""
        var raw = ""
        var app = XiaoLanOrders.App.wechat
    }
    enum Order: Equatable {
        case send(Command), stop(String), clearQueue(String), remove([String], String), test(String)
        case invalid(Int, String, String), unsupported(Int, String)
    }
    struct Incoming: Equatable { var socketType: Int?; var messageId: String; var orders: [Order] }

    static let stopAndGoHome = 201, receivePump = 202, sendMessage = 203, replyMessage = 204, queueClear = 304, heartBeat = 11
    static let controllerTest = 303, queueRemove = 305
    /// Packets that are not orders: heartbeat answers, received-message lists, toasts, logs, the engine's own pump.
    static let notOrders: Set<Int> = [0, 11, 101, 102, 202, 283, 301, 302]
    static let internalGroup = 3, privateChat = 0, plainText = 1
    static let heartbeatSocket = 0, receiptSocket = 1, listSocket = 2, resultSocket = 3
    /// ExecCallbackBean's codes: SUCCESS, ERROR_ILLEGAL_DATA, ERROR_SEND_MESSAGE, ERROR_OTHER.
    static let done = 0, badData = 101011, sendFailed = 201102, otherError = 501000
    /// Reasons go to the customer's server, worded like Android 小藍's.
    static let reasonPrivacy = "隐私检查拦下，未发送", reasonNotSent = "微信里没有发出去", reasonCleared = "指令已被清除",
               reasonBadData = "缺少聊天名称或内容"
    static func reasonUnsupported(_ type: Int) -> String { "小蓝 iPad 版还不支持指令 \(type)" }

    let app: XiaoLanOrders.App
    @Published private(set) var state = State.off
    @Published private(set) var pending: [Command] = []
    @Published private(set) var reported = 0
    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var job: Task<Void, Never>?
    private struct Tally { var left: Int; var ok: [String] = []; var failed: [String] = []; var reasons: [String] = []
                           var messageId: String; var type: Int; var raw: String; var started: Date }
    private var tallies: [String: Tally] = [:]

    init(app: XiaoLanOrders.App = .wechat) { self.app = app }

    /// The server's host, for checking where an order's own callback (跟圈) may post.
    var host: String? { url?.host }

    /// http(s)://host:port[/path] (or ws://) → ws(s)://host:port[/path]/webserver/wechat/<robot> (WeCom: …/wework/…);
    /// nil when unusable.
    static func socketURL(_ server: String, robot: String, app: XiaoLanOrders.App = .wechat) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !robot.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        c.scheme = c.scheme == "https" || c.scheme == "wss" ? "wss" : "ws"
        var base = c.path
        while base.hasSuffix("/") { base.removeLast() }
        c.path = base + (app == .wework ? "/webserver/wework/" : "/webserver/wechat/") + robot
        c.query = nil
        return c.url
    }

    func connect(server: String, robot: String) {
        disconnect()
        guard let url = Self.socketURL(server, robot: robot, app: app) else { return }
        self.url = url
        job = Task { [weak self] in await self?.keepConnected() }
    }

    func disconnect() {
        job?.cancel()
        job = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pending = []
        tallies = [:]
        state = .off
    }

    /// The next message the server asked for, or nil. Hand it back with `finish` when it is sent or given up.
    func nextCommand() -> Command? { pending.isEmpty ? nil : pending.removeFirst() }

    /// What was read, one packet per message (ChatTool's dedupe then drops a message read twice).
    func report(_ messages: [ReadMessage]) {
        guard state == .connected else { return }
        for m in messages {
            guard let packet = Self.packet(m) else { continue }
            send(packet) { [weak self] in self?.reported += 1 }
        }
    }

    /// A read message in the robot's callback format (list[].titleList, receivedName, rawSpoken, atMe, roomType).
    static func packet(_ m: ReadMessage) -> String? {
        let item: [String: Any] = [
            "titleList": [m.chat], "groupName": m.group ? m.chat : "", "roomType": m.group ? internalGroup : privateChat,
            "receivedName": m.sender, "rawSpoken": m.text, "atMe": m.atMe ? "1" : "", "textType": plainText,
            "sender": m.sender == "me" ? 1 : 0,
        ]
        return json(["list": [item]])
    }

    /// The orders in a packet from the server (for the engine `app`). Heartbeat answers, receive pumps and other
    /// packets give none. An order naming several chats (XiaoLanOrders.perChat) becomes one command per chat.
    static func incoming(_ text: String, app: XiaoLanOrders.App = .wechat) -> Incoming {
        guard let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Incoming(socketType: nil, messageId: "", orders: [])
        }
        let id = obj["messageId"] as? String ?? "", socketType = obj["socketType"] as? Int
        let list = obj["list"] as? [[String: Any]] ?? []
        var orders: [Order] = []
        for (index, item) in list.enumerated() {
            let type = item["type"] as? Int ?? 0, raw = json(item) ?? ""
            let f = XiaoLanOrders.Fields(item)
            switch type {
            case _ where notOrders.contains(type): continue
            case stopAndGoHome: orders.append(.stop(raw))
            case queueClear: orders.append(.clearQueue(raw))
            case controllerTest: orders.append(.test(raw))
            case queueRemove: orders.append(.remove(f.list("selectList") + f.list("duplicateMessageId") + f.list("titleList"), raw))
            case _ where XiaoLanOrders.label(type, app) == nil: orders.append(.unsupported(type, raw))
            default:
                if let why = XiaoLanOrders.problem(type, app, f) { orders.append(.invalid(type, raw, why)); continue }
                let chats = XiaoLanOrders.perChat.contains(type) ? f.list("titleList") : [XiaoLanOrders.target(type, f)]
                for chat in chats {
                    orders.append(.send(Command(chat: chat, text: f.s("receivedContent"), type: type, messageId: id, key: "\(id)#\(index)",
                                                at: f.list("atList") + f.list("at"), quote: f.s("originalContent"), raw: raw, app: app)))
                }
            }
        }
        return Incoming(socketType: socketType, messageId: id, orders: orders)
    }

    /// The "send message" commands in a packet from the server.
    static func commands(_ text: String) -> [Command] {
        incoming(text).orders.compactMap { if case .send(let c) = $0 { return c } else { return nil } }
    }

    static func receiptPacket(_ messageId: String) -> String? { json(["socketType": receiptSocket, "messageId": messageId]) }
    static func heartbeatPacket() -> String? { json(["socketType": heartbeatSocket, "list": [["type": heartBeat]]]) }

    static func resultPacket(messageId: String, type: Int, raw: String, code: Int, reason: String, ok: [String], failed: [String],
                             started: Date, now: Date) -> String? {
        let item: [String: Any] = [
            "type": type, "rawMsg": raw, "errorCode": code, "errorReason": reason,
            "runTime": Int64((started.timeIntervalSince1970 * 1000).rounded()),
            "timeCost": (max(0, now.timeIntervalSince(started)) * 10).rounded() / 10,
            "successList": ok, "failList": failed,
        ]
        return json(["socketType": resultSocket, "messageId": messageId, "list": [item]])
    }

    /// Takes a packet from the server: queues what watch types and answers the rest. Returns what went back at once
    /// (the receipt first, then results of orders done on the spot).
    @discardableResult func accept(_ text: String, now: Date = Date()) -> [String] {
        let got = Self.incoming(text, app: app)
        var out: [String] = []
        if got.socketType == Self.listSocket, !got.messageId.isEmpty, let r = Self.receiptPacket(got.messageId) { out.append(r) }
        func clear(_ type: Int, _ raw: String) {
            let dropped = pending
            pending = []
            for c in dropped { if let r = finish(c, ok: false, reason: Self.reasonCleared, now: now, sending: false) { out.append(r) } }
            if let r = Self.resultPacket(messageId: got.messageId, type: type, raw: raw, code: Self.done, reason: "",
                                         ok: dropped.map(\.chat), failed: [], started: now, now: now) { out.append(r) }
            DebugLog.write("chattool: \(type): cleared \(dropped.count) queued message(s)")
        }
        for order in got.orders {
            switch order {
            case .send(let c):
                if tallies[c.key] == nil { tallies[c.key] = Tally(left: 0, messageId: c.messageId, type: c.type, raw: c.raw, started: now) }
                tallies[c.key]?.left += 1
                pending.append(c)
            case .stop(let raw): clear(Self.stopAndGoHome, raw)
            case .clearQueue(let raw): clear(Self.queueClear, raw)
            case .test(let raw):
                if let r = Self.resultPacket(messageId: got.messageId, type: Self.controllerTest, raw: raw, code: Self.done, reason: "",
                                             ok: [], failed: [], started: now, now: now) { out.append(r) }
            case .remove(let ids, let raw):
                let dropped = pending.filter { ids.contains($0.messageId) }
                pending.removeAll { ids.contains($0.messageId) }
                for c in dropped { if let r = finish(c, ok: false, reason: Self.reasonCleared, now: now, sending: false) { out.append(r) } }
                if let r = Self.resultPacket(messageId: got.messageId, type: Self.queueRemove, raw: raw, code: Self.done, reason: "",
                                             ok: dropped.map(\.chat), failed: [], started: now, now: now) { out.append(r) }
            case .invalid(let type, let raw, let why):
                if let r = Self.resultPacket(messageId: got.messageId, type: type, raw: raw, code: Self.badData, reason: why,
                                             ok: [], failed: [], started: now, now: now) { out.append(r) }
            case .unsupported(let type, let raw):
                if let r = Self.resultPacket(messageId: got.messageId, type: type, raw: raw, code: Self.otherError,
                                             reason: Self.reasonUnsupported(type), ok: [], failed: [], started: now, now: now) { out.append(r) }
                DebugLog.write("chattool: order \(type) not supported yet")
            }
        }
        let queued = got.orders.filter { if case .send = $0 { return true } else { return false } }.count
        if queued > 0 { DebugLog.write("chattool: \(queued) message(s) to send") }
        for packet in out { send(packet) }
        return out
    }

    /// A command watch sent (or gave up on). Once every chat of its order is done, the order's result goes up and is
    /// returned; until then nil.
    @discardableResult func finish(_ c: Command, ok: Bool, reason: String = "", now: Date = Date(), sending: Bool = true) -> String? {
        guard var t = tallies[c.key] else { return nil }
        if ok { t.ok.append(c.chat) } else {
            t.failed.append(c.chat)
            if !reason.isEmpty, !t.reasons.contains(reason) { t.reasons.append(reason) }
        }
        t.left -= 1
        guard t.left <= 0 else { tallies[c.key] = t; return nil }
        tallies[c.key] = nil
        let packet = Self.resultPacket(messageId: t.messageId, type: t.type, raw: t.raw, code: t.failed.isEmpty ? Self.done : Self.sendFailed,
                                       reason: t.reasons.joined(separator: "；"), ok: t.ok, failed: t.failed, started: t.started, now: now)
        if sending, let packet { send(packet) }
        return packet
    }

    /// A read's data, as the engines send it: `{socketType:2, list:[{type:503, myInfo:{…}}]}`.
    @discardableResult func sendData(_ bean: [String: Any]) -> String? {
        let packet = Self.json(["socketType": Self.listSocket, "list": [bean]])
        if let packet { send(packet) }
        return packet
    }

    private static func json(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func send(_ packet: String, then: (@MainActor () -> Void)? = nil) {
        guard let task else { DebugLog.write("chattool: not connected; dropped a packet"); return }
        task.send(.string(packet)) { error in
            Task { @MainActor in
                if let error { DebugLog.write("chattool: send failed: \(error.localizedDescription)") } else { then?() }
            }
        }
    }

    private func keepConnected() async {
        var wait: UInt64 = 2
        while !Task.isCancelled, let url = self.url {
            state = .connecting
            let t = URLSession.shared.webSocketTask(with: url)
            task = t
            t.resume()
            let beat = Task { [weak self] in
                while !Task.isCancelled {
                    if let packet = ChatToolLink.heartbeatPacket() { self?.send(packet) }
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
            do {
                while !Task.isCancelled {
                    let message = try await t.receive()
                    if state != .connected { state = .connected; wait = 2; DebugLog.write("chattool: connected to \(url.host ?? "")") }
                    if case .string(let text) = message { accept(text) }
                }
            } catch {
                beat.cancel()
                guard !Task.isCancelled else { break }
                state = .waiting(error.localizedDescription)
                DebugLog.write("chattool: disconnected (\(error.localizedDescription)); retrying in \(wait) s")
            }
            beat.cancel()
            task = nil
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            wait = min(wait * 2, 30)
        }
    }
}

/// Knowledge chosen from the computer: tools/lan-knowledge-server.py serves the .md/.txt files of one folder (by
/// default ChatTool's E:\桌面\小蓝知识库) to whoever has its token. Only the files switched on here are fetched.
enum ComputerKnowledge {
    struct File: Decodable, Hashable { var name: String; var chars: Int }

    static func url(_ server: String, _ path: String, _ query: [URLQueryItem]) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), c.host?.isEmpty == false else { return nil }
        c.path = path
        c.queryItems = query
        return c.url
    }

    static func files(server: String, token: String) async throws -> [File] {
        struct Box: Decodable { var files: [File] }
        return try await get(url(server, "/files", [URLQueryItem(name: "token", value: token)]), as: Box.self).files
    }

    static func content(server: String, token: String, names: [String]) async throws -> String {
        struct Box: Decodable { var text: String }
        let query = [URLQueryItem(name: "token", value: token), URLQueryItem(name: "names", value: names.joined(separator: "\n"))]
        return try await get(url(server, "/content", query), as: Box.self).text
    }

    private static func get<T: Decodable>(_ url: URL?, as: T.Type) async throws -> T {
        guard let url else { throw DeviceError(message: String(localized: "Enter the computer's knowledge address, like http://192.168.31.85:8882.")) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw DeviceError(message: code == 403 ? String(localized: "Wrong password for the computer's knowledge base.")
                                                   : String(localized: "The computer answered \(code)."))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
