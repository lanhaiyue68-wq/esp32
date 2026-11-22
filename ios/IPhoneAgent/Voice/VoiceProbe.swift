import AVFoundation

/// SPIKE, build 157 (throwaway; user 11-22): the client wants bulk WeChat voice messages in his own cloned voice. Can
/// WeChat's 按住说话 record a clip this app plays while the board holds the button down (plan A: no hardware)?
/// Run only over the USB test channel: /gesture {"do":"voicetest","x":…,"y":…,"mode":"playback"|"speaker"}.
/// No task uses it. "playback" plays the way the background audio already does (mixable, never taking focus);
/// "speaker" plays with .playAndRecord + .defaultToSpeaker (the bottom speaker, next to the microphone), then puts
/// the session back.
@MainActor enum VoiceProbe {
    /// Seconds of the last clip played to its end, or -1 when it did not play.
    private(set) static var lastPlayed: Double = -1
    /// Where the sound went (speaker, receiver…) while it played.
    private(set) static var lastRoute = ""
    private static var player: AVAudioPlayer?

    /// Plays Voice/voice-probe.wav to its end at full volume.
    static func play(mode: String) async {
        lastPlayed = -1
        lastRoute = ""
        guard let url = Bundle.main.url(forResource: "voice-probe", withExtension: "wav"),
              let clip = try? AVAudioPlayer(contentsOf: url) else {
            DebugLog.write("voice probe: no clip in the bundle")
            return
        }
        let session = AVAudioSession.sharedInstance()
        let speaker = mode == "speaker"
        do {
            if speaker {
                try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
            } else {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
        } catch {
            DebugLog.write("voice probe: session for \(mode) failed: \(error.localizedDescription)")
            return
        }
        clip.volume = 1
        player = clip
        guard clip.play() else {
            DebugLog.write("voice probe: the clip did not start")
            player = nil
            return
        }
        lastRoute = session.currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: ",")
        DebugLog.write("voice probe: playing \(String(format: "%.1f", clip.duration)) s, \(mode), to \(lastRoute)")
        try? await Task.sleep(nanoseconds: UInt64((clip.duration + 0.2) * 1_000_000_000))
        clip.stop()
        player = nil
        lastPlayed = clip.duration
        if speaker {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
    }
}
