import { useEffect, useRef, useState } from "react";
import {
  answerInput,
  backendLabel,
  speakLocal,
  stopLocalSpeech,
  submitTurn,
  transcribeVoiceNote,
  type AgentResult,
  type PendingInput
} from "./api-client";

type Phase = "idle" | "recording" | "transcribing" | "responding" | "input" | "ready" | "error";

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
    input: "Input required",
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
  const [pendingInput, setPendingInput] = useState<PendingInput | null>(null);
  const [approvalArmed, setApprovalArmed] = useState(false);
  const recorderRef = useRef<MediaRecorder | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const endRef = useRef<HTMLDivElement | null>(null);
  const inputActionRef = useRef<HTMLButtonElement | null>(null);
  const textEntryRef = useRef<HTMLTextAreaElement | null>(null);

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
      stopLocalSpeech();
    },
    []
  );

  useEffect(() => {
    if (pendingInput?.kind === "approval") inputActionRef.current?.focus();
    if (pendingInput?.kind === "clarification") textEntryRef.current?.focus();
  }, [pendingInput]);

  function applyAgentResult(result: AgentResult) {
    if (result.kind === "input") {
      setPendingInput(result.input);
      setApprovalArmed(false);
      setPhase("input");
      return;
    }
    setPendingInput(null);
    setMessages((current) => [
      ...current,
      { id: crypto.randomUUID(), role: "coordinator", ...result }
    ]);
    setLastReply(result.text);
    setPhase("ready");
    speakLocal(result.text);
  }

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
      const reply = await submitTurn(cleanText);
      applyAgentResult(reply);
    } catch {
      setPhase("error");
    }
  }

  async function respondToInput(
    answer: { kind: "text"; text: string } | { kind: "approve" | "deny"; confirmationNonce?: string }
  ) {
    if (!pendingInput) return;
    setPhase("responding");
    try {
      const result = await answerInput(pendingInput, answer);
      applyAgentResult(result);
    } catch {
      setPhase("error");
    }
  }

  async function startRecording() {
    stopLocalSpeech();
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
          const transcript = await transcribeVoiceNote(audio);
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
        <div className="connection" aria-label={`${backendLabel} connected`}>
          <span aria-hidden="true" />
          {backendLabel}
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
                  <button type="button" className="replay" onClick={() => speakLocal(message.text)}>
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
        {pendingInput?.kind === "approval" && (
          <section className="input-card" aria-labelledby="approval-title">
            <h2 id="approval-title">Approval</h2>
            <p>{pendingInput.prompt}</p>
            <div className="input-actions">
              <button
                ref={inputActionRef}
                type="button"
                onClick={() => {
                  speakLocal(pendingInput.prompt);
                  setApprovalArmed(true);
                }}
                disabled={busy}
              >
                Read back
              </button>
              {approvalArmed && (
                <button
                  type="button"
                  className="approve-action"
                  onClick={() =>
                    void respondToInput({
                      kind: "approve",
                      confirmationNonce: pendingInput.confirmationNonce
                    })
                  }
                  disabled={busy}
                >
                  Approve
                </button>
              )}
              <button
                type="button"
                onClick={() => void respondToInput({ kind: "deny" })}
                disabled={busy}
              >
                Deny
              </button>
            </div>
          </section>
        )}
        {pendingInput?.kind === "clarification" && (
          <section className="input-card" aria-labelledby="clarification-title">
            <h2 id="clarification-title">Clarification</h2>
            <p>{pendingInput.prompt}</p>
          </section>
        )}
        <div className="transport-status" role="status">
          <span>{phaseLabel(phase)}</span>
          <span>{phase === "recording" ? formatDuration(seconds) : "Voice note"}</span>
        </div>

        <div className="record-row">
          <button
            type="button"
            className={`record-button ${phase === "recording" ? "is-recording" : ""}`}
            onClick={phase === "recording" ? stopRecording : startRecording}
            disabled={busy || pendingInput !== null}
            aria-label={phase === "recording" ? "Stop recording" : "Record voice note"}
            aria-pressed={phase === "recording"}
          >
            <span aria-hidden="true" />
          </button>
          {lastReply && (
            <button type="button" className="stop-button" onClick={stopLocalSpeech}>
              Stop audio
            </button>
          )}
        </div>

        <form
          className="text-entry"
          onSubmit={(event) => {
            event.preventDefault();
            if (pendingInput?.kind === "clarification") {
              const answer = draft.trim();
              if (!answer) return;
              setMessages((current) => [
                ...current,
                { id: crypto.randomUUID(), role: "user", text: answer }
              ]);
              setDraft("");
              void respondToInput({ kind: "text", text: answer });
            } else {
              void processTurn(draft);
            }
          }}
        >
          <label className="sr-only" htmlFor="message">
            Message
          </label>
          <textarea
            ref={textEntryRef}
            id="message"
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            placeholder={pendingInput?.kind === "clarification" ? "Reply" : "Message"}
            rows={1}
            disabled={busy || phase === "recording" || pendingInput?.kind === "approval"}
          />
          <button
            type="submit"
            disabled={
              !draft.trim() || busy || phase === "recording" || pendingInput?.kind === "approval"
            }
          >
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
