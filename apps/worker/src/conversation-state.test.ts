import { beforeAll, describe, expect, it } from "vitest";
import type { Bindings } from "./auth";
import { ConversationStateCodec } from "./conversation-state";

let env: Bindings;

function base64url(value: Uint8Array) {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

beforeAll(() => {
  env = {
    AUTH_MODE: "local",
    SPEECH_MODE: "mock",
    AGENT_MODE: "hermes",
    CONVERSATION_STATE_KEY: base64url(crypto.getRandomValues(new Uint8Array(32)))
  };
});

describe("opaque conversation state", () => {
  it("round-trips state without exposing the Hermes session ID", async () => {
    const codec = new ConversationStateCodec(env);
    const token = await codec.seal(
      { profile: "default", storedSessionId: "raw-hermes-session-id" },
      "owner-1"
    );
    expect(token).not.toContain("raw-hermes-session-id");
    expect(token.length).toBeLessThanOrEqual(200);
    await expect(codec.open(token, "owner-1")).resolves.toEqual({
      profile: "default",
      storedSessionId: "raw-hermes-session-id"
    });
  });

  it("rejects use by another identity", async () => {
    const codec = new ConversationStateCodec(env);
    const token = await codec.seal({ profile: "default" }, "owner-1");
    await expect(codec.open(token, "owner-2")).rejects.toThrow("invalid conversation");
  });

  it("rejects tampering", async () => {
    const codec = new ConversationStateCodec(env);
    const token = await codec.seal({ profile: "default" }, "owner-1");
    const tampered = `${token.slice(0, -1)}${token.endsWith("A") ? "B" : "A"}`;
    await expect(codec.open(tampered, "owner-1")).rejects.toThrow("invalid conversation");
  });

  it("binds a pending approval and confirmation nonce", async () => {
    const codec = new ConversationStateCodec(env);
    const token = await codec.seal(
      {
        profile: "default",
        storedSessionId: "stored-session-id",
        pendingInput: {
          requestId: "approval-request-id",
          kind: "approval",
          confirmationNonce: "confirmation-nonce"
        }
      },
      "owner-1"
    );
    expect(token.length).toBeLessThanOrEqual(1024);
    await expect(codec.open(token, "owner-1")).resolves.toMatchObject({
      pendingInput: {
        requestId: "approval-request-id",
        kind: "approval",
        confirmationNonce: "confirmation-nonce"
      }
    });
  });

  it("fails closed without a 256-bit key", async () => {
    const codec = new ConversationStateCodec({ ...env, CONVERSATION_STATE_KEY: "short" });
    await expect(codec.seal({ profile: "default" }, "owner-1")).rejects.toThrow(
      "conversation state unavailable"
    );
  });
});
