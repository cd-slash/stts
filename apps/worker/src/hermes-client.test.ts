import { describe, expect, it } from "vitest";
import type { AnswerInputCommand, InterruptRunCommand, SubmitTurnCommand } from "@stts/protocol";
import type { Bindings } from "./auth";
import {
  runHermesInputResponse,
  runHermesInterrupt,
  runHermesTurn,
  type HermesSocketProvider
} from "./hermes-client";

class FakeHermesSocket extends EventTarget {
  readonly requests: Array<{ id: string; method: string; params: Record<string, unknown> }> = [];
  private sequence = 0;

  constructor(private readonly staleCompletedSequence?: number) {
    super();
    if (staleCompletedSequence) this.sequence = staleCompletedSequence;
  }

  accept() {
    queueMicrotask(() => this.event({ type: "gateway.ready", payload: { replay_epoch: "epoch-1" } }));
  }

  send(value: string) {
    const request = JSON.parse(value) as {
      id: string;
      method: string;
      params: Record<string, unknown>;
    };
    this.requests.push(request);
    queueMicrotask(() => {
      if (request.method === "session.create") {
        this.reply(request.id, { session_id: "runtime-secret", stored_session_id: "stored-secret" });
        return;
      }
      if (request.method === "session.resume") {
        this.reply(request.id, { session_id: "resumed-runtime-secret" });
        return;
      }
      if (request.method === "prompt.submit") {
        const sessionId = String(request.params.session_id);
        if (this.staleCompletedSequence) {
          this.event({
            type: "message.complete",
            session_id: sessionId,
            seq: this.staleCompletedSequence,
            payload: { text: "Stale response", status: "complete" }
          });
        }
        this.event({ type: "message.start", session_id: sessionId, seq: ++this.sequence });
        this.event({
          type: "message.delta",
          session_id: sessionId,
          seq: ++this.sequence,
          payload: { text: "Hello" }
        });
        this.reply(request.id, { status: "streaming" });
        this.event({
          type: "message.complete",
          session_id: sessionId,
          seq: ++this.sequence,
          payload: { text: "Hello there", status: "complete" }
        });
        return;
      }
      if (request.method === "session.events.since") {
        this.reply(request.id, {
          events: this.staleCompletedSequence ? [{ seq: this.staleCompletedSequence }] : []
        });
        return;
      }
      if (request.method === "approval.respond" || request.method === "clarify.respond") {
        const sessionId = String(request.params.session_id);
        this.reply(request.id, { resolved: 1, status: "ok" });
        this.event({
          type: "message.complete",
          session_id: sessionId,
          seq: ++this.sequence,
          payload: { text: "Action complete", status: "complete" }
        });
        return;
      }
      if (request.method === "session.interrupt") {
        this.reply(request.id, { status: "interrupted", interrupted: true });
      }
    });
  }

  close() {}

  private reply(id: string, result: unknown) {
    this.dispatchEvent(
      new MessageEvent("message", { data: JSON.stringify({ jsonrpc: "2.0", id, result }) })
    );
  }

  private event(params: Record<string, unknown>) {
    this.dispatchEvent(
      new MessageEvent("message", {
        data: JSON.stringify({ jsonrpc: "2.0", method: "event", params })
      })
    );
  }
}

const env: Bindings = {
  AUTH_MODE: "local",
  SPEECH_MODE: "mock",
  AGENT_MODE: "hermes",
  HERMES_TURN_TIMEOUT_MS: "5000"
};

const command: SubmitTurnCommand = {
  operationId: "operation-1",
  conversationId: "opaque-conversation",
  input: { kind: "text", text: "Hello" },
  profileOverride: null,
  clientContext: { timezone: "UTC", locale: "en" }
};

describe("Hermes turn lifecycle", () => {
  it("creates the first durable session and collects its completed response", async () => {
    const socket = new FakeHermesSocket();
    const provider: HermesSocketProvider = { connect: async () => socket as unknown as WebSocket };
    const result = await runHermesTurn(env, { profile: "default" }, command, provider);

    expect(socket.requests.map((request) => request.method)).toEqual([
      "session.create",
      "prompt.submit"
    ]);
    expect(socket.requests[0]?.params).toMatchObject({
      profile: "default",
      source: "stts",
      close_on_disconnect: false
    });
    expect(result.storedSessionId).toBe("stored-secret");
    expect(result.events.map((event) => event.type)).toEqual([
      "response.started",
      "response.delta",
      "response.completed"
    ]);
    expect(JSON.stringify(result.events)).not.toContain("runtime-secret");
    expect(JSON.stringify(result.events)).not.toContain("stored-secret");
  });

  it("resumes subsequent turns by durable session ID", async () => {
    const socket = new FakeHermesSocket();
    const provider: HermesSocketProvider = { connect: async () => socket as unknown as WebSocket };
    const result = await runHermesTurn(
      env,
      { profile: "default", storedSessionId: "stored-secret" },
      command,
      provider
    );

    expect(socket.requests[0]).toMatchObject({
      method: "session.resume",
      params: { session_id: "stored-secret", profile: "default", defer_history: true }
    });
    expect(socket.requests.map((request) => request.method)).toEqual([
      "session.resume",
      "session.interrupt",
      "session.events.since",
      "prompt.submit"
    ]);
    expect(result.storedSessionId).toBe("stored-secret");
  });

  it("ignores completed events at or below the pre-submit sequence watermark", async () => {
    const socket = new FakeHermesSocket(7);
    const provider: HermesSocketProvider = { connect: async () => socket as unknown as WebSocket };
    const result = await runHermesTurn(
      env,
      { profile: "default", storedSessionId: "stored-secret" },
      command,
      provider
    );

    expect(result.events.at(-1)?.data.text).toBe("Hello there");
    expect(JSON.stringify(result.events)).not.toContain("Stale response");
  });

  it("resumes and resolves a pending approval", async () => {
    const socket = new FakeHermesSocket();
    const provider: HermesSocketProvider = { connect: async () => socket as unknown as WebSocket };
    const answer: AnswerInputCommand = {
      operationId: "answer-operation",
      conversationId: "opaque-conversation",
      requestId: "approval-request",
      answer: { kind: "approve", confirmationNonce: "nonce" }
    };
    const result = await runHermesInputResponse(
      env,
      {
        profile: "default",
        storedSessionId: "stored-secret",
        pendingInput: {
          requestId: "approval-request",
          kind: "approval",
          confirmationNonce: "nonce"
        }
      },
      answer,
      provider
    );

    expect(socket.requests.map((request) => request.method)).toEqual([
      "session.resume",
      "session.events.since",
      "approval.respond"
    ]);
    expect(socket.requests[2]?.params).toMatchObject({
      request_id: "approval-request",
      choice: "once",
      all: false
    });
    expect(result.events.map((event) => event.type)).toEqual([
      "input.resolved",
      "response.completed"
    ]);
  });

  it("resumes and interrupts an active run", async () => {
    const socket = new FakeHermesSocket();
    const provider: HermesSocketProvider = { connect: async () => socket as unknown as WebSocket };
    const interrupt: InterruptRunCommand = {
      operationId: "interrupt-operation",
      conversationId: "opaque-conversation",
      runId: "run-1",
      reason: "user_redirect"
    };
    const result = await runHermesInterrupt(
      env,
      { profile: "default", storedSessionId: "stored-secret" },
      interrupt,
      provider
    );

    expect(socket.requests.map((request) => request.method)).toEqual([
      "session.resume",
      "session.interrupt"
    ]);
    expect(result.events.map((event) => event.type)).toEqual([
      "run.interrupting",
      "run.interrupted"
    ]);
  });
});
