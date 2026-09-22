import type { EventEnvelope, SubmitTurnCommand } from "@stts/protocol";
import type { Bindings } from "./auth";
import { runMockTurn } from "./mock-agent";

export interface ConversationHandle {
  conversationId: string;
  profile: string;
}

export interface AgentAdapter {
  createConversation(profile: string, subject: string): Promise<ConversationHandle>;
  submitTurn(command: SubmitTurnCommand, subject: string): Promise<EventEnvelope[]>;
}

export class AgentAdapterError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly status = 503
  ) {
    super(message);
  }
}

class MockAgentAdapter implements AgentAdapter {
  async createConversation(profile: string): Promise<ConversationHandle> {
    return { conversationId: crypto.randomUUID(), profile };
  }

  async submitTurn(command: SubmitTurnCommand): Promise<EventEnvelope[]> {
    return runMockTurn(command);
  }
}

class UnavailableHermesAdapter implements AgentAdapter {
  async createConversation(): Promise<ConversationHandle> {
    throw new AgentAdapterError("Agent service unavailable", true);
  }

  async submitTurn(): Promise<EventEnvelope[]> {
    throw new AgentAdapterError("Agent service unavailable", true);
  }
}

export function createAgentAdapter(env: Bindings): AgentAdapter {
  if (env.AGENT_MODE === "mock") return new MockAgentAdapter();
  if (env.AGENT_MODE === "hermes") return new UnavailableHermesAdapter();
  throw new AgentAdapterError("Agent service unavailable", false);
}
