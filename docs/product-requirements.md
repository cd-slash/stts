# Product requirements

## Product statement

STTS is a voice-first, asynchronous conversation client for coordinator-led AI agents. It combines the interaction model of voice notes with a durable text transcript and supports both speech-to-text and text-to-speech.

The first release is a single-owner, installable mobile PWA. A native iOS and CarPlay client follows after the backend contract and interaction model are proven.

## Goals

- Make speaking and listening the primary interaction path.
- Preserve a readable, durable transcript of both sides of the conversation.
- Let a coordinator agent route work to specialists without making users manage agent topology.
- Show specialist activity without fragmenting the coordinator's conversational voice.
- Keep clients independent of any one agent stack.
- Protect agent and speech service credentials from browser clients.
- Provide a backend contract suitable for a later native iOS and CarPlay client.

## Non-goals for the first milestone

- Full-duplex, low-latency telephone-style conversation.
- Continuous wake-word listening.
- Multi-user organizations or shared threads.
- Offline transcription or synthesis.
- Permanent storage of source or synthesized audio.
- A native iOS or CarPlay binary.
- Replacing Hermes session storage, coordination, or tool execution.
- Supporting every possible Hermes dashboard operation.

## Primary user

The initial user is the single owner of the deployment. They use a phone-oriented browser, authenticate through Cloudflare Access, and converse mainly by recording discrete voice notes.

## Core experience

### Voice-note turn

1. The user taps record.
2. The app captures audio and shows recording state and duration.
3. The user stops and submits, or discards the recording.
4. The app uploads the note for transcription.
5. The recognized text appears as the user's message and can be corrected before agent submission when transcription confidence or user preference requires it.
6. The coordinator processes the turn and may invoke specialists or tools.
7. Text events progressively update the transcript.
8. Once the coordinator's response is complete, the app synthesizes it as one replayable voice note.
9. The app plays the completed note automatically when user settings and browser playback policy permit.

Text may stream before synthesis completes, but speech begins only when the complete response voice note is available. This avoids sentence-boundary artifacts and makes replay deterministic.

### Wrist voice note

1. The user records a short voice note on Apple Watch.
2. The watch hands the audio to the paired iPhone; it holds no credential and performs no network request.
3. The phone transcribes, submits the turn, and returns the completed response.
4. The reply is playable on the watch.

### Meeting recording

1. The user starts a meeting recording on the phone, or from the watch as a remote control.
2. Audio is captured as bounded segments and each closed segment is uploaded for transcription.
3. A segment's audio is discarded once it has been transcribed. A failed segment is retried a bounded number of times and then recorded as a gap rather than merged across.
4. The transcript is assembled with timestamps and retained on device, where it can be browsed.
5. A **Summarize** action explicitly submits the transcript to the coordinator as one meeting turn and plays the reply.

Meetings are deliberately not auto-submitted: a long transcript is an artifact the user reviews, not a message that silently starts agent work. Meetings are captured on the phone because watchOS restricts sustained background recording and watch audio quality is unsuitable for hour-long capture.

### Coordinator and specialists

Hermes **Chief of Staff** is the default coordinator. It may route to:

- Car Mechanic
- Cloud Engineer
- Legal Assistant
- Personal Assistant
- Property Agent
- Trainer
- Travel Planner

The transcript presents the coordinator as the main conversational voice. Specialist work is labeled and expandable. Users may explicitly select a profile for a turn, but automatic routing remains the default.

### Approvals and clarification

Agent work may pause for clarification or approval. The app presents the request as a first-class conversation event.

Voice approval uses two steps:

1. Capture and interpret the user's proposed answer.
2. Read back the consequential action and require explicit confirmation.

Ambiguous, negative, expired, or interrupted confirmation does not approve the action. High-impact approvals must remain available as explicit on-screen controls.

### Interruption

If the user begins another turn while speech is playing, playback stops immediately. If the previous agent run is still active, the app requests interruption before submitting the redirecting turn. The UI must distinguish “playback stopped” from “agent work cancelled.”

## Functional requirements

### Conversation

- Create, resume, and display a conversation.
- Record, preview, submit, retry, and discard a voice note.
- Submit typed text as an accessibility and recovery path.
- Render user, coordinator, specialist, tool, approval, clarification, and error events.
- Replay a synthesized coordinator response.
- Stop playback independently of agent execution.
- Interrupt active agent work.
- Retry failed transcription, submission, and synthesis without duplicating successful operations.

### Speech

- Accept browser-supported audio and normalize it server-side when required.
- Enforce duration and payload limits before forwarding audio.
- Return transcription text and language when available.
- Synthesize only finalized coordinator-facing response text.
- Treat audio as ephemeral and allow regeneration from durable text.

### Agent integration

- Default to Chief of Staff.
- Support explicit profile override.
- Preserve upstream conversation/session identity behind an opaque application conversation ID.
- Normalize streaming output and control requests.
- Recover from a dropped connection by resuming from an event cursor or reconstructing from authoritative history.

## Experience requirements

- Mobile-first and installable.
- Primary controls must be operable one-handed.
- Recording, upload, thinking, synthesis, playback, paused, and error states must be unambiguous.
- The transcript must remain usable without audio.
- Keyboard operation, visible focus, screen-reader names, captions/transcripts, and reduced motion are required.
- The interface should contain concise operational labels and states, not explanatory prose.

## Reliability requirements

- Client-generated operation IDs make retries idempotent.
- A page refresh can recover conversation state from Hermes-backed history.
- Speech failure does not erase or invalidate completed text.
- TTS failure leaves the final text available with a retry action.
- Agent disconnection exposes a recoverable state rather than inventing completion.

## Success criteria for the vertical slice

- A complete spoken round trip succeeds on a supported mobile browser.
- No upstream service credential appears in browser source, storage, requests, or logs.
- Duplicate submit/retry actions do not create duplicate user turns.
- Final response text can regenerate equivalent playback after reload.
- The client renders the same normalized events without knowledge of Hermes JSON-RPC method names.
- Interruption and approval behavior pass their state-machine tests.

## Open product decisions

- Maximum voice-note duration and file size.
- Whether transcript correction is always offered or only on low confidence.
- Default autoplay policy and selected TTS voice.
- Retention period for application operational logs.
- Exact set of actions requiring two-step confirmation.
