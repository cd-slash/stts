import SwiftUI
import STTSCore

struct MeetingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MeetingsContent(library: appState.library, meetings: appState.meetings)
            .navigationTitle("Meetings")
    }
}

private struct MeetingsContent: View {
    @ObservedObject var library: MeetingLibraryViewModel
    @ObservedObject var meetings: MeetingCoordinator

    var body: some View {
        List {
            if let message = library.loadError {
                Text(message).foregroundStyle(.red)
            }
            if library.meetings.isEmpty {
                Text("No meetings").foregroundStyle(.secondary)
            }
            ForEach(library.meetings) { meeting in
                NavigationLink {
                    MeetingTranscriptView(meeting: meeting)
                } label: {
                    VStack(alignment: .leading) {
                        Text(meeting.title)
                        Text("\(Self.dateText(meeting.startedAt)) · \(STTSTimeFormat.clockString(ms: meeting.durationMs))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .onDelete { offsets in
                let doomed = offsets.map { library.meetings[$0] }
                Task {
                    for meeting in doomed {
                        await library.delete(meeting)
                    }
                }
            }
        }
        .refreshable {
            await library.refresh()
        }
        .task {
            await library.refresh()
        }
        .onChange(of: meetings.state) { _, newState in
            if newState == .saved {
                Task { await library.refresh() }
            }
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
