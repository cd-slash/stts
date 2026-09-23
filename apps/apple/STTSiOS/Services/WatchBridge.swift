import Foundation
import STTSCore
import WatchConnectivity

/// Phone-side WatchConnectivity bridge: receives control commands and
/// transferred voice-note files from the watch, coordinates meeting
/// start/stop/marker state and playback/work interruption, and pushes compact
/// state updates plus reply audio back to the watch.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate, ObservableObject {
    private weak var meetings: MeetingCoordinator?
    private weak var conversation: ConversationController?
    private weak var playback: AudioPlaybackService?

    func bind(
        meetings: MeetingCoordinator,
        conversation: ConversationController,
        playback: AudioPlaybackService
    ) {
        self.meetings = meetings
        self.conversation = conversation
        self.playback = playback
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Commands from the watch

    private func dispatch(command: String, label: String?) {
        switch command {
        case "meeting.start":
            meetings?.start()
        case "meeting.stop":
            meetings?.stopAndSave()
        case "meeting.mark":
            meetings?.addMarker(label: label)
        case "playback.stop":
            playback?.stop()
        case "work.stop":
            conversation?.stopWork()
        default:
            break
        }
    }

    private func handleVoiceNote(at url: URL) {
        conversation?.submitVoiceNote(at: url)
    }

    // MARK: State to the watch

    func pushState() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        var context: [String: Any] = [:]
        if let meetings {
            context["meetingState"] = meetings.watchStateName
            if meetings.state == .recording || meetings.state == .paused {
                context["meetingStartedAtEpochMs"] = Int(meetings.startedAt.timeIntervalSince1970 * 1000)
            }
        } else {
            context["meetingState"] = "idle"
        }
        if let conversation {
            context["replyText"] = conversation.replyText
        }
        try? session.updateApplicationContext(context)
    }

    /// Relays a synthesized coordinator reply to the watch as an audio file.
    /// The watch plays it; the phone also plays it locally.
    func relayReply(text: String, audio: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stts-watch-reply-\(UUID().uuidString).mp3")
        do {
            try audio.write(to: url, options: .atomic)
        } catch {
            return
        }
        session.transferFile(url, metadata: ["kind": "reply-audio"])
        pushState()
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.pushState()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let command = message["command"] as? String
        let label = message["label"] as? String
        Task { @MainActor in
            guard let command else { return }
            self.dispatch(command: command, label: label)
            self.pushState()
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Incoming files are temporary; copy before the callback returns.
        guard (file.metadata?["kind"] as? String) == "voice-note" else { return }
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("stts-watch-note-\(UUID().uuidString).m4a")
        do {
            try FileManager.default.copyItem(at: file.fileURL, to: target)
        } catch {
            return
        }
        Task { @MainActor in
            self.handleVoiceNote(at: target)
        }
    }
}
