import { useEffect, useRef, useState } from "react";
import { speakMock, stopMockSpeech, submitMock, transcribeMock } from "./mock-client";

type Phase = "idle" | "recording" | "transcribing" | "responding" | "ready" | "error";

interface Message {
  id: string;
  role: "user" | "coordinator";
  text: string;
  specialist?: string;
  activity?: string;
}

function formatDuration(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function phaseLabel(phase: Phase) {
  const labels: Record<Phase, string> = {
    idle: "Ready",
    recording: "Recording",
    transcribing: "Transcribing",
    responding: "Chief of Staff",
    ready: "Ready",
    error: "Voice unavailable"
  };
  return labels[phase];
}

export function App() {
  const [phase, setPhase] = useState<Phase>("idle");
  const [seconds, setSeconds] = useState(0);
  const [messages, setMessages] = useState<Message[]>([]);
  const [draft, setDraft] = useState("");
  const [lastReply, setLastReply] = useState("");
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const endRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (phase !== "recording") return;
    const timer = window.setInterval(() => setSeconds((value) => value + 1), 1000);
    return () => window.clearInterval(timer);
  }, [phase]);

  useEffect(() => {
    endRef.current?.scrollIntoView?.({ behavior: "smooth", block: "end" });
  }, [messages, phase]);

  useEffect(
    () => () => {
      recorderRef.current?.stop();
      streamRef.current?.getTracks().forEach((track) => track.stop());
      stopMockSpeech();
    },
    []
  );

  async function processTurn(text: string) {
    const cleanText = text.trim();
    if (!cleanText) return;

    setMessages((current) => [
      ...current,
      { id: crypto.randomUUID(), role: "user", text: cleanText }
    ]);
    setDraft("");
    setPhase("responding");

    try {
      const reply = await submitMock(cleanText);
      setMessages((current) => [
        ...current,
        { id: crypto.randomUUID(), role: "coordinator", ...reply }
      ]);
      setLastReply(reply.text);
      setPhase("ready");
      speakMock(reply.text);
    } catch {
      setPhase("error");
    }
  }

  async function startRecording() {
    stopMockSpeech();
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      chunksRef.current = [];
      streamRef.current = stream;
      recorderRef.current = recorder;
      recorder.addEventListener("dataavailable", (event) => {
        if (event.data.size > 0) chunksRef.current.push(event.data);
      });
      recorder.addEventListener("stop", async () => {
        stream.getTracks().forEach((track) => track.stop());
        setPhase("transcribing");
        try {
          const audio = new Blob(chunksRef.current, { type: recorder.mimeType });
          const transcript = await transcribeMock(audio);
          await processTurn(transcript);
        } catch {
          setPhase("error");
        }
      });
      setSeconds(0);
      setPhase("recording");
      recorder.start();
    } catch {
      setPhase("error");
    }
  }

  function stopRecording() {
    if (recorderRef.current?.state === "recording") recorderRef.current.stop();
  }

  const busy = phase === "transcribing" || phase === "responding";

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <h1>STTS</h1>
          <span className="profile">Chief of Staff</span>
        </div>
        <div className="connection" aria-label="Local mock connected">
          <span aria-hidden="true" />
          Mock
        </div>
      </header>

      <section className="ledger" aria-label="Conversation" aria-live="polite">
        {messages.length === 0 ? (
          <div className="empty-state">
            <SignalIcon />
            <p>No messages</p>
          </div>
        ) : (
          messages.map((message) => (
            <article className={`message message--${message.role}`} key={message.id}>
              <div className="message-meta">
                <span>{message.role === "user" ? "You" : "Chief of Staff"}</span>
                {message.role === "coordinator" && (
                  <button type="button" className="replay" onClick={() => speakMock(message.text)}>
                    <PlayIcon />
                    <span className="sr-only">Replay response</span>
                  </button>
                )}
              </div>
              <p>{message.text}</p>
              {message.specialist && (
                <details className="activity">
                  <summary>{message.specialist}</summary>
                  <p>{message.activity}</p>
                </details>
              )}
            </article>
          ))
        )}
        <div ref={endRef} />
      </section>

      <section className="transport" aria-label="Voice controls">
        <div className="transport-status" role="status">
          <span>{phaseLabel(phase)}</span>
          <span>{phase === "recording" ? formatDuration(seconds) : "Voice note"}</span>
        </div>

        <div className="record-row">
          <button
            type="button"
            className={`record-button ${phase === "recording" ? "is-recording" : ""}`}
            onClick={phase === "recording" ? stopRecording : startRecording}
            disabled={busy}
            aria-label={phase === "recording" ? "Stop recording" : "Record voice note"}
            aria-pressed={phase === "recording"}
          >
            <span aria-hidden="true" />
          </button>
          {lastReply && (
            <button type="button" className="stop-button" onClick={stopMockSpeech}>
              Stop audio
            </button>
          )}
        </div>

        <form
          className="text-entry"
          onSubmit={(event) => {
            event.preventDefault();
            void processTurn(draft);
          }}
        >
          <label className="sr-only" htmlFor="message">
            Message
          </label>
          <textarea
            id="message"
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            placeholder="Message"
            rows={1}
            disabled={busy || phase === "recording"}
          />
          <button type="submit" disabled={!draft.trim() || busy || phase === "recording"}>
            Send
          </button>
        </form>
      </section>
    </main>
  );
}

function SignalIcon() {
  return (
    <svg viewBox="0 0 64 32" aria-hidden="true">
      <path d="M2 16h8l5-12 8 24 9-22 8 20 6-10h16" />
    </svg>
  );
}

function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m9 7 8 5-8 5V7Z" />
    </svg>
  );
}
