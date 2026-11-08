import SwiftUI

/// WeChat watch settings and the start / stop button (WatchMode.swift). Everything is kept on this iPhone.
struct WatchView: View {
    @ObservedObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WatchSettings.onlyListedKey) private var onlyListed = true
    @AppStorage(WatchSettings.targetsKey) private var targets = ""
    @AppStorage(WatchSettings.interjectKey) private var interject = false
    @AppStorage(WatchSettings.sendersKey) private var senders = ""
    @AppStorage(WatchSettings.phoneTasksKey) private var phoneTasks = false
    @AppStorage(WatchSettings.passphrasesKey) private var passphrases = WatchSettings.defaultPassphrase
    @AppStorage(WatchSettings.myNamesKey) private var myNames = ""
    @AppStorage(WatchSettings.instructionKey) private var instruction = WatchSettings.defaultInstruction
    @AppStorage(WatchSettings.fallbackKey) private var fallback = WatchSettings.defaultFallback
    @AppStorage(WatchSettings.knowledgeKey) private var knowledge = ""
    @AppStorage(WatchSettings.knowledgeFromComputerKey) private var fromComputer = false
    @AppStorage(WatchSettings.computerURLKey) private var computerURL = ""
    @AppStorage(WatchSettings.computerTokenKey) private var computerToken = ""
    @AppStorage(WatchSettings.computerFilesKey) private var computerChosen = ""
    @AppStorage(WatchSettings.serverOnKey) private var serverOn = false
    @AppStorage(WatchSettings.serverURLKey) private var serverURL = ""
    @AppStorage(WatchSettings.robotKey) private var robot = WatchSettings.defaultRobot
    @AppStorage(WatchSettings.serverRepliesKey) private var serverReplies = false
    @AppStorage(WatchSettings.privateWordsKey) private var privateWords = ""
    @AppStorage(WatchSettings.blockNumbersKey) private var blockNumbers = true
    @AppStorage(WatchSettings.intervalKey) private var interval = 5
    @State private var ownerPIN = WatchSettings.ownerPIN
    @State private var files: [String] = []
    @State private var computerFiles: [ComputerKnowledge.File] = []
    @State private var computerProblem: String?
    @State private var loadingComputer = false
    @State private var problem: String?
    @State private var summary: String?
    @State private var summarizing = false

    var body: some View {
        NavigationStack {
            Form {
                controls
                Section {
                    Toggle("Only these chats", isOn: $onlyListed)
                    TextField("Chat or group names, one per line", text: $targets, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Which Chats to Read")
                } footer: {
                    // build98 (user 11-09): a red mark opens any chat; only the listed ones get replies and tasks.
                    Text(onlyListed ? "这里列出的会话和群：有红色未读数字或免打扰的小红点就打开，可以回复、执行任务。其他会话有红色标记也会打开，但只读，不回复。公众号、服务通知除外。"
                                    : "所有私聊都会读、也会回复；这里列出的群可以回复、执行任务，其他群只读，不回复。公众号、服务通知除外。")
                }
                triggers
                Section {
                    Toggle("Allow phone tasks from WeChat", isOn: $phoneTasks)
                        .disabled(serverOn && serverReplies)
                    if phoneTasks {
                        SecureField("Phone task passcode", text: $ownerPIN)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: ownerPIN) { _, value in WatchSettings.ownerPIN = value }
                    }
                    if phoneTasks && (WatchSettings.lines(senders).isEmpty || WatchSettings.lines(targets).isEmpty) {
                        Text("List both a chat and its permitted sender before phone tasks can run.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if phoneTasks && ownerPIN.trimmingCharacters(in: .whitespacesAndNewlines).count < 4 {
                        Text("Set a passcode of at least 4 characters before phone tasks can run.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("Phone Tasks")
                } footer: {
                    Text("Only a private chat listed in both lists can give phone tasks, and the message must contain the passcode; group messages never start one, because anyone can copy a nickname there. The passcode stays in this iPhone's Keychain and is removed before anything is read or replied. Give the owner a unique remark in WeChat. ChatTool reply mode does not run phone tasks.")
                }
                Section("How to Reply") {
                    TextField("How replies should sound", text: $instruction, axis: .vertical)
                        .lineLimit(2...8)
                    TextField("Reply when the knowledge base has no answer", text: $fallback, axis: .vertical)
                        .lineLimit(1...4)
                }
                knowledgeSection
                chatToolSection
                Section {
                    Toggle("Block phone, ID and bank card numbers and emails", isOn: $blockNumbers)
                    TextField("Never send these (one per line): names, addresses…", text: $privateWords, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Checked before anything is typed, ChatTool's replies included: a reply that contains them is stopped and rewritten, never sent.")
                }
                readLogSection
                Section {
                    Stepper(value: $interval, in: 1...60) { Text("Check at least every \(interval) min") }
                } footer: {
                    Text("A change on WeChat starts a check at once; this is the safety net.")
                }
            }
            .navigationTitle("WeChat Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                files = KnowledgeBase.files()
                if fromComputer && computerFiles.isEmpty { await loadComputerFiles() }
            }
        }
    }

    private var controls: some View {
        Section {
            if app.watching || !app.watchStatus.isEmpty {
                Label(app.watchStatus, systemImage: app.watching ? "eye" : "eye.slash")
                if app.watching { Text("Read \(app.watchRead) messages so far").font(.footnote).foregroundStyle(.secondary) }
            }
            Button(role: app.watching ? .destructive : nil) {
                if app.watching {
                    Task { await app.stopAgent() }  // ends the watch and any check under way
                } else {
                    problem = app.startWatch()
                    if problem == nil { dismiss() }
                }
            } label: {
                Label(app.watching ? "Stop Watching" : "Start Watching", systemImage: app.watching ? "stop.fill" : "eye.fill")
            }
            if let problem { Text(verbatim: problem).foregroundStyle(.red) }
        } footer: {
            Text(app.feed.isNative
                 ? "监听期间保持整屏共享和手机解锁。等待本身不调用模型，只在微信变化或定期检查时请求模型。"
                 : "While watching, leave this iPhone to the agent and keep Screen Mirroring on. Waiting costs nothing; the model is asked only when WeChat changes or at the regular check.")
        }
    }

    private var triggers: some View {
        Section {
            Picker("Mode", selection: $interject) {
                Text("Reply only when triggered").tag(false)
                Text("Interject").tag(true)
            }
            TextField("My name in WeChat, as people @ me (one per line)", text: $myNames, axis: .vertical)
                .lineLimit(1...4)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Whitelist: who may trigger a reply, one per line (empty: anyone)", text: $senders, axis: .vertical)
                .lineLimit(2...6)
            TextField("Passphrases, one per line (“@我” means when you @ this account)", text: $passphrases, axis: .vertical)
                .lineLimit(1...4)
        } header: {
            Text("When to Reply")
        } footer: {
            Text(interject
                 ? "A whitelisted person who @mentions you or says a passphrase gets a reply. Besides that, small talk may get one short, light remark; never on money, promises, privacy or work."
                 : "Only a whitelisted person who @mentions you or says a passphrase gets a reply. Everything else is only read and kept, so the agent learns the chat.")
        }
        .disabled(serverReplies)
    }

    private var knowledgeSection: some View {
        Section {
            Picker("Source", selection: $fromComputer) {
                Text("Files on this iPhone").tag(false)
                Text("My computer").tag(true)
            }
            if fromComputer {
                TextField("Computer address, like http://192.168.31.85:8882", text: $computerURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                SecureField("Password shown by the computer", text: $computerToken)
                Button { Task { await loadComputerFiles() } } label: {
                    HStack { Text("Load the Computer's Files"); if loadingComputer { Spacer(); ProgressView() } }
                }
                .disabled(loadingComputer)
                if let computerProblem { Text(verbatim: computerProblem).font(.footnote).foregroundStyle(.red) }
                ForEach(computerFiles, id: \.self) { file in
                    Toggle(isOn: chosen(file.name, in: $computerChosen)) {
                        VStack(alignment: .leading) {
                            Text(verbatim: file.name)
                            Text("\(file.chars) characters").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                if files.isEmpty { Text("No files yet.").foregroundStyle(.secondary) }
                ForEach(files, id: \.self) { name in
                    Toggle(isOn: chosen(name, in: $knowledge)) { Text(verbatim: name) }
                }
                let picked = WatchSettings.lines(knowledge).filter(files.contains)
                if !picked.isEmpty {
                    let used = KnowledgeBase.text(picked)
                    Text("\(used.text.count) of \(KnowledgeBase.limit) characters used\(used.truncated ? String(localized: "; the rest is cut") : "")")
                        .font(.footnote).foregroundStyle(used.truncated ? .orange : .secondary)
                }
            }
        } header: {
            Text("Knowledge Base")
        } footer: {
            Text(fromComputer
                 ? "Run tools/lan-knowledge-server on the computer; it serves one folder (ChatTool's 小蓝知识库 by default). Only the files switched on here are fetched."
                 : "Put .md or .txt files in Files › On My iPhone › Lan Agent › knowledge. Replies use only the files switched on here; nothing else of yours is sent.")
        }
    }

    private var chatToolSection: some View {
        Section {
            Toggle("Connect to ChatTool on my computer", isOn: $serverOn)
            if serverOn {
                TextField("ChatTool address, like http://192.168.31.85:8881", text: $serverURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Robot ID", text: $robot)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("ChatTool decides the replies", isOn: $serverReplies)
                ChatToolStatus(link: app.chatTool)
            }
        } header: {
            Text("Computer (ChatTool)")
        } footer: {
            Text(serverReplies
                 ? "This iPhone reads and reports every message; ChatTool's prefix and allowed senders decide what to send, and this iPhone types it."
                 : "Messages read here also show up in ChatTool's dashboard and digests. Replies are still decided here.")
        }
    }

    private var readLogSection: some View {
        Section {
            let today = ReadLog.messages().count
            Text("\(today) messages read today")
            Button { Task { await summarize() } } label: {
                HStack { Text("Summarize Today"); if summarizing { Spacer(); ProgressView() } }
            }
            .disabled(summarizing || today == 0)
            if let summary { Text(verbatim: summary).font(.callout).textSelection(.enabled) }
        } header: {
            Text("Read Log")
        } footer: {
            Text("Every message read is kept in Files › On My iPhone › Lan Agent › readlog, one file per day, with the summaries next to them.")
        }
    }

    private func chosen(_ name: String, in store: Binding<String>) -> Binding<Bool> {
        Binding(get: { WatchSettings.lines(store.wrappedValue).contains(name) }, set: { on in
            var names = WatchSettings.lines(store.wrappedValue).filter { $0 != name }
            if on { names.append(name) }
            store.wrappedValue = names.joined(separator: "\n")
        })
    }

    private func loadComputerFiles() async {
        loadingComputer = true
        defer { loadingComputer = false }
        do {
            computerFiles = try await ComputerKnowledge.files(server: computerURL, token: computerToken)
            computerProblem = computerFiles.isEmpty ? String(localized: "The computer's folder has no .md or .txt files.") : nil
        } catch {
            computerProblem = error.localizedDescription
        }
    }

    private func summarize() async {
        summarizing = true
        defer { summarizing = false }
        summary = await app.summarizeToday()
    }
}

/// ChatTool's connection while watching, its reports and the replies it still wants sent.
struct ChatToolStatus: View {
    @ObservedObject var link: ChatToolLink

    var body: some View {
        switch link.state {
        case .off: Text("Connects when watching starts").foregroundStyle(.secondary)
        case .connecting: Label("Connecting…", systemImage: "arrow.triangle.2.circlepath")
        case .connected: Label("Connected · reported \(link.reported) · \(link.pending.count) replies to send", systemImage: "checkmark.circle")
        case .waiting(let why): Label("Not reachable: \(why)", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}
