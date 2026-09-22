# Hermes pinned gateway contract

## Evidence

The deployed infrastructure pins `NousResearch/hermes-agent` commit:

```text
b6b53c69a6ed49cb099cf1bfe76b5e6edd718e5a
```

This document records only contracts verified in that source. It does not assume that current upstream `main` matches the deployed image.

Primary source files:

- `web/src/lib/gatewayClient.ts`
- `apps/shared/src/json-rpc-gateway.ts`
- `tui_gateway/ws.py`
- `tui_gateway/methods_session.py`
- `tui_gateway/methods_prompt.py`
- `tui_gateway/prompt_turn.py`
- `tui_gateway/event_replay.py`

## Transport

The dashboard client connects to `/api/ws`. Each WebSocket text frame is one JSON-RPC 2.0 object. Requests have `id`, `method`, and `params`. Events use method `event` with the event body in `params`.

```json
{
  "jsonrpc": "2.0",
  "id": "stts-1",
  "method": "prompt.submit",
  "params": {
    "session_id": "runtime-session",
    "text": "Hello"
  }
}
```

```json
{
  "jsonrpc": "2.0",
  "method": "event",
  "params": {
    "type": "message.delta",
    "session_id": "runtime-session",
    "seq": 4,
    "payload": { "text": "Hello" }
  }
}
```

## Core methods

| Method | Purpose | Relevant fields |
|---|---|---|
| `session.create` | Create a runtime and durable session | request `profile`, `source`, optional `close_on_disconnect`; result `session_id`, `stored_session_id` |
| `session.resume` | Reattach to stored history | request `session_id`, optional `profile`; result includes new runtime `session_id` |
| `prompt.submit` | Start a turn | `session_id`, `text`; result status `streaming` |
| `session.interrupt` | Interrupt active work | `session_id`; result status `interrupted` |
| `session.events.since` | Replay missed events | `session_id`, `last_seen`; result `events`, replay epoch/truncation metadata |
| `clarify.respond` | Answer a clarification card | session and request correlation plus `answer` |
| `approval.respond` | Resolve an approval | `session_id`, `request_id`, `choice`, optional `all` |
| `gateway.ping` | Heartbeat | empty params |

The adapter must use runtime `session_id` for active RPC calls and retain `stored_session_id` as the durable identity used for resume. Application clients receive neither raw identifier.

## Core events

| Hermes event | Normalized event |
|---|---|
| `message.start` | `response.started` |
| `message.delta` | `response.delta` |
| successful `message.complete` | `response.completed` |
| unsuccessful `message.complete` | `response.failed` |
| `tool.start/progress/complete` | `activity.started/updated/completed` |
| `subagent.*` | specialist activity |
| `clarify.request` | `input.requested` / clarification |
| `approval.request` | `input.requested` / approval |
| `error` | `error.occurred` |

`thinking.delta`, `reasoning.delta`, and `reasoning.available` are intentionally dropped. Internal reasoning is not part of the STTS application contract.

`message.complete` carries final `text` and a status. Only status `complete` becomes final response text eligible for TTS.

## Replay

Hermes stamps session events with a monotonic `seq` and retains a bounded replay ring. The server also publishes a replay epoch because sequence numbering resets after a gateway restart.

The adapter must:

1. Record the latest applied `seq` per runtime session.
2. Call `session.events.since` after reconnect.
3. Apply replay events before parked live events.
4. Deduplicate non-increasing sequence numbers.
5. Reset sequence watermarks when the replay epoch changes.
6. Rebuild from durable session history if Hermes reports truncated replay.

## Authentication constraint

Hermes dashboard authentication has two distinct modes:

- loopback/insecure mode uses a session token query parameter;
- gated mode mints a fresh single-use WebSocket ticket through `/api/auth/ws-ticket` and rejects the legacy token path.

The production BFF must not assume that a dashboard session token works through the Access-gated hostname. Before implementing the live relay, verify or provision a machine-to-machine path that can both pass Cloudflare Access and obtain an accepted Hermes WebSocket credential. Until that is proven, committed `AGENT_MODE=hermes` fails closed.

The separate Hermes OpenAI-compatible API is not a substitute for this gateway contract because it does not preserve the same replay, clarification, approval, and interruption semantics.

## Compatibility policy

- Pin adapter fixtures to the deployed Hermes commit.
- Reject malformed frames and sanitize upstream error text.
- Treat additive unknown events as non-critical and ignore them.
- Require contract tests before changing the pinned commit.
- Never pass arbitrary Hermes method names or upstream payloads from the browser.
