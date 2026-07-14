// The floating Badge pill (PRD #103), drawn entirely in SwiftUI: a fixed
// adaptive capsule with a violet/ribbon identity that survives both appearances,
// static idle glyph, hover action row, and the silk-ribbon recording
// canvas. GPU-driven via TimelineView + Canvas — no main-thread drawing loop.
// All state transitions come from `BadgeReducer` via the controller; this
// file only renders `BadgeModel`.

import SwiftUI

final class BadgeModel: ObservableObject {
    @Published var state: BadgeState = .idle
    @Published var recordingSeconds = 0
    @Published var activeModeName = ""
    /// Pretty label of the dictation hotkey ("right ⌥"), for the mic tooltip.
    @Published var hotkeyLabel = ""
    /// Smoothed ribbon amplitude in [0.10, 0.45]; mutated by the controller at
    /// 30 Hz while recording. Not @Published — TimelineView redraws anyway.
    var amplitude: Double = LevelSmoother.floor
}

struct BadgeView: View {
    @ObservedObject var model: BadgeModel
    var onHover: (Bool) -> Void
    var onClick: () -> Void
    var onChangeMode: () -> Void
    var onRecord: () -> Void
    var onOpenApp: () -> Void

    var body: some View {
        ZStack {
            Capsule().fill(Theme.Badge.pillBackground)
            content
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
        // No glow or drop shadow: blurs smudge light wallpapers, and the
        // panel is exactly pill-sized so they'd clip anyway. The border and
        // the ribbons carry the state, not a halo.
        .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
        .contentShape(Capsule())
        .onHover(perform: onHover)
        .onTapGesture(perform: onClick)
        .animation(Theme.badgeCrossFade, value: model.state)
    }

    private var borderColor: Color {
        switch model.state {
        case .recording, .working: Theme.Badge.borderRecording
        case .error: Theme.Badge.borderError
        default: Theme.Badge.border
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            BadgeIdleGlyph()
        case .hover:
            hoverActions
        case .recording:
            HStack(spacing: 10) {
                RibbonCanvas(live: true, amplitude: { model.amplitude })
                    .frame(height: 20)
                Text(timerText)
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.Badge.timerText)
            }
            .padding(.horizontal, 13)
        case .working:
            HStack(spacing: 10) {
                RibbonCanvas(live: false, amplitude: { 0.18 })
                    .frame(height: 20)
                if model.state.statusText != nil {
                    statusLine
                } else {
                    BadgeSpinner()
                }
            }
            .padding(.horizontal, 13)
        case .done:
            HStack(spacing: 7) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Badge.iconEmphasized)
                Text("inserted")
                    .font(Theme.mono(11, .medium))
                    .foregroundStyle(Theme.Badge.timerText)
            }
        case .error:
            statusLine
                .padding(.horizontal, 13)
        }
    }

    private var statusLine: some View {
        Text(model.state.statusText ?? "")
            .font(Theme.mono(11, .medium))
            .foregroundStyle(Theme.Badge.timerText)
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
                symbol: "sparkles", diameter: 28, emphasized: false, action: onChangeMode
            )
            .help("Mode: \(model.activeModeName)")
            BadgeRoundButton(
                symbol: "mic.fill", diameter: 30, emphasized: true, action: onRecord
            )
            .help("Dictate — \(model.hotkeyLabel)")
            BadgeRoundButton(
                symbol: "arrow.up.left.and.arrow.down.right", diameter: 28,
                emphasized: false, action: onOpenApp
            )
            .help("Open FoldWise")
        }
        .padding(.horizontal, 6)
    }
}

private struct BadgeRoundButton: View {
    let symbol: String
    let diameter: CGFloat
    /// The mic gets a standing tint and a slight hover scale-up.
    let emphasized: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.36, weight: .semibold))
                .foregroundStyle(hovering || emphasized
                    ? Theme.Badge.iconEmphasized
                    : Theme.Badge.iconIdle)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(background))
                    .scaleEffect(emphasized && hovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    private var background: Color {
        if emphasized {
            return hovering ? Theme.Badge.buttonHover : Theme.Badge.buttonBackground
        }
        return hovering ? Theme.Badge.buttonBackground.opacity(0.6) : .clear
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
                let isBar = height > 3.5
                let rect = CGRect(
                    x: x0 + CGFloat(i) * (width + gap),
                    y: (size.height - height) / 2,
                    width: width, height: height
                )
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: width / 2),
                    with: .color(isBar ? Theme.Badge.iconEmphasized : Theme.Badge.iconIdle)
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
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .trim(from: 0, to: 0.72)
                .stroke(
                    Theme.Badge.timerText,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                )
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 1) * 360))
        }
        .allowsHitTesting(false)
    }
}

/// The silk-ribbon light animation (PRD #103): four additive-blended strands,
/// each drawn as three phase-offset sub-strokes over a gradient hairline,
/// flattened at the edges by a sin² envelope. `live` ribbons move at the
/// recording speed with mic-driven amplitude; calm ribbons (working state)
/// keep the slow idle-preview speed at a low fixed amplitude.
struct RibbonCanvas: View {
    let live: Bool
    /// Sampled every frame; recording feeds the smoothed mic level.
    let amplitude: () -> Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            // The spec's algorithm works in milliseconds.
            let t = context.date.timeIntervalSinceReferenceDate * 1000
            Canvas { ctx, size in
                drawBaseline(&ctx, size: size)
                drawStrands(&ctx, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawBaseline(_ ctx: inout GraphicsContext, size: CGSize) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: size.height / 2))
        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        let gradient = Gradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: Theme.Badge.baselineLeft, location: 0.15),
            .init(color: Theme.Badge.baselineRight, location: 0.85),
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
        let amp = amplitude()
        let flat = 0.09
        for strand in 0 ..< 4 {
            let i = Double(strand)
            let color = Theme.Badge.ribbonPalette[strand]
            let phase = i * 1.7
            let freq = 0.010 + i * 0.0032
            let drift = sin(t * 0.00012 + i) * 0.12
            var strandCtx = ctx
            strandCtx.blendMode = .plusLighter
            strandCtx.addFilter(.shadow(color: color.opacity(0.8), radius: 6))
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
