import SwiftUI

/// WeChat watch settings and the start / stop button (WatchMode.swift). Everything is kept on this iPhone.
struct WatchView: View {
    @ObservedObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WatchSettings.onlyListedKey) private var onlyListed = true
    @AppStorage(WatchSettings.targetsKey) private var targets = ""
    @AppStorage(WatchSettings.instructionKey) private var instruction = WatchSettings.defaultInstruction
    @AppStorage(WatchSettings.fallbackKey) private var fallback = WatchSettings.defaultFallback
    @AppStorage(WatchSettings.knowledgeKey) private var knowledge = ""
    @AppStorage(WatchSettings.privateWordsKey) private var privateWords = ""
    @AppStorage(WatchSettings.blockNumbersKey) private var blockNumbers = true
    @AppStorage(WatchSettings.intervalKey) private var interval = 5
    @State private var files: [String] = []
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if app.watching || !app.watchStatus.isEmpty {
                        Label(app.watchStatus, systemImage: app.watching ? "eye" : "eye.slash")
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
                    Text("While watching, leave this iPhone to the agent and keep Screen Mirroring on. Waiting costs nothing; the model is asked only when WeChat changes or at the regular check.")
                }

                Section {
                    Toggle("Only these chats", isOn: $onlyListed)
                    TextField("Chat or group names, one per line", text: $targets, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Who to Reply To")
                } footer: {
                    Text(onlyListed ? "Only the chats and groups listed here are answered; everything else stays unread."
                                    : "Every private chat is answered. Groups only when listed here; Official Accounts and service notices never.")
                }

                Section("How to Reply") {
                    TextField("How replies should sound", text: $instruction, axis: .vertical)
                        .lineLimit(2...8)
                    TextField("Reply when the knowledge base has no answer", text: $fallback, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    if files.isEmpty {
                        Text("No files yet.").foregroundStyle(.secondary)
                    }
                    ForEach(files, id: \.self) { name in
                        Toggle(isOn: Binding(get: { selected.contains(name) }, set: { choose(name, $0) })) {
                            Text(verbatim: name)
                        }
                    }
                    if !selected.isEmpty {
                        let used = KnowledgeBase.text(Array(selected))
                        Text("\(used.text.count) of \(KnowledgeBase.limit) characters used\(used.truncated ? String(localized: "; the rest is cut") : "")")
                            .font(.footnote).foregroundStyle(used.truncated ? .orange : .secondary)
                    }
                } header: {
                    Text("Knowledge Base")
                } footer: {
                    Text("Put .md or .txt files in Files › On My iPhone › Lan Agent › knowledge. Replies use only the files switched on here; nothing else of yours is sent.")
                }

                Section {
                    Toggle("Block phone, ID and bank card numbers and emails", isOn: $blockNumbers)
                    TextField("Never send these (one per line): names, addresses…", text: $privateWords, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Checked before anything is typed: a reply that contains them is stopped and rewritten, never sent.")
                }

                Section {
                    Stepper(value: $interval, in: 1...60) { Text("Check at least every \(interval) min") }
                } footer: {
                    Text("A change on WeChat starts a check at once; this is the safety net.")
                }
            }
            .navigationTitle("WeChat Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { files = KnowledgeBase.files() }
        }
    }

    private var selected: Set<String> { Set(WatchSettings.lines(knowledge)).intersection(files) }

    private func choose(_ name: String, _ on: Bool) {
        var names = WatchSettings.lines(knowledge).filter { $0 != name && files.contains($0) }
        if on { names.append(name) }
        knowledge = names.joined(separator: "\n")
    }
}
