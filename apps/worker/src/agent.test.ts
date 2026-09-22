import { describe, expect, it } from "vitest";
import type { Bindings } from "./auth";
import { createAgentAdapter } from "./agent";
import { ConversationStateCodec } from "./conversation-state";

const env: Bindings = {
  AUTH_MODE: "local",
  SPEECH_MODE: "mock",
  AGENT_MODE: "hermes",
  CONVERSATION_STATE_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
};

describe("Hermes input policy", () => {
  it("requires the bound confirmation nonce before approval", async () => {
    const conversationId = await new ConversationStateCodec(env).seal(
      {
        profile: "default",
        storedSessionId: "stored-session",
        pendingInput: {
          requestId: "approval-request",
          kind: "approval",
          confirmationNonce: "expected-nonce"
        }
      },
      "owner-1"
    );

    await expect(
      createAgentAdapter(env).answerInput(
        {
          operationId: "answer-operation",
          conversationId,
          requestId: "approval-request",
          answer: { kind: "approve", confirmationNonce: "wrong-nonce" }
        },
        "owner-1"
      )
    ).rejects.toMatchObject({
      code: "CONFIRMATION_REQUIRED",
      retryable: false,
      status: 409
    });
  });

  it("rejects a request ID not bound into the conversation", async () => {
    const conversationId = await new ConversationStateCodec(env).seal(
      {
        profile: "default",
        storedSessionId: "stored-session",
        pendingInput: {
          requestId: "approval-request",
          kind: "approval",
          confirmationNonce: "expected-nonce"
        }
      },
      "owner-1"
    );

    await expect(
      createAgentAdapter(env).answerInput(
        {
          operationId: "answer-operation",
          conversationId,
          requestId: "different-request",
          answer: { kind: "deny" }
        },
        "owner-1"
      )
    ).rejects.toMatchObject({ code: "INPUT_EXPIRED", status: 409 });
  });
});
