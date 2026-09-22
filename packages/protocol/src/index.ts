import { z } from "zod";

const opaqueId = z.string().min(1).max(200);
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

export const eventEnvelope = z.object({
  version: protocolVersion,
  eventId: opaqueId,
  conversationId: opaqueId,
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

export const submitTurnCommand = z.object({
  operationId: opaqueId,
  conversationId: opaqueId,
  input: z.object({
    kind: z.literal("text"),
    text: z.string().trim().min(1).max(50_000)
  }),
  profileOverride: z.string().min(1).max(100).nullable().default(null),
  clientContext: z.object({
    timezone: z.string().min(1).max(100),
    locale: z.string().min(2).max(35)
  })
});

export const answerInputCommand = z.object({
  operationId: opaqueId,
  conversationId: opaqueId,
  requestId: opaqueId,
  answer: z.object({
    kind: z.enum(["text", "approve", "deny"]),
    text: z.string().trim().max(50_000).optional(),
    confirmationNonce: z.string().min(1).optional()
  })
});

export const interruptRunCommand = z.object({
  operationId: opaqueId,
  conversationId: opaqueId,
  runId: opaqueId,
  reason: z.enum(["user_cancelled", "user_redirect"])
});

export const synthesizeResponseCommand = z.object({
  operationId: opaqueId,
  conversationId: opaqueId,
  responseId: opaqueId,
  voice: z.string().min(1).max(100).default("default"),
  format: z.enum(["audio/mpeg", "audio/wav", "audio/ogg"])
});

export type CreateConversationCommand = z.infer<typeof createConversationCommand>;
export type SubmitTurnCommand = z.infer<typeof submitTurnCommand>;
export type AnswerInputCommand = z.infer<typeof answerInputCommand>;
export type InterruptRunCommand = z.infer<typeof interruptRunCommand>;
export type SynthesizeResponseCommand = z.infer<typeof synthesizeResponseCommand>;
