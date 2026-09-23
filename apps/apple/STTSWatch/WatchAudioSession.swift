import AVFoundation
import Foundation

enum WatchAudioSession {
    /// watchOS capture uses `.playAndRecord`; watchOS apps are foreground-only
    /// for recording, and long-form capture is intentionally not attempted.
    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [])
        try session.setActive(true)
    }

    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }
}
