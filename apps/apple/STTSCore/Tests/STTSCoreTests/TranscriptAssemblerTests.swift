import XCTest
@testable import STTSCore

final class TranscriptAssemblerTests: XCTestCase {
    private func segment(_ index: Int, startedAtMs: Int, durationMs: Int = 45_000) -> SegmentMetadata {
        SegmentMetadata(
            index: index,
            startedAtMs: startedAtMs,
            durationMs: durationMs,
            fileURL: URL(fileURLWithPath: "/tmp/segments/segment-\(index).m4a")
        )
    }

    private func result(_ text: String, language: String? = "en") -> TranscriptionResult {
        TranscriptionResult(operationId: "op-\(text)", text: text, language: language, duration: nil)
    }

    func testOutOfOrderArrivalProducesOrderedTranscript() {
        var assembler = TranscriptAssembler()
        assembler.register(segment: segment(0, startedAtMs: 0))
        assembler.register(segment: segment(1, startedAtMs: 45_000))
        assembler.register(segment: segment(2, startedAtMs: 90_000))

        assembler.apply(result: result("third"), for: segment(2, startedAtMs: 90_000))
        assembler.apply(result: result("first"), for: segment(0, startedAtMs: 0))
        assembler.apply(result: result("second"), for: segment(1, startedAtMs: 45_000))

        XCTAssertEqual(assembler.orderedEntries().map(\.text), ["first", "second", "third"])
        XCTAssertEqual(assembler.assembledText(), "first\nsecond\nthird")
        XCTAssertEqual(assembler.transcribedCount, 3)
        XCTAssertFalse(assembler.hasPending)
    }

    func testDuplicateSegmentDeliveryKeepsSingleLatestEntry() {
        var assembler = TranscriptAssembler()
        assembler.register(segment: segment(0, startedAtMs: 0))

        assembler.apply(result: result("stale"), for: segment(0, startedAtMs: 0))
        assembler.apply(result: result("fresh"), for: segment(0, startedAtMs: 0))

        XCTAssertEqual(assembler.orderedEntries().count, 1)
        XCTAssertEqual(assembler.transcribedCount, 1)
        XCTAssertEqual(assembler.orderedEntries().first?.text, "fresh")
        XCTAssertEqual(assembler.assembledText(), "fresh")
    }

    func testRetryReplacesTextForSameIndex() throws {
        var assembler = TranscriptAssembler()
        assembler.register(segment: segment(3, startedAtMs: 135_000, durationMs: 12_000))

        assembler.apply(result: result("partial"), for: segment(3, startedAtMs: 135_000, durationMs: 12_000))
        assembler.apply(
            result: TranscriptionResult(operationId: "op-retry", text: "complete sentence", language: nil),
            for: segment(3, startedAtMs: 135_000, durationMs: 12_000)
        )

        let entry = try XCTUnwrap(assembler.orderedEntries().first)
        XCTAssertEqual(entry.text, "complete sentence")
        XCTAssertEqual(assembler.assembledText(), "complete sentence")
    }

    func testPermanentlyFailedSegmentIsSkippedAndReported() throws {
        var assembler = TranscriptAssembler()
        assembler.register(segment: segment(0, startedAtMs: 0))
        assembler.register(segment: segment(1, startedAtMs: 45_000))
        assembler.register(segment: segment(2, startedAtMs: 90_000))

        assembler.apply(result: result("kept"), for: segment(0, startedAtMs: 0))
        assembler.apply(result: result("kept too"), for: segment(2, startedAtMs: 90_000))
        assembler.markFailed(index: 1)

        XCTAssertEqual(assembler.assembledText(), "kept\nkept too")
        XCTAssertEqual(assembler.failedIndices, [1])
        let failedEntry = try XCTUnwrap(assembler.orderedEntries().first { $0.index == 1 })
        XCTAssertEqual(failedEntry.status, .failed)
    }

    func testEmptyTranscript() {
        let assembler = TranscriptAssembler()

        XCTAssertTrue(assembler.orderedEntries().isEmpty)
        XCTAssertEqual(assembler.assembledText(), "")
        XCTAssertEqual(assembler.failedIndices, [])
        XCTAssertFalse(assembler.hasPending)
        XCTAssertEqual(assembler.registeredCount, 0)
    }

    func testRegisteredOnlySegmentsStayPendingAndAreExcludedFromText() {
        var assembler = TranscriptAssembler()
        assembler.register(segment: segment(0, startedAtMs: 0))

        XCTAssertTrue(assembler.hasPending)
        XCTAssertEqual(assembler.assembledText(), "")
        XCTAssertEqual(assembler.orderedEntries().first?.status, .pending)
    }

    func testMonotonicOrderingRegardlessOfArrivalOrder() {
        var assembler = TranscriptAssembler()
        let offsets = [0, 45_000, 90_000, 135_000, 180_000, 225_000, 270_000, 315_000]
        for (index, offset) in offsets.enumerated() {
            assembler.register(segment: segment(index, startedAtMs: offset))
        }

        for (index, offset) in offsets.reversed().enumerated() {
            let reversedIndex = offsets.count - 1 - index
            assembler.apply(result: result("text-\(reversedIndex)"), for: segment(reversedIndex, startedAtMs: offset))
        }

        let entries = assembler.orderedEntries()
        XCTAssertEqual(entries.map(\.text), (0..<8).map { "text-\($0)" })
        let starts = entries.map(\.startedAtMs)
        XCTAssertEqual(starts, starts.sorted(), "startedAtMs must be non-decreasing")
    }
}
