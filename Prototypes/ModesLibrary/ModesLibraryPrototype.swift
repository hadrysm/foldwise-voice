// THROWAWAY PROTOTYPE — visual decision aid for Wayfinder ticket
// "Prototype Modes and the Mode editor".
//
// Three structurally different Modes compositions, switchable from the bottom
// review bar, preserve Mode selection, ordering, detail, empty, unavailable-
// model, destructive-confirmation, and editor contracts while applying the
// approved Ember Edge visual grammar and Continuous Frame shell.

import AppKit
import SwiftUI

private enum ModesVariant: String, CaseIterable, Identifiable {
    case ledger = "Command Ledger"
    case rail = "Studio Rail"
    case stack = "Mode Stack"

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .ledger: "A"
        case .rail: "B"
        case .stack: "C"
        }
    }

    var thesis: String {
        switch self {
        case .ledger:
            "Selection stays visible in a dense library while detail occupies a stable inspector."
        case .rail:
            "Modes read as an instrument rack above one generous editing canvas."
        case .stack:
            "Selection and detail live together; the active Mode expands in place."
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

private enum ModesScene: String, CaseIterable, Identifiable {
    case library = "Selected Mode"
    case voice = "Voice to Text"
    case empty = "Empty library"
    case unavailable = "Unavailable model"
    case delete = "Delete confirmation"
    case editor = "Edit sheet"
    case validation = "Validation errors"
    case retry = "Persistence retry"
    case icons = "Icon palette"

    var id: String {
        rawValue
    }

    var showsEditor: Bool {
        [.editor, .validation, .retry, .icons].contains(self)
    }
}

private enum ContrastPreview: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case increased = "Contrast+"

    var id: String {
        rawValue
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

private struct PrototypeMode: Identifiable {
    let id: String
    let name: String
    let icon: String
    let transformation: String
    let model: String
    let prompt: String
    let vocabulary: String
}

private let sampleModes = [
    PrototypeMode(
        id: "casual",
        name: "Casual",
        icon: "text.bubble",
        transformation: "Keep wording",
        model: "qwen2.5:3b",
        prompt: "Fix punctuation and casing while keeping my wording and tone.",
        vocabulary: "FoldWise · Ollama"
    ),
    PrototypeMode(
        id: "email",
        name: "Email",
        icon: "envelope",
        transformation: "Reshape",
        model: "qwen2.5:7b",
        prompt: "Turn the transcript into a concise, warm email with a clear next step.",
        vocabulary: "Mateusz · FoldWise · SwiftUI"
    ),
    PrototypeMode(
        id: "bullets",
        name: "Bullets",
        icon: "list.bullet",
        transformation: "Reshape",
        model: "qwen2.5:3b",
        prompt: "Organize the transcript into short, scannable bullet points.",
        vocabulary: "None"
    ),
]

private struct SnapshotCase {
    let variant: ModesVariant
    let appearance: PrototypeAppearance
    let scene: ModesScene
    let contrast: ContrastPreview

    var filename: String {
        [
            variant.key.lowercased(),
            variant.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"),
            appearance.rawValue.lowercased(),
            scene.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"),
        ].joined(separator: "-") + ".png"
    }
}

@main
private enum ModesLibraryPrototypeApp {
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
            .appendingPathComponent(".context/modes-library-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        if let staleFiles = try? FileManager.default.contentsOfDirectory(
            at: output,
            includingPropertiesForKeys: nil
        ) {
            for file in staleFiles where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }

        var cases: [SnapshotCase] = []
        for variant in ModesVariant.allCases {
            cases.append(.init(
                variant: variant,
                appearance: .dark,
                scene: .library,
                contrast: .standard
            ))
            cases.append(.init(
                variant: variant,
                appearance: .light,
                scene: .library,
                contrast: .standard
            ))
            for scene in [
                ModesScene.empty,
                .voice,
                .unavailable,
                .delete,
                .editor,
                .validation,
                .retry,
                .icons,
            ] {
                cases.append(.init(
                    variant: variant,
                    appearance: .dark,
                    scene: scene,
                    contrast: scene == .validation ? .increased : .standard
                ))
            }
        }

        let size = CGSize(width: 1220, height: 840)
        for item in cases {
            let root = PrototypeRoot(
                initialVariant: item.variant,
                initialAppearance: item.appearance,
                initialScene: item.scene,
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
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
        window.title = "FoldWise Modes prototype"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setContentSize(CGSize(width: 1220, height: 840))
        window.contentMinSize = CGSize(width: 1080, height: 760)
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
    @State private var variant: ModesVariant
    @State private var appearance: PrototypeAppearance
    @State private var scene: ModesScene
    @State private var contrast: ContrastPreview

    init(
        initialVariant: ModesVariant = .ledger,
        initialAppearance: PrototypeAppearance = .dark,
        initialScene: ModesScene = .library,
        initialContrast: ContrastPreview = .standard
    ) {
        _variant = State(initialValue: initialVariant)
        _appearance = State(initialValue: initialAppearance)
        _scene = State(initialValue: initialScene)
        _contrast = State(initialValue: initialContrast)
    }

    var body: some View {
        let palette = Palette.ember(appearance)
        ZStack(alignment: .bottom) {
            palette.canvas.ignoresSafeArea()
            ModesWindow(
                variant: variant,
                scene: scene,
                contrast: contrast,
                palette: palette
            )
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 84)

            ReviewBar(
                variant: $variant,
                appearance: $appearance,
                scene: $scene,
                contrast: $contrast
            )
            .padding(.bottom, 15)
        }
        .environment(\.colorScheme, appearance.scheme)
    }
}

private struct ModesWindow: View {
    let variant: ModesVariant
    let scene: ModesScene
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            Titlebar(palette: palette)
            Hairline(color: borderColor)
            HStack(spacing: 0) {
                Sidebar(palette: palette)
                Hairline(color: borderColor, vertical: true)
                ZStack {
                    Destination(
                        variant: variant,
                        scene: scene,
                        contrast: contrast,
                        palette: palette
                    )
                    if scene == .delete {
                        ModalScrim(palette: palette) {
                            DeleteConfirmation(palette: palette, contrast: contrast)
                        }
                    } else if scene.showsEditor {
                        ModalScrim(palette: palette) {
                            ModeEditor(scene: scene, palette: palette, contrast: contrast)
                        }
                    }
                }
            }
        }
        .background(palette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: .black.opacity(0.3), radius: 22, y: 10)
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

    var body: some View {
        HStack(spacing: 12) {
            TrafficLights()
            SidebarToggleGlyph(color: palette.tertiary)
            WaveMark(color: palette.accent)
                .frame(width: 28, height: 17)
            HStack(spacing: 3) {
                Text("FoldWise")
                    .foregroundStyle(palette.accent)
                Text("Voice")
                    .foregroundStyle(palette.text)
            }
            .font(.system(size: 12, weight: .semibold))
            Spacer()
            Text("MODES / VISUAL PROTOTYPE")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(palette.sidebar)
    }
}

private struct Sidebar: View {
    let palette: Palette

    private let destinations = [
        ("Home", "house"),
        ("Modes", "sparkles"),
        ("Models", "shippingbox"),
        ("History", "clock"),
        ("Stats", "chart.bar"),
        ("Settings", "slider.horizontal.3"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(destinations, id: \.0) { destination in
                let active = destination.0 == "Modes"
                HStack(spacing: 9) {
                    Image(systemName: destination.1)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(active ? palette.accent : palette.tertiary)
                    Text(destination.0)
                        .font(.system(size: 12, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? palette.text : palette.secondary)
                    Spacer()
                    if active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 36)
                .background(active ? palette.raised : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .leading) {
                    if active {
                        Rectangle().fill(palette.accent).frame(width: 2, height: 22)
                    }
                }
            }
            Spacer()
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
            Text("v0.15.0")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: 190)
        .background(palette.sidebar)
    }
}

private struct Destination: View {
    let variant: ModesVariant
    let scene: ModesScene
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Header(variant: variant, palette: palette)
            Group {
                switch variant {
                case .ledger:
                    CommandLedger(scene: baseScene, contrast: contrast, palette: palette)
                case .rail:
                    StudioRail(scene: baseScene, contrast: contrast, palette: palette)
                case .stack:
                    ModeStack(scene: baseScene, contrast: contrast, palette: palette)
                }
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.canvas)
    }

    private var baseScene: ModesScene {
        scene.showsEditor || scene == .delete ? .library : scene
    }
}

private struct Header: View {
    let variant: ModesVariant
    let palette: Palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Modes")
                    .font(.system(size: 30, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(palette.text)
                Text(variant.thesis)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            PrimaryButton(title: "Add Mode", icon: "plus", palette: palette)
        }
    }
}

private struct CommandLedger: View {
    let scene: ModesScene
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("DICTATION SELECTION", palette: palette)
                Surface(contrast: contrast, palette: palette) {
                    SelectionRow(
                        icon: "waveform",
                        title: "Voice to Text",
                        detail: "Raw transcription — no Polish",
                        selected: scene == .voice || scene == .empty,
                        protected: true,
                        palette: palette
                    )
                }
                SectionLabel("YOUR MODES · CYCLE ORDER", palette: palette)
                if scene == .empty {
                    EmptyLibrary(compact: true, palette: palette)
                } else {
                    Surface(contrast: contrast, palette: palette) {
                        VStack(spacing: 0) {
                            ForEach(Array(sampleModes.enumerated()), id: \.element.id) { pair in
                                SelectionRow(
                                    icon: pair.element.icon,
                                    title: pair.element.name,
                                    detail: summary(pair.element, scene: scene),
                                    selected: scene != .voice && pair.element.id == "email",
                                    protected: false,
                                    palette: palette
                                )
                                if pair.offset < sampleModes.count - 1 {
                                    Hairline(color: palette.border)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: 330)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("MODE DETAILS", palette: palette)
                if scene == .voice || scene == .empty {
                    NoModeDetail(palette: palette, contrast: contrast)
                } else {
                    ModeInspector(
                        mode: sampleModes[1],
                        unavailable: scene == .unavailable,
                        contrast: contrast,
                        palette: palette
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct StudioRail: View {
    let scene: ModesScene
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel("DICTATION SELECTION · MODE CYCLE ORDER", palette: palette)
            HStack(spacing: 8) {
                RailTile(
                    icon: "waveform",
                    name: "Voice to Text",
                    caption: "System",
                    selected: scene == .voice || scene == .empty,
                    palette: palette
                )
                if scene == .empty {
                    EmptyRailSlot(palette: palette)
                } else {
                    ForEach(sampleModes) { mode in
                        RailTile(
                            icon: mode.icon,
                            name: mode.name,
                            caption: summary(mode, scene: scene),
                            selected: scene != .voice && mode.id == "email",
                            palette: palette
                        )
                    }
                }
            }
            if scene == .empty {
                EmptyLibrary(compact: false, palette: palette)
            } else if scene == .voice {
                NoModeDetail(palette: palette, contrast: contrast)
            } else {
                StudioInspector(
                    mode: sampleModes[1],
                    unavailable: scene == .unavailable,
                    contrast: contrast,
                    palette: palette
                )
            }
        }
    }
}

private struct ModeStack: View {
    let scene: ModesScene
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("DICTATION SELECTION · EXPANDED ITEM IS ACTIVE", palette: palette)
            Surface(contrast: contrast, palette: palette) {
                VStack(spacing: 0) {
                    StackSystemRow(
                        selected: scene == .voice || scene == .empty,
                        palette: palette
                    )
                    if scene == .empty {
                        Hairline(color: palette.border)
                        EmptyLibrary(compact: false, palette: palette)
                            .padding(12)
                    } else {
                        ForEach(sampleModes) { mode in
                            Hairline(color: palette.border)
                            StackModeRow(
                                mode: mode,
                                expanded: scene != .voice && mode.id == "email",
                                unavailable: scene == .unavailable && mode.id == "email",
                                palette: palette
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct SelectionRow: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    let protected: Bool
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? palette.accent : palette.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.text)
                    if protected {
                        Text("SYSTEM")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(palette.tertiary)
                    }
                }
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !protected {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(palette.tertiary)
            }
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? palette.accent : palette.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 54)
        .background(selected ? palette.raised : Color.clear)
        .overlay(alignment: .leading) {
            if selected {
                Rectangle().fill(palette.accent).frame(width: 2, height: 32)
            }
        }
    }
}

private struct RailTile: View {
    let icon: String
    let name: String
    let caption: String
    let selected: Bool
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? palette.accent : palette.secondary)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? palette.accent : palette.tertiary)
            }
            Text(name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(caption)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(palette.tertiary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(selected ? palette.raised : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? palette.accent : palette.border, lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if selected {
                Rectangle().fill(palette.accent).frame(width: 36, height: 2)
            }
        }
    }
}

private struct ModeInspector: View {
    let mode: PrototypeMode
    let unavailable: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        Surface(contrast: contrast, palette: palette) {
            VStack(alignment: .leading, spacing: 14) {
                InspectorHeader(mode: mode, palette: palette)
                Hairline(color: palette.border)
                DetailField(label: "AI MODEL", value: mode.model, mono: true, palette: palette)
                if unavailable {
                    UnavailableNotice(model: mode.model, palette: palette)
                }
                DetailField(
                    label: "POLISH INSTRUCTIONS",
                    value: mode.prompt,
                    mono: false,
                    palette: palette
                )
                DetailField(
                    label: "PRESERVED VOCABULARY",
                    value: mode.vocabulary,
                    mono: true,
                    palette: palette
                )
                Hairline(color: palette.border)
                LibraryActions(palette: palette)
            }
            .padding(16)
        }
    }
}

private struct StudioInspector: View {
    let mode: PrototypeMode
    let unavailable: Bool
    let contrast: ContrastPreview
    let palette: Palette

    var body: some View {
        Surface(contrast: contrast, palette: palette) {
            VStack(spacing: 0) {
                InspectorHeader(mode: mode, palette: palette)
                    .padding(16)
                Hairline(color: palette.border)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        DetailField(
                            label: "POLISH INSTRUCTIONS",
                            value: mode.prompt,
                            mono: false,
                            palette: palette
                        )
                        DetailField(
                            label: "PRESERVED VOCABULARY",
                            value: mode.vocabulary,
                            mono: true,
                            palette: palette
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    Hairline(color: palette.border, vertical: true)
                    VStack(alignment: .leading, spacing: 14) {
                        DetailField(
                            label: "AI MODEL",
                            value: mode.model,
                            mono: true,
                            palette: palette
                        )
                        if unavailable {
                            UnavailableNotice(model: mode.model, palette: palette)
                        }
                        Spacer(minLength: 20)
                        LibraryActions(palette: palette)
                    }
                    .padding(16)
                    .frame(width: 300, alignment: .topLeading)
                }
            }
        }
    }
}

private struct InspectorHeader: View {
    let mode: PrototypeMode
    let palette: Palette

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
                Label(mode.transformation, systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            QuietButton(title: "Edit", icon: "pencil", palette: palette)
            QuietButton(title: "Duplicate", icon: "plus.square.on.square", palette: palette)
        }
    }
}

private struct StackSystemRow: View {
    let selected: Bool
    let palette: Palette

    var body: some View {
        SelectionRow(
            icon: "waveform",
            title: "Voice to Text",
            detail: "Raw transcription — no Polish · permanent system selection",
            selected: selected,
            protected: true,
            palette: palette
        )
    }
}

private struct StackModeRow: View {
    let mode: PrototypeMode
    let expanded: Bool
    let unavailable: Bool
    let palette: Palette

    var body: some View {
        VStack(spacing: 0) {
            SelectionRow(
                icon: mode.icon,
                title: mode.name,
                detail: "\(mode.transformation) · \(mode.model)",
                selected: expanded,
                protected: false,
                palette: palette
            )
            if expanded {
                HStack(alignment: .top, spacing: 18) {
                    DetailField(
                        label: "POLISH INSTRUCTIONS",
                        value: mode.prompt,
                        mono: false,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 10) {
                        DetailField(
                            label: "PRESERVED VOCABULARY",
                            value: mode.vocabulary,
                            mono: true,
                            palette: palette
                        )
                        if unavailable {
                            UnavailableNotice(model: mode.model, palette: palette)
                        }
                    }
                    .frame(width: 250, alignment: .leading)
                    LibraryActions(palette: palette)
                        .frame(width: 230)
                }
                .padding(14)
                .background(palette.raised)
                .overlay(alignment: .leading) {
                    Rectangle().fill(palette.accent).frame(width: 2)
                }
            }
        }
    }
}

private struct DetailField: View {
    let label: String
    let value: String
    let mono: Bool
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(palette.tertiary)
            Text(value)
                .font(mono ? .system(size: 10.5, design: .monospaced) : .system(size: 12))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LibraryActions: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            QuietButton(title: "Up", icon: "arrow.up", palette: palette)
            QuietButton(title: "Down", icon: "arrow.down", palette: palette)
            Spacer()
            Text("Delete")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.error)
        }
    }
}

private struct UnavailableNotice: View {
    let model: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(model) isn't installed", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.warning)
            Text("Polish uses the raw transcript until the model is installed.")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
            Text("Open Models →")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .padding(10)
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.warning).frame(width: 2)
        }
    }
}

private struct EmptyLibrary: View {
    let compact: Bool
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: compact ? 18 : 24, weight: .medium))
                .foregroundStyle(palette.accent)
            Text("Build your first Polish workflow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
            Text("Add a Mode with its own model and writing instructions. Voice to Text remains available.")
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
            PrimaryButton(title: "Add Mode", icon: "plus", palette: palette)
        }
        .padding(compact ? 14 : 20)
        .frame(maxWidth: .infinity, minHeight: compact ? 150 : 230, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}

private struct EmptyRailSlot: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
            Text("Your first Mode")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(palette.tertiary)
        .frame(maxWidth: .infinity, minHeight: 92)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(palette.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}

private struct NoModeDetail: View {
    let palette: Palette
    let contrast: ContrastPreview

    var body: some View {
        Surface(contrast: contrast, palette: palette) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "cursorarrow.click")
                    .font(.system(size: 20))
                    .foregroundStyle(palette.tertiary)
                Text("Choose a Mode")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(
                    "Voice to Text is selected for the next Dictation session. "
                        + "Select a Mode to review or edit its Polish instructions."
                )
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        }
    }
}

private struct ModalScrim<Content: View>: View {
    let palette: Palette
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
            content()
        }
    }
}

private struct DeleteConfirmation: View {
    let palette: Palette
    let contrast: ContrastPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.error)
                Text("Delete Email?")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.text)
            }
            Text("Email will be removed from your Mode library and cycle order.")
                .font(.system(size: 12))
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 6) {
                Label("Saved History remains unchanged", systemImage: "clock")
                Label("qwen2.5:7b is not uninstalled", systemImage: "shippingbox")
                Label("Voice to Text becomes selected", systemImage: "waveform")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(palette.secondary)
            HStack {
                Spacer()
                QuietButton(title: "Cancel", icon: nil, palette: palette)
                Text("Delete Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(palette.error, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    contrast == .increased ? palette.borderStrong : palette.border,
                    lineWidth: contrast == .increased ? 2 : 1
                )
        }
        .overlay(alignment: .topLeading) {
            Rectangle().fill(palette.error).frame(width: 42, height: 2)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
    }
}

private struct ModeEditor: View {
    let scene: ModesScene
    let palette: Palette
    let contrast: ContrastPreview

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(palette: palette)
            Hairline(color: borderColor)
            HStack(alignment: .top, spacing: 0) {
                EditorIdentity(scene: scene, palette: palette)
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Hairline(color: borderColor, vertical: true)
                EditorInstructions(scene: scene, palette: palette)
                    .padding(22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Hairline(color: borderColor)
            EditorFooter(scene: scene, palette: palette)
        }
        .frame(width: 820, height: 570)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: contrast == .increased ? 2 : 1)
        }
        .overlay(alignment: .topLeading) {
            Rectangle().fill(palette.accent).frame(width: 56, height: 2)
        }
        .shadow(color: .black.opacity(0.48), radius: 34, y: 16)
        .overlay(alignment: .topLeading) {
            if scene == .icons {
                IconPalette(palette: palette)
                    .offset(x: 92, y: 198)
            }
        }
    }

    private var borderColor: Color {
        contrast == .increased ? palette.borderStrong : palette.border
    }
}

private struct EditorHeader: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Mode")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Changes affect future Dictation sessions after Save.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.secondary)
                .frame(width: 28, height: 28)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 22)
        .frame(height: 66)
    }
}

private struct EditorIdentity: View {
    let scene: ModesScene
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorHeading(
                title: "Identity",
                detail: "How this Mode appears across FoldWise",
                palette: palette
            )
            EditorField(
                label: "NAME",
                value: scene == .validation ? "" : "Email",
                error: scene == .validation ? "Enter a Mode name." : nil,
                palette: palette
            )
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("ICON", palette: palette)
                HStack {
                    Image(systemName: "envelope")
                    Text("Email")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(.system(size: 11))
                .foregroundStyle(palette.text)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(palette.raised)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            scene == .icons ? palette.accent : palette.border,
                            lineWidth: scene == .icons ? 2 : 1
                        )
                }
            }
            EditorField(
                label: "AI MODEL",
                value: scene == .validation ? "No installed models" : "qwen2.5:7b",
                error: scene == .validation ? "Choose an installed AI model." : nil,
                palette: palette
            )
            Spacer()
        }
    }
}

private struct EditorInstructions: View {
    let scene: ModesScene
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            EditorHeading(
                title: "Polish instructions",
                detail: "How the transcript should change",
                palette: palette
            )
            VStack(alignment: .leading, spacing: 6) {
                FieldLabel("TRANSFORMATION", palette: palette)
                HStack(spacing: 0) {
                    Segment(title: "Keep wording", selected: false, palette: palette)
                    Segment(title: "Reshape", selected: true, palette: palette)
                }
                .padding(2)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
                Text("May reorder and rephrase while preserving meaning.")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
            }
            EditorTextArea(
                label: "SYSTEM PROMPT",
                value: scene == .validation
                    ? ""
                    : "Turn the transcript into a concise, warm email with a clear next step.",
                height: 116,
                error: scene == .validation ? "Enter Polish instructions." : nil,
                palette: palette
            )
            EditorTextArea(
                label: "PRESERVED VOCABULARY · OPTIONAL",
                value: "Mateusz\nFoldWise\nSwiftUI",
                height: 70,
                error: nil,
                palette: palette
            )
            Text("One term per line. Empty and repeated terms are removed on Save.")
                .font(.system(size: 9.5))
                .foregroundStyle(palette.secondary)
        }
    }
}

private struct EditorFooter: View {
    let scene: ModesScene
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            if scene == .retry {
                Label(
                    "Couldn't save Email. The complete draft is still here.",
                    systemImage: "exclamationmark.octagon.fill"
                )
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.error)
            } else {
                Text("⌘↩ SAVE · ESC CANCEL")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(palette.tertiary)
            }
            Spacer()
            QuietButton(title: "Cancel", icon: nil, palette: palette)
            PrimaryButton(
                title: scene == .retry ? "Retry" : "Save",
                icon: scene == .retry ? "arrow.clockwise" : nil,
                palette: palette
            )
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
        .background(palette.raised)
    }
}

private struct EditorHeading: View {
    let title: String
    let detail: String
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.text)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
        }
    }
}

private struct EditorField: View {
    let label: String
    let value: String
    let error: String?
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label, palette: palette)
            Text(value.isEmpty ? "Mode name" : value)
                .font(.system(size: 11))
                .foregroundStyle(value.isEmpty ? palette.tertiary : palette.text)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(palette.raised)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(error == nil ? palette.border : palette.error, lineWidth: 1)
                }
            if let error {
                ValidationMessage(message: error, palette: palette)
            }
        }
    }
}

private struct EditorTextArea: View {
    let label: String
    let value: String
    let height: CGFloat
    let error: String?
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel(label, palette: palette)
            Text(value.isEmpty ? "Required instructions for Polish" : value)
                .font(.system(size: 10.5, design: label.contains("VOCABULARY") ? .monospaced : .default))
                .foregroundStyle(value.isEmpty ? palette.tertiary : palette.text)
                .padding(9)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                .background(palette.raised)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(error == nil ? palette.border : palette.error, lineWidth: 1)
                }
            if let error {
                ValidationMessage(message: error, palette: palette)
            }
        }
    }
}

private struct ValidationMessage: View {
    let message: String
    let palette: Palette

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(palette.error)
    }
}

private struct FieldLabel: View {
    let title: String
    let palette: Palette

    init(_ title: String, palette: Palette) {
        self.title = title
        self.palette = palette
    }

    var body: some View {
        Text(title)
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(palette.tertiary)
    }
}

private struct Segment: View {
    let title: String
    let selected: Bool
    let palette: Palette

    var body: some View {
        Text(title)
            .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? palette.text : palette.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .background(selected ? palette.hover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(alignment: .bottom) {
                if selected {
                    Rectangle().fill(palette.accent).frame(height: 2)
                }
            }
    }
}

private struct IconPalette: View {
    let palette: Palette

    private let icons = [
        ("wand.and.sparkles", "Magic"),
        ("envelope", "Email"),
        ("text.bubble", "Chat"),
        ("doc.text", "Document"),
        ("list.bullet", "List"),
        ("briefcase", "Work"),
        ("terminal", "Terminal"),
        ("pencil.and.outline", "Writing"),
        ("globe", "Language"),
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 7) {
            ForEach(icons, id: \.0) { icon in
                VStack(spacing: 5) {
                    Image(systemName: icon.0)
                        .font(.system(size: 15, weight: .medium))
                    Text(icon.1)
                        .font(.system(size: 9.5))
                }
                .foregroundStyle(icon.0 == "envelope" ? palette.accent : palette.text)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(icon.0 == "envelope" ? palette.raised : palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            icon.0 == "envelope" ? palette.accent : palette.border,
                            lineWidth: 1
                        )
                }
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }
}

private struct Surface<Content: View>: View {
    let contrast: ContrastPreview
    let palette: Palette
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
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
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(palette.tertiary)
    }
}

private struct PrimaryButton: View {
    let title: String
    let icon: String?
    let palette: Palette

    init(title: String, icon: String? = nil, palette: Palette) {
        self.title = title
        self.icon = icon
        self.palette = palette
    }

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(palette.accentText)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(palette.accent, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct QuietButton: View {
    let title: String
    let icon: String?
    let palette: Palette

    init(title: String, icon: String? = nil, palette: Palette) {
        self.title = title
        self.icon = icon
        self.palette = palette
    }

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
            }
            Text(title)
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(palette.text)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6).strokeBorder(palette.border, lineWidth: 1)
        }
    }
}

private struct ReviewBar: View {
    @Binding var variant: ModesVariant
    @Binding var appearance: PrototypeAppearance
    @Binding var scene: ModesScene
    @Binding var contrast: ContrastPreview

    var body: some View {
        HStack(spacing: 9) {
            Button { cycle(-1) } label: {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            Text("\(variant.key) — \(variant.rawValue)")
                .font(.system(size: 11, weight: .semibold))
                .frame(minWidth: 132)

            Button { cycle(1) } label: {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Divider().frame(height: 18)
            Picker("Scene", selection: $scene) {
                ForEach(ModesScene.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .frame(width: 176)
            reviewPicker(selection: $appearance, width: 108)
            reviewPicker(selection: $contrast, width: 146)
            Text("⌘← / ⌘→ variants")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.62))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(Color.black.opacity(0.95), in: RoundedRectangle(cornerRadius: 11))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .environment(\.colorScheme, .dark)
    }

    private func reviewPicker<T: Hashable & Identifiable & CaseIterable & RawRepresentable>(
        selection: Binding<T>,
        width: CGFloat
    ) -> some View where T.AllCases: RandomAccessCollection, T.RawValue == String {
        Picker("", selection: selection) {
            ForEach(Array(T.allCases)) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    private func cycle(_ offset: Int) {
        let variants = ModesVariant.allCases
        guard let index = variants.firstIndex(of: variant) else { return }
        variant = variants[(index + offset + variants.count) % variants.count]
    }
}

private struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color(hex: 0xFF5F57))
            Circle().fill(Color(hex: 0xFEBC2E))
            Circle().fill(Color(hex: 0x28C840))
        }
        .frame(width: 42, height: 11)
    }
}

private struct SidebarToggleGlyph: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5)
            .strokeBorder(color, lineWidth: 1.2)
            .frame(width: 18, height: 14)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .frame(width: 1)
                    .padding(.vertical, 1.5)
                    .offset(x: 5)
            }
    }
}

private struct WaveMark: View {
    let color: Color
    private let heights: [CGFloat] = [5, 11, 17, 9, 15, 7, 12]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { item in
                Capsule().fill(color).frame(width: 2, height: item.element)
            }
        }
    }
}

private struct Hairline: View {
    let color: Color
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

private func summary(_ mode: PrototypeMode, scene: ModesScene) -> String {
    if scene == .unavailable, mode.id == "email" {
        return "Unavailable model"
    }
    return "\(mode.transformation) · \(mode.model)"
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
