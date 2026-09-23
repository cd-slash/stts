import Foundation

public struct MeetingMarker: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var atOffsetMs: Int
    public var label: String

    public init(id: String = UUID().uuidString, atOffsetMs: Int, label: String) {
        self.id = id
        self.atOffsetMs = atOffsetMs
        self.label = label
    }
}

/// Persisted meeting transcript. Only text is retained — never audio.
public struct MeetingTranscript: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMs: Int
    public var segments: [TranscriptEntry]
    public var assembledText: String
    public var markers: [MeetingMarker]
    /// True when the recording never stopped cleanly — for example the app was
    /// terminated mid-meeting and the draft was recovered at launch.
    public var interrupted: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationMs: Int,
        segments: [TranscriptEntry],
        assembledText: String,
        markers: [MeetingMarker],
        interrupted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.segments = segments
        self.assembledText = assembledText
        self.markers = markers
        self.interrupted = interrupted
    }

    /// Decoded explicitly so a transcript written before `interrupted` existed
    /// still loads; the synthesized decoder would ignore the init default and
    /// fail on the missing key.
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case startedAt
        case endedAt
        case durationMs
        case segments
        case assembledText
        case markers
        case interrupted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        segments = try container.decode([TranscriptEntry].self, forKey: .segments)
        assembledText = try container.decode(String.self, forKey: .assembledText)
        markers = try container.decode([MeetingMarker].self, forKey: .markers)
        interrupted = try container.decodeIfPresent(Bool.self, forKey: .interrupted) ?? false
    }

    /// Promotes an abandoned draft into a saved transcript.
    public init(draft: MeetingDraft) {
        self.init(
            id: draft.id,
            title: draft.title,
            startedAt: draft.startedAt,
            endedAt: nil,
            durationMs: draft.durationMs,
            segments: draft.segments,
            assembledText: draft.assembledText,
            markers: draft.markers,
            interrupted: true
        )
    }
}

/// In-progress meeting state, rewritten after each segment outcome, marker, or
/// pause so a crash or termination cannot lose already-transcribed text.
/// Contains no audio.
public struct MeetingDraft: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var durationMs: Int
    public var segments: [TranscriptEntry]
    public var assembledText: String
    public var markers: [MeetingMarker]
    public var updatedAt: Date

    public init(
        id: String,
        title: String,
        startedAt: Date,
        durationMs: Int,
        segments: [TranscriptEntry],
        assembledText: String,
        markers: [MeetingMarker],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.segments = segments
        self.assembledText = assembledText
        self.markers = markers
        self.updatedAt = updatedAt
    }
}

/// On-device persistence for meeting transcripts and in-progress drafts.
public protocol MeetingStore: Sendable {
    func save(_ meeting: MeetingTranscript) async throws
    func listMeetings() async throws -> [MeetingTranscript]
    func meeting(id: String) async throws -> MeetingTranscript?
    func delete(id: String) async throws

    /// Creates or replaces the draft for one recording.
    func saveDraft(_ draft: MeetingDraft) async throws
    func listDrafts() async throws -> [MeetingDraft]
    func deleteDraft(id: String) async throws
}

/// JSON-file-backed store. Each meeting is one `<directory>/meeting-<id>.json`
/// file; the directory can point anywhere (tests use a temporary directory).
public actor JSONFileMeetingStore: MeetingStore {
    private let directory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: MeetingStore

    public func save(_ meeting: MeetingTranscript) async throws {
        try ensureDirectory()
        let data = try encoder.encode(meeting)
        try data.write(to: fileURL(for: meeting.id), options: .atomic)
    }

    public func listMeetings() async throws -> [MeetingTranscript] {
        let files = try jsonFiles(prefixed: Self.meetingPrefix)

        var meetings: [MeetingTranscript] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let meeting = try? decoder.decode(MeetingTranscript.self, from: data) {
                meetings.append(meeting)
            }
        }
        return meetings.sorted { $0.startedAt > $1.startedAt }
    }

    public func meeting(id: String) async throws -> MeetingTranscript? {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(MeetingTranscript.self, from: data)
    }

    public func delete(id: String) async throws {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    // MARK: Drafts

    public func saveDraft(_ draft: MeetingDraft) async throws {
        try ensureDirectory()
        let data = try encoder.encode(draft)
        try data.write(to: draftURL(for: draft.id), options: .atomic)
    }

    public func listDrafts() async throws -> [MeetingDraft] {
        let files = try jsonFiles(prefixed: Self.draftPrefix)

        var drafts: [MeetingDraft] = []
        for file in files {
            if let data = try? Data(contentsOf: file),
               let draft = try? decoder.decode(MeetingDraft.self, from: data) {
                drafts.append(draft)
            }
        }
        return drafts.sorted { $0.startedAt > $1.startedAt }
    }

    public func deleteDraft(id: String) async throws {
        try? FileManager.default.removeItem(at: draftURL(for: id))
    }

    // MARK: Internals

    private static let meetingPrefix = "meeting-"
    private static let draftPrefix = "draft-"

    private func jsonFiles(prefixed prefix: String) throws -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries.filter {
            $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix(prefix)
        }
    }

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent(
            "\(Self.meetingPrefix)\(Self.safeID(id)).json",
            isDirectory: false
        )
    }

    private func draftURL(for id: String) -> URL {
        directory.appendingPathComponent(
            "\(Self.draftPrefix)\(Self.safeID(id)).json",
            isDirectory: false
        )
    }

    private func ensureDirectory() throws {
        if FileManager.default.fileExists(atPath: directory.path) { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// IDs are generated UUIDs, but the filename is sanitized defensively so a
    /// malformed ID can never escape the store directory.
    private static func safeID(_ id: String) -> String {
        let scalars = id.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
        let filtered = String(String.UnicodeScalarView(scalars))
        return filtered.isEmpty ? "unnamed" : filtered
    }
}
