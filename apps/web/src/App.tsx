import { useEffect, useRef, useState } from "react";
import {
  answerInput,
  backendLabel,
  interruptActiveTurn,
  playResponse,
  speakLocal,
  stopAudio,
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
  responseId?: string;
}

function formatDuration(seconds: number) {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

function phaseLabel(phase: Phase) {
  const labels: Record<Phase, string> = {
    idle: "Ready",
    recording: "Recording",
    transcribing: "Transcribing",
    responding: "Working",
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
  const [canInterrupt, setCanInterrupt] = useState(false);
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
      stopAudio();
    },
    []
  );

  useEffect(() => {
    if (pendingInput?.kind === "approval") inputActionRef.current?.focus();
    if (pendingInput?.kind === "clarification") textEntryRef.current?.focus();
  }, [pendingInput]);

  function applyAgentResult(result: AgentResult) {
    if (result.kind === "interrupted") {
      setPhase("ready");
      return;
    }
    if (result.kind === "input") {
      if (backendLabel === "Worker") setCanInterrupt(true);
      setPendingInput(result.input);
      setApprovalArmed(false);
      setPhase("input");
      return;
    }
    setPendingInput(null);
    if (backendLabel === "Worker") setCanInterrupt(true);
    setMessages((current) => [
      ...current,
      { id: crypto.randomUUID(), role: "coordinator", ...result }
    ]);
    setLastReply(result.text);
    setPhase("ready");
    void playResponse(result.text, result.responseId).catch(() => undefined);
  }

  async function stopWork() {
    stopAudio();
    try {
      if (await interruptActiveTurn()) setPhase("ready");
    } catch {
      setPhase("error");
    }
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
    stopAudio();
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
        <h1>Chief of Staff</h1>
        <div className="connection" aria-label={`${backendLabel} connected`}>
          <span aria-hidden="true" />
          {backendLabel}
        </div>
      </header>

      <p className={`state-line${phase === "error" ? " state-line--alert" : ""}`} role="status">
        {phaseLabel(phase)}
      </p>

      <section className="conversation" aria-label="Conversation" aria-live="polite">
        {messages.length === 0 ? (
          <p className="empty-state">No messages</p>
        ) : (
          messages.map((message) => (
            <article className={`message message--${message.role}`} key={message.id}>
              <p className="message-text">{message.text}</p>
              {message.role === "coordinator" && (
                <button
                  type="button"
                  className="replay"
                  onClick={() => void playResponse(message.text, message.responseId).catch(() => undefined)}
                >
                  <PlayIcon />
                  <span className="sr-only">Replay response</span>
                </button>
              )}
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
        {((phase === "responding" && canInterrupt) || lastReply) && (
          <div className="secondary-actions">
            {phase === "responding" && canInterrupt && (
              <button type="button" className="quiet-button quiet-button--strong" onClick={() => void stopWork()}>
                Stop work
              </button>
            )}
            {lastReply && (
              <button type="button" className="quiet-button" onClick={stopAudio}>
                Stop audio
              </button>
            )}
          </div>
        )}

        {phase === "recording" ? (
          <div className="live-bar">
            <span className="live-dot" aria-hidden="true" />
            <span className="live-time">{formatDuration(seconds)}</span>
            <button
              type="button"
              className="live-stop"
              onClick={stopRecording}
              aria-label="Stop recording"
            >
              Stop
            </button>
          </div>
        ) : (
          <form
            className="composer"
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
              disabled={busy || pendingInput?.kind === "approval"}
            />
            <button
              type="button"
              className="icon-button"
              onClick={startRecording}
              disabled={busy || pendingInput !== null}
              aria-label="Record voice note"
            >
              <MicIcon />
            </button>
            <button
              type="submit"
              className="send-button"
              disabled={!draft.trim() || busy || pendingInput?.kind === "approval"}
              aria-label="Send"
            >
              <SendIcon />
            </button>
          </form>
        )}
      </section>
    </main>
  );
}

function MicIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path d="M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3Z" fill="currentColor" />
      <path
        d="M6 11a6 6 0 0 0 12 0M12 17v4"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
      />
    </svg>
  );
}

function SendIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        d="M12 19V5M6 11l6-6 6 6"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
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
