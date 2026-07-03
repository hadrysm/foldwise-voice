// The floating pill, drawn entirely in SwiftUI: translucent material capsule,
// pulsing status dot, audio-reactive waveform, hover gear. GPU-driven via
// TimelineView + Canvas — no main-thread drawing loop.

import SwiftUI

/// Visual style of the floating bar, chosen in Settings → Configuration.
/// Persisted in modes.json as `hud_style`; more styles can be added here and
/// they appear in the picker automatically.
enum HUDStyle: String, CaseIterable, Identifiable {
    /// Translucent pill with status dot, text labels and always-visible bars.
    case classic
    /// Solid near-black pill: waveform glyph when idle (controls on hover),
    /// live waveform only while recording, short text for statuses.
    case minimal

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        }
    }
}

final class HUDModel: ObservableObject {
    enum Phase: Equatable {
        case idle, listening, working, done, error
    }

    @Published var phase: Phase = .idle
    @Published var label: String = ""
    @Published var hovering = false
    @Published var style: HUDStyle = .classic

    /// Waveform ring buffer; mutated by the controller at 30 Hz while
    /// listening. Not @Published — TimelineView redraws continuously anyway.
    var levels: [Float] = Array(repeating: 0, count: 26)

    func pushLevel(_ value: Float) {
        levels.removeFirst()
        levels.append(value)
    }

    var dotColor: Color {
        switch phase {
        case .listening: .red
        case .working: .orange
        case .error: .yellow
        default: .green
        }
    }
}

struct HUDView: View {
    @ObservedObject var model: HUDModel
    var onHover: (Bool) -> Void
    var onGear: () -> Void
    var onStop: () -> Void
    var onChangeMode: () -> Void
    var onRecord: () -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let mini = model.phase == .idle

            ZStack {
                if model.style == .minimal {
                    Capsule().fill(Color(white: 0.07).opacity(0.97))
                } else {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.10).opacity(mini ? 0.55 : 0.72),
                                Color(white: 0.02).opacity(mini ? 0.65 : 0.85),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }

                if mini {
                    miniContent(t: t)
                } else {
                    fullContent(t: t)
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    model.style == .minimal
                        ? LinearGradient(
                            colors: [.white.opacity(0.14), .white.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        )
                        : LinearGradient(
                            colors: [.white.opacity(0.28), .white.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom
                        ),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .onHover(perform: onHover)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.hovering)
        .animation(.easeOut(duration: 0.20), value: model.phase)
    }

    // MARK: - idle mini pill

    @ViewBuilder
    private func miniContent(t: Double) -> some View {
        if model.style == .minimal {
            minimalMiniContent()
        } else {
            ZStack {
                WaveformBars(
                    count: 12, barWidth: 3, gap: 2, alpha: 0.45,
                    heights: WaveformBars.idleHeights(t: t, count: 12)
                )
                if model.hovering {
                    HStack {
                        Spacer()
                        gearButton
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }

    /// Static "···|·|·" glyph; hovering swaps it for the control panel:
    /// change mode, start dictation (app logo placeholder), open settings.
    private static let minimalIdleGlyph: [CGFloat] = [3, 3, 3, 12, 3, 9, 3]

    @ViewBuilder
    private func minimalMiniContent() -> some View {
        if model.hovering {
            HStack(spacing: 13) {
                minimalIconButton(
                    "sparkles", size: 12, help: "Change mode", action: onChangeMode
                )
                // Logo mark doubling as start-recording; swap for the real
                // logo asset once there is one.
                minimalIconButton(
                    "mic.fill", size: 12, help: "Start dictation", action: onRecord
                )
                Button(action: onGear) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Open settings")
            }
            .padding(.horizontal, 6)
            .transition(.opacity)
        } else {
            WaveformBars(
                count: 7, barWidth: 3, gap: 3, alpha: 0.9,
                heights: Self.minimalIdleGlyph
            )
        }
    }

    private func minimalIconButton(
        _ symbol: String, size: CGFloat, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 22, height: 26)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - expanded pill

    @ViewBuilder
    private func fullContent(t: Double) -> some View {
        if model.style == .minimal {
            if model.phase == .listening {
                minimalListeningContent(t: t)
            } else {
                minimalStatusContent()
            }
        } else if model.phase == .listening {
            listeningContent(t: t)
        } else {
            statusContent(t: t)
        }
    }

    /// Recording, minimal: just the live waveform; stop appears on hover.
    private func minimalListeningContent(t: Double) -> some View {
        HStack(spacing: 10) {
            WaveformBars(
                count: 20, barWidth: 3, gap: 2.5, alpha: 0.95,
                heights: heights(t: t, count: 20)
            )
            .frame(height: 18)
            if model.hovering {
                stopButton
            }
        }
        .padding(.horizontal, 14)
    }

    /// Working / done / error, minimal: one short text line, no dot.
    private func minimalStatusContent() -> some View {
        HStack(spacing: 8) {
            Text(model.label)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
            if model.hovering {
                gearButton
            }
        }
        .padding(.horizontal, 14)
    }

    /// Recording: no text, just the pulsing dot, live bars and a stop button.
    @ViewBuilder
    private func listeningContent(t: Double) -> some View {
        let pulse = 0.72 + 0.28 * (0.5 + 0.5 * sin(t * 9.0))
        HStack(spacing: 12) {
            Circle()
                .fill(model.dotColor)
                .frame(width: 9, height: 9)
                .opacity(pulse)
                .shadow(color: model.dotColor.opacity(0.7), radius: 4)
            WaveformBars(
                count: 26, barWidth: 4, gap: 3, alpha: 0.85,
                heights: heights(t: t, count: 26)
            )
            .frame(height: 20)
            stopButton
            if model.hovering {
                gearButton
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func statusContent(t: Double) -> some View {
        let pulse = 0.72 + 0.28 * (0.5 + 0.5 * sin(t * 9.0))
        VStack(spacing: 3) {
            HStack(spacing: 9) {
                Circle()
                    .fill(model.dotColor)
                    .frame(width: 9, height: 9)
                    .opacity(model.phase == .listening || model.phase == .working ? pulse : 1.0)
                    .shadow(color: model.dotColor.opacity(0.7), radius: 4)
                Text(model.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if model.hovering {
                    gearButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 11)

            WaveformBars(
                count: 26, barWidth: 4, gap: 3, alpha: 0.85,
                heights: heights(t: t, count: 26)
            )
            .frame(height: 20)
            .padding(.bottom, 8)
        }
    }

    private func heights(t: Double, count: Int) -> [CGFloat] {
        switch model.phase {
        case .listening:
            return model.levels.suffix(count).map { level in
                let lvl = min(1.0, pow(Double(level), 0.5) * 1.6)
                return CGFloat(2.0 + lvl * 14.0)
            }
        case .working:
            let phase = t * 4.5
            return (0 ..< count).map { i -> CGFloat in
                let wave = 0.5 + 0.5 * sin(phase + Double(i) * 0.55)
                return CGFloat(4.0 + 5.0 * wave)
            }
        default:
            return Array(repeating: 2.5, count: count)
        }
    }

    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.red.opacity(0.88)))
        }
        .buttonStyle(.plain)
        .help("Stop recording")
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var gearButton: some View {
        Button(action: onGear) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }
}

struct WaveformBars: View {
    var count: Int
    var barWidth: CGFloat
    var gap: CGFloat
    var alpha: Double
    var heights: [CGFloat]

    static func idleHeights(t: Double, count: Int) -> [CGFloat] {
        let phase = t * 2.7 // slow breathing
        return (0 ..< count).map { i -> CGFloat in
            let wave = 0.5 + 0.5 * sin(phase + Double(i) * 0.4)
            return CGFloat(2.0 + 3.0 * wave)
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let total = CGFloat(count) * barWidth + CGFloat(count - 1) * gap
            let x0 = (size.width - total) / 2
            for i in 0 ..< count {
                let h = i < heights.count ? heights[i] : 2.0
                let rect = CGRect(
                    x: x0 + CGFloat(i) * (barWidth + gap),
                    y: (size.height - h) / 2,
                    width: barWidth, height: h
                )
                ctx.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}
