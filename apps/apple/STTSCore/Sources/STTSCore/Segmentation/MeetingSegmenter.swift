import Foundation

/// Plans bounded windows for a discrete voice note: one window up to the
/// target duration, split into consecutive windows when longer.
public struct VoiceNoteSegmenter: Sendable, Equatable {
    public let targetSegmentDurationMs: Int

    public init(targetSegmentDurationMs: Int = 45_000) {
        self.targetSegmentDurationMs = max(1, targetSegmentDurationMs)
    }

    public func planWindows(totalDurationMs: Int) -> [SegmentWindow] {
        guard totalDurationMs > 0 else { return [] }
        var windows: [SegmentWindow] = []
        var start = 0
        var index = 0
        while start < totalDurationMs {
            let duration = min(targetSegmentDurationMs, totalDurationMs - start)
            windows.append(SegmentWindow(index: index, startedAtMs: start, durationMs: duration))
            start += duration
            index += 1
        }
        return windows
    }
}

/// Stateful segment planner for live meeting capture. The recorder asks for
/// the next segment's file URL, closes the current segment at (or after) the
/// target duration, and receives closed-segment metadata for upload.
///
/// Offsets are supplied by the caller (e.g. from a monotonic clock) so the
/// segmenter stays deterministic and testable without AVFoundation.
public struct MeetingSegmenter: Sendable, Equatable {
    public let targetSegmentDurationMs: Int
    public private(set) var completedSegments: [SegmentMetadata] = []
    public private(set) var currentSegment: SegmentMetadata?

    public init(targetSegmentDurationMs: Int = 45_000) {
        self.targetSegmentDurationMs = max(1, targetSegmentDurationMs)
    }

    /// Opens a new segment at `offsetMs`. Any open segment is closed first
    /// (defensively) so indexes stay sequential.
    @discardableResult
    public mutating func beginSegment(atOffsetMs offsetMs: Int, directory: URL) -> SegmentMetadata {
        if currentSegment != nil {
            _ = endCurrentSegment(atOffsetMs: offsetMs)
        }
        let index = (completedSegments.last?.index ?? -1) + 1
        let fileURL = directory.appendingPathComponent(
            "segment-\(String(format: "%04d", index)).m4a",
            isDirectory: false
        )
        let segment = SegmentMetadata(index: index, startedAtMs: offsetMs, durationMs: 0, fileURL: fileURL)
        currentSegment = segment
        return segment
    }

    /// Closes the open segment at `offsetMs` and returns its metadata.
    @discardableResult
    public mutating func endCurrentSegment(atOffsetMs offsetMs: Int) -> SegmentMetadata? {
        guard var segment = currentSegment else { return nil }
        currentSegment = nil
        segment.durationMs = max(0, offsetMs - segment.startedAtMs)
        completedSegments.append(segment)
        return segment
    }

    public func shouldCloseCurrentSegment(atOffsetMs offsetMs: Int) -> Bool {
        guard let current = currentSegment else { return false }
        return (offsetMs - current.startedAtMs) >= targetSegmentDurationMs
    }

    public var totalRecordedMs: Int {
        completedSegments.reduce(0) { $0 + $1.durationMs }
    }
}
