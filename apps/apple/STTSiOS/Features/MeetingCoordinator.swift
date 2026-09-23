import AVFoundation
import Foundation
import STTSCore

/// Long-form meeting capture: records AAC segments of bounded length, uploads
/// each closed segment with bounded retries, deletes raw audio after a
/// successful transcription, assembles the transcript, and persists it
/// on device. Raw audio is ephemeral — the segment directory is removed when
/// the meeting finalizes.
@MainActor
final class MeetingCoordinator: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case paused
        case processing
        case saved
    }

    static let segmentTargetMs = 45_000
    static let maxUploadAttempts = 3

    @Published private(set) var state: State = .idle
    @Published private(set) var entries: [TranscriptEntry] = []
    @Published private(set) var markers: [MeetingMarker] = []
    @Published private(set) var elapsedMs = 0
    @Published private(set) var statusMessage: String?

    /// Invoked on the main actor whenever meeting state changes; the app root
    /// forwards this to the watch bridge.
    var onStateChange: (@MainActor () -> Void)?

    /// Assigned by the app root after construction.
    var clientProvider: (() -> STTSClient?)?

    private(set) var startedAt = Date()

    private var segmenter = MeetingSegmenter(targetSegmentDurationMs: MeetingCoordinator.segmentTargetMs)
    private var assembler = TranscriptAssembler()
    private var uploadTasks: [Int: Task<Void, Never>] = [:]
    private var recorder: AVAudioRecorder?
    private var tickTimer: Timer?
    private var startUptime: UInt64?
    private var meetingDirectory: URL?
    private var interruptionMonitor: InterruptionMonitor?
    private var recordingId = newOperationId()
    private let store: any MeetingStore

    init(store: any MeetingStore) {
        self.store = store
    }

    var watchStateName: String {
        switch state {
        case .idle: "idle"
        case .recording: "recording"
        case .paused: "paused"
        case .processing: "processing"
        case .saved: "idle"
        }
    }

    // MARK: Controls

    func start() {
        guard state == .idle else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stts-meeting-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            statusMessage = "Storage unavailable"
            return
        }
        meetingDirectory = directory
        segmenter = MeetingSegmenter(targetSegmentDurationMs: Self.segmentTargetMs)
        assembler = TranscriptAssembler()
        uploadTasks = [:]
        recordingId = newOperationId()
        entries = []
        markers = []
        elapsedMs = 0
        statusMessage = nil
        startedAt = Date()
        startUptime = DispatchTime.now().uptimeNanoseconds
        interruptionMonitor = InterruptionMonitor { [weak self] began in
            if began {
                self?.pause()
            }
        }
        state = .recording
        openSegment()
        if state == .recording {
            startTicking()
        }
        onStateChange?()
    }

    func pause() {
        guard state == .recording else { return }
        closeCurrentSegmentUpload()
        stopTicking()
        state = .paused
        onStateChange?()
    }

    /// Appends a new segment and continues the same meeting after a pause or
    /// an audio-session interruption.
    func resume() {
        guard state == .paused else { return }
        statusMessage = nil
        state = .recording
        openSegment()
        if state == .recording {
            startTicking()
        }
        onStateChange?()
    }

    func addMarker(label: String?) {
        guard state == .recording || state == .paused else { return }
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        markers.append(MeetingMarker(
            atOffsetMs: currentOffsetMs(),
            label: trimmed.isEmpty ? "Marker" : trimmed
        ))
        onStateChange?()
    }

    func stopAndSave() {
        guard state == .recording || state == .paused else { return }
        closeCurrentSegmentUpload()
        stopTicking()
        interruptionMonitor = nil
        state = .processing
        onStateChange?()
        Task { await finalizeMeeting() }
    }

    func reset() {
        guard state == .saved else { return }
        statusMessage = nil
        state = .idle
        onStateChange?()
    }

    // MARK: Recording internals

    private func currentOffsetMs() -> Int {
        guard let startUptime else { return 0 }
        let elapsed = DispatchTime.now().uptimeNanoseconds &- startUptime
        return Int(elapsed / 1_000_000)
    }

    private func openSegment() {
        guard let meetingDirectory else { return }
        let segment = segmenter.beginSegment(atOffsetMs: currentOffsetMs(), directory: meetingDirectory)
        do {
            try AudioSessionConfig.activateRecording()
            let recorder = try RecorderFactory.makeRecorder(url: segment.fileURL)
            guard recorder.record() else {
                throw STTSClientError.transport("Recorder start failed")
            }
            self.recorder = recorder
        } catch {
            recorder = nil
            // The segment was opened before a recorder existed. Close and
            // register it so the gap appears as an explicit failed segment
            // instead of silently missing from the transcript.
            if let stray = segmenter.endCurrentSegment(atOffsetMs: currentOffsetMs()) {
                assembler.register(segment: stray)
                assembler.markFailed(index: stray.index)
                try? FileManager.default.removeItem(at: stray.fileURL)
                entries = assembler.orderedEntries()
            }
            state = .paused
            statusMessage = "Recording unavailable"
            onStateChange?()
        }
    }

    private func closeCurrentSegmentUpload() {
        recorder?.stop()
        recorder = nil
        guard let segment = segmenter.endCurrentSegment(atOffsetMs: currentOffsetMs()) else { return }
        assembler.register(segment: segment)
        entries = assembler.orderedEntries()
        enqueueUpload(for: segment)
    }

    private func startTicking() {
        tickTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard state == .recording else { return }
        elapsedMs = currentOffsetMs()
        let targetSeconds = Double(segmenter.targetSegmentDurationMs) / 1000
        if let recorder, recorder.currentTime >= targetSeconds {
            closeCurrentSegmentUpload()
            if state == .recording {
                openSegment()
            }
        }
    }

    // MARK: Uploads

    private enum UploadOutcome: Sendable {
        case success(segment: SegmentMetadata, result: TranscriptionResult)
        case failure(segment: SegmentMetadata)
    }

    private func enqueueUpload(for segment: SegmentMetadata) {
        guard let provider = clientProvider, let client = provider() else {
            statusMessage = "Transcription unavailable"
            return
        }
        let task = Task { [weak self] in
            let outcome = await Self.upload(
                client: client,
                recordingId: recordingId,
                segment: segment,
                maxAttempts: Self.maxUploadAttempts
            )
            self?.applyUploadOutcome(outcome)
        }
        uploadTasks[segment.index] = task
    }

    /// Nonisolated: file IO and network calls run off the main actor; results
    /// are applied on the main actor.
    private nonisolated static func upload(
        client: STTSClient,
        recordingId: String,
        segment: SegmentMetadata,
        maxAttempts: Int
    ) async -> UploadOutcome {
        let claim = TranscriptionSegmentClaim(
            recordingId: recordingId,
            segmentIndex: segment.index,
            segmentStartedAtMs: segment.startedAtMs,
            segmentDurationMs: segment.durationMs
        )
        var attempt = 1
        while true {
            if Task.isCancelled {
                return .failure(segment: segment)
            }
            do {
                let audio = try Data(contentsOf: segment.fileURL)
                let result = try await client.transcribe(audioData: audio, segment: claim)
                // The Worker echoes the ordering claim. A mismatch means the
                // result does not belong to this segment, so it must not be
                // assembled into the transcript.
                if let echoed = result.segmentIndex, echoed != segment.index {
                    return .failure(segment: segment)
                }
                if let echoedRecording = result.recordingId, echoedRecording != recordingId {
                    return .failure(segment: segment)
                }
                return .success(segment: segment, result: result)
            } catch {
                if attempt >= maxAttempts {
                    return .failure(segment: segment)
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000)
                attempt += 1
            }
        }
    }

    private func applyUploadOutcome(_ outcome: UploadOutcome) {
        let index: Int
        switch outcome {
        case .success(let segment, let result):
            assembler.apply(result: result, for: segment)
            // Raw audio is ephemeral: delete only after successful transcription.
            try? FileManager.default.removeItem(at: segment.fileURL)
            index = segment.index
        case .failure(let segment):
            assembler.markFailed(index: segment.index)
            statusMessage = "Transcription failed"
            index = segment.index
        }
        uploadTasks[index] = nil
        entries = assembler.orderedEntries()
    }

    private func finalizeMeeting() async {
        // Snapshot: applying an outcome removes entries from `uploadTasks`.
        for task in Array(uploadTasks.values) {
            await task.value
        }
        uploadTasks.removeAll()
        assembler.markAllPendingFailed()
        entries = assembler.orderedEntries()

        let duration = max(elapsedMs, segmenter.totalRecordedMs)
        let meeting = MeetingTranscript(
            title: Self.defaultTitle(startedAt: startedAt),
            startedAt: startedAt,
            endedAt: Date(),
            durationMs: duration,
            segments: entries,
            assembledText: assembler.assembledText(),
            markers: markers
        )
        do {
            try await store.save(meeting)
        } catch {
            statusMessage = "Save failed"
        }

        // Meeting audio never persists: drop the whole segment directory.
        if let meetingDirectory {
            try? FileManager.default.removeItem(at: meetingDirectory)
        }
        meetingDirectory = nil
        startUptime = nil
        state = .saved
        onStateChange?()
    }

    private static func defaultTitle(startedAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "Meeting " + formatter.string(from: startedAt)
    }
}
