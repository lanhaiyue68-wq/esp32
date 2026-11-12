import SwiftUI

/// A view of the stores actually retrieved by the agent, with no example memories or model calls on opening.
struct LearningView: View {
    @ObservedObject var app: AppModel

    var body: some View {
        Group {
            if let book = app.agent.lessons, let experience = app.agent.experience {
                LearningContent(app: app, book: book, experience: experience)
            } else {
                ContentUnavailableView("Learning is unavailable", systemImage: "brain")
            }
        }
        .navigationTitle("Learning")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LearningContent: View {
    @ObservedObject var app: AppModel
    @ObservedObject var book: LessonBook
    @ObservedObject var experience: ExperienceStore
    @AppStorage(ExperienceStore.enabledKey) private var enabled = true
    @State private var clearing = false
    @State private var appPlaces = AppPlaces.count  // UserDefaults, not observed: read on appear and after clearing

    var body: some View {
        List {
            Section {
                Toggle("Learn from operation feedback", isOn: $enabled)
                LabeledContent("Automatic lessons", value: "\(book.lessons.filter { $0.auto == true }.count)")
                LabeledContent("Your corrections and accepted hints", value: "\(book.lessons.filter { $0.auto != true }.count)")
                LabeledContent("Measured feedback", value: "\(experience.count)")
                LabeledContent("Learned routes", value: "\(app.agent.routes?.count ?? 0)")
                LabeledContent("Learned buttons", value: "\(app.agent.controls?.count ?? 0)")
                LabeledContent("Learned app places", value: "\(appPlaces)")
                // User 11-13: apps moved to the first pages for speed. A wrong place is only forgotten one app at a time,
                // and the pages are read again at most every three days: moved apps went through Search until then.
                Button("重新記 App 位置（移動過 App 後按）") { AppPlaces.clear(); appPlaces = 0 }
            } footer: {
                Text(LocalizedStringKey(enabled
                     ? "Related lessons are included in later task requests. This is local experience memory, not model-weight training. A reference does not prove success."
                     : "Learning is off. Existing records remain visible, but are neither collected nor included in new requests."))
            }
            lessonSection
            activitySection
            feedbackSection
            Section {
                Button("Clear all learning records", role: .destructive) { clearing = true }
            } footer: {
                Text("Learning stores no screenshots. Up to 200 lessons (400 KB), 128 feedback cases (256 KB) and 24 review records (32 KB) are kept locally. Browsing this page makes no model requests.")
            }
        }
        .confirmationDialog("Clear all learning records?", isPresented: $clearing, titleVisibility: .visible) {
            Button("Clear all learning records", role: .destructive) {
                book.clear(); experience.clear(); app.agent.routes?.clear(); app.agent.controls?.clear()
                AppPlaces.clear(); appPlaces = 0
            }
        } message: {
            Text("Saved lessons, feedback and review records will be removed. A review already in progress cannot restore them.")
        }
        .onAppear { app.runs.reload(); appPlaces = AppPlaces.count }
        .onChange(of: enabled) { _, value in
            book.enabled = value; experience.enabled = value; app.agent.routes?.enabled = value; app.agent.controls?.enabled = value
        }
    }

    private var lessonSection: some View {
        Section {
            if book.lessons.isEmpty {
                Text("No lessons yet. Completed tasks may produce evidence-based lessons; your review corrections are also saved here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(book.lessons) { lesson in
                NavigationLink {
                    LessonDetailView(app: app, book: book, id: lesson.id)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: lesson.text).lineLimit(2)
                        HStack {
                            Text(LocalizedStringKey(lesson.auto == true ? "Automatic review" : "Your correction or accepted hint"))
                            if lesson.disabled == true { Text("Disabled") }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let uses = lesson.uses { Text("Referenced in \(uses) tasks").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        } header: { Text("Saved lessons") }
    }

    private var activitySection: some View {
        Section {
            if book.activity.isEmpty {
                Text("No review records yet. New tasks will show whether review ran, saved a lesson, was skipped or failed.")
                    .foregroundStyle(.secondary)
            }
            ForEach(book.activity) { event in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(event.state.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(event.date, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(verbatim: event.task).lineLimit(2)
                    Text(LocalizedStringKey(event.reason)).font(.caption).foregroundStyle(.secondary)
                    if event.state == .learned {
                        Text("Saved or reinforced: \(event.retained)").font(.caption)
                    }
                    SourceRunLink(app: app, run: event.id)
                }
            }
        } header: { Text("Recent learning activity") }
    }

    private var feedbackSection: some View {
        Section {
            if experience.entries.isEmpty {
                Text("No measured feedback yet. Unconfirmed taps and your explicit operation reviews appear here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(experience.entries.sorted { $0.updated > $1.updated }) { item in
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.verdict.title).font(.subheadline.weight(.semibold))
                    Text(verbatim: item.action.kind + " " + item.action.values.map(String.init).joined(separator: ", "))
                        .font(.caption.monospaced())
                    if let x = item.correctedX, let y = item.correctedY {
                        Text("Corrected position: \(x), \(y)").font(.caption)
                    }
                    Text("Observations: \(item.observations)").font(.caption).foregroundStyle(.secondary)
                    Text(item.updated, style: .date).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: { Text("Operation feedback") } footer: {
            Text("Unconfirmed means the action lacked confirmation. These cases are evidence for checking a live screen, not permission to replay a saved position.")
        }
    }
}

private struct LessonDetailView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var book: LessonBook
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false

    var body: some View {
        Group {
            if let lesson = book.lessons.first(where: { $0.id == id }) {
                List {
                    Section {
                        Text(verbatim: lesson.text).textSelection(.enabled)
                        Toggle("Use in related future tasks", isOn: Binding(
                            get: { lesson.disabled != true }, set: { book.setEnabled($0, id: id) }))
                    } footer: { Text("Changes apply to future requests; requests already sent cannot be changed.") }
                    Section {
                        LabeledContent("Source", value: lesson.auto == true
                            ? String(localized: "Automatic review") : String(localized: "Your correction or accepted hint"))
                        Text(verbatim: lesson.task).textSelection(.enabled)
                        LabeledContent("Learned or reinforced", value: lesson.updated.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Reinforced by tasks", value: "\(lesson.seen ?? 1)")
                        ForEach(sourceRuns(lesson), id: \.self) { run in
                            VStack(alignment: .leading) {
                                Text(verbatim: run).font(.caption.monospaced()).textSelection(.enabled)
                                SourceRunLink(app: app, run: run)
                            }
                        }
                    } header: { Text("Where it came from") }
                    Section {
                        if let uses = lesson.uses { Text("Referenced in \(uses) tasks") }
                        else { Text("Older records have no reference counter.") }
                        if let date = lesson.used {
                            LabeledContent("Last referenced", value: date.formatted(date: .abbreviated, time: .shortened))
                        } else { Text("Not referenced yet") }
                        if let task = lesson.lastTask { Text(verbatim: task).textSelection(.enabled) }
                        if let run = lesson.lastRun {
                            Text(verbatim: run).font(.caption.monospaced())
                            SourceRunLink(app: app, run: run)
                        }
                    } header: { Text("Actual references") } footer: {
                        Text("Counted when the lesson is included in a model request, once per task. This does not mean the operation succeeded.")
                    }
                    Section { Button("Delete lesson", role: .destructive) { deleting = true } }
                }
            } else { ContentUnavailableView("Lesson no longer exists", systemImage: "brain") }
        }
        .navigationTitle("Lesson details")
        .confirmationDialog("Delete this lesson?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete lesson", role: .destructive) { book.remove(id: id); dismiss() }
        }
    }

    private func sourceRuns(_ lesson: LessonBook.Lesson) -> [String] {
        let sources = lesson.from ?? [lesson.id]
        return Array(Set(sources.map { String($0.split(separator: ":").first ?? "") })).sorted()
    }
}

private struct SourceRunLink: View {
    @ObservedObject var app: AppModel
    let run: String
    var body: some View {
        if app.runs.run(run) != nil {
            Button("Open source task review") { app.openReview(run: run) }.font(.caption)
        } else {
            Text("Source log is no longer available.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private extension LessonBook.ReviewState {
    var title: LocalizedStringKey {
        switch self {
        case .reviewing: "Reviewing"
        case .learned: "Evidence saved"
        case .noLesson: "No reliable new lesson"
        case .skipped: "Review skipped"
        case .failed: "Review failed"
        case .interrupted: "Review interrupted"
        }
    }
}

private extension ExperienceStore.Verdict {
    var title: LocalizedStringKey {
        switch self {
        case .unconfirmed: "Unconfirmed operation"
        case .userConfirmed: "Confirmed by you"
        case .userRejected: "Rejected by you"
        case .userCorrected: "Corrected by you"
        }
    }
}
