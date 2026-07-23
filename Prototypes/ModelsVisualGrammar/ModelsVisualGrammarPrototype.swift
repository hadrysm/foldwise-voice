// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype Models within the new visual grammar".
//
// Three Models workspace treatments, switchable from the bottom review bar,
// preserve the approved comparison-ledger and inspector product behavior.

import AppKit
import SwiftUI

private enum ModelsVariant: String, CaseIterable, Identifiable {
    case trace
    case bays
    case inspector

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .trace: "A"
        case .bays: "B"
        case .inspector: "C"
        }
    }

    var title: String {
        switch self {
        case .trace: "Trace Ledger"
        case .bays: "Family Bays"
        case .inspector: "Inspector Forward"
        }
    }

    var thesis: String {
        switch self {
        case .trace:
            "The comparison scan stays primary; one orange trace hands inspection to detail."
        case .bays:
            "Each model family becomes a bounded work bay with a compact management rail."
        case .inspector:
            "A condensed index spends more width on status, recovery, and consequences."
        }
    }

    var wideLedgerRatio: CGFloat {
        switch self {
        case .trace: 0.55
        case .bays: 0.62
        case .inspector: 0.45
        }
    }
}

private enum PrototypeAppearance: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"

    var id: String {
        rawValue
    }

    var scheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

private enum WidthPreview: String, CaseIterable, Identifiable {
    case standard = "Default"
    case compact = "617 pt"

    var id: String {
        rawValue
    }

    var modelsWidth: CGFloat {
        self == .standard ? 980 : 617
    }

    var previewHeight: CGFloat {
        self == .standard ? 720 : 640
    }
}

private enum StatePreview: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case fallback = "Fallback"
    case progress = "Progress"
    case repair = "Repair"
    case error = "Error"
    case focus = "Focus"
    case confirm = "Confirm"

    var id: String {
        rawValue
    }
}

private enum ContrastPreview: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case increased = "Contrast+"

    var id: String {
        rawValue
    }
}

private enum ModelFamily: String {
    case speech = "Speech recognition"
    case polish = "Polish"

    var semanticLabel: String {
        self == .speech ? "Global selection" : "Mode inventory"
    }

    var symbol: String {
        self == .speech ? "waveform" : "wand.and.stars"
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
    let text: Color
    let secondary: Color
    let tertiary: Color
    let accent: Color
    let accentText: Color
    let success: Color
    let warning: Color
    let error: Color

    static func ember(_ appearance: PrototypeAppearance) -> Palette {
        switch appearance {
        case .dark:
            Palette(
                canvas: Color(hex: 0x07090B),
                sidebar: Color(hex: 0x090B0E),
                surface: Color(hex: 0x0D1013),
                raised: Color(hex: 0x13171B),
                hover: Color(hex: 0x1A2026),
                border: Color(hex: 0x262C32),
                borderStrong: Color(hex: 0x5B6570),
                text: Color(hex: 0xF4F5F6),
                secondary: Color(hex: 0xA4AAB0),
                tertiary: Color(hex: 0x747C85),
                accent: Color(hex: 0xFF6A1A),
                accentText: Color(hex: 0x160900),
                success: Color(hex: 0x43D17A),
                warning: Color(hex: 0xF0B44B),
                error: Color(hex: 0xFF6464)
            )
        case .light:
            Palette(
                canvas: Color(hex: 0xF7F3EC),
                sidebar: Color(hex: 0xEEE8DE),
                surface: Color(hex: 0xFFFCF7),
                raised: Color(hex: 0xF4EFE7),
                hover: Color(hex: 0xEAE2D7),
                border: Color(hex: 0xD8CFC1),
                borderStrong: Color(hex: 0x978B7C),
                text: Color(hex: 0x1A1714),
                secondary: Color(hex: 0x625C55),
                tertiary: Color(hex: 0x766E65),
                accent: Color(hex: 0xBF4008),
                accentText: .white,
                success: Color(hex: 0x147A42),
                warning: Color(hex: 0x865B00),
                error: Color(hex: 0xB4232C)
            )
        }
    }
}

private struct ModelRow: Identifiable {
    let id: String
    let family: ModelFamily
    let name: String
    let fit: String
    let size: String
    let speed: Int?
    let quality: Int?
    let state: String
    let stateSymbol: String
    let stateTone: StateTone
    let isSavedSelection: Bool
    let isEffectiveFallback: Bool
    let progress: Double?
    let canCancel: Bool
}

private enum StateTone {
    case neutral
    case accent
    case success
    case warning
    case error
}

private struct SnapshotCase {
    let variant: ModelsVariant
    let appearance: PrototypeAppearance
    let width: WidthPreview
    let state: StatePreview
    let contrast: ContrastPreview

    var filename: String {
        [
            variant.key.lowercased(),
            variant.rawValue,
            appearance.rawValue.lowercased(),
            width == .compact ? "compact" : "default",
            state.rawValue.lowercased(),
        ].joined(separator: "-") + ".png"
    }
}

@main
private enum ModelsVisualGrammarPrototypeApp {
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
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    @MainActor
    private static func renderSnapshots() {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".context/models-visual-grammar-shots", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: output,
            withIntermediateDirectories: true
        )
        if let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        ) {
            for file in staleFiles where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        var cases: [SnapshotCase] = []
        for variant in ModelsVariant.allCases {
            for appearance in PrototypeAppearance.allCases {
                cases.append(SnapshotCase(
                    variant: variant,
                    appearance: appearance,
                    width: .standard,
                    state: .baseline,
                    contrast: .standard
                ))
                cases.append(SnapshotCase(
                    variant: variant,
                    appearance: appearance,
                    width: .compact,
                    state: .fallback,
                    contrast: .standard
                ))
            }
            for state in [StatePreview.progress, .repair, .error, .focus, .confirm] {
                cases.append(SnapshotCase(
                    variant: variant,
                    appearance: .dark,
                    width: state == .focus ? .compact : .standard,
                    state: state,
                    contrast: state == .focus ? .increased : .standard
                ))
            }
        }

        let size = CGSize(width: 1440, height: 900)
        for item in cases {
            let root = PrototypeRoot(
                initialVariant: item.variant,
                initialAppearance: item.appearance,
                initialWidth: item.width,
                initialState: item.state,
                initialContrast: item.contrast
            )
            .frame(width: size.width, height: size.height)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.appearance = NSAppearance(
                named: item.appearance == .light ? .aqua : .darkAqua
            )
            let window = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.contentView = hosting
            window.appearance = hosting.appearance
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
            else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:])
            else { continue }
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
        window.title = "FoldWise Models visual grammar prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1440, height: 900))
        window.contentMinSize = CGSize(width: 1180, height: 780)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

private struct PrototypeRoot: View {
    @State private var variant: ModelsVariant
    @State private var appearance: PrototypeAppearance
    @State private var width: WidthPreview
    @State private var state: StatePreview
    @State private var contrast: ContrastPreview

    init(
        initialVariant: ModelsVariant = .trace,
        initialAppearance: PrototypeAppearance = .dark,
        initialWidth: WidthPreview = .standard,
        initialState: StatePreview = .baseline,
        initialContrast: ContrastPreview = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _appearance = State(initialValue: initialAppearance)
        _width = State(initialValue: initialWidth)
        _state = State(initialValue: initialState)
        _contrast = State(initialValue: initialContrast)
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        ZStack(alignment: .bottom) {
            palette.canvas.ignoresSafeArea()
            WindowPreview(
                variant: variant,
                width: width,
                state: state,
                contrast: contrast,
                palette: palette
            )
            .frame(
                width: width.modelsWidth + 190,
                height: width.previewHeight
            )
            .padding(.bottom, 104)

            ReviewBar(
                variant: $variant,
                appearance: $appearance,
                width: $width,
                state: $state,
                contrast: $contrast
            )
            .environment(\.colorScheme, .dark)
            .padding(.bottom, 18)
        }
        .environment(\.colorScheme, appearance.scheme)
    }
}

private struct WindowPreview: View {
    let variant: ModelsVariant
    let width: WidthPreview
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            Titlebar(palette: palette, width: width)
            Hairline(color: borderColor)
            HStack(spacing: 0) {
                Sidebar(palette: palette)
                    .frame(width: 190)
                Hairline(color: borderColor, vertical: true)
                ModelsDestination(
                    variant: variant,
                    width: width,
                    state: state,
                    contrast: contrast,
                    palette: palette
                )
                .frame(width: width.modelsWidth)
            }
        }
        .background(palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private struct Titlebar: View {
    let palette: Palette
    let width: WidthPreview

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xFF5F57)).frame(width: 10, height: 10)
                Circle().fill(Color(hex: 0xFEBB2E)).frame(width: 10, height: 10)
                Circle().fill(Color(hex: 0x28C840)).frame(width: 10, height: 10)
            }
            Image(systemName: "sidebar.left")
                .foregroundStyle(palette.secondary)
            WaveformMark(color: palette.accent)
            HStack(spacing: 0) {
                Text("FoldWise")
                    .foregroundStyle(palette.accent)
                Text(" Voice")
                    .foregroundStyle(palette.text)
            }
            Spacer()
            Text("\(Int(width.modelsWidth)) PT MODELS SURFACE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(palette.tertiary)
        }
        .font(.system(size: 14, weight: .semibold))
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(palette.canvas)
    }
}

private struct Sidebar: View {
    let palette: Palette

    private let destinations = [
        ("house", "Home"),
        ("sparkles", "Modes"),
        ("shippingbox", "Models"),
        ("clock", "History"),
        ("chart.bar", "Stats"),
        ("slider.horizontal.3", "Settings"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(destinations, id: \.1) { destination in
                let selected = destination.1 == "Models"
                HStack(spacing: 12) {
                    Image(systemName: destination.0)
                        .frame(width: 18)
                        .foregroundStyle(selected ? palette.accent : palette.tertiary)
                    Text(destination.1)
                        .foregroundStyle(selected ? palette.text : palette.secondary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(selected ? palette.raised : .clear)
                .overlay(alignment: .leading) {
                    if selected {
                        Rectangle().fill(palette.accent).frame(width: 3)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            Spacer()
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text("v0.15.0")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(palette.tertiary)
        }
        .padding(12)
        .background(palette.sidebar)
    }
}

private struct ModelsDestination: View {
    let variant: ModelsVariant
    let width: WidthPreview
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    private var rows: [ModelRow] {
        ModelFixtures.rows(for: state)
    }

    private var inspected: ModelRow {
        let id = ModelFixtures.inspectedID(for: state)
        return rows.first(where: { $0.id == id }) ?? rows[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            destinationHeader
            Hairline(color: borderColor)
            switch variant {
            case .trace:
                TraceLedgerWorkspace(
                    rows: rows,
                    inspected: inspected,
                    state: state,
                    contrast: contrast,
                    palette: palette,
                    ratio: variant.wideLedgerRatio
                )
            case .bays:
                FamilyBaysWorkspace(
                    rows: rows,
                    inspected: inspected,
                    state: state,
                    contrast: contrast,
                    palette: palette,
                    ratio: variant.wideLedgerRatio
                )
            case .inspector:
                InspectorForwardWorkspace(
                    rows: rows,
                    inspected: inspected,
                    state: state,
                    contrast: contrast,
                    palette: palette,
                    ratio: variant.wideLedgerRatio
                )
            }
        }
        .background(palette.canvas)
        .overlay {
            if state == .confirm {
                ConfirmationOverlay(palette: palette, contrast: contrast)
            }
        }
    }

    private var destinationHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Models")
                    .font(.system(size: 25, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(palette.text)
                Text("Compare what runs each stage, then manage its local data.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(variant.key + " — " + variant.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(palette.accent)
                if width == .standard {
                    Text(variant.thesis)
                        .font(.system(size: 9.5))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(palette.canvas)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct TraceLedgerWorkspace: View {
    let rows: [ModelRow]
    let inspected: ModelRow
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette
    let ratio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let leading = splitWidth(total: geometry.size.width, ratio: ratio)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach([ModelFamily.speech, .polish], id: \.rawValue) { family in
                            TraceFamily(
                                family: family,
                                rows: rows.filter { $0.family == family },
                                inspectedID: inspected.id,
                                state: state,
                                contrast: contrast,
                                palette: palette
                            )
                        }
                    }
                    .padding(14)
                }
                .frame(width: leading)
                .background(palette.sidebar.opacity(0.55))
                Hairline(color: borderColor, vertical: true)
                TraceInspector(
                    row: inspected,
                    state: state,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct TraceFamily: View {
    let family: ModelFamily
    let rows: [ModelRow]
    let inspectedID: String
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FamilyHeading(family: family, palette: palette)
            LedgerColumnHeaders(palette: palette)
            if family == .speech, state == .fallback {
                RecoveryNotice(palette: palette, contrast: contrast)
            }
            ForEach(rows) { row in
                TraceRow(
                    row: row,
                    inspected: row.id == inspectedID,
                    focused: state == .focus && row.id == inspectedID,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }
}

private struct TraceRow: View {
    let row: ModelRow
    let inspected: Bool
    let focused: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if row.isSavedSelection {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                    Text(row.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                }
                Text(row.fit)
                    .font(.system(size: 8.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DataText(row.size, palette: palette).frame(width: 38, alignment: .trailing)
            RatingDots(value: row.speed, palette: palette).frame(width: 38)
            RatingDots(value: row.quality, palette: palette).frame(width: 38)
            RowState(row: row, palette: palette).frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(height: 39)
        .background(inspected ? palette.raised : palette.surface)
        .overlay(alignment: .leading) {
            if inspected {
                Rectangle().fill(palette.accent).frame(width: 3)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    focused ? palette.accent : borderColor,
                    lineWidth: focused ? 2 : borderWidth
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private struct TraceInspector: View {
    let row: ModelRow
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                InspectorIdentity(row: row, palette: palette)
                VStack(alignment: .leading, spacing: 14) {
                    InspectorStatus(row: row, state: state, palette: palette)
                    Divider().overlay(palette.border)
                    InspectorCopy(row: row, palette: palette)
                    FamilyExplanation(family: row.family, palette: palette)
                }
                .padding(18)
            }
            Hairline(color: borderColor)
            InspectorAction(row: row, state: state, palette: palette)
                .padding(14)
        }
        .background(palette.canvas)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct FamilyBaysWorkspace: View {
    let rows: [ModelRow]
    let inspected: ModelRow
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette
    let ratio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let leading = splitWidth(total: geometry.size.width, ratio: ratio)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach([ModelFamily.speech, .polish], id: \.rawValue) { family in
                            FamilyBay(
                                family: family,
                                rows: rows.filter { $0.family == family },
                                inspectedID: inspected.id,
                                state: state,
                                contrast: contrast,
                                palette: palette
                            )
                        }
                    }
                    .padding(14)
                }
                .frame(width: leading)
                .background(palette.canvas)
                Hairline(color: borderColor, vertical: true)
                BayInspector(
                    row: inspected,
                    state: state,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct FamilyBay: View {
    let family: ModelFamily
    let rows: [ModelRow]
    let inspectedID: String
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: family.symbol)
                    .foregroundStyle(family == .speech ? palette.accent : palette.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(family.rawValue)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.text)
                    Text(family.semanticLabel.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(palette.tertiary)
                }
                Spacer()
                Text("\(rows.count) MODELS")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(palette.raised)
            Hairline(color: borderColor)
            if family == .speech, state == .fallback {
                RecoveryNotice(palette: palette, contrast: contrast)
                    .padding(8)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                BayRow(
                    row: row,
                    inspected: row.id == inspectedID,
                    focused: state == .focus && row.id == inspectedID,
                    palette: palette
                )
                if index != rows.count - 1 {
                    Hairline(color: palette.border)
                }
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }

    private var borderWidth: CGFloat {
        contrast == .increased ? 2 : 1
    }
}

private struct BayRow: View {
    let row: ModelRow
    let inspected: Bool
    let focused: Bool
    let palette: Palette

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2)
                .fill(inspected ? palette.accent : Color.clear)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if row.isSavedSelection {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                    Text(row.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    Text(row.fit).lineLimit(1)
                    Text(row.size)
                    Text("S\(row.speed.map(String.init) ?? "—")")
                    Text("Q\(row.quality.map(String.init) ?? "—")")
                }
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 6)
            RowState(row: row, palette: palette)
        }
        .padding(.horizontal, 9)
        .frame(height: 45)
        .background(inspected ? palette.hover : .clear)
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(palette.accent, lineWidth: 2)
                    .padding(2)
            }
        }
    }
}

private struct BayInspector: View {
    let row: ModelRow
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Rectangle().fill(palette.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.family.semanticLabel.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(palette.tertiary)
                    Text(row.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(row.fit)
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.secondary)
                }
                .padding(16)
                Spacer()
            }
            .background(palette.raised)
            Hairline(color: borderColor)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InspectorStatus(row: row, state: state, palette: palette)
                    FactsStrip(row: row, palette: palette)
                    InspectorCopy(row: row, palette: palette)
                    FamilyExplanation(family: row.family, palette: palette)
                }
                .padding(16)
            }
            Hairline(color: borderColor)
            InspectorAction(row: row, state: state, palette: palette)
                .padding(14)
        }
        .background(palette.sidebar.opacity(0.55))
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct InspectorForwardWorkspace: View {
    let rows: [ModelRow]
    let inspected: ModelRow
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette
    let ratio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let leading = splitWidth(total: geometry.size.width, ratio: ratio)
            HStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach([ModelFamily.speech, .polish], id: \.rawValue) { family in
                            IndexFamily(
                                family: family,
                                rows: rows.filter { $0.family == family },
                                inspectedID: inspected.id,
                                state: state,
                                contrast: contrast,
                                palette: palette
                            )
                        }
                    }
                    .padding(14)
                }
                .frame(width: leading)
                .background(palette.sidebar.opacity(0.62))
                Hairline(color: borderColor, vertical: true)
                DossierInspector(
                    row: inspected,
                    state: state,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct IndexFamily: View {
    let family: ModelFamily
    let rows: [ModelRow]
    let inspectedID: String
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FamilyHeading(family: family, palette: palette)
                .padding(.bottom, 6)
            if family == .speech, state == .fallback {
                RecoveryNotice(palette: palette, contrast: contrast)
                    .padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                IndexRow(
                    row: row,
                    index: index + 1,
                    inspected: row.id == inspectedID,
                    focused: state == .focus && row.id == inspectedID,
                    palette: palette
                )
            }
        }
    }
}

private struct IndexRow: View {
    let row: ModelRow
    let index: Int
    let inspected: Bool
    let focused: Bool
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", index))
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(inspected ? palette.accent : palette.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if row.isSavedSelection {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                    Text(row.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(1)
                    Spacer()
                    RowState(row: row, palette: palette)
                }
                Text(indexFacts)
                    .font(.system(size: 8.3, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 43)
        .background(inspected ? palette.raised : .clear)
        .overlay(alignment: .bottom) {
            Hairline(color: palette.border)
        }
        .overlay {
            if focused {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(palette.accent, lineWidth: 2)
                    .padding(2)
            }
        }
    }

    private var indexFacts: String {
        let speed = row.speed.map(String.init) ?? "—"
        let quality = row.quality.map(String.init) ?? "—"
        return "\(row.fit)  ·  \(row.size)  ·  S\(speed) / Q\(quality)"
    }
}

private struct DossierInspector: View {
    let row: ModelRow
    let state: StatePreview
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: row.family.symbol)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(palette.accent)
                            .frame(width: 42, height: 42)
                            .background(palette.raised)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.family.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(palette.tertiary)
                            Text(row.name)
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(-0.3)
                                .foregroundStyle(palette.text)
                            Text(row.fit)
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    FactsStrip(row: row, palette: palette)
                    InspectorStatus(row: row, state: state, palette: palette)
                    InspectorCopy(row: row, palette: palette)
                    FamilyExplanation(family: row.family, palette: palette)
                }
                .padding(20)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Hairline(color: borderColor)
            InspectorAction(row: row, state: state, palette: palette)
                .padding(14)
        }
        .background(palette.canvas)
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct FamilyHeading: View {
    let family: ModelFamily
    let palette: Palette

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: family.symbol)
                .foregroundStyle(family == .speech ? palette.accent : palette.tertiary)
            Text(family.rawValue.uppercased())
            Text("—").foregroundStyle(palette.tertiary)
            Text(family.semanticLabel)
                .foregroundStyle(family == .speech ? palette.accent : palette.secondary)
            Spacer()
        }
        .font(.system(size: 8.8, weight: .bold, design: .monospaced))
        .tracking(0.55)
        .foregroundStyle(palette.tertiary)
    }
}

private struct LedgerColumnHeaders: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 6) {
            Text("MODEL / FIT").frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE").frame(width: 38, alignment: .trailing)
            Text("SPD").frame(width: 38)
            Text("QLT").frame(width: 38)
            Text("STATE").frame(width: 62, alignment: .trailing)
        }
        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
        .tracking(0.4)
        .foregroundStyle(palette.tertiary)
        .padding(.horizontal, 8)
    }
}

private struct RecoveryNotice: View {
    let palette: Palette
    let contrast: ContrastPreview

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(palette.warning)
            Text(
                "Whisper large-v3-turbo is saved but unavailable. "
                    + "Parakeet TDT v3 is the Effective ASR model until you download it again."
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 8.7, weight: .medium))
        .foregroundStyle(palette.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raised)
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.warning).frame(width: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct InspectorIdentity: View {
    let row: ModelRow
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(palette.accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.family.semanticLabel.uppercased())
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(palette.tertiary)
                Text(row.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(row.fit)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }
            .padding(18)
            Spacer()
        }
        .background(palette.raised)
    }
}

private struct InspectorStatus: View {
    let row: ModelRow
    let state: StatePreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("STATUS")
                .sectionLabel(palette: palette)
            HStack(spacing: 7) {
                Image(systemName: row.stateSymbol)
                    .foregroundStyle(toneColor(row.stateTone, palette: palette))
                Text(row.state)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            if row.progress != nil {
                ProgressView(value: row.progress)
                    .tint(palette.accent)
                Text(progressExplanation)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.secondary)
            } else if state == .error {
                Text(
                    "The download could not be verified because the local model data is incomplete. "
                        + "Your saved selection did not change."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if state == .repair {
                Text(
                    "Default model preparation failed. "
                        + "Dictation is blocked until Parakeet is repaired and can load successfully."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else if row.isEffectiveFallback {
                Text(
                    "Your saved selection remains Whisper large-v3-turbo. "
                        + "Dictation uses Parakeet only until the saved model is available again."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(statusExplanation)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(palette.border)
        }
    }

    private var progressExplanation: String {
        row.family == .speech
            ? "64% · preparing local ASR model data · cancellation available"
            : "contacting Ollama… · one Polish inventory mutation at a time"
    }

    private var statusExplanation: String {
        if row.family == .speech {
            return row.isSavedSelection
                ? "This is the saved ASR model selection for the next Dictation session."
                : "Inspecting this row does not change the saved ASR model selection."
        }
        return "Installed Polish models remain inventory here and are assigned separately by each Mode."
    }
}

private struct InspectorCopy: View {
    let row: ModelRow
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("WHAT IT IS FOR")
                .sectionLabel(palette: palette)
            Text(description)
                .font(.system(size: 10.8))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var description: String {
        switch row.id {
        case "asr-parakeet":
            "Fast, power-efficient recognition on Apple Neural Engine hardware, "
                + "covering common European languages and Japanese."
        case "asr-whisper":
            "Broad on-device language coverage with a balanced quality and footprint trade-off. "
                + "Downloading adds availability but never selects it."
        case "asr-small":
            "A smaller multilingual ASR model for lower storage pressure and faster preparation."
        case "polish-qwen":
            "Strong prompt adherence and multilingual output for both in-place and expanding Modes."
        case "polish-gemma":
            "A compact local model suited to fast in-place Modes on memory-constrained Macs."
        default:
            "Install any Ollama library model by its model:tag name. Installing does not assign it to a Mode."
        }
    }
}

private struct FamilyExplanation: View {
    let family: ModelFamily
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(family.semanticLabel.uppercased())
                .sectionLabel(palette: palette)
            Text(explanation)
                .font(.system(size: 10.2))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanation: String {
        if family == .speech {
            return "One global ASR model selection is captured when each Dictation session begins. "
                + "Availability and Effective ASR model are separate facts."
        }
        return "Polish models are local inventory. Each Mode chooses its own model; "
            + "unavailable assignments safely fall back to raw text."
    }
}

private struct FactsStrip: View {
    let row: ModelRow
    let palette: Palette

    var body: some View {
        HStack(spacing: 0) {
            Fact(label: "SIZE", value: row.size, palette: palette)
            Fact(
                label: "SPEED",
                value: row.speed.map { "\($0) / 5" } ?? "—",
                palette: palette
            )
            Fact(
                label: "QUALITY",
                value: row.quality.map { "\($0) / 5" } ?? "—",
                palette: palette
            )
        }
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(palette.border)
        }
    }
}

private struct Fact: View {
    let label: String
    let value: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.text)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InspectorAction: View {
    let row: ModelRow
    let state: StatePreview
    let palette: Palette

    var body: some View {
        HStack(spacing: 9) {
            if row.canCancel {
                Button("Cancel") {}
                    .buttonStyle(SecondaryPrototypeButton(palette: palette))
            }
            if row.progress != nil {
                Label(row.state, systemImage: row.stateSymbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            } else if row.isSavedSelection && row.state == "Selected" {
                Label("Selected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.accent)
            } else if row.family == .polish && row.state == "Installed" {
                Label("Installed", systemImage: "checkmark.square.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(palette.success)
            } else {
                Button(actionTitle) {}
                    .buttonStyle(PrimaryPrototypeButton(palette: palette))
            }
            Spacer()
            if destructiveAvailable {
                Button {} label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(SecondaryPrototypeButton(palette: palette))
                .help(row.family == .speech ? "Delete model" : "Uninstall model")
            }
        }
    }

    private var actionTitle: String {
        if state == .repair {
            return "Retry repair"
        }
        if state == .error {
            return "Download again"
        }
        if row.family == .polish {
            return "Install"
        }
        if row.state.contains("unavailable") {
            return "Download again"
        }
        if row.state == "Download" {
            return "Download"
        }
        return "Select"
    }

    private var destructiveAvailable: Bool {
        row.family == .polish && row.state == "Installed"
            || row.family == .speech && !row.isSavedSelection && row.state == "Ready"
    }
}

private struct ConfirmationOverlay: View {
    let palette: Palette
    let contrast: ContrastPreview

    var body: some View {
        ZStack {
            Color.black.opacity(0.56)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "trash")
                        .foregroundStyle(palette.error)
                    Text("Uninstall qwen2.5:7b?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
                Text(
                    "This permanently removes 4.7 GB of local model data. "
                        + "Email, Bullets, and Meeting Notes will use raw text "
                        + "until you assign another available model."
                )
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel") {}
                        .buttonStyle(SecondaryPrototypeButton(palette: palette))
                    Button("Uninstall") {}
                        .buttonStyle(DestructivePrototypeButton(palette: palette))
                }
            }
            .padding(18)
            .frame(width: 360)
            .background(palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        contrast == .increased ? palette.borderStrong : palette.border,
                        lineWidth: contrast == .increased ? 2 : 1
                    )
            }
            .shadow(color: .black.opacity(0.42), radius: 26, y: 12)
        }
    }
}

private struct RowState: View {
    let row: ModelRow
    let palette: Palette

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: row.stateSymbol)
                Text(primaryState)
            }
            .font(.system(size: 7.7, weight: .bold, design: .monospaced))
            .foregroundStyle(toneColor(row.stateTone, palette: palette))
            if let secondaryState {
                Text(secondaryState)
                    .font(.system(size: 6.8, weight: .bold, design: .monospaced))
                    .foregroundStyle(toneColor(row.stateTone, palette: palette))
            }
            if let progress = row.progress {
                ProgressView(value: progress)
                    .tint(palette.accent)
                    .frame(width: 54)
            }
        }
        .lineLimit(1)
    }

    private var primaryState: String {
        if row.canCancel, row.progress != nil {
            return "64% · Cancel"
        }
        if row.state == "Saved · unavailable" {
            return "SAVED"
        }
        if row.state == "Effective fallback" {
            return "EFFECTIVE"
        }
        if row.state == "Repair required" {
            return "REPAIR"
        }
        return row.state
    }

    private var secondaryState: String? {
        if row.state == "Saved · unavailable" {
            return "UNAVAILABLE"
        }
        if row.state == "Effective fallback" {
            return "FALLBACK"
        }
        if row.state == "Repair required" {
            return "REQUIRED"
        }
        return nil
    }
}

private struct RatingDots: View {
    let value: Int?
    let palette: Palette

    var body: some View {
        HStack(spacing: 2) {
            if let value {
                ForEach(1 ... 5, id: \.self) { index in
                    Circle()
                        .fill(index <= value ? palette.secondary : palette.border)
                        .frame(width: 4, height: 4)
                }
            } else {
                Text("—")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(palette.tertiary)
            }
        }
    }
}

private struct DataText: View {
    let text: String
    let palette: Palette

    init(_ text: String, palette: Palette) {
        self.text = text
        self.palette = palette
    }

    var body: some View {
        Text(text)
            .font(.system(size: 8.2, weight: .medium, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
    }
}

private struct ReviewBar: View {
    @Binding var variant: ModelsVariant
    @Binding var appearance: PrototypeAppearance
    @Binding var width: WidthPreview
    @Binding var state: StatePreview
    @Binding var contrast: ContrastPreview

    var body: some View {
        HStack(spacing: 10) {
            Button {
                cycleVariant(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(ReviewArrowButton())
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Text("\(variant.key) — \(variant.title)")
                .font(.system(size: 12.5, weight: .semibold))
                .frame(width: 154, alignment: .leading)

            Button {
                cycleVariant(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(ReviewArrowButton())
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            ReviewDivider()
            Picker("", selection: $appearance) {
                ForEach(PrototypeAppearance.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 118)

            Picker("", selection: $width) {
                ForEach(WidthPreview.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 140)

            Picker("", selection: $state) {
                ForEach(StatePreview.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 462)

            Picker("", selection: $contrast) {
                ForEach(ContrastPreview.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 160)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .foregroundStyle(.white)
        .background(Color.black.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    private func cycleVariant(_ offset: Int) {
        let variants = ModelsVariant.allCases
        guard let current = variants.firstIndex(of: variant) else { return }
        let next = (current + offset + variants.count) % variants.count
        variant = variants[next]
    }
}

private struct ReviewArrowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? Color.white.opacity(0.16) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ReviewDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 28)
    }
}

private struct PrimaryPrototypeButton: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.accentText)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(palette.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SecondaryPrototypeButton: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.text)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(configuration.isPressed ? palette.hover : palette.raised)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(palette.border)
            }
    }
}

private struct DestructivePrototypeButton: ButtonStyle {
    let palette: Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 28)
            .background(palette.error.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct Hairline: View {
    let color: Color
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(
                width: vertical ? 1 : nil,
                height: vertical ? nil : 1
            )
    }
}

private struct WaveformMark: View {
    let color: Color

    private let heights: [CGFloat] = [8, 15, 23, 13, 28, 18, 24, 11]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(color)
                    .frame(width: 2, height: height)
            }
        }
        .frame(width: 28, height: 30)
        .accessibilityHidden(true)
    }
}

private enum ModelFixtures {
    static func inspectedID(for state: StatePreview) -> String {
        switch state {
        case .baseline: "asr-parakeet"
        case .fallback: "asr-whisper"
        case .progress: "asr-whisper"
        case .repair: "asr-parakeet"
        case .error: "asr-small"
        case .focus: "polish-qwen"
        case .confirm: "polish-qwen"
        }
    }

    static func rows(for state: StatePreview) -> [ModelRow] {
        [
            speechParakeet(state),
            speechWhisper(state),
            speechSmall(state),
            polishQwen(state),
            polishGemma(state),
            polishUtility(state),
        ]
    }

    private static func speechParakeet(_ state: StatePreview) -> ModelRow {
        ModelRow(
            id: "asr-parakeet",
            family: .speech,
            name: "Parakeet TDT v3",
            fit: "25 languages · Neural Engine",
            size: "600 MB",
            speed: 5,
            quality: 4,
            state: parakeetState(state),
            stateSymbol: parakeetSymbol(state),
            stateTone: parakeetTone(state),
            isSavedSelection: state != .fallback,
            isEffectiveFallback: state == .fallback,
            progress: nil,
            canCancel: false
        )
    }

    private static func speechWhisper(_ state: StatePreview) -> ModelRow {
        ModelRow(
            id: "asr-whisper",
            family: .speech,
            name: "Whisper large-v3-turbo",
            fit: "~99 languages · balanced",
            size: "632 MB",
            speed: 3,
            quality: 4,
            state: whisperState(state),
            stateSymbol: whisperSymbol(state),
            stateTone: whisperTone(state),
            isSavedSelection: state == .fallback,
            isEffectiveFallback: false,
            progress: state == .progress ? 0.64 : nil,
            canCancel: state == .progress
        )
    }

    private static func speechSmall(_ state: StatePreview) -> ModelRow {
        ModelRow(
            id: "asr-small",
            family: .speech,
            name: "Whisper small",
            fit: "~99 languages · lighter",
            size: "483 MB",
            speed: 4,
            quality: 3,
            state: state == .error ? "Download failed" : "Ready",
            stateSymbol: state == .error ? "exclamationmark.octagon.fill" : "circle",
            stateTone: state == .error ? .error : .neutral,
            isSavedSelection: false,
            isEffectiveFallback: false,
            progress: nil,
            canCancel: false
        )
    }

    private static func polishQwen(_ state: StatePreview) -> ModelRow {
        ModelRow(
            id: "polish-qwen",
            family: .polish,
            name: "qwen2.5:7b",
            fit: "Multilingual · prompt-faithful",
            size: "4.7 GB",
            speed: 3,
            quality: 4,
            state: "Installed",
            stateSymbol: "checkmark.square.fill",
            stateTone: .success,
            isSavedSelection: false,
            isEffectiveFallback: false,
            progress: nil,
            canCancel: false
        )
    }

    private static func polishGemma(_ state: StatePreview) -> ModelRow {
        ModelRow(
            id: "polish-gemma",
            family: .polish,
            name: "gemma3:4b",
            fit: "Balanced local Polish",
            size: "3.3 GB",
            speed: 4,
            quality: 4,
            state: state == .progress ? "Contacting…" : "Install",
            stateSymbol: state == .progress ? "arrow.down.circle" : "plus.circle",
            stateTone: state == .progress ? .accent : .neutral,
            isSavedSelection: false,
            isEffectiveFallback: false,
            progress: state == .progress ? 0.18 : nil,
            canCancel: false
        )
    }

    private static func polishUtility(_ state: StatePreview) -> ModelRow {
        ModelRow(
            id: "polish-utility",
            family: .polish,
            name: "Install by name",
            fit: "Any Ollama model:tag",
            size: "—",
            speed: nil,
            quality: nil,
            state: state == .error ? "Install failed" : "Other",
            stateSymbol: state == .error ? "exclamationmark.octagon.fill" : "plus.circle",
            stateTone: state == .error ? .error : .neutral,
            isSavedSelection: false,
            isEffectiveFallback: false,
            progress: nil,
            canCancel: false
        )
    }

    private static func whisperState(_ state: StatePreview) -> String {
        switch state {
        case .fallback: "Saved · unavailable"
        case .progress: "Downloading"
        default: "Download"
        }
    }

    private static func whisperSymbol(_ state: StatePreview) -> String {
        switch state {
        case .fallback: "exclamationmark.triangle.fill"
        case .progress: "arrow.down.circle"
        default: "arrow.down.circle"
        }
    }

    private static func whisperTone(_ state: StatePreview) -> StateTone {
        switch state {
        case .fallback: .warning
        case .progress: .accent
        default: .neutral
        }
    }

    private static func parakeetState(_ state: StatePreview) -> String {
        switch state {
        case .fallback: "Effective fallback"
        case .repair: "Repair required"
        default: "Selected"
        }
    }

    private static func parakeetSymbol(_ state: StatePreview) -> String {
        switch state {
        case .repair: "wrench.and.screwdriver.fill"
        case .fallback: "arrow.trianglehead.2.clockwise.rotate.90"
        default: "checkmark.circle.fill"
        }
    }

    private static func parakeetTone(_ state: StatePreview) -> StateTone {
        switch state {
        case .repair: .error
        case .fallback: .warning
        default: .accent
        }
    }
}

private func splitWidth(total: CGFloat, ratio: CGFloat) -> CGFloat {
    let available = total - 1
    return min(max(available * ratio, 340), available - 270)
}

private func toneColor(_ tone: StateTone, palette: Palette) -> Color {
    switch tone {
    case .neutral: palette.secondary
    case .accent: palette.accent
    case .success: palette.success
    case .warning: palette.warning
    case .error: palette.error
    }
}

private extension Text {
    func sectionLabel(palette: Palette) -> some View {
        font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.55)
            .foregroundStyle(palette.tertiary)
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
