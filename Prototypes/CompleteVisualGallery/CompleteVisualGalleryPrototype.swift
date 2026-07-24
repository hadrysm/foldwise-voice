// THROWAWAY PROTOTYPE — one assembled gallery for the approved FoldWise visual system.
// Seven surfaces, switchable from the review bar, with curated state and accessibility previews.

import AppKit
import SwiftUI

private enum GallerySurface: String, CaseIterable, Identifiable {
    case home = "Home"
    case modes = "Modes"
    case models = "Models"
    case history = "History"
    case stats = "Stats"
    case settings = "Settings"
    case badge = "Badge"

    var id: Self {
        self
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .modes: "sparkles"
        case .models: "shippingbox"
        case .history: "clock"
        case .stats: "chart.bar"
        case .settings: "slider.horizontal.3"
        case .badge: "waveform"
        }
    }

    var treatment: String {
        switch self {
        case .home, .history: "Instrument Panel"
        case .modes: "Command Ledger"
        case .models: "Trace Ledger"
        case .stats: "Dictation Pulse"
        case .settings: "Signal Ledger"
        case .badge: "Ember Trace"
        }
    }
}

private enum GalleryAppearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    var id: Self {
        self
    }

    var scheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

private enum GalleryWidth: String, CaseIterable, Identifiable {
    case wide = "Wide"
    case compact = "Compact"
    var id: Self {
        self
    }

    var size: CGSize {
        self == .wide ? CGSize(width: 1180, height: 720) : CGSize(width: 880, height: 640)
    }
}

private enum GalleryScene: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case hover = "Hover"
    case focus = "Focus"
    case empty = "Empty"
    case progress = "Progress"
    case error = "Error"
    var id: Self {
        self
    }
}

private enum GalleryContrast: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case increased = "Contrast+"
    var id: Self {
        self
    }
}

private enum GalleryMotion: String, CaseIterable, Identifiable {
    case standard = "Motion"
    case reduced = "Reduced"
    var id: Self {
        self
    }
}

private enum BadgeScene: String, CaseIterable, Identifiable {
    case idle = "Idle"
    case hover = "Hover"
    case recording = "Recording"
    case working = "Working"
    case done = "Done"
    case error = "Error"
    case modeCycle = "Mode cycle"
    var id: Self {
        self
    }
}

private struct Palette {
    let canvas: Color
    let sidebar: Color
    let surface: Color
    let raised: Color
    let hover: Color
    let border: Color
    let borderStrong: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let orange: Color
    let orangeForeground: Color
    let success: Color
    let warning: Color
    let error: Color

    static func ember(_ appearance: GalleryAppearance) -> Palette {
        if appearance == .dark {
            return Palette(
                canvas: Color(hex: 0x07090B), sidebar: Color(hex: 0x090B0E),
                surface: Color(hex: 0x0D1013), raised: Color(hex: 0x13171B),
                hover: Color(hex: 0x1A2026), border: Color(hex: 0x262C32),
                borderStrong: Color(hex: 0x5B6570), primary: Color(hex: 0xF4F5F6),
                secondary: Color(hex: 0xA4AAB0), tertiary: Color(hex: 0x747C85),
                orange: Color(hex: 0xFF6A1A), orangeForeground: Color(hex: 0x160900),
                success: Color(hex: 0x43D17A), warning: Color(hex: 0xF0B44B),
                error: Color(hex: 0xFF6464)
            )
        }
        return Palette(
            canvas: Color(hex: 0xF7F3EC), sidebar: Color(hex: 0xEEE8DE),
            surface: Color(hex: 0xFFFCF7), raised: Color(hex: 0xF4EFE7),
            hover: Color(hex: 0xEAE2D7), border: Color(hex: 0xD8CFC1),
            borderStrong: Color(hex: 0x978B7C), primary: Color(hex: 0x1A1714),
            secondary: Color(hex: 0x625C55), tertiary: Color(hex: 0x766E65),
            orange: Color(hex: 0xBF4008), orangeForeground: .white,
            success: Color(hex: 0x147A42), warning: Color(hex: 0x865B00),
            error: Color(hex: 0xB4232C)
        )
    }
}

private struct SnapshotCase {
    let surface: GallerySurface
    let appearance: GalleryAppearance
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let motion: GalleryMotion
    let badgeScene: BadgeScene

    var filename: String {
        [
            surface.rawValue.lowercased(),
            appearance.rawValue.lowercased(),
            width.rawValue.lowercased(),
            scene.rawValue.lowercased(),
            contrast == .increased ? "contrast" : "standard",
            motion == .reduced ? "reduced" : "motion",
            surface == .badge ? badgeScene.rawValue.lowercased().replacingOccurrences(of: " ", with: "-") : nil,
        ].compactMap(\.self).joined(separator: "-") + ".png"
    }
}

@main
private enum CompleteVisualGalleryPrototypeApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        if CommandLine.arguments.contains("--render") {
            renderSnapshots()
            return
        }
        application.setActivationPolicy(.regular)
        let delegate = PrototypeAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }

    @MainActor
    private static func renderSnapshots() {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".context/complete-visual-gallery-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if let files = try? FileManager.default.contentsOfDirectory(
            at: output, includingPropertiesForKeys: nil
        ) {
            for file in files where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }
        let cases: [SnapshotCase] = [
            SnapshotCase(
                surface: .home,
                appearance: .dark,
                width: .wide,
                scene: .hover,
                contrast: .standard,
                motion: .standard,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .home,
                appearance: .light,
                width: .compact,
                scene: .focus,
                contrast: .increased,
                motion: .reduced,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .modes,
                appearance: .dark,
                width: .wide,
                scene: .baseline,
                contrast: .standard,
                motion: .standard,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .models,
                appearance: .dark,
                width: .compact,
                scene: .progress,
                contrast: .standard,
                motion: .standard,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .models,
                appearance: .light,
                width: .wide,
                scene: .error,
                contrast: .increased,
                motion: .reduced,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .history,
                appearance: .light,
                width: .wide,
                scene: .empty,
                contrast: .standard,
                motion: .standard,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .stats,
                appearance: .dark,
                width: .wide,
                scene: .hover,
                contrast: .standard,
                motion: .standard,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .stats,
                appearance: .light,
                width: .compact,
                scene: .focus,
                contrast: .increased,
                motion: .reduced,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .settings,
                appearance: .dark,
                width: .wide,
                scene: .baseline,
                contrast: .standard,
                motion: .standard,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .settings,
                appearance: .light,
                width: .compact,
                scene: .error,
                contrast: .increased,
                motion: .reduced,
                badgeScene: .idle
            ),
            SnapshotCase(
                surface: .badge,
                appearance: .dark,
                width: .wide,
                scene: .baseline,
                contrast: .standard,
                motion: .standard,
                badgeScene: .working
            ),
            SnapshotCase(
                surface: .badge,
                appearance: .light,
                width: .wide,
                scene: .error,
                contrast: .increased,
                motion: .reduced,
                badgeScene: .error
            ),
        ]

        let renderSize = CGSize(width: 1280, height: 860)
        for item in cases {
            let root = PrototypeRoot(
                initialSurface: item.surface,
                initialAppearance: item.appearance,
                initialWidth: item.width,
                initialScene: item.scene,
                initialContrast: item.contrast,
                initialMotion: item.motion,
                initialBadgeScene: item.badgeScene
            )
            .frame(width: renderSize.width, height: renderSize.height)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: renderSize)
            hosting.appearance = NSAppearance(named: item.appearance == .light ? .aqua : .darkAqua)
            let window = NSWindow(
                contentRect: hosting.frame, styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            window.contentView = hosting
            window.appearance = hosting.appearance
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: output.appendingPathComponent(item.filename))
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class PrototypeAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let hosting = NSHostingController(rootView: PrototypeRoot())
        let window = NSWindow(contentViewController: hosting)
        window.title = "FoldWise complete visual prototype gallery"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1280, height: 860))
        window.contentMinSize = CGSize(width: 1080, height: 760)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct PrototypeRoot: View {
    @State private var surface: GallerySurface
    @State private var appearance: GalleryAppearance
    @State private var width: GalleryWidth
    @State private var scene: GalleryScene
    @State private var contrast: GalleryContrast
    @State private var motion: GalleryMotion
    @State private var badgeScene: BadgeScene

    init(
        initialSurface: GallerySurface = .home,
        initialAppearance: GalleryAppearance = .dark,
        initialWidth: GalleryWidth = .wide,
        initialScene: GalleryScene = .baseline,
        initialContrast: GalleryContrast = .standard,
        initialMotion: GalleryMotion = .standard,
        initialBadgeScene: BadgeScene = .idle
    ) {
        _surface = State(initialValue: initialSurface)
        _appearance = State(initialValue: initialAppearance)
        _width = State(initialValue: initialWidth)
        _scene = State(initialValue: initialScene)
        _contrast = State(initialValue: initialContrast)
        _motion = State(initialValue: initialMotion)
        _badgeScene = State(initialValue: initialBadgeScene)
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        ZStack(alignment: .bottom) {
            palette.canvas.ignoresSafeArea()
            GalleryPreview(
                surface: surface, width: width, scene: scene, contrast: contrast,
                motion: motion, badgeScene: badgeScene, palette: palette
            )
            .frame(width: width.size.width, height: width.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        contrast == .increased ? palette.borderStrong : palette.border,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
            .padding(.bottom, 102)

            ReviewBar(
                surface: $surface, appearance: $appearance, width: $width,
                scene: $scene, contrast: $contrast, motion: $motion,
                badgeScene: $badgeScene
            )
            .padding(.bottom, 14)
        }
        .environment(\.colorScheme, appearance.scheme)
        .onKeyPress(.leftArrow, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            cycleSurface(-1)
            return .handled
        }
        .onKeyPress(.rightArrow, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            cycleSurface(1)
            return .handled
        }
    }

    private func cycleSurface(_ delta: Int) {
        let cases = GallerySurface.allCases
        guard let index = cases.firstIndex(of: surface) else { return }
        surface = cases[(index + delta + cases.count) % cases.count]
    }
}

private struct GalleryPreview: View {
    let surface: GallerySurface
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let motion: GalleryMotion
    let badgeScene: BadgeScene
    let palette: Palette

    var body: some View {
        if surface == .badge {
            BadgeGallery(scene: badgeScene, motion: motion, contrast: contrast, palette: palette)
        } else {
            ContinuousFrame(
                surface: surface, width: width, scene: scene,
                contrast: contrast, palette: palette
            )
        }
    }
}

private struct ContinuousFrame: View {
    let surface: GallerySurface
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            Titlebar(width: width, palette: palette)
            Hairline(palette: palette, contrast: contrast)
            HStack(spacing: 0) {
                Sidebar(selected: surface, compact: width == .compact, palette: palette)
                Hairline(vertical: true, palette: palette, contrast: contrast)
                VStack(spacing: 0) {
                    if scene == .error && surface == .settings {
                        RecoveryBanner(palette: palette, contrast: contrast)
                        Hairline(palette: palette, contrast: contrast)
                    }
                    DestinationView(
                        surface: surface, width: width, scene: scene,
                        contrast: contrast, palette: palette
                    )
                    if scene == .error && surface != .settings {
                        Hairline(palette: palette, contrast: contrast)
                        GlobalStatus(palette: palette)
                    }
                }
            }
        }
        .background(palette.canvas)
    }
}

private struct Titlebar: View {
    let width: GalleryWidth
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xFF5F57))
                Circle().fill(Color(hex: 0xFEBB2E))
                Circle().fill(Color(hex: 0x28C840))
            }
            .frame(width: 52)
            .frame(maxHeight: .infinity)
            Image(systemName: "sidebar.left").foregroundStyle(palette.tertiary)
            WaveMark(color: palette.orange)
            if width == .wide {
                HStack(spacing: 0) {
                    Text("FoldWise").foregroundStyle(palette.orange)
                    Text(" Voice").foregroundStyle(palette.primary)
                }
            }
            Spacer()
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(palette.sidebar)
    }
}

private struct Sidebar: View {
    let selected: GallerySurface
    let compact: Bool
    let palette: Palette

    var body: some View {
        VStack(spacing: 4) {
            ForEach(GallerySurface.allCases.filter { $0 != .badge }) { item in
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(item == selected ? palette.orange : .clear)
                        .frame(width: 2)
                    Image(systemName: item.symbol)
                        .frame(width: 18)
                        .foregroundStyle(item == selected ? palette.orange : palette.tertiary)
                    if !compact {
                        Text(item.rawValue)
                            .foregroundStyle(item == selected ? palette.primary : palette.secondary)
                        Spacer()
                        if item == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(palette.orange)
                        }
                    }
                }
                .font(.system(size: 13, weight: item == selected ? .semibold : .regular))
                .frame(height: 40)
                .background(item == selected ? palette.raised : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(item.rawValue + (item == selected ? ", selected" : ""))
            }
            Spacer()
            if !compact {
                VStack(alignment: .leading, spacing: 5) {
                    Label("All systems go", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(palette.success)
                    Text("v0.15.0 · up to date").foregroundStyle(palette.tertiary)
                }
                .font(.system(size: 10, weight: .medium))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(palette.success)
                    .padding(.bottom, 12)
            }
        }
        .padding(compact ? 6 : 10)
        .frame(width: compact ? 52 : 190)
        .background(palette.sidebar)
    }
}

@ViewBuilder
private func DestinationView(
    surface: GallerySurface,
    width: GalleryWidth,
    scene: GalleryScene,
    contrast: GalleryContrast,
    palette: Palette
) -> some View {
    switch surface {
    case .home:
        HomeView(width: width, scene: scene, contrast: contrast, palette: palette)
    case .modes:
        ModesView(width: width, scene: scene, contrast: contrast, palette: palette)
    case .models:
        ModelsView(width: width, scene: scene, contrast: contrast, palette: palette)
    case .history:
        HistoryView(width: width, scene: scene, contrast: contrast, palette: palette)
    case .stats:
        StatsView(width: width, scene: scene, contrast: contrast, palette: palette)
    case .settings:
        SettingsView(width: width, scene: scene, contrast: contrast, palette: palette)
    case .badge:
        EmptyView()
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String
    let palette: Palette
    var action: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.primary)
                Text(subtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            if let action {
                Button(action) {}
                    .buttonStyle(PrimaryButtonStyle(palette: palette))
            }
        }
    }
}

private struct HomeView: View {
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    title: "Ready when you are.",
                    subtitle: "Hold  right ⌘  and speak — release to insert at your cursor.",
                    palette: palette
                )
                metrics
                StatusBand(scene: scene, contrast: contrast, palette: palette)
                HStack {
                    Label("Today", systemImage: "list.bullet")
                        .foregroundStyle(palette.primary)
                    Spacer()
                    Text("NEWEST 10")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
                if scene == .empty {
                    EmptySurface(
                        icon: "waveform", title: "Your first Dictation session will appear here.",
                        detail: "Hold right ⌘ and speak when you’re ready.", palette: palette
                    )
                } else {
                    DictationLedger(scene: scene, history: false, contrast: contrast, palette: palette)
                }
                Text("All history →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.orange)
            }
            .padding(width == .wide ? 28 : 20)
        }
        .background(palette.canvas)
    }

    private var metrics: some View {
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: width == .wide ? 4 : 2
        )
        return LazyVGrid(columns: columns, spacing: 8) {
            MetricCell(icon: "textformat", value: "5,809", unit: "", label: "Total words", palette: palette)
            MetricCell(icon: "bolt", value: "125", unit: "wpm", label: "Speaking speed", palette: palette)
            MetricCell(icon: "flame", value: "6", unit: "days", label: "Current streak", palette: palette)
            MetricCell(icon: "clock.arrow.circlepath", value: "~65", unit: "min", label: "Time saved", palette: palette)
        }
    }
}

private struct MetricCell: View {
    let icon: String
    let value: String
    let unit: String
    let label: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: icon).foregroundStyle(palette.orange)
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.primary)
                Text(unit).font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.tertiary)
            }
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(palette.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border) }
    }
}

private struct StatusBand: View {
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        let isError = scene == .error
        let color = isError ? palette.error : palette.success
        HStack(spacing: 12) {
            Rectangle().fill(palette.orange).frame(width: 2)
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(isError ? "Accessibility permission needed" : "All systems go")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primary)
                Text(isError
                    ? "Grant access so FoldWise can insert text."
                    : "Parakeet TDT v3 · Email · accessibility granted")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            Text(isError ? "Open Settings →" : "Stats →")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isError ? palette.error : palette.orange)
        }
        .padding(.trailing, 14)
        .frame(height: 58)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
    }
}

private struct DictationLedger: View {
    let scene: GalleryScene
    let history: Bool
    let contrast: GalleryContrast
    let palette: Palette

    private let rows = [
        ("18:51", "Send the revised launch notes after the client review.", "Email"),
        ("12:54", "The model should stay local and keep the existing fallback.", "Voice to Text"),
        ("12:44", "Break the migration into small reversible checkpoints.", "Project brief"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                        .frame(width: 42, alignment: .leading)
                    Rectangle().fill(palette.orange).frame(width: 2, height: 22)
                    Text(row.1).lineLimit(1).foregroundStyle(palette.primary)
                    Spacer()
                    if index == 0 && (scene == .hover || scene == .focus) {
                        Label("Copy", systemImage: "doc.on.doc")
                        Label("Flag", systemImage: "flag")
                        if history {
                            Image(systemName: "ellipsis")
                        }
                    } else {
                        Text(row.2).foregroundStyle(palette.tertiary)
                    }
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(index == 0 && scene == .hover ? palette.hover : palette.surface)
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 {
                        Rectangle().fill(palette.border).frame(height: 1)
                    }
                }
                .overlay {
                    if index == 0 && scene == .focus {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(palette.orange, lineWidth: 2)
                            .padding(3)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
    }
}

private struct ModesView: View {
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                title: "Modes",
                subtitle: "Choose how the next Dictation session should shape your words.",
                palette: palette, action: "＋  Add Mode"
            )
            if scene == .empty {
                EmptySurface(
                    icon: "sparkles", title: "No Modes yet.",
                    detail: "Voice to Text remains ready. Add a Mode when you want Polish.", palette: palette
                )
            } else {
                GeometryReader { geometry in
                    HStack(alignment: .top, spacing: 14) {
                        modeLibrary
                            .frame(width: width == .compact ? geometry.size.width * 0.42 : geometry.size.width * 0.38)
                        modeInspector
                    }
                }
            }
        }
        .padding(width == .wide ? 28 : 20)
        .background(palette.canvas)
    }

    private var modeLibrary: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("DICTATION SELECTION", palette: palette)
            SelectionRow(
                icon: "waveform",
                title: "Voice to Text",
                subtitle: "Raw transcription — no Polish",
                selected: false,
                palette: palette
            )
            SectionLabel("YOUR MODES · CYCLE ORDER", palette: palette)
            VStack(spacing: 0) {
                SelectionRow(
                    icon: "text.bubble",
                    title: "Casual",
                    subtitle: "Keep wording · qwen2.5:3b",
                    selected: false,
                    palette: palette
                )
                SelectionRow(icon: "envelope", title: "Email", subtitle: scene == .error
                    ? "Model unavailable · raw fallback"
                    : "Reshape · qwen2.5:7b", selected: true, palette: palette)
                SelectionRow(
                    icon: "list.bullet",
                    title: "Bullets",
                    subtitle: "Reshape · qwen2.5:3b",
                    selected: false,
                    palette: palette
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var modeInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("MODE DETAILS", palette: palette)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "envelope").font(.system(size: 24)).foregroundStyle(palette.orange)
                    VStack(alignment: .leading) {
                        Text("Email").font(.system(size: 20, weight: .semibold)).foregroundStyle(palette.primary)
                        Text("Reshape").foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    QuietButton(title: "Edit", palette: palette)
                    QuietButton(title: "Duplicate", palette: palette)
                }
                Hairline(palette: palette, contrast: contrast)
                DetailField(label: "AI MODEL", value: "qwen2.5:7b", palette: palette)
                DetailField(
                    label: "POLISH INSTRUCTIONS",
                    value: "Turn the transcript into a concise, warm email with a clear next step.",
                    palette: palette
                )
                DetailField(
                    label: "PRESERVED VOCABULARY",
                    value: "Mateusz · FoldWise · SwiftUI",
                    mono: true,
                    palette: palette
                )
                if scene == .progress {
                    InlineNotice(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Saving Mode…",
                        color: palette.orange,
                        palette: palette
                    )
                }
                if scene == .error {
                    InlineNotice(
                        icon: "exclamationmark.triangle.fill",
                        title: "qwen2.5:7b is unavailable. Polish falls back to raw text.",
                        color: palette.warning,
                        palette: palette
                    )
                }
                Spacer()
                HStack {
                    QuietButton(title: "↑ Up", palette: palette)
                    QuietButton(title: "↓ Down", palette: palette)
                    Spacer()
                    Text("Delete").foregroundStyle(palette.error)
                }
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border) }
        }
    }
}

private struct SelectionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(selected ? palette.orange : .clear).frame(width: 2)
            Image(systemName: icon).foregroundStyle(selected ? palette.orange : palette.tertiary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold).foregroundStyle(palette.primary)
                Text(subtitle).foregroundStyle(palette.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? palette.orange : palette.tertiary)
        }
        .font(.system(size: 11))
        .padding(.trailing, 12)
        .frame(height: 52)
        .background(selected ? palette.raised : palette.surface)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border) }
    }
}

private struct ModelsView: View {
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: "Models",
                subtitle: "Compare what runs each Stage, then manage its local data.",
                palette: palette
            )
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    modelLedger
                        .frame(width: width == .compact ? 340 : geometry.size.width * 0.56)
                    modelInspector
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            contrast == .increased ? palette.borderStrong : palette.border,
                            lineWidth: contrast == .increased ? 2 : 1
                        )
                }
            }
        }
        .padding(width == .wide ? 24 : 16)
        .background(palette.canvas)
    }

    private var modelLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            ModelFamily(
                title: "SPEECH RECOGNITION — Global selection",
                rows: [
                    ("Parakeet TDT v3", "25 languages · Neural Engine", "600 MB", "Selected"),
                    ("Whisper large-v3-turbo", "~99 languages · balanced", "632 MB", scene == .progress
                        ? "64% · Cancel"
                        : "Download"),
                    ("Whisper small", "~99 languages · lighter", "483 MB", scene == .error ? "Repair" : "Ready"),
                ],
                selected: 0, scene: scene, palette: palette
            )
            ModelFamily(
                title: "POLISH — Mode inventory",
                rows: [
                    ("qwen2.5:7b", "Multilingual · prompt-faithful", "4.7 GB", "Installed"),
                    ("gemma3:4b", "Balanced local Polish", "3.3 GB", "Install"),
                    ("Install by name", "Any Ollama model:tag", "—", "Other"),
                ],
                selected: nil, scene: .baseline, palette: palette
            )
            Spacer()
        }
        .padding(12)
        .background(palette.canvas)
    }

    private var modelNotice: (title: String, color: Color) {
        if scene == .error {
            return ("Local data needs repair", palette.error)
        }
        if scene == .progress {
            return ("Downloading model · 64%", palette.orange)
        }
        return ("Selected for the next Dictation session", palette.success)
    }

    private var modelInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                Rectangle().fill(palette.orange).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("GLOBAL SELECTION", palette: palette)
                    Text("Parakeet TDT v3").font(.system(size: 19, weight: .semibold)).foregroundStyle(palette.primary)
                    Text("25 languages · Neural Engine").foregroundStyle(palette.secondary)
                }
                .padding(16)
                Spacer()
            }
            .background(palette.raised)
            VStack(alignment: .leading, spacing: 14) {
                InlineNotice(
                    icon: scene == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                    title: modelNotice.title,
                    color: modelNotice.color,
                    palette: palette
                )
                DetailField(
                    label: "WHAT IT IS FOR",
                    value: "Fast, power-efficient recognition on Apple Neural Engine hardware.",
                    palette: palette
                )
                DetailField(
                    label: "GLOBAL SELECTION",
                    value: "The selection is captured when each Dictation session begins. "
                        + "Availability remains separate.",
                    palette: palette
                )
            }
            .padding(16)
            Spacer()
            HStack {
                Image(systemName: scene == .error ? "wrench.and.screwdriver.fill" : "checkmark.circle.fill")
                Text(scene == .error ? "Repair local data" : "Selected")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(scene == .error ? palette.error : palette.orange)
            .padding(14)
        }
        .background(palette.surface)
    }
}

private struct ModelFamily: View {
    let title: String
    let rows: [(String, String, String, String)]
    let selected: Int?
    let scene: GalleryScene
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title, palette: palette)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Rectangle().fill(index == selected ? palette.orange : .clear).frame(width: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0).fontWeight(.semibold).foregroundStyle(palette.primary)
                        Text(row.1).foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Text(row.2).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(palette.secondary)
                    Label(row.3, systemImage: stateIcon(row.3))
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(stateColor(row.3))
                }
                .font(.system(size: 10.5))
                .padding(.trailing, 8)
                .frame(height: 46)
                .background(index == selected ? palette.raised : palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border) }
            }
        }
    }

    private func stateIcon(_ state: String) -> String {
        if state.contains("Selected") {
            return "checkmark.circle.fill"
        }
        if state.contains("Repair") {
            return "exclamationmark.triangle.fill"
        }
        if state.contains("%") {
            return "arrow.down.circle.fill"
        }
        if state.contains("Ready") || state.contains("Installed") {
            return "checkmark.circle"
        }
        return "plus.circle"
    }

    private func stateColor(_ state: String) -> Color {
        if state.contains("Repair") {
            return palette.error
        }
        if state.contains("Selected") || state.contains("%") {
            return palette.orange
        }
        if state.contains("Ready") || state.contains("Installed") {
            return palette.success
        }
        return palette.secondary
    }
}

private struct HistoryView: View {
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    title: "History",
                    subtitle: "Saved locally on this Mac. Audio is never retained.",
                    palette: palette
                )
                HStack(spacing: 10) {
                    SettingCell(title: "Save History", value: "On", icon: "externaldrive", palette: palette)
                    SettingCell(title: "Keep Dictation sessions", value: "Forever", icon: "calendar", palette: palette)
                }
                HStack {
                    Label("Search Dictation sessions", systemImage: "magnifyingglass")
                    Spacer()
                    Label("Flagged only", systemImage: "flag")
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border) }
                if scene == .empty {
                    EmptySurface(
                        icon: "clock", title: "No saved Dictation sessions.",
                        detail: "Your saved text will appear here when History is on.", palette: palette
                    )
                } else {
                    SectionLabel("TODAY", palette: palette)
                    DictationLedger(scene: scene, history: true, contrast: contrast, palette: palette)
                    SectionLabel("YESTERDAY", palette: palette)
                    DictationLedger(scene: .baseline, history: true, contrast: contrast, palette: palette)
                }
                Text("Clear all history")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.error)
            }
            .padding(width == .wide ? 28 : 20)
        }
        .background(palette.canvas)
    }
}

private struct SettingCell: View {
    let title: String
    let value: String
    let icon: String
    let palette: Palette

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(palette.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold).foregroundStyle(palette.primary)
                Text(value).foregroundStyle(palette.secondary)
            }
            Spacer()
            Image(systemName: "chevron.down").foregroundStyle(palette.tertiary)
        }
        .font(.system(size: 11.5))
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border) }
    }
}

private struct StatsView: View {
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    private let values = [0, 0, 2, 4, 3, 0, 1, 0, 1, 0, 2, 3, 1, 0, 5, 2, 0, 1, 3, 4, 5, 2]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: "Stats",
                subtitle: "A look at how you dictate, drawn from the History you already keep.",
                palette: palette
            )
            HStack {
                PulseMetric(title: "Words dictated", value: "14,680", icon: "text.bubble", palette: palette)
                PulseMetric(title: "Speaking speed", value: "137 wpm", icon: "waveform", palette: palette)
                PulseMetric(title: "Current streak", value: "3 days", icon: "flame", palette: palette)
                PulseMetric(
                    title: "Time saved",
                    value: "~1 hr 04 min",
                    icon: "clock.arrow.circlepath",
                    palette: palette
                )
            }
            Hairline(palette: palette, contrast: contrast)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("This month").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.primary)
                        Text("July 2026").foregroundStyle(palette.secondary)
                    }
                    Spacer()
                    Text(scene == .empty ? "— spoken words" : "14,540 spoken words")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                }
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"], id: \.self) {
                        Text($0).font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.tertiary)
                    }
                    ForEach(1 ... 28, id: \.self) { day in
                        let level = scene == .empty ? 0 : values[(day - 1) % values.count]
                        CalendarCell(
                            day: day, level: level,
                            highlighted: (scene == .hover && day == 12) || (scene == .focus && day == 22),
                            focused: scene == .focus && day == 22,
                            palette: palette
                        )
                    }
                }
                HStack {
                    WaveCue(level: scene == .empty ? 0 : 5, palette: palette)
                    VStack(alignment: .leading) {
                        Text(scene == .empty ? "No activity yet this month" : "Sunday, 12 July")
                            .fontWeight(.semibold).foregroundStyle(palette.primary)
                        Text(scene == .empty
                            ? "Start a Dictation session to build your calendar."
                            : "1,910 spoken words across 5 saved sessions")
                            .foregroundStyle(palette.secondary)
                    }
                }
                .font(.system(size: 10.5))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.raised)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(14)
            .background(palette.surface)
            .overlay(alignment: .leading) { Rectangle().fill(palette.orange).frame(width: 2) }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        contrast == .increased ? palette.borderStrong : palette.border,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
        }
        .padding(width == .wide ? 28 : 18)
        .background(palette.canvas)
    }
}

private struct PulseMetric: View {
    let title: String
    let value: String
    let icon: String
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(palette.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.secondary)
                Text(value).font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.primary)
            }
            Spacer()
        }
    }
}

private struct CalendarCell: View {
    let day: Int
    let level: Int
    let highlighted: Bool
    let focused: Bool
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("\(day)").font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                Spacer()
                if day == 22 {
                    Circle().fill(palette.orange).frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(day > 22 ? palette.tertiary.opacity(0.55) : palette.secondary)
            if day > 22 {
                Text("—").foregroundStyle(palette.tertiary.opacity(0.5))
            } else if level == 0 {
                Text("—").foregroundStyle(palette.tertiary)
            } else {
                WaveCue(level: level, palette: palette)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(highlighted ? palette.hover : palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 6).strokeBorder(palette.orange, lineWidth: 2)
            }
        }
    }
}

private struct WaveCue: View {
    let level: Int
    let palette: Palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0 ..< 5, id: \.self) { index in
                Capsule()
                    .fill(index < level ? palette.orange : palette.border)
                    .frame(width: 3, height: CGFloat([6, 10, 15, 11, 8][index]))
            }
        }
        .frame(height: 16)
    }
}

private struct SettingsView: View {
    let width: GalleryWidth
    let scene: GalleryScene
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(
                    title: "Settings",
                    subtitle: "One dense scan path; every state reads where its control lives.",
                    palette: palette
                )
                SettingsSection(title: "⌘  KEYBOARD SHORTCUTS", contrast: contrast, palette: palette) {
                    PreferenceRow(
                        title: "Push to Talk",
                        detail: "Hold to record, release when done",
                        value: "right ⌥",
                        palette: palette
                    )
                    PreferenceRow(
                        title: "Toggle Recording",
                        detail: "Starts and stops Dictation sessions",
                        value: "⌃ Space",
                        palette: palette
                    )
                    PreferenceRow(
                        title: "Cycle Modes",
                        detail: "Selects the next Mode",
                        value: "Click to set",
                        palette: palette
                    )
                    if scene == .error {
                        InlineNotice(
                            icon: "exclamationmark.triangle.fill",
                            title: "Shortcut collision. Choose a different key.",
                            color: palette.error,
                            palette: palette
                        )
                    }
                }
                SettingsSection(title: "🎙  INPUT", contrast: contrast, palette: palette) {
                    PreferenceRow(
                        title: "System Default",
                        detail: "MacBook Pro Microphone",
                        value: "IN USE",
                        selected: true,
                        palette: palette
                    )
                    PreferenceRow(
                        title: "Studio Display Microphone",
                        detail: "Connected · Preferred",
                        value: "",
                        palette: palette
                    )
                    if scene == .progress {
                        InlineNotice(
                            icon: "clock.fill",
                            title: "Input change will apply after this Dictation session.",
                            color: palette.warning,
                            palette: palette
                        )
                    }
                }
                HStack(spacing: 10) {
                    SettingsSection(title: "◐  APPEARANCE", contrast: contrast, palette: palette) {
                        if width == .wide {
                            HStack(spacing: 8) { appearanceChoices }
                        } else {
                            VStack(spacing: 8) { appearanceChoices }
                        }
                    }
                    if width == .wide {
                        SettingsSection(title: "↻  UPDATES", contrast: contrast, palette: palette) {
                            PreferenceRow(
                                title: "FoldWise Voice",
                                detail: "Version 0.15.0",
                                value: "Current",
                                palette: palette
                            )
                        }
                    }
                }
            }
            .padding(width == .wide ? 24 : 16)
        }
        .background(palette.canvas)
        .opacity(scene == .error ? 0.72 : 1)
    }

    @ViewBuilder private var appearanceChoices: some View {
        AppearanceChoice(title: "System", symbol: "circle.lefthalf.filled", selected: false, palette: palette)
        AppearanceChoice(title: "Light", symbol: "sun.max", selected: false, palette: palette)
        AppearanceChoice(title: "Dark", symbol: "moon", selected: true, palette: palette)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let contrast: GalleryContrast
    let palette: Palette
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(title, palette: palette)
            VStack(spacing: 0) { content }
                .padding(10)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            contrast == .increased ? palette.borderStrong : palette.border,
                            lineWidth: contrast == .increased ? 2 : 1
                        )
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PreferenceRow: View {
    let title: String
    let detail: String
    let value: String
    var selected = false
    let palette: Palette

    var body: some View {
        HStack {
            if selected {
                Image(systemName: "record.circle.fill").foregroundStyle(palette.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold).foregroundStyle(palette.primary)
                Text(detail).foregroundStyle(palette.secondary)
            }
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(selected ? palette.orange : palette.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(palette.raised)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .font(.system(size: 10.5))
        .padding(.horizontal, 2)
        .frame(minHeight: 42)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 1) }
    }
}

private struct AppearanceChoice: View {
    let title: String
    let symbol: String
    let selected: Bool
    let palette: Palette

    var body: some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(selected ? palette.orange : palette.secondary)
            Text(title).fontWeight(.semibold).foregroundStyle(palette.primary)
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? palette.orange : palette.tertiary)
        }
        .font(.system(size: 10.5))
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(selected ? palette.raised : palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? palette.orange : palette.border)
        }
    }
}

private struct BadgeGallery: View {
    let scene: BadgeScene
    let motion: GalleryMotion
    let contrast: GalleryContrast
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            Titlebar(width: .wide, palette: palette)
            Hairline(palette: palette, contrast: contrast)
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Badge",
                    subtitle: "Mic-reactive ribbons carry Recording; orange signals work, "
                        + "green confirms Done, and red owns Error.",
                    palette: palette
                )
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: 14),
                        count: 4
                    ),
                    spacing: 22
                ) {
                    ForEach(BadgeScene.allCases) { item in
                        VStack(spacing: 12) {
                            BadgePreview(
                                scene: item, selected: item == scene, motion: motion,
                                contrast: contrast, palette: palette
                            )
                            Text(item.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(item == scene ? palette.primary : palette.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 18)
                .background(
                    LinearGradient(
                        colors: [palette.raised, palette.canvas],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(palette.border) }
                HStack(spacing: 20) {
                    BadgeLegend(
                        color: palette.orange,
                        title: "Active / Working",
                        detail: "mic amplitude, progress, focus",
                        palette: palette
                    )
                    BadgeLegend(color: palette.success, title: "Done", detail: "checkmark + inserted", palette: palette)
                    BadgeLegend(
                        color: palette.error,
                        title: "Error",
                        detail: "warning + recovery text",
                        palette: palette
                    )
                    Spacer()
                    Text(motion == .reduced ? "DECORATIVE TIMELINES FROZEN" : "160 MS EASE-OUT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.tertiary)
                }
                Spacer()
            }
            .padding(30)
        }
        .background(palette.canvas)
    }
}

private struct BadgePreview: View {
    let scene: BadgeScene
    let selected: Bool
    let motion: GalleryMotion
    let contrast: GalleryContrast
    let palette: Palette

    var roleColor: Color {
        switch scene {
        case .done: palette.success
        case .error: palette.error
        case .recording, .working, .modeCycle: palette.orange
        case .idle, .hover: palette.borderStrong
        }
    }

    var width: CGFloat {
        switch scene {
        case .idle: 88
        case .hover: 132
        case .modeCycle: 176
        case .recording, .working, .done, .error: 208
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            switch scene {
            case .idle:
                WaveMark(color: palette.orange)
            case .hover:
                Image(systemName: "mic.fill").foregroundStyle(palette.orange)
                Image(systemName: "gearshape").foregroundStyle(palette.secondary)
            case .recording:
                BadgeRibbon(live: true, motion: motion, palette: palette)
                    .frame(width: 138, height: 20)
                Text("0:14")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.primary)
            case .working:
                BadgeRibbon(live: false, motion: motion, palette: palette)
                    .frame(width: 142, height: 20)
                Image(systemName: motion == .reduced ? "ellipsis" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(palette.orange)
            case .done:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.success)
                Text("Inserted").foregroundStyle(palette.primary)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.error)
                Text("Copied — couldn’t paste").foregroundStyle(palette.primary)
            case .modeCycle:
                Image(systemName: "envelope.fill").foregroundStyle(palette.orange)
                Text("Email").foregroundStyle(palette.primary)
            }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(width: width, height: 38)
        .background(palette.surface)
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .strokeBorder(
                    selected ? roleColor : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        .accessibilityLabel(scene.rawValue)
    }
}

private struct BadgeRibbon: View {
    let live: Bool
    let motion: GalleryMotion
    let palette: Palette

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: motion == .reduced
            )
        ) { context in
            let time = motion == .reduced
                ? 730.0
                : context.date.timeIntervalSinceReferenceDate
            Canvas { graphics, size in
                drawBaseline(&graphics, size: size)
                drawStrands(&graphics, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawBaseline(
        _ graphics: inout GraphicsContext,
        size: CGSize
    ) {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: size.height / 2))
        line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        graphics.stroke(
            line,
            with: .linearGradient(
                Gradient(colors: [
                    .clear, palette.orange.opacity(0.5), .clear,
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            ),
            lineWidth: 1
        )
    }

    private func drawStrands(
        _ graphics: inout GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        let amplitude = live ? liveAmplitude(at: time) : 0.18
        let colors = [
            palette.orange,
            palette.orange.opacity(0.86),
            palette.warning,
            palette.orange.opacity(0.58),
        ]
        let speed = live ? 4.8 : 2.1
        for strand in 0 ..< colors.count {
            let index = Double(strand)
            let phase = index * 1.7
            let frequency = 0.050 + index * 0.012
            var path = Path()
            var x = 0.0
            while x <= size.width {
                let unit = x / size.width
                let envelopeUnit = min(1, max(0, (unit - 0.09) / 0.82))
                let envelope = pow(sin(.pi * envelopeUnit), 2)
                let y = size.height / 2
                    + sin(x * frequency + time * speed * (1 + index * 0.13) + phase)
                    * size.height * amplitude * envelope
                if x == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                x += 2
            }
            graphics.stroke(
                path,
                with: .color(colors[strand].opacity(0.78)),
                lineWidth: strand == 0 ? 1.6 : 1
            )
        }
    }

    private func liveAmplitude(at time: Double) -> Double {
        let syllable = pow(max(0, sin(time * 5.2)), 1.6)
        let phrase = 0.62 + 0.38 * max(0, sin(time * 1.15 + 0.8))
        return 0.10 + 0.35 * syllable * phrase
    }
}

private struct BadgeLegend: View {
    let color: Color
    let title: String
    let detail: String
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold).foregroundStyle(palette.primary)
                Text(detail).foregroundStyle(palette.secondary)
            }
        }
        .font(.system(size: 10))
    }
}

private struct EmptySurface: View {
    let icon: String
    let title: String
    let detail: String
    let palette: Palette

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(palette.orange)
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.primary)
            Text(detail).font(.system(size: 11.5)).foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border) }
    }
}

private struct RecoveryBanner: View {
    let palette: Palette
    let contrast: GalleryContrast

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(palette.warning).frame(width: 3)
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration needs recovery").fontWeight(.semibold).foregroundStyle(palette.primary)
                Text("Settings is read-only. Voice to Text remains available.").foregroundStyle(palette.secondary)
            }
            Spacer()
            QuietButton(title: "Quit", palette: palette)
            Button("Reset Configuration") {}.buttonStyle(PrimaryButtonStyle(palette: palette))
        }
        .font(.system(size: 10.5))
        .padding(.trailing, 12)
        .frame(height: 54)
        .background(palette.raised)
    }
}

private struct GlobalStatus: View {
    let palette: Palette
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(palette.error).frame(width: 3)
            Image(systemName: "xmark.octagon.fill").foregroundStyle(palette.error)
            Text("The change could not be saved. Review the highlighted control and try again.")
                .foregroundStyle(palette.primary)
            Spacer()
            Text("ERROR").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(palette.error)
        }
        .font(.system(size: 10.5, weight: .medium))
        .padding(.trailing, 14)
        .frame(height: 38)
        .background(palette.raised)
    }
}

private struct InlineNotice: View {
    let icon: String
    let title: String
    let color: Color
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).foregroundStyle(palette.primary)
            Spacer()
        }
        .font(.system(size: 10.5, weight: .medium))
        .padding(10)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
    }
}

private struct DetailField: View {
    let label: String
    let value: String
    var mono = false
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(label, palette: palette)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(palette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let palette: Palette
    init(_ title: String, palette: Palette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(palette.tertiary)
    }
}

private struct QuietButton: View {
    let title: String
    let palette: Palette
    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border) }
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let palette: Palette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.orangeForeground)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(palette.orange.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct Hairline: View {
    var vertical = false
    let palette: Palette
    let contrast: GalleryContrast
    var body: some View {
        let thickness: CGFloat = contrast == .increased ? 2 : 1
        Rectangle()
            .fill(contrast == .increased ? palette.borderStrong : palette.border)
            .frame(width: vertical ? thickness : nil,
                   height: vertical ? nil : thickness)
    }
}

private struct WaveMark: View {
    let color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach([8.0, 17.0, 25.0, 17.0, 10.0], id: \.self) { height in
                Capsule().fill(color).frame(width: 2, height: height)
            }
        }
        .frame(width: 22, height: 26)
    }
}

private struct ReviewBar: View {
    @Binding var surface: GallerySurface
    @Binding var appearance: GalleryAppearance
    @Binding var width: GalleryWidth
    @Binding var scene: GalleryScene
    @Binding var contrast: GalleryContrast
    @Binding var motion: GalleryMotion
    @Binding var badgeScene: BadgeScene

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Picker("Surface", selection: $surface) {
                    ForEach(GallerySurface.allCases) { Text($0.rawValue).tag($0) }
                }
                Text(surface.treatment)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 110, alignment: .leading)
                Divider().frame(height: 22)
                Picker("Appearance", selection: $appearance) {
                    ForEach(GalleryAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Width", selection: $width) {
                    ForEach(GalleryWidth.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("State", selection: $scene) {
                    ForEach(GalleryScene.allCases) { Text($0.rawValue).tag($0) }
                }
                if surface == .badge {
                    Picker("Badge", selection: $badgeScene) {
                        ForEach(BadgeScene.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Picker("Contrast", selection: $contrast) {
                    ForEach(GalleryContrast.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Motion", selection: $motion) {
                    ForEach(GalleryMotion.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            .labelsHidden()
            Text(reviewSummary)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.58))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.black.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.12)) }
        .fixedSize()
        .environment(\.colorScheme, .dark)
    }

    private var reviewSummary: String {
        [
            "⌘← / ⌘→ surfaces", surface.rawValue, appearance.rawValue,
            width.rawValue, scene.rawValue, contrast.rawValue, motion.rawValue,
        ].joined(separator: " · ")
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
