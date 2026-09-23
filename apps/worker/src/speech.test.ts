import { afterEach, describe, expect, it, vi } from "vitest";
import type { Bindings } from "./auth";
import { OpenAiSpeechAdapter, SpeechAdapterError } from "./speech";

const env: Bindings = {
  AUTH_MODE: "local",
  SPEECH_MODE: "live",
  AGENT_MODE: "mock",
  SPEECH_BASE_URL: "https://speech.example.com",
  SPEECH_API_KEY: "synthetic-test-key"
};

afterEach(() => vi.unstubAllGlobals());

describe("OpenAI-compatible speech adapter", () => {
  it("sends the verified Qwen transcription contract", async () => {
    const fetchMock = vi.fn(async (_input: string | URL | Request, init?: RequestInit) => {
      const form = init?.body as FormData;
      expect(form.get("model")).toBe("Qwen/Qwen3-ASR-1.7B-hf");
      expect(form.get("response_format")).toBe("verbose_json");
      expect(new Headers(init?.headers).get("authorization")).toBe("Bearer synthetic-test-key");
      return Response.json({ text: "hello", language: "en", duration: 1.2 });
    });
    vi.stubGlobal("fetch", fetchMock);

    const adapter = new OpenAiSpeechAdapter(env);
    await expect(
      adapter.transcribe(new File(["audio"], "unsafe-name", { type: "audio/webm;codecs=opus" }))
    ).resolves.toEqual({
      text: "hello",
      language: "en",
      duration: 1.2
    });
    expect(fetchMock).toHaveBeenCalledWith(
      "https://speech.example.com/v1/audio/transcriptions",
      expect.objectContaining({ method: "POST", redirect: "manual" })
    );
  });

  it("does not expose upstream errors", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("secret diagnostic", { status: 503 })));
    const adapter = new OpenAiSpeechAdapter(env);
    const error = await adapter
      .transcribe(new File(["audio"], "note.webm", { type: "audio/webm" }))
      .catch((caught: unknown) => caught);
    expect(error).toBeInstanceOf(SpeechAdapterError);
    expect((error as Error).message).toBe("Transcription failed");
  });

  it("rejects unsupported audio before fetching", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const adapter = new OpenAiSpeechAdapter(env);
    await expect(
      adapter.transcribe(new File(["audio"], "note.bin", { type: "application/octet-stream" }))
    ).rejects.toMatchObject({ message: "Unsupported audio", status: 400 });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("returns only safe synthesis headers", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        new Response("audio", {
          headers: { "content-type": "audio/mpeg", "set-cookie": "upstream=secret" }
        })
      )
    );
    const adapter = new OpenAiSpeechAdapter(env);
    const response = await adapter.synthesize("hello", { format: "mp3" });
    expect(response.headers.get("content-type")).toBe("audio/mpeg");
    expect(response.headers.get("set-cookie")).toBeNull();
  });
});
