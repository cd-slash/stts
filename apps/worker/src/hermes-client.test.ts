import { describe, expect, it } from "vitest";
import type { SubmitTurnCommand } from "@stts/protocol";
import type { Bindings } from "./auth";
import { runHermesTurn, type HermesSocketProvider } from "./hermes-client";

class FakeHermesSocket extends EventTarget {
  readonly requests: Array<{ id: string; method: string; params: Record<string, unknown> }> = [];
  private sequence = 0;

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
    expect(result.storedSessionId).toBe("stored-secret");
  });
});
