import Foundation
import Network

/// Lan Agent's side of its keyboard (KeyboardLink): a listener on 127.0.0.1 that hands the keyboard text to type and
/// waits for it to confirm. Works while the app runs in the background (background audio keeps it alive during a
/// watch or a test). Phase A of the new design (specs/004): replaces the paste hop once the device test passes.
@MainActor final class KeyboardBridge: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var lastSeen: Date?          // the keyboard's last request
    @Published private(set) var fullAccess: Bool?
    private var listener: NWListener?
    private var pending: [KeyboardLink.Job] = []
    private var waiting: [String: CheckedContinuation<Bool, Never>] = [:]
    private let port: UInt16

    /// `port`: the keyboard's (KeyboardLink.port); tests use their own, since the app they run in listens there.
    init(port: UInt16 = KeyboardLink.port) { self.port = port }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.serve(connection) }
            }
            l.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    switch state {
                    case .ready:
                        self?.listening = true
                        DebugLog.write("keyboard bridge: listening on 127.0.0.1:\(self?.port ?? 0)")
                    case .failed(let error):
                        self?.listening = false
                        self?.listener = nil
                        DebugLog.write("keyboard bridge: failed: \(error)")
                    default: break
                    }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch {
            DebugLog.write("keyboard bridge: could not listen: \(error.localizedDescription)")
        }
    }

    /// Has the keyboard type `text` (and Return when `enter`) into the field in front; true once it says it did.
    /// The keyboard must be on screen: it asks every 0.35 s while shown.
    func type(_ text: String, enter: Bool, within seconds: Double) async -> Bool {
        start()
        let job = KeyboardLink.Job(id: UUID().uuidString.prefix(8).lowercased(), text: text, enter: enter)
        pending.append(job)
        DebugLog.write("keyboard bridge: queued \(text.count) character(s)\(enter ? " + return" : "")")
        let ok = await withCheckedContinuation { continuation in
            waiting[job.id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
                self?.finish(job.id, ok: false)
            }
        }
        DebugLog.write("keyboard bridge: \(ok ? "typed by the keyboard" : "not picked up within \(Int(seconds)) s")")
        return ok
    }

    private func finish(_ id: String, ok: Bool) {
        pending.removeAll { $0.id == id }
        waiting.removeValue(forKey: id)?.resume(returning: ok)
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self, let data, let line = String(data: data, encoding: .utf8),
                      let request = KeyboardLink.request(line) else { return connection.cancel() }
                self.lastSeen = Date()
                let reply: String
                switch request {
                case .hello(let full):
                    if self.fullAccess != full { DebugLog.write("keyboard bridge: keyboard on screen, full access \(full)") }
                    self.fullAccess = full
                    reply = "OK\n"
                case .next:
                    self.fullAccess = true  // it reached us, so the connection is allowed
                    // Handed out once: a lost DONE must never make the keyboard type (and send) the text twice.
                    let job = self.pending.isEmpty ? nil : self.pending.removeFirst()
                    reply = KeyboardLink.line(job)
                case .done(let id, let ok):
                    self.finish(id, ok: ok)
                    reply = "OK\n"
                }
                connection.send(content: Data(reply.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
