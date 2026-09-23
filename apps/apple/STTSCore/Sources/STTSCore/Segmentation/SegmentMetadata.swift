import Foundation

/// Metadata for one recorded audio segment. `startedAtMs` and `durationMs`
/// are offsets from the start of the recording; `fileURL` points at the
/// ephemeral audio file.
public struct SegmentMetadata: Codable, Sendable, Equatable {
    public var index: Int
    public var startedAtMs: Int
    public var durationMs: Int
    public var fileURL: URL

    public init(index: Int, startedAtMs: Int, durationMs: Int, fileURL: URL) {
        self.index = index
        self.startedAtMs = startedAtMs
        self.durationMs = durationMs
        self.fileURL = fileURL
    }
}

/// A planned time window within a bounded voice note.
public struct SegmentWindow: Codable, Sendable, Equatable {
    public var index: Int
    public var startedAtMs: Int
    public var durationMs: Int

    public init(index: Int, startedAtMs: Int, durationMs: Int) {
        self.index = index
        self.startedAtMs = startedAtMs
        self.durationMs = durationMs
    }
}
