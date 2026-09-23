# Voice interface system

One visual system across the PWA, iOS, watchOS, and the CarPlay scene.

The reference is the Grok app's discipline: true-black field, enormous negative space, almost no chrome, one input surface at the bottom, content presented as plain text rather than boxed cards. We borrow the discipline, not the branding — no Grok wordmark, logo, or trade dress.

## The one idea

**The interface is monochrome until the microphone is live.**

Every surface is black, white, and grey. Colour appears in exactly two situations: amber while recording or listening, red for failure. That makes colour a *state* rather than decoration, which is the right trade for a voice-first product — the only thing worth signalling is whether the app is hearing you.

Everything below follows from that rule. Spend the boldness here and keep the rest quiet.

## Colour

| Token | Value | Role |
|---|---|---|
| `void` | `#000000` | App background. True black, not a tinted near-black. |
| `surface` | `#141417` | Assistant bubble, list row |
| `surfaceRaised` | `#1C1C21` | Composer, text fields, selected row |
| `hairline` | `#33333A` | Decorative separators and grouping |
| `outline` | `#5F5F68` | Meaningful boundaries and control edges — 3.3:1 on `void` |
| `ink` | `#F4F4F6` | Primary text — 19:1 on `void` |
| `inkMuted` | `#8B8B94` | Metadata, secondary text — 6.2:1 on `void` |
| `inkFaint` | `#5A5A63` | Disabled text |
| `live` | `#F0A868` | Recording and listening only — 10.5:1 on `void` |
| `alert` | `#FF6B5E` | Failure and destructive actions — 7.5:1 on `void` |

Rules:

- Never use `live` or `alert` decoratively. If nothing is recording and nothing failed, the screen has no colour.
- `alert` also carries warnings that need attention — a truncated summary, an insecure server URL. Warnings are states, not failures, but they must not be silent.
- `hairline` is for grouping; anything a person must perceive as a boundary uses `outline`. That includes the composer and the live bar, which are control edges and need non-text contrast.
- Text never sits on `surfaceRaised` below `inkMuted`. Placeholder text is real text, not disabled text.
- The app icon is the one deliberate exception to the `live` rule: an installed icon represents the act of listening, so it may carry the amber waveform.

## Type

One family per platform. No display/body pairing — the scale and weight do the work.

| Platform | Family | Why |
|---|---|---|
| iOS, watchOS | System (SF Pro) | Dynamic Type, accessibility, and platform correctness |
| Web | System UI stack | The PWA's CSP is `default-src 'self'`, so external webfonts are blocked; a self-hosted face is a follow-up |

Scale:

| Role | iOS | watchOS | Web | Treatment |
|---|---|---|---|---|
| Display | 34 | 24 | `clamp(28px, 7vw, 40px)` | `.heavy`, tracking −0.4. The live state and empty-state only. |
| Title | 22 | 17 | 20 | `.semibold`, tracking −0.2 |
| Body | 17 | 15 | 16 | `.regular` |
| Caption | 13 | 12 | 13 | `.regular`, `inkMuted` |
| Micro | 11 | 11 | 11 | `.medium`, `inkFaint`, only inside dense rows |

Durations, timestamps, and counters use **tabular figures**, never a monospace family:

- iOS/watchOS: `.monospacedDigit()`
- Web: `font-variant-numeric: tabular-nums`

## Layout

### Phone — Voice

```text
┌───────────────────────────────┐
│ Ready                         │  status line, inkMuted
│                               │
│  [you] book a service friday  │  user bubble, right, surfaceRaised
│                               │
│  Friday 3pm works.            │  coordinator, left, surface
│  ▸ Cloud Engineer             │  specialist, caption, inkMuted
│                               │
│  ┌─────────────────────┬───┐  │
│  │ Message             │mic│  │  composer pill
│  └─────────────────────┴───┘  │
│   Voice    Meetings   Sett.   │  bottom bar, no icons-only
└───────────────────────────────┘
```

Empty state: no bubbles. A single display-weight state word centred, with the composer beneath. Nothing else.

Recording state: the composer is replaced by a full-width live bar — amber dot, elapsed time in tabular figures, and a stop control. This is the only moment the screen has colour and the only non-user motion.

### Phone — Meetings

A separate area, deliberately unlike Voice. Voice is an open canvas; Meetings is a titled library.

```text
┌───────────────────────────────┐
│ Meetings                      │  large title
│                               │
│  ── Today ────────────────    │  date grouping, hairline
│  Standup               12:04  │
│  Discussed the migration…     │  one-line opening, inkMuted
│                               │
│  ── Yesterday ──────────────  │
│  Supplier call         47:21  │
│  ⚠ Interrupted                │  state, alert tint
│                               │
│  ┌─────────────────────────┐  │
│  │      Record meeting     │  │  sticky primary action
│  └─────────────────────────┘  │
└───────────────────────────────┘
```

- Rows are not cards: a hairline separates them, and the row hugs its content.
- Transcript view is a timestamped reading surface: `mm:ss` in tabular figures in a narrow leading column, text in the body column.
- `Summarize` is a single action at the top of a transcript, never a floating button.
- `Interrupted` is a state label in `alert`, never a sentence.

### Watch

```text
┌─────────────┐
│   Ready     │   state, display weight
│             │
│    ◉        │   mic, 72pt tap target, amber while live
│             │
│   0:07      │   elapsed, tabular
└─────────────┘
```

Meeting control is a second page: start, stop, marker. No transcript on the watch.

### CarPlay

Voice only. The prompt text is the entire interface, and the CarPlay framework draws it.

## Motion

- Motion answers an action or reports a live state. Nothing else.
- A single pulse on the live indicator while recording. One transition when the composer swaps for the live bar.
- Respect Reduce Motion: the pulse becomes a static amber dot, the swap becomes a cut.
- No entrance animations on lists or bubbles.

## Copy

Labels, states, units, data, actions, and short errors. Nothing else — no greetings, no helper text, no explanations, no onboarding. An empty area says what it is (`No meetings`) and offers the action that fills it.

Errors name what failed and what to do, in the interface's voice: `Transcription unavailable`, `Retry`. They never apologise and never explain the architecture.

## Per-client notes

- **PWA** — single dark theme; there is no light mode. The existing phase model maps directly onto the state colours.
- **iOS/watchOS** — one dark appearance; do not implement a light variant. `Color` values live in one file per target so the tokens are not scattered.
- **CarPlay** — follows the same type and state rules within CarPlay's own templates.

## Applying this

The tokens are normative. When a platform cannot express a token directly (watch materials, CarPlay templates), match the intent — contrast and hierarchy — rather than the literal value.

Contrast was verified for the pairs that actually occur, not just against `void`:

| Pair | Ratio |
|---|---|
| `ink` on `void` | 19.1 |
| `ink` on `surfaceRaised` | 15.4 |
| `live` on `void` | 10.5 |
| `alert` on `void` | 7.5 |
| `alert` on `surfaceRaised` | 6.1 |
| `inkMuted` on `void` | 6.2 |
| `inkMuted` on `surface` | 5.4 |
| `inkMuted` on `surfaceRaised` | 5.0 |
| `outline` on `void` | 3.3 |

`inkFaint` sits at 2.5:1 on `surfaceRaised` and is for disabled text only.
