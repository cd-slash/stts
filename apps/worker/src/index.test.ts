import { describe, expect, it } from "vitest";
import app from "./index";

const env = {
  AUTH_MODE: "local" as const,
  SPEECH_MODE: "mock" as const,
  AGENT_MODE: "mock" as const
};

describe("worker API", () => {
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
});
