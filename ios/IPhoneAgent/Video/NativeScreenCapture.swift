import Foundation
import CoreMedia
import CoreImage
import ImageIO
import UniformTypeIdentifiers
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

enum DirectCaptureEvent {
    case began(UUID)
    case frame(UUID, UInt64, Data, Int, Int, Double, Double)
    case idle(UUID, UInt64, Double)
    case unavailable(UUID, UInt64, String)
    case stopped(UUID?, String)
}

#if canImport(ScreenCaptureKit)
/// Owns system consent and stream lifecycle. Only the serial output queue touches pixel buffers.
@available(iOS 27.0, *)
@MainActor final class NativeScreenCapture: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    private let deliver: (DirectCaptureEvent) -> Void
    private var stream: SCStream?
    private var output: DirectScreenOutput?
    private var generation: UUID?
    private var stopped = false
    private var shared: SCContentFilter?
    /// User 11-11: a video's spoken words. The stream carries the screen's audio too (to ScreenAudio, used only while a
    /// listen runs); a stream refused with audio is started again without it, and later ones stay without.
    private var audioRefused = false
    private let audioOutput = ScreenAudioOutput()
    private var withAudio: Bool { !audioRefused && (UserDefaults.standard.object(forKey: "captureAudioV1") as? Bool ?? true) }

    init(deliver: @escaping (DirectCaptureEvent) -> Void) { self.deliver = deliver }

    /// A new stream on what the user already agreed to share: no prompt. The stream can go quiet with no error and no
    /// way back (over USB 11-09: replayd counting screenframeCount=0 for good, sharing "on", every run refused).
    /// The old stream stays until the new one runs: iOS refuses a start in the background ("無法開始串流"), and stopping
    /// the old one first lost the sharing three times on 11-09, when it had only been quiet for a moment.
    func restart() -> Bool {
        guard !stopped, let filter = shared else { return false }
        let id = UUID()
        let audio = withAudio
        let next = SCStream(filter: filter, configuration: Self.configuration(filter, audio: audio), delegate: self)
        let sink = DirectScreenOutput(generation: id) { [weak self] event in
            Task { @MainActor in
                guard let self, !self.stopped, self.generation == id else { return }
                self.deliver(event)
            }
        }
        do {
            try next.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            if audio { try? next.addStreamOutput(audioOutput, type: .audio, sampleHandlerQueue: audioOutput.queue) }
        } catch {
            DebugLog.write("capture: no new stream: \(error.localizedDescription); keeping the one there is")
            return false
        }
        next.startCapture { [weak self] error in
            Task { @MainActor in
                guard let self, !self.stopped else { next.stopCapture { _ in }; return }
                if let error {
                    if audio { self.audioRefused = true }  // the next one goes without audio
                    DebugLog.write("capture: the new stream was refused: \(error.localizedDescription); keeping the one there is")
                    return
                }
                let previous = self.stream
                self.stream = next; self.output = sink; self.generation = id
                self.deliver(.began(id))
                previous?.stopCapture { _ in }
                DebugLog.write("capture: the new stream runs; the old one is stopped")
            }
        }
        return true
    }

    private static func configuration(_ filter: SCContentFilter, audio: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.capturesAudio = audio
        config.width = max(1, Int(filter.contentRect.width * CGFloat(filter.pointPixelScale)))
        config.height = max(1, Int(filter.contentRect.height * CGFloat(filter.pointPixelScale)))
        return config
    }

    func present() {
        let picker = SCContentSharingPicker.shared
        guard picker.isAvailable else { deliver(.stopped(nil, "系统不允许屏幕共享，请检查屏幕录制限制")); return }
        picker.add(self)
        picker.isActive = true
        picker.present(using: .display)
    }

    func stop() {
        stopped = true
        shared = nil
        let previous = stream
        stream = nil; output = nil; generation = nil
        let picker = SCContentSharingPicker.shared
        picker.remove(self); picker.isActive = false
        previous?.stopCapture { _ in }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in self?.select(filter) }
    }

    private func select(_ filter: SCContentFilter) {
        guard !stopped else { return }
        let previous = stream
        stream = nil; output = nil; generation = nil
        previous?.stopCapture { _ in }
        guard filter.style == .display else {
            deliver(.stopped(nil, "请选择共享整个屏幕；仅共享当前 App 无法操作其他 App"))
            stop(); return
        }
        shared = filter
        let id = UUID()
        generation = id
        deliver(.began(id))
        let audio = withAudio
        let next = SCStream(filter: filter, configuration: Self.configuration(filter, audio: audio), delegate: self)
        let sink = DirectScreenOutput(generation: id) { [weak self] event in
            Task { @MainActor in
                guard let self, !self.stopped, self.generation == id else { return }
                self.deliver(event)
            }
        }
        do {
            try next.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
            if audio { try? next.addStreamOutput(audioOutput, type: .audio, sampleHandlerQueue: audioOutput.queue) }
            stream = next; output = sink
            next.startCapture { [weak self] error in
                guard let error else { return }
                Task { @MainActor in
                    guard let self, !self.stopped else { return }
                    if audio {  // the screen matters more than its audio: the same share again, without audio
                        DebugLog.write("capture: refused with audio (\(error.localizedDescription)); starting without it")
                        self.audioRefused = true
                        self.select(filter)
                        return
                    }
                    self.ended(next, reason: "取屏启动失败：\(error.localizedDescription)")
                }
            }
        } catch {
            deliver(.stopped(id, "取屏启动失败：\(error.localizedDescription)"))
            stop()
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped, self.stream == nil else { return }
            self.deliver(.stopped(nil, "已取消屏幕共享")); self.stop()
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.stopped else { return }
            self.deliver(.stopped(self.generation, "共享选择器失败：\(error.localizedDescription)")); self.stop()
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in self?.ended(stream, reason: "系统已停止屏幕共享：\(error.localizedDescription)") }
    }

    private func ended(_ ended: SCStream, reason: String) {
        guard !stopped, stream === ended else { return }
        deliver(.stopped(generation, reason)); stop()
    }
}

@available(iOS 27.0, *)
private final class ScreenAudioOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "LanAgent.screen-audio", qos: .userInitiated)
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferIsValid(sample) else { return }
        ScreenAudio.shared.take(sample)
    }
}

@available(iOS 27.0, *)
private final class DirectScreenOutput: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "LanAgent.direct-screen", qos: .userInitiated)
    private let generation: UUID
    private let deliver: (DirectCaptureEvent) -> Void
    // Software rendering also works when the agent is behind another app.
    private let context = CIContext(options: [.useSoftwareRenderer: true, .cacheIntermediates: false])
    private var sequence: UInt64 = 0
    private var lastRender = -Double.infinity
    private var pending: (CVPixelBuffer, Double, Int32)?
    private var pendingConfirmation: Double?
    private var lastProof = -Double.infinity
    private var flushScheduled = false

    init(generation: UUID, deliver: @escaping (DirectCaptureEvent) -> Void) {
        self.generation = generation; self.deliver = deliver
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferIsValid(sample),
              let info = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = info.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else {
            unavailable("系统尚未提供完整画面"); return
        }
        let clock: Double, timestamp: Double
        if let ticks = info.first?[.displayTime] as? UInt64, ticks > 0 {
            clock = CMClockGetTime(CMClockGetHostTimeClock()).seconds
            timestamp = CMClockMakeHostTimeFromSystemUnits(ticks).seconds
        } else {
            clock = CMClockGetTime(stream.synchronizationClock ?? CMClockGetHostTimeClock()).seconds
            timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
        }
        guard let captured = DirectFrameState.localTimestamp(sampleTime: timestamp, clockTime: clock, receivedAt: now()) else {
            unavailable("系统画面已过期，等待新画面"); return
        }
        switch status {
        case .complete:
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { unavailable("画面缺少像素"); return }
            let orientation = (info.first?[.videoOrientation] as? NSNumber)?.uint32Value ?? CGImagePropertyOrientation.up.rawValue
            guard CGImagePropertyOrientation(rawValue: orientation) != nil else { unavailable("未知画面方向"); return }
            // Keep one newest frame; never build a conversion backlog.
            pending = (pixels, captured, Int32(orientation))
            pendingConfirmation = nil
            if now() - lastRender >= 0.25 { flush() }
            else if !flushScheduled {
                flushScheduled = true
                queue.asyncAfter(deadline: .now() + max(0, 0.25 - (now() - lastRender))) { [weak self] in
                    self?.flushScheduled = false; self?.flush()
                }
            }
        case .idle:
            if pending != nil {
                // The scheduled flush publishes the last changed pixels before this proof.
                pendingConfirmation = captured
            } else if now() - lastProof >= 0.25 {
                lastProof = now()
                sequence += 1; deliver(.idle(generation, sequence, captured))
            }
        case .stopped:
            unavailable("系统已停止提供画面，请重新共享整个屏幕")
        case .blank, .suspended, .started:
            unavailable("屏幕暂不可用或共享暂停，等待画面恢复")
        @unknown default:
            unavailable("未知取屏状态，等待完整画面")
        }
    }

    private func unavailable(_ reason: String) {
        pending = nil; pendingConfirmation = nil
        sequence += 1; deliver(.unavailable(generation, sequence, reason))
    }

    private func flush() {
        guard let (pixels, timestamp, orientation) = pending else { return }
        pending = nil
        let began = now()
        lastRender = began; lastProof = began
        autoreleasepool {
            let image = CIImage(cvPixelBuffer: pixels).oriented(forExifOrientation: orientation)
            guard image.extent.width > 0, image.extent.height > image.extent.width else {
                unavailable("请保持手机竖屏；横屏画面暂停操作"); return
            }
            let scale = min(1, 1280 / max(image.extent.width, image.extent.height))
            let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(resized, from: resized.extent) else { unavailable("画面转换失败"); return }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                unavailable("无法编码画面"); return
            }
            CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { unavailable("画面编码失败"); return }
            sequence += 1
            deliver(.frame(generation, sequence, data as Data, cg.width, cg.height, timestamp, (now() - began) * 1000))
            if let confirmation = pendingConfirmation, confirmation >= timestamp {
                sequence += 1; deliver(.idle(generation, sequence, confirmation))
            }
            pendingConfirmation = nil
        }
    }
}
#endif
