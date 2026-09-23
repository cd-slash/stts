import Foundation
import STTSCore

/// Owns the single voice conversation: voice-note round trips, typed turns,
/// approvals/clarifications, interruption, synthesis, and reply playback.
@MainActor
final class ConversationController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case transcribing
        case submitting
        case awaitingInput(PendingInput)
        case failed(String)
    }

    /// Meeting summaries are chunked rather than truncated. Each part stays
    /// under the protocol's interactive turn ceiling, and the chunk count is
    /// bounded so an extreme transcript cannot trigger unbounded agent work.
    static let chunker = TranscriptChunker(maximumCharacters: 18_000)
    static let maximumSummaryChunks = 12
    /// Ceiling for the final combine turn, kept under the protocol's
    /// `meeting-transcript` allowance.
    static let combineCeiling = 90_000

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var recognizedText = ""
    @Published private(set) var replyText = ""
    /// True when a summary had to drop trailing parts at `maximumSummaryChunks`.
    @Published private(set) var summaryTruncated = false

    /// Invoked on the main actor with (replyText, audioData) after successful
    /// synthesis; used to relay replies to the watch.
    var onReplyAudio: (@MainActor (String, Data) -> Void)?

    /// Assigned by the app root after construction; returns the configured
    /// client or nil when server/credentials are missing.
    var clientProvider: (() -> STTSClient?)?

    private(set) var conversationId: String?
    private(set) var activeRunId: String?
    private var lastResponseId: String?
    private var pendingVoiceNoteURL: URL?
    private var runTask: Task<Void, Never>?
    private let playback: AudioPlaybackService

    init(playback: AudioPlaybackService) {
        self.playback = playback
    }

    // MARK: Derived state

    var isBusy: Bool {
        switch phase {
        case .transcribing, .submitting: true
        default: false
        }
    }

    var canPlayReply: Bool {
        lastResponseId != nil && conversationId != nil
    }

    var hasPendingVoiceNote: Bool {
        pendingVoiceNoteURL != nil
    }

    // MARK: Voice note

    /// Transcribes the recording, deletes the raw file on success, and
    /// submits the text as one turn. On transcription failure the file is
    /// retained for retry or discard.
    func submitVoiceNote(at url: URL) {
        // Keep the file reachable even when a turn is already running, so a
        // watch handover is never silently dropped; the retry control picks it
        // up once the current turn finishes.
        pendingVoiceNoteURL = url
        summaryTruncated = false
        guard !isBusy else {
            phase = .failed("Busy")
            return
        }
        runTask?.cancel()
        runTask = Task { await transcribeAndSubmit() }
    }

    func retryPendingVoiceNote() {
        guard let url = pendingVoiceNoteURL, !isBusy else { return }
        submitVoiceNote(at: url)
    }

    func discardPendingVoiceNote() {
        if let url = pendingVoiceNoteURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingVoiceNoteURL = nil
    }

    private func transcribeAndSubmit() async {
        guard let url = pendingVoiceNoteURL else { return }
        guard let client = clientProvider?() else {
            phase = .failed("Not configured")
            discardPendingVoiceNote()
            return
        }
        phase = .transcribing
        do {
            let audio = try Data(contentsOf: url)
            let transcription = try await client.transcribe(audioData: audio)
            try? FileManager.default.removeItem(at: url)
            pendingVoiceNoteURL = nil
            recognizedText = transcription.text
            try await runTurn(text: transcription.text, client: client, surface: .voiceLive)
        } catch {
            guard !Task.isCancelled else {
                phase = .idle
                return
            }
            phase = .failed(Self.shortMessage(error))
        }
    }

    // MARK: Turns

    func submitText(_ raw: String) {
        guard !isBusy else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed("Text required")
            return
        }
        startTurn(text: text, surface: .text)
    }

    /// Summarizes the assembled meeting transcript. Short transcripts go as one
    /// turn; longer ones are summarized part by part and the notes combined, so
    /// no text is discarded.
    func summarize(meeting: MeetingTranscript) {
        guard !isBusy else { return }
        let text = meeting.assembledText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            phase = .failed("Transcript empty")
            return
        }

        var chunks = Self.chunker.chunks(of: text)
        var truncated = false
        if chunks.count > Self.maximumSummaryChunks {
            chunks = Array(chunks.prefix(Self.maximumSummaryChunks))
            truncated = true
        }
        self.summaryTruncated = truncated
        startSummary(chunks: chunks)
    }

    private func startSummary(chunks: [String]) {
        runTask?.cancel()
        runTask = Task {
            guard let client = clientProvider?() else {
                phase = .failed("Not configured")
                return
            }
            do {
                try await runSummary(chunks: chunks, client: client)
            } catch {
                guard !Task.isCancelled else {
                    phase = .idle
                    return
                }
                phase = .failed(Self.shortMessage(error))
            }
        }
    }

    /// Map then reduce: one partial-summary turn per chunk, then one turn that
    /// combines the notes.
    private func runSummary(chunks: [String], client: STTSClient) async throws {
        phase = .submitting
        if chunks.count == 1 {
            let submission = try await submissionWithRetry(
                text: chunks[0],
                surface: .meetingTranscript,
                client: client
            )
            conversationId = submission.conversationId
            apply(submission.result)
            return
        }

        var notes: [String] = []
        for (offset, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            phase = .submitting
            let prompt = """
                Summarize part \(offset + 1) of \(chunks.count) of a meeting \
                transcript into concise notes. Preserve decisions, action items, \
                owners, and figures. Output notes only.

                \(chunk)
                """
            let submission = try await submissionWithRetry(
                text: prompt,
                surface: .meetingTranscript,
                client: client
            )
            conversationId = submission.conversationId
            guard case .completed(let note, _) = submission.result else {
                // A mid-summary input request cannot be answered automatically;
                // surface it rather than silently dropping the rest.
                apply(submission.result)
                return
            }
            notes.append(note)
        }

        try Task.checkCancellation()
        phase = .submitting
        let notesText = notes.joined(separator: "\n\n")
        if notesText.count > Self.combineCeiling {
            // Notes are abnormally large. Present them directly rather than
            // submitting a turn the Worker would reject, discarding the work.
            replyText = notesText
            phase = .idle
            return
        }
        let combine = """
            Combine these notes from one meeting into a single summary.

            \(notesText)
            """
        let submission = try await submissionWithRetry(
            text: combine,
            surface: .meetingTranscript,
            client: client
        )
        conversationId = submission.conversationId
        apply(submission.result)
    }

    private func submissionWithRetry(
        text: String,
        surface: TurnSurface,
        client: STTSClient
    ) async throws -> TurnSubmission {
        let operationId = newOperationId()
        activeRunId = operationId
        defer { activeRunId = nil }
        do {
            return try await performTurn(
                text: text,
                surface: surface,
                operationId: operationId,
                client: client
            )
        } catch let error as STTSClientError where error.isStaleConversation {
            // Conversation handle rejected: recreate and retry once with the
            // same operation ID, mirroring the web client.
            conversationId = nil
            return try await performTurn(
                text: text,
                surface: surface,
                operationId: operationId,
                client: client
            )
        }
    }

    private func startTurn(text: String, surface: TurnSurface) {
        summaryTruncated = false
        runTask?.cancel()
        runTask = Task {
            guard let client = clientProvider?() else {
                phase = .failed("Not configured")
                return
            }
            do {
                try await runTurn(text: text, client: client, surface: surface)
            } catch {
                guard !Task.isCancelled else {
                    phase = .idle
                    return
                }
                phase = .failed(Self.shortMessage(error))
            }
        }
    }

    private func runTurn(text: String, client: STTSClient, surface: TurnSurface) async throws {
        phase = .submitting
        let submission = try await submissionWithRetry(
            text: text,
            surface: surface,
            client: client
        )
        conversationId = submission.conversationId
        apply(submission.result)
    }

    private func performTurn(
        text: String,
        surface: TurnSurface,
        operationId: String,
        client: STTSClient
    ) async throws -> TurnSubmission {
        let conversationId = try await ensureConversation(client: client)
        return try await client.submitTurn(
            text: text,
            conversationId: conversationId,
            timezone: TimeZone.current.identifier,
            locale: Locale.current.identifier,
            surface: surface,
            operationId: operationId
        )
    }

    private func ensureConversation(client: STTSClient) async throws -> String {
        if let conversationId { return conversationId }
        let handle = try await client.createConversation()
        conversationId = handle.conversationId
        return handle.conversationId
    }

    private func apply(_ result: AgentTurnResult) {
        switch result {
        case .completed(let text, let responseId):
            replyText = text
            lastResponseId = responseId
            phase = .idle
            if responseId != nil {
                Task { await playReply() }
            }
        case .inputRequested(let pending):
            phase = .awaitingInput(pending)
        case .interrupted:
            phase = .idle
        }
    }

    // MARK: Answers

    func answerPending(text: String) {
        guard case .awaitingInput(let pending) = phase else { return }
        submitAnswer(.text(text), pending: pending)
    }

    func approvePending() {
        guard case .awaitingInput(let pending) = phase else { return }
        submitAnswer(.approve(nonce: pending.confirmationNonce), pending: pending)
    }

    func denyPending() {
        guard case .awaitingInput(let pending) = phase else { return }
        submitAnswer(.deny(), pending: pending)
    }

    private func submitAnswer(_ answer: AnswerPayload, pending: PendingInput) {
        guard let client = clientProvider?(), let conversationId else { return }
        phase = .submitting
        runTask?.cancel()
        runTask = Task {
            do {
                let submission = try await client.answerInput(
                    conversationId: conversationId,
                    requestId: pending.requestId,
                    answer: answer
                )
                self.conversationId = submission.conversationId
                apply(submission.result)
            } catch {
                guard !Task.isCancelled else {
                    phase = .idle
                    return
                }
                phase = .failed(Self.shortMessage(error))
            }
        }
    }

    // MARK: Interruption and playback

    /// Cancels the in-flight task, stops playback, and interrupts the active
    /// agent run with reason `user_cancelled`.
    func stopWork() {
        runTask?.cancel()
        playback.stop()
        guard let client = clientProvider?(), let conversationId, let runId = activeRunId else {
            phase = .idle
            return
        }
        activeRunId = nil
        phase = .idle
        Task {
            // The interrupt response rotates the handle; retaining it keeps the
            // stored conversation current, as the web client does.
            if let rotated = try? await client.interruptRun(
                conversationId: conversationId,
                runId: runId,
                reason: .userCancelled
            ) {
                self.conversationId = rotated
            }
        }
    }

    func stopPlayback() {
        playback.stop()
    }

    func playReply() async {
        guard let client = clientProvider?(), let conversationId, let responseId = lastResponseId else {
            return
        }
        do {
            let command = SynthesizeResponseCommand(
                conversationId: conversationId,
                responseId: responseId
            )
            let audio = try await client.synthesize(command: command)
            onReplyAudio?(replyText, audio)
            try playback.play(mp3Data: audio)
        } catch {
            phase = .failed(Self.shortMessage(error))
        }
    }

    // MARK: Errors

    static func shortMessage(_ error: Error) -> String {
        switch error as? STTSClientError {
        case .credentialUnavailable: "Credentials missing"
        case .invalidResponse: "Invalid response"
        case .transport: "Connection failed"
        case .requestFailed(_, let code):
            if let code {
                "Request failed (\(code))"
            } else {
                "Request failed"
            }
        case nil: "Request failed"
        }
    }
}
