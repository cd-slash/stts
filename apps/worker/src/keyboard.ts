import type { Bindings } from "./auth";

export const MAX_KEYBOARD_TEXT = 4096;

export function keyboardText(value: unknown): string | undefined {
  if (typeof value !== "string" || !value || value.length > MAX_KEYBOARD_TEXT) return undefined;
  // The serial HID protocol currently supports US-layout printable ASCII, tab and enter.
  if (!/^[\x20-\x7e\t\r\n]+$/.test(value)) return undefined;
  return value.replace(/\r\n?/g, "\n");
}

function configuration(env: Bindings): { url: URL; headers: Headers } | undefined {
  if (!env.KEYBOARD_BASE_URL || !env.KEYBOARD_ACCESS_CLIENT_ID ||
      !env.KEYBOARD_ACCESS_CLIENT_SECRET || !env.KEYBOARD_BRIDGE_TOKEN) return undefined;
  try {
    const url = new URL(env.KEYBOARD_BASE_URL);
    if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash ||
        (url.pathname !== "/" && url.pathname !== "")) return undefined;
    const headers = new Headers({
      "CF-Access-Client-Id": env.KEYBOARD_ACCESS_CLIENT_ID,
      "CF-Access-Client-Secret": env.KEYBOARD_ACCESS_CLIENT_SECRET,
      Authorization: `Bearer ${env.KEYBOARD_BRIDGE_TOKEN}`
    });
    return { url, headers };
  } catch {
    return undefined;
  }
}

export async function keyboardRequest(
  env: Bindings,
  method: "GET" | "POST",
  text?: string
): Promise<{ status: number; code?: string }> {
  const config = configuration(env);
  if (!config) return { status: 503, code: "KEYBOARD_UNAVAILABLE" };
  const { url, headers } = config;
  url.pathname = method === "GET" ? "/health" : "/type";
  if (method === "POST") headers.set("content-type", "application/json");
  try {
    const response = await fetch(url, {
      method,
      headers,
      redirect: "manual",
      ...(method === "POST" ? { body: JSON.stringify({ text }) } : {}),
      signal: AbortSignal.timeout(method === "POST" ? 35_000 : 5_000)
    });
    if (response.ok) return { status: 200 };
    if (response.status === 400) return { status: 400, code: "INVALID_REQUEST" };
    if (response.status === 409) return { status: 409, code: "KEYBOARD_BUSY" };
    return { status: 503, code: "KEYBOARD_UNAVAILABLE" };
  } catch {
    return { status: 503, code: "KEYBOARD_UNAVAILABLE" };
  }
}
