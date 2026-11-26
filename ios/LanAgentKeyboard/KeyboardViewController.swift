import Network
import UIKit

/// Lan Agent's keyboard (phase A test version). While it is on screen it asks Lan Agent, over 127.0.0.1, for text to
/// type and puts it straight into the focused field: no app switch and no pasteboard (iOS lets only the app in front
/// fill the pasteboard, and that switch failed whenever other apps were used in between, logs 11-06 to 11-08).
/// Needs "Allow Full Access" for the local connection. A few manual keys stay for the user.
final class KeyboardViewController: UIInputViewController {
    /// 180 (Echo 178, 11-25: 小藍's keyboard said "Pilot"): the keyboard's own name, 小藍 or Pilot, from its bundle.
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pilot"
    private let status = UILabel()
    private var timer: Timer?
    private var busy = false
    private let queue = DispatchQueue(label: "lan-agent-keyboard")
    private lazy var returnButton = key("換行", #selector(returnKey))

    /// The key says what Return does in this field: a key that read 換行 in a chat, where it sends, had the agent looking
    /// for a send button all over the screen (over USB 11-09).
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        let title: String
        switch textDocumentProxy.returnKeyType {
        case .send: title = "發送"
        case .search, .google, .yahoo: title = "搜尋"
        case .go, .route, .join: title = "前往"
        case .done: title = "完成"
        case .next, .continue: title = "下一步"
        default: title = "換行"
        }
        returnButton.setTitle(title, for: .normal)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let height = view.heightAnchor.constraint(equalToConstant: 216)
        height.priority = UILayoutPriority(999)
        height.isActive = true

        status.text = "\(Self.name) 輸入法"
        status.font = .systemFont(ofSize: 15, weight: .medium)
        status.textAlignment = .center
        status.numberOfLines = 3

        let globe = key("🌐 下一個", nil)  // tap: next keyboard; hold: the list (Apple's handler)
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        let row = UIStackView(arrangedSubviews: [globe, key("空格", #selector(space)), key("⌫", #selector(backspace)), returnButton])
        row.distribution = .fillEqually
        row.spacing = 6

        let stack = UIStackView(arrangedSubviews: [status, row])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard hasFullAccess else {
            status.text = "請到 設定 › 一般 › 鍵盤 › 鍵盤 › \(Self.name)\n打開「允許完整取用」"
            return
        }
        status.text = "\(Self.name) 輸入法：等待要打的字…"
        textDidChange(nil)
        exchange(KeyboardLink.line(.hello(fullAccess: true))) { _ in }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.poll() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !busy else { return }
        busy = true
        exchange(KeyboardLink.line(.next)) { [weak self] reply in
            guard let self else { return }
            // D84, y5 on 138: one unanswered ask (iOS held Lan Agent for a few seconds) left "連不上" up for good, and
            // Codex read it and gave the item up. The line says so only while asks go unanswered.
            guard let reply, let job = KeyboardLink.job(reply) else {
                if reply == nil {
                    self.status.text = "暫時連不上 \(Self.name)（沒打開請先打開）"
                } else if self.status.text?.hasPrefix("暫時連不上") == true {
                    self.status.text = "\(Self.name) 輸入法：等待要打的字…"
                }
                self.busy = false
                return
            }
            // 185 (B10): a job to put the keyboard down (no text): done, then down.
            if job.dismiss == true && job.text.isEmpty && !job.enter {
                self.exchange(KeyboardLink.line(.done(id: job.id, ok: true))) { _ in
                    self.busy = false
                    self.dismissKeyboard()
                }
                return
            }
            // A return alone (the iPhone watch's own return, a search's return): as before, at once.
            if job.text.isEmpty && job.enter {
                self.textDocumentProxy.insertText("\n")
                self.exchange(KeyboardLink.line(.done(id: job.id, ok: true))) { _ in self.busy = false }
                return
            }
            self.textDocumentProxy.insertText(job.text)
            self.status.text = "\(Self.name) 已填入：\(job.text.prefix(20))"
            guard job.enter else {
                self.exchange(KeyboardLink.line(.done(id: job.id, ok: true))) { _ in self.busy = false }
                return
            }
            // 185 (Echo 184, 11-26: the return right after the text sent nothing in WeChat, three times in three, and
            // Lan Agent said sent; with iOS's 语音控制 on, words spoken nearby went into the field after the text): the
            // return a moment later, and only when the field holds exactly this text (what the field shows around the
            // cursor; a field that shows nothing is sent as before). Otherwise nothing is sent and Lan Agent is told.
            // 185 (Echo 184, 11-26 18:19: the return went into WeChat's field as a new line, the cursor on a second
            // line): after the return the field is looked at again; still holding the text, it was not sent: the new
            // line is taken back and Lan Agent told.
            DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardLink.returnDelay) {
                let field = KeyboardLink.fieldMatches(job.text, before: self.textDocumentProxy.documentContextBeforeInput,
                                              after: self.textDocumentProxy.documentContextAfterInput)
                guard field else {
                    self.status.text = "\(Self.name)：輸入框裡還有別的字，沒有發送"
                    self.exchange(KeyboardLink.line(.done(id: job.id, ok: false))) { _ in self.busy = false }
                    return
                }
                self.textDocumentProxy.insertText("\n")
                DispatchQueue.main.asyncAfter(deadline: .now() + KeyboardLink.sentCheckDelay) {
                    let before = self.textDocumentProxy.documentContextBeforeInput
                    let sent = !KeyboardLink.stillHolds(job.text, before: before)
                    if !sent {
                        if before?.hasSuffix("\n") == true { self.textDocumentProxy.deleteBackward() }
                        self.status.text = "\(Self.name)：發送鍵沒有送出（變成換行）"
                    }
                    self.exchange(KeyboardLink.line(.done(id: job.id, ok: sent))) { _ in
                        self.busy = false
                        if sent && job.dismiss == true { self.dismissKeyboard() }
                    }
                }
            }
        }
    }

    /// One request line to Lan Agent and its one reply line (nil when it cannot be reached), on the main thread.
    private func exchange(_ line: String, reply: @escaping (String?) -> Void) {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: KeyboardLink.port)!, using: .tcp)
        var finished = false
        func finish(_ text: String?) {
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async { reply(text) }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(line.utf8), completion: .contentProcessed { error in
                    if error != nil { return finish(nil) }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                        finish(data.flatMap { String(data: $0, encoding: .utf8) })
                    }
                })
            case .failed, .waiting: finish(nil)
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 1.5) { finish(nil) }
    }

    private func key(_ title: String, _ action: Selector?) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16)
        b.backgroundColor = UIColor.secondarySystemBackground
        b.layer.cornerRadius = 6
        if let action { b.addTarget(self, action: action, for: .touchUpInside) }
        return b
    }

    @objc private func space() { textDocumentProxy.insertText(" ") }
    @objc private func backspace() { textDocumentProxy.deleteBackward() }
    @objc private func returnKey() { textDocumentProxy.insertText("\n") }
}
