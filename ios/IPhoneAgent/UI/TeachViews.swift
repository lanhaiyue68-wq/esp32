import CoreTransferable
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// F, user 11-15: a screen recording handed over by Photos (copied, since Photos' own file goes away).
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "-" + received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// F: Learning › 上传录屏: the owner's screen recording of doing a task once becomes a draft to check and keep.
struct VideoLearnRow: View {
    @ObservedObject var recorder: DemoRecorder
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .videos) {
            Label {
                Text(verbatim: recorder.inferring ? "正在看录屏，推出每一步…" : "上传录屏，学会这个操作")
            } icon: {
                Image(systemName: "film.stack")
            }
        }
        .disabled(recorder.inferring || recorder.recording)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let movie = try? await picked.loadTransferable(type: PickedMovie.self) {
                    await recorder.learn(fromVideo: movie.url)
                } else {
                    recorder.error = "没能读取这段视频。"
                }
                item = nil
            }
        }
        if let error = recorder.error {
            Text(verbatim: error).font(.caption).foregroundStyle(Palette.warning)
        }
    }
}

/// F, user 11-15 (跟 AI 对话的窗口: 截图给它，告诉它下次遇到这个问题要怎么解决): what the owner teaches becomes an app tip
/// (LessonBook.learnAppTip), kept once the owner taps 记住; every later task that names the app gets it.
struct TeachView: View {
    @ObservedObject var app: AppModel
    @ObservedObject var book: LessonBook
    @State private var lines: [TeachLine] = []
    @State private var draft = ""
    @State private var item: PhotosPickerItem?
    @State private var picture: Data?
    @State private var asking = false

    struct TeachLine: Identifiable {
        let id = UUID()
        let mine: Bool
        let text: String
        var picture: Data?
        var tip: TeachTip?
        var saved = false
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: "发一张截图（可以不发），告诉我下次遇到这个画面要怎么做。我整理成一条做法给你看，你点“记住”后，以后提到这个 App 的任务都会照着做；在“学习”页可以停用或删掉。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach($lines) { $line in
                VStack(alignment: line.mine ? .trailing : .leading, spacing: Space.xs) {
                    if let data = line.picture, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Text(verbatim: line.text)
                        .padding(Space.s)
                        .background(line.mine ? Palette.ok.opacity(0.15) : Color.secondary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10))
                    if let tip = line.tip {
                        Text(verbatim: "【\(tip.app)】\(tip.when)：\(tip.way)").font(.caption).foregroundStyle(.secondary)
                        Button {
                            if book.learnAppTip(app: tip.app, goal: tip.when, text: tip.way, run: "teach") != nil { line.saved = true }
                        } label: {
                            Text(verbatim: line.saved ? "已记住" : "记住这条做法")
                        }
                        .buttonStyle(.borderedProminent).tint(Palette.ok)
                        .disabled(line.saved)
                    }
                }
                .frame(maxWidth: .infinity, alignment: line.mine ? .trailing : .leading)
            }
            if asking { ProgressView() }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(Text(verbatim: "教我怎么做"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    picture = Self.smaller(image).jpegData(compressionQuality: 0.6)
                }
                item = nil
            }
        }
    }

    private var composer: some View {
        HStack(spacing: Space.s) {
            PhotosPicker(selection: $item, matching: .screenshots) {
                Image(systemName: picture == nil ? "photo.badge.plus" : "photo.fill").font(.title3)
            }
            TextField(text: $draft, axis: .vertical) { Text(verbatim: "下次遇到这个，要这样做…") }
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                .disabled(asking || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Space.s)
        .background(.bar)
    }

    private func send() async {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        let shot = picture
        lines.append(TeachLine(mine: true, text: words, picture: shot))
        draft = ""
        picture = nil
        asking = true
        defer { asking = false }
        do {
            let reply = try await app.settings.client("planner").chat(system: Self.prompt, text: words,
                                                                     images: shot.map { [$0] } ?? [], maxTokens: 800, temperature: 0)
            let tip = TeachTip.parse(reply.text)
            lines.append(TeachLine(mine: false, text: tip.say.isEmpty ? reply.text : tip.say, tip: tip.isLesson ? tip : nil))
        } catch {
            lines.append(TeachLine(mine: false, text: "没能连上模型：" + error.localizedDescription))
        }
    }

    static func smaller(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 1600 else { return image }
        let scale = 1600 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static let prompt = """
    The owner of an iPhone is teaching a phone agent how to handle a situation in an app, with words and maybe a \
    screenshot. Reply in this format only, in Simplified Chinese:
    APP: <the app's name as under its icon>
    WHEN: <the situation, one line>
    WAY: <what to do on the screen, as short steps the agent can follow>
    SAY: <one or two sentences to the owner: what you understood, or what is missing>
    If the owner asks a question instead of teaching, answer it in SAY and leave APP, WHEN and WAY empty.
    """
}

/// F: one lesson the owner taught (TeachView), as the model put it.
struct TeachTip: Equatable {
    var app = "", when = "", way = "", say = ""
    var isLesson: Bool { !app.isEmpty && !way.isEmpty }

    static func parse(_ reply: String) -> TeachTip {
        var tip = TeachTip()
        for raw in reply.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            func value(_ key: String) -> String? {
                guard line.uppercased().hasPrefix(key + ":") || line.hasPrefix(key + "：") else { return nil }
                return String(line.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
            }
            if let v = value("APP") { tip.app = v } else if let v = value("WHEN") { tip.when = v }
            else if let v = value("WAY") { tip.way = v } else if let v = value("SAY") { tip.say = v }
        }
        return tip
    }
}
