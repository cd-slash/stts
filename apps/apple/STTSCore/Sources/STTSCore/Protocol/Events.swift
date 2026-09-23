import Foundation

/// Event types from the protocol's `eventType` enum. Unknown event types are
/// preserved as `.unknown(raw)` so additive protocol changes do not break
/// decoding (non-critical unknown events may be ignored).
public enum EventType: Sendable, Equatable, Hashable {
    case conversationSnapshot
    case connectionResumed
    case turnTranscribed
    case turnAccepted
    case turnRejected
    case responseStarted
    case responseDelta
    case responseCompleted
    case responseFailed
    case activityStarted
    case activityUpdated
    case activityCompleted
    case activityFailed
    case inputRequested
    case inputResolved
    case inputExpired
    case runInterrupting
    case runInterrupted
    case runInterruptFailed
    case speechSynthesisStarted
    case speechSynthesisReady
    case speechSynthesisFailed
    case errorOccurred
    case unknown(String)

    public var rawValue: String {
        switch self {
        case .conversationSnapshot: "conversation.snapshot"
        case .connectionResumed: "connection.resumed"
        case .turnTranscribed: "turn.transcribed"
        case .turnAccepted: "turn.accepted"
        case .turnRejected: "turn.rejected"
        case .responseStarted: "response.started"
        case .responseDelta: "response.delta"
        case .responseCompleted: "response.completed"
        case .responseFailed: "response.failed"
        case .activityStarted: "activity.started"
        case .activityUpdated: "activity.updated"
        case .activityCompleted: "activity.completed"
        case .activityFailed: "activity.failed"
        case .inputRequested: "input.requested"
        case .inputResolved: "input.resolved"
        case .inputExpired: "input.expired"
        case .runInterrupting: "run.interrupting"
        case .runInterrupted: "run.interrupted"
        case .runInterruptFailed: "run.interrupt_failed"
        case .speechSynthesisStarted: "speech.synthesis.started"
        case .speechSynthesisReady: "speech.synthesis.ready"
        case .speechSynthesisFailed: "speech.synthesis.failed"
        case .errorOccurred: "error.occurred"
        case .unknown(let value): value
        }
    }

    public init(known rawValue: String) {
        switch rawValue {
        case "conversation.snapshot": self = .conversationSnapshot
        case "connection.resumed": self = .connectionResumed
        case "turn.transcribed": self = .turnTranscribed
        case "turn.accepted": self = .turnAccepted
        case "turn.rejected": self = .turnRejected
        case "response.started": self = .responseStarted
        case "response.delta": self = .responseDelta
        case "response.completed": self = .responseCompleted
        case "response.failed": self = .responseFailed
        case "activity.started": self = .activityStarted
        case "activity.updated": self = .activityUpdated
        case "activity.completed": self = .activityCompleted
        case "activity.failed": self = .activityFailed
        case "input.requested": self = .inputRequested
        case "input.resolved": self = .inputResolved
        case "input.expired": self = .inputExpired
        case "run.interrupting": self = .runInterrupting
        case "run.interrupted": self = .runInterrupted
        case "run.interrupt_failed": self = .runInterruptFailed
        case "speech.synthesis.started": self = .speechSynthesisStarted
        case "speech.synthesis.ready": self = .speechSynthesisReady
        case "speech.synthesis.failed": self = .speechSynthesisFailed
        case "error.occurred": self = .errorOccurred
        default: self = .unknown(rawValue)
        }
    }
}

extension EventType: Codable {
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = EventType(known: value)
    }

    public func encode(to encoder: Encoder) throws {
        try encoder.singleValueContainer().encode(rawValue)
    }
}

/// Normalized event envelope from the shared protocol.
public struct EventEnvelope: Codable, Sendable, Equatable {
    public var version: String
    public var eventId: String
    public var conversationId: String
    public var cursor: String
    /// RFC 3339 timestamp string, kept as delivered.
    public var occurredAt: String
    public var correlationId: String
    public var type: EventType
    public var critical: Bool
    public var data: JSONValue

    public init(
        version: String,
        eventId: String,
        conversationId: String,
        cursor: String,
        occurredAt: String,
        correlationId: String,
        type: EventType,
        critical: Bool,
        data: JSONValue
    ) {
        self.version = version
        self.eventId = eventId
        self.conversationId = conversationId
        self.cursor = cursor
        self.occurredAt = occurredAt
        self.correlationId = correlationId
        self.type = type
        self.critical = critical
        self.data = data
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case eventId
        case conversationId
        case cursor
        case occurredAt
        case correlationId
        case type
        case critical
        case data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        eventId = try container.decode(String.self, forKey: .eventId)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        cursor = try container.decode(String.self, forKey: .cursor)
        occurredAt = try container.decode(String.self, forKey: .occurredAt)
        correlationId = try container.decode(String.self, forKey: .correlationId)
        type = try container.decode(EventType.self, forKey: .type)
        critical = try container.decode(Bool.self, forKey: .critical)
        data = (try? container.decode(JSONValue.self, forKey: .data)) ?? .object([:])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(cursor, forKey: .cursor)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(correlationId, forKey: .correlationId)
        try container.encode(type, forKey: .type)
        try container.encode(critical, forKey: .critical)
        try container.encode(data, forKey: .data)
    }

    /// Decodes the envelope's `data` into a typed payload, tolerating missing
    /// or unexpected shapes by returning nil.
    public func typedData<T: Decodable>(_ type: T.Type) -> T? {
        guard case .object = data else { return nil }
        guard let encoded = try? JSONEncoder().encode(data) else { return nil }
        return try? JSONDecoder().decode(type, from: encoded)
    }

    public var responseCompletedData: ResponseCompletedData? {
        typedData(ResponseCompletedData.self)
    }

    public var inputRequestedData: InputRequestedData? {
        typedData(InputRequestedData.self)
    }
}

/// Payload of `response.completed`: final text plus the response ID needed
/// for later synthesis. Unknown extra fields are ignored.
public struct ResponseCompletedData: Codable, Sendable, Equatable {
    public var text: String?
    public var responseId: String?
}

/// Payload of `input.requested`: clarification or approval request.
public struct InputRequestedData: Codable, Sendable, Equatable {
    public var requestId: String?
    public var kind: String?
    public var prompt: String?
    public var choices: [JSONValue]?
    public var confirmationNonce: String?
}
