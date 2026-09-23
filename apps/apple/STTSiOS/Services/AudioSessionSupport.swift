import AVFoundation
import Foundation

enum AudioSessionConfig {
    /// Capture-only category; used for voice notes and meeting segments.
    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true)
    }

    /// Playback category for synthesized replies. Switching categories while a
    /// meeting records is avoided: capture re-activates `.record` when the
    /// next segment opens.
    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }
}

enum RecorderFactory {
    /// AAC in an m4a container; uploaded with MIME type `audio/mp4`, which the
    /// Worker's speech adapter maps to the `.m4a` filename extension.
    static func makeRecorder(url: URL) throws -> AVAudioRecorder {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000
        ]
        return try AVAudioRecorder(url: url, settings: settings)
    }
}
