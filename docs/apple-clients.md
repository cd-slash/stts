# Apple clients

Native iOS and watchOS clients for STTS. See [ADR 0002](decisions/0002-native-clients.md) for why native clients exist and where the credential boundary sits.

## Targets

```text
apps/apple/
  project.yml        XcodeGen specification
  STTSCore/          shared, platform-agnostic Swift package
  STTSiOS/           iOS companion app
  STTSWatch/         watchOS app
```

`STTSCore` depends only on Foundation so it can be reasoned about and unit-tested without UIKit, WatchKit, or AVFoundation. Platform APIs stay in the app targets.

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
cd apps/apple && xcodegen generate && open STTS.xcodeproj
```

## Responsibility split

| Concern | watchOS | iOS | Worker |
|---|---|---|---|
| Voice note capture | yes (short, foreground) | yes | — |
| Voice note upload | no | yes | transcribe |
| Meeting capture | control only | yes | — |
| Meeting audio upload | no | yes (segmented) | transcribe per segment |
| Transcript assembly | no | yes | — |
| Transcript storage | no | on device | none |
| Agent conversation | no | yes | Hermes adapter |
| TTS playback | relayed from phone | yes | Kokoro |

The watch holds no credential and makes no Worker requests.

## Voice notes on the watch

1. The watch records in the foreground. watchOS restricts sustained background recording, so a voice note is deliberately short.
2. On stop, the watch hands the audio file to the phone with `WCSession.transferFile`.
3. The phone uploads it to `POST /api/transcriptions`, submits the transcript as a turn, and returns the completed response.
4. The phone relays the reply audio back to the watch for playback.

Transfer is asynchronous by design; the user-visible states are recorded, sent, waiting, and ready.

## Meeting capture on the phone

```text
record -> close segment -> upload segment -> delete audio -> assemble -> browse -> summarize
```

- Audio is captured as AAC/m4a and closed into bounded segments, targeting roughly 45 seconds.
- Each closed segment is uploaded to `POST /api/transcriptions` with its ordering metadata.
- A segment file is deleted only after its transcription succeeds. A failed segment is retried a bounded number of times and then recorded as a gap.
- The assembled transcript is persisted on device; audio is not.

### Segment metadata

`POST /api/transcriptions` accepts these optional multipart fields alongside `operationId` and `audio`:

| Field | Meaning |
|---|---|
| `recordingId` | Opaque meeting identifier, `[A-Za-z0-9._:-]`, max 100 |
| `segmentIndex` | Zero-based order within the recording |
| `segmentStartedAtMs` | Offset from recording start |
| `segmentDurationMs` | Segment length |

The Worker validates and echoes them, so the client can order results by index and place them on a timeline regardless of completion order. Partial claims are rejected: `recordingId` and `segmentIndex` must appear together, and timing requires a segment identity. The Worker never uses these values for storage or routing — they are ordering hints returned to the caller.

Existing limits still apply per segment: 20 MB of audio and a 21 MB declared `content-length` preflight.

### Assembly

Assembly sorts by `segmentIndex`, tolerates out-of-order completion, ignores duplicate deliveries of the same index, and preserves gaps as explicit markers rather than silently joining text across a missing segment. This is the behaviour covered by `STTSCore` unit tests.

## Meeting summary

Meetings are not submitted as a single turn. The transcript is browseable on device, and a **Summarize** action explicitly hands the assembled text to Hermes:

```json
{
  "operationId": "op",
  "input": { "kind": "text", "text": "<assembled transcript>" },
  "profileOverride": null,
  "surface": "meeting-transcript",
  "clientContext": { "timezone": "Europe/London", "locale": "en-GB" }
}
```

`surface` is a bounded enum: `voice-live`, `text`, or `meeting-transcript`.

Text limits are surface-dependent and enforced by the shared protocol and the Worker:

| Surface | Maximum text |
|---|---|
| `voice-live`, `text` | 50,000 characters |
| `meeting-transcript` | 100,000 characters |

A transcript longer than the meeting limit must be reduced client-side before submission. The iOS client applies a stricter 40,000-character cap and submits the tail of the transcript when a meeting exceeds it.

## Authentication

Native clients authenticate with a Cloudflare Access service token:

```text
CF-Access-Client-Id: <client id>
CF-Access-Client-Secret: <client secret>
```

The token is entered once by the owner and stored in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. It is never written to `UserDefaults`, source, logs, or the watch.

The Worker verifies the assertion and binds the session to `service:<common_name>`, so a native client has its own subject and conversation handles are not interchangeable with the web client's. Rotation is a two-step operation: create the replacement token, then remove the old one from the Access application policy.

A stolen device can be revoked by deleting the service token; because conversation handles are bound to the subject fingerprint, outstanding handles for the removed token stop validating.

## Background and interruption

- iOS declares `UIBackgroundModes: audio` so a meeting recording can continue while the app is not foregrounded. The active recording state is surfaced persistently.
- An interruption — an incoming call, or another app taking the audio session — stops capture cleanly. The app offers to resume by starting a new segment on the same recording rather than silently producing a hole.
- The watch app avoids long-running capture entirely, so it is not exposed to these constraints.

## Security rules

- Raw meeting audio is ephemeral and is deleted after successful transcription.
- Only the transcript is retained, on device, under the app's protected container.
- The Worker remains the only holder of upstream credentials.
- Transcripts are never logged by the client or the Worker.
- The client may call only the documented routes; it does not send arbitrary text for synthesis and does not construct upstream method names.

## Verification status

The Worker-side additions in this change are covered by automated tests and typechecking, and were exercised against the deployed Worker.

The Swift sources have **not** been compiled: the development environment for this change had no Swift toolchain or Xcode. Treat the Swift targets as reviewed source that still needs a first build, signing, and on-device run from a Mac.
