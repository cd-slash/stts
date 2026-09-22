import { cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as api from "./api-client";
import { App } from "./App";

vi.mock("./api-client", () => ({
  backendLabel: "Worker",
  transcribeVoiceNote: vi.fn(),
  submitTurn: vi.fn(),
  answerInput: vi.fn(),
  interruptActiveTurn: vi.fn(),
  playResponse: vi.fn(),
  speakLocal: vi.fn(),
  stopAudio: vi.fn()
}));

Object.defineProperty(window, "speechSynthesis", {
  value: { cancel: vi.fn(), speak: vi.fn() },
  configurable: true
});

describe("App", () => {
  beforeEach(() => vi.resetAllMocks());
  afterEach(cleanup);

  it("presents voice-first controls and a text fallback", () => {
    render(<App />);

    expect(screen.getByRole("button", { name: "Record voice note" })).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: "Message" })).toBeInTheDocument();
    expect(screen.getByText("No messages")).toBeInTheDocument();
  });

  it("requires read-back before approving", async () => {
    vi.mocked(api.submitTurn).mockResolvedValue({
      kind: "input",
      input: {
        requestId: "approval-1",
        kind: "approval",
        prompt: "Run maintenance command?",
        choices: ["once", "deny"],
        confirmationNonce: "nonce-1"
      }
    });
    vi.mocked(api.answerInput).mockResolvedValue({ kind: "completed", text: "Complete" });
    render(<App />);

    fireEvent.change(screen.getByRole("textbox", { name: "Message" }), {
      target: { value: "Run maintenance" }
    });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(await screen.findByRole("heading", { name: "Approval" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Approve" })).not.toBeInTheDocument();

    fireEvent.click(screen.getByRole("button", { name: "Read back" }));
    expect(api.speakLocal).toHaveBeenCalledWith("Run maintenance command?");
    fireEvent.click(screen.getByRole("button", { name: "Approve" }));

    await waitFor(() =>
      expect(api.answerInput).toHaveBeenCalledWith(
        expect.objectContaining({ requestId: "approval-1" }),
        { kind: "approve", confirmationNonce: "nonce-1" }
      )
    );
  });

  it("offers interruption after a durable turn", async () => {
    vi.mocked(api.submitTurn)
      .mockResolvedValueOnce({ kind: "completed", text: "First response" })
      .mockImplementationOnce(() => new Promise(() => undefined));
    vi.mocked(api.interruptActiveTurn).mockResolvedValue(true);
    render(<App />);

    const field = screen.getByRole("textbox", { name: "Message" });
    fireEvent.change(field, { target: { value: "First" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    expect(await screen.findByText("First response")).toBeInTheDocument();

    fireEvent.change(field, { target: { value: "Second" } });
    fireEvent.click(screen.getByRole("button", { name: "Send" }));
    fireEvent.click(await screen.findByRole("button", { name: "Stop work" }));
    await waitFor(() => expect(api.interruptActiveTurn).toHaveBeenCalledOnce());
  });
});
