import SwiftUI
import STTSCore

struct WatchVoiceNoteView: View {
    @EnvironmentObject var recorder: WatchVoiceNoteRecorder

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                switch recorder.phase {
                case .idle:
                    Button {
                        recorder.start()
                    } label: {
                        Image(systemName: "record.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel("Start recording")
                case .recording:
                    Text(STTSTimeFormat.clockString(ms: Int(recorder.elapsed * 1000)))
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .accessibilityLabel("Recording elapsed time")
                    Button("Stop") {
                        recorder.stopAndSend()
                    }
                    .accessibilityLabel("Stop and send to phone")
                    Button("Discard", role: .destructive) {
                        recorder.cancel()
                    }
                    .accessibilityLabel("Discard recording")
                case .sent:
                    Text("Sent").font(.headline)
                    Button("Record") {
                        recorder.reset()
                        recorder.start()
                    }
                    .accessibilityLabel("Record new voice note")
                case .failed(let message):
                    Text(message).font(.headline)
                    Button("Record") {
                        recorder.reset()
                        recorder.start()
                    }
                    .accessibilityLabel("Record new voice note")
                }
            }
        }
    }
}
