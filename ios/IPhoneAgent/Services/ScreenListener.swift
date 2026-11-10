import CoreMedia
import Foundation
import Speech

/// The screen's audio while a listen runs (user 11-11: a video's spoken words, 口播文案, from WeChat, 抖音, 视频号).
/// The capture stream hands every audio sample here; only while a request is attached is it passed on.
final class ScreenAudio: @unchecked Sendable {
    static let shared = ScreenAudio()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var samples = 0

    func attach(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); self.request = request; lock.unlock()
    }

    /// Samples passed on since the counter was last read (and reset).
    func takeCount() -> Int {
        lock.lock(); defer { samples = 0; lock.unlock() }
        return samples
    }

    func take(_ sample: CMSampleBuffer) {
        lock.lock()
        let request = self.request
        if request != nil { samples += 1 }
        lock.unlock()
        request?.appendAudioSampleBuffer(sample)
    }
}

/// What the latest recognition said, set from the recognizer's queue.
private final class Transcript: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func set(_ text: String) { lock.lock(); value = text; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor enum ScreenListener {
    /// Asked once with Lan Agent in front (starting the watch, connecting the cloud): the system asks the user.
    static func authorize() {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        SFSpeechRecognizer.requestAuthorization { @Sendable status in Task { @MainActor in DebugLog.write("listen: speech recognition \(status.rawValue)") } }
    }

    static var authorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    /// A line worth keeping as a subtitle: words (Han), not a count, a button or a handle.
    static func subtitle(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard (4...60).contains(t.count), !t.hasPrefix("@"), !t.hasPrefix("#") else { return false }
        let han = t.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return han * 2 >= t.count
    }

    /// Subtitles in the order they showed, each once (a subtitle stays up for several frames, a caption for all).
    static func merge(_ seen: [String], _ line: String) -> [String] {
        guard subtitle(line), !seen.suffix(8).contains(line) else { return seen }
        return seen + [line]
    }

    /// What plays for `seconds`: the screen's audio turned to text (Mandarin, on the phone where it can), in segments of
    /// under a minute, and the subtitles read off the frames once a second.
    static func listen(seconds: Double, frame: () -> Data?) async -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        let canSpeak = authorized && (recognizer?.isAvailable ?? false)
        var spoken: [String] = []
        var subtitles: [String] = []
        var heard = 0
        let end = Date().addingTimeInterval(seconds)
        while Date() < end, !Task.isCancelled {
            // One segment: a request of its own (a recognition off the phone stops at about a minute).
            let segmentEnd = min(end, Date().addingTimeInterval(55))
            var request: SFSpeechAudioBufferRecognitionRequest?
            var task: SFSpeechRecognitionTask?
            let transcript = Transcript()
            if canSpeak, let recognizer {
                let r = SFSpeechAudioBufferRecognitionRequest()
                r.shouldReportPartialResults = true
                r.addsPunctuation = true
                if recognizer.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
                task = recognizer.recognitionTask(with: r) { @Sendable result, _ in
                    if let result { transcript.set(result.bestTranscription.formattedString) }
                }
                request = r
                _ = ScreenAudio.shared.takeCount()
                ScreenAudio.shared.attach(r)
            }
            while Date() < segmentEnd, !Task.isCancelled {
                if let shown = frame() {
                    for row in await CandidatePicker.rowsOffMain(in: shown, top: 0.45, bottom: 0.93) {
                        subtitles = merge(subtitles, row.map(\.text).joined())
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if let request {
                ScreenAudio.shared.attach(nil)
                heard += ScreenAudio.shared.takeCount()
                request.endAudio()
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // the last words come in after the end
                task?.finish()
                let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { spoken.append(text) }
            }
        }
        var note = ""
        if !authorized { note = "没有语音识别权限：在 Lan Agent 打开守候微信设置，允许语音识别" }
        else if !canSpeak { note = "语音识别暂时不可用" }
        else if heard == 0 { note = "没有收到声音：这个 App 可能不让录音，或者没有在播放" }
        DebugLog.write("listen: \(Int(seconds)) s, \(heard) audio sample(s), \(spoken.joined().count) character(s) heard, \(subtitles.count) subtitle line(s)")
        return "【语音转文字】" + (spoken.isEmpty ? "（没有）" : spoken.joined(separator: " "))
            + "\n【画面字幕】" + (subtitles.isEmpty ? "（没有）" : subtitles.joined(separator: "／"))
            + (note.isEmpty ? "" : "\n（\(note)）")
    }
}
