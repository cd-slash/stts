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

    public init(
        id: String = UUID().uuidString,
        title: String,
        startedAt: Date,
        endedAt: Date? = nil,
        durationMs: Int,
        segments: [TranscriptEntry],
        assembledText: String,
        markers: [MeetingMarker]
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.segments = segments
        self.assembledText = assembledText
        self.markers = markers
    }
}

/// On-device persistence for meeting transcripts.
public protocol MeetingStore: Sendable {
    func save(_ meeting: MeetingTranscript) async throws
    func listMeetings() async throws -> [MeetingTranscript]
    func meeting(id: String) async throws -> MeetingTranscript?
    func delete(id: String) async throws
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
        let files = (
            try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        )?
            .filter { $0.pathExtension == "json" } ?? []

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

    // MARK: Internals

    private func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("meeting-\(Self.safeID(id)).json", isDirectory: false)
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
