import { createLocalJWKSet } from "jose";
import { describe, expect, it } from "vitest";
import { verifyAccessJwt } from "./auth";

function base64url(value: Uint8Array | string) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

async function fixture(overrides: Record<string, unknown> = {}) {
  const pair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"]
  );
  const publicJwk = {
    ...(await crypto.subtle.exportKey("jwk", pair.publicKey)),
    kid: "key-1",
    alg: "RS256"
  };
  const header = base64url(JSON.stringify({ alg: "RS256", kid: "key-1", typ: "JWT" }));
  const payload = base64url(
    JSON.stringify({
      aud: ["audience-1"],
      exp: 2_000_000_000,
      iat: 1_900_000_000,
      iss: "https://example.cloudflareaccess.com",
      sub: "owner-id",
      ...overrides
    })
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    pair.privateKey,
    new TextEncoder().encode(`${header}.${payload}`)
  );
  return {
    token: `${header}.${payload}.${base64url(new Uint8Array(signature))}`,
    resolver: createLocalJWKSet({ keys: [publicJwk] })
  };
}

describe("Access JWT verification", () => {
  it("verifies signature, issuer, audience, and time", async () => {
    const { token, resolver } = await fixture();
    const claims = await verifyAccessJwt(
      token,
      { audience: "audience-1", issuer: "https://example.cloudflareaccess.com" },
      resolver,
      1_950_000_000
    );
    expect(claims.sub).toBe("owner-id");
  });

  it("rejects an expired assertion", async () => {
    const { token, resolver } = await fixture({ exp: 1_900_000_000 });
    await expect(
      verifyAccessJwt(
        token,
        { audience: "audience-1", issuer: "https://example.cloudflareaccess.com" },
        resolver,
        1_950_000_000
      )
    ).rejects.toMatchObject({ code: "ERR_JWT_EXPIRED" });
  });

  it("binds an Access service token to its signed common name", async () => {
    const { token, resolver } = await fixture({ sub: "", common_name: "acceptance-token" });
    const claims = await verifyAccessJwt(
      token,
      { audience: "audience-1", issuer: "https://example.cloudflareaccess.com" },
      resolver,
      1_950_000_000
    );
    expect(claims.sub).toBe("service:acceptance-token");
  });
});
