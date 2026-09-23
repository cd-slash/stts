# STTS

STTS is a voice-note-first client for conversations with coordinator-led AI agent stacks. It records a spoken turn, transcribes it, sends the text to a coordinator, presents the resulting conversation, and returns the coordinator's answer as a replayable voice note.

The first integration targets Hermes, with its **Chief of Staff** profile coordinating specialist profiles. The application protocol remains independent of Hermes so other agent stacks can be added without changing the client.

## Recommended architecture

**Approach 1: an installable PWA backed by a Cloudflare Worker BFF and a Hermes adapter.**

```text
PWA ── Cloudflare Access ── Worker BFF ── Speech service
                                  └────── Hermes adapter ── Chief of Staff
```

The browser never receives upstream service credentials. The Worker owns authentication, policy, request limits, speech proxying, and protocol normalization. Hermes owns coordinator reasoning, specialist routing, tools, and conversation history.

See [Architecture](docs/architecture.md) for the decision and alternatives.

## First milestone

The initial vertical slice supports:

1. Authenticate with Cloudflare Access.
2. Record and submit a voice note.
3. Transcribe it through the speech service.
4. send the transcript to Hermes Chief of Staff.
5. Show normalized coordinator and specialist activity.
6. Synthesize the completed response.
7. Play, stop, replay, or retry the response voice note.

CarPlay is a later native iOS client using the same BFF and application protocol. A PWA is not itself a CarPlay application.

## Documentation

- [Product requirements](docs/product-requirements.md)
- [Architecture](docs/architecture.md)
- [Communication flow](docs/communication-flow.md)
- [Agent adapter protocol](docs/agent-adapter-protocol.md)
- [Hermes pinned contract](docs/hermes-pinned-contract.md)
- [Security and deployment](docs/security-and-deployment.md)
- [Roadmap](docs/roadmap.md)
- [Architecture decision record](docs/decisions/0001-worker-bff.md)

## Status

An owner-only preview is deployed at `https://stts.cdslash.com` behind Cloudflare Access. Live acceptance passes conversation creation, first and resumed Hermes turns, completed-response replay after handle rotation, Kokoro synthesis, and Qwen transcription through the Worker.

The implementation contains a mobile PWA shell, Worker BFF, shared validated protocol, local mock adapters, Cloudflare Access JWT verification, production STT/TTS adapters, expiring response-audio tokens, and a Hermes adapter with opaque encrypted conversation state, durable resume, stale-event rejection, clarification responses, nonce-gated read-back approvals, and interruption. Resumable browser event streaming, transcript hydration, durable idempotency, subject rate limiting, and automatic new-turn redirection remain roadmap work.

## Development

Requirements: Node.js 22 or later.

```sh
npm install
npm run dev
```

The initial PWA uses local mock transcription, agent response, and browser speech synthesis to exercise the interaction states. Browser synthesis is not the production TTS implementation. The Worker scaffold exposes mock API boundaries for contract development.

Set `VITE_BACKEND=worker` when serving the PWA and proxying `/api` to a separately running Worker to exercise the BFF contract. The default remains self-contained local mocks.

```sh
npm run typecheck
npm test
npm run build
```

Run the Worker separately when developing its routes:

```sh
cp apps/worker/.dev.vars.example apps/worker/.dev.vars
npm run dev --workspace @stts/worker
```

The committed Worker configuration uses Access mode and fails closed until JWT verification is configured. Local authentication bypass must remain in the ignored `.dev.vars` file.

Production Worker configuration requires `ACCESS_ISSUER` and `ACCESS_AUD`. Add `SPEECH_API_KEY`, `HERMES_ACCESS_CLIENT_ID`, `HERMES_ACCESS_CLIENT_SECRET`, and a random 32-byte base64url `CONVERSATION_STATE_KEY` with `wrangler secret put`; never place values in `wrangler.jsonc` or `.dev.vars.example`.
