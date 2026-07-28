// What a Streaming ASR model publishes while the user is still speaking
// (ADR-0009). The FluidAudio streaming managers report the *whole* transcript
// they have decoded so far, and separately mark an utterance boundary as final;
// this file turns those absolute reports into the committed/tentative contract
// that the Live transcript caption renders and that last-resort recovery reads.

import Foundation

/// A Transcript snapshot: an append-only `committed` prefix plus a `tentative`
/// suffix that later audio may still rewrite.
struct TranscriptSnapshot: Equatable {
    let committed: String
    let tentative: String

    static let empty = TranscriptSnapshot(committed: "", tentative: "")

    /// Everything recognized so far. A concatenation rather than a join, so the
    /// engine's own spacing survives and the caption's text agrees with the
    /// final transcript character for character.
    var text: String {
        committed + tentative
    }

    var isEmpty: Bool {
        committed.isEmpty && tentative.isEmpty
    }
}

/// Owns one live attempt's snapshot state. Separate from the stream that drives
/// the engine so the committed-prefix rules stay value-in, value-out.
struct TranscriptAccumulator {
    private(set) var snapshot: TranscriptSnapshot = .empty

    /// Everything the engine has decoded so far, including text it may revise.
    @discardableResult
    mutating func observeTentative(_ text: String) -> TranscriptSnapshot {
        // The report is split at the committed boundary rather than appended
        // after it, so a re-detokenized read that differs inside the committed
        // span neither repeats nor mangles the words around the boundary — the
        // committed text simply wins, which is what append-only means.
        let boundary = snapshot.committed.count
        // A report that no longer reaches the boundary would unsay committed
        // words, so it is dropped: the boundary only ever moves forward.
        guard text.count >= boundary else { return snapshot }
        snapshot = TranscriptSnapshot(
            committed: snapshot.committed,
            tentative: String(text.dropFirst(boundary))
        )
        return snapshot
    }

    /// Everything up to an utterance boundary the engine declares final.
    @discardableResult
    mutating func commit(_ text: String) -> TranscriptSnapshot {
        // Append-only: a boundary that is shorter than, or diverges from, what is
        // already committed cannot take back words the caption has shown as
        // settled, so it is ignored rather than applied.
        guard text.count > snapshot.committed.count, text.hasPrefix(snapshot.committed) else {
            return snapshot
        }
        // Re-split the same recognized text at the new boundary, so committing
        // never changes what has been recognized — only where the line falls.
        let recognized = snapshot.text
        snapshot = TranscriptSnapshot(
            committed: text,
            tentative: recognized.hasPrefix(text)
                ? String(recognized.dropFirst(text.count))
                : ""
        )
        return snapshot
    }

    /// The stream's own `finish()` result, which *is* the transcript (ADR-0009),
    /// so it replaces both spans instead of extending them.
    @discardableResult
    mutating func finalize(_ text: String) -> TranscriptSnapshot {
        snapshot = TranscriptSnapshot(committed: text, tentative: "")
        return snapshot
    }
}
