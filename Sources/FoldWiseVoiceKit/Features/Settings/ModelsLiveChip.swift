import SwiftUI

/// The streaming capability, stated beside a Speech model's name (ADR-0009). It
/// reads as a distinction rather than as a footnote, which the clause it
/// replaced inside the row's `fit` detail could not do.
///
/// Deliberately *not* called a badge: **Badge** is the floating recording pill
/// (see `CONTEXT.md`), and this is an inline label inside the Models ledger.
///
/// It carries no accessibility label of its own. The row and the inspector each
/// fold "transcribes live while you speak" into their own labels through
/// `ModelsStreamingCopy`, so labelling the chip too would make VoiceOver say the
/// capability twice.
struct ModelsLiveChip: View {
    var body: some View {
        HStack(spacing: 2.5) {
            Image(systemName: "waveform")
                .font(Theme.ui(7.5, .bold))
            Text("LIVE")
                .font(Theme.ui(8, .bold))
                .kerning(0.5)
                // The row lets its name truncate; the chip is four letters and
                // must not wrap when it doesn't have to.
                .fixedSize()
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(Theme.accent.opacity(0.15), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.accent.opacity(0.38), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
