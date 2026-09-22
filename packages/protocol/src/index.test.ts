import { describe, expect, it } from "vitest";
import { eventEnvelope, submitTurnCommand } from "./index";

describe("protocol schemas", () => {
  it("accepts a normalized completion event", () => {
    const result = eventEnvelope.safeParse({
      version: "1",
      eventId: "evt_1",
      conversationId: "conv_1",
      cursor: "4",
      occurredAt: "2026-09-22T12:00:00Z",
      correlationId: "corr_1",
      type: "response.completed",
      critical: true,
      data: { responseId: "response_1", text: "Done" }
    });

    expect(result.success).toBe(true);
  });

  it("rejects an empty user turn", () => {
    const result = submitTurnCommand.safeParse({
      operationId: "op_1",
      conversationId: "conv_1",
      input: { kind: "text", text: " " },
      profileOverride: null,
      clientContext: { timezone: "Europe/London", locale: "en-GB" }
    });

    expect(result.success).toBe(false);
  });
});
