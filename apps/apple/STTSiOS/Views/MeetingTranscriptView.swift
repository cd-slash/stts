import SwiftUI
import STTSCore

struct MeetingTranscriptView: View {
    @EnvironmentObject var appState: AppState

    let meeting: MeetingTranscript

    var body: some View {
        TranscriptContent(
            meeting: meeting,
            conversation: appState.conversation,
            playback: appState.playback
        )
        .navigationTitle(meeting.title)
    }
}

private struct TranscriptContent: View {
    let meeting: MeetingTranscript
    @ObservedObject var conversation: ConversationController
    @ObservedObject var playback: AudioPlaybackService

    @State private var summarizeRequested = false

    var body: some View {
        List {
            summarizeSection
            transcriptSection
            if !meeting.markers.isEmpty {
                markersSection
            }
        }
    }

    @ViewBuilder private var summarizeSection: some View {
        Section("Summarize") {
            Button("Summarize") {
                summarizeRequested = true
                conversation.summarize(meeting: meeting)
            }
            .disabled(conversation.isBusy || meeting.assembledText.isEmpty)
            .accessibilityLabel("Summarize meeting transcript")

            if summarizeRequested {
                switch conversation.phase {
                case .submitting:
                    HStack {
                        ProgressView()
                        Text("Submitting")
                    }
                case .transcribing:
                    HStack {
                        ProgressView()
                        Text("Transcribing")
                    }
                case .failed(let message):
                    Text(message).foregroundStyle(.red)
                default:
                    EmptyView()
                }
                if !conversation.replyText.isEmpty {
                    Text(conversation.replyText).textSelection(.enabled)
                    Button("Play") {
                        Task { await conversation.playReply() }
                    }
                    .disabled(!conversation.canPlayReply)
                    Button("Stop playback") {
                        conversation.stopPlayback()
                    }
                    .disabled(!playback.isPlaying)
                    Button("Stop work") {
                        conversation.stopWork()
                    }
                    .accessibilityLabel("Stop agent work")
                }
            }
        }
    }

    @ViewBuilder private var transcriptSection: some View {
        Section("Transcript") {
            if meeting.segments.isEmpty {
                Text("No transcript").foregroundStyle(.secondary)
            }
            ForEach(meeting.segments, id: \.index) { entry in
                HStack(alignment: .top) {
                    Text(STTSTimeFormat.clockString(ms: entry.startedAtMs))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    switch entry.status {
                    case .transcribed:
                        Text(entry.text)
                    case .pending:
                        Text("Processing").foregroundStyle(.secondary)
                    case .failed:
                        Text("Segment failed").foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var markersSection: some View {
        Section("Markers") {
            ForEach(meeting.markers) { marker in
                HStack {
                    Text(STTSTimeFormat.clockString(ms: marker.atOffsetMs))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(marker.label)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
