import { describe, expect, it } from "vitest";
import app from "./index";

const env = { AUTH_MODE: "local" as const };

describe("worker API", () => {
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
});
