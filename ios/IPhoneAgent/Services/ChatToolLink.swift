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
    /// 174: 小藍's own order (not in either engine): delete a chat from the app's chat list.
    static let deleteChat = 290
    /// Packets that are not orders: heartbeat answers, received-message lists, toasts, logs, the engine's own pump.
    static let notOrders: Set<Int> = [0, 11, 101, 102, 202, 283, 301, 302]
    static let internalGroup = 3, privateChat = 0, plainText = 1
    static let heartbeatSocket = 0, receiptSocket = 1, listSocket = 2, resultSocket = 3
    /// ExecCallbackBean's codes: SUCCESS, ERROR_ILLEGAL_DATA, ERROR_SEND_MESSAGE, ERROR_OTHER.
    static let done = 0, badData = 101011, sendFailed = 201102, otherError = 501000
    /// Reasons go to the customer's server, worded like Android 小藍's.
    static let reasonPrivacy = "隐私检查拦下，未发送", reasonNotSent = "微信里没有发出去", reasonCleared = "指令已被清除",
               reasonBadData = "缺少聊天名称或内容",
               reasonNoAt = "已发送，但没有 @ 成员（小蓝还没有 @ 的固定步骤）",
               reasonNoSteps = "小蓝还没有这个指令的固定步骤（不用大模型执行）"
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
    /// 199 (the kernel's 「同一动作号 防重复提交」): the result sent for each order (messageId), sent again if it is heard again.
    private var resultsSent: [String: String] = [:]

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
        configJob = Task { [weak self] in await self?.loadConfig(server: server, robot: robot) }
    }

    func disconnect() {
        job?.cancel()
        job = nil
        configJob?.cancel()
        configJob = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pending = []
        tallies = [:]
        config = nil
        state = .off
    }

    /// The next message the server asked for, or nil. Hand it back with `finish` when it is sent or given up.
    func nextCommand() -> Command? {
        // 199 (RiskPace): a risky order not due yet stays queued; the ones after it go on
        let t = Date().timeIntervalSince1970
        guard let i = pending.firstIndex(where: { RiskPace.due($0, at: t) }) else { return nil }
        let c = pending.remove(at: i)  // 189: its turn kept until it is finished (retry)
        RiskPace.start(c, at: t)
        return c
    }

    /// 189 (N16, Echo 188, 11-27 11:36 首爾: 测试群's QA reply failed before a word was typed — the failure kept only on
    /// 小藍's page — and was dropped; the line was opened and asked again 14 s later): an order handed back unsent, with
    /// nothing typed, goes first again, its turn and tally kept.
    func retry(_ c: Command) {
        pending.insert(c, at: 0)
    }

    /// 189: an order the QA callback's reply made (its result stays on the iPad).
    static func isQA(_ messageId: String) -> Bool { messageId.hasPrefix(qaPrefix) }

    /// 188 (user 11-27: 「先收到的消息先回，後面來的在後面排著，前面的回完了再接著回第二個…不管是企微還是個微，都要按
    /// 收到的順序依次回復」): one count for WeChat's and WeCom's links together. A message asked of the QA callback takes
    /// its turn when it is read, and its reply keeps it; a server's own order takes one when it comes.
    private static var turnCount = 0
    static func takeTurn() -> Int {
        turnCount += 1
        return turnCount
    }
    private var turns: [String: Int] = [:]  // a waiting order's key → its turn
    private var askedLately: [(said: String, at: Date)] = []  // 189 (N19)
    private var asking: Set<Int> = []       // turns whose QA reply is still coming
    /// The earliest turn among the orders waiting here.
    /// 199: an order here that may go now (a risky one waiting its turn does not hold the watch's reading up).
    var hasDue: Bool {
        let t = Date().timeIntervalSince1970
        return pending.contains { RiskPace.due($0, at: t) }
    }
    var firstTurn: Int? {
        let t = Date().timeIntervalSince1970
        return pending.filter { RiskPace.due($0, at: t) }.compactMap { turns[$0.key] }.min()  // 199: a risky one waits its turn
    }
    /// The earliest turn whose QA reply is still coming (15 s at most).
    var askingTurn: Int? { asking.min() }
    /// The order of that turn, taken off the queue.
    func take(turn: Int) -> Command? {
        let t = Date().timeIntervalSince1970
        guard let i = pending.firstIndex(where: { turns[$0.key] == turn && RiskPace.due($0, at: t) }) else { return nil }
        let c = pending.remove(at: i)  // 189: its turn kept until it is finished (retry)
        RiskPace.start(c, at: t)  // 199
        return c
    }

    /// 198: a reported line's own words, without the note in brackets after it (「\n（引用的文件：…）」, 「\n（小蓝没能打开…）」);
    /// a picture's or a video's account stays (「[图片]\n图片内容：…」: two pictures are two lines).
    static func askedLine(_ text: String) -> String {
        guard let r = text.range(of: "\n（") ?? text.range(of: "\n(") else { return text }
        return String(text[..<r.lowerBound])
    }

    /// What was read: one packet per message over the socket (ChatTool's dedupe then drops a message read twice), and
    /// what the robot settings say goes to the QA callback, whose reply is queued to be sent (163, as the engines do).
    func report(_ messages: [ReadMessage]) {
        for m in messages {
            if let packet = Self.packet(m) {  // 187: kept when it cannot go out now
                if state == .connected {
                    send(packet, then: { [weak self] in self?.reported += 1 }, failed: { [weak self] in self?.keep(packet) })
                } else {
                    keep(packet)
                }
            }
            if Self.asksQA(m, config: config) {
                // 189 (N19, Echo 189, 11-27 12:51 首爾: 企微测试群's 「你好啊」「我敢」 reported at :28 and again at :45, when
                // the chat was opened again for the next line): the same line of the same sender in the same chat is
                // asked of the QA callback once in 90 s (two replies to it would go out)
                // 198 (Echo 197 11-28 05:15: WeCom's 「这里面是什么」 asked three times in 50 s — read plain once, then with
                // 「（引用的文件：…）」 and 「（小蓝没能打开…）」 after it — and answered three times): the line itself, its first
                // line, without what was added about its quote or media
                let said = "\(m.chat)|\(m.sender)|\(XiaoLanSelf.plain(Self.askedLine(m.text)))", t = Date()
                askedLately = askedLately.filter { t.timeIntervalSince($0.at) < 90 }
                if askedLately.contains(where: { $0.said == said }) {
                    DebugLog.write("chattool: 「\(m.text.prefix(20))」 in \(m.chat) was asked of the QA callback moments ago; not asked again")
                    continue
                }
                askedLately.append((said: said, at: t))
                qaWaiting += 1
                let turn = Self.takeTurn()  // 188: its turn is when it was read
                asking.insert(turn)
                Task { [weak self] in
                    await self?.askQA(m, turn: turn)
                    self?.asking.remove(turn)
                    self?.qaWaiting -= 1
                }
            }
        }
    }

    /// 187 (user 11-27: "各位先收到一個消息…正在要回呢，然後啟微又收到了一個消息…先把各位的回了，然後再去點啟微的"): the QA
    /// callbacks still out (each 15 s at most); the watch waits for their replies before it looks at the other window.
    @Published private(set) var qaWaiting = 0

    /// A read message as the engines report it: socketType 2, an item of type 101 (TYPE_RECEIVE_MESSAGE_LIST) with
    /// messageList [SubMessageBean: sender 0 others / 1 me, nameList, itemMessageList feature 2 = text]. ChatTool's
    /// callback keys (receivedName, rawSpoken, atMe…) stay on the item; ChatTool reads messageList when it is there.
    static func packet(_ m: ReadMessage) -> String? {
        let sub: [String: Any] = [
            "sender": m.sender == "me" ? 1 : 0, "textType": plainText, "nameList": [Self.who(m)],
            "itemMessageList": [["feature": 2, "text": m.text]],
        ]
        let item: [String: Any] = [
            "type": receiveMessageList, "titleList": [m.chat], "roomType": m.group ? internalGroup : privateChat,
            "messageList": [sub],
            "groupName": m.group ? m.chat : "", "receivedName": Self.who(m), "rawSpoken": m.text, "atMe": m.atMe ? "1" : "",
            "textType": plainText, "sender": m.sender == "me" ? 1 : 0,
        ]
        return json(["socketType": listSocket, "list": [item]])
    }

    // MARK: The engines' robot settings and QA callback (163)
    // Both engines (docs/xiaolan-engine-logic.md) fetch GET /robot/robotInfo/get?robotId= (callbackUrl → qaUrl,
    // openCallback, replyAll, robotType), POST each new message to the QA callback {spoken, rawSpoken, receivedName,
    // groupName, groupRemark, roomType, atMe, textType} and send its {"code":0,"data":{"info":{"text":…}}} back into that
    // chat as a 203. The reply is the server's (its rules, or its model for 接茬); the phone runs no model.

    struct RobotConfig: Equatable { var callbackUrl: String; var openCallback: Bool; var replyAll: Bool; var autoReply: Bool }
    @Published private(set) var config: RobotConfig?
    private var configJob: Task<Void, Never>?
    static let receiveMessageList = 101, qaPrefix = "qa#"

    /// The server's HTTP root for a robot address: ws(s) → http(s), the path kept (…/zwt).
    static func httpBase(_ server: String) -> String? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        c.scheme = c.scheme == "https" || c.scheme == "wss" ? "https" : "http"
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        c.path = path
        c.query = nil
        return c.url?.absoluteString
    }

    static func configURL(_ server: String, robot: String) -> URL? {
        guard !robot.isEmpty, let base = httpBase(server), var c = URLComponents(string: base + "/robot/robotInfo/get") else { return nil }
        c.queryItems = [URLQueryItem(name: "robotId", value: robot)]
        return c.url
    }

    /// robotInfo/get's answer as the engines keep it (MyConfigBean): replyAll -1 = only private chats and @ in groups;
    /// robotType 2 = no auto reply.
    static func robotConfig(_ data: Data) -> RobotConfig? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], (obj["code"] as? Int) == 200,
              let d = obj["data"] as? [String: Any] else { return nil }
        return RobotConfig(callbackUrl: (d["callbackUrl"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                           openCallback: (d["openCallback"] as? Int ?? 0) == 1,
                           replyAll: (d["replyAll"] as? Int ?? 1) != -1,
                           autoReply: (d["robotType"] as? Int ?? 1) != 2)
    }

    /// Whether a read message goes to the QA callback: not our own; with replyAll every one, else private chats and
    /// group messages that @ us.
    static func asksQA(_ m: ReadMessage, config: RobotConfig?) -> Bool {
        guard let c = config, c.openCallback, c.autoReply, !c.callbackUrl.isEmpty, m.sender != "me" else { return false }
        return c.replyAll || !m.group || m.atMe
    }

    /// 189 (N34, Echo 189, 11-27 13:12 首爾: a private chat's video, its line taken from the list's preview, went to the
    /// server with no sender, and was not answered): a private chat's line with no sender read is its chat's person's.
    static func who(_ m: ReadMessage) -> String { m.sender.isEmpty && !m.group ? m.chat : m.sender }

    static func qaBody(_ m: ReadMessage) -> [String: Any] {
        ["spoken": m.text, "rawSpoken": m.text, "receivedName": Self.who(m), "groupName": m.chat, "groupRemark": "",
         "roomType": m.group ? internalGroup : privateChat, "atMe": m.atMe ? "true" : "false", "textType": plainText]
    }

    /// The QA callback's reply text, or nil when it gives none to send (an empty text means: do not reply).
    /// 192 (N44): the words of a reported line to quote in its answer — its first line, a 「[链接]」-style tag left out
    /// (what the chat shows is the address itself).
    /// 195 (N78, Echo 194 11-28 00:40: the answer to a photo went without its quote; user: every reply quotes its line):
    /// a line with no words of its own (「[图片]」, 「[语音] 4"」, 「[视频]」) is quoted by its tag, and paneQuote finds it by
    /// its place on the window (XiaoLanMediaFind.mediaQuoteSpot).
    static func quoteLine(_ text: String) -> String {
        var first = text.components(separatedBy: .newlines).first ?? ""
        first = first.trimmingCharacters(in: .whitespaces)
        var tag = ""
        if first.hasPrefix("["), let close = first.firstIndex(of: "]"), first.distance(from: first.startIndex, to: close) <= 6 {
            tag = String(first[...close])
            first = String(first[first.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        // 193 (N59, Echo 192 11-27 18:24: 「1」「2」「3」 answered without their quotes; user: every reply quotes its line,
        // one character too): any letter or digit is words enough; a voice note's length alone (「4"」) is none
        if XiaoLanMediaFind.voiceSeconds(first) != nil { return tag }
        return first.contains(where: { $0.isLetter || $0.isNumber }) ? first : tag
    }

    /// 193 (N64, Echo 192 11-27 18:32: WeCom's failed send told as 「微信里没有发出去」): said for the app it failed in.
    static func notSentSaid(_ why: String, wework: Bool) -> String {
        wework && why == reasonNotSent ? "企业微信里没有发出去" : why
    }

    static func qaReply(_ data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], (obj["code"] as? Int ?? 0) == 0,
              let info = (obj["data"] as? [String: Any])?["info"] as? [String: Any],
              let text = (info["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private func loadConfig(server: String, robot: String) async {
        guard let url = Self.configURL(server, robot: robot) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // 189 (N18, Echo 189, 11-27 12:51 首爾: 小藍 started with the network not up yet, 「似乎已断开与互联网的连接」; the
        // socket came back 7 s later but the robot settings were never asked again, so no line went to the QA callback
        // and nothing was answered until the watch was started again): not loaded, asked again 2, 4, 8 … 30 s later.
        var wait: UInt64 = 2
        while !Task.isCancelled {
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                config = Self.robotConfig(data)
                if let c = config {
                    note("⚙ 機器人設定：回調\(c.openCallback && !c.callbackUrl.isEmpty ? "開" : "關")・\(c.replyAll ? "全部回覆" : "只回私聊與 @")\(c.autoReply ? "" : "・不自動回覆")")
                } else {
                    note("⚙ 伺服器沒有給機器人設定（不走 QA 回調）")
                }
                return
            } catch {
                DebugLog.write("chattool: robot settings not loaded: \(error.localizedDescription); asked again in \(wait) s")
                try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
                wait = min(wait * 2, 30)
            }
        }
    }

    private func askQA(_ m: ReadMessage, turn: Int? = nil) async {
        guard let c = config, let url = URL(string: c.callbackUrl),
              let body = try? JSONSerialization.data(withJSONObject: Self.qaBody(m)) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code), let text = Self.qaReply(data) else {
                DebugLog.write("chattool: QA callback for \(m.chat) gave nothing to send (HTTP \(code))")  // 189 (N16)
                return
            }
            let id = Self.qaPrefix + UUID().uuidString
            let raw = Self.json(["type": Self.sendMessage, "titleList": [m.chat], "receivedContent": text]) ?? ""
            // 192 (N44; user 188 「給別人回消息要引用那條消息回復」, 11-27 「你再引用我這句話回我」: the server's answers went
            // plain): the answer quotes the line it answers
            queue(Command(chat: m.chat, text: text, type: Self.sendMessage, messageId: id, key: id + "#0", quote: Self.quoteLine(m.text),
                          raw: raw, app: app), now: Date(), turn: turn)
            note("↩ 伺服器回覆 · \(m.chat)")
            DebugLog.write("chattool: QA reply for \(m.chat) queued (turn \(turn.map { String($0) } ?? "-"), \(text.count) characters)")  // 189 (N16)
        } catch {
            DebugLog.write("chattool: QA callback failed: \(error.localizedDescription); asked again when the link is back")
            unasked.append(m)  // 187
            if unasked.count > 50 { unasked.removeFirst(unasked.count - 50) }
        }
    }

    /// Orders that answer into the record, not to a server: the tool box's and the QA callback's replies.
    static func isLocal(_ messageId: String) -> Bool { messageId.hasPrefix(localPrefix) || messageId.hasPrefix(qaPrefix) }

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
        let going = Set(tallies.keys)  // 199: orders already queued or under way before this packet
        for order in got.orders {
            switch order {
            case .send(let c):
                // 199 (the kernel's 「同一动作号 防重复提交」): an order heard again — its result went already, or it is
                // still under way — is not done again; a finished one gets its result once more
                if let again = resultsSent[c.messageId] {
                    if !out.contains(again) { out.append(again) }
                    DebugLog.write("chattool: order \(c.messageId) heard again; its result sent again, nothing done twice")
                    break
                }
                if going.contains(c.key) {
                    DebugLog.write("chattool: order \(c.messageId) heard again while under way; not queued twice")
                    break
                }
                // 199: the same risky order (another number) done, half done or not known in the last 30 minutes:
                // answered at once, not done again blind (a second group, a second forward)
                if let before = OrderLedger.alike(c, now: now.timeIntervalSince1970) {
                    let label = XiaoLanOrders.label(c.type, app) ?? "\(c.type)"
                    let mins = max(1, Int((now.timeIntervalSince1970 - before.received) / 60))
                    let ok = before.outcome == .done
                    var how = "结果不明"
                    if before.outcome == nil { how = "还在做" } else if before.outcome == .partial { how = "只做了一部分" }
                    let notAgain = "同样的「\(label)」\(mins) 分钟前\(how)，为免重复没有再做：请先人工确认"
                    let why = ok ? "同样的「\(label)」\(mins) 分钟前已经做过，没有再做" : OrderOutcome.unknownMark + notAgain
                    queue(c, now: now)
                    pending.removeAll { $0.key == c.key && $0.chat == c.chat }
                    if let r = finish(c, ok: ok, reason: why, now: now, sending: false) { out.append(r) }
                    break
                }
                queue(c, now: now)
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
        turns[c.key] = nil  // 189: kept from take/nextCommand until here (retry)
        // 199: how this chat's part ended, in the order's line (a picture of the screen when it did not go)
        OrderLedger.finished(c, outcome: OrderOutcome.of(ok: ok, reason: reason), reason: reason, now: now.timeIntervalSince1970)
        guard var t = tallies[c.key] else { return nil }
        if ok { t.ok.append(c.chat) } else { t.failed.append(c.chat) }
        // 184 (Echo 183, 11-26: a line with @ went out and the answer said nothing of the @ left out; only a failure's
        // reason was kept): a reason given with a success goes back too ("已发送，但没有 @ 成员").
        if !reason.isEmpty, !t.reasons.contains(reason) { t.reasons.append(reason) }
        t.left -= 1
        guard t.left <= 0 else { tallies[c.key] = t; return nil }
        tallies[c.key] = nil
        let packet = Self.resultPacket(messageId: t.messageId, type: t.type, raw: t.raw, code: t.failed.isEmpty ? Self.done : Self.sendFailed,
                                       reason: t.reasons.joined(separator: "；"), ok: t.ok, failed: t.failed, started: t.started, now: now)
        let label = XiaoLanOrders.label(t.type, app) ?? "\(t.type)"
        note((t.failed.isEmpty ? "✓ " : "✗ ") + label + " · " + (t.ok + t.failed).joined(separator: "、")
             + (t.reasons.isEmpty ? "" : "：" + t.reasons.joined(separator: "；")), now: now)
        // 189 (N16): a failure is in the debug log too (a QA reply's was only on 小藍's page)
        if !t.failed.isEmpty { DebugLog.write("chattool: \(label) to \(t.failed.joined(separator: "、")) failed: \(t.reasons.joined(separator: "；"))") }
        if Self.isLocal(t.messageId) { return nil }  // a tool-box order or a QA reply: its result stays on the iPad
        if let packet {  // 199: an order heard again gets this again
            resultsSent[t.messageId] = packet
            if resultsSent.count > 300 { resultsSent.removeAll() }
        }
        if sending, let packet { send(packet) }
        return packet
    }

    // MARK: 小藍's own orders and record (162)

    /// What was done, newest last (server orders and the tool box's), shown on 小藍's 守候 page.
    @Published private(set) var history: [String] = []
    static let localPrefix = "local#"

    private func note(_ line: String, now: Date = Date()) {
        let stamp = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        history = Array((history + [stamp + "  " + line]).suffix(100))
    }

    private func queue(_ c: Command, now: Date, turn: Int? = nil) {
        if turns[c.key] == nil { turns[c.key] = turn ?? Self.takeTurn() }  // 188
        if tallies[c.key] == nil { tallies[c.key] = Tally(left: 0, messageId: c.messageId, type: c.type, raw: c.raw, started: now) }
        tallies[c.key]?.left += 1
        pending.append(c)
        OrderLedger.received(c, label: XiaoLanOrders.label(c.type, app) ?? "\(c.type)", now: now.timeIntervalSince1970)  // 199
    }

    /// An order typed in 小藍's tool box: checked and queued like a server's (watch does it), its result and any data
    /// kept in `history` instead of going to a server. Returns why it cannot run, or nil when queued.
    @discardableResult func enqueueLocal(_ item: [String: Any], now: Date = Date()) -> String? {
        let id = Self.localPrefix + UUID().uuidString
        guard let text = Self.json(["socketType": Self.listSocket, "messageId": id, "list": [item]]) else { return "指令内容无法读取" }
        let got = Self.incoming(text, app: app)
        var queued: [Command] = []
        for order in got.orders {
            switch order {
            case .send(let c): queued.append(c)
            case .invalid(_, _, let why): return why
            case .unsupported(let type, _): return Self.reasonUnsupported(type)
            default: return "这个指令不能从工具箱发"
            }
        }
        guard let first = queued.first else { return "这个指令不能从工具箱发" }
        for c in queued { queue(c, now: now) }
        note("⋯ " + (XiaoLanOrders.label(first.type, app) ?? "\(first.type)") + " · " + queued.map(\.chat).joined(separator: "、"), now: now)
        return nil
    }

    /// A read's data for an order: to the server, or (a tool-box order) into the record.
    func deliver(_ bean: [String: Any], for c: Command) {
        guard Self.isLocal(c.messageId) else { sendData(bean); return }
        var shown = bean
        shown["type"] = nil
        if let q = shown["qrcode"] as? String { shown["qrcode"] = "（图片 \(q.count / 1024) KB）" }
        let text = Self.json(shown).map { String($0.prefix(400)) } ?? ""
        note("ⓘ " + (XiaoLanOrders.label(c.type, app) ?? "\(c.type)") + "：" + text)
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

    private func send(_ packet: String, then: (@MainActor () -> Void)? = nil, failed: (@MainActor () -> Void)? = nil) {
        guard let task else {
            DebugLog.write("chattool: not connected; dropped a packet")
            failed?()
            return
        }
        task.send(.string(packet)) { error in
            Task { @MainActor in
                if let error {
                    DebugLog.write("chattool: send failed: \(error.localizedDescription)")
                    failed?()
                } else { then?() }
            }
        }
    }

    // 187 (Echo 186, 11-27 00:58 首爾: the server down, 「187断线4」 was read, its red mark cleared and "reported", and
    // never reached the server after it came back): a read message that could not go out, and its QA ask, are kept
    // (the newest 200 and 50) and sent, in order, as soon as the link is up again.
    private var unsent: [String] = []
    private var unasked: [ReadMessage] = []
    private func keep(_ packet: String) {
        unsent.append(packet)
        if unsent.count > 200 { unsent.removeFirst(unsent.count - 200) }
        DebugLog.write("chattool: a read message kept to send when the link is back (\(unsent.count) kept)")
    }
    private func sendKept() {
        let packets = unsent, asks = unasked
        (unsent, unasked) = ([], [])
        guard !packets.isEmpty || !asks.isEmpty else { return }
        DebugLog.write("chattool: link back; \(packets.count) read message(s) and \(asks.count) QA ask(s) kept while it was down sent now")
        for p in packets { send(p, then: { [weak self] in self?.reported += 1 }, failed: { [weak self] in self?.keep(p) }) }
        for m in asks {
            qaWaiting += 1
            Task { [weak self] in
                await self?.askQA(m)
                self?.qaWaiting -= 1
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
                    if state != .connected {
                        state = .connected
                        wait = 2
                        DebugLog.write("chattool: connected to \(url.host ?? "")")
                        sendKept()  // 187: what was read while the link was down
                    }
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
