import SwiftUI
import STTSCore

struct VoiceNoteView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VoiceNoteContent(
            voice: appState.voiceNotes,
            conversation: appState.conversation,
            playback: appState.playback
        )
        .navigationTitle("Voice")
    }
}

private struct VoiceNoteContent: View {
    @ObservedObject var voice: VoiceNoteViewModel
    @ObservedObject var conversation: ConversationController
    @ObservedObject var playback: AudioPlaybackService

    @State private var draftText = ""
    @State private var clarificationText = ""

    var body: some View {
        Form {
            captureSection
            transcriptSection
            if !conversation.replyText.isEmpty {
                replySection
            }
            textInputSection
        }
    }

    @ViewBuilder private var captureSection: some View {
        Section("Voice note") {
            if voice.capturePhase == .recording {
                Text(STTSTimeFormat.clockString(ms: voice.captureElapsedMs))
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Recording elapsed time")
                Button("Stop and submit") {
                    voice.stop()
                }
                .accessibilityLabel("Stop recording and submit")
                Button("Discard", role: .destructive) {
                    voice.discard()
                }
                .accessibilityLabel("Discard recording")
            } else {
                Button {
                    voice.start()
                } label: {
                    Label("Record", systemImage: "mic")
                }
                .accessibilityLabel("Start recording")
                if let message = voice.captureError {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder private var transcriptSection: some View {
        Section("Transcript") {
            switch conversation.phase {
            case .transcribing:
                HStack {
                    ProgressView()
                    Text("Transcribing")
                }
            case .submitting:
                HStack {
                    ProgressView()
                    Text("Submitting")
                }
                Button("Stop work") {
                    conversation.stopWork()
                }
                .accessibilityLabel("Stop agent work")
            case .awaitingInput(let pending):
                Text(pending.prompt).textSelection(.enabled)
                if pending.kind == .approval {
                    Button("Approve") {
                        conversation.approvePending()
                    }
                    Button("Deny", role: .destructive) {
                        conversation.denyPending()
                    }
                } else {
                    TextField("Answer", text: $clarificationText)
                        .accessibilityLabel("Clarification answer")
                    Button("Answer") {
                        conversation.answerPending(text: clarificationText)
                        clarificationText = ""
                    }
                    .disabled(clarificationText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            case .failed(let message):
                Text(message).foregroundStyle(.red)
                if conversation.hasPendingVoiceNote {
                    Button("Retry transcription") {
                        conversation.retryPendingVoiceNote()
                    }
                    Button("Discard recording", role: .destructive) {
                        conversation.discardPendingVoiceNote()
                    }
                }
            case .idle:
                if conversation.recognizedText.isEmpty {
                    Text("No transcript").foregroundStyle(.secondary)
                } else {
                    Text(conversation.recognizedText).textSelection(.enabled)
                }
            }
        }
    }

    private var replySection: some View {
        Section("Reply") {
            Text(conversation.replyText).textSelection(.enabled)
            Button("Play reply") {
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

    private var textInputSection: some View {
        Section("Text") {
            TextField("Text", text: $draftText, axis: .vertical)
                .accessibilityLabel("Turn text")
            Button("Submit") {
                conversation.submitText(draftText)
                draftText = ""
            }
            .disabled(
                draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || conversation.isBusy
            )
        }
    }
}
