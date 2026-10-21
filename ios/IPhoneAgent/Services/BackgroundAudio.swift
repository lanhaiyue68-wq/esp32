import AVFoundation

/// Keeps the app running in the background for the length of a run by playing silence (UIBackgroundModes `audio`).
/// The app operates the iPhone it runs on, so it is always in the background while it works. With only
/// `bluetooth-central`, iOS suspended it within seconds: the Wi-Fi video socket died, frames fell back to BLE and
/// arrived seconds late, and starts failed "no verified current video frame". For self-signed / enterprise builds,
/// not the App Store.
///
/// Everything else on the phone comes first: a mixable `.playback` session never takes audio focus or ducks anyone
/// (ringtones, notifications, alarms, music and videos play as usual), a call interrupts it and it resumes only
/// once the call is over, and it never records or uses the receiver (no microphone permission, no input node,
/// no voice-chat mode, no route override). The speaker stays the system's: digital silence at mixer volume 0,
/// mixed with everyone else's sound, never exclusive. iOS has no way to stay alive with background audio without
/// an output at all.
@MainActor final class BackgroundAudio {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var wanted = false
    private var retry: Task<Void, Never>?
    private(set) var playing = false

    init() {
        let center = NotificationCenter.default
        // A call or Siri stops our audio; resume when it ends, or iOS suspends the run a few seconds later.
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            MainActor.assumeIsolated { self?.interrupted(began: began) }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart("media services were reset") }
        }
        center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart("audio configuration changed") }
        }
    }

    /// From just before the app leaves the screen until the run ends. False (and logged) if audio could not start:
    /// the run still goes on, as before, on BLE wake-ups alone.
    @discardableResult
    func start() -> Bool {
        wanted = true
        return begin()
    }

    func stop() {
        guard wanted else { return }
        wanted = false
        retry?.cancel()
        retry = nil
        engine.stop()
        playing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        DebugLog.write("background audio: stopped")
    }

    private func begin() -> Bool {
        guard wanted, !playing else { return playing }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if source == nil {
                let node = Self.silence()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
                engine.mainMixerNode.outputVolume = 0  // zeros at zero volume: nothing ever reaches the speaker
                source = node
            }
            try engine.start()
            playing = true
            DebugLog.write("background audio: playing silence to keep the run alive")
            return true
        } catch {
            playing = false
            DebugLog.write("background audio: could not start: \(error.localizedDescription)")
            scheduleRetry()
            return false
        }
    }

    /// Activation fails while a call holds the audio (a run started mid-call): try again every 5 s, so the run is kept
    /// alive again as soon as the call is over. BLE wake-ups keep this going in the meantime.
    private func scheduleRetry() {
        guard wanted, retry == nil else { return }
        retry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.wanted, !self.playing else { break }
                _ = self.begin()  // a failure here finds `retry` set and schedules nothing new
            }
            self?.retry = nil
        }
    }

    private func interrupted(began: Bool) {
        guard wanted else { return }
        if began {
            playing = false
            DebugLog.write("background audio: interrupted (call or Siri)")
        } else {
            restart("interruption ended")
        }
    }

    private func restart(_ why: String) {
        guard wanted else { return }
        DebugLog.write("background audio: restarting, \(why)")
        engine.stop()
        playing = false
        _ = begin()
    }

    /// Zeros on the real-time audio thread: built outside the main actor so the block carries no actor isolation.
    nonisolated private static func silence() -> AVAudioSourceNode {
        AVAudioSourceNode { _, _, _, buffers in
            for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
    }
}
