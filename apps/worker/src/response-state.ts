import type { Bindings } from "./auth";

interface ResponseState {
  v: 1;
  u: string;
  c: string;
  t: string;
  x: number;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const additionalData = encoder.encode("stts-response-v1");

function encode(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function decode(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid response");
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return encode(new Uint8Array(digest).slice(0, 16));
}

async function key(value: string | undefined): Promise<CryptoKey> {
  if (!value) throw new Error("response state unavailable");
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = decode(value);
  } catch {
    throw new Error("response state unavailable");
  }
  if (bytes.byteLength !== 32) throw new Error("response state unavailable");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function ttl(value: string | undefined): number {
  const parsed = Number(value ?? "900");
  return Number.isInteger(parsed) && parsed >= 60 && parsed <= 3_600 ? parsed : 900;
}

export class ResponseStateCodec {
  constructor(private readonly env: Bindings) {}

  async seal(text: string, conversationId: string, subject: string): Promise<string> {
    const state: ResponseState = {
      v: 1,
      u: await fingerprint(subject),
      c: await fingerprint(conversationId),
      t: text,
      x: Math.floor(Date.now() / 1000) + ttl(this.env.RESPONSE_TOKEN_TTL_SECONDS)
    };
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const ciphertext = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData },
      await key(this.env.CONVERSATION_STATE_KEY),
      encoder.encode(JSON.stringify(state))
    );
    return `v1.${encode(iv)}.${encode(new Uint8Array(ciphertext))}`;
  }

  async open(token: string, conversationId: string, subject: string): Promise<string> {
    const parts = token.split(".");
    if (parts.length !== 3 || parts[0] !== "v1" || !parts[1] || !parts[2]) {
      throw new Error("invalid response");
    }
    let state: unknown;
    try {
      const plaintext = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: decode(parts[1]), additionalData },
        await key(this.env.CONVERSATION_STATE_KEY),
        decode(parts[2])
      );
      state = JSON.parse(decoder.decode(plaintext));
    } catch {
      throw new Error("invalid response");
    }
    if (!state || typeof state !== "object" || Array.isArray(state)) throw new Error("invalid response");
    const candidate = state as Partial<ResponseState>;
    if (
      candidate.v !== 1 ||
      typeof candidate.u !== "string" ||
      typeof candidate.c !== "string" ||
      typeof candidate.t !== "string" ||
      !candidate.t ||
      typeof candidate.x !== "number" ||
      !Number.isFinite(candidate.x)
    ) {
      throw new Error("invalid response");
    }
    if (
      candidate.u !== (await fingerprint(subject)) ||
      candidate.c !== (await fingerprint(conversationId)) ||
      candidate.x <= Math.floor(Date.now() / 1000)
    ) {
      throw new Error("invalid response");
    }
    return candidate.t;
  }
}
