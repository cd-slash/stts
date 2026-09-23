import Foundation

/// Transcription response from `POST /api/transcriptions`:
/// `{ operationId, text, language?, duration?, adapter }`. Unknown fields
/// (e.g. `adapter`) are ignored. When the request carried a segment claim, the
/// Worker echoes `recordingId` and `segmentIndex` back so a client can confirm
/// which ordered segment a result belongs to.
public struct TranscriptionResult: Codable, Sendable, Equatable {
    public var operationId: String
    public var text: String
    public var language: String?
    public var duration: Double?
    public var recordingId: String?
    public var segmentIndex: Int?

    public init(
        operationId: String,
        text: String,
        language: String? = nil,
        duration: Double? = nil,
        recordingId: String? = nil,
        segmentIndex: Int? = nil
    ) {
        self.operationId = operationId
        self.text = text
        self.language = language
        self.duration = duration
        self.recordingId = recordingId
        self.segmentIndex = segmentIndex
    }
}

/// Ordering claim for one meeting audio segment. The Worker rejects partial
/// claims, so all four fields travel together or not at all.
public struct TranscriptionSegmentClaim: Sendable, Equatable {
    public var recordingId: String
    public var segmentIndex: Int
    public var segmentStartedAtMs: Int
    public var segmentDurationMs: Int

    public init(
        recordingId: String,
        segmentIndex: Int,
        segmentStartedAtMs: Int,
        segmentDurationMs: Int
    ) {
        self.recordingId = recordingId
        self.segmentIndex = segmentIndex
        self.segmentStartedAtMs = segmentStartedAtMs
        self.segmentDurationMs = segmentDurationMs
    }

    /// Multipart form fields; the protocol coerces these string values.
    var formFields: [String: String] {
        [
            "recordingId": recordingId,
            "segmentIndex": String(segmentIndex),
            "segmentStartedAtMs": String(segmentStartedAtMs),
            "segmentDurationMs": String(segmentDurationMs)
        ]
    }
}

/// Conversation handle returned by `POST /api/conversations`.
public struct ConversationHandle: Codable, Sendable, Equatable {
    public var conversationId: String
    public var profile: String?
}

/// Body of a successful turn, answer, or interrupt response:
/// `{ conversationId, events }`. The conversation ID rotates on every
/// operation and must replace the previously stored handle.
public struct TurnResponse: Codable, Sendable, Equatable {
    public var conversationId: String
    public var events: [EventEnvelope]
}
