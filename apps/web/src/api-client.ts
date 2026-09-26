import { eventEnvelope } from "@stts/protocol";

export interface CompletedReply {
  kind: "completed";
  text: string;
  responseId?: string;
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

export type AgentResult =
  | CompletedReply
  | { kind: "input"; input: PendingInput }
  | { kind: "interrupted" };

const wait = (milliseconds: number) =>
  new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));

const usesWorker = import.meta.env.VITE_BACKEND === "worker";
export const backendLabel = usesWorker ? "Worker" : "Mock";

export async function keyboardAvailable(): Promise<boolean> {
  if (!usesWorker) return false;
  const response = await fetch("/api/keyboard", { credentials: "same-origin" });
  if (!response.ok) return false;
  const body: unknown = await response.json();
  return !!body && typeof body === "object" && "available" in body && body.available === true;
}

export async function typeOnKeyboard(text: string): Promise<void> {
  await fetch("/api/keyboard/type", {
    method: "POST",
    credentials: "same-origin",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ text })
  }).then(parseJson);
}
const conversationStorageKey = "stts.conversation.v1";

class ApiError extends Error {
  constructor(readonly code: string) {
    super("Request failed");
  }
}

function restoredConversation(): string | undefined {
  if (!usesWorker) return undefined;
  try {
    const value = window.localStorage.getItem(conversationStorageKey);
    return value || undefined;
  } catch {
    return undefined;
  }
}

let currentConversationId: string | undefined;
let nextMutation = 0;
let retainedMutation = 0;

function retainConversation(value: string, mutation = retainedMutation): void {
  if (mutation < retainedMutation) return;
  retainedMutation = mutation;
  currentConversationId = value;
  conversation = Promise.resolve(value);
  try {
    window.localStorage.setItem(conversationStorageKey, value);
  } catch {
    // In-memory continuation remains available when storage is blocked.
  }
}

function clearConversation(value: string, mutation: number): void {
  if (currentConversationId !== value || mutation < retainedMutation) return;
  currentConversationId = undefined;
  conversation = undefined;
  hasDurableConversation = false;
  try {
    window.localStorage.removeItem(conversationStorageKey);
  } catch {
    // In-memory state is still cleared when storage is blocked.
  }
}

const restored = restoredConversation();
let conversation: Promise<string> | undefined = restored ? Promise.resolve(restored) : undefined;
currentConversationId = restored;
let activeAudio: HTMLAudioElement | undefined;
let activeAudioUrl: string | undefined;
const audioCache = new Map<string, Blob>();
const MAX_CACHED_AUDIO = 10;
let hasDurableConversation = false;
let activeTurn: { runId: string; controller: AbortController } | undefined;

async function parseJson(response: Response): Promise<unknown> {
  const body = await response.json().catch(() => null);
  if (!response.ok) {
    const code =
      body && typeof body === "object" && "code" in body && typeof body.code === "string"
        ? body.code
        : "REQUEST_FAILED";
    throw new ApiError(code);
  }
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
        retainConversation(id);
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

function agentResult(body: unknown, mutation: number): AgentResult {
  if (!body || typeof body !== "object" || !("events" in body)) throw new Error("Invalid response");
  if (!("conversationId" in body) || typeof body.conversationId !== "string") {
    throw new Error("Invalid response");
  }
  const parsed = eventEnvelope.array().safeParse(body.events);
  if (!parsed.success) throw new Error("Invalid response");
  retainConversation(body.conversationId, mutation);
  hasDurableConversation = true;
  const completed = parsed.data.slice().reverse().find((event) => event.type === "response.completed");
  const responseText = completed?.data.text;
  if (typeof responseText === "string") {
    const responseId = completed?.data.responseId;
    return {
      kind: "completed",
      text: responseText,
      ...(typeof responseId === "string" ? { responseId } : {})
    };
  }

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
    const runId = crypto.randomUUID();
    const controller = new AbortController();
    activeTurn = { runId, controller };
    try {
      for (let attempt = 0; attempt < 2; attempt += 1) {
        const id = await conversationId();
        const mutation = ++nextMutation;
        try {
          const body = await fetch(`/api/conversations/${encodeURIComponent(id)}/turns`, {
            method: "POST",
            credentials: "same-origin",
            headers: { "content-type": "application/json" },
            signal: controller.signal,
            body: JSON.stringify({
              operationId: runId,
              input: { kind: "text", text },
              profileOverride: null,
              clientContext: {
                timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
                locale: navigator.language
              }
            })
          }).then(parseJson);
          return agentResult(body, mutation);
        } catch (error) {
          if (attempt === 0 && error instanceof ApiError && error.code === "INVALID_REQUEST") {
            clearConversation(id, mutation);
            continue;
          }
          throw error;
        }
      }
      throw new Error("Request failed");
    } catch (error) {
      if (controller.signal.aborted) return { kind: "interrupted" };
      throw error;
    } finally {
      if (activeTurn?.runId === runId) activeTurn = undefined;
    }
  }

  await wait(900);
  return {
    kind: "completed",
    text: `Your priority summary is ready. The recorded request was: ${text}`,
    specialist: "Personal Assistant",
    activity: "Priority review complete"
  };
}

export async function interruptActiveTurn(): Promise<boolean> {
  if (!usesWorker || !hasDurableConversation || !activeTurn) return false;
  const turn = activeTurn;
  const id = await conversationId();
  const mutation = ++nextMutation;
  const body = await fetch(
    `/api/conversations/${encodeURIComponent(id)}/runs/${encodeURIComponent(turn.runId)}/interrupt`,
    {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ operationId: crypto.randomUUID(), reason: "user_cancelled" })
    }
  ).then(parseJson);
  if (!body || typeof body !== "object" || !("conversationId" in body)) {
    throw new Error("Invalid response");
  }
  if (typeof body.conversationId !== "string") throw new Error("Invalid response");
  retainConversation(body.conversationId, mutation);
  turn.controller.abort();
  if (activeTurn?.runId === turn.runId) activeTurn = undefined;
  return true;
}

export async function answerInput(
  input: PendingInput,
  answer: { kind: "text"; text: string } | { kind: "approve" | "deny"; confirmationNonce?: string }
): Promise<AgentResult> {
  const id = await conversationId();
  const mutation = ++nextMutation;
  const body = await fetch(
    `/api/conversations/${encodeURIComponent(id)}/inputs/${encodeURIComponent(input.requestId)}/answer`,
    {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ operationId: crypto.randomUUID(), answer })
    }
  ).then(parseJson);
  return agentResult(body, mutation);
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

export function stopAudio(): void {
  stopLocalSpeech();
  activeAudio?.pause();
  activeAudio = undefined;
  if (activeAudioUrl) URL.revokeObjectURL(activeAudioUrl);
  activeAudioUrl = undefined;
}

export async function playResponse(text: string, responseId?: string): Promise<void> {
  stopAudio();
  if (!usesWorker || !responseId) {
    speakLocal(text);
    return;
  }

  let blob = audioCache.get(responseId);
  if (!blob) {
    const id = await conversationId();
    const response = await fetch("/api/speech/synthesis", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        operationId: crypto.randomUUID(),
        conversationId: id,
        responseId,
        voice: "default",
        format: "audio/mpeg"
      })
    });
    if (!response.ok) throw new Error("Synthesis failed");
    blob = await response.blob();
    audioCache.set(responseId, blob);
    if (audioCache.size > MAX_CACHED_AUDIO) {
      const oldest = audioCache.keys().next().value;
      if (typeof oldest === "string") audioCache.delete(oldest);
    }
  }
  const url = URL.createObjectURL(blob);
  const audio = new Audio(url);
  activeAudioUrl = url;
  activeAudio = audio;
  const cleanup = () => {
    URL.revokeObjectURL(url);
    if (activeAudio === audio) {
      activeAudio = undefined;
      activeAudioUrl = undefined;
    }
  };
  audio.addEventListener("ended", cleanup, { once: true });
  audio.addEventListener("error", cleanup, { once: true });
  try {
    await audio.play();
  } catch (error) {
    cleanup();
    throw error;
  }
}
