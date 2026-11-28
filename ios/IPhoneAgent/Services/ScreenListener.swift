import AVFoundation
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
    // Build 121 on the phone, 11-11: 8816 samples in 180 s of a news video and not one word recognized. What came in
    // and how loud it was are kept for the log, and every sample goes in in the recognizer's own format. Touched only
    // on the capture's audio queue (take) or under the lock (report).
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private var format = ""
    private var peak: Float = 0
    private var converted = 0, passedRaw = 0

    func attach(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock(); self.request = request; lock.unlock()
    }

    /// Samples passed on since the counter was last read (and reset).
    func takeCount() -> Int {
        lock.lock(); defer { samples = 0; lock.unlock() }
        return samples
    }

    /// What came in since the last report: its format, the loudest sample (0 is silence), how it went in.
    func report() -> (text: String, silent: Bool) {
        lock.lock(); defer { format = ""; peak = 0; converted = 0; passedRaw = 0; lock.unlock() }
        let text = (format.isEmpty ? "no audio format" : format) + String(format: ", peak %.4f", peak)
            + ", \(converted) converted, \(passedRaw) as they came"
        return (text, !format.isEmpty && peak < 0.0005)
    }

    func take(_ sample: CMSampleBuffer) {
        lock.lock()
        let request = self.request
        if request != nil { samples += 1 }
        lock.unlock()
        guard let request else { return }
        guard let pcm = Self.pcm(sample) else {
            lock.lock(); passedRaw += 1; lock.unlock()
            request.appendAudioSampleBuffer(sample)
            return
        }
        let loudest = Self.loudness(pcm)
        let target = request.nativeAudioFormat
        let out = convert(pcm, to: target)
        lock.lock()
        if format.isEmpty {
            let f = pcm.format
            format = "\(Int(f.sampleRate)) Hz, \(f.channelCount) ch, \(f.commonFormat.rawValue)/\(f.isInterleaved ? "interleaved" : "planar")"
                + " -> \(Int(target.sampleRate)) Hz, \(target.channelCount) ch, \(target.commonFormat.rawValue)"
        }
        peak = max(peak, loudest)
        if out != nil { converted += 1 } else { passedRaw += 1 }
        lock.unlock()
        if let out { request.append(out) } else { request.appendAudioSampleBuffer(sample) }
    }

    /// The sample as a PCM buffer, in the format it came in.
    static func pcm(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description) else { return nil }
        var stream = basic.pointee
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0, let format = AVAudioFormat(streamDescription: &stream),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames),
                                                                  into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    /// The loudest sample, 0-1, of the first channel.
    static func loudness(_ buffer: AVAudioPCMBuffer) -> Float {
        let n = Int(buffer.frameLength)
        if let data = buffer.floatChannelData?[0] {
            var m: Float = 0
            for i in 0..<n { m = max(m, abs(data[i])) }
            return m
        }
        if let data = buffer.int16ChannelData?[0] {
            var m: Int32 = 0
            for i in 0..<n { m = max(m, abs(Int32(data[i]))) }
            return Float(m) / 32768
        }
        return 0
    }

    private func convert(_ pcm: AVAudioPCMBuffer, to target: AVAudioFormat) -> AVAudioPCMBuffer? {
        if pcm.format == target { return pcm }
        if converter == nil || converterInput != pcm.format {
            converter = AVAudioConverter(from: pcm.format, to: target)
            converterInput = pcm.format
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(Double(pcm.frameLength) * target.sampleRate / pcm.format.sampleRate) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        // The input block may be @Sendable in newer SDKs: what it changes lives in an object, not a captured var.
        final class Once: @unchecked Sendable { var given = false }
        let once = Once()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if once.given { inputStatus.pointee = .noDataNow; return nil }
            once.given = true
            inputStatus.pointee = .haveData
            return pcm
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }
}

/// What the latest recognition said, set from the recognizer's queue.
private final class Transcript: @unchecked Sendable {
    private let lock = NSLock()
    private var value = "", failure = ""
    func set(_ text: String) { lock.lock(); value = text; lock.unlock() }
    func fail(_ error: Error) {
        let e = error as NSError
        lock.lock(); failure = "\(e.domain) \(e.code): \(e.localizedDescription)"; lock.unlock()
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return value }
    var error: String { lock.lock(); defer { lock.unlock() }; return failure }
}

@MainActor enum ScreenListener {
    /// Asked once with Lan Agent in front (starting the watch, connecting the cloud): the system asks the user.
    static func authorize() {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        SFSpeechRecognizer.requestAuthorization { @Sendable status in Task { @MainActor in DebugLog.write("listen: speech recognition \(status.rawValue)") } }
    }

    /// Siri and Dictation are off on this phone (kLSRErrorDomain 201): recognition goes to Apple's server from the start.
    static var phoneRecognitionOff = false
    static var authorized: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    static var undecided: Bool { SFSpeechRecognizer.authorizationStatus() == .notDetermined }

    /// A line worth keeping as a subtitle: words (Han), not a count, a button or a handle.
    static func subtitle(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard (4...60).contains(t.count), !t.hasPrefix("@"), !t.hasPrefix("#") else { return false }
        let han = t.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return han * 2 >= t.count
    }

    /// Subtitles in the order they showed, each once (a subtitle stays up for several frames, a caption for all).
    /// 192 (N42, Echo 191 11-27: a page's own words, the same every second, came back 255 times): each line once.
    static func merge(_ seen: [String], _ line: String) -> [String] {
        guard subtitle(line), !seen.contains(line) else { return seen }
        return seen + [line]
    }

    /// What plays for `seconds`: the screen's audio turned to text (Mandarin, on the phone where it can), in segments of
    /// under a minute, and the subtitles read off the frames once a second.
    /// 192: `ended`, a line read on the frame that says the video is over (Douyin's 「重播」, the 「离开微信」 sheet that
    /// Kuaishou and Xiaohongshu raise at their end): the listen stops there.
    static func listen(seconds: Double, frame: () -> Data?, ended: ((String) -> Bool)? = nil) async -> String {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        let canSpeak = authorized && (recognizer?.isAvailable ?? false)
        var spoken: [String] = []
        var subtitles: [String] = []
        var heard = 0
        var failures: [String] = []
        _ = ScreenAudio.shared.report()  // what came in before this listen is not this one's
        // Build 121 on the phone, 11-11: with speech recognition denied, 视频号 was listened to twice for 180 s each
        // (6 minutes for subtitles alone), then left and opened again until the run failed. Without speech, 20 s of
        // subtitles is what a listen can give.
        let end = Date().addingTimeInterval(canSpeak ? seconds : min(seconds, 20))
        // 122 on the phone 11-11/12: all 17 listens failed at once with "kLSRErrorDomain 201: Siri and Dictation are
        // disabled": recognition on the phone itself needs Siri on. Then the rest is heard through Apple's server.
        // 134 (11-15): every listen tried the phone first and lost its first second and those words; once seen, the
        // server is used from the start until the app restarts.
        var onPhone = !Self.phoneRecognitionOff
        var over = false
        while Date() < end, !Task.isCancelled, !over {
            // One segment: a request of its own (a recognition off the phone stops at about a minute).
            let segmentEnd = min(end, Date().addingTimeInterval(55))
            var request: SFSpeechAudioBufferRecognitionRequest?
            var task: SFSpeechRecognitionTask?
            let transcript = Transcript()
            if canSpeak, let recognizer {
                let r = SFSpeechAudioBufferRecognitionRequest()
                r.shouldReportPartialResults = true
                r.addsPunctuation = true
                if onPhone, recognizer.supportsOnDeviceRecognition { r.requiresOnDeviceRecognition = true }
                task = recognizer.recognitionTask(with: r) { @Sendable result, error in
                    if let result { transcript.set(result.bestTranscription.formattedString) }
                    if let error { transcript.fail(error) }
                }
                request = r
                _ = ScreenAudio.shared.takeCount()
                ScreenAudio.shared.attach(r)
            }
            while Date() < segmentEnd, !Task.isCancelled, !over {
                if let shown = frame() {
                    for row in await CandidatePicker.rowsOffMain(in: shown, top: 0.3, bottom: 0.93) {
                        let line = row.map(\.text).joined()
                        if let ended, ended(line) { over = true }
                        if row.first.map({ Double($0.box.midY) >= 0.45 }) ?? false { subtitles = merge(subtitles, line) }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if onPhone, request != nil, transcript.error.hasPrefix("kLSRErrorDomain 201") {
                    onPhone = false
                    Self.phoneRecognitionOff = true
                    DebugLog.write("listen: recognition on the phone is off (Siri); hearing the rest through the server")
                    break
                }
            }
            if let request {
                ScreenAudio.shared.attach(nil)
                heard += ScreenAudio.shared.takeCount()
                request.endAudio()
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // the last words come in after the end
                task?.finish()
                let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { spoken.append(text) }
                if !transcript.error.isEmpty { failures.append(transcript.error) }
            }
        }
        var note = ""
        // What the model does next is said too: listening again cannot help, and going to fix it is not its job.
        let after = "再听一次也一样：不要再听，用画面字幕和看到的内容直接回答，并说明口播拿不到"
        if !authorized { note = "这台手机没有允许语音识别，听不到说的话。" + after }
        else if !canSpeak { note = "语音识别暂时不可用。" + after }
        else if heard == 0 { note = "没有收到声音：这个 App 可能不让录音，或者没有在播放" }
        let audio = ScreenAudio.shared.report()
        // 198 (Echo 197 11-28 05:48: a 6 s video with no one speaking, 「No speech detected」 reported as 「语音识别出错」):
        // that answer is the recognition's own, no error
        let noSpeech = failures.filter { $0.contains("1110") || $0.localizedCaseInsensitiveContains("No speech") }
        if note.isEmpty, heard > 0, spoken.isEmpty, !failures.isEmpty, noSpeech.count == failures.count {
            note = "没有听到有人说话（可能只有画面、音乐或环境声）"
        }
        if note.isEmpty, heard > 0, spoken.isEmpty, !failures.isEmpty {
            note = "语音识别出错，没有认出说的话。" + after  // not "only music": 122 said so for every listen that errored
        }
        if note.isEmpty, heard > 0, spoken.isEmpty {
            note = audio.silent ? "收到的声音是静音（手机音量为 0，或这个 App 不让录音）" : "收到了声音，但没有认出说的话（可能只有音乐）"
        }
        DebugLog.write("listen: audio \(audio.text)" + (failures.isEmpty ? "" : "; recognition: " + Set(failures).joined(separator: " | ")))
        DebugLog.write("listen: \(Int(seconds)) s, \(heard) audio sample(s), \(spoken.joined().count) character(s) heard, \(subtitles.count) subtitle line(s)")
        return "【语音转文字】" + (spoken.isEmpty ? "（没有）" : spoken.joined(separator: " "))
            + "\n【画面字幕】" + (subtitles.isEmpty ? "（没有）" : subtitles.joined(separator: "／"))
            + (note.isEmpty ? "" : "\n（\(note)）")
    }
}
