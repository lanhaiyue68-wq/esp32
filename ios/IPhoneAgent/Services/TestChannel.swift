import Foundation
import Network

/// The USB test channel (user 11-09: "好，你自己測"). From the computer the phone is plugged into (usbmux forwards a port
/// to this loopback listener), tasks and gestures go in and the screen comes out, so a fix can be checked without anyone
/// at the phone. Loopback only, and every request must carry the token in Documents/testchannel.token, which only a USB
/// computer the phone trusts can put there: no file, no service. The file is removed when the testing is over.
@MainActor final class TestChannel {
    static let port: UInt16 = 47821

    struct Request: Equatable {
        var method: String
        var path: String
        var query: [String: String]
        var token: String?
        var body: Data
    }

    struct Response {
        var status = 200
        var type = "application/json"
        var body = Data()

        static func json(_ object: JObject, status: Int = 200) -> Response {
            Response(status: status, type: "application/json", body: Data(PyJSON.dumps(object, ascii: false).utf8))
        }
    }

    var handle: ((Request) async -> Response)?
    private var listener: NWListener?

    static var tokenFile: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("testchannel.token")
    }

    /// The token now on the phone; nil (the channel refuses everything) without the file, or with one too short to mean it.
    static func token() -> String? {
        guard let file = tokenFile, let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.count >= 16 ? token : nil
    }

    static func authorized(_ request: Request, token: String?) -> Bool {
        guard let token else { return false }
        return request.token == token
    }

    /// One HTTP request from the bytes so far; nil while it is incomplete.
    static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        let target = first[1].split(separator: "?", maxSplits: 1).map(String.init)
        var query: [String: String] = [:]
        if target.count == 2 {
            for pair in target[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1] }
            }
        }
        return Request(method: first[0].uppercased(), path: target.first ?? "/", query: query,
                       token: headers["x-token"], body: Data(body.prefix(length)))
    }

    func start() {
        guard listener == nil, let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated {
                    connection.start(queue: .main)
                    self?.receive(connection, Data())
                }
            }
            l.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        DebugLog.write("test channel: listening on 127.0.0.1:\(Self.port), token \(Self.token() == nil ? "absent" : "present")")
                    case .failed(let error):
                        self?.listener = nil
                        DebugLog.write("test channel: failed: \(error)")
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            DebugLog.write("test channel: could not listen: \(error.localizedDescription)")
        }
    }

    private func receive(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self else { return connection.cancel() }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = Self.parse(buffer) {
                    Task { await self.answer(request, on: connection) }
                } else if done || error != nil || buffer.count > 1_000_000 {
                    connection.cancel()
                } else {
                    self.receive(connection, buffer)
                }
            }
        }
    }

    private func answer(_ request: Request, on connection: NWConnection) async {
        let response: Response
        if !Self.authorized(request, token: Self.token()) {
            response = .json(["error": .str("forbidden")], status: 403)
        } else if let handle {
            response = await handle(request)
        } else {
            response = .json(["error": .str("not ready")], status: 503)
        }
        var bytes = Data("HTTP/1.1 \(response.status) \(response.status == 200 ? "OK" : "Error")\r\nContent-Type: \(response.type)\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8)
        bytes.append(response.body)
        connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
}
