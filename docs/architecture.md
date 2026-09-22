# Architecture

## Decision summary

The recommended architecture is **Approach 1: Cloudflare Worker BFF with a Hermes adapter**.

```text
Installable mobile PWA
        │
        │ Access-authenticated HTTPS and WebSocket
        ▼
Cloudflare Worker BFF
        ├── Speech adapter ── speech.cdslash.com
        │                     ├── Qwen STT
        │                     └── Kokoro TTS
        │
        └── Agent adapter ─── Hermes gateway
                              └── Chief of Staff
                                  └── specialist profiles
```

This is the smallest architecture that keeps secrets server-side, preserves Hermes capabilities, and gives future agent stacks a stable adapter boundary.

## Responsibilities

### PWA

- Capture, preview, and locally discard recordings.
- Upload a submitted voice note.
- Render the normalized conversation event stream.
- Assemble or receive completed response audio.
- Play, stop, and replay audio.
- Maintain transient interaction state.
- Store only non-sensitive user preferences locally.

The PWA does not know Hermes RPC method names, hold service tokens, choose specialists on behalf of the coordinator, or become the durable conversation authority.

### Cloudflare Worker BFF

- Validate Cloudflare Access identity on every HTTP request and WebSocket upgrade.
- Authorize the identity for the requested conversation.
- Hold upstream service credentials in Worker secrets.
- Validate payload type and size, apply limits, and set timeouts.
- Proxy STT and TTS through a speech adapter.
- Relay agent traffic through a stack-specific adapter.
- Convert upstream activity into the normalized application protocol.
- Apply idempotency, correlation, redaction, and safe error mapping.

The Worker is the application's only public backend. It is a policy and translation boundary, not the coordinator.

### Speech service

- Transcribe submitted voice-note audio with Qwen STT.
- Synthesize finalized coordinator text with Kokoro TTS.
- Return explicit media types and machine-readable errors.

Speech remains app-owned rather than Hermes-owned. This lets another agent stack use the same voice pipeline and keeps speech behavior consistent across adapters.

### Hermes adapter

- Establish a service-authenticated Hermes connection.
- Map application conversation IDs to Hermes session IDs.
- Submit turns to the selected profile, defaulting to Chief of Staff.
- Normalize message deltas/completion, specialist and tool activity, clarification, approval, interruption, errors, and replay.
- Translate normalized client commands back to Hermes operations.

Hermes remains authoritative for sessions, text transcript, coordinator reasoning, specialist routing, tools, approvals, and agent interruption.

## Coordinator boundary

The app does not implement coordinator reasoning. Chief of Staff owns delegation and composes the user-facing answer. The app's deterministic controller only manages capture, transport, audio playback, state transitions, and safety confirmation.

This distinction prevents UI code from silently acquiring agent policy and permits the coordinator to evolve independently.

## Data ownership

| Data | Initial authority | Retention |
|---|---|---|
| Conversation text and agent events | Hermes | Hermes policy |
| Agent execution and tool state | Hermes | Hermes policy |
| Source recording | Browser/Worker request | Ephemeral |
| Synthesized audio | Browser/Worker response | Ephemeral; regenerable |
| Identity | Cloudflare Access | Access policy |
| Upstream credentials | Worker secrets | Until rotated |
| UI preferences | Browser | User-controlled |
| Correlation and security logs | Worker/platform | Short, configured window |

No Durable Object, D1, or R2 is required initially. If the application later needs shared threads, multi-device fan-out, or an independent event history, persistence can be added behind the same protocol.

## Transport

Use HTTPS for commands and finite media operations. Use a WebSocket or a resumable event stream for normalized agent events. The exact Worker implementation can be chosen during scaffolding, but the application semantics must not depend on transport framing.

Every operation carries:

- an opaque conversation ID;
- a client-generated operation ID;
- a server correlation ID;
- an event cursor where replay is supported.

## Failure boundaries

- **Capture failure:** remains local; no turn exists.
- **STT failure:** retain the local recording until retry or discard.
- **Agent submission failure before acceptance:** safely retry with the same operation ID.
- **Connection loss after acceptance:** reconnect and resume/rebuild; do not resubmit blindly.
- **TTS failure:** preserve finalized text and offer synthesis retry.
- **Playback failure:** preserve audio/text and expose replay or text-only state.
- **Upstream malformed event:** log a redacted adapter error and emit a stable application error.

## Alternatives considered

### Approach 2: direct browser-to-Hermes connection

This is initially shorter, but it couples the client to Hermes' broad RPC contract, complicates browser WebSocket authentication, increases credential exposure risk, and forces UI changes when another stack is added. It is not recommended.

### Approach 3: Durable Object conversation hub

A Durable Object per conversation would provide strong multi-device fan-out and application-owned ordering. It would also duplicate session responsibilities Hermes already provides and add storage, migration, and failure modes before they are needed. Defer it until multi-user or multi-device requirements justify it.

## Evolution to native iOS and CarPlay

The PWA validates the interaction and backend. A later Swift client consumes the same HTTP commands and normalized event protocol. CarPlay requires a native entitlement-compatible app and a constrained, voice-first interface; it cannot be delivered by the PWA alone.

CarPlay should expose only safe conversational actions, short status prompts, clarification, and confirmation. Browsing full transcripts, specialist internals, configuration, and complex recovery stay on the phone.

## Constraints requiring validation

- Confirm the deployed Hermes gateway's exact JSON-RPC methods, event names, replay cursors, and cancellation semantics before implementing the adapter.
- Confirm Cloudflare Worker support and limits for the chosen WebSocket relay and audio payload sizes.
- Confirm the speech gateway's accepted codecs, duration limits, response media types, and authentication.
- Confirm Apple's current CarPlay app category, entitlement, and template eligibility before committing to a native release plan.
