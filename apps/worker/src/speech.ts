import type { Bindings } from "./auth";

export interface TranscriptionResult {
  text: string;
  language?: string;
  duration?: number;
}

export interface SynthesisOptions {
  format: "mp3" | "wav" | "ogg";
  speed?: number;
  voice?: string;
}

export interface SpeechAdapter {
  transcribe(audio: File, language?: string): Promise<TranscriptionResult>;
  synthesize(text: string, options: SynthesisOptions): Promise<Response>;
}

export class SpeechAdapterError extends Error {
  constructor(
    message: string,
    readonly retryable: boolean,
    readonly status = 502
  ) {
    super(message);
  }
}

function checkedBaseUrl(value: string): string {
  const url = new URL(value);
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    throw new SpeechAdapterError("Speech service unavailable", false, 503);
  }
  return url.href.replace(/\/$/, "");
}

function timeout(value: string | undefined): number {
  const parsed = Number(value ?? "60000");
  return Number.isInteger(parsed) && parsed >= 1_000 && parsed <= 120_000 ? parsed : 60_000;
}

function safeAudioFilename(audio: File): string {
  const mediaType = audio.type.toLowerCase().split(";", 1)[0] ?? "";
  const extensions: Record<string, string> = {
    "audio/aac": "aac",
    "audio/flac": "flac",
    "audio/m4a": "m4a",
    "audio/mp4": "m4a",
    "audio/mpeg": "mp3",
    "audio/ogg": "ogg",
    "audio/opus": "opus",
    "audio/wav": "wav",
    "audio/webm": "webm",
    "audio/x-wav": "wav"
  };
  const extension = extensions[mediaType];
  if (!extension) throw new SpeechAdapterError("Unsupported audio", false, 400);
  return `voice-note.${extension}`;
}

export class OpenAiSpeechAdapter implements SpeechAdapter {
  private readonly baseUrl: string;
  private readonly timeoutMs: number;

  constructor(private readonly env: Bindings) {
    if (!env.SPEECH_BASE_URL || !env.SPEECH_API_KEY) {
      throw new SpeechAdapterError("Speech service unavailable", false, 503);
    }
    this.baseUrl = checkedBaseUrl(env.SPEECH_BASE_URL);
    this.timeoutMs = timeout(env.SPEECH_TIMEOUT_MS);
  }

  private headers(): HeadersInit {
    return {
      accept: "application/json",
      authorization: `Bearer ${this.env.SPEECH_API_KEY}`
    };
  }

  async transcribe(audio: File, language?: string): Promise<TranscriptionResult> {
    const form = new FormData();
    form.set("file", audio, safeAudioFilename(audio));
    form.set("model", "Qwen/Qwen3-ASR-1.7B-hf");
    form.set("response_format", "verbose_json");
    if (language) form.set("language", language);

    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/v1/audio/transcriptions`, {
        method: "POST",
        headers: this.headers(),
        body: form,
        redirect: "error",
        signal: AbortSignal.timeout(this.timeoutMs)
      });
    } catch (error) {
      console.error("speech_transcription_fetch_failed", {
        name: error instanceof Error ? error.name : "unknown",
        message: error instanceof Error ? error.message.slice(0, 200) : "unknown"
      });
      throw new SpeechAdapterError("Transcription unavailable", true);
    }

    if (!response.ok) {
      throw new SpeechAdapterError("Transcription failed", response.status >= 500, 502);
    }
    const declaredLength = Number(response.headers.get("content-length") ?? "0");
    if (declaredLength > 256 * 1024) throw new SpeechAdapterError("Invalid transcription response", true);

    let payload: unknown;
    try {
      const body = await response.text();
      if (body.length > 256 * 1024) throw new Error("response too large");
      payload = JSON.parse(body);
    } catch {
      throw new SpeechAdapterError("Invalid transcription response", true);
    }
    if (!payload || typeof payload !== "object" || !("text" in payload) || typeof payload.text !== "string") {
      throw new SpeechAdapterError("Invalid transcription response", true);
    }

    const result: TranscriptionResult = { text: payload.text };
    if ("language" in payload && typeof payload.language === "string") result.language = payload.language;
    if ("duration" in payload && typeof payload.duration === "number") result.duration = payload.duration;
    return result;
  }

  async synthesize(text: string, options: SynthesisOptions): Promise<Response> {
    let response: Response;
    try {
      response = await fetch(`${this.baseUrl}/v1/audio/speech`, {
        method: "POST",
        headers: { ...this.headers(), "content-type": "application/json" },
        body: JSON.stringify({
          model: "kokoro",
          input: text,
          voice: options.voice ?? "af_heart",
          response_format: options.format,
          speed: options.speed ?? 1
        }),
        redirect: "error",
        signal: AbortSignal.timeout(this.timeoutMs)
      });
    } catch (error) {
      console.error("speech_synthesis_fetch_failed", {
        name: error instanceof Error ? error.name : "unknown",
        message: error instanceof Error ? error.message.slice(0, 200) : "unknown"
      });
      throw new SpeechAdapterError("Synthesis unavailable", true);
    }
    if (!response.ok || !response.headers.get("content-type")?.startsWith("audio/")) {
      response.body?.cancel();
      throw new SpeechAdapterError("Synthesis failed", response.status >= 500, 502);
    }

    return new Response(response.body, {
      status: 200,
      headers: {
        "cache-control": "no-store",
        "content-type": response.headers.get("content-type") ?? "application/octet-stream"
      }
    });
  }
}

export class MockSpeechAdapter implements SpeechAdapter {
  async transcribe(_audio: File): Promise<TranscriptionResult> {
    return { text: "Summarize my next priorities.", language: "en" };
  }

  async synthesize(): Promise<Response> {
    throw new SpeechAdapterError("Mock synthesis unavailable", false, 501);
  }
}

export function createSpeechAdapter(env: Bindings): SpeechAdapter {
  if (env.SPEECH_MODE === "mock") return new MockSpeechAdapter();
  if (env.SPEECH_MODE === "live") return new OpenAiSpeechAdapter(env);
  throw new SpeechAdapterError("Speech service unavailable", false, 503);
}
