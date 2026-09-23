import Foundation
import STTSCore

/// Library of persisted meeting transcripts.
@MainActor
final class MeetingLibraryViewModel: ObservableObject {
    @Published private(set) var meetings: [MeetingTranscript] = []
    @Published private(set) var loadError: String?

    private let store: any MeetingStore

    init(store: any MeetingStore) {
        self.store = store
    }

    func refresh() async {
        do {
            meetings = try await store.listMeetings()
            loadError = nil
        } catch {
            loadError = "Load failed"
        }
    }

    func delete(_ meeting: MeetingTranscript) async {
        try? await store.delete(id: meeting.id)
        await refresh()
    }
}
