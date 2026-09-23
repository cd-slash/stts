import SwiftUI
import STTSCore

/// Meeting control page: start, stop, marker. The transcript stays on the
/// phone.
struct WatchMeetingControlView: View {
    @EnvironmentObject var link: PhoneLink

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    Text(meetingStateLabel)
                        .sttsTitle()
                        .foregroundStyle(Color.sttsInk)
                        .accessibilityLabel("Meeting state")

                    if link.meetingState == "recording",
                       let started = link.meetingStartedAtEpochMs {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(elapsedText(startedAtEpochMs: started, now: context.date))
                                .font(.sttsBodyTabular)
                                .foregroundStyle(Color.sttsInkMuted)
                                .accessibilityLabel("Meeting elapsed time")
                        }
                    }

                    controls

                    if let reply = link.replyText, !reply.isEmpty {
                        Text(reply)
                            .font(.sttsCaption)
                            .foregroundStyle(Color.sttsInk)
                            .lineLimit(6)
                    }
                    if let message = link.statusMessage {
                        Text(message)
                            .font(.sttsCaption)
                            .foregroundStyle(Color.sttsAlert)
                    }
                    Button("Stop playback") {
                        link.stopPlayback()
                    }
                    .font(.sttsCaption)
                    .foregroundStyle(Color.sttsInkMuted)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop reply playback")
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(Color.sttsVoid.ignoresSafeArea())
    }

    private var meetingStateLabel: String {
        link.meetingState.prefix(1).uppercased() + link.meetingState.dropFirst()
    }

    @ViewBuilder
    private var controls: some View {
        switch link.meetingState {
        case "recording":
            VStack(spacing: 8) {
                controlButton("Marker", filled: false) {
                    link.addMarker()
                }
                .accessibilityLabel("Add meeting marker")
                controlButton("Stop", filled: false, destructive: true, stroke: Color.sttsAlert) {
                    link.stopMeeting()
                }
                .accessibilityLabel("Stop meeting on phone")
            }
        case "paused":
            controlButton("Stop", filled: false, destructive: true, stroke: Color.sttsAlert) {
                link.stopMeeting()
            }
            .accessibilityLabel("Stop meeting on phone")
        default:
            controlButton("Start", filled: true) {
                link.startMeeting()
            }
            .accessibilityLabel("Start meeting on phone")
        }
    }

    private func controlButton(
        _ title: String,
        filled: Bool,
        destructive: Bool = false,
        stroke: Color = Color.sttsInk,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Text(title)
                .font(.sttsBody)
                .foregroundStyle(filled ? Color.sttsVoid : stroke)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(filled ? Color.sttsInk : Color.sttsVoid))
                .overlay(
                    Capsule().strokeBorder(filled ? Color.clear : stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func elapsedText(startedAtEpochMs: Int, now: Date) -> String {
        let elapsedMs = max(0, Int(now.timeIntervalSince1970 * 1000) - startedAtEpochMs)
        return STTSTimeFormat.clockString(ms: elapsedMs)
    }
}
