/// Re-runs the Polish stage on a stored dictation (PRD #78). It takes the
/// entry's `rawText` — the pre-Polish transcript kept for exactly this — runs
/// Polish under a Mode the user picks, and overwrites the row's
/// `text`/`isPolished`/`modeName` before persisting through the store. It works
/// on stored TEXT only; no audio is ever needed or decoded. The keep-or-fall-
/// back rule is the live session's: a candidate that reads as a reply rather
/// than a transform is discarded for the raw transcript (ADR-0004), so a re-run
/// can only ever improve or leave a row unchanged, never replace it with an
/// off-task answer. The `polish` seam mirrors the Pipeline's, injected so a test
/// drives the outcome without Ollama.
final class HistoryReprocessor {
    private let store: HistoryStore
    private let polish: (String, Mode) async -> String

    init(
        store: HistoryStore,
        polish: @escaping (String, Mode) async -> String = Pipeline.ollamaPolish
    ) {
        self.store = store
        self.polish = polish
    }

    /// Runs Polish on `entry.rawText` under `mode`, keeping the candidate only
    /// when it survives the off-task check, then persists and returns the updated
    /// entry. A Mode that does not polish, or a transcript too short to polish,
    /// resolves to the raw transcript marked unpolished — the same gate the live
    /// session applies.
    @discardableResult
    func rerunPolish(_ entry: HistoryEntry, mode: Mode) async -> HistoryEntry {
        var updated = entry
        // `modeName` records which Mode was applied, matching the live session's
        // convention (set to the session's Mode whether or not Polish survived);
        // the row displays it, so leaving it stale would misattribute the text.
        updated.modeName = mode.name
        updated.modeID = mode.id
        // Same keep-or-fall-back decision as the live session, from the shared
        // `Polish.run` (ADR-0004): the short-input gate and the off-task check
        // are defined once, so Re-run can only ever match what the session does.
        let polished = await Polish.run(rawText: entry.rawText, mode: mode, polish: polish)
        updated.text = polished.text
        updated.isPolished = polished.isPolished
        store.update(updated)
        return updated
    }
}
