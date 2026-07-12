// The Polish stage's keep-or-fall-back decision (ADR-0004), factored out as the
// single source of truth shared by the live dictation session (Pipeline) and
// Re-run Polish (HistoryReprocessor). Given a raw transcript and a Mode, it runs
// the injected polish stage and judges the candidate: a Mode that does not
// polish, or a transcript too short to polish, resolves to the raw transcript
// marked unpolished; otherwise the candidate is kept only when it survives the
// off-task check, and the raw transcript is restored when it does not. The gate
// (`Mode.willPolish`) and the off-task judging (`OllamaClient.offTaskVerdict`)
// therefore live in exactly one place, so the live and re-run paths cannot drift
// apart.

import Foundation

/// The result of running the Polish stage on a raw transcript under a Mode:
/// the text to keep, whether it is a surviving polish (as opposed to a fallback
/// to raw), and the off-task verdict when Polish actually ran — `nil` when it
/// was skipped (a raw Mode or a too-short transcript) — so a caller that wants
/// to log which rule fired can do so without recomputing it.
struct PolishOutcome {
    let text: String
    let isPolished: Bool
    let verdict: OllamaClient.OffTaskVerdict?
}

enum Polish {
    /// Runs the Polish stage on `rawText` under `mode` using the injected
    /// `polish` closure, then applies the keep-or-fall-back rule. See the file
    /// comment for the full contract. Pure of any UI or persistence: callers own
    /// emitting `.polishing`, logging the fallback, and writing the result.
    static func run(
        rawText: String, mode: Mode, polish: (String, Mode) async -> String
    ) async -> PolishOutcome {
        guard mode.willPolish(rawText) else {
            return PolishOutcome(text: rawText, isPolished: false, verdict: nil)
        }
        let candidate = await polish(rawText, mode)
        let verdict = OllamaClient.offTaskVerdict(
            candidate, transcript: rawText, expands: mode.expands
        )
        return PolishOutcome(
            text: verdict.fellBack ? rawText : candidate,
            isPolished: !verdict.fellBack,
            verdict: verdict
        )
    }
}
