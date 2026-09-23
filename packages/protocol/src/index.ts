import { z } from "zod";

const opaqueId = z.string().min(1).max(200);
const conversationId = z.string().min(1).max(1024);
const responseId = z.string().min(1).max(100_000);
const timestamp = z.iso.datetime({ offset: true });

export const protocolVersion = z.literal("1");

export const eventType = z.enum([
  "conversation.snapshot",
  "connection.resumed",
  "turn.transcribed",
  "turn.accepted",
  "turn.rejected",
  "response.started",
  "response.delta",
  "response.completed",
  "response.failed",
  "activity.started",
  "activity.updated",
  "activity.completed",
  "activity.failed",
  "input.requested",
  "input.resolved",
  "input.expired",
  "run.interrupting",
  "run.interrupted",
  "run.interrupt_failed",
  "speech.synthesis.started",
  "speech.synthesis.ready",
  "speech.synthesis.failed",
  "error.occurred"
]);

export type EventType = z.infer<typeof eventType>;

export const turnSurface = z.enum(["voice-live", "text", "meeting-transcript"]);

export type TurnSurface = z.infer<typeof turnSurface>;

const recordingId = z
  .string()
  .min(1)
  .max(100)
  .regex(/^[A-Za-z0-9._:-]+$/);

// Client-supplied ordering metadata for one meeting audio segment. Timing and
// recording identity are only meaningful together, so partial claims are
// rejected rather than silently dropped downstream.
export const transcriptionSegment = z
  .object({
    recordingId: recordingId.optional(),
    segmentIndex: z.coerce.number().int().min(0).max(9_999).optional(),
    segmentStartedAtMs: z.coerce.number().int().min(0).max(86_400_000).optional(),
    segmentDurationMs: z.coerce.number().int().min(0).max(3_600_000).optional()
  })
  .superRefine((value, context) => {
    const hasSegment = value.recordingId !== undefined || value.segmentIndex !== undefined;
    const hasTiming =
      value.segmentStartedAtMs !== undefined || value.segmentDurationMs !== undefined;
    if (hasSegment && (value.recordingId === undefined || value.segmentIndex === undefined)) {
      context.addIssue({
        code: "custom",
        message: "recordingId and segmentIndex are required together"
      });
    }
    if (hasTiming && (value.segmentStartedAtMs === undefined || value.segmentDurationMs === undefined)) {
      context.addIssue({
        code: "custom",
        message: "segmentStartedAtMs and segmentDurationMs are required together"
      });
    }
    if (hasTiming && !hasSegment) {
      context.addIssue({
        code: "custom",
        message: "segment timing requires a recording segment"
      });
    }
  });

export type TranscriptionSegment = z.infer<typeof transcriptionSegment>;

export const eventEnvelope = z.object({
  version: protocolVersion,
  eventId: opaqueId,
  conversationId,
  cursor: opaqueId,
  occurredAt: timestamp,
  correlationId: opaqueId,
  type: eventType,
  critical: z.boolean(),
  data: z.record(z.string(), z.unknown())
});

export type EventEnvelope = z.infer<typeof eventEnvelope>;

export const createConversationCommand = z.object({
  operationId: opaqueId,
  profile: z.string().min(1).max(100).default("chief-of-staff")
});

// A meeting transcript is a single long document rather than a spoken note, so
// it is allowed a larger bounded payload than an interactive turn while still
// keeping an explicit ceiling on what reaches the agent stack.
const maximumTurnText = (surface: TurnSurface): number =>
  surface === "meeting-transcript" ? 100_000 : 50_000;

export const submitTurnCommand = z
  .object({
    operationId: opaqueId,
    conversationId,
    input: z.object({
      kind: z.literal("text"),
      text: z.string().trim().min(1).max(100_000)
    }),
    profileOverride: z.string().min(1).max(100).nullable().default(null),
    surface: turnSurface.default("voice-live"),
    clientContext: z.object({
      timezone: z.string().min(1).max(100),
      locale: z.string().min(2).max(35)
    })
  })
  .superRefine((value, context) => {
    const limit = maximumTurnText(value.surface);
    if (value.input.text.length > limit) {
      context.addIssue({
        code: "custom",
        path: ["input", "text"],
        message: `text exceeds ${limit} characters for surface ${value.surface}`
      });
    }
  });

export const answerInputCommand = z.object({
  operationId: opaqueId,
  conversationId,
  requestId: opaqueId,
  answer: z.object({
    kind: z.enum(["text", "approve", "deny"]),
    text: z.string().trim().max(50_000).optional(),
    confirmationNonce: z.string().min(1).optional()
  })
});

export const interruptRunCommand = z.object({
  operationId: opaqueId,
  conversationId,
  runId: opaqueId,
  reason: z.enum(["user_cancelled", "user_redirect"])
});

export const synthesizeResponseCommand = z.object({
  operationId: opaqueId,
  conversationId,
  responseId,
  voice: z.string().min(1).max(100).default("default"),
  format: z.enum(["audio/mpeg", "audio/wav", "audio/ogg"])
});

export type CreateConversationCommand = z.infer<typeof createConversationCommand>;
export type SubmitTurnCommand = z.infer<typeof submitTurnCommand>;
export type AnswerInputCommand = z.infer<typeof answerInputCommand>;
export type InterruptRunCommand = z.infer<typeof interruptRunCommand>;
export type SynthesizeResponseCommand = z.infer<typeof synthesizeResponseCommand>;
