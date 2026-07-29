// The Live transcript caption surface (PRD #351), validated by the prototype in
// issue #346: a flat, shadowless card tethered above the unchanged Badge.
// Every word, label, and role it draws comes from
// LiveTranscriptCaptionPresentation; this file only renders.

import AppKit
import SwiftUI

final class LiveTranscriptCaptionModel: ObservableObject {
    @Published var presentation: LiveTranscriptCaptionPresentation?
    /// Slides the tether so it keeps pointing at the Badge after the caption has
    /// been clamped to a screen edge.
    @Published var tetherOffset: CGFloat = 0
    /// Fires from the caption's own AppKit draw. Nil in the shipping app, so the
    /// production view tree is unchanged; the streaming latency gate (PRD #351)
    /// refuses a first-feedback measurement that was not taken from a real
    /// caption render, and this is where that render is observed.
    var onRender: (@MainActor (LiveTranscriptCaptionPresentation) -> Void)?
}

@MainActor
final class LiveTranscriptCaptionRenderView: NSView {
    var presentation: LiveTranscriptCaptionPresentation
    var onRender: @MainActor (LiveTranscriptCaptionPresentation) -> Void

    init(
        presentation: LiveTranscriptCaptionPresentation,
        onRender: @escaping @MainActor (LiveTranscriptCaptionPresentation) -> Void
    ) {
        self.presentation = presentation
        self.onRender = onRender
        super.init(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let presentation = presentation
        let onRender = onRender
        DispatchQueue.main.async { onRender(presentation) }
    }
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
        .overlay(alignment: .topLeading) {
            if let onRender = model.onRender {
                LiveTranscriptCaptionRenderMarker(
                    presentation: presentation,
                    onRender: onRender
                )
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
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

    /// A one-point draw marker inside the caption's own view tree — the same
    /// mechanism the pane harness uses for first-meaningful-frame, so "the
    /// caption appeared" means AppKit drew it rather than a snapshot arriving.
    private struct LiveTranscriptCaptionRenderMarker: NSViewRepresentable {
        let presentation: LiveTranscriptCaptionPresentation
        let onRender: @MainActor (LiveTranscriptCaptionPresentation) -> Void

        func makeNSView(context _: Context) -> LiveTranscriptCaptionRenderView {
            LiveTranscriptCaptionRenderView(presentation: presentation, onRender: onRender)
        }

        func updateNSView(_ view: LiveTranscriptCaptionRenderView, context _: Context) {
            view.presentation = presentation
            view.onRender = onRender
            view.needsDisplay = true
        }
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
