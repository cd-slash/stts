import XCTest
@testable import STTSCore

final class SegmenterTests: XCTestCase {
    // MARK: VoiceNoteSegmenter

    func testVoiceNoteSingleWindowUnderTarget() {
        let segmenter = VoiceNoteSegmenter(targetSegmentDurationMs: 45_000)
        let windows = segmenter.planWindows(totalDurationMs: 30_000)

        XCTAssertEqual(windows, [SegmentWindow(index: 0, startedAtMs: 0, durationMs: 30_000)])
    }

    func testVoiceNoteWindowsSplitAtTarget() {
        let segmenter = VoiceNoteSegmenter(targetSegmentDurationMs: 45_000)
        let windows = segmenter.planWindows(totalDurationMs: 100_000)

        XCTAssertEqual(windows, [
            SegmentWindow(index: 0, startedAtMs: 0, durationMs: 45_000),
            SegmentWindow(index: 1, startedAtMs: 45_000, durationMs: 45_000),
            SegmentWindow(index: 2, startedAtMs: 90_000, durationMs: 10_000)
        ])
    }

    func testVoiceNoteZeroAndNegativeDurations() {
        let segmenter = VoiceNoteSegmenter(targetSegmentDurationMs: 45_000)
        XCTAssertTrue(segmenter.planWindows(totalDurationMs: 0).isEmpty)
        XCTAssertTrue(segmenter.planWindows(totalDurationMs: -5).isEmpty)
    }

    // MARK: MeetingSegmenter

    func testMeetingSegmentLifecycleAndIndexes() {
        var segmenter = MeetingSegmenter(targetSegmentDurationMs: 45_000)
        let directory = URL(fileURLWithPath: "/tmp/meeting")

        let first = segmenter.beginSegment(atOffsetMs: 0, directory: directory)
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.fileURL.lastPathComponent, "segment-0000.m4a")
        XCTAssertEqual(segmenter.currentSegment?.index, 0)

        let closed = segmenter.endCurrentSegment(atOffsetMs: 10_000)
        XCTAssertEqual(closed?.durationMs, 10_000)
        XCTAssertNil(segmenter.currentSegment)
        XCTAssertEqual(segmenter.totalRecordedMs, 10_000)

        let second = segmenter.beginSegment(atOffsetMs: 12_000, directory: directory)
        XCTAssertEqual(second.index, 1)
        XCTAssertEqual(second.fileURL.lastPathComponent, "segment-0001.m4a")
    }

    func testMeetingSegmentRolloverThreshold() {
        var segmenter = MeetingSegmenter(targetSegmentDurationMs: 45_000)
        _ = segmenter.beginSegment(atOffsetMs: 500, directory: URL(fileURLWithPath: "/tmp/meeting"))

        XCTAssertFalse(segmenter.shouldCloseCurrentSegment(atOffsetMs: 500 + 44_999))
        XCTAssertTrue(segmenter.shouldCloseCurrentSegment(atOffsetMs: 500 + 45_000))
    }

    func testMeetingSegmentBeginClosesStrayOpenSegment() {
        var segmenter = MeetingSegmenter(targetSegmentDurationMs: 45_000)
        let directory = URL(fileURLWithPath: "/tmp/meeting")

        _ = segmenter.beginSegment(atOffsetMs: 0, directory: directory)
        let replacement = segmenter.beginSegment(atOffsetMs: 20_000, directory: directory)

        XCTAssertEqual(segmenter.completedSegments.count, 1)
        XCTAssertEqual(segmenter.completedSegments.first?.durationMs, 20_000)
        XCTAssertEqual(replacement.index, 1)
    }

    func testMeetingSegmentEndWithoutOpenSegment() {
        var segmenter = MeetingSegmenter(targetSegmentDurationMs: 45_000)
        XCTAssertNil(segmenter.endCurrentSegment(atOffsetMs: 100))
        XCTAssertEqual(segmenter.totalRecordedMs, 0)
    }

    func testDefaultTargetIsFortyFiveSeconds() {
        XCTAssertEqual(MeetingSegmenter().targetSegmentDurationMs, 45_000)
        XCTAssertEqual(VoiceNoteSegmenter().targetSegmentDurationMs, 45_000)
    }
}
