# CarPlay

STTS targets the CarPlay **voice-based conversational app** category: a voice-first assistant that answers questions and performs actions without showing text-heavy or image-heavy surfaces.

## Status

| Item | State |
|---|---|
| Category eligibility | Fits: voice-first assistant, primary modality is voice |
| Entitlement requested from Apple | Not yet |
| Entitlement wired into the target | No — deliberately, see below |
| CarPlay scene implemented | Yes, minimal: voice note in, spoken reply out |
| Verified on device | No |

## The entitlement

```text
com.apple.developer.carplay-voice-based-conversation
```

The declaration lives in `apps/apple/STTSiOS/STTSiOS.entitlements` and is **not** wired into the target. Apple grants CarPlay entitlements per app, and an unapproved value fails device signing, so wiring it early would break every build.

Request it at <https://developer.apple.com/contact/carplay/>. Once granted, add one line to the `STTSiOS` settings in `apps/apple/project.yml`:

```yaml
CODE_SIGN_ENTITLEMENTS: STTSiOS/STTSiOS.entitlements
```

## What CarPlay permits

Verified against Apple's CarPlay developer material for the voice-based conversational category:

- Apps **launch straight into voice interaction**.
- **Recording is permitted** for this category — and for CarPlay navigation apps — but only in conjunction with the Voice Control template. This is the one place third-party CarPlay apps may capture audio.
- Surfaces must **avoid text-heavy and image-heavy displays**; query responses should be spoken.
- **No custom wake word.** The driver opens the app from the car screen; the app cannot be summoned invisibly.
- Apps must use the CarPlay framework's templates.
- Apps may **not** control vehicle systems or unrelated iPhone functions.
- Audio feedback should signal conversation state, so the experience is usable by ear. The audio session uses `.playAndRecord` with the default mode and mixing disabled.

## Scope in this app

CarPlay is intentionally the narrowest surface of the three clients:

| Capability | CarPlay |
|---|---|
| Voice note | Yes |
| Spoken coordinator reply | Yes |
| Replay the last reply | Yes |
| Stop work / stop playback | Yes |
| Transcript browsing | No |
| Meeting capture and control | No |
| Approvals and clarifications | No — surfaced as unavailable while driving |

Approvals are excluded because a consequential action must not be confirmed by a driver under time pressure. The scene reports the conversation as unavailable if one is pending.

`CarPlayVoiceSession` reuses the existing recorder (`VoiceNoteViewModel`) and conversation controller rather than duplicating capture logic, so the CarPlay-specific surface stays small.

## Unverified

- The CarPlay template calls in `CarPlayVoiceSession` and `CarPlaySceneDelegate` could not be compiled or checked: this repository was developed without a Swift toolchain or Xcode. Confirm `CPVoiceControlTemplate`, `CPVoiceControlState`, and `activateVoiceControlState(withIdentifier:)` against the shipping SDK, and confirm the `CPTemplateApplicationSceneSessionRoleApplication` scene manifest.
- The entitlement identifier comes from reporting on the CarPlay Developer Guide; confirm it against the current guide before requesting.

## Zero-entitlement alternative

Apple states that Live Activities and widgets from any app appear in CarPlay automatically, with no entitlement and no CarPlay-specific code. A recording Live Activity would therefore show meeting or voice-note state in the car today, independently of this work.
