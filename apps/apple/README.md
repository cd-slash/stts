# STTS Apple clients

Native Apple clients for STTS: an iOS app (`STTSiOS`) for voice notes and long-form
meeting capture, a watchOS app (`STTSWatch`) for voice notes and meeting control,
and a shared platform-agnostic Swift package (`STTSCore`).

The clients call only the existing Worker HTTP routes. No backend changes are
required to build and run them, with one exception noted under
[Required Worker change](#required-worker-change).

## Layout

```text
apps/apple/
  project.yml            XcodeGen spec (STTSiOS + STTSWatch targets)
  STTSCore/              Pure-Foundation Swift package (no Apple frameworks)
    Sources/STTSCore/    Codable protocol models, STTSClient, segmenters,
                         TranscriptAssembler, MeetingStore
    Tests/STTSCoreTests/ XCTest coverage
  STTSiOS/               iOS app: credential setup, voice notes, meetings,
                         transcript browser, WatchConnectivity bridge
  STTSWatch/             watchOS app: voice notes, meeting control, reply playback
```

## Prerequisites

- macOS with Xcode 16 or newer (Swift 6 toolchain).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
- An Apple ID / development team for code signing (device builds).
- For WatchConnectivity: an Apple Watch paired with the iPhone.

## Generate and run

```bash
cd apps/apple
xcodegen generate          # produces STTS.xcodeproj (git-ignored)
open STTS.xcodeproj
```

1. Select the **STTSiOS** scheme.
2. In *Signing & Capabilities*, set your development team for both **STTSiOS**
   and **STTSWatch** (the watch app embeds into the iOS app; bundle IDs are
   `com.stts.mobile` and `com.stts.mobile.watchkitapp`).
3. Run on an iPhone (simulator has no microphone recording; use a device for
   capture). The embedded watch app installs with the phone app.

### STTSCore tests

The package is platform-agnostic and testable without Xcode:

```bash
cd apps/apple/STTSCore
swift test
```

## Configuration

All configuration lives in the **Settings** tab of the iOS app.

- **Server URL**: the Worker origin, e.g. `https://<your-worker>.workers.dev`.
  Stored in `UserDefaults` (not a secret). `http://` is allowed only so local
  development Workers with `AUTH_MODE=local` work without credentials.
- **Access credentials**: a Cloudflare Access **service token** (client ID and
  secret) scoped to the Access application protecting the Worker. The pair is
  sent as `CF-Access-Client-Id` / `CF-Access-Client-Secret` request headers;
  Access validates them at the edge and injects the `cf-access-jwt-assertion`
  header the Worker verifies.

### Credential model

- Stored in the iOS Keychain as one generic-password item
  (`com.stts.mobile.credentials` / `cloudflare-access`) with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- Never written to `UserDefaults`, never logged, never displayed back — the UI
  only shows whether a credential exists (`Saved` / `None`).
- Removed with the **Remove** action on the credential screen.
- The watch app holds no credential and performs no networking.

## Meeting capture

- `AVAudioSession` category `.record` during capture (`.playback` for reply
  playback); `UIBackgroundModes: audio` in `Info.plist` lets a meeting keep
  recording while the app is backgrounded. The background-audio mode is
  required for long-form capture; iOS suspends apps without it.
- Audio is AAC in an m4a container (mono, 64 kbit/s), written to a temp
  directory as 45-second segments (`MeetingSegmenter`).
- Each closed segment is uploaded to `POST /api/transcriptions` with up to 3
  attempts and linear backoff. A segment file is deleted **only after** a
  successful transcription; permanently failed segments are marked in the
  transcript and their audio is dropped when the meeting finalizes.
- After stop, outstanding uploads settle, the transcript is assembled with
  `TranscriptAssembler`, and the meeting is persisted **as text only** via the
  JSON-file `MeetingStore` (Application Support/Meetings). The segment
  directory is then deleted — meeting audio never persists.
- Audio-session interruptions (phone calls) pause capture cleanly; the UI
  offers **Resume** (appends a new segment; gaps are handled by the assembler)
  or **Stop**.

## Summarize

The transcript browser has an explicit **Summarize** action that submits the
assembled transcript text to Hermes as a single turn (default profile) and
plays the reply. Submissions are capped at 40,000 characters; longer
transcripts are truncated to the most recent 40,000 characters.

## Watch app

Respects watchOS platform limits:

- **Foreground-only recording**, capped at 60 seconds per voice note; on stop
  the file is handed to the phone with `WCSession.transferFile` (queued while
  backgrounded). The watch does not transcribe, submit, or hold credentials.
- **No long-form recording.** Meeting start/stop/marker are remote controls
  for the phone-side recorder; elapsed time is derived locally from the
  meeting start pushed in the application context.
- **Reply playback**: the phone synthesizes the reply and relays the audio
  file to the watch, which plays it in the foreground.

## Worker routes used

| Route | Body |
|---|---|
| `GET /api/health` | — |
| `POST /api/conversations` | `{ operationId, profile }` |
| `POST /api/transcriptions` | multipart: `operationId`, `audio` (filename `voice-note.m4a`, type `audio/mp4`) |
| `POST /api/conversations/:id/turns` | `{ operationId, input: { kind: "text", text }, profileOverride: null, clientContext: { timezone, locale } }` |
| `POST /api/conversations/:id/inputs/:requestId/answer` | `{ operationId, answer: { kind, text?, confirmationNonce? } }` |
| `POST /api/conversations/:id/runs/:runId/interrupt` | `{ operationId, reason }` |
| `POST /api/speech/synthesis` | `{ operationId, conversationId, responseId, voice: "default", format: "audio/mpeg" }` |

The conversation ID rotates on every turn/answer/interrupt response; the
client always stores the returned handle (as the web client does). A stale
handle surfaces as `400 INVALID_REQUEST`; the client recreates the
conversation and retries the turn once with the same operation ID.

## Turn surface

Turns carry a bounded `surface` value that tells the adapter what produced the
turn:

| Surface | Used by |
| --- | --- |
| `voice-live` | voice note transcribed on the phone or watch |
| `text` | typed input |
| `meeting-transcript` | the Summarize action |

Meeting segments also send ordering metadata (`recordingId`, `segmentIndex`,
`segmentStartedAtMs`, `segmentDurationMs`) on `POST /api/transcriptions`. The
Worker validates and echoes it, and the meeting coordinator treats a mismatched
echo as a failed segment rather than assembling the wrong text.

## Known limitations

- **Unverified builds.** This code was written without a Swift toolchain; it
  has not been compiled or run. `xcodegen generate` plus a build may surface
  mechanical fixes (imports, minor signatures). `swift test` in `STTSCore/`
  is the fastest first check on a Mac.
- **Single conversation.** Like the web client, one conversation handle is
  retained at a time; there is no thread list.
- **No streaming.** Turns use the Worker's request/response endpoints
  (`events` array returned per turn); there is no WebSocket or event-cursor
  replay in the current Worker, so the client has none either.
- **No CarPlay**, widgets, or Live Activities.
- **Watch pausing.** The watch can start/stop/mark a meeting but cannot pause
  or resume; those controls are phone-only.
- **Watch reply audio** requires the watch app to be foreground when the
  transfer arrives; `transferFile` delivers in background and playback starts
  on next launch of the watch UI.
- **Segment gaps.** Pausing capture produces a time gap between segments;
  ordering is preserved by `startedAtMs`, and the gap is visible as skipped
  clock time in the transcript.
