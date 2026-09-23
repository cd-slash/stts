import AVFoundation
import Foundation
import WatchConnectivity

/// Watch-side link to the phone. The watch never holds a credential and never
/// talks to the Worker: voice notes travel as transferred files, meeting
/// control travels as messages, state arrives via the application context,
/// and reply audio arrives as a transferred file from the phone.
@MainActor
final class PhoneLink: NSObject, WCSessionDelegate, ObservableObject {
    @Published private(set) var meetingState = "idle"
    @Published private(set) var meetingStartedAtEpochMs: Int?
    @Published private(set) var replyText: String?
    @Published private(set) var statusMessage: String?

    private var player: AVAudioPlayer?

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Commands to the phone

    func startMeeting() {
        send(["command": "meeting.start"])
    }

    func stopMeeting() {
        send(["command": "meeting.stop"])
    }

    func addMarker() {
        send(["command": "meeting.mark", "label": "Marker"])
    }

    func stopPlayback() {
        send(["command": "playback.stop"])
    }

    func stopWork() {
        send(["command": "work.stop"])
    }

    private func send(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            session.transferUserInfo(message)
            return
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    // MARK: Reply playback

    private func playReplyAudio(at url: URL) {
        do {
            try WatchAudioSession.activatePlayback()
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.play()
        } catch {
            statusMessage = "Playback failed"
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let state = applicationContext["meetingState"] as? String
        let started = applicationContext["meetingStartedAtEpochMs"] as? Int
        let reply = applicationContext["replyText"] as? String
        Task { @MainActor in
            if let state {
                self.meetingState = state
            }
            self.meetingStartedAtEpochMs = started
            if let reply, !reply.isEmpty {
                self.replyText = reply
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Incoming files are temporary; copy before the callback returns.
        guard (file.metadata?["kind"] as? String) == "reply-audio" else { return }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("stts-watch-reply-\(UUID().uuidString).mp3")
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: target)
        } catch {
            return
        }
        Task { @MainActor in
            self.playReplyAudio(at: target)
        }
    }
}
