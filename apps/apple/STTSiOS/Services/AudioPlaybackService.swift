import AVFoundation
import Foundation

/// Plays synthesized coordinator replies. Reply audio is ephemeral: the temp
/// file is deleted when playback stops or finishes.
@MainActor
final class AudioPlaybackService: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var playerFileURL: URL?

    func play(mp3Data: Data) throws {
        stop()
        try AudioSessionConfig.activatePlayback()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stts-reply-\(UUID().uuidString).mp3")
        try mp3Data.write(to: url, options: .atomic)
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        playerFileURL = url
        self.player = player
        isPlaying = true
        player.play()
    }

    func stop() {
        player?.stop()
        player = nil
        removeFile()
        isPlaying = false
    }

    private func removeFile() {
        if let playerFileURL {
            try? FileManager.default.removeItem(at: playerFileURL)
        }
        playerFileURL = nil
    }

    nonisolated private func finished() {
        Task { @MainActor in
            self.player = nil
            self.removeFile()
            self.isPlaying = false
        }
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finished()
    }
}
