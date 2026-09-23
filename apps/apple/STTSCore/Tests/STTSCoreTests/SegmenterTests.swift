import XCTest
@testable import STTSCore

final class SegmenterTests: XCTestCase {
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
    }
}
