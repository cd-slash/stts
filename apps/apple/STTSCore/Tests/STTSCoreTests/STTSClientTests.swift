import XCTest
@testable import STTSCore

final class STTSClientTests: XCTestCase {
    /// Wraps `@unchecked Sendable` because the handler assigns once per request
    /// on the transport executor; the test reads it only after the awaited
    /// client call has returned.
    private final class RequestBox: @unchecked Sendable {
        private(set) var request: HTTPRequest?

        func store(_ request: HTTPRequest) {
            self.request = request
        }
    }

    private struct StubCredentials: CredentialProviding {
        let credential: Credential?

        func currentCredential() async throws -> Credential? {
            credential
        }
    }

    private final class HandlerTransport: HTTPTransport, @unchecked Sendable {
        // @unchecked Sendable: the handler closure is fixed during test
        // arrangement and only read by send(_:).
        private let handler: @Sendable (HTTPRequest) throws -> HTTPResponse

        init(handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse) {
            self.handler = handler
        }

        func send(_ request: HTTPRequest) async throws -> HTTPResponse {
            try handler(request)
        }
    }

    private func makeClient(
        credentials: CredentialProviding = StubCredentials(
            credential: Credential(clientID: "id", clientSecret: "secret")
        ),
        handler: @escaping @Sendable (HTTPRequest) throws -> HTTPResponse
    ) -> STTSClient {
        STTSClient(
            baseURL: URL(string: "https://stts.example")!,
            transport: HandlerTransport(handler: handler),
            credentials: credentials
        )
    }

    private func jsonResponse(_ object: [String: Any], status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["content-type": "application/json"],
            body: try JSONSerialization.data(withJSONObject: object)
        )
    }

    private func audioResponse() -> HTTPResponse {
        HTTPResponse(
            status: 200,
            headers: ["content-type": "audio/mpeg"],
            body: Data([0x01, 0x02, 0x03])
        )
    }

    private func completedEnvelope() -> [String: Any] {
        [
            "version": "1",
            "eventId": "e1",
            "conversationId": "conv-2",
            "cursor": "c1",
            "occurredAt": "2026-09-23T12:00:00Z",
            "correlationId": "op-1",
            "type": "response.completed",
            "critical": true,
            "data": ["text": "Done", "responseId": "resp-1"]
        ]
    }

    private func bodyObject(_ request: HTTPRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request?.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Health and headers

    func testHealthAttachesAccessHeadersAndDecodes() async throws {
        let box = RequestBox()
        let response = try jsonResponse(["status": "ok"])
        let client = makeClient { request in
            box.store(request)
            return response
        }

        try await client.health()

        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.path, "/api/health")
        XCTAssertEqual(request.headers["CF-Access-Client-Id"], "id")
        XCTAssertEqual(request.headers["CF-Access-Client-Secret"], "secret")
    }

    func testMissingCredentialSendsNoAccessHeaders() async throws {
        let box = RequestBox()
        let response = try jsonResponse(["status": "ok"])
        let client = makeClient(credentials: StubCredentials(credential: nil)) { request in
            box.store(request)
            return response
        }

        try await client.health()

        let request = try XCTUnwrap(box.request)
        XCTAssertNil(request.headers["CF-Access-Client-Id"])
        XCTAssertNil(request.headers["CF-Access-Client-Secret"])
    }

    // MARK: Create conversation

    func testCreateConversationSendsProtocolBody() async throws {
        let box = RequestBox()
        let response = try jsonResponse(
            ["conversationId": "conv-1", "profile": "chief-of-staff"],
            status: 201
        )
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let handle = try await client.createConversation(profile: "chief-of-staff", operationId: "op-1")

        XCTAssertEqual(handle.conversationId, "conv-1")
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/conversations")
        let object = try bodyObject(request)
        XCTAssertEqual(object["operationId"] as? String, "op-1")
        XCTAssertEqual(object["profile"] as? String, "chief-of-staff")
    }

    // MARK: Submit turn

    func testSubmitTurnBodyMatchesProtocolAndReducesCompleted() async throws {
        let box = RequestBox()
        let response = try jsonResponse(
            ["conversationId": "conv-2", "events": [completedEnvelope()]],
            status: 202
        )
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let submission = try await client.submitTurn(
            text: "hello",
            conversationId: "conv-1",
            timezone: "UTC",
            locale: "en-GB",
            operationId: "op-1"
        )

        XCTAssertEqual(submission.conversationId, "conv-2")
        guard case .completed(let text, let responseId) = submission.result else {
            return XCTFail("Expected completed result")
        }
        XCTAssertEqual(text, "Done")
        XCTAssertEqual(responseId, "resp-1")

        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.url.path, "/api/conversations/conv-1/turns")
        let object = try bodyObject(request)
        XCTAssertEqual(object["operationId"] as? String, "op-1")
        XCTAssertEqual(object["conversationId"] as? String, "conv-1")
        XCTAssertEqual(object["surface"] as? String, "voice-live")
        XCTAssertTrue(object["profileOverride"] is NSNull, "profileOverride must be explicit null")
        let input = try XCTUnwrap(object["input"] as? [String: Any])
        XCTAssertEqual(input["kind"] as? String, "text")
        XCTAssertEqual(input["text"] as? String, "hello")
        let context = try XCTUnwrap(object["clientContext"] as? [String: Any])
        XCTAssertEqual(context["timezone"] as? String, "UTC")
        XCTAssertEqual(context["locale"] as? String, "en-GB")
    }

    func testSubmitTurnReducesInputRequested() async throws {
        let envelope: [String: Any] = [
            "version": "1",
            "eventId": "e2",
            "conversationId": "conv-2",
            "cursor": "c2",
            "occurredAt": "2026-09-23T12:00:01Z",
            "correlationId": "op-1",
            "type": "input.requested",
            "critical": true,
            "data": [
                "requestId": "req-1",
                "kind": "approval",
                "prompt": "Proceed?",
                "choices": [],
                "confirmationNonce": "nonce-1"
            ]
        ]
        let response = try jsonResponse(["conversationId": "conv-2", "events": [envelope]], status: 202)
        let client = makeClient { _ in response }

        let submission = try await client.submitTurn(
            text: "hello",
            conversationId: "conv-1",
            timezone: "UTC",
            locale: "en"
        )

        guard case .inputRequested(let pending) = submission.result else {
            return XCTFail("Expected inputRequested result")
        }
        XCTAssertEqual(pending.requestId, "req-1")
        XCTAssertEqual(pending.kind, .approval)
        XCTAssertEqual(pending.prompt, "Proceed?")
        XCTAssertEqual(pending.confirmationNonce, "nonce-1")
    }

    func testSubmitTurnWithoutTerminalEventThrows() async throws {
        let response = try jsonResponse(["conversationId": "conv-2", "events": []], status: 202)
        let client = makeClient { _ in response }

        do {
            _ = try await client.submitTurn(
                text: "hello",
                conversationId: "conv-1",
                timezone: "UTC",
                locale: "en"
            )
            XCTFail("Expected invalidResponse error")
        } catch let error as STTSClientError {
            XCTAssertEqual(error, .invalidResponse("Missing response"))
        }
    }

    func testUnknownEventTypeIsTolerated() async throws {
        var envelope = completedEnvelope()
        envelope["type"] = "future.event"
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        let decoded = try JSONDecoder().decode(EventEnvelope.self, from: envelopeData)
        XCTAssertEqual(decoded.type, .unknown("future.event"))
        XCTAssertTrue(decoded.critical)
    }

    func testAnswerInputSendsAnswerShape() async throws {
        let box = RequestBox()
        let response = try jsonResponse(["conversationId": "conv-2", "events": [completedEnvelope()]], status: 202)
        let client = makeClient { request in
            box.store(request)
            return response
        }

        _ = try await client.answerInput(
            conversationId: "conv-1",
            requestId: "req-1",
            answer: .approve(nonce: "nonce-1"),
            operationId: "op-9"
        )

        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.url.path, "/api/conversations/conv-1/inputs/req-1/answer")
        let object = try bodyObject(request)
        XCTAssertEqual(object["operationId"] as? String, "op-9")
        let answer = try XCTUnwrap(object["answer"] as? [String: Any])
        XCTAssertEqual(answer["kind"] as? String, "approve")
        XCTAssertEqual(answer["confirmationNonce"] as? String, "nonce-1")
        XCTAssertNil(answer["text"])
    }

    func testInterruptRunSendsReasonAndReturnsRotatedHandle() async throws {
        let box = RequestBox()
        let response = try jsonResponse(["conversationId": "conv-9", "events": []], status: 202)
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let conversationId = try await client.interruptRun(
            conversationId: "conv-1",
            runId: "run-1",
            reason: .userCancelled,
            operationId: "op-7"
        )

        XCTAssertEqual(conversationId, "conv-9")
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.url.path, "/api/conversations/conv-1/runs/run-1/interrupt")
        let object = try bodyObject(request)
        XCTAssertEqual(object["operationId"] as? String, "op-7")
        XCTAssertEqual(object["runId"] as? String, "run-1")
        XCTAssertEqual(object["reason"] as? String, "user_cancelled")
    }

    func testErrorResponsesCarryWorkerCode() async throws {
        let response = try jsonResponse(
            ["code": "PAYLOAD_TOO_LARGE", "message": "Voice note too large", "retryable": false],
            status: 413
        )
        let client = makeClient { _ in response }

        do {
            _ = try await client.transcribe(audioData: Data([0x01]), operationId: "op-1")
            XCTFail("Expected requestFailed error")
        } catch let error as STTSClientError {
            XCTAssertEqual(error, .requestFailed(status: 413, code: "PAYLOAD_TOO_LARGE"))
        }
    }

    // MARK: Transcription multipart

    func testTranscribeBuildsMultipartWithDeclaredFields() async throws {
        let box = RequestBox()
        let response = try jsonResponse(
            ["operationId": "op-9", "text": "recognized", "language": "en", "duration": 3.5]
        )
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let result = try await client.transcribe(
            audioData: Data([0x01, 0x02, 0x03]),
            mimeType: "audio/mp4",
            fileExtension: "m4a",
            operationId: "op-9"
        )

        XCTAssertEqual(result.text, "recognized")
        XCTAssertEqual(result.language, "en")
        XCTAssertEqual(result.duration, 3.5)

        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/api/transcriptions")
        let contentType = try XCTUnwrap(request.headers["content-type"])
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = try XCTUnwrap(contentType.components(separatedBy: "boundary=").last)

        let body = String(decoding: try XCTUnwrap(request.body), as: UTF8.self)
        XCTAssertTrue(
            body.contains("--\(boundary)\r\nContent-Disposition: form-data; name=\"operationId\"\r\n\r\nop-9\r\n")
        )
        XCTAssertTrue(
            body.contains("Content-Disposition: form-data; name=\"audio\"; filename=\"voice-note.m4a\"\r\n")
        )
        XCTAssertTrue(body.contains("Content-Type: audio/mp4\r\n"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
    }

    func testTranscribeIncludesSegmentClaimAndDecodesEcho() async throws {
        let box = RequestBox()
        let response = try jsonResponse([
            "operationId": "op-9",
            "text": "recognized",
            "recordingId": "meeting-1",
            "segmentIndex": 4
        ])
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let claim = TranscriptionSegmentClaim(
            recordingId: "meeting-1",
            segmentIndex: 4,
            segmentStartedAtMs: 180_000,
            segmentDurationMs: 45_000
        )
        let result = try await client.transcribe(
            audioData: Data([0x01]),
            segment: claim,
            operationId: "op-9"
        )

        XCTAssertEqual(result.recordingId, "meeting-1")
        XCTAssertEqual(result.segmentIndex, 4)

        let request = try XCTUnwrap(box.request)
        let contentType = try XCTUnwrap(request.headers["content-type"])
        let boundary = try XCTUnwrap(contentType.components(separatedBy: "boundary=").last)
        let body = String(decoding: try XCTUnwrap(request.body), as: UTF8.self)
        for field in ["recordingId", "segmentIndex", "segmentStartedAtMs", "segmentDurationMs"] {
            XCTAssertTrue(
                body.contains("name=\"\(field)\""),
                "multipart body must declare \(field)"
            )
        }
        XCTAssertTrue(body.contains("180000"))
        XCTAssertTrue(body.contains("45000"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
    }

    func testSubmitTurnCarriesMeetingSurface() async throws {
        let box = RequestBox()
        let envelope: [String: Any] = [
            "version": "1",
            "eventId": "e1",
            "conversationId": "conv-2",
            "cursor": "c1",
            "occurredAt": "2026-09-23T12:00:00Z",
            "correlationId": "op-2",
            "type": "response.completed",
            "critical": true,
            "data": ["responseId": "resp-1", "text": "Summary"]
        ]
        let response = try jsonResponse(
            ["conversationId": "conv-2", "events": [envelope]],
            status: 202
        )
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let submission = try await client.submitTurn(
            text: "transcript",
            conversationId: "conv-1",
            timezone: "UTC",
            locale: "en",
            surface: .meetingTranscript,
            operationId: "op-2"
        )

        XCTAssertEqual(submission.conversationId, "conv-2")
        let request = try XCTUnwrap(box.request)
        let object = try bodyObject(request)
        XCTAssertEqual(object["surface"] as? String, "meeting-transcript")
    }

    // MARK: Synthesis

    func testSynthesizePostsCommandAndReturnsAudio() async throws {
        let box = RequestBox()
        let response = audioResponse()
        let client = makeClient { request in
            box.store(request)
            return response
        }

        let command = SynthesizeResponseCommand(
            operationId: "op-5",
            conversationId: "conv-1",
            responseId: "resp-1"
        )
        let audio = try await client.synthesize(command: command)

        XCTAssertEqual(audio, Data([0x01, 0x02, 0x03]))
        let request = try XCTUnwrap(box.request)
        XCTAssertEqual(request.url.path, "/api/speech/synthesis")
        let object = try bodyObject(request)
        XCTAssertEqual(object["operationId"] as? String, "op-5")
        XCTAssertEqual(object["conversationId"] as? String, "conv-1")
        XCTAssertEqual(object["responseId"] as? String, "resp-1")
        XCTAssertEqual(object["voice"] as? String, "default")
        XCTAssertEqual(object["format"] as? String, "audio/mpeg")
    }

    func testSynthesizeSurfacesWorkerErrorCode() async throws {
        let response = try jsonResponse(["code": "RESPONSE_NOT_FOUND"], status: 404)
        let client = makeClient { _ in response }
        let command = SynthesizeResponseCommand(conversationId: "conv-1", responseId: "resp-1")

        do {
            _ = try await client.synthesize(command: command)
            XCTFail("Expected requestFailed error")
        } catch let error as STTSClientError {
            XCTAssertEqual(error, .requestFailed(status: 404, code: "RESPONSE_NOT_FOUND"))
        }
    }
}
