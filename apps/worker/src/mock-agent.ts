import type { EventEnvelope, SubmitTurnCommand } from "@stts/protocol";

function event(
  command: SubmitTurnCommand,
  cursor: number,
  type: EventEnvelope["type"],
  data: Record<string, unknown>
): EventEnvelope {
  return {
    version: "1",
    eventId: crypto.randomUUID(),
    conversationId: command.conversationId,
    cursor: String(cursor),
    occurredAt: new Date().toISOString(),
    correlationId: command.operationId,
    type,
    critical: true,
    data
  };
}

export function runMockTurn(command: SubmitTurnCommand): EventEnvelope[] {
  const runId = crypto.randomUUID();
  const responseId = crypto.randomUUID();
  const text = `Mock response to: ${command.input.text}`;

  return [
    event(command, 1, "turn.accepted", { runId, turnId: crypto.randomUUID() }),
    event(command, 2, "response.started", { runId }),
    event(command, 3, "response.delta", { runId, text }),
    event(command, 4, "response.completed", { runId, responseId, text })
  ];
}
