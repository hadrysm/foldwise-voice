// The floating Badge pill (PRDs #103 and #260), drawn entirely in SwiftUI:
// a fixed adaptive capsule with Ember Trace semantics, a static idle glyph,
// hover action row, and the mic-reactive recording canvas. GPU-driven via
// TimelineView + Canvas — no main-thread drawing loop.
// All state transitions come from the Badge reducers via the controller; this
// file only renders `BadgeModel`.

import SwiftUI

final class BadgeModel: ObservableObject {
    @Published var state: BadgeState = .idle
    @Published var modeCycleDisplay: BadgeModeCycleDisplay?
    @Published var recordingSeconds = 0
    @Published var activeModeName = ""
    /// Pretty label of the dictation hotkey ("right ⌥"), for the mic tooltip.
    @Published var hotkeyLabel = ""
    /// Smoothed ribbon amplitude in [0.10, 0.45]; mutated by the controller at
    /// 30 Hz while recording. Not @Published — TimelineView redraws anyway.
    var amplitude: Double = LevelSmoother.floor
    #if BADGE_TRANSCRIPT_PROTOTYPE
        let transcriptPrototype = BadgeTranscriptPrototypeModel()
    #endif
}

struct BadgeEnvironmentAdaptations: Equatable {
    let reduceMotion: Bool
    let increaseContrast: Bool
}

struct BadgeView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject var model: BadgeModel
    let onHover: (Bool) -> Void
    let onClick: () -> Void
    let onChangeMode: () -> Void
    let onRecord: () -> Void
    let onOpenApp: () -> Void
    let onReduceMotionChanged: (Bool) -> Void
    private let environmentOverride: BadgeEnvironmentAdaptations?

    init(
        model: BadgeModel,
        onHover: @escaping (Bool) -> Void,
        onClick: @escaping () -> Void,
        onChangeMode: @escaping () -> Void,
        onRecord: @escaping () -> Void,
        onOpenApp: @escaping () -> Void,
        onReduceMotionChanged: @escaping (Bool) -> Void = { _ in },
        environmentOverride: BadgeEnvironmentAdaptations? = nil
    ) {
        self.model = model
        self.onHover = onHover
        self.onClick = onClick
        self.onChangeMode = onChangeMode
        self.onRecord = onRecord
        self.onOpenApp = onOpenApp
        self.onReduceMotionChanged = onReduceMotionChanged
        self.environmentOverride = environmentOverride
    }

    var body: some View {
        ZStack {
            Capsule().fill(Theme.surface)
            content
                .transition(contentTransition)
        }
        .overlay {
            Capsule().strokeBorder(
                borderColor,
                lineWidth: resolvedEnvironment.increaseContrast ? 2 : 1
            )
        }
        .contentShape(Capsule())
        .onHover(perform: onHover)
        .onTapGesture(perform: onClick)
        .animation(ordinaryAnimation, value: model.state)
        .onAppear { onReduceMotionChanged(resolvedEnvironment.reduceMotion) }
        .onChange(of: accessibilityReduceMotion) { _, reduced in
            onReduceMotionChanged(environmentOverride?.reduceMotion ?? reduced)
        }
    }

    private var borderColor: Color {
        switch visualPresentation.role {
        case .neutral:
            resolvedEnvironment.increaseContrast ? Theme.borderStrong : Theme.border
        case .active:
            Theme.accent
        case .success:
            Theme.success
        case .error:
            Theme.error
        }
    }

    private var visualPresentation: BadgeVisualPresentation {
        BadgeVisualPolicy.presentation(
            for: model.state,
            presentsModeCycle: model.modeCycleDisplay != nil
        )
    }

    private var resolvedEnvironment: BadgeEnvironmentAdaptations {
        environmentOverride ?? BadgeEnvironmentAdaptations(
            reduceMotion: accessibilityReduceMotion,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    private var motion: BadgeMotionPresentation {
        BadgeMotionPolicy.presentation(reduceMotion: resolvedEnvironment.reduceMotion)
    }

    private var ordinaryAnimation: Animation? {
        motion.ordinaryTransitionDuration.map(Animation.easeOut(duration:))
    }

    private var contentTransition: AnyTransition {
        motion.ordinaryTransitionDuration == nil
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.9))
    }

    @ViewBuilder
    private var content: some View {
        switch visualPresentation.cue {
        case .idleGlyph:
            BadgeIdleGlyph()
        case .hoverActions:
            hoverActions
        case .ribbonsAndTimer:
            HStack(spacing: 10) {
                RibbonCanvas(
                    live: true,
                    amplitude: { model.amplitude },
                    motion: motion
                )
                .frame(height: 20)
                Text(timerText)
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 13)
        case .ribbonsAndSpinner:
            HStack(spacing: 10) {
                workingRibbon
                BadgeSpinner(motion: motion)
            }
            .padding(.horizontal, 13)
        case .ribbonsAndStatus:
            HStack(spacing: 10) {
                workingRibbon
                statusLine
            }
            .padding(.horizontal, 13)
        case .checkmarkAndText:
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.success)
                Text("inserted")
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
        case .warningAndText:
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.error)
                statusLine
            }
            .padding(.horizontal, 13)
        case .modeSelection:
            if let modeCycleDisplay = model.modeCycleDisplay {
                BadgeModeCycleReel(display: modeCycleDisplay)
            }
        }
    }

    private var workingRibbon: some View {
        RibbonCanvas(
            live: false,
            amplitude: { 0.18 },
            motion: motion
        )
        .frame(height: 20)
    }

    private var statusLine: some View {
        Text(model.state.statusText ?? "")
            .font(Theme.mono(11, .medium))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
    }

    private var timerText: String {
        let minutes = model.recordingSeconds / 60
        let seconds = model.recordingSeconds % 60
        return "\(minutes):" + String(format: "%02d", seconds)
    }

    /// The three hover actions: mode picker, dictate, open the app. Native
    /// `.help` tooltips keep the non-activating panel's focus discipline —
    /// they never make the panel key.
    private var hoverActions: some View {
        HStack(spacing: 8) {
            BadgeRoundButton(
                symbol: "sparkles", diameter: 28, emphasized: false,
                motion: motion, action: onChangeMode
            )
            .help("Mode: \(model.activeModeName)")
            .accessibilityLabel(
                BadgeHoverAccessibility.selectionLabel(currentSelection: model.activeModeName)
            )
            BadgeRoundButton(
                symbol: "mic.fill", diameter: 30, emphasized: true,
                motion: motion, action: onRecord
            )
            .help("Dictate — \(model.hotkeyLabel)")
            .accessibilityLabel(
                BadgeHoverAccessibility.recordLabel(shortcut: model.hotkeyLabel)
            )
            BadgeRoundButton(
                symbol: "arrow.up.left.and.arrow.down.right", diameter: 28,
                emphasized: false, motion: motion, action: onOpenApp
            )
            .help("Open FoldWise")
            .accessibilityLabel(BadgeHoverAccessibility.openAppLabel)
        }
        .padding(.horizontal, 6)
    }
}

#if BADGE_TRANSCRIPT_PROTOTYPE

    struct BadgeTranscriptPrototypeCaption: View {
        @ObservedObject var prototype: BadgeTranscriptPrototypeModel

        var body: some View {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(phaseColor)
                            .frame(width: 5, height: 5)
                        Text(captionLabel)
                            .font(Theme.mono(9, .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                        if let handoffLabel {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(handoffLabel)
                                    .font(Theme.ui(9.5, .semibold))
                            }
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                        }
                    }
                    captionText
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                        .truncationMode(.head)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.border, lineWidth: 1)
                }

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.accent.opacity(0.58))
                        .frame(width: 1, height: 7)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 4, height: 4)
                }
                .frame(height: 11)
                .offset(x: prototype.captionTetherOffset)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }

        @ViewBuilder
        private var captionText: some View {
            if prototype.fullTranscript.isEmpty {
                Text("Listening for words…")
                    .font(Theme.ui(12.5, .medium))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                (
                    Text(prototype.confirmed)
                        .foregroundStyle(
                            prototype.phase == .polishing
                                ? Theme.textSecondary
                                : Theme.textPrimary
                        )
                        + Text(prototype.confirmed.isEmpty || prototype.tentative.isEmpty ? "" : " ")
                        + Text(prototype.tentative)
                        .foregroundStyle(Theme.textPrimary.opacity(0.48))
                        + Text(prototype.tentative.isEmpty ? "" : "  •")
                        .foregroundStyle(Theme.accent.opacity(0.72))
                )
                .font(Theme.ui(12.5, .medium))
            }
        }

        private var captionLabel: String {
            switch prototype.phase {
            case .listening:
                "RAW · LIVE"
            case .transcribing:
                "RAW · LOCKED"
            case .polishing:
                "RAW · LOCKED"
            case .idle, .finished, .failed:
                "RAW"
            }
        }

        private var handoffLabel: String? {
            switch prototype.phase {
            case .transcribing:
                "finalizing speech…"
            case .polishing:
                "shaping as \(prototype.modeName)…"
            case .idle, .listening, .finished, .failed:
                nil
            }
        }

        private var phaseColor: Color {
            switch prototype.phase {
            case .polishing:
                Theme.warning
            case .failed:
                Theme.error
            case .idle, .listening, .transcribing, .finished:
                Theme.accent
            }
        }
    }

#endif

private struct BadgeModeCycleReel: View {
    let display: BadgeModeCycleDisplay

    var body: some View {
        ZStack {
            if let outgoing = display.outgoing {
                row(outgoing)
                    .opacity(display.outgoingOpacity)
                    .offset(y: display.outgoingOffset)
            }
            row(display.destination)
                .opacity(display.incomingOpacity)
                .offset(y: display.incomingOffset)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(display.animatesSwap ? animation : nil, value: display.phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(display.accessibilityLabel)
        .accessibilityValue("Selected Mode")
    }

    private var animation: Animation {
        switch display.motion {
        case .standard:
            .timingCurve(0.4, 0, 0.2, 1, duration: BadgeModeCycleReducer.swapDuration)
        case .reduced:
            .easeOut(duration: BadgeModeCycleReducer.reducedSwapDuration)
        }
    }

    private func row(_ item: BadgeModeCycleItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(item.name)
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct BadgeRoundButton: View {
    let symbol: String
    let diameter: CGFloat
    /// The mic gets a standing tint and a slight hover scale-up.
    let emphasized: Bool
    let motion: BadgeMotionPresentation
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(background))
                .scaleEffect(emphasized && hovering ? motion.emphasizedHoverScale : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(hoverAnimation, value: hovering)
    }

    private var iconColor: Color {
        if emphasized {
            return hovering ? Theme.accentHover : Theme.accent
        }
        return hovering ? Theme.textPrimary : Theme.textSecondary
    }

    private var background: Color {
        if emphasized {
            return hovering ? Theme.hover : Theme.raised
        }
        return hovering ? Theme.hover : .clear
    }

    private var hoverAnimation: Animation? {
        motion.ordinaryTransitionDuration.map(Animation.easeOut(duration:))
    }
}

/// The idle "···|·|·" glyph: rounded dots and bars, drawn motionless. Idle
/// must sit still — element-by-element height/opacity motion reads as
/// "listening" — and a static Canvas spares the timeline redraw loop while
/// the badge idles. Geometry is locked by BadgeIdleSilhouetteTests;
/// motionlessness is covered by the manual macOS smoke procedure.
struct BadgeIdleGlyph: View {
    /// Element heights in points; 3.5pt-wide dots (3.5) and bars (12, 7).
    private static let heights: [CGFloat] = [3.5, 3.5, 3.5, 12, 3.5, 7, 3.5]

    var body: some View {
        Canvas { ctx, size in
            let count = Self.heights.count
            let width: CGFloat = 3.5
            let gap: CGFloat = 3.5
            let total = CGFloat(count) * width + CGFloat(count - 1) * gap
            let x0 = (size.width - total) / 2
            for (i, height) in Self.heights.enumerated() {
                let rect = CGRect(
                    x: x0 + CGFloat(i) * (width + gap),
                    y: (size.height - height) / 2,
                    width: width, height: height
                )
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(Theme.accent)
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// The small working spinner: a 12pt arc in the badge palette, rotated by
/// the same TimelineView clock as the other badge animations — no implicit
/// animations inside the non-activating panel.
struct BadgeSpinner: View {
    let motion: BadgeMotionPresentation

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: motion.pausesDecorativeTimelines
        )) { context in
            let t = motion.representativeTimelineTime
                ?? context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
        }
        .allowsHitTesting(false)
    }
}

/// The Ember Trace animation: four orange-led strands over a subtle accent
/// baseline, flattened at the edges by a sin² envelope. `live` ribbons move
/// at the recording speed with mic-driven amplitude; calm ribbons use the
/// fixed working amplitude.
struct RibbonCanvas: View {
    let live: Bool
    /// Sampled every frame; recording feeds the smoothed mic level.
    let amplitude: () -> Double
    let motion: BadgeMotionPresentation

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: motion.pausesDecorativeTimelines
        )) { context in
            let time = motion.representativeTimelineTime
                ?? context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                drawBaseline(&ctx, size: size)
                drawStrands(&ctx, size: size, t: time * 1000)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawBaseline(_ ctx: inout GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: size.height / 2))
        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Theme.Badge.baseline, location: 0.15),
            .init(color: Theme.Badge.baseline, location: 0.85),
            .init(color: .clear, location: 1),
        ])
        ctx.stroke(
            line,
            with: .linearGradient(
                gradient,
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            ),
            lineWidth: 1
        )
    }

    private func drawStrands(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width
        let h = size.height
        let speed = live ? 0.0009 : 0.00045
        let amp = motion.ribbonAmplitude(
            live: live,
            sampledAmplitude: amplitude()
        )
        let flat = 0.09
        for strand in 0 ..< 4 {
            let i = Double(strand)
            let color = Theme.Badge.ribbonPalette[strand]
            let phase = i * 1.7
            let freq = 0.010 + i * 0.0032
            let drift = sin(t * 0.00012 + i) * 0.12
            var strandCtx = ctx
            strandCtx.blendMode = .plusLighter
            for sub in 0 ..< 3 {
                let s = Double(sub)
                var path = Path()
                var x = 0.0
                while x <= w {
                    let u = x / w
                    let eu = min(1, max(0, (u - flat) / (1 - 2 * flat)))
                    let env = pow(sin(.pi * eu), 2)
                    let y = h / 2
                        + sin(x * freq + t * speed * (1 + i * 0.13) + phase + s * 0.5)
                        * h * amp * env
                        + sin(x * 0.004 + t * 0.0002 + i) * h * 0.06 * env
                        + drift * h * env * 0.3
                    if x == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    x += 2
                }
                strandCtx.stroke(
                    path,
                    with: .color(color.opacity(0.5 / 3 + 0.08)),
                    lineWidth: sub == 0 ? 1.6 : 1.0
                )
            }
        }
    }
}
