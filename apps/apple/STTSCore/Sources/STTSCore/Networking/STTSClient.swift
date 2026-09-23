import Foundation

/// Client for the existing Worker routes only:
/// - `GET /api/health`
/// - `POST /api/conversations`
/// - `POST /api/transcriptions` (multipart: `operationId`, `audio`)
/// - `POST /api/conversations/:conversationId/turns`
/// - `POST /api/conversations/:conversationId/inputs/:requestId/answer`
/// - `POST /api/conversations/:conversationId/runs/:runId/interrupt`
/// - `POST /api/speech/synthesis`
public struct STTSClient: Sendable {
    public let baseURL: URL
    private let transport: any HTTPTransport
    private let credentials: any CredentialProviding

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        credentials: any CredentialProviding
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.credentials = credentials
    }

    // MARK: Health

    public struct HealthPayload: Codable, Sendable, Equatable {
        public var status: String
    }

    public func health() async throws {
        var headers = try await credentials.authHeaders()
        headers["accept"] = "application/json"
        let request = HTTPRequest(method: "GET", url: apiURL(["api", "health"]), headers: headers)
        let response = try await transport.send(request)
        guard response.status == 200 else { throw Self.error(from: response) }
        let payload = try decode(HealthPayload.self, from: response)
        guard payload.status == "ok" else {
            throw STTSClientError.invalidResponse("Unhealthy service")
        }
    }

    // MARK: Conversations

    public func createConversation(
        profile: String = "chief-of-staff",
        operationId: String = newOperationId()
    ) async throws -> ConversationHandle {
        let command = CreateConversationCommand(operationId: operationId, profile: profile)
        let response = try await postJSON(command, path: ["api", "conversations"], acceptedStatuses: [201])
        let handle = try decode(ConversationHandle.self, from: response)
        guard !handle.conversationId.isEmpty else {
            throw STTSClientError.invalidResponse("Missing conversationId")
        }
        return handle
    }

    public func submitTurn(
        text: String,
        conversationId: String,
        timezone: String,
        locale: String,
        surface: TurnSurface = .voiceLive,
        profileOverride: String? = nil,
        operationId: String = newOperationId()
    ) async throws -> TurnSubmission {
        let command = SubmitTurnCommand(
            operationId: operationId,
            conversationId: conversationId,
            text: text,
            timezone: timezone,
            locale: locale,
            surface: surface,
            profileOverride: profileOverride
        )
        let response = try await postJSON(
            command,
            path: ["api", "conversations", conversationId, "turns"],
            acceptedStatuses: [202]
        )
        return try turnSubmission(from: response)
    }

    public func answerInput(
        conversationId: String,
        requestId: String,
        answer: AnswerPayload,
        operationId: String = newOperationId()
    ) async throws -> TurnSubmission {
        let command = AnswerInputCommand(
            operationId: operationId,
            conversationId: conversationId,
            requestId: requestId,
            answer: answer
        )
        let response = try await postJSON(
            command,
            path: ["api", "conversations", conversationId, "inputs", requestId, "answer"],
            acceptedStatuses: [202]
        )
        return try turnSubmission(from: response)
    }

    public func interruptRun(
        conversationId: String,
        runId: String,
        reason: InterruptRunCommand.InterruptReason = .userCancelled,
        operationId: String = newOperationId()
    ) async throws -> String {
        let command = InterruptRunCommand(
            operationId: operationId,
            conversationId: conversationId,
            runId: runId,
            reason: reason
        )
        let response = try await postJSON(
            command,
            path: ["api", "conversations", conversationId, "runs", runId, "interrupt"],
            acceptedStatuses: [202]
        )
        let turn = try decode(TurnResponse.self, from: response)
        return turn.conversationId
    }

    // MARK: Speech

    /// Multipart upload to `POST /api/transcriptions`. The Worker maps the
    /// declared MIME type to a canonical filename (e.g. `audio/mp4` → m4a).
    public func transcribe(
        audioData: Data,
        mimeType: String = "audio/mp4",
        fileExtension: String = "m4a",
        language: String? = nil,
        segment: TranscriptionSegmentClaim? = nil,
        operationId: String = newOperationId()
    ) async throws -> TranscriptionResult {
        let boundary = "stts.boundary.\(UUID().uuidString)"
        var fields: [String: String] = ["operationId": operationId]
        if let language {
            fields["language"] = language
        }
        for (key, value) in segment?.formFields ?? [:] {
            fields[key] = value
        }
        let body = MultipartBody.encode(
            boundary: boundary,
            fields: fields,
            fileField: "audio",
            filename: "voice-note.\(fileExtension)",
            mimeType: mimeType,
            fileData: audioData
        )

        var headers = try await credentials.authHeaders()
        headers["content-type"] = "multipart/form-data; boundary=\(boundary)"
        headers["accept"] = "application/json"
        let request = HTTPRequest(
            method: "POST",
            url: apiURL(["api", "transcriptions"]),
            headers: headers,
            body: body
        )
        let response = try await transport.send(request)
        guard response.status == 200 else { throw Self.error(from: response) }
        return try decode(TranscriptionResult.self, from: response)
    }

    /// Posts `POST /api/speech/synthesis` and returns the audio bytes. The
    /// Worker resolves text by `responseId`; clients never send raw text.
    public func synthesize(command: SynthesizeResponseCommand) async throws -> Data {
        let response = try await postJSON(
            command,
            path: ["api", "speech", "synthesis"],
            acceptedStatuses: [200]
        )
        guard response.header("content-type")?.hasPrefix("audio/") == true else {
            throw STTSClientError.invalidResponse("Non-audio synthesis response")
        }
        return response.body
    }

    // MARK: Internals

    private func turnSubmission(from response: HTTPResponse) throws -> TurnSubmission {
        let turn = try decode(TurnResponse.self, from: response)
        return TurnSubmission(conversationId: turn.conversationId, result: try AgentTurnResult(events: turn.events))
    }

    private func postJSON(
        _ payload: some Encodable & Sendable,
        path: [String],
        acceptedStatuses: [Int]
    ) async throws -> HTTPResponse {
        var headers = try await credentials.authHeaders()
        headers["content-type"] = "application/json"
        headers["accept"] = "application/json"
        let body = try JSONEncoder().encode(payload)
        let request = HTTPRequest(method: "POST", url: apiURL(path), headers: headers, body: body)
        let response = try await transport.send(request)
        guard acceptedStatuses.contains(response.status) else {
            throw Self.error(from: response)
        }
        return response
    }

    private func decode<T: Decodable>(_ type: T.Type, from response: HTTPResponse) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: response.body)
        } catch {
            throw STTSClientError.invalidResponse("Undecodable response")
        }
    }

    static func error(from response: HTTPResponse) -> STTSClientError {
        struct ErrorBody: Decodable {
            var code: String
        }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: response.body))?.code
        return .requestFailed(status: response.status, code: code)
    }

    /// RFC 3986 unreserved characters stay unescaped; everything else is
    /// percent-encoded so opaque IDs (base64url handles) travel safely.
    private static let pathSafeCharacters: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private func apiURL(_ components: [String]) -> URL {
        var url = baseURL
        for component in components {
            let encoded = component.addingPercentEncoding(withAllowedCharacters: Self.pathSafeCharacters) ?? component
            url.append(path: encoded)
        }
        return url
    }
}
