import { afterEach, describe, expect, it, vi } from "vitest";
import app from "./index";
import type { Bindings } from "./auth";

const env: Bindings = {
  AUTH_MODE: "local",
  SPEECH_MODE: "mock",
  AGENT_MODE: "mock",
  KEYBOARD_BASE_URL: "https://keyboard.cdslash.com",
  KEYBOARD_ACCESS_CLIENT_ID: "device-id",
  KEYBOARD_ACCESS_CLIENT_SECRET: "access-secret",
  KEYBOARD_BRIDGE_TOKEN: "bridge-secret"
};

const request = (text: unknown, configuration = env) => app.request(
  "/api/keyboard/type",
  { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text }) },
  configuration
);

describe("keyboard route", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("requires identity before reaching the device", async () => {
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    expect((await request("hello", { ...env, AUTH_MODE: "access" })).status).toBe(401);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("rejects unsupported characters and oversized inputs without contacting the bridge", async () => {
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    for (const text of ["", "é", "\u0000", "x".repeat(4097)]) {
      expect((await request(text)).status).toBe(400);
    }
    expect(fetch).not.toHaveBeenCalled();
  });

  it("forwards text only to the configured tunnel with its service credentials", async () => {
    const fetch = vi.fn().mockResolvedValue(new Response('{"status":"ok"}', { status: 200 }));
    vi.stubGlobal("fetch", fetch);
    expect((await request("Hello\r\nworld")).status).toBe(200);
    const [url, options] = fetch.mock.calls[0] as [URL, RequestInit];
    expect(url.href).toBe("https://keyboard.cdslash.com/type");
    expect(options.redirect).toBe("manual");
    expect(options.body).toBe(JSON.stringify({ text: "Hello\nworld" }));
    expect(new Headers(options.headers).get("Authorization")).toBe("Bearer bridge-secret");
    expect(new Headers(options.headers).get("CF-Access-Client-Secret")).toBe("access-secret");
  });

  it("reports offline on missing configuration, redirects, and transport failures", async () => {
    expect((await request("Hello", { ...env, KEYBOARD_BASE_URL: undefined })).status).toBe(503);
    const fetch = vi.fn().mockResolvedValue(new Response(null, { status: 302 }));
    vi.stubGlobal("fetch", fetch);
    expect((await request("Hello")).status).toBe(503);
    fetch.mockRejectedValueOnce(new Error("network"));
    expect((await request("Hello")).status).toBe(503);
  });

  it("checks serial availability via the authenticated tunnel", async () => {
    const fetch = vi.fn().mockResolvedValue(new Response(null, { status: 200 }));
    vi.stubGlobal("fetch", fetch);
    const response = await app.request("/api/keyboard", {}, env);
    expect(await response.json()).toEqual({ available: true });
    expect((fetch.mock.calls[0] as [URL])[0].pathname).toBe("/health");
  });
});
