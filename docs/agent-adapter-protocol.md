# Agent adapter protocol

## Purpose

The application protocol separates clients from Hermes and future agent stacks. It defines semantic commands and events, not an upstream RPC mirror. Stack-specific identifiers and payloads stay behind the adapter.

This document is the initial contract. Concrete endpoint schemas should be generated from shared runtime-validated types during implementation.

## Design rules

- IDs are opaque strings.
- Times are RFC 3339 UTC strings.
- Commands are idempotent by `operationId`.
- Events have a unique `eventId` and monotonically ordered opaque `cursor` within a conversation.
- Additive fields and new event types are versioned compatibility changes.
- Unknown events may be ignored only when marked non-critical.
- Internal model reasoning, credentials, raw tool secrets, and upstream stack payloads are excluded.

## Common event envelope

```json
{
  "version": "1",
  "eventId": "evt_opaque",
  "conversationId": "conv_opaque",
  "cursor": "cursor_opaque",
  "occurredAt": "2026-09-22T12:00:00Z",
  "correlationId": "corr_opaque",
  "type": "response.completed",
  "critical": true,
  "data": {}
}
```

`correlationId` connects logs across the client, BFF, speech service, and adapter. It is not authorization and must not contain user data.

## Commands

### Create conversation

```json
{
  "operationId": "op_opaque",
  "profile": "chief-of-staff"
}
```

Returns an opaque application `conversationId`. The adapter stores or derives the associated upstream session identity without exposing it to the client.

### Transcribe voice note

Multipart request containing:

- `operationId`
- `audio`
- optional declared `language`
- codec and duration metadata when known

The response contains recognized text, detected language when available, and an operation status. Confidence is included only if the speech backend provides a meaningful calibrated value.

### Submit turn

```json
{
  "operationId": "op_opaque",
  "conversationId": "conv_opaque",
  "input": {
    "kind": "text",
    "text": "Book a service for Friday"
  },
  "profileOverride": null,
  "clientContext": {
    "timezone": "Europe/London",
    "locale": "en-GB"
  }
}
```

Only allowlisted context is accepted. Arbitrary browser or device state is not forwarded.

### Answer input request

```json
{
  "operationId": "op_opaque",
  "conversationId": "conv_opaque",
  "requestId": "req_opaque",
  "answer": {
    "kind": "text",
    "text": "Friday afternoon"
  }
}
```

Approval answers additionally require a server-issued confirmation nonce after read-back.

HTTP mapping:

```text
POST /api/conversations/{conversationId}/inputs/{requestId}/answer
```

The Worker verifies that the request ID and input kind are bound into the owner-authenticated encrypted conversation handle. `approve` must include the exact one-time `confirmationNonce` emitted with the pending approval. Approval maps only to Hermes choice `once`; denial maps to `deny`. Clarification maps to `clarify.respond`. A successful response returns a replacement conversation handle with the pending input removed.

### Interrupt run

```json
{
  "operationId": "op_opaque",
  "conversationId": "conv_opaque",
  "runId": "run_opaque",
  "reason": "user_redirect"
}
```

HTTP mapping:

```text
POST /api/conversations/{conversationId}/runs/{runId}/interrupt
```

The Worker validates the owner-bound conversation handle, resumes its durable Hermes session, and calls `session.interrupt` with the current runtime session ID. The response contains `run.interrupting` followed by either `run.interrupted` or `run.interrupt_failed`; upstream session IDs remain excluded.

### Synthesize response

```json
{
  "operationId": "op_opaque",
  "conversationId": "conv_opaque",
  "responseId": "response_opaque",
  "voice": "default",
  "format": "audio/mpeg"
}
```

The BFF resolves text by `responseId`. Clients do not send arbitrary text for privileged synthesis unless a future endpoint explicitly permits it.

## Events

### Conversation lifecycle

- `conversation.snapshot`: reconstructed current state on initial load or fallback recovery.
- `connection.resumed`: replay completed and live delivery resumed.

### Turn lifecycle

- `turn.transcribed`: recognized user text is available.
- `turn.accepted`: agent stack accepted the turn; includes `turnId` and `runId`.
- `turn.rejected`: stable reason and retryability.

### Response lifecycle

- `response.started`: coordinator response began.
- `response.delta`: append-only display text delta.
- `response.completed`: authoritative final display/TTS text and `responseId`.
- `response.failed`: stable error code and retryability.

Adapters must emit exactly one terminal response event per accepted run: completed, failed, or interrupted.

### Activity

- `activity.started`
- `activity.updated`
- `activity.completed`
- `activity.failed`

Activity data includes a safe label, category (`specialist` or `tool`), status, and optional concise result summary. Raw tool arguments and outputs are excluded by default.

### Input requests

- `input.requested`: clarification or approval request, prompt, expiry, and allowed answer modes.
- `input.resolved`: accepted answer or decision.
- `input.expired`: request can no longer be answered.

Approval events include a safe action summary and risk level. They never include executable secrets.

### Interruption

- `run.interrupting`
- `run.interrupted`
- `run.interrupt_failed`

### Speech

- `speech.synthesis.started`
- `speech.synthesis.ready`: response ID, media type, duration when known, and a short-lived same-origin URL.
- `speech.synthesis.failed`

### Error

`error.occurred` contains:

```json
{
  "code": "UPSTREAM_UNAVAILABLE",
  "message": "Agent service unavailable",
  "retryable": true,
  "operationId": "op_opaque"
}
```

Messages are concise and safe for users. Detailed diagnostics belong in redacted server logs under the correlation ID.

## Stable error codes

Initial codes:

- `AUTH_REQUIRED`
- `FORBIDDEN`
- `INVALID_REQUEST`
- `PAYLOAD_TOO_LARGE`
- `UNSUPPORTED_AUDIO`
- `TRANSCRIPTION_FAILED`
- `CONVERSATION_NOT_FOUND`
- `TURN_CONFLICT`
- `UPSTREAM_UNAVAILABLE`
- `UPSTREAM_PROTOCOL_ERROR`
- `REQUEST_EXPIRED`
- `INTERRUPT_FAILED`
- `SYNTHESIS_FAILED`
- `RATE_LIMITED`

## Hermes mapping

The Hermes adapter is expected to map normalized operations to Hermes' typed JSON-RPC WebSocket, including prompt submission, streamed messages, tool activity, approval/clarification, interruption, and session replay. Exact deployed method and event names are intentionally absent from this public contract and must be recorded in adapter tests after live schema verification.

Chief of Staff is the default upstream profile. Profile overrides use application slugs mapped to verified Hermes profile identifiers in server configuration.

## Compatibility tests

Every adapter must pass a shared contract suite covering:

- ordered streaming and deduplication;
- one terminal event per run;
- reconnect and replay;
- clarification and approval correlation;
- interruption races;
- safe redaction of upstream payloads;
- retry/idempotency behavior;
- malformed and unknown upstream events.
