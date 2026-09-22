import type { EventEnvelope, EventType } from "@stts/protocol";

export interface HermesEvent {
  type: string;
  session_id?: string;
  seq?: number;
  payload?: unknown;
}

export interface HermesJsonRpcFrame {
  jsonrpc?: string;
  id?: string | number | null;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { code?: number; message?: string; data?: unknown };
}

export interface HermesNormalizationContext {
  conversationId: string;
  correlationId: string;
  fallbackCursor: string;
  occurredAt?: string;
}

function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function text(payload: Record<string, unknown>, fallback = "") {
  return typeof payload.text === "string" ? payload.text : fallback;
}

function envelope(
  event: HermesEvent,
  context: HermesNormalizationContext,
  type: EventType,
  data: Record<string, unknown>,
  critical = true
): EventEnvelope {
  const cursor = Number.isFinite(event.seq) ? String(event.seq) : context.fallbackCursor;
  const session = event.session_id || context.conversationId;
  return {
    version: "1",
    eventId: `hermes:${session}:${cursor}:${type}`,
    conversationId: context.conversationId,
    cursor,
    occurredAt: context.occurredAt ?? new Date().toISOString(),
    correlationId: context.correlationId,
    type,
    critical,
    data
  };
}

function activityData(payload: Record<string, unknown>, eventType: string) {
  const specialist = eventType.startsWith("subagent.");
  const name =
    typeof payload.name === "string"
      ? payload.name
      : typeof payload.tool_name === "string"
        ? payload.tool_name
        : specialist
          ? "Specialist"
          : "Tool";
  const toolId =
    typeof payload.tool_id === "string"
      ? payload.tool_id
      : typeof payload.task_id === "string"
        ? payload.task_id
        : name;
  return {
    activityId: toolId,
    category: specialist || name.includes("delegate") || name.includes("subagent") ? "specialist" : "tool",
    label: name,
    ...(typeof payload.preview === "string" ? { summary: payload.preview } : {})
  };
}

export function normalizeHermesEvent(
  event: HermesEvent,
  context: HermesNormalizationContext
): EventEnvelope[] {
  const payload = record(event.payload);

  switch (event.type) {
    case "message.start":
      return [envelope(event, context, "response.started", {})];
    case "message.delta":
      return [envelope(event, context, "response.delta", { text: text(payload) })];
    case "message.complete": {
      const status = typeof payload.status === "string" ? payload.status : "complete";
      if (status !== "complete") {
        return [
          envelope(event, context, "response.failed", {
            code: "UPSTREAM_RESPONSE_FAILED",
            message: "Agent response failed",
            retryable: Boolean(record(payload.error_surface).retryable)
          })
        ];
      }
      return [
        envelope(event, context, "response.completed", {
          responseId: `hermes:${event.session_id || context.conversationId}:${event.seq ?? context.fallbackCursor}`,
          text: text(payload)
        })
      ];
    }
    case "tool.start":
    case "subagent.start":
      return [envelope(event, context, "activity.started", activityData(payload, event.type), false)];
    case "tool.progress":
    case "tool.generating":
    case "subagent.text":
    case "subagent.tool":
      return [envelope(event, context, "activity.updated", activityData(payload, event.type), false)];
    case "tool.complete":
      return [envelope(event, context, "activity.completed", activityData(payload, event.type), false)];
    case "subagent.complete":
      return [
        envelope(
          event,
          context,
          "activity.completed",
          {
            ...activityData(payload, event.type),
            ...(typeof payload.summary === "string"
              ? { summary: payload.summary }
              : text(payload)
                ? { summary: text(payload) }
                : {})
          },
          false
        )
      ];
    case "clarify.request":
      {
        const questions = Array.isArray(payload.questions)
          ? payload.questions.flatMap((candidate) => {
              const question = record(candidate);
              if (typeof question.question !== "string") return [];
              return [
                {
                  id: String(question.qid ?? ""),
                  prompt: question.question,
                  choices: Array.isArray(question.choices) ? question.choices : [],
                  multiSelect: question.multi_select === true
                }
              ];
            })
          : [];
      return [
        envelope(event, context, "input.requested", {
          requestId: String(payload.request_id ?? ""),
          kind: "clarification",
          prompt: text(payload, String(payload.question ?? questions[0]?.prompt ?? "")),
          choices: Array.isArray(payload.choices) ? payload.choices : [],
          ...(questions.length ? { questions } : {})
        })
      ];
      }
    case "approval.request":
      return [
        envelope(event, context, "input.requested", {
          requestId: String(payload.request_id ?? ""),
          kind: "approval",
          prompt: text(payload, String(payload.description ?? payload.command ?? "Approval required")),
          choices: Array.isArray(payload.choices) ? payload.choices : ["deny"]
        })
      ];
    case "error":
      return [
        envelope(event, context, "error.occurred", {
          code: "UPSTREAM_PROTOCOL_ERROR",
          message: "Agent service error",
          retryable: true
        })
      ];
    case "thinking.delta":
    case "reasoning.delta":
    case "reasoning.available":
      return [];
    default:
      return [];
  }
}

export function hermesRequest(
  id: string,
  method: string,
  params: Record<string, unknown>
): HermesJsonRpcFrame {
  return { jsonrpc: "2.0", id, method, params };
}
