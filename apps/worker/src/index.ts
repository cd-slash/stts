import { createConversationCommand, submitTurnCommand } from "@stts/protocol";
import { Hono } from "hono";
import { requireIdentity, type Bindings, type Variables } from "./auth";
import { runMockTurn } from "./mock-agent";

const app = new Hono<{ Bindings: Bindings; Variables: Variables }>();

app.get("/api/health", (context) => context.json({ status: "ok" }));
app.use("/api/*", requireIdentity);

app.post("/api/conversations", async (context) => {
  const parsed = createConversationCommand.safeParse(await context.req.json().catch(() => null));
  if (!parsed.success) {
    return context.json({ code: "INVALID_REQUEST", message: "Invalid conversation", retryable: false }, 400);
  }

  return context.json(
    {
      conversationId: crypto.randomUUID(),
      profile: parsed.data.profile
    },
    201
  );
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

  return context.json({
    operationId,
    text: "Summarize my next priorities.",
    language: "en",
    adapter: "mock"
  });
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

  return context.json({ events: runMockTurn(parsed.data), adapter: "mock" }, 202);
});

app.notFound((context) =>
  context.json({ code: "INVALID_REQUEST", message: "Route not found", retryable: false }, 404)
);

export default app;
