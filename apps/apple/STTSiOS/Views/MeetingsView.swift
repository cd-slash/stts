import SwiftUI
import STTSCore

struct MeetingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MeetingsContent(library: appState.library, meetings: appState.meetings)
            .navigationTitle("Meetings")
    }
}

private struct MeetingsContent: View {
    @ObservedObject var library: MeetingLibraryViewModel
    @ObservedObject var meetings: MeetingCoordinator

    var body: some View {
        List {
            if let message = library.loadError {
                Text(message)
                    .font(.sttsCaption)
                    .foregroundStyle(Color.sttsAlert)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if library.meetings.isEmpty {
                Text("No meetings")
                    .font(.sttsCaption)
                    .foregroundStyle(Color.sttsInkMuted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.meetings) { meeting in
                        meetingRow(meeting)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { group.meetings[$0] }
                        Task {
                            for meeting in doomed {
                                await library.delete(meeting)
                            }
                        }
                    }
                } header: {
                    groupHeader(group.label)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.sttsVoid.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            recordAction
        }
        .refreshable {
            await library.refresh()
        }
        .task {
            await library.refresh()
        }
        .onChange(of: meetings.state) { _, newState in
            if newState == .saved {
                Task { await library.refresh() }
            }
        }
    }

    // MARK: Rows

    private func meetingRow(_ meeting: MeetingTranscript) -> some View {
        NavigationLink {
            MeetingTranscriptView(meeting: meeting)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(meeting.title)
                        .font(.sttsBody)
                        .foregroundStyle(Color.sttsInk)
                    Spacer(minLength: 12)
                    Text(STTSTimeFormat.clockString(ms: meeting.durationMs))
                        .font(.sttsCaptionTabular)
                        .foregroundStyle(Color.sttsInkMuted)
                }
                if let opening = Self.openingLine(of: meeting) {
                    Text(opening)
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsInkMuted)
                        .lineLimit(1)
                }
                if meeting.interrupted {
                    Text("Interrupted")
                        .font(.sttsCaption)
                        .foregroundStyle(Color.sttsAlert)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.sttsHairline)
    }

    private func groupHeader(_ label: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.sttsCaption)
                .foregroundStyle(Color.sttsInkMuted)
            Rectangle()
                .fill(Color.sttsHairline)
                .frame(height: 1)
        }
        .textCase(nil)
    }

    /// Sticky primary action.
    private var recordAction: some View {
        NavigationLink {
            MeetingView()
        } label: {
            Text("Record meeting")
                .font(.sttsBody)
                .foregroundStyle(Color.sttsVoid)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.sttsInk)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.sttsVoid)
    }

    // MARK: Grouping

    private struct MeetingGroup: Identifiable {
        let label: String
        let meetings: [MeetingTranscript]
        var id: String { label }
    }

    private var groups: [MeetingGroup] {
        var result: [MeetingGroup] = []
        for meeting in library.meetings {
            let label = Self.dayLabel(meeting.startedAt)
            if var last = result.last, last.label == label {
                last.meetings.append(meeting)
                result[result.count - 1] = last
            } else {
                result.append(MeetingGroup(label: label, meetings: [meeting]))
            }
        }
        return result
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// The single-line opening shown under a row's title.
    private static func openingLine(of meeting: MeetingTranscript) -> String? {
        let assembled = meeting.assembledText
            .split(separator: "\n")
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let assembled {
            return String(assembled)
        }
        let segment = meeting.segments.first { $0.status == .transcribed && !$0.text.isEmpty }
        return segment?.text
    }
}
