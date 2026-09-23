import XCTest
@testable import STTSCore

final class MeetingStoreTests: XCTestCase {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("stts-store-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func meeting(title: String, startedAt: Date) -> MeetingTranscript {
        MeetingTranscript(
            title: title,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            durationMs: 60_000,
            segments: [
                TranscriptEntry(
                    index: 0,
                    startedAtMs: 0,
                    durationMs: 45_000,
                    status: .transcribed,
                    text: "hello",
                    language: "en"
                ),
                TranscriptEntry(
                    index: 1,
                    startedAtMs: 45_000,
                    durationMs: 15_000,
                    status: .failed,
                    text: "",
                    language: nil
                )
            ],
            assembledText: "hello",
            markers: [MeetingMarker(atOffsetMs: 30_000, label: "Decision")]
        )
    }

    func testSaveListRoundtripAndDelete() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileMeetingStore(directory: directory)

        let older = meeting(
            title: "Older",
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = meeting(
            title: "Newer",
            startedAt: Date(timeIntervalSince1970: 5_000)
        )

        try await store.save(older)
        try await store.save(newer)

        let listed = try await store.listMeetings()
        XCTAssertEqual(listed.map(\.id), [newer.id, older.id], "newest first")

        let fetched = try await store.meeting(id: older.id)
        XCTAssertEqual(fetched, older)

        try await store.delete(id: older.id)
        let afterDelete = try await store.listMeetings()
        XCTAssertEqual(afterDelete.map(\.id), [newer.id])
        let missing = try await store.meeting(id: older.id)
        XCTAssertNil(missing)
    }

    func testListWithEmptyDirectoryReturnsEmptyArray() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileMeetingStore(directory: directory)

        let listed = try await store.listMeetings()
        XCTAssertTrue(listed.isEmpty)
    }

    func testSaveOverwritesExistingMeeting() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileMeetingStore(directory: directory)

        var stored = meeting(title: "First", startedAt: Date(timeIntervalSince1970: 10))
        try await store.save(stored)

        stored.title = "Second"
        try await store.save(stored)

        let listed = try await store.listMeetings()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.title, "Second")
    }

    // MARK: Drafts

    private func draft(id: String = UUID().uuidString, text: String) -> MeetingDraft {
        MeetingDraft(
            id: id,
            title: "Meeting",
            startedAt: Date(timeIntervalSince1970: 2_000),
            durationMs: 45_000,
            segments: [
                TranscriptEntry(
                    index: 0,
                    startedAtMs: 0,
                    durationMs: 45_000,
                    status: .transcribed,
                    text: text,
                    language: nil
                )
            ],
            assembledText: text,
            markers: []
        )
    }

    func testDraftRoundTripAndReplacement() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileMeetingStore(directory: directory)

        let id = UUID().uuidString
        try await store.saveDraft(draft(id: id, text: "first"))
        try await store.saveDraft(draft(id: id, text: "second"))

        let drafts = try await store.listDrafts()
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.assembledText, "second")
    }

    func testDraftsAndMeetingsDoNotAppearInEachOther() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileMeetingStore(directory: directory)

        try await store.save(meeting(title: "Saved", startedAt: Date(timeIntervalSince1970: 10)))
        try await store.saveDraft(draft(text: "in progress"))

        let meetings = try await store.listMeetings()
        let drafts = try await store.listDrafts()
        XCTAssertEqual(meetings.count, 1)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(meetings.first?.title, "Saved")
        XCTAssertEqual(drafts.first?.assembledText, "in progress")
    }

    func testDeleteDraftIsIdempotent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JSONFileMeetingStore(directory: directory)

        let id = UUID().uuidString
        try await store.saveDraft(draft(id: id, text: "text"))
        try await store.deleteDraft(id: id)
        try await store.deleteDraft(id: id)

        let drafts = try await store.listDrafts()
        XCTAssertTrue(drafts.isEmpty)
    }

    func testRecoveredDraftBecomesInterruptedTranscript() {
        let recovered = MeetingTranscript(draft: draft(text: "recovered text"))

        XCTAssertTrue(recovered.interrupted)
        XCTAssertNil(recovered.endedAt)
        XCTAssertEqual(recovered.assembledText, "recovered text")
        XCTAssertFalse(
            MeetingTranscript(
                title: "Clean",
                startedAt: Date(),
                durationMs: 1,
                segments: [],
                assembledText: "",
                markers: []
            ).interrupted,
            "a normally finished meeting is not interrupted"
        )
    }
}
