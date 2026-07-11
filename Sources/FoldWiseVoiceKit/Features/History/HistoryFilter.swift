import Foundation

/// The History pane's list filter, kept a pure function so its matching rules
/// are unit-tested apart from the (untested) SwiftUI view (PRD #78). Narrows to
/// flagged rows when `flaggedOnly` is set, then keeps rows whose polished `text`
/// or raw `rawText` contains `query` — case-insensitively, so a dictation is
/// found by any words it contained whichever version the user remembers. A
/// blank query matches every row. Order-preserving.
enum HistoryFilter {
    static func apply(
        to entries: [HistoryEntry], query: String, flaggedOnly: Bool
    ) -> [HistoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if flaggedOnly, !entry.flagged { return false }
            guard !needle.isEmpty else { return true }
            return entry.text.localizedCaseInsensitiveContains(needle)
                || entry.rawText.localizedCaseInsensitiveContains(needle)
        }
    }
}
