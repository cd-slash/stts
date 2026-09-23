# ADR 0002: Native iOS and watchOS clients

- Status: Accepted
- Date: 2026-09-23

## Context

The PWA covers voice notes on a phone browser. Two requirements cannot be met there:

- **Voice notes from the wrist.** watchOS has no browser, so an installable PWA cannot reach it.
- **Meeting recordings.** Long-form capture needs sustained background audio, large and reliable local buffering, and segmented upload. A mobile browser tab is suspended in the background and cannot be trusted to hold an hour of audio.

The Worker already exposes a normalized protocol and verifies Cloudflare Access identity, so native clients can reuse the same contract rather than introducing a second backend.

## Decision

Build two native clients that share one Swift package:

1. **A watchOS app** that records short voice notes and controls meeting capture.
2. **An iOS companion app** that owns long-form meeting recording, transcript assembly, playback, and the agent conversation.

Specific boundaries:

- **The watch never holds a credential and never calls the Worker.** Watch audio is transferred to the phone with WatchConnectivity and uploaded by the phone, which already holds an authenticated session. This keeps a bearer credential off a device that is easy to lose and hard to re-provision.
- **The phone owns meeting capture.** It records segmented audio, uploads each segment, and assembles the transcript locally.
- **Meeting transcripts are retained on device.** Raw audio stays ephemeral: a segment is deleted once it has been transcribed successfully. The transcript is the durable artifact.
- **Native authentication uses an owner-provisioned Cloudflare Access service token** stored in the iOS Keychain and sent as `CF-Access-Client-Id` / `CF-Access-Client-Secret`. The Worker already maps such a token to the subject `service:<common_name>`.
- **Existing Worker routes are reused.** The only protocol additions are a bounded `surface` value on turn submission and optional segment ordering metadata on transcription.

## Consequences

### Positive

- Both requirements are achievable without weakening the credential boundary.
- Native and web clients share one protocol and one agent integration.
- Long meetings get phone-quality audio and battery characteristics.
- No server-side storage is introduced; transcripts remain a client artifact.

### Negative

- The watch depends on the phone being reachable for voice notes.
- A service token now lives on a device, so rotation and revocation become operational tasks.
- Two more platforms to keep aligned with protocol changes.

### Deferred

- Standalone watch voice notes with a device-bound credential.
- Server-side meeting transcript storage and search.
- Speaker diarization.
- CarPlay.

## Alternatives considered

- **Watch records meetings directly.** Rejected: watch microphones and battery are poor for hour-long capture, and watchOS restricts sustained background recording.
- **Interactive Access login from the native app.** Rejected for the first milestone: extracting the resulting `CF_Authorization` cookie into `URLSession` is fragile, whereas service tokens are the documented machine-client path and are already supported by the Worker.
- **Adding a storage service for transcripts.** Rejected for now: the requirement is satisfied on device, and the roadmap defers application-owned persistence until an observed need appears.
