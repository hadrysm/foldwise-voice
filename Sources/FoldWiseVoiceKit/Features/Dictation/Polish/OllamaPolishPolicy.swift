import Foundation

extension OllamaClient {
    /// A generous `max_tokens` backstop for a Polish request, sized from the
    /// transcript length and Mode category. Its only job is to stop UNBOUNDED
    /// runaway — never to bound legitimate expansion tightly: a truncated
    /// legitimate output stays high-overlap, so it reads as on-task and the
    /// off-task check cannot rescue it. Expanding Modes get a larger multiple and
    /// a higher floor (a short dictation can become a full email — the floor
    /// governs short inputs); In-place Modes track the transcript, so a tighter
    /// multiple catches a runaway sooner. Kept pure — no network — so the sizing
    /// is directly assertable, mirroring `deleteOutcome`.
    static func maxPolishTokens(transcriptCharacterCount count: Int, expands: Bool) -> Int {
        // ~4 chars per English token; precision is unimportant for a generous cap.
        let estimatedTranscriptTokens = max(0, count) / 4
        let floor = expands ? 512 : 256
        let multiple = expands ? 4 : 2
        return max(floor, multiple * estimatedTranscriptTokens)
    }

    /// Builds the Polish request body for Ollama's native `/api/chat` endpoint.
    /// The native response exposes model-load, prompt-evaluation, and generation
    /// durations, which the OpenAI-compatible endpoint omits. Kept pure — no
    /// network — so its shape is directly assertable, mirroring `deleteOutcome`.
    static func chatRequestBody(
        model: String, system: String, user: String, maxTokens: Int
    ) -> [String: Any] {
        [
            "model": model,
            "stream": false,
            "keep_alive": keepAlive,
            "options": [
                "temperature": 0,
                "num_predict": maxTokens,
            ],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
    }

    /// Strips prompt scaffolding and model narration from a Polish response,
    /// leaving only the transformed text. Small local models narrate their
    /// work ("Here is…", "Changes: …") and echo request delimiters; this
    /// removes those known-bad patterns only — it never truncates by length,
    /// so legitimate Email/Bullets expansion survives. Returns "" when
    /// nothing but chatter remains, which drives the raw-transcript fallback.
    static func sanitize(_ output: String) -> String {
        var text = output
        for delimiter in ["<transcript>", "</transcript>"] {
            text = text.replacingOccurrences(of: delimiter, with: "")
        }
        var lines = text.components(separatedBy: "\n")

        // A model that labels its final answer ("Corrected: …") has buried
        // the real result under narration — keep only the labeled answer.
        if let index = lines.lastIndex(where: isAnswerLabel) {
            var kept = Array(lines[(index + 1)...])
            if let colon = lines[index].firstIndex(of: ":") {
                kept.insert(String(lines[index][lines[index].index(after: colon)...]), at: 0)
            }
            lines = kept
        }

        if let index = lines.firstIndex(where: isMetaLabel) {
            lines.removeSubrange(index...)
        }

        if let index = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }), isPreambleLine(lines[index]) {
            lines.remove(at: index)
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Corrected:", "Corrected text is:", … — a label the model puts on its
    /// final answer.
    private static func isAnswerLabel(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).range(
            of: #"^corrected(\s+\w+){0,2}\s*:"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// "Changes: …" — a trailing block explaining what the model did.
    private static func isMetaLabel(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).range(
            of: #"^changes(\s+made)?\s*:"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// A narration opener ("Here is the cleaned text:") is only stripped when
    /// it both ends with ":" and names the rewrite — a dictated colon-headed
    /// line like "Here is what we need:" must survive.
    private static func isPreambleLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard trimmed.hasSuffix(":") else { return false }
        let openers = [
            "here is", "here's", "sure", "certainly", "of course", "okay",
            "the ", "after ",
        ]
        guard openers.contains(where: trimmed.hasPrefix) else { return false }
        let keywords = [
            "correct", "clean", "extract", "polish", "transform", "rewrit",
            "revis", "format", "transcript", "text", "version", "result",
            "output", "sentence", "you go",
        ]
        return keywords.contains(where: trimmed.contains)
    }

    // MARK: - off-task detection (#72)

    // Overlap below which an In-place polish has drifted too far from the
    // transcript; the loose FLOOR paired with a length blow-up catches the
    // "wrote me a verse" case in any Mode. Set by OllamaOffTaskTests, not
    // guessed — see that fixture table for the keep/fallback separation.
    private static let STRICT_OVERLAP = 0.5
    private static let FLOOR_OVERLAP = 0.3
    private static let BLOWUP_FACTOR = 1.5

    /// Known assistant/refusal openers, as word lists. A candidate that *begins*
    /// with one — and whose words the user did not speak — is a model reply, not
    /// a transform. Tokenized the same way as the compared text so apostrophes
    /// and commas never matter.
    private static let refusalOpeners: [[String]] = [
        "i'm sorry", "i am sorry", "i apologize", "i cannot", "i can't", "i can not",
        "i'm not able to", "i am not able to", "i'm unable to", "i am unable to",
        "i'm afraid i can't", "sorry i can't", "unfortunately i can't",
        "i won't be able to", "as an ai",
    ].map(words)

    /// The verdict of the off-task check plus the signals behind it, kept
    /// together so the Pipeline can log which rule fired and its scores without
    /// recomputing them.
    struct OffTaskVerdict {
        /// True when the candidate should be discarded for the raw transcript.
        let fellBack: Bool
        /// The rule that fired — "overlap", "blowup", or "refusal" — or "" when
        /// the polish was kept. Logged at public level; carries no content.
        let signal: String
        let overlap: Double
        let lengthRatio: Double
    }

    /// Whether a Polish candidate is a *reply to* the transcript (an answer,
    /// refusal, or poem) rather than a *transform* of it, in which case the
    /// session pastes the raw transcript instead. Pure so the thresholds are
    /// pinned by a fixture table without a network, mirroring `deleteOutcome`.
    ///
    /// Word-overlap is the backbone and assumes a language- and
    /// content-preserving transform (ADR-0004): a Mode that translates or
    /// heavily summarizes shares almost no words and would false-fall-back, so
    /// such Modes are out of scope. `expands` loosens the calibration for
    /// Expanding Modes, whose legitimate output has honestly lower overlap.
    static func isOffTask(_ candidate: String, transcript: String, expands: Bool) -> Bool {
        offTaskVerdict(candidate, transcript: transcript, expands: expands).fellBack
    }

    /// The decision behind `isOffTask`, with the signals exposed for logging.
    /// The OR-of-rules is the decision: fall back when an In-place polish drifts
    /// below the strict overlap, when any polish combines low overlap with a
    /// length blow-up, or when it opens with a refusal the user did not speak.
    static func offTaskVerdict(_ candidate: String, transcript: String, expands: Bool) -> OffTaskVerdict {
        let transcriptWords = words(transcript)
        let candidateWords = words(candidate)
        let transcriptSet = Set(transcriptWords)
        let candidateSet = Set(candidateWords)

        let overlap = transcriptSet.isEmpty
            ? 1.0
            : Double(transcriptSet.intersection(candidateSet).count) / Double(transcriptSet.count)
        let lengthRatio = transcriptWords.isEmpty
            ? 1.0
            : Double(candidateWords.count) / Double(transcriptWords.count)

        func verdict(_ fellBack: Bool, _ signal: String) -> OffTaskVerdict {
            OffTaskVerdict(fellBack: fellBack, signal: signal, overlap: overlap, lengthRatio: lengthRatio)
        }

        // A refusal opener the user did not speak — the Mode-invariant net. The
        // "words absent" guard keeps a *dictated* refusal ("I can't help…"),
        // whose opener words are in the transcript.
        if let opener = refusalOpeners.first(where: { candidateWords.starts(with: $0) }),
           opener.allSatisfy({ !transcriptSet.contains($0) }) {
            return verdict(true, "refusal")
        }
        // In-place Modes must track the transcript closely.
        if !expands, overlap < STRICT_OVERLAP {
            return verdict(true, "overlap")
        }
        // The "wrote me a verse" case: little of the transcript survives and the
        // output ballooned — caught even in an Expanding Mode.
        if overlap < FLOOR_OVERLAP, lengthRatio > BLOWUP_FACTOR {
            return verdict(true, "blowup")
        }
        return verdict(false, "")
    }

    /// Lowercased, punctuation-stripped word tokens. Swift has characters, not
    /// model tokens, so the overlap and length signals compare words; both the
    /// transcript and the candidate go through this same splitter.
    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
