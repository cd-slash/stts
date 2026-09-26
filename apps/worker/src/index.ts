import {
  answerInputCommand,
  createConversationCommand,
  interruptRunCommand,
  synthesizeResponseCommand,
  submitTurnCommand,
  transcriptionSegment
} from "@stts/protocol";
import { Hono } from "hono";
import { AgentAdapterError, createAgentAdapter } from "./agent";
import { requireIdentity, type Bindings, type Variables } from "./auth";
import { ConversationStateCodec } from "./conversation-state";
import { ResponseStateCodec } from "./response-state";
import { createSpeechAdapter, SpeechAdapterError } from "./speech";
import { keyboardRequest, keyboardText } from "./keyboard";

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

app.use("/api/*", requireIdentity);
app.get("/api/health", (context) => context.json({ status: "ok" }));

app.get("/api/keyboard", async (context) => {
  const result = await keyboardRequest(context.env, "GET");
  return context.json({ available: result.status === 200 });
});

app.post("/api/keyboard/type", async (context) => {
  const raw = await context.req.text();
  if (raw.length > 6 * 1024) {
    return context.json({ code: "PAYLOAD_TOO_LARGE", message: "Text too long", retryable: false }, 413);
  }
  let body: unknown;
  try { body = JSON.parse(raw); } catch { body = null; }
  const text = keyboardText(body && typeof body === "object" && "text" in body ? body.text : null);
  if (!text) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid keyboard text", retryable: false }, 400);
  }
  const result = await keyboardRequest(context.env, "POST", text);
  if (result.status !== 200) {
    return context.json(
      { code: result.code, message: result.status === 409 ? "Keyboard busy" : "Keyboard unavailable", retryable: result.status !== 400 },
      result.status as 400 | 409 | 503
    );
  }
  return context.json({ status: "typed" });
});

const segmentFieldNames = [
  "recordingId",
  "segmentIndex",
  "segmentStartedAtMs",
  "segmentDurationMs"
] as const;

// Only non-empty string fields are forwarded to the schema so a client that
// omits a field is distinguishable from one that sends it blank.
function segmentFields(form: FormData): Record<string, string> {
  const raw: Record<string, string> = {};
  for (const name of segmentFieldNames) {
    const value = form.get(name);
    if (typeof value === "string" && value.length > 0) raw[name] = value;
  }
  return raw;
}

app.post("/api/conversations", async (context) => {
  const parsed = createConversationCommand.safeParse(await context.req.json().catch(() => null));
  if (!parsed.success) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid conversation", retryable: false }, 400);
  }

  try {
    const conversation = await createAgentAdapter(context.env).createConversation(
      parsed.data.profile,
      context.get("subject")
    );
    return context.json(conversation, 201);
  } catch (error) {
    const adapterError =
      error instanceof AgentAdapterError
        ? error
        : new AgentAdapterError("Agent service unavailable", true);
    return context.json(
      { code: adapterError.code, message: adapterError.message, retryable: adapterError.retryable },
      adapterError.status as 503
    );
  }
});

app.post("/api/transcriptions", async (context) => {
  const declaredLength = Number(context.req.header("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > 21 * 1024 * 1024) {
    return context.json(
      { code: "PAYLOAD_TOO_LARGE", message: "Voice note too large", retryable: false },
      413
    );
  }
  const form = await context.req.formData();
  const audio = form.get("audio");
  const operationId = form.get("operationId");

  if (!(audio instanceof File) || typeof operationId !== "string") {
    return context.json({ code: "INVALID_REQUEST", message: "Audio required", retryable: false }, 400);
  }

  const segment = transcriptionSegment.safeParse(segmentFields(form));
  if (!segment.success) {
    return context.json(
      { code: "INVALID_REQUEST", message: "Invalid segment metadata", retryable: false },
      400
    );
  }

  if (audio.size > 20 * 1024 * 1024) {
    return context.json({ code: "PAYLOAD_TOO_LARGE", message: "Voice note too large", retryable: false }, 413);
  }

  try {
    const result = await createSpeechAdapter(context.env).transcribe(audio);
    return context.json({
      operationId,
      ...result,
      ...segment.data,
      adapter: context.env.SPEECH_MODE
    });
  } catch (error) {
    const adapterError =
      error instanceof SpeechAdapterError
        ? error
        : new SpeechAdapterError("Transcription unavailable", true);
    return context.json(
      {
        code: "TRANSCRIPTION_FAILED",
        message: adapterError.message,
        retryable: adapterError.retryable
      },
      adapterError.status as 500
    );
  }
});

app.post("/api/speech/synthesis", async (context) => {
  const parsed = synthesizeResponseCommand.safeParse(await context.req.json().catch(() => null));
  if (!parsed.success) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid synthesis", retryable: false }, 400);
  }

  let text: string;
  try {
    const conversation = await new ConversationStateCodec(context.env).open(
      parsed.data.conversationId,
      context.get("subject")
    );
    if (!conversation.conversationKey) throw new Error("invalid conversation");
    text = await new ResponseStateCodec(context.env).open(
      parsed.data.responseId,
      conversation.conversationKey,
      context.get("subject")
    );
  } catch {
    return context.json(
      { code: "RESPONSE_NOT_FOUND", message: "Response unavailable", retryable: false },
      404
    );
  }

  const formats = {
    "audio/mpeg": "mp3",
    "audio/wav": "wav",
    "audio/ogg": "ogg"
  } as const;
  try {
    return await createSpeechAdapter(context.env).synthesize(text, {
      format: formats[parsed.data.format],
      ...(parsed.data.voice === "default" ? {} : { voice: parsed.data.voice })
    });
  } catch (error) {
    const adapterError =
      error instanceof SpeechAdapterError
        ? error
        : new SpeechAdapterError("Synthesis unavailable", true);
    return context.json(
      {
        code: "SYNTHESIS_FAILED",
        message: adapterError.message,
        retryable: adapterError.retryable
      },
      adapterError.status as 500
    );
  }
});

app.post("/api/conversations/:conversationId/turns", async (context) => {
  const body = await context.req.json().catch(() => null);
  const parsed = submitTurnCommand.safeParse({
    ...(typeof body === "object" && body !== null ? body : {}),
    conversationId: context.req.param("conversationId")
  });

  if (!parsed.success) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid turn", retryable: false }, 400);
  }

  try {
    const result = await createAgentAdapter(context.env).submitTurn(
      parsed.data,
      context.get("subject")
    );
    return context.json({ ...result, adapter: context.env.AGENT_MODE }, 202);
  } catch (error) {
    const adapterError =
      error instanceof AgentAdapterError
        ? error
        : new AgentAdapterError("Agent service unavailable", true);
    return context.json(
      { code: adapterError.code, message: adapterError.message, retryable: adapterError.retryable },
      adapterError.status as 503
    );
  }
});

app.post("/api/conversations/:conversationId/inputs/:requestId/answer", async (context) => {
  const body = await context.req.json().catch(() => null);
  const parsed = answerInputCommand.safeParse({
    ...(typeof body === "object" && body !== null ? body : {}),
    conversationId: context.req.param("conversationId"),
    requestId: context.req.param("requestId")
  });
  if (!parsed.success) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid response", retryable: false }, 400);
  }

  try {
    const result = await createAgentAdapter(context.env).answerInput(
      parsed.data,
      context.get("subject")
    );
    return context.json({ ...result, adapter: context.env.AGENT_MODE }, 202);
  } catch (error) {
    const adapterError =
      error instanceof AgentAdapterError
        ? error
        : new AgentAdapterError("Agent service unavailable", true);
    return context.json(
      { code: adapterError.code, message: adapterError.message, retryable: adapterError.retryable },
      adapterError.status as 503
    );
  }
});

app.post("/api/conversations/:conversationId/runs/:runId/interrupt", async (context) => {
  const body = await context.req.json().catch(() => null);
  const parsed = interruptRunCommand.safeParse({
    ...(typeof body === "object" && body !== null ? body : {}),
    conversationId: context.req.param("conversationId"),
    runId: context.req.param("runId")
  });
  if (!parsed.success) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid interrupt", retryable: false }, 400);
  }

  try {
    const result = await createAgentAdapter(context.env).interrupt(
      parsed.data,
      context.get("subject")
    );
    return context.json({ ...result, adapter: context.env.AGENT_MODE }, 202);
  } catch (error) {
    const adapterError =
      error instanceof AgentAdapterError
        ? error
        : new AgentAdapterError("Agent service unavailable", true);
    return context.json(
      { code: adapterError.code, message: adapterError.message, retryable: adapterError.retryable },
      adapterError.status as 503
    );
  }
});

app.notFound((context) =>
  context.json({ code: "INVALID_REQUEST", message: "Route not found", retryable: false }, 404)
);

export default app;
