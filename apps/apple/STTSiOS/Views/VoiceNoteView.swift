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
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct VoiceNoteContent: View {
    @ObservedObject var voice: VoiceNoteViewModel
    @ObservedObject var conversation: ConversationController
    @ObservedObject var playback: AudioPlaybackService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftText = ""
    @State private var clarificationText = ""

    private static let bubbleRadius: CGFloat = 18

    private var isRecording: Bool { voice.capturePhase == .recording }

    private var draftIsEmpty: Bool {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            statusLine
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            if hasConversationContent {
                conversationCanvas
            } else {
                stateCanvas
            }
            composerZone
        }
        .background(Color.sttsVoid.ignoresSafeArea())
    }

    // MARK: Status line

    private var statusLine: some View {
        Text(statusText)
            .font(.sttsCaption)
            .foregroundStyle(statusIsError ? Color.sttsAlert : Color.sttsInkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        if isRecording { return "Recording" }
        if let message = voice.captureError { return message }
        switch conversation.phase {
        case .idle:
            return "Ready"
        case .transcribing:
            return "Transcribing"
        case .submitting:
            return "Submitting"
        case .awaitingInput(let pending):
            return pending.kind == .approval ? "Approval" : "Clarification"
        case .failed(let message):
            return message
        }
    }

    private var statusIsError: Bool {
        if isRecording { return false }
        if voice.captureError != nil { return true }
        if case .failed = conversation.phase { return true }
        return false
    }

    // MARK: Canvas

    private var hasConversationContent: Bool {
        if !conversation.recognizedText.isEmpty { return true }
        if !conversation.replyText.isEmpty { return true }
        // Any pending input is content, even with an empty prompt: the answer
        // controls only render on the canvas, so treating it as empty would
        // make the request impossible to answer.
        if case .awaitingInput = conversation.phase { return true }
        return false
    }

    private var stateWord: String {
        if isRecording { return "Recording" }
        return switch conversation.phase {
        case .idle: "Ready"
        case .transcribing: "Transcribing"
        case .submitting: "Submitting"
        case .awaitingInput(let pending): pending.kind == .approval ? "Approval" : "Clarification"
        case .failed: "Failed"
        }
    }

    /// Empty state: a single display-weight state word, nothing else.
    private var stateCanvas: some View {
        ZStack {
            Spacer()
            Text(stateWord)
                .sttsDisplay()
                .foregroundStyle(isRecording ? Color.sttsLive : Color.sttsInk)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var conversationCanvas: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !conversation.recognizedText.isEmpty {
                    userBubble(conversation.recognizedText)
                }
                if !conversation.replyText.isEmpty {
                    coordinatorBubble(conversation.replyText)
                    replyActions
                }
                if case .awaitingInput(let pending) = conversation.phase {
                    coordinatorBubble(pending.prompt)
                    pendingActions(pending)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
    }

    private func userBubble(_ text: String) -> some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 56)
            Text(text)
                .font(.sttsBody)
                .foregroundStyle(Color.sttsInk)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sttsSurfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: Self.bubbleRadius, style: .continuous))
        }
    }

    private func coordinatorBubble(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text(text)
                .font(.sttsBody)
                .foregroundStyle(Color.sttsInk)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.sttsSurface)
                .clipShape(RoundedRectangle(cornerRadius: Self.bubbleRadius, style: .continuous))
            Spacer(minLength: 56)
        }
    }

    // MARK: Turn actions

    @ViewBuilder
    private var replyActions: some View {
        HStack(spacing: 24) {
            if conversation.canPlayReply {
                Button("Play reply") {
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

    @ViewBuilder
    private func pendingActions(_ pending: PendingInput) -> some View {
        if pending.kind == .approval {
            HStack(spacing: 24) {
                Button("Approve") {
                    conversation.approvePending()
                }
                Button("Deny", role: .destructive) {
                    conversation.denyPending()
                }
                .foregroundStyle(Color.sttsAlert)
            }
            .font(.sttsBody)
        } else {
            HStack(spacing: 12) {
                TextField("Answer", text: $clarificationText, axis: .vertical)
                    .font(.sttsBody)
                    .foregroundStyle(Color.sttsInk)
                    .submitLabel(.send)
                    .onSubmit(answerClarification)
                    .accessibilityLabel("Clarification answer")
                Button("Answer", action: answerClarification)
                    .disabled(clarificationText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(Color.sttsSurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Self.bubbleRadius, style: .continuous))
            .font(.sttsBody)
        }
    }

    private func answerClarification() {
        let text = clarificationText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        conversation.answerPending(text: text)
        clarificationText = ""
    }

    // MARK: Composer

    private var composerZone: some View {
        VStack(spacing: 10) {
            actionStrip
            Group {
                if isRecording {
                    LiveBar(
                        elapsedMs: voice.captureElapsedMs,
                        reduceMotion: reduceMotion,
                        stop: { voice.stop() },
                        discard: { voice.discard() }
                    )
                    .transition(.opacity)
                } else {
                    composerPill
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion ? nil : Animation.easeInOut(duration: 0.25),
                value: isRecording
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var actionStrip: some View {
        HStack(spacing: 24) {
            if conversation.isBusy && conversation.replyText.isEmpty {
                Button("Stop work") {
                    conversation.stopWork()
                }
                .accessibilityLabel("Stop agent work")
            }
            // Reachable whenever a recording is waiting, so cancelling a turn
            // can never strand it with no way to retry or discard.
            if conversation.hasPendingVoiceNote && !conversation.isBusy {
                Button("Retry") {
                    conversation.retryPendingVoiceNote()
                }
                .accessibilityLabel("Retry transcription")
                Button("Discard", role: .destructive) {
                    conversation.discardPendingVoiceNote()
                }
                .foregroundStyle(Color.sttsAlert)
                .accessibilityLabel("Discard recording")
            }
        }
        .font(.sttsCaption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var composerPill: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $draftText, axis: .vertical)
                .font(.sttsBody)
                .foregroundStyle(Color.sttsInk)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(submitDraft)
                .accessibilityLabel("Turn text")
            primaryControl
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(Color.sttsSurfaceRaised)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.sttsOutline, lineWidth: 1))
    }

    @ViewBuilder
    private var primaryControl: some View {
        // The mic is always available; a draft adds Send alongside it rather
        // than replacing it, so typing never removes the ability to record.
        Button {
            voice.start()
        } label: {
            Image(systemName: "mic.fill")
                .font(.sttsBody)
                .foregroundStyle(Color.sttsVoid)
                .frame(width: 44, height: 44)
                .background(Color.sttsInk)
                .clipShape(Circle())
        }
        .accessibilityLabel("Start recording")

        if !draftIsEmpty {
            Button(action: submitDraft) {
                Image(systemName: "arrow.up")
                    .font(.sttsBody)
                    .foregroundStyle(Color.sttsVoid)
                    .frame(width: 44, height: 44)
                    .background(Color.sttsInk)
                    .clipShape(Circle())
            }
            .disabled(conversation.isBusy)
            .accessibilityLabel("Send message")
        }
    }

    private func submitDraft() {
        guard !draftIsEmpty, !conversation.isBusy else { return }
        conversation.submitText(draftText)
        draftText = ""
    }
}

/// Full-width live bar shown while recording: amber indicator, elapsed time in
/// tabular figures, and the stop control.
private struct LiveBar: View {
    let elapsedMs: Int
    let reduceMotion: Bool
    let stop: () -> Void
    let discard: () -> Void

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.sttsLive)
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.4 : 1)
                .opacity(pulse ? 0.5 : 1)
                .animation(
                    reduceMotion
                        ? nil
                        : Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear {
                    guard !reduceMotion else { return }
                    pulse = true
                }
                .accessibilityHidden(true)
            Text(STTSTimeFormat.clockString(ms: elapsedMs))
                .font(.sttsBodyTabular)
                .foregroundStyle(Color.sttsInk)
                .accessibilityLabel("Recording elapsed time")
            Spacer(minLength: 8)
            Button("Discard", role: .destructive, action: discard)
                .font(.sttsCaption)
                .foregroundStyle(Color.sttsAlert)
                .accessibilityLabel("Discard recording")            Button(action: stop) {
                Image(systemName: "stop.fill")
                    .font(.sttsBody)
                    .foregroundStyle(Color.sttsVoid)
                    .frame(width: 44, height: 44)
                    .background(Color.sttsInk)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Stop recording and submit")
        }
        .padding(.leading, 16)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(Color.sttsSurfaceRaised)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.sttsLive, lineWidth: 1))
    }
}
