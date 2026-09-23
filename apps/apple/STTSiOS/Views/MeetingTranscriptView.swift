import SwiftUI
import STTSCore

/// One transcript line: a narrow leading `mm:ss` column in tabular figures
/// and the text in the body column.
struct TranscriptRow: View {
    enum Content {
        case text(String)
        case processing
        case failedSegment
    }

    let startedAtMs: Int
    let content: Content

    /// Minimum width for the leading column. It is a minimum rather than a
    /// fixed width so a long timestamp (`100:00`) or a large Dynamic Type size
    /// widens the column instead of truncating.
    static let timeColumnMinWidth: CGFloat = 44

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(STTSTimeFormat.clockString(ms: startedAtMs))
                .font(.sttsCaptionTabular)
                .foregroundStyle(Color.sttsInkMuted)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: Self.timeColumnMinWidth, alignment: .leading)
            switch content {
            case .text(let text):
                Text(text)
                    .font(.sttsBody)
                    .foregroundStyle(Color.sttsInk)
                    .textSelection(.enabled)
            case .processing:
                Text("Processing")
                    .font(.sttsCaption)
                    .foregroundStyle(Color.sttsInkMuted)
            case .failedSegment:
                Text("Segment failed")
                    .font(.sttsCaption)
                    .foregroundStyle(Color.sttsAlert)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One marker line in the same reading layout.
struct MarkerRow: View {
    let atOffsetMs: Int
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(STTSTimeFormat.clockString(ms: atOffsetMs))
                .font(.sttsCaptionTabular)
                .foregroundStyle(Color.sttsInkMuted)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: TranscriptRow.timeColumnMinWidth, alignment: .leading)
            Text(label)
                .font(.sttsBody)
                .foregroundStyle(Color.sttsInk)
        }
        .accessibilityElement(children: .combine)
    }
}

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
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TranscriptContent: View {
    let meeting: MeetingTranscript
    @ObservedObject var conversation: ConversationController
    @ObservedObject var playback: AudioPlaybackService

    @State private var summarizeRequested = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summarizeHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                Rectangle()
                    .fill(Color.sttsHairline)
                    .frame(height: 1)
                transcriptBody
                markersBody
            }
        }
        .background(Color.sttsVoid.ignoresSafeArea())
    }

    // MARK: Summarize — the single action at the top

    @ViewBuilder
    private var summarizeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Summarize") {
                summarizeRequested = true
                conversation.summarize(meeting: meeting)
            }
            .disabled(conversation.isBusy || meeting.assembledText.isEmpty)
            .font(.sttsBody)
            .accessibilityLabel("Summarize meeting transcript")

            if summarizeRequested {
                if conversation.summaryTruncated {
                    Text("Truncated")
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsAlert)
                }
                switch conversation.phase {
                case .submitting:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Submitting")
                            .font(.sttsCaption)
                            .foregroundStyle(Color.sttsInkMuted)
                    }
                case .transcribing:
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Transcribing")
                            .font(.sttsCaption)
                            .foregroundStyle(Color.sttsInkMuted)
                    }
                case .failed(let message):
                    Text(message)
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsAlert)
                default:
                    EmptyView()
                }
                if !conversation.replyText.isEmpty {
                    Text(conversation.replyText)
                        .font(.sttsBody)
                        .foregroundStyle(Color.sttsInk)
                        .textSelection(.enabled)
                    HStack(spacing: 24) {
                        if conversation.canPlayReply {
                            Button("Play") {
                                Task { await conversation.playReply() }
                            }
                        }
                        if playback.isPlaying {
                            Button("Stop playback") {
                                conversation.stopPlayback()
                            }
                        }
                        Button("Stop work") {
                            conversation.stopWork()
                        }
                        .accessibilityLabel("Stop agent work")
                    }
                    .font(.sttsCaption)
                }
            }
        }
    }

    // MARK: Reading surface

    @ViewBuilder
    private var transcriptBody: some View {
        if meeting.segments.isEmpty {
            Text("No transcript")
                .font(.sttsCaption)
                .foregroundStyle(Color.sttsInkMuted)
                .padding(20)
        } else {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(meeting.segments, id: \.index) { entry in
                    TranscriptRow(
                        startedAtMs: entry.startedAtMs,
                        content: content(of: entry)
                    )
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var markersBody: some View {
        if !meeting.markers.isEmpty {
            Rectangle()
                .fill(Color.sttsHairline)
                .frame(height: 1)
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(meeting.markers) { marker in
                    MarkerRow(atOffsetMs: marker.atOffsetMs, label: marker.label)
                }
            }
            .padding(20)
        }
    }

    private func content(of entry: TranscriptEntry) -> TranscriptRow.Content {
        switch entry.status {
        case .transcribed: .text(entry.text)
        case .pending: .processing
        case .failed: .failedSegment
        }
    }
}
