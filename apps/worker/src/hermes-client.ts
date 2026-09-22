import type { AnswerInputCommand, EventEnvelope, SubmitTurnCommand } from "@stts/protocol";
import type { Bindings } from "./auth";
import type { ConversationState } from "./conversation-state";
import {
  hermesRequest,
  normalizeHermesEvent,
  type HermesEvent,
  type HermesJsonRpcFrame
} from "./hermes-protocol";
import { HermesTransport, HermesTransportError } from "./hermes-transport";

const MAX_FRAME_BYTES = 1024 * 1024;

interface PendingRequest {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timer: ReturnType<typeof setTimeout>;
}

interface SessionResult {
  session_id: string;
  stored_session_id?: string;
}

export interface HermesTurnResult {
  events: EventEnvelope[];
  storedSessionId: string;
}

function turnTimeout(env: Bindings): number {
  const configured = Number(env.HERMES_TURN_TIMEOUT_MS ?? "110000");
  return Number.isInteger(configured) && configured >= 5_000 && configured <= 120_000
    ? configured
    : 110_000;
}

export interface HermesSocketProvider {
  connect(): Promise<WebSocket>;
}

function object(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function sessionResult(value: unknown, requireStored: boolean): SessionResult {
  const result = object(value);
  if (
    typeof result.session_id !== "string" ||
    !result.session_id ||
    (requireStored && (typeof result.stored_session_id !== "string" || !result.stored_session_id))
  ) {
    throw new HermesTransportError("Invalid agent response", true);
  }
  return {
    session_id: result.session_id,
    ...(typeof result.stored_session_id === "string" ? { stored_session_id: result.stored_session_id } : {})
  };
}

export class HermesRpcClient {
  private readonly pending = new Map<string, PendingRequest>();
  private readonly eventListeners = new Set<(event: HermesEvent) => void>();
  private readonly failureListeners = new Set<(error: Error) => void>();
  private readonly readyPromise: Promise<void>;
  private readyResolve!: () => void;
  private readyReject!: (error: Error) => void;
  private nextId = 0;
  private closed = false;

  constructor(
    private readonly socket: WebSocket,
    private readonly timeoutMs = 15_000
  ) {
    this.readyPromise = new Promise<void>((resolve, reject) => {
      this.readyResolve = resolve;
      this.readyReject = reject;
    });
    socket.addEventListener("message", this.onMessage);
    socket.addEventListener("close", this.onClose);
    socket.addEventListener("error", this.onError);
    socket.accept();
  }

  private fail(error: Error) {
    if (this.closed) return;
    this.closed = true;
    this.readyReject(error);
    for (const request of this.pending.values()) {
      clearTimeout(request.timer);
      request.reject(error);
    }
    this.pending.clear();
    for (const listener of this.failureListeners) listener(error);
    this.failureListeners.clear();
  }

  private readonly onClose = () => this.fail(new HermesTransportError("Agent connection closed", true));
  private readonly onError = () => this.fail(new HermesTransportError("Agent connection failed", true));

  private readonly onMessage = (message: MessageEvent) => {
    if (typeof message.data !== "string" || message.data.length > MAX_FRAME_BYTES) {
      this.fail(new HermesTransportError("Invalid agent response", true));
      this.socket.close(1009, "invalid frame");
      return;
    }

    let frame: HermesJsonRpcFrame;
    try {
      frame = JSON.parse(message.data) as HermesJsonRpcFrame;
    } catch {
      this.fail(new HermesTransportError("Invalid agent response", true));
      this.socket.close(1002, "invalid frame");
      return;
    }

    if (frame.method === "event") {
      const event = object(frame.params) as unknown as HermesEvent;
      if (event.type === "gateway.ready") this.readyResolve();
      if (typeof event.type === "string") {
        for (const listener of this.eventListeners) listener(event);
      }
      return;
    }

    if (typeof frame.id !== "string") return;
    const pending = this.pending.get(frame.id);
    if (!pending) return;
    this.pending.delete(frame.id);
    clearTimeout(pending.timer);
    if (frame.error) {
      pending.reject(new HermesTransportError("Agent request failed", true));
    } else {
      pending.resolve(frame.result);
    }
  };

  async ready(): Promise<void> {
    const timer = setTimeout(
      () => this.readyReject(new HermesTransportError("Agent connection timed out", true)),
      this.timeoutMs
    );
    try {
      await this.readyPromise;
    } finally {
      clearTimeout(timer);
    }
  }

  call(method: string, params: Record<string, unknown>): Promise<unknown> {
    if (this.closed) return Promise.reject(new HermesTransportError("Agent connection closed", true));
    const id = `stts-${++this.nextId}`;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new HermesTransportError("Agent request timed out", true));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      try {
        this.socket.send(JSON.stringify(hermesRequest(id, method, params)));
      } catch {
        clearTimeout(timer);
        this.pending.delete(id);
        reject(new HermesTransportError("Agent request failed", true));
      }
    });
  }

  collectTurn(
    sessionId: string,
    command: SubmitTurnCommand,
    timeoutMs: number
  ): { promise: Promise<EventEnvelope[]>; cancel(): void } {
    const events: EventEnvelope[] = [];
    let timer: ReturnType<typeof setTimeout>;
    let rejectWaiter: (error: Error) => void = () => undefined;
    const cleanup = () => {
      clearTimeout(timer);
      this.eventListeners.delete(listener);
      this.failureListeners.delete(rejectWaiter);
    };
    const listener = (event: HermesEvent) => {
      if (event.session_id !== sessionId) return;
      const normalized = normalizeHermesEvent(event, {
        conversationId: command.conversationId,
        correlationId: command.operationId,
        fallbackCursor: `operation-${command.operationId}`
      });
      events.push(...normalized);
      if (
        normalized.some((candidate) =>
          ["response.completed", "response.failed", "input.requested", "error.occurred"].includes(
            candidate.type
          )
        )
      ) {
        cleanup();
        resolveWaiter(events);
      }
    };
    let resolveWaiter: (events: EventEnvelope[]) => void = () => undefined;
    const promise = new Promise<EventEnvelope[]>((resolve, reject) => {
      resolveWaiter = resolve;
      rejectWaiter = reject;
      timer = setTimeout(() => {
        cleanup();
        reject(new HermesTransportError("Agent response timed out", true));
      }, timeoutMs);
    });
    this.eventListeners.add(listener);
    this.failureListeners.add(rejectWaiter);
    return {
      promise,
      cancel: cleanup
    };
  }

  close() {
    if (!this.closed) this.socket.close(1000, "request complete");
    this.fail(new HermesTransportError("Agent connection closed", true));
  }
}

export async function runHermesTurn(
  env: Bindings,
  state: ConversationState,
  command: SubmitTurnCommand,
  provider: HermesSocketProvider = new HermesTransport(env)
): Promise<HermesTurnResult> {
  const socket = await provider.connect();
  const timeoutMs = turnTimeout(env);
  const client = new HermesRpcClient(socket, 15_000);
  let collector: ReturnType<HermesRpcClient["collectTurn"]> | undefined;
  try {
    await client.ready();
    const session = state.storedSessionId
      ? sessionResult(
          await client.call("session.resume", {
            session_id: state.storedSessionId,
            profile: state.profile,
            defer_history: true
          }),
          false
        )
      : sessionResult(
          await client.call("session.create", {
            profile: state.profile,
            source: "stts",
            close_on_disconnect: false,
            follow_profile_config: true
          }),
          true
        );
    const storedSessionId = state.storedSessionId ?? session.stored_session_id!;
    collector = client.collectTurn(session.session_id, command, timeoutMs);
    await client.call("prompt.submit", {
      session_id: session.session_id,
      text: command.input.text,
      surface: "voice-live"
    });
    return { events: await collector.promise, storedSessionId };
  } catch (error) {
    collector?.cancel();
    throw error instanceof HermesTransportError
      ? error
      : new HermesTransportError("Agent service unavailable", true);
  } finally {
    client.close();
  }
}

export async function runHermesInputResponse(
  env: Bindings,
  state: ConversationState & { storedSessionId: string },
  command: AnswerInputCommand,
  provider: HermesSocketProvider = new HermesTransport(env)
): Promise<HermesTurnResult> {
  const socket = await provider.connect();
  const client = new HermesRpcClient(socket, 15_000);
  let collector: ReturnType<HermesRpcClient["collectTurn"]> | undefined;
  try {
    await client.ready();
    const session = sessionResult(
      await client.call("session.resume", {
        session_id: state.storedSessionId,
        profile: state.profile,
        defer_history: true
      }),
      false
    );
    collector = client.collectTurn(
      session.session_id,
      {
        operationId: command.operationId,
        conversationId: command.conversationId,
        input: { kind: "text", text: command.answer.text || command.answer.kind },
        profileOverride: null,
        clientContext: { timezone: "UTC", locale: "en" }
      },
      turnTimeout(env)
    );

    const method = state.pendingInput?.kind === "approval" ? "approval.respond" : "clarify.respond";
    const params =
      method === "approval.respond"
        ? {
            session_id: session.session_id,
            request_id: command.requestId,
            choice: command.answer.kind === "approve" ? "once" : "deny",
            all: false
          }
        : {
            session_id: session.session_id,
            request_id: command.requestId,
            answer: command.answer.text ?? ""
          };
    const response = object(await client.call(method, params));
    if (response.status === "expired") {
      collector.cancel();
      throw new HermesTransportError("Input request expired", false);
    }

    const events = await collector.promise;
    events.unshift({
      version: "1",
      eventId: `event:${command.operationId}:input-resolved`,
      conversationId: command.conversationId,
      cursor: `operation-${command.operationId}-input-resolved`,
      occurredAt: new Date().toISOString(),
      correlationId: command.operationId,
      type: "input.resolved",
      critical: true,
      data: { requestId: command.requestId }
    });
    return { events, storedSessionId: state.storedSessionId };
  } catch (error) {
    collector?.cancel();
    throw error instanceof HermesTransportError
      ? error
      : new HermesTransportError("Agent service unavailable", true);
  } finally {
    client.close();
  }
}
