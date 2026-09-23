import AVFoundation
import Foundation
import STTSCore

/// Records a single voice-note file and hands it to the conversation
/// controller on stop.
@MainActor
final class VoiceNoteViewModel: ObservableObject {
    enum CapturePhase: Equatable {
        case idle
        case recording
    }

    @Published private(set) var capturePhase: CapturePhase = .idle
    @Published private(set) var captureElapsedMs = 0
    @Published private(set) var captureError: String?

    /// Invoked on the main actor after capture finishes; assigned by the app
    /// root to hand the file to the conversation controller.
    var onFinished: (@MainActor (URL) -> Void)?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        guard capturePhase == .idle else { return }
        do {
            try AudioSessionConfig.activateRecording()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("stts-voice-note-\(UUID().uuidString).m4a")
            let recorder = try RecorderFactory.makeRecorder(url: url)
            guard recorder.record() else {
                throw STTSClientError.transport("Recorder start failed")
            }
            self.recorder = recorder
            fileURL = url
            captureElapsedMs = 0
            captureError = nil
            capturePhase = .recording
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } catch {
            captureError = "Recording unavailable"
        }
    }

    func stop() {
        guard capturePhase == .recording else { return }
        stopCapture()
        capturePhase = .idle
        guard let url = fileURL else { return }
        fileURL = nil
        onFinished?(url)
    }

    func discard() {
        guard capturePhase == .recording else { return }
        stopCapture()
        capturePhase = .idle
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
    }

    private func tick() {
        guard capturePhase == .recording else { return }
        captureElapsedMs = Int((recorder?.currentTime ?? 0) * 1000)
    }

    private func stopCapture() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
    }
}
