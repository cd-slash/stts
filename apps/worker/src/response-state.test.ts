import { describe, expect, it, vi } from "vitest";
import type { Bindings } from "./auth";
import { ResponseStateCodec } from "./response-state";

const env: Bindings = {
  AUTH_MODE: "local",
  SPEECH_MODE: "mock",
  AGENT_MODE: "hermes",
  CONVERSATION_STATE_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  RESPONSE_TOKEN_TTL_SECONDS: "60"
};

describe("ephemeral response state", () => {
  it("round-trips only for the bound owner and conversation", async () => {
    const codec = new ResponseStateCodec(env);
    const token = await codec.seal("Completed response", "conversation-1", "owner-1");
    expect(token).not.toContain("Completed response");
    await expect(codec.open(token, "conversation-1", "owner-1")).resolves.toBe(
      "Completed response"
    );
    await expect(codec.open(token, "conversation-2", "owner-1")).rejects.toThrow(
      "invalid response"
    );
    await expect(codec.open(token, "conversation-1", "owner-2")).rejects.toThrow(
      "invalid response"
    );
  });

  it("rejects expired response state", async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(new Date("2026-09-22T12:00:00Z"));
      const codec = new ResponseStateCodec(env);
      const token = await codec.seal("Completed response", "conversation-1", "owner-1");
      vi.setSystemTime(new Date("2026-09-22T12:01:01Z"));
      await expect(codec.open(token, "conversation-1", "owner-1")).rejects.toThrow(
        "invalid response"
      );
    } finally {
      vi.useRealTimers();
    }
  });
});
