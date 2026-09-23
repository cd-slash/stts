import Foundation

public enum SegmentStatus: String, Codable, Sendable, Equatable {
    case pending
    case transcribed
    case failed
}

/// One positioned entry of an assembled transcript.
public struct TranscriptEntry: Codable, Sendable, Equatable {
    public var index: Int
    public var startedAtMs: Int
    public var durationMs: Int
    public var status: SegmentStatus
    public var text: String
    public var language: String?

    public init(
        index: Int,
        startedAtMs: Int,
        durationMs: Int,
        status: SegmentStatus,
        text: String,
        language: String? = nil
    ) {
        self.index = index
        self.startedAtMs = startedAtMs
        self.durationMs = durationMs
        self.status = status
        self.text = text
        self.language = language
    }
}

/// Merges per-segment transcription results into an ordered transcript.
///
/// - Out-of-order completion: entries are keyed by segment index in a
///   dictionary and sorted by `startedAtMs` (then index) on read.
/// - Duplicate delivery: applying a segment again replaces its entry; the
///   latest result wins.
/// - Retries: a retried segment overwrites the previous text for its index.
/// - Gaps: pending and failed segments are excluded from the assembled text
///   and reported separately.
///
/// Value type: the owner (a view model or coordinator) holds and mutates it
/// from a single concurrency domain.
public struct TranscriptAssembler: Sendable, Equatable {
    private var entries: [Int: TranscriptEntry] = [:]
    public private(set) var registeredCount = 0

    public init() {}

    /// Registers a recorded segment as pending so gaps are visible even when
    /// its transcription never arrives.
    public mutating func register(segment: SegmentMetadata) {
        guard entries[segment.index] == nil else { return }
        entries[segment.index] = TranscriptEntry(
            index: segment.index,
            startedAtMs: segment.startedAtMs,
            durationMs: segment.durationMs,
            status: .pending,
            text: "",
            language: nil
        )
        registeredCount += 1
    }

    /// Applies (or re-applies) a transcription result for a segment.
    public mutating func apply(result: TranscriptionResult, for segment: SegmentMetadata) {
        entries[segment.index] = TranscriptEntry(
            index: segment.index,
            startedAtMs: segment.startedAtMs,
            durationMs: segment.durationMs,
            status: .transcribed,
            text: result.text,
            language: result.language
        )
    }

    public mutating func markFailed(index: Int) {
        guard var entry = entries[index] else { return }
        entry.status = .failed
        entries[index] = entry
    }

    public mutating func markAllPendingFailed() {
        let pendingIndices = entries.filter { $0.value.status == .pending }.map(\.key)
        for index in pendingIndices {
            markFailed(index: index)
        }
    }

    /// Entries sorted by `startedAtMs` then index — monotonic regardless of
    /// arrival order.
    public func orderedEntries() -> [TranscriptEntry] {
        entries.values.sorted { lhs, rhs in
            if lhs.startedAtMs != rhs.startedAtMs {
                return lhs.startedAtMs < rhs.startedAtMs
            }
            return lhs.index < rhs.index
        }
    }

    /// Successful, non-empty segment texts joined in order. Pending and
    /// failed segments are skipped.
    public func assembledText(separator: String = "\n") -> String {
        orderedEntries()
            .compactMap { entry -> String? in
                guard entry.status == .transcribed else { return nil }
                let trimmed = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: separator)
    }

    public var hasPending: Bool {
        entries.values.contains { $0.status == .pending }
    }

    public var failedIndices: [Int] {
        entries.values.filter { $0.status == .failed }.map(\.index).sorted()
    }

    public var transcribedCount: Int {
        entries.values.filter { $0.status == .transcribed }.count
    }
}
