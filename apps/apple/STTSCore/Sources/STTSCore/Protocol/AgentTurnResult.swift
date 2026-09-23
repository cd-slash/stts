import Foundation

/// Reduced result of a turn or answer, mirroring the web client's
/// `AgentResult`:
/// - last `response.completed` with string `text` → `.completed`
/// - else last `input.requested` with a valid shape → `.inputRequested`
/// - else `run.interrupted` present → `.interrupted`
/// - otherwise throws `.invalidResponse`
public enum AgentTurnResult: Sendable, Equatable {
    case completed(text: String, responseId: String?)
    case inputRequested(PendingInput)
    case interrupted

    public init(events: [EventEnvelope]) throws {
        if let completed = events.last(where: { $0.type == .responseCompleted }),
           let data = completed.responseCompletedData,
           let text = data.text {
            self = .completed(text: text, responseId: data.responseId)
            return
        }

        if let requested = events.last(where: { $0.type == .inputRequested }),
           let data = requested.inputRequestedData,
           let requestId = data.requestId,
           let rawKind = data.kind,
           let kind = PendingInputKind(rawValue: rawKind) {
            self = .inputRequested(PendingInput(
                requestId: requestId,
                kind: kind,
                prompt: data.prompt ?? "",
                choices: data.choices ?? [],
                confirmationNonce: data.confirmationNonce
            ))
            return
        }

        if events.contains(where: { $0.type == .runInterrupted }) {
            self = .interrupted
            return
        }

        throw STTSClientError.invalidResponse("Missing response")
    }
}

/// A pending clarification or approval request awaiting an answer.
public struct PendingInput: Codable, Sendable, Equatable {
    public var requestId: String
    public var kind: PendingInputKind
    public var prompt: String
    public var choices: [JSONValue]
    public var confirmationNonce: String?

    public init(
        requestId: String,
        kind: PendingInputKind,
        prompt: String,
        choices: [JSONValue],
        confirmationNonce: String? = nil
    ) {
        self.requestId = requestId
        self.kind = kind
        self.prompt = prompt
        self.choices = choices
        self.confirmationNonce = confirmationNonce
    }
}

/// Conversation ID as rotated by an operation, paired with its reduced result.
public struct TurnSubmission: Sendable, Equatable {
    public var conversationId: String
    public var result: AgentTurnResult

    public init(conversationId: String, result: AgentTurnResult) {
        self.conversationId = conversationId
        self.result = result
    }
}
