import type { EventEnvelope, SubmitTurnCommand } from "@stts/protocol";
import type { Bindings } from "./auth";
import { ConversationStateCodec } from "./conversation-state";
import { runHermesTurn } from "./hermes-client";
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

class MockAgentAdapter implements AgentAdapter {
  async createConversation(profile: string): Promise<ConversationHandle> {
    return { conversationId: crypto.randomUUID(), profile };
  }

  async submitTurn(command: SubmitTurnCommand): Promise<TurnResult> {
    return { conversationId: command.conversationId, events: runMockTurn(command) };
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
      return {
        conversationId: await this.state.seal(
          { profile: state.profile, storedSessionId: result.storedSessionId },
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
}

export function createAgentAdapter(env: Bindings): AgentAdapter {
  if (env.AGENT_MODE === "mock") return new MockAgentAdapter();
  if (env.AGENT_MODE === "hermes") return new HermesAgentAdapter(env);
  throw new AgentAdapterError("Agent service unavailable", false);
}
