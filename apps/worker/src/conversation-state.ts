import type { Bindings } from "./auth";

interface StoredConversationState {
  v: 1;
  u: string;
  p: string;
  s?: string;
}

export interface ConversationState {
  profile: string;
  storedSessionId?: string;
}

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const additionalData = encoder.encode("stts-conversation-v1");

function encodeBase64url(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function decodeBase64url(value: string): Uint8Array<ArrayBuffer> {
  if (!/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid conversation");
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

async function subjectFingerprint(subject: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(subject));
  return encodeBase64url(new Uint8Array(digest).slice(0, 16));
}

async function importStateKey(value: string | undefined): Promise<CryptoKey> {
  if (!value) throw new Error("conversation state unavailable");
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = decodeBase64url(value);
  } catch {
    throw new Error("conversation state unavailable");
  }
  if (bytes.byteLength !== 32) throw new Error("conversation state unavailable");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function parseState(value: unknown): StoredConversationState {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid conversation");
  const candidate = value as Partial<StoredConversationState>;
  if (
    candidate.v !== 1 ||
    typeof candidate.u !== "string" ||
    typeof candidate.p !== "string" ||
    !candidate.u ||
    !candidate.p ||
    (candidate.s !== undefined && (typeof candidate.s !== "string" || !candidate.s))
  ) {
    throw new Error("invalid conversation");
  }
  return candidate as StoredConversationState;
}

export class ConversationStateCodec {
  constructor(private readonly env: Bindings) {}

  async seal(state: ConversationState, subject: string): Promise<string> {
    const payload: StoredConversationState = {
      v: 1,
      u: await subjectFingerprint(subject),
      p: state.profile,
      ...(state.storedSessionId ? { s: state.storedSessionId } : {})
    };
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const encrypted = await crypto.subtle.encrypt(
      { name: "AES-GCM", iv, additionalData },
      await importStateKey(this.env.CONVERSATION_STATE_KEY),
      encoder.encode(JSON.stringify(payload))
    );
    return `v1.${encodeBase64url(iv)}.${encodeBase64url(new Uint8Array(encrypted))}`;
  }

  async open(token: string, subject: string): Promise<ConversationState> {
    const parts = token.split(".");
    if (parts.length !== 3 || parts[0] !== "v1" || !parts[1] || !parts[2]) {
      throw new Error("invalid conversation");
    }
    let decrypted: ArrayBuffer;
    try {
      decrypted = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: decodeBase64url(parts[1]), additionalData },
        await importStateKey(this.env.CONVERSATION_STATE_KEY),
        decodeBase64url(parts[2])
      );
    } catch {
      throw new Error("invalid conversation");
    }

    let state: StoredConversationState;
    try {
      state = parseState(JSON.parse(decoder.decode(decrypted)));
    } catch {
      throw new Error("invalid conversation");
    }
    if (state.u !== (await subjectFingerprint(subject))) throw new Error("invalid conversation");
    return { profile: state.p, ...(state.s ? { storedSessionId: state.s } : {}) };
  }
}
