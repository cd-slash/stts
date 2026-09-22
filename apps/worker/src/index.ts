import {
  answerInputCommand,
  createConversationCommand,
  interruptRunCommand,
  synthesizeResponseCommand,
  submitTurnCommand
} from "@stts/protocol";
import { Hono } from "hono";
import { AgentAdapterError, createAgentAdapter } from "./agent";
import { requireIdentity, type Bindings, type Variables } from "./auth";
import { ResponseStateCodec } from "./response-state";
import { createSpeechAdapter, SpeechAdapterError } from "./speech";

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

app.use("/api/*", requireIdentity);
app.get("/api/health", (context) => context.json({ status: "ok" }));

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
  const form = await context.req.formData();
  const audio = form.get("audio");
  const operationId = form.get("operationId");

  if (!(audio instanceof File) || typeof operationId !== "string") {
    return context.json({ code: "INVALID_REQUEST", message: "Audio required", retryable: false }, 400);
  }

  if (audio.size > 20 * 1024 * 1024) {
    return context.json({ code: "PAYLOAD_TOO_LARGE", message: "Voice note too large", retryable: false }, 413);
  }

  try {
    const result = await createSpeechAdapter(context.env).transcribe(audio);
    return context.json({ operationId, ...result, adapter: context.env.SPEECH_MODE });
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
    text = await new ResponseStateCodec(context.env).open(
      parsed.data.responseId,
      parsed.data.conversationId,
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
