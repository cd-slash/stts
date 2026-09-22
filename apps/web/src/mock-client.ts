export interface MockReply {
  text: string;
  specialist: string;
  activity: string;
}

const wait = (milliseconds: number) =>
  new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));

export async function transcribeMock(_audio: Blob): Promise<string> {
  await wait(600);
  return "Summarize my next priorities.";
}

export async function submitMock(text: string): Promise<MockReply> {
  await wait(900);
  return {
    text: `Your priority summary is ready. The recorded request was: ${text}`,
    specialist: "Personal Assistant",
    activity: "Priority review complete"
  };
}

export function speakMock(text: string): void {
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = 1;
  window.speechSynthesis.speak(utterance);
}

export function stopMockSpeech(): void {
  window.speechSynthesis.cancel();
}
