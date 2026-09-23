import Foundation

/// Commands mirroring `packages/protocol/src/index.ts` exactly.
/// Field names are camelCase as on the wire; no key mapping is applied.

public struct CreateConversationCommand: Codable, Sendable, Equatable {
    public var operationId: String
    public var profile: String

    public init(operationId: String = newOperationId(), profile: String = "chief-of-staff") {
        self.operationId = operationId
        self.profile = profile
    }
}

/// The `input` object of `submitTurnCommand`: `kind` is the literal "text".
public struct TextTurnInput: Codable, Sendable, Equatable {
    public var kind: String
    public var text: String

    public init(text: String) {
        self.kind = "text"
        self.text = text
    }
}

/// What kind of input produced a turn. Mirrors the protocol's bounded
/// `surface` enum; it is never free-form.
public enum TurnSurface: String, Codable, Sendable, Equatable, CaseIterable {
    case voiceLive = "voice-live"
    case text = "text"
    case meetingTranscript = "meeting-transcript"
}

public struct ClientContext: Codable, Sendable, Equatable {
    /// Note the protocol spells this key `timezone` (all lowercase).
    public var timezone: String
    public var locale: String

    public init(timezone: String, locale: String) {
        self.timezone = timezone
        self.locale = locale
    }
}

public struct SubmitTurnCommand: Codable, Sendable, Equatable {
    public var operationId: String
    public var conversationId: String
    public var input: TextTurnInput
    public var profileOverride: String?
    public var surface: TurnSurface
    public var clientContext: ClientContext

    public init(
        operationId: String = newOperationId(),
        conversationId: String,
        text: String,
        timezone: String,
        locale: String,
        surface: TurnSurface = .voiceLive,
        profileOverride: String? = nil
    ) {
        self.operationId = operationId
        self.conversationId = conversationId
        self.input = TextTurnInput(text: text)
        self.profileOverride = profileOverride
        self.surface = surface
        self.clientContext = ClientContext(timezone: timezone, locale: locale)
    }

    private enum CodingKeys: String, CodingKey {
        case operationId
        case conversationId
        case input
        case profileOverride
        case surface
        case clientContext
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        operationId = try container.decode(String.self, forKey: .operationId)
        conversationId = try container.decode(String.self, forKey: .conversationId)
        input = try container.decode(TextTurnInput.self, forKey: .input)
        profileOverride = try container.decodeIfPresent(String.self, forKey: .profileOverride)
        surface = try container.decodeIfPresent(TurnSurface.self, forKey: .surface) ?? .voiceLive
        clientContext = try container.decode(ClientContext.self, forKey: .clientContext)
    }

    /// `profileOverride` is always present on the wire, as explicit JSON null
    /// when unset — mirroring the web client's payload.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(conversationId, forKey: .conversationId)
        try container.encode(input, forKey: .input)
        if let profileOverride {
            try container.encode(profileOverride, forKey: .profileOverride)
        } else {
            try container.encodeNil(forKey: .profileOverride)
        }
        try container.encode(surface, forKey: .surface)
        try container.encode(clientContext, forKey: .clientContext)
    }
}

/// Kind of a pending `input.requested` event: approval or clarification.
public enum PendingInputKind: String, Codable, Sendable, Equatable {
    case approval
    case clarification
}

/// Kind of an answer submitted through `answerInputCommand`.
public enum AnswerKind: String, Codable, Sendable, Equatable {
    case text
    case approve
    case deny
}

public struct AnswerPayload: Codable, Sendable, Equatable {
    public var kind: AnswerKind
    public var text: String?
    public var confirmationNonce: String?

    public init(kind: AnswerKind, text: String? = nil, confirmationNonce: String? = nil) {
        self.kind = kind
        self.text = text
        self.confirmationNonce = confirmationNonce
    }

    public static func text(_ value: String) -> AnswerPayload {
        AnswerPayload(kind: .text, text: value)
    }

    public static func approve(nonce: String?) -> AnswerPayload {
        AnswerPayload(kind: .approve, confirmationNonce: nonce)
    }

    public static func deny() -> AnswerPayload {
        AnswerPayload(kind: .deny)
    }
}

public struct AnswerInputCommand: Codable, Sendable, Equatable {
    public var operationId: String
    public var conversationId: String
    public var requestId: String
    public var answer: AnswerPayload

    public init(
        operationId: String = newOperationId(),
        conversationId: String,
        requestId: String,
        answer: AnswerPayload
    ) {
        self.operationId = operationId
        self.conversationId = conversationId
        self.requestId = requestId
        self.answer = answer
    }
}

public struct InterruptRunCommand: Codable, Sendable, Equatable {
    public enum InterruptReason: String, Codable, Sendable, Equatable {
        case userCancelled = "user_cancelled"
        case userRedirect = "user_redirect"
    }

    public var operationId: String
    public var conversationId: String
    public var runId: String
    public var reason: InterruptReason

    public init(
        operationId: String = newOperationId(),
        conversationId: String,
        runId: String,
        reason: InterruptReason
    ) {
        self.operationId = operationId
        self.conversationId = conversationId
        self.runId = runId
        self.reason = reason
    }
}

public enum SynthesisFormat: String, Codable, Sendable, Equatable {
    case mpeg = "audio/mpeg"
    case wav = "audio/wav"
    case ogg = "audio/ogg"
}

public struct SynthesizeResponseCommand: Codable, Sendable, Equatable {
    public var operationId: String
    public var conversationId: String
    public var responseId: String
    public var voice: String
    public var format: SynthesisFormat

    public init(
        operationId: String = newOperationId(),
        conversationId: String,
        responseId: String,
        voice: String = "default",
        format: SynthesisFormat = .mpeg
    ) {
        self.operationId = operationId
        self.conversationId = conversationId
        self.responseId = responseId
        self.voice = voice
        self.format = format
    }
}
