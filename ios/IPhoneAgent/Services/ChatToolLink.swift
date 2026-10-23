import Foundation

/// Lan Agent as a ChatTool robot (D:\AIProjects\my-first-peoject\chattool-apk-recovery, local-backend/server.py): one
/// WebSocket to ws://<computer>:8881/webserver/wechat/<robotId>. What watch reads goes up in the robot's own message
/// format (stored, shown in ChatTool's dashboard, used for its digests and group commands); ChatTool's "send
/// message" packets (type 203) come down and watch types them, through the same privacy check as its own replies.
@MainActor final class ChatToolLink: ObservableObject {
    enum State: Equatable { case off, connecting, connected, waiting(String) }
    struct Command: Equatable { var chat: String; var text: String }

    static let sendMessage = 203, internalGroup = 3, privateChat = 0, plainText = 1

    @Published private(set) var state = State.off
    @Published private(set) var pending: [Command] = []
    @Published private(set) var reported = 0
    private var task: URLSessionWebSocketTask?
    private var url: URL?
    private var job: Task<Void, Never>?

    /// http(s)://host:port (or ws://) → ws(s)://host:port/webserver/wechat/<robot>; nil when the address is unusable.
    static func socketURL(_ server: String, robot: String) -> URL? {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !robot.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        c.scheme = c.scheme == "https" || c.scheme == "wss" ? "wss" : "ws"
        c.path = "/webserver/wechat/" + robot
        c.query = nil
        return c.url
    }

    func connect(server: String, robot: String) {
        disconnect()
        guard let url = Self.socketURL(server, robot: robot) else { return }
        self.url = url
        job = Task { [weak self] in await self?.keepConnected() }
    }

    func disconnect() {
        job?.cancel()
        job = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pending = []
        state = .off
    }

    /// The next reply ChatTool asked for, or nil.
    func nextCommand() -> Command? { pending.isEmpty ? nil : pending.removeFirst() }

    /// What was read, one packet per message (ChatTool's dedupe then drops a message read twice).
    func report(_ messages: [ReadMessage]) {
        guard let task, state == .connected else { return }
        for m in messages {
            guard let packet = Self.packet(m) else { continue }
            task.send(.string(packet)) { [weak self] error in
                Task { @MainActor in
                    if let error { DebugLog.write("chattool: report failed: \(error.localizedDescription)") } else { self?.reported += 1 }
                }
            }
        }
    }

    /// A read message in the robot's callback format (list[].titleList, receivedName, rawSpoken, atMe, roomType).
    static func packet(_ m: ReadMessage) -> String? {
        let item: [String: Any] = [
            "titleList": [m.chat], "groupName": m.group ? m.chat : "", "roomType": m.group ? internalGroup : privateChat,
            "receivedName": m.sender, "rawSpoken": m.text, "atMe": m.atMe ? "1" : "", "textType": plainText,
            "sender": m.sender == "me" ? 1 : 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: ["list": [item]]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The "send message" items in a packet from ChatTool; other packets (receive pumps, errors) give none.
    static func commands(_ text: String) -> [Command] {
        guard let data = text.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["list"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard (item["type"] as? Int) == sendMessage, let chat = (item["titleList"] as? [String])?.first,
                  let body = item["receivedContent"] as? String, !chat.isEmpty, !body.isEmpty else { return nil }
            return Command(chat: chat, text: body)
        }
    }

    private func keepConnected() async {
        var wait: UInt64 = 2
        while !Task.isCancelled, let url = self.url {
            state = .connecting
            let t = URLSession.shared.webSocketTask(with: url)
            task = t
            t.resume()
            do {
                while !Task.isCancelled {
                    let message = try await t.receive()
                    if state != .connected { state = .connected; wait = 2; DebugLog.write("chattool: connected to \(url.host ?? "")") }
                    if case .string(let text) = message {
                        let found = Self.commands(text)
                        if !found.isEmpty { pending += found; DebugLog.write("chattool: \(found.count) reply command(s)") }
                    }
                }
            } catch {
                guard !Task.isCancelled else { break }
                state = .waiting(error.localizedDescription)
                DebugLog.write("chattool: disconnected (\(error.localizedDescription)); retrying in \(wait) s")
            }
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
