import SwiftUI
import STTSCore

struct WatchMeetingControlView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(link.meetingState)
                    .font(.headline)
                    .accessibilityLabel("Meeting state")

                if link.meetingState == "recording", let started = link.meetingStartedAtEpochMs {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(elapsedText(startedAtEpochMs: started, now: context.date))
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .accessibilityLabel("Meeting elapsed time")
                    }
                }

                switch link.meetingState {
                case "recording":
                    Button("Add marker") {
                        link.addMarker()
                    }
                    .accessibilityLabel("Add meeting marker")
                    Button("Stop", role: .destructive) {
                        link.stopMeeting()
                    }
                    .accessibilityLabel("Stop meeting on phone")
                case "paused":
                    Button("Stop", role: .destructive) {
                        link.stopMeeting()
                    }
                    .accessibilityLabel("Stop meeting on phone")
                default:
                    Button("Start") {
                        link.startMeeting()
                    }
                    .accessibilityLabel("Start meeting on phone")
                }

                if let reply = link.replyText, !reply.isEmpty {
                    Text(reply)
                        .font(.caption2)
                        .lineLimit(6)
                }
                if let message = link.statusMessage {
                    Text(message)
                        .font(.caption2)
                }
                Button("Stop playback") {
                    link.stopPlayback()
                }
                .accessibilityLabel("Stop reply playback")
            }
        }
    }

    private func elapsedText(startedAtEpochMs: Int, now: Date) -> String {
        let elapsedMs = max(0, Int(now.timeIntervalSince1970 * 1000) - startedAtEpochMs)
        return STTSTimeFormat.clockString(ms: elapsedMs)
    }
}
