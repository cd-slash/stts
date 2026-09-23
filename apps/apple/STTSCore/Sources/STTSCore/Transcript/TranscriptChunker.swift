import Foundation

/// Splits a long transcript into ordered chunks small enough to submit as
/// individual turns, so summarization never has to discard text.
///
/// Chunking prefers line boundaries (meeting transcripts are newline-joined
/// segment texts), falls back to word boundaries, and only hard-splits a
/// single token that cannot fit. Concatenating the returned chunks reproduces
/// every non-whitespace character of the input in order.
public struct TranscriptChunker: Sendable, Equatable {
    public let maximumCharacters: Int

    public init(maximumCharacters: Int = 18_000) {
        self.maximumCharacters = max(1, maximumCharacters)
    }

    public func chunks(of text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > maximumCharacters else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        func flush() {
            let value = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { chunks.append(value) }
            current = ""
        }

        // Line boundaries first: transcripts are newline-joined segments, so a
        // line is the most semantically meaningful split point.
        for line in trimmed.components(separatedBy: .newlines) {
            let piece = line.trimmingCharacters(in: .whitespaces)
            guard !piece.isEmpty else { continue }

            if fits(piece) {
                if current.isEmpty {
                    current = piece
                } else if current.count + 1 + piece.count <= maximumCharacters {
                    current += "\n" + piece
                } else {
                    flush()
                    current = piece
                }
                continue
            }

            // A single line longer than the ceiling: split on words, then hard.
            flush()
            for word in piece.split(separator: " ", omittingEmptySubsequences: true) {
                let token = String(word)
                if fits(token) {
                    if current.isEmpty {
                        current = token
                    } else if current.count + 1 + token.count <= maximumCharacters {
                        current += " " + token
                    } else {
                        flush()
                        current = token
                    }
                } else {
                    flush()
                    chunks.append(contentsOf: hardSplit(token))
                }
            }
            flush()
        }
        flush()
        return chunks
    }

    private func fits(_ value: String) -> Bool {
        value.count <= maximumCharacters
    }

    /// Splits a token that cannot fit on its own into fixed-size pieces.
    private func hardSplit(_ token: String) -> [String] {
        guard token.count > maximumCharacters else { return [token] }
        var pieces: [String] = []
        var start = token.startIndex
        while start < token.endIndex {
            let end = token.index(start, offsetBy: maximumCharacters, limitedBy: token.endIndex)
                ?? token.endIndex
            pieces.append(String(token[start..<end]))
            start = end
        }
        return pieces
    }
}
