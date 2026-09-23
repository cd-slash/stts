import AVFoundation
import Foundation
import STTSCore
import WatchConnectivity

/// Foreground-only voice-note capture on watchOS. On stop, the file is handed
/// to the phone via `WCSession.transferFile`; the phone transcribes and
/// submits it. Long-form recording is intentionally not attempted here.
@MainActor
final class WatchVoiceNoteRecorder: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case sent
        case failed(String)
    }

    static let maxDurationSeconds: TimeInterval = 60

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        guard phase != .recording else { return }
        do {
            try WatchAudioSession.activateRecording()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("stts-watch-note-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                throw STTSClientError.transport("Recorder start failed")
            }
            self.recorder = recorder
            fileURL = url
            elapsed = 0
            phase = .recording
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } catch {
            phase = .failed("Recording unavailable")
        }
    }

    func stopAndSend() {
        guard phase == .recording else { return }
        stopCapture()
        guard let url = fileURL else {
            phase = .failed("Recording unavailable")
            return
        }
        fileURL = nil
        guard WCSession.isSupported() else {
            phase = .failed("Phone unavailable")
            try? FileManager.default.removeItem(at: url)
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            phase = .failed("Phone unavailable")
            try? FileManager.default.removeItem(at: url)
            return
        }
        session.transferFile(url, metadata: ["kind": "voice-note"])
        phase = .sent
    }

    func cancel() {
        guard phase == .recording else { return }
        stopCapture()
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        phase = .idle
    }

    func reset() {
        phase = .idle
        elapsed = 0
    }

    private func tick() {
        guard phase == .recording else { return }
        elapsed = recorder?.currentTime ?? 0
        if elapsed >= Self.maxDurationSeconds {
            stopAndSend()
        }
    }

    private func stopCapture() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
    }
}
