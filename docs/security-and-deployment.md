# Security and deployment

## Trust boundaries

```text
Untrusted browser
  │ Cloudflare Access identity
  ▼
Worker BFF and secrets
  ├─ service-authenticated speech origin
  └─ service-authenticated Hermes origin
```

The browser, audio metadata, client IDs, and all upstream responses are untrusted inputs. Cloudflare Access authentication establishes identity, not blanket authorization or payload trust.

## Authentication and authorization

- Protect the application and every API route with Cloudflare Access.
- Validate the Access JWT at the Worker, including signature, issuer, audience, and expiry.
- Validate identity again for WebSocket upgrades; do not rely only on a prior page request.
- Restrict the initial deployment to the owner's allowlisted identity.
- Bind every conversation operation to the authenticated subject.
- Never accept a client-supplied upstream session ID or identity.
- Use short-lived, narrowly scoped service credentials between the Worker and origins.

## Secrets

Store only in Worker secrets or the relevant platform secret manager:

- Hermes service token/Access credentials.
- Speech service token/Access credentials.
- Any signing or encryption keys introduced later.

Do not put secrets in source control, Wrangler variables committed to Git, browser bundles, local storage, query strings, analytics, or error responses. Document secret names but never values.

Current bindings:

- `AUTH_MODE` (`access` in committed configuration)
- `SPEECH_MODE` (`live` in committed configuration)
- `AGENT_MODE` (`hermes` in committed configuration; fails closed until implemented)
- `HERMES_BASE_URL`
- `HERMES_ACCESS_CLIENT_ID` (secret)
- `HERMES_ACCESS_CLIENT_SECRET` (secret)
- `HERMES_TIMEOUT_MS`
- `HERMES_TURN_TIMEOUT_MS`
- `CONVERSATION_STATE_KEY` (secret; random 32-byte base64url key)
- `RESPONSE_TOKEN_TTL_SECONDS` (60–3600; defaults to 900)
- `SPEECH_BASE_URL`
- `SPEECH_API_KEY` (secret)
- `SPEECH_TIMEOUT_MS`
- `ACCESS_AUD`
- `ACCESS_ISSUER` (the exact HTTPS Access team issuer)

Hermes uses a host-specific Access service token to fetch the dashboard bootstrap and open its authenticated WebSocket. Never reuse that token for another Access app. The current speech gateway uses a fixed client bearer key. If either authentication contract changes, replace the adapter credentials without changing the browser protocol.

Conversation handles are encrypted and authenticated with AES-GCM, bind to a truncated SHA-256 fingerprint of the Access subject, and carry the selected profile plus durable Hermes session ID. They are not storage or bearer authorization: every operation still requires a valid Access identity, and a handle fails validation for another subject. Rotate `CONVERSATION_STATE_KEY` only with an explicit plan to invalidate all outstanding handles.

The PWA may retain the opaque handle in local storage to continue after reload. It does not store transcript text, audio, credentials, raw Hermes identifiers, approval secrets outside the encrypted handle, or an authorization grant. Clearing site data removes local continuation state; Hermes remains the transcript authority.

Completed-response IDs use the same key with separate authenticated context. They bind the final text to both Access subject and a stable random conversation key carried inside each rotating handle, and expire after `RESPONSE_TOKEN_TTL_SECONDS`. This allows replay after later turns without accepting arbitrary synthesis text or storing response audio.

The Worker verifies the Access assertion's RS256 signature against the issuer JWKS and validates issuer, audience, expiry, activation time, and subject. Committed configuration defaults to Access authentication and live adapters; missing bindings fail closed. The local bypass is accepted only when an explicit ignored `.dev.vars` file sets `AUTH_MODE=local`.

## Request controls

The list below is the production target. Route and schema allowlists, bounded uploads, filename normalization, text limits, deadlines, and upstream method allowlists are implemented. Durable idempotency and subject-level rate limiting remain required before general availability.

- Allow only expected HTTP methods, routes, media types, and origins.
- Apply audio byte and duration limits before forwarding.
- Normalize filenames and never trust file extensions.
- Enforce transcript and synthesis text limits.
- Set per-stage deadlines and bounded retry policies.
- Rate-limit by authenticated subject and route.
- Use idempotency keys to prevent duplicate agent/tool actions.
- Reject client-provided URLs and arbitrary upstream method names.

If audio transcoding is needed, run it in a constrained service designed for media processing rather than executing arbitrary binaries in request handlers.

## Approval safety

- Bind approval to authenticated subject, conversation, request ID, action digest, expiry, and one-time confirmation nonce.
- Require explicit read-back confirmation for consequential actions.
- Re-fetch current request state before applying a decision.
- Fail closed on ambiguity, expiry, replay, connection loss, or mismatched action digest.
- Record who decided, what request was decided, and when; do not retain approval audio.

## Content and privacy

- Do not log source audio, full transcripts, prompts, tool arguments, tool output, credentials, or authorization headers by default.
- Log stable event/error codes, timings, byte counts, adapter name/version, and correlation IDs.
- Redact upstream errors before returning them.
- Avoid third-party analytics in the first milestone.
- Define a short operational log retention period before production use.
- Keep internal reasoning out of APIs and logs.

## Browser controls

- Use a restrictive Content Security Policy.
- Use same-origin API URLs.
- Set `Secure`, `HttpOnly`, and appropriate `SameSite` attributes for any application cookies.
- Do not persist bearer credentials in browser storage.
- Set `Permissions-Policy` to allow microphone only where required.
- Prevent framing unless explicitly needed.
- Disable MIME sniffing and set explicit media types.
- Revoke object URLs and release microphone tracks promptly.

## Origin controls

- Origins should accept traffic only through approved Cloudflare/service paths or private networking.
- Authenticate Worker-to-origin requests independently from end-user identity.
- Rotate credentials without a client release.
- Pin allowed hostnames and protocols in server configuration.
- Apply network and application timeouts to both speech and Hermes connections.

## Deployment environments

Use separate Worker environments and credentials:

| Environment | Purpose | Upstreams |
|---|---|---|
| local | Contract and UI development | mocks by default |
| preview | PR validation | non-production or read-limited services |
| production | Owner use | production speech and Hermes |

Production credentials must never be exposed to preview deployments from untrusted branches.

## Observability

Measure:

- capture-to-transcript latency;
- transcript-to-turn-accepted latency;
- time to first response text;
- response completion latency;
- synthesis latency and response duration;
- reconnect/replay frequency;
- transcription, agent, and synthesis failure rates;
- approval and interruption outcomes.

Use correlation IDs across stages. Alerts should identify a failed boundary without including conversation content.

## Deployment checks

Before production:

- Verify Access JWT validation against the production audience.
- Verify unauthorized HTTP and WebSocket access is rejected.
- Confirm no service credential is present in browser artifacts or network responses.
- Exercise maximum-size, malformed, and unsupported audio requests.
- Exercise upstream timeout, disconnect, malformed-event, and rate-limit behavior.
- Exercise approval replay and expiry attacks.
- Confirm logs and traces contain no audio, transcript content, or authorization headers.
- Confirm TTS URLs expire and cannot access another conversation.
- Run dependency, secret, and static security scans.

## Incident response basics

If a service credential is suspected exposed: revoke it, rotate the Worker secret, inspect redacted access logs by correlation/time window, invalidate active upstream connections, and redeploy. Client releases should not be necessary because credentials are server-side.
