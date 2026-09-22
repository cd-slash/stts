import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { App } from "./App";

Object.defineProperty(window, "speechSynthesis", {
  value: { cancel: vi.fn(), speak: vi.fn() },
  configurable: true
});

describe("App", () => {
  it("presents voice-first controls and a text fallback", () => {
    render(<App />);

    expect(screen.getByRole("button", { name: "Record voice note" })).toBeInTheDocument();
    expect(screen.getByRole("textbox", { name: "Message" })).toBeInTheDocument();
    expect(screen.getByText("No messages")).toBeInTheDocument();
  });
});
