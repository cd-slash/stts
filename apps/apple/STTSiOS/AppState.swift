import Foundation
import STTSCore

/// Composition root: configuration, credential state, client construction,
/// and wiring between the conversation, meetings, playback, and watch bridge.
@MainActor
final class AppState: ObservableObject {
    private static let serverURLKey = "stts.serverURL"

    /// The process-wide composition root. CarPlay scenes have no SwiftUI
    /// environment, so its scene delegate reaches the app through here.
    private(set) static var current: AppState?

    @Published var serverURLString: String {
        didSet {
            UserDefaults.standard.set(serverURLString, forKey: Self.serverURLKey)
            rebuildClient()
        }
    }
    @Published private(set) var credentialConfigured = false
    @Published private(set) var client: STTSClient?

    let credentials = KeychainCredentialStore()
    let playback: AudioPlaybackService
    let conversation: ConversationController
    let voiceNotes: VoiceNoteViewModel
    let meetings: MeetingCoordinator
    let library: MeetingLibraryViewModel
    let watch: WatchBridge

    init() {
        serverURLString = UserDefaults.standard.string(forKey: Self.serverURLKey) ?? ""

        let meetingStore = JSONFileMeetingStore(directory: Self.meetingsDirectory())
        let playback = AudioPlaybackService()
        self.playback = playback
        let conversation = ConversationController(playback: playback)
        self.conversation = conversation
        let voiceNotes = VoiceNoteViewModel()
        self.voiceNotes = voiceNotes
        let meetings = MeetingCoordinator(store: meetingStore)
        self.meetings = meetings
        self.library = MeetingLibraryViewModel(store: meetingStore)
        let watch = WatchBridge()
        self.watch = watch

        voiceNotes.onFinished = { [weak conversation] url in
            conversation?.submitVoiceNote(at: url)
        }
        meetings.onStateChange = { [weak watch] in
            watch?.pushState()
        }
        conversation.onReplyAudio = { [weak watch] text, audio in
            watch?.relayReply(text: text, audio: audio)
        }
        watch.bind(meetings: meetings, conversation: conversation, playback: playback)

        rebuildClient()
        conversation.clientProvider = { [weak self] in self?.client }
        meetings.clientProvider = { [weak self] in self?.client }
        watch.activate()
        watch.pushState()
        AppState.current = self
    }

    // MARK: Configuration

    var isConfigured: Bool {
        client != nil && credentialConfigured
    }

    /// True when the configured server URL would send Access credentials over
    /// cleartext. Intended for local development only.
    var usesInsecureTransport: Bool {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed)?.scheme?.lowercased() == "http"
    }

    /// Runs once at launch: clears audio left by a previous run and promotes a
    /// draft abandoned by a crash or termination into a saved transcript.
    func recoverAfterLaunch() async {
        MeetingCoordinator.pruneOrphanedAudio(protecting: watch.outstandingTransferPaths)
        await meetings.recoverUnfinishedMeetings()
        await library.refresh()
    }

    func storeCredential(_ credential: Credential) throws {
        try credentials.store(credential)
        credentialConfigured = true
        rebuildClient()
    }

    func removeCredential() {
        try? credentials.clear()
        credentialConfigured = false
        rebuildClient()
    }

    private func rebuildClient() {
        credentialConfigured = credentials.hasCredential()
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else {
            client = nil
            return
        }
        client = STTSClient(baseURL: url, credentials: credentials)
    }

    private static func meetingsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Meetings", isDirectory: true)
    }
}
