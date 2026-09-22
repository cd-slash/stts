import { describe, expect, it } from "vitest";
import { hermesRequest, normalizeHermesEvent } from "./hermes-protocol";

const context = {
  conversationId: "conv_1",
  correlationId: "op_1",
  fallbackCursor: "local_1",
  occurredAt: "2026-09-22T12:00:00Z"
};

describe("Hermes pinned protocol mapping", () => {
  it("builds JSON-RPC 2.0 requests", () => {
    expect(hermesRequest("rpc_1", "prompt.submit", { session_id: "session_1", text: "hello" })).toEqual({
      jsonrpc: "2.0",
      id: "rpc_1",
      method: "prompt.submit",
      params: { session_id: "session_1", text: "hello" }
    });
  });

  it("maps streaming and completion frames", () => {
    const delta = normalizeHermesEvent(
      { type: "message.delta", session_id: "session_1", seq: 4, payload: { text: "Hello" } },
      context
    );
    const complete = normalizeHermesEvent(
      {
        type: "message.complete",
        session_id: "session_1",
        seq: 5,
        payload: { text: "Hello there", status: "complete" }
      },
      context
    );

    expect(delta[0]).toMatchObject({ cursor: "4", type: "response.delta", data: { text: "Hello" } });
    expect(complete[0]).toMatchObject({
      cursor: "5",
      type: "response.completed",
      data: { responseId: "response:op_1:5", text: "Hello there" }
    });
  });

  it("maps approval and clarification requests without raw payload passthrough", () => {
    const approval = normalizeHermesEvent(
      {
        type: "approval.request",
        seq: 7,
        payload: { request_id: "approval_1", command: "redacted command", choices: ["once", "deny"] }
      },
      context
    );
    const clarification = normalizeHermesEvent(
      {
        type: "clarify.request",
        seq: 8,
        payload: { request_id: "clarify_1", question: "Which date?", choices: ["Friday"] }
      },
      context
    );

    expect(approval[0]).toMatchObject({
      type: "input.requested",
      data: { requestId: "approval_1", kind: "approval", choices: ["once", "deny"] }
    });
    expect(clarification[0]).toMatchObject({
      type: "input.requested",
      data: { requestId: "clarify_1", kind: "clarification", prompt: "Which date?" }
    });
  });

  it("drops internal reasoning events", () => {
    expect(
      normalizeHermesEvent({ type: "reasoning.delta", seq: 9, payload: { text: "private" } }, context)
    ).toEqual([]);
  });

  it("preserves safe batch clarification fields", () => {
    const events = normalizeHermesEvent(
      {
        type: "clarify.request",
        seq: 10,
        payload: {
          request_id: "clarify_batch",
          questions: [
            { qid: "date", question: "Which date?", choices: ["Friday"], multi_select: false }
          ]
        }
      },
      context
    );

    expect(events[0]).toMatchObject({
      type: "input.requested",
      data: {
        requestId: "clarify_batch",
        prompt: "Which date?",
        questions: [{ id: "date", prompt: "Which date?", choices: ["Friday"], multiSelect: false }]
      }
    });
  });
});
