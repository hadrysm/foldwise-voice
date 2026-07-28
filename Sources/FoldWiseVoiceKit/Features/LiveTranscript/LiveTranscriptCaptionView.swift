// The Live transcript caption surface (PRD #351), validated by the prototype in
// issue #346: a flat, shadowless card tethered above the unchanged Badge.
// Every word, label, and role it draws comes from
// LiveTranscriptCaptionPresentation; this file only renders.

import SwiftUI

final class LiveTranscriptCaptionModel: ObservableObject {
    @Published var presentation: LiveTranscriptCaptionPresentation?
    /// Slides the tether so it keeps pointing at the Badge after the caption has
    /// been clamped to a screen edge.
    @Published var tetherOffset: CGFloat = 0
}

struct LiveTranscriptCaptionView: View {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject var model: LiveTranscriptCaptionModel
    private let increaseContrastOverride: Bool?

    init(model: LiveTranscriptCaptionModel, increaseContrastOverride: Bool? = nil) {
        self.model = model
        self.increaseContrastOverride = increaseContrastOverride
    }

    var body: some View {
        VStack(spacing: 0) {
            if let presentation = model.presentation {
                card(presentation)
                tether
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var increaseContrast: Bool {
        increaseContrastOverride ?? (colorSchemeContrast == .increased)
    }

    private func card(_ presentation: LiveTranscriptCaptionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header(presentation)
            text(presentation)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(LiveTranscriptCaptionPresentation.lineLimit)
                .truncationMode(
                    LiveTranscriptCaptionPresentation.truncatesHead ? .head : .tail
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Theme.essentialBorderColor(increaseContrast: increaseContrast),
                    lineWidth: Theme.essentialBorderWidth(increaseContrast: increaseContrast)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
    }

    private func header(_ presentation: LiveTranscriptCaptionPresentation) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(presentation.recedesCommitted ? Theme.warning : Theme.accent)
                .frame(width: 5, height: 5)
            Text(presentation.header)
                .font(Theme.mono(9, .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            if let handoff = presentation.handoff {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8, weight: .semibold))
                    Text(handoff)
                        .font(Theme.ui(9.5, .semibold))
                }
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
            }
        }
    }

    /// One `Text` concatenation rather than a stack, so the two spans wrap and
    /// head-truncate as a single run of words.
    private func text(_ presentation: LiveTranscriptCaptionPresentation) -> some View {
        (
            Text(presentation.committed)
                .foregroundStyle(
                    presentation.recedesCommitted ? Theme.textSecondary : Theme.textPrimary
                )
                + Text(presentation.tentative)
                .foregroundStyle(Theme.textPrimary.opacity(0.48))
                + Text(presentation.marksLiveFrontier ? "  •" : "")
                .foregroundStyle(Theme.accent.opacity(0.72))
        )
        .font(Theme.ui(12.5, .medium))
    }

    private var tether: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.accent.opacity(0.58))
                .frame(width: 1, height: 7)
            Circle()
                .fill(Theme.accent)
                .frame(width: 4, height: 4)
        }
        .frame(height: LiveTranscriptCaptionFramePolicy.badgeGap + 9)
        .offset(x: model.tetherOffset)
        .accessibilityHidden(true)
    }
}
