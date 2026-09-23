import SwiftUI
import STTSCore

struct MeetingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MeetingContent(meetings: appState.meetings)
            .navigationTitle("Meeting")
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MeetingContent: View {
    @ObservedObject var meetings: MeetingCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var markerLabel = ""
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlArea
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            Rectangle()
                .fill(Color.sttsHairline)
                .frame(height: 1)
            transcriptArea
        }
        .background(Color.sttsVoid.ignoresSafeArea())
    }

    // MARK: Controls

    @ViewBuilder
    private var controlArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch meetings.state {
            case .idle:
                primaryButton("Start recording", action: { meetings.start() })
                    .accessibilityLabel("Start meeting recording")
            case .recording:
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.sttsLive)
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 1.4 : 1)
                        .opacity(pulse ? 0.5 : 1)
                        .animation(
                            reduceMotion
                                ? nil
                                : Animation.easeInOut(duration: 0.9)
                                    .repeatForever(autoreverses: true),
                            value: pulse
                        )
                        .onAppear {
                            guard !reduceMotion else { return }
                            pulse = true
                        }
                        .accessibilityHidden(true)
                    Text(STTSTimeFormat.clockString(ms: meetings.elapsedMs))
                        .font(.sttsBodyTabular)
                        .foregroundStyle(Color.sttsInk)
                        .accessibilityLabel("Meeting elapsed time")
                    Spacer(minLength: 8)
                    Button("Pause") {
                        meetings.pause()
                    }
                    .font(.sttsBody)
                    .accessibilityLabel("Pause meeting recording")
                }
                markerComposer
                Button("Stop", role: .destructive) {
                    meetings.stopAndSave()
                }
                .font(.sttsBody)
                .foregroundStyle(Color.sttsAlert)
                .accessibilityLabel("Stop and save meeting")
            case .paused:
                Text("Paused")
                    .font(.sttsBody)
                    .foregroundStyle(Color.sttsInk)
                HStack(spacing: 24) {
                    Button("Resume") {
                        meetings.resume()
                    }
                    .accessibilityLabel("Resume meeting recording")
                    Button("Stop", role: .destructive) {
                        meetings.stopAndSave()
                    }
                    .foregroundStyle(Color.sttsAlert)
                    .accessibilityLabel("Stop and save meeting")
                }
                .font(.sttsBody)
            case .processing:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Processing")
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsInkMuted)
                }
            case .saved:
                HStack {
                    Text("Saved")
                        .font(.sttsBody)
                        .foregroundStyle(Color.sttsInk)
                    Spacer(minLength: 8)
                    Button("Done") {
                        meetings.reset()
                    }
                    .accessibilityLabel("Close saved meeting")
                }
                .font(.sttsBody)
            }
            if let message = meetings.statusMessage {
                Text(message)
                    .font(.sttsCaption)
                    .foregroundStyle(Color.sttsAlert)
            }
        }
    }

    private func primaryButton(
        _ title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.sttsBody)
                .foregroundStyle(Color.sttsVoid)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sttsInk)
                .clipShape(Capsule())
        }
    }

    private var markerComposer: some View {
        HStack(spacing: 8) {
            TextField("Marker label", text: $markerLabel)
                .font(.sttsBody)
                .foregroundStyle(Color.sttsInk)
                .submitLabel(.done)
                .onSubmit(addMarker)
                .accessibilityLabel("Marker label")
            Button("Mark", action: addMarker)
                .accessibilityLabel("Add marker")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color.sttsSurfaceRaised)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.sttsOutline, lineWidth: 1))
        .font(.sttsBody)
    }

    private func addMarker() {
        meetings.addMarker(label: markerLabel)
        markerLabel = ""
    }

    // MARK: Transcript

    private var transcriptArea: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if meetings.entries.isEmpty {
                    Text("No transcript")
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsInkMuted)
                }
                ForEach(meetings.entries, id: \.index) { entry in
                    TranscriptRow(
                        startedAtMs: entry.startedAtMs,
                        content: content(of: entry)
                    )
                }
                ForEach(meetings.markers) { marker in
                    MarkerRow(atOffsetMs: marker.atOffsetMs, label: marker.label)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func content(of entry: TranscriptEntry) -> TranscriptRow.Content {
        switch entry.status {
        case .transcribed: .text(entry.text)
        case .pending: .processing
        case .failed: .failedSegment
        }
    }
}
