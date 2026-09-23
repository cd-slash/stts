import { afterEach, describe, expect, it, vi } from "vitest";
import { ResponseStateCodec } from "./response-state";
import { ConversationStateCodec } from "./conversation-state";
import app from "./index";

const env = {
  AUTH_MODE: "local" as const,
  SPEECH_MODE: "mock" as const,
  AGENT_MODE: "mock" as const
};

describe("worker API", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("protects health routes in Access mode", async () => {
    const response = await app.request("/api/health", {}, { ...env, AUTH_MODE: "access" });
    expect(response.status).toBe(401);
  });

  it("creates a conversation", async () => {
    const response = await app.request(
      "/api/conversations",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ operationId: "op_1", profile: "chief-of-staff" })
      },
      env
    );

    expect(response.status).toBe(201);
    await expect(response.json()).resolves.toMatchObject({ profile: "chief-of-staff" });
  });

  it("rejects an empty turn", async () => {
    const response = await app.request(
      "/api/conversations/conv_1/turns",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operationId: "op_1",
          input: { kind: "text", text: "" },
          profileOverride: null,
          clientContext: { timezone: "UTC", locale: "en" }
        })
      },
      env
    );

    expect(response.status).toBe(400);
  });

  it("transcribes through the configured adapter", async () => {
    const form = new FormData();
    form.set("operationId", "op_audio");
    form.set("audio", new File(["audio"], "note.webm", { type: "audio/webm" }));
    const response = await app.request(
      "/api/transcriptions",
      { method: "POST", body: form },
      env
    );

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      operationId: "op_audio",
      adapter: "mock"
    });
  });

  it("echoes ordering metadata for a meeting segment", async () => {
    const form = new FormData();
    form.set("operationId", "op_segment");
    form.set("recordingId", "meeting-7f3a");
    form.set("segmentIndex", "4");
    form.set("segmentStartedAtMs", "180000");
    form.set("segmentDurationMs", "45000");
    form.set("audio", new File(["audio"], "segment.m4a", { type: "audio/mp4" }));
    const response = await app.request("/api/transcriptions", { method: "POST", body: form }, env);

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toMatchObject({
      operationId: "op_segment",
      recordingId: "meeting-7f3a",
      segmentIndex: 4,
      segmentStartedAtMs: 180000,
      segmentDurationMs: 45000
    });
  });

  it("rejects a segment index without its recording", async () => {
    const form = new FormData();
    form.set("operationId", "op_segment");
    form.set("segmentIndex", "4");
    form.set("audio", new File(["audio"], "segment.m4a", { type: "audio/mp4" }));
    const response = await app.request("/api/transcriptions", { method: "POST", body: form }, env);

    expect(response.status).toBe(400);
    await expect(response.json()).resolves.toMatchObject({ code: "INVALID_REQUEST" });
  });

  it("rejects segment timing without a segment identity", async () => {
    const form = new FormData();
    form.set("operationId", "op_segment");
    form.set("segmentStartedAtMs", "0");
    form.set("segmentDurationMs", "1000");
    form.set("audio", new File(["audio"], "segment.m4a", { type: "audio/mp4" }));
    const response = await app.request("/api/transcriptions", { method: "POST", body: form }, env);

    expect(response.status).toBe(400);
  });

  it("rejects an unsafe recording identifier", async () => {
    const form = new FormData();
    form.set("operationId", "op_segment");
    form.set("recordingId", "../../etc/passwd");
    form.set("segmentIndex", "0");
    form.set("audio", new File(["audio"], "segment.m4a", { type: "audio/mp4" }));
    const response = await app.request("/api/transcriptions", { method: "POST", body: form }, env);

    expect(response.status).toBe(400);
  });

  it("accepts a meeting transcript surface and rejects an oversized interactive turn", async () => {
    const meeting = await app.request(
      "/api/conversations/conv_1/turns",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operationId: "op_meeting",
          input: { kind: "text", text: "x".repeat(60_000) },
          profileOverride: null,
          surface: "meeting-transcript",
          clientContext: { timezone: "UTC", locale: "en" }
        })
      },
      env
    );
    expect(meeting.status).toBe(202);

    const interactive = await app.request(
      "/api/conversations/conv_1/turns",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operationId: "op_voice",
          input: { kind: "text", text: "x".repeat(60_000) },
          profileOverride: null,
          clientContext: { timezone: "UTC", locale: "en" }
        })
      },
      env
    );
    expect(interactive.status).toBe(400);
  });

  it("creates an opaque owner-bound handle in Hermes mode", async () => {
    const response = await app.request(
      "/api/conversations",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ operationId: "op_1", profile: "chief-of-staff" })
      },
      {
        ...env,
        AGENT_MODE: "hermes",
        CONVERSATION_STATE_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
      }
    );

    expect(response.status).toBe(201);
    const body = (await response.json()) as { conversationId: string };
    expect(body.conversationId).toMatch(/^v1\./);
    expect(body.conversationId).not.toContain("default");
  });

  it("fails closed when Hermes state encryption is unavailable", async () => {
    const response = await app.request(
      "/api/conversations",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ operationId: "op_1", profile: "chief-of-staff" })
      },
      { ...env, AGENT_MODE: "hermes" }
    );

    expect(response.status).toBe(503);
    await expect(response.json()).resolves.toMatchObject({ code: "UPSTREAM_UNAVAILABLE" });
  });

  it("accepts normalized mock input responses", async () => {
    const response = await app.request(
      "/api/conversations/conv_1/inputs/request_1/answer",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operationId: "op_answer",
          answer: { kind: "deny" }
        })
      },
      env
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toMatchObject({
      conversationId: "conv_1",
      events: [{ type: "input.resolved", data: { requestId: "request_1" } }]
    });
  });

  it("accepts normalized mock interruptions", async () => {
    const response = await app.request(
      "/api/conversations/conv_1/runs/run_1/interrupt",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ operationId: "op_interrupt", reason: "user_redirect" })
      },
      env
    );

    expect(response.status).toBe(202);
    await expect(response.json()).resolves.toMatchObject({
      events: [{ type: "run.interrupted", data: { runId: "run_1" } }]
    });
  });

  it("rejects unbound response synthesis", async () => {
    const response = await app.request(
      "/api/speech/synthesis",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operationId: "op_speech",
          conversationId: "conv_1",
          responseId: "invalid-response",
          voice: "default",
          format: "audio/mpeg"
        })
      },
      { ...env, CONVERSATION_STATE_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toMatchObject({ code: "RESPONSE_NOT_FOUND" });
  });

  it("synthesizes only text recovered from a bound response ID", async () => {
    const liveEnv = {
      ...env,
      SPEECH_MODE: "live" as const,
      CONVERSATION_STATE_KEY: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      SPEECH_BASE_URL: "https://speech.example.com",
      SPEECH_API_KEY: "synthetic-key"
    };
    const conversationKey = "stable-conversation-key";
    const conversationId = await new ConversationStateCodec(liveEnv).seal(
      { profile: "default", conversationKey },
      "local-owner"
    );
    const responseId = await new ResponseStateCodec(liveEnv).seal(
      "Authoritative response",
      conversationKey,
      "local-owner"
    );
    const fetcher = vi.fn(async (_input: string | URL | Request, init?: RequestInit) => {
      expect(JSON.parse(String(init?.body))).toMatchObject({ input: "Authoritative response" });
      return new Response("audio", { headers: { "content-type": "audio/mpeg" } });
    });
    vi.stubGlobal("fetch", fetcher);

    const response = await app.request(
      "/api/speech/synthesis",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          operationId: "op_speech",
          conversationId,
          responseId,
          voice: "default",
          format: "audio/mpeg"
        })
      },
      liveEnv
    );

    expect(response.status).toBe(200);
    expect(response.headers.get("content-type")).toBe("audio/mpeg");
    expect(fetcher).toHaveBeenCalledOnce();
  });
});
