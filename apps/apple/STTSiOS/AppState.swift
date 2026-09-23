import Foundation
import STTSCore

/// Composition root: configuration, credential state, client construction,
/// and wiring between the conversation, meetings, playback, and watch bridge.
@MainActor
final class AppState: ObservableObject {
    private static let serverURLKey = "stts.serverURL"

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
    }

    // MARK: Configuration

    var isConfigured: Bool {
        client != nil && credentialConfigured
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
