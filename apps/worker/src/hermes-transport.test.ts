import { describe, expect, it, vi } from "vitest";
import type { Bindings } from "./auth";
import { HermesTransport, HermesTransportError } from "./hermes-transport";

const env: Bindings = {
  AUTH_MODE: "local",
  SPEECH_MODE: "mock",
  AGENT_MODE: "hermes",
  HERMES_BASE_URL: "https://hermes.example.com",
  HERMES_ACCESS_CLIENT_ID: "synthetic-client-id",
  HERMES_ACCESS_CLIENT_SECRET: "synthetic-client-secret"
};

describe("Hermes authenticated transport", () => {
  it("extracts the injected session token using Access service headers", async () => {
    const fetcher = vi.fn(async (_input: string | URL | Request, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      expect(headers.get("cf-access-client-id")).toBe("synthetic-client-id");
      expect(headers.get("cf-access-client-secret")).toBe("synthetic-client-secret");
      return new Response(
        '<script>window.__HERMES_SESSION_TOKEN__="synthetic-session-token";</script>',
        { headers: { "content-type": "text/html" } }
      );
    });

    const transport = new HermesTransport(env, fetcher as typeof fetch);
    await expect(transport.bootstrapToken()).resolves.toBe("synthetic-session-token");
    expect(fetcher).toHaveBeenCalledWith(
      "https://hermes.example.com/",
      expect.objectContaining({ redirect: "manual" })
    );
  });

  it("rejects malformed bootstrap documents without exposing them", async () => {
    const transport = new HermesTransport(
      env,
      (async () => new Response("upstream diagnostic")) as typeof fetch
    );
    await expect(transport.bootstrapToken()).rejects.toMatchObject({
      message: "Agent authentication unavailable",
      retryable: true
    });
  });

  it("rejects invalid origins before fetching", () => {
    expect(
      () => new HermesTransport({ ...env, HERMES_BASE_URL: "https://user@example.com/path" })
    ).toThrow(HermesTransportError);
  });

  it("upgrades with both Hermes and Access authentication", async () => {
    const socket = {} as WebSocket;
    const fetcher = vi.fn(async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      if (url === "https://hermes.example.com/") {
        return new Response(
          '<script>window.__HERMES_SESSION_TOKEN__="token-with-a-space-value";</script>',
          { headers: { "set-cookie": "CF_Authorization=signed-access-cookie; HttpOnly; Secure" } }
        );
      }
      expect(url).toBe("https://hermes.example.com/api/ws?token=token-with-a-space-value");
      const headers = new Headers(init?.headers);
      expect(headers.get("upgrade")).toBe("websocket");
      expect(headers.get("origin")).toBe("https://hermes.example.com");
      expect(headers.get("cookie")).toBe("CF_Authorization=signed-access-cookie");
      return { status: 101, webSocket: socket, body: null } as unknown as Response;
    });

    const transport = new HermesTransport(env, fetcher as typeof fetch);
    await expect(transport.connect()).resolves.toBe(socket);
  });
});
