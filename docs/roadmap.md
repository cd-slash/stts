# Roadmap

## Delivery principles

- Prove one complete voice-note round trip before broadening scope.
- Keep the client dependent only on the normalized protocol.
- Use mocks and contract fixtures before connecting production services.
- Preserve text when speech fails.
- Add persistence only when an observed requirement needs it.

## Phase 0: design and contracts

Deliverables:

- Product requirements and non-goals.
- Accepted Worker BFF architecture decision.
- Communication and safety state machines.
- Versioned normalized protocol.
- Security and deployment baseline.

Exit criteria:

- The first vertical slice has testable acceptance criteria.
- Unverified Hermes details are isolated behind the adapter.
- PWA and future iOS clients can share the proposed contract.

## Phase 1: local vertical slice

Deliverables:

- TypeScript monorepo with PWA, Worker, shared protocol package, and adapter packages.
- Runtime-validated command/event schemas.
- Mock speech and mock agent adapters.
- Mobile recording, transcript, final response, and playback flow.
- State-machine and adapter contract tests.

Exit criteria:

- A browser test completes record → transcribe → respond → synthesize → replay.
- Failure and retry can be demonstrated independently at each stage.
- No client code imports Hermes-specific types.

## Phase 2: real speech integration

Deliverables:

- Verified `speech.cdslash.com` STT and TTS contracts.
- Codec normalization and payload limits.
- Ephemeral audio handling.
- Speech latency and error instrumentation.

Current progress: the upstream request/response contract, bearer isolation, bounded transcription parsing, sanitized failures, and safe synthesis response headers are implemented and covered by adapter tests. Completed Hermes text receives an expiring, owner- and conversation-bound encrypted response ID; the PWA exchanges it for Kokoro audio only after completion and keeps a bounded in-memory audio cache for replay. Speech latency instrumentation and post-refresh audio regeneration remain outstanding.

Exit criteria:

- Supported mobile browsers complete STT and TTS with production-like authentication.
- TTS can be regenerated from final response text.
- Audio and transcript content do not appear in logs.

## Phase 3: Hermes integration

Deliverables:

- Captured deployed Hermes schema/version fixture.
- Hermes adapter for submission, stream normalization, replay, interruption, clarification, and approval.
- Chief of Staff default and verified profile mappings.
- Compatibility tests for gateway upgrades.

Current progress: the exact RPC methods, event shapes, replay semantics, and deployed source commit are documented. A tested normalizer maps core message, tool, specialist, clarification, approval, and error events while excluding internal reasoning. The machine authentication path is proven, and the Worker implements authenticated transport, owner-bound opaque conversation state, first-turn creation, subsequent resume, prompt submission, terminal event collection, clarification responses, nonce-gated one-time approvals, and interruption. The PWA requires read-back before rendering its approval action and exposes stop-work controls after a durable session exists. Resumable browser event streaming and automatic new-turn redirection remain outstanding.

Exit criteria:

- A real Chief of Staff conversation survives page refresh and stream reconnection.
- Specialist activity is visible but separated from the coordinator response.
- Interruption and input requests behave deterministically.

## Phase 4: secured PWA deployment

Deliverables:

- Cloudflare Access-protected application and Worker routes.
- Production secret bindings and origin authentication.
- PWA manifest, service worker, installability, and update behavior.
- Rate limits, observability, security checks, and operational runbook.

Exit criteria:

- The owner completes the full flow from an installed mobile PWA.
- Unauthorized HTTP and WebSocket requests fail closed.
- Browser artifacts and logs pass credential/content inspection.

## Phase 5: product hardening

Deliverables:

- Accessibility and mobile-browser matrix.
- Network-loss, duplicate-operation, reconnect, and long-turn tests.
- Configurable voice and autoplay preferences.
- Usability validation for approval read-back and interruption.

Exit criteria:

- Defined latency and reliability targets are met over representative use.
- No known path can voice-approve an action without explicit confirmation.
- Text-only operation remains complete and accessible.

## Phase 6: native iOS, watchOS, and CarPlay

Deliverables:

- Current Apple entitlement/category eligibility assessment.
- Swift client spike using the same BFF protocol.
- watchOS voice notes and meeting control, with audio relayed to the phone.
- iOS meeting capture, segmented upload, on-device transcript, and explicit summary.
- CarPlay-safe command, response, clarification, and confirmation subset.
- Driver-distraction and failure-mode review.

Current progress: an `STTSCore` package, an iOS companion target, and a watchOS target are implemented with an owner-provisioned Access service token in the Keychain, WatchConnectivity audio relay, segmented meeting capture, on-device transcript assembly and browsing, crash-safe draft persistence, and lossless chunked summarization. The Worker validates and echoes segment ordering metadata and passes the requested turn surface to Hermes, with tests and typechecking in place. A minimal CarPlay voice scene targets Apple's iOS 26.4 **voice-based conversational app** category; it is implemented but the entitlement is not yet granted or wired, so it stays dormant. The Swift sources have not been compiled or run on device because this environment has no Swift toolchain or Xcode.

Exit criteria:

- Apple platform eligibility is confirmed before full implementation.
- Native client reconnect and audio session behavior are proven.
- CarPlay interaction does not require reading or manipulating the full transcript.

## Deferred scaling triggers

Consider Durable Objects or application-owned persistence only when one of these becomes real:

- simultaneous clients need ordered live fan-out;
- users share conversations;
- Hermes cannot provide required replay/history guarantees;
- application-level retention must differ from Hermes;
- multiple agent stacks participate in one conversation concurrently.

## Immediate implementation backlog

1. Confirm monorepo tools and scaffold packages.
2. Define shared schemas and state-machine tests.
3. Implement mock adapters and a complete local round trip.
4. Verify the speech service contract.
5. Verify the live Hermes RPC schema and write adapter fixtures.
6. Integrate upstreams behind configuration flags.
7. Deploy a protected preview and run the security checklist.
