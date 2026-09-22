import type { Context, Next } from "hono";

export interface Bindings {
  AUTH_MODE: "local" | "access";
  ACCESS_AUD?: string;
  HERMES_BASE_URL?: string;
  SPEECH_BASE_URL?: string;
}

export interface Variables {
  subject: string;
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
  const email = context.req.header("cf-access-authenticated-user-email");

  if (!assertion || !email) {
    return context.json({ code: "AUTH_REQUIRED", message: "Sign in required", retryable: false }, 401);
  }

  // Deployment adds cryptographic JWT verification against ACCESS_AUD before
  // AUTH_MODE may be switched to access. Header presence alone is not sufficient.
  return context.json(
    { code: "AUTH_REQUIRED", message: "Access verification not configured", retryable: false },
    503
  );
}
