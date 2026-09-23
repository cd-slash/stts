import XCTest
@testable import STTSCore

final class TranscriptChunkerTests: XCTestCase {
    private func nonWhitespace(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }

    func testShortTextIsOneChunk() {
        let chunker = TranscriptChunker(maximumCharacters: 100)
        XCTAssertEqual(chunker.chunks(of: "one line"), ["one line"])
    }

    func testEmptyAndWhitespaceProduceNoChunks() {
        let chunker = TranscriptChunker(maximumCharacters: 10)
        XCTAssertTrue(chunker.chunks(of: "").isEmpty)
        XCTAssertTrue(chunker.chunks(of: "   \n\n  ").isEmpty)
    }

    func testEmptyLinesAreIgnoredAndNotChunked() {
        let chunker = TranscriptChunker(maximumCharacters: 100)
        XCTAssertEqual(chunker.chunks(of: "a\n\n\nb"), ["a\nb"])
    }

    func testChunksRespectTheCeiling() {
        let chunker = TranscriptChunker(maximumCharacters: 40)
        let text = (1...20).map { "line number \($0)" }.joined(separator: "\n")
        let chunks = chunker.chunks(of: text)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 40)
        }
    }

    func testNoContentIsLostAcrossChunks() {
        let chunker = TranscriptChunker(maximumCharacters: 40)
        let text = (1...50).map { "segment \($0) has some words" }.joined(separator: "\n")
        let chunks = chunker.chunks(of: text)

        XCTAssertEqual(
            nonWhitespace(chunks.joined()),
            nonWhitespace(text),
            "chunking must preserve every non-whitespace character in order"
        )
    }

    func testSingleLongLineSplitsOnWords() {
        let chunker = TranscriptChunker(maximumCharacters: 20)
        let text = "alpha bravo charlie delta echo foxtrot"
        let chunks = chunker.chunks(of: text)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 20)
        }
        XCTAssertEqual(nonWhitespace(chunks.joined()), nonWhitespace(text))
    }

    func testSingleTokenLongerThanCeilingIsHardSplitWithoutLoss() {
        let chunker = TranscriptChunker(maximumCharacters: 5)
        let text = String(repeating: "x", count: 12)
        let chunks = chunker.chunks(of: text)

        XCTAssertEqual(chunks, ["xxxxx", "xxxxx", "xx"])
        XCTAssertEqual(chunks.joined(), text)
    }

    func testExactlyAtCeilingStaysOneChunk() {
        let chunker = TranscriptChunker(maximumCharacters: 10)
        let text = "0123456789"
        XCTAssertEqual(chunker.chunks(of: text), [text])
    }

    func testDefaultCeilingStaysUnderTheMeetingTurnLimit() {
        // The protocol allows 100,000 characters for a `meeting-transcript`
        // turn, and each submitted part also carries a short prompt wrapper.
        XCTAssertLessThan(TranscriptChunker().maximumCharacters + 500, 100_000)
    }

    func testMixedFittableWordsAndOverlongTokenAreAllPreserved() {
        let chunker = TranscriptChunker(maximumCharacters: 12)
        let text = "short words here " + String(repeating: "y", count: 20) + " trailing words"
        let chunks = chunker.chunks(of: text)

        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 12)
        }
        XCTAssertEqual(nonWhitespace(chunks.joined()), nonWhitespace(text))
    }

    func testConsecutiveOverlongLinesArePreserved() {
        let chunker = TranscriptChunker(maximumCharacters: 8)
        let first = String(repeating: "a", count: 10)
        let second = String(repeating: "b", count: 9)
        let chunks = chunker.chunks(of: "\(first)\n\(second)")

        XCTAssertEqual(chunks.joined(), first + second)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 8)
        }
    }
}
