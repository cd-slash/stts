import type { Bindings } from "./auth";

const MAX_BOOTSTRAP_BYTES = 128 * 1024;
const SESSION_TOKEN_PATTERN = /window\.__HERMES_SESSION_TOKEN__\s*=\s*("(?:[^"\\]|\\.)*")\s*;/;

export class HermesTransportError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean
  ) {
    super(message);
  }
}

function baseUrl(value: string): URL {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  ) {
    throw new HermesTransportError("Agent service unavailable", false);
  }
  return url;
}

function timeout(value: string | undefined): number {
  const parsed = Number(value ?? "15000");
  return Number.isInteger(parsed) && parsed >= 1_000 && parsed <= 30_000 ? parsed : 15_000;
}

function parseBootstrapToken(document: string): string {
  const match = SESSION_TOKEN_PATTERN.exec(document);
  if (!match?.[1]) throw new HermesTransportError("Agent authentication unavailable", true);

  let token: unknown;
  try {
    token = JSON.parse(match[1]);
  } catch {
    throw new HermesTransportError("Agent authentication unavailable", true);
  }
  if (typeof token !== "string" || token.length < 16 || token.length > 4_096) {
    throw new HermesTransportError("Agent authentication unavailable", true);
  }
  return token;
}

export class HermesTransport {
  private readonly origin: URL;
  private readonly timeoutMs: number;

  constructor(
    private readonly env: Bindings,
    private readonly fetcher: typeof fetch = fetch
  ) {
    if (
      !env.HERMES_BASE_URL ||
      !env.HERMES_ACCESS_CLIENT_ID ||
      !env.HERMES_ACCESS_CLIENT_SECRET
    ) {
      throw new HermesTransportError("Agent service unavailable", false);
    }
    this.origin = baseUrl(env.HERMES_BASE_URL);
    this.timeoutMs = timeout(env.HERMES_TIMEOUT_MS);
  }

  private accessHeaders(): Record<string, string> {
    return {
      "CF-Access-Client-Id": this.env.HERMES_ACCESS_CLIENT_ID!,
      "CF-Access-Client-Secret": this.env.HERMES_ACCESS_CLIENT_SECRET!
    };
  }

  async bootstrapToken(): Promise<string> {
    let response: Response;
    try {
      response = await this.fetcher(this.origin.href, {
        headers: { ...this.accessHeaders(), accept: "text/html" },
        redirect: "manual",
        signal: AbortSignal.timeout(this.timeoutMs)
      });
    } catch {
      console.error("hermes_bootstrap_fetch_failed");
      throw new HermesTransportError("Agent authentication unavailable", true);
    }
    if (!response.ok) {
      console.error("hermes_bootstrap_rejected", { status: response.status });
      response.body?.cancel();
      throw new HermesTransportError("Agent authentication unavailable", response.status >= 500);
    }
    const declaredLength = Number(response.headers.get("content-length") ?? "0");
    if (declaredLength > MAX_BOOTSTRAP_BYTES) {
      response.body?.cancel();
      throw new HermesTransportError("Agent authentication unavailable", true);
    }

    const document = await response.text();
    if (document.length > MAX_BOOTSTRAP_BYTES) {
      throw new HermesTransportError("Agent authentication unavailable", true);
    }
    try {
      return parseBootstrapToken(document);
    } catch (error) {
      console.error("hermes_bootstrap_invalid", { bytes: document.length });
      throw error;
    }
  }

  async connect(): Promise<WebSocket> {
    const token = await this.bootstrapToken();
    const websocketUrl = new URL("/api/ws", this.origin);
    websocketUrl.protocol = "wss:";
    websocketUrl.searchParams.set("token", token);

    let response: Response;
    try {
      response = await this.fetcher(websocketUrl.href, {
        headers: {
          ...this.accessHeaders(),
          Origin: this.origin.origin,
          Upgrade: "websocket"
        },
        redirect: "manual",
        signal: AbortSignal.timeout(this.timeoutMs)
      });
    } catch {
      throw new HermesTransportError("Agent service unavailable", true);
    }

    if (response.status !== 101 || !response.webSocket) {
      response.body?.cancel();
      throw new HermesTransportError("Agent service unavailable", response.status >= 500);
    }
    return response.webSocket;
  }
}
