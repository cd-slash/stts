import SwiftUI
import STTSCore

/// Voice capture page: the state word in display weight, a single centred
/// 72pt mic control that turns amber while live, and the elapsed time in
/// tabular figures below.
struct WatchVoiceNoteView: View {
    @EnvironmentObject var recorder: WatchVoiceNoteRecorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pulse = false

    private var isRecording: Bool { recorder.phase == .recording }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    Text(stateWord)
                        .sttsDisplay()
                        .foregroundStyle(isRecording ? Color.sttsLive : Color.sttsInk)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    micControl
                    detailArea
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(Color.sttsVoid.ignoresSafeArea())
    }

    private var stateWord: String {
        switch recorder.phase {
        case .idle: "Ready"
        case .recording: "Recording"
        case .sent: "Sent"
        case .failed: "Failed"
        }
    }

    // MARK: Mic control

    private var micControl: some View {
        Button(action: handleTap) {
            ZStack {
                if isRecording && !reduceMotion {
                    pulseRing
                }
                Circle()
                    .fill(isRecording ? Color.sttsLive : Color.sttsVoid)
                    .overlay(
                        Circle().strokeBorder(
                            isRecording ? Color.sttsLive : Color.sttsOutline,
                            lineWidth: 1
                        )
                    )
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.sttsTitle)
                    .foregroundStyle(isRecording ? Color.sttsVoid : Color.sttsInk)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop and send to phone" : "Start recording")
    }

    /// A single expanding pulse on the live indicator. Reduce Motion keeps a
    /// static amber control.
    private var pulseRing: some View {
        Circle()
            .stroke(Color.sttsLive, lineWidth: 2)
            .scaleEffect(pulse ? 1.3 : 0.95)
            .opacity(pulse ? 0 : 0.8)
            .animation(
                reduceMotion
                    ? nil
                    : Animation.easeOut(duration: 1.1).repeatForever(autoreverses: false),
                value: pulse
            )
            .onAppear {
                guard !reduceMotion else { return }
                pulse = true
            }
    }

    private func handleTap() {
        switch recorder.phase {
        case .recording:
            recorder.stopAndSend()
        case .idle:
            recorder.start()
        case .sent, .failed:
            recorder.reset()
            recorder.start()
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detailArea: some View {
        switch recorder.phase {
        case .recording:
            VStack(spacing: 8) {
                Text(STTSTimeFormat.clockString(ms: Int(recorder.elapsed * 1000)))
                    .font(.sttsBodyTabular)
                    .foregroundStyle(Color.sttsInk)
                    .accessibilityLabel("Recording elapsed time")
                Button("Discard", role: .destructive) {
                    recorder.cancel()
                }
                .font(.sttsCaption)
                .foregroundStyle(Color.sttsAlert)
                .buttonStyle(.plain)
                .accessibilityLabel("Discard recording")
            }
        case .failed(let message):
            Text(message)
                .font(.sttsCaption)
                .foregroundStyle(Color.sttsAlert)
                .multilineTextAlignment(.center)
        case .idle, .sent:
            EmptyView()
        }
    }
}
