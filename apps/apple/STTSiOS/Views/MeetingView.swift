import SwiftUI
import STTSCore

struct MeetingView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MeetingContent(meetings: appState.meetings)
            .navigationTitle("Meeting")
    }
}

private struct MeetingContent: View {
    @ObservedObject var meetings: MeetingCoordinator

    @State private var markerLabel = ""

    var body: some View {
        Form {
            controlsSection
            transcriptSection
            if !meetings.markers.isEmpty {
                markersSection
            }
        }
    }

    @ViewBuilder private var controlsSection: some View {
        Section {
            switch meetings.state {
            case .idle:
                Button {
                    meetings.start()
                } label: {
                    Label("Start recording", systemImage: "record.circle")
                }
                .accessibilityLabel("Start meeting recording")
            case .recording:
                Text(STTSTimeFormat.clockString(ms: meetings.elapsedMs))
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Meeting elapsed time")
                Button("Pause") {
                    meetings.pause()
                }
                .accessibilityLabel("Pause meeting recording")
                HStack {
                    TextField("Marker label", text: $markerLabel)
                        .accessibilityLabel("Marker label")
                    Button("Mark") {
                        meetings.addMarker(label: markerLabel)
                        markerLabel = ""
                    }
                    .accessibilityLabel("Add marker")
                }
                Button("Stop", role: .destructive) {
                    meetings.stopAndSave()
                }
                .accessibilityLabel("Stop and save meeting")
            case .paused:
                Text("Paused")
                Button("Resume") {
                    meetings.resume()
                }
                .accessibilityLabel("Resume meeting recording")
                Button("Stop", role: .destructive) {
                    meetings.stopAndSave()
                }
                .accessibilityLabel("Stop and save meeting")
            case .processing:
                HStack {
                    ProgressView()
                    Text("Processing")
                }
            case .saved:
                Text("Saved")
                Button("Done") {
                    meetings.reset()
                }
                .accessibilityLabel("Close saved meeting")
            }
            if let message = meetings.statusMessage {
                Text(message).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var transcriptSection: some View {
        Section("Transcript") {
            if meetings.entries.isEmpty {
                Text("No transcript").foregroundStyle(.secondary)
            }
            ForEach(meetings.entries, id: \.index) { entry in
                HStack(alignment: .top) {
                    Text(STTSTimeFormat.clockString(ms: entry.startedAtMs))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    switch entry.status {
                    case .transcribed:
                        Text(entry.text)
                    case .pending:
                        Text("Processing").foregroundStyle(.secondary)
                    case .failed:
                        Text("Segment failed").foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var markersSection: some View {
        Section("Markers") {
            ForEach(meetings.markers) { marker in
                HStack {
                    Text(STTSTimeFormat.clockString(ms: marker.atOffsetMs))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(marker.label)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
