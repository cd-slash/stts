import { eventEnvelope } from "@stts/protocol";

export interface CompletedReply {
  kind: "completed";
  text: string;
  specialist?: string;
  activity?: string;
}

export interface PendingInput {
  requestId: string;
  kind: "approval" | "clarification";
  prompt: string;
  choices: unknown[];
  confirmationNonce?: string;
}

export type AgentResult = CompletedReply | { kind: "input"; input: PendingInput };

const wait = (milliseconds: number) =>
  new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));

const usesWorker = import.meta.env.VITE_BACKEND === "worker";
export const backendLabel = usesWorker ? "Worker" : "Mock";
let conversation: Promise<string> | undefined;

async function parseJson(response: Response): Promise<unknown> {
  const body = await response.json().catch(() => null);
  if (!response.ok) throw new Error("Request failed");
  return body;
}

async function conversationId(): Promise<string> {
  if (!conversation) {
    conversation = fetch("/api/conversations", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ operationId: crypto.randomUUID(), profile: "chief-of-staff" })
    })
      .then(parseJson)
      .then((body) => {
        if (!body || typeof body !== "object" || !("conversationId" in body)) {
          throw new Error("Invalid response");
        }
        const id = body.conversationId;
        if (typeof id !== "string" || !id) throw new Error("Invalid response");
        return id;
      })
      .catch((error: unknown) => {
        conversation = undefined;
        throw error;
      });
  }
  return conversation;
}

export async function transcribeVoiceNote(audio: Blob): Promise<string> {
  if (usesWorker) {
    const form = new FormData();
    form.set("operationId", crypto.randomUUID());
    form.set("audio", audio, "voice-note.webm");
    const body = await fetch("/api/transcriptions", {
      method: "POST",
      credentials: "same-origin",
      body: form
    }).then(parseJson);
    if (!body || typeof body !== "object" || !("text" in body) || typeof body.text !== "string") {
      throw new Error("Invalid transcription");
    }
    return body.text;
  }

  await wait(600);
  return "Summarize my next priorities.";
}

function agentResult(body: unknown): AgentResult {
  if (!body || typeof body !== "object" || !("events" in body)) throw new Error("Invalid response");
  if (!("conversationId" in body) || typeof body.conversationId !== "string") {
    throw new Error("Invalid response");
  }
  conversation = Promise.resolve(body.conversationId);
  const parsed = eventEnvelope.array().safeParse(body.events);
  if (!parsed.success) throw new Error("Invalid response");
  const completed = parsed.data.slice().reverse().find((event) => event.type === "response.completed");
  const responseText = completed?.data.text;
  if (typeof responseText === "string") return { kind: "completed", text: responseText };

  const requested = parsed.data.slice().reverse().find((event) => event.type === "input.requested");
  const data = requested?.data;
  if (
    typeof data?.requestId === "string" &&
    (data.kind === "approval" || data.kind === "clarification") &&
    typeof data.prompt === "string"
  ) {
    return {
      kind: "input",
      input: {
        requestId: data.requestId,
        kind: data.kind,
        prompt: data.prompt,
        choices: Array.isArray(data.choices) ? data.choices : [],
        ...(typeof data.confirmationNonce === "string"
          ? { confirmationNonce: data.confirmationNonce }
          : {})
      }
    };
  }
  throw new Error("Missing response");
}

export async function submitTurn(text: string): Promise<AgentResult> {
  if (usesWorker) {
    const id = await conversationId();
    const body = await fetch(`/api/conversations/${encodeURIComponent(id)}/turns`, {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        operationId: crypto.randomUUID(),
        input: { kind: "text", text },
        profileOverride: null,
        clientContext: {
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
          locale: navigator.language
        }
      })
    }).then(parseJson);
    return agentResult(body);
  }

  await wait(900);
  return {
    kind: "completed",
    text: `Your priority summary is ready. The recorded request was: ${text}`,
    specialist: "Personal Assistant",
    activity: "Priority review complete"
  };
}

export async function answerInput(
  input: PendingInput,
  answer: { kind: "text"; text: string } | { kind: "approve" | "deny"; confirmationNonce?: string }
): Promise<AgentResult> {
  const id = await conversationId();
  const body = await fetch(
    `/api/conversations/${encodeURIComponent(id)}/inputs/${encodeURIComponent(input.requestId)}/answer`,
    {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ operationId: crypto.randomUUID(), answer })
    }
  ).then(parseJson);
  return agentResult(body);
}

export function speakLocal(text: string): void {
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = 1;
  window.speechSynthesis.speak(utterance);
}

export function stopLocalSpeech(): void {
  window.speechSynthesis.cancel();
}
