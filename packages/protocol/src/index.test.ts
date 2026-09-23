import { describe, expect, it } from "vitest";
import { eventEnvelope, submitTurnCommand, transcriptionSegment } from "./index";

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

  it("separates the interactive and meeting text ceilings", () => {
    const base = {
      operationId: "op_1",
      conversationId: "conv_1",
      input: { kind: "text", text: "x".repeat(60_000) },
      profileOverride: null,
      clientContext: { timezone: "Europe/London", locale: "en-GB" }
    };

    expect(submitTurnCommand.safeParse(base).success).toBe(false);
    expect(
      submitTurnCommand.safeParse({ ...base, surface: "meeting-transcript" }).success
    ).toBe(true);
    expect(submitTurnCommand.safeParse({ ...base, surface: "text" }).success).toBe(false);
  });

  it("defaults the turn surface to a live voice turn", () => {
    const result = submitTurnCommand.safeParse({
      operationId: "op_1",
      conversationId: "conv_1",
      input: { kind: "text", text: "Hello" },
      profileOverride: null,
      clientContext: { timezone: "Europe/London", locale: "en-GB" }
    });

    expect(result.success && result.data.surface).toBe("voice-live");
  });

  it("requires segment identity and timing to be claimed together", () => {
    expect(
      transcriptionSegment.safeParse({ recordingId: "meeting-1", segmentIndex: "2" }).success
    ).toBe(true);
    expect(transcriptionSegment.safeParse({ segmentIndex: "2" }).success).toBe(false);
    expect(
      transcriptionSegment.safeParse({ segmentStartedAtMs: "0", segmentDurationMs: "1000" }).success
    ).toBe(false);
    expect(
      transcriptionSegment.safeParse({ recordingId: "meeting-1", segmentIndex: "2", segmentStartedAtMs: "0" })
        .success
    ).toBe(false);
    expect(transcriptionSegment.safeParse({ recordingId: "../escape" }).success).toBe(false);
  });
});
