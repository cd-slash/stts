import { createRemoteJWKSet, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from "jose";
import type { Context, Next } from "hono";

export interface Bindings {
  AUTH_MODE: "local" | "access";
  SPEECH_MODE: "mock" | "live";
  AGENT_MODE: "mock" | "hermes";
  ACCESS_AUD?: string;
  ACCESS_ISSUER?: string;
  HERMES_BASE_URL?: string;
  HERMES_ACCESS_CLIENT_ID?: string;
  HERMES_ACCESS_CLIENT_SECRET?: string;
  HERMES_TIMEOUT_MS?: string;
  HERMES_TURN_TIMEOUT_MS?: string;
  CONVERSATION_STATE_KEY?: string;
  RESPONSE_TOKEN_TTL_SECONDS?: string;
  SPEECH_BASE_URL?: string;
  SPEECH_API_KEY?: string;
  SPEECH_TIMEOUT_MS?: string;
  KEYBOARD_BASE_URL?: string;
  KEYBOARD_ACCESS_CLIENT_ID?: string;
  KEYBOARD_ACCESS_CLIENT_SECRET?: string;
  KEYBOARD_BRIDGE_TOKEN?: string;
  KEYBOARD_OWNER_SUBJECT?: string;
}

export interface Variables {
  subject: string;
}

const remoteKeys = new Map<string, JWTVerifyGetKey>();

function normalizedIssuer(value: string): string {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash
  ) {
    throw new Error("invalid Access issuer");
  }
  return url.origin;
}

function resolverFor(issuer: string): JWTVerifyGetKey {
  const cached = remoteKeys.get(issuer);
  if (cached) return cached;
  const resolver = createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`));
  remoteKeys.set(issuer, resolver);
  return resolver;
}

export async function verifyAccessJwt(
  token: string,
  configuration: { audience: string; issuer: string },
  resolver?: JWTVerifyGetKey,
  now = Math.floor(Date.now() / 1000)
): Promise<JWTPayload & { sub: string }> {
  const issuer = normalizedIssuer(configuration.issuer);
  const { payload } = await jwtVerify(token, resolver ?? resolverFor(issuer), {
    algorithms: ["RS256"],
    audience: configuration.audience,
    issuer,
    clockTolerance: 30,
    currentDate: new Date(now * 1000)
  });
  const subject =
    typeof payload.sub === "string" && payload.sub.length > 0
      ? payload.sub
      : typeof payload.common_name === "string" && payload.common_name.length > 0
        ? `service:${payload.common_name}`
        : undefined;
  if (!subject) {
    throw new Error("invalid Access subject");
  }
  return { ...payload, sub: subject } as JWTPayload & { sub: string };
}

export async function requireIdentity(
  context: Context<{ Bindings: Bindings; Variables: Variables }>,
  next: Next
) {
  if (context.env.AUTH_MODE === "local") {
    context.set("subject", "local-owner");
    await next();
    return;
  }

  const assertion = context.req.header("cf-access-jwt-assertion");
  if (!assertion) {
    return context.json({ code: "AUTH_REQUIRED", message: "Sign in required", retryable: false }, 401);
  }
  if (!context.env.ACCESS_AUD || !context.env.ACCESS_ISSUER) {
    return context.json(
      { code: "UPSTREAM_UNAVAILABLE", message: "Access unavailable", retryable: false },
      503
    );
  }

  try {
    const claims = await verifyAccessJwt(assertion, {
      audience: context.env.ACCESS_AUD,
      issuer: context.env.ACCESS_ISSUER
    });
    context.set("subject", claims.sub);
    await next();
  } catch {
    return context.json({ code: "AUTH_REQUIRED", message: "Sign in required", retryable: false }, 401);
  }
}
