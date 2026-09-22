import type { AnswerInputCommand, EventEnvelope, SubmitTurnCommand } from "@stts/protocol";
import type { Bindings } from "./auth";
import { ConversationStateCodec, type ConversationState } from "./conversation-state";
import { runHermesInputResponse, runHermesTurn } from "./hermes-client";
import { HermesTransportError } from "./hermes-transport";
import { runMockTurn } from "./mock-agent";

export interface ConversationHandle {
  conversationId: string;
  profile: string;
}

export interface TurnResult {
  conversationId: string;
  events: EventEnvelope[];
}

export interface AgentAdapter {
  createConversation(profile: string, subject: string): Promise<ConversationHandle>;
  submitTurn(command: SubmitTurnCommand, subject: string): Promise<TurnResult>;
  answerInput(command: AnswerInputCommand, subject: string): Promise<TurnResult>;
}

export class AgentAdapterError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly status = 503,
    readonly code = "UPSTREAM_UNAVAILABLE"
  ) {
    super(message);
  }
}

const profileIds = new Set([
  "default",
  "car-mechanic",
  "cloud-engineer",
  "legal-assistant",
  "personal-assistant",
  "property-agent",
  "trainer",
  "travel-planner"
]);

function hermesProfile(profile: string): string {
  const mapped = profile === "chief-of-staff" ? "default" : profile;
  if (!profileIds.has(mapped)) {
    throw new AgentAdapterError("Invalid profile", false, 400, "INVALID_REQUEST");
  }
  return mapped;
}

function nonce(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pendingInput(events: EventEnvelope[]): ConversationState["pendingInput"] {
  const requested = events.slice().reverse().find((event) => event.type === "input.requested");
  const requestId = requested?.data.requestId;
  const kind = requested?.data.kind;
  if (
    !requested ||
    typeof requestId !== "string" ||
    (kind !== "approval" && kind !== "clarification")
  ) {
    return undefined;
  }
  const confirmationNonce = kind === "approval" ? nonce() : undefined;
  if (confirmationNonce) requested.data = { ...requested.data, confirmationNonce };
  return {
    requestId,
    kind,
    ...(confirmationNonce ? { confirmationNonce } : {})
  };
}

class MockAgentAdapter implements AgentAdapter {
  async createConversation(profile: string): Promise<ConversationHandle> {
    return { conversationId: crypto.randomUUID(), profile };
  }

  async submitTurn(command: SubmitTurnCommand): Promise<TurnResult> {
    return { conversationId: command.conversationId, events: runMockTurn(command) };
  }

  async answerInput(command: AnswerInputCommand): Promise<TurnResult> {
    return {
      conversationId: command.conversationId,
      events: [
        {
          version: "1",
          eventId: `event:${command.operationId}:input-resolved`,
          conversationId: command.conversationId,
          cursor: `operation-${command.operationId}`,
          occurredAt: new Date().toISOString(),
          correlationId: command.operationId,
          type: "input.resolved",
          critical: true,
          data: { requestId: command.requestId }
        }
      ]
    };
  }
}

class HermesAgentAdapter implements AgentAdapter {
  private readonly state: ConversationStateCodec;

  constructor(private readonly env: Bindings) {
    this.state = new ConversationStateCodec(env);
  }

  async createConversation(profile: string, subject: string): Promise<ConversationHandle> {
    const normalizedProfile = hermesProfile(profile);
    try {
      return {
        conversationId: await this.state.seal({ profile: normalizedProfile }, subject),
        profile
      };
    } catch {
      throw new AgentAdapterError("Agent service unavailable", false);
    }
  }

  async submitTurn(command: SubmitTurnCommand, subject: string): Promise<TurnResult> {
    try {
      const state = await this.state.open(command.conversationId, subject);
      if (command.profileOverride && hermesProfile(command.profileOverride) !== state.profile) {
        throw new AgentAdapterError("Profile change unavailable", false, 400, "INVALID_REQUEST");
      }
      const result = await runHermesTurn(this.env, state, command);
      const pending = pendingInput(result.events);
      return {
        conversationId: await this.state.seal(
          {
            profile: state.profile,
            storedSessionId: result.storedSessionId,
            ...(pending ? { pendingInput: pending } : {})
          },
          subject
        ),
        events: result.events
      };
    } catch (error) {
      if (error instanceof AgentAdapterError) throw error;
      if (error instanceof HermesTransportError) {
        throw new AgentAdapterError(error.message, error.retryable);
      }
      if (error instanceof Error && error.message === "invalid conversation") {
        throw new AgentAdapterError("Invalid conversation", false, 400, "INVALID_REQUEST");
      }
      throw new AgentAdapterError("Agent service unavailable", true);
    }
  }

  async answerInput(command: AnswerInputCommand, subject: string): Promise<TurnResult> {
    try {
      const state = await this.state.open(command.conversationId, subject);
      const pending = state.pendingInput;
      if (!state.storedSessionId || !pending || pending.requestId !== command.requestId) {
        throw new AgentAdapterError("Input request unavailable", false, 409, "INPUT_EXPIRED");
      }
      if (pending.kind === "approval") {
        if (command.answer.kind !== "approve" && command.answer.kind !== "deny") {
          throw new AgentAdapterError("Invalid approval response", false, 400, "INVALID_REQUEST");
        }
        if (
          command.answer.kind === "approve" &&
          command.answer.confirmationNonce !== pending.confirmationNonce
        ) {
          throw new AgentAdapterError("Confirmation required", false, 409, "CONFIRMATION_REQUIRED");
        }
      } else if (command.answer.kind !== "text" || !command.answer.text) {
        throw new AgentAdapterError("Clarification required", false, 400, "INVALID_REQUEST");
      }

      const result = await runHermesInputResponse(
        this.env,
        { ...state, storedSessionId: state.storedSessionId },
        command
      );
      const nextPending = pendingInput(result.events);
      return {
        conversationId: await this.state.seal(
          {
            profile: state.profile,
            storedSessionId: result.storedSessionId,
            ...(nextPending ? { pendingInput: nextPending } : {})
          },
          subject
        ),
        events: result.events
      };
    } catch (error) {
      if (error instanceof AgentAdapterError) throw error;
      if (error instanceof Error && error.message === "invalid conversation") {
        throw new AgentAdapterError("Invalid conversation", false, 400, "INVALID_REQUEST");
      }
      if (error instanceof HermesTransportError) {
        if (error.message === "Input request expired") {
          throw new AgentAdapterError(error.message, false, 409, "INPUT_EXPIRED");
        }
        throw new AgentAdapterError(error.message, error.retryable);
      }
      throw new AgentAdapterError("Agent service unavailable", true);
    }
  }
}

export function createAgentAdapter(env: Bindings): AgentAdapter {
  if (env.AGENT_MODE === "mock") return new MockAgentAdapter();
  if (env.AGENT_MODE === "hermes") return new HermesAgentAdapter(env);
  throw new AgentAdapterError("Agent service unavailable", false);
}
