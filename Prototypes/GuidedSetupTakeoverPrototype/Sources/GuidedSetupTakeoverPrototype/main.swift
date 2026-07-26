import AppKit
import SwiftUI

// Three variants of the Guided setup main-window takeover, switchable from
// the fixed bottom prototype bar. PROTOTYPE — throw away after issue #333.

private enum Palette {
    static let canvas = Color(red: 7 / 255, green: 9 / 255, blue: 11 / 255)
    static let navigation = Color(red: 9 / 255, green: 11 / 255, blue: 14 / 255)
    static let surface = Color(red: 13 / 255, green: 16 / 255, blue: 19 / 255)
    static let raised = Color(red: 19 / 255, green: 23 / 255, blue: 27 / 255)
    static let border = Color(red: 38 / 255, green: 44 / 255, blue: 50 / 255)
    static let primary = Color(red: 244 / 255, green: 245 / 255, blue: 246 / 255)
    static let secondary = Color(red: 164 / 255, green: 170 / 255, blue: 176 / 255)
    static let tertiary = Color(red: 116 / 255, green: 124 / 255, blue: 133 / 255)
    static let accent = Color(red: 1, green: 106 / 255, blue: 26 / 255)
    static let success = Color(red: 67 / 255, green: 209 / 255, blue: 122 / 255)
    static let warning = Color(red: 240 / 255, green: 180 / 255, blue: 75 / 255)
}

private enum Variant: String, CaseIterable, Identifiable {
    case shell
    case rail
    case root

    var id: String {
        rawValue
    }

    var key: String {
        switch self {
        case .shell: "A"
        case .rail: "B"
        case .root: "C"
        }
    }

    var name: String {
        switch self {
        case .shell: "Shell takeover"
        case .rail: "Setup rail"
        case .root: "Separate root"
        }
    }

    var representation: String {
        switch self {
        case .shell:
            "A state above SettingsModel.Pane; SettingsView switches its root content."
        case .rail:
            "A setup-only navigation system beside the step; app panes stay intact but hidden."
        case .root:
            "SettingsController swaps the hosting controller to a dedicated GuidedSetupRoot."
        }
    }

    var badgeVisibleDuringSetup: Bool {
        switch self {
        case .shell, .rail: true
        case .root: false
        }
    }
}

private enum SetupStep: String, CaseIterable {
    case accessibility = "Accessibility"
    case speechModel = "Speech model"
    case microphone = "Microphone"
    case shortcut = "Push-to-Talk shortcut"
    case polish = "Polish"

    var symbol: String {
        switch self {
        case .accessibility: "hand.raised"
        case .speechModel: "waveform.badge.magnifyingglass"
        case .microphone: "mic"
        case .shortcut: "option"
        case .polish: "sparkles"
        }
    }
}

private enum TakeoverOutcome: String {
    case active = "Active"
    case completed = "Setup completed"
    case skipped = "Setup skipped"
}

@MainActor
private final class PrototypeModel: ObservableObject {
    @Published var variant: Variant = .shell
    @Published var stepIndex = 0
    @Published var outcome: TakeoverOutcome = .active
    @Published var windowVisible = true
    @Published var recoveryRequestSuppressed = false
    @Published var permissionGuidePresented = false
    @Published var event = "First launch opened Guided setup."

    var currentStep: SetupStep {
        SetupStep.allCases[min(stepIndex, SetupStep.allCases.count - 1)]
    }

    var setupActive: Bool {
        outcome == .active
    }

    var badgeVisible: Bool {
        !setupActive || variant.badgeVisibleDuringSetup
    }

    var activationPolicy: String {
        windowVisible ? ".regular" : ".accessory"
    }

    func select(_ newVariant: Variant) {
        variant = newVariant
        reset()
        event = "Switched to \(newVariant.key) — \(newVariant.name)."
    }

    func cycle(_ offset: Int) {
        let variants = Variant.allCases
        guard let index = variants.firstIndex(of: variant) else { return }
        let next = (index + offset + variants.count) % variants.count
        select(variants[next])
    }

    func advance() {
        guard setupActive else { return }
        if stepIndex < SetupStep.allCases.count - 1 {
            stepIndex += 1
            event = "Advanced to \(currentStep.rawValue)."
        } else {
            finish()
        }
    }

    func back() {
        guard setupActive, stepIndex > 0 else { return }
        stepIndex -= 1
        event = "Returned to \(currentStep.rawValue)."
    }

    func triggerPermissionRecovery() {
        if setupActive {
            recoveryRequestSuppressed = true
            permissionGuidePresented = false
            event = "Recovery show() was suppressed; Guided setup keeps ownership "
                + "and refreshes permission state inline."
        } else {
            permissionGuidePresented = true
            event = "Returning-user Permission recovery guide presented."
        }
    }

    func closeWindow() {
        windowVisible = false
        if setupActive {
            outcome = .skipped
            event = "Window close committed the terminal Setup skipped outcome, then restored .accessory."
        } else {
            event = "Window closed; app returned to menu-bar-only mode."
        }
    }

    func reopenWindow() {
        windowVisible = true
        event = setupActive
            ? "Main window reopened into Guided setup."
            : "Main window reopened to Home."
    }

    func finish() {
        outcome = .completed
        stepIndex = SetupStep.allCases.count - 1
        recoveryRequestSuppressed = false
        event = "Released the main window to Home; sidebar and its toggle are available again."
    }

    func runAgain() {
        outcome = .active
        stepIndex = 0
        windowVisible = true
        recoveryRequestSuppressed = false
        permissionGuidePresented = false
        event = "Run setup again entered the same takeover from live configuration."
    }

    func reset() {
        stepIndex = 0
        outcome = .active
        windowVisible = true
        recoveryRequestSuppressed = false
        permissionGuidePresented = false
    }
}

@main
private struct GuidedSetupTakeoverPrototypeApp: App {
    @StateObject private var model = PrototypeModel()

    var body: some Scene {
        WindowGroup("FoldWise Voice — Guided setup prototype") {
            PrototypeHost(model: model)
                .frame(minWidth: 880, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 980, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}

private struct PrototypeHost: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if !model.windowVisible {
                    ClosedWindowState(model: model)
                } else if model.setupActive {
                    switch model.variant {
                    case .shell:
                        ShellTakeover(model: model)
                    case .rail:
                        SetupRailTakeover(model: model)
                    case .root:
                        SeparateRootTakeover(model: model)
                    }
                } else {
                    ReleasedHome(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            PrototypeSwitcher(model: model)
                .padding(.bottom, 14)
        }
        .background(Palette.canvas)
        .foregroundStyle(Palette.primary)
        .overlay(alignment: .topTrailing) {
            StateInspector(model: model)
                .padding(.top, 52)
                .padding(.trailing, 16)
        }
        .overlay(alignment: .topTrailing) {
            if model.badgeVisible {
                BadgePreview()
                    .offset(x: -24, y: -31)
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            model.cycle(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            model.cycle(1)
            return .handled
        }
    }
}

private struct ProductionTitlebar: View {
    let showsSidebarToggle: Bool

    var body: some View {
        HStack(spacing: 12) {
            Color.clear.frame(width: 70)
            if showsSidebarToggle {
                Image(systemName: "sidebar.left")
                    .foregroundStyle(Palette.tertiary)
            }
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.leading, showsSidebarToggle ? 10 : 0)
            HStack(spacing: 0) {
                Text("FoldWise").foregroundStyle(Palette.accent)
                Text(" Voice").foregroundStyle(Palette.primary)
            }
            .font(.system(size: 12.5, weight: .semibold))
            Spacer()
        }
        .frame(height: 52)
        .background(Palette.navigation)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.border).frame(height: 1)
        }
    }
}

private struct ShellTakeover: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 0) {
            ProductionTitlebar(showsSidebarToggle: false)
            ZStack {
                Palette.canvas
                VStack(alignment: .leading, spacing: 28) {
                    SetupEyebrow(model: model, treatment: "WINDOW-ROOT STATE")
                    StepHero(model: model)
                        .frame(maxWidth: 560)
                    SetupActions(model: model)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 64)
                .padding(.vertical, 48)
            }
        }
    }
}

private struct SetupRailTakeover: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 0) {
            ProductionTitlebar(showsSidebarToggle: false)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GUIDED SETUP")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(Palette.secondary)
                        .padding(.bottom, 8)
                    ForEach(Array(SetupStep.allCases.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 9) {
                            Image(systemName: index < model.stepIndex ? "checkmark" : step.symbol)
                                .frame(width: 18)
                                .foregroundStyle(index == model.stepIndex ? Palette.accent : Palette.tertiary)
                            Text(step.rawValue)
                                .font(.system(size: 13, weight: index == model.stepIndex ? .semibold : .regular))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(index == model.stepIndex ? Palette.raised : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                    Text("App destinations return when setup releases the window.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
                .padding(16)
                .frame(width: 220)
                .background(Palette.navigation)
                Rectangle().fill(Palette.border).frame(width: 1)
                VStack(alignment: .leading, spacing: 28) {
                    SetupEyebrow(model: model, treatment: "SETUP-ONLY NAVIGATION")
                    StepHero(model: model)
                        .frame(maxWidth: 560)
                    SetupActions(model: model)
                    Spacer()
                }
                .padding(.horizontal, 52)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.canvas)
            }
        }
    }
}

private struct SeparateRootTakeover: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Color.clear.frame(width: 70)
                Text("GUIDED SETUP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(Palette.tertiary)
                Spacer()
                Text("\(model.stepIndex + 1) / \(SetupStep.allCases.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.secondary)
                    .padding(.trailing, 18)
            }
            .frame(height: 52)
            .background(Palette.canvas)
            ZStack {
                Palette.canvas
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Palette.border, lineWidth: 1)
                    }
                    .frame(maxWidth: 680, maxHeight: 430)
                VStack(alignment: .leading, spacing: 30) {
                    HStack(spacing: 9) {
                        Image(systemName: "waveform").foregroundStyle(Palette.accent)
                        Text("FoldWise Voice")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    StepHero(model: model)
                    SetupActions(model: model)
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(56)
            }
        }
    }
}

private struct SetupEyebrow: View {
    @ObservedObject var model: PrototypeModel
    let treatment: String

    var body: some View {
        HStack(spacing: 10) {
            Text(treatment)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.tertiary)
            Rectangle().fill(Palette.border).frame(height: 1)
            Text("\(model.stepIndex + 1) / \(SetupStep.allCases.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.secondary)
        }
    }
}

private struct StepHero: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: model.currentStep.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Palette.accent)
            Text(model.currentStep.rawValue)
                .font(.system(size: 30, weight: .semibold))
            Text(stepDetail)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(4)
            if model.recoveryRequestSuppressed {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Palette.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Permission state refreshed here")
                            .font(.system(size: 13, weight: .semibold))
                        Text("The returning-user guide did not compete with Guided setup.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .padding(14)
                .background(Palette.surface)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Palette.warning).frame(width: 3)
                }
            }
        }
    }

    private var stepDetail: String {
        switch model.currentStep {
        case .accessibility:
            "Choose how completed text reaches other apps. Guided setup owns "
                + "this permission state while the takeover is active."
        case .speechModel:
            "Prepare the on-device speech model. Progress can continue while you visit later Setup steps."
        case .microphone:
            "Allow FoldWise to hear you. This is the only hard gate in Guided setup."
        case .shortcut:
            "Keep Right Option or capture a different valid Push-to-Talk shortcut."
        case .polish:
            "Keep complete Voice to Text, or opt into local rewriting through Ollama."
        }
    }
}

private struct SetupActions: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button("Back") { model.back() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(model.stepIndex == 0)
                Button(model.stepIndex == SetupStep.allCases.count - 1 ? "Finish" : "Continue") {
                    model.advance()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            HStack(spacing: 16) {
                Button("Trigger permission-recovery request") {
                    model.triggerPermissionRecovery()
                }
                Button("Close main window") {
                    model.closeWindow()
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
    }
}

private struct ReleasedHome: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 0) {
            ProductionTitlebar(showsSidebarToggle: true)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["Home", "Modes", "Models", "History", "Stats", "Settings"], id: \.self) { pane in
                        HStack {
                            Image(systemName: pane == "Home" ? "house" : "circle")
                                .frame(width: 18)
                            Text(pane)
                            Spacer()
                            if pane == "Home" {
                                Image(systemName: "checkmark")
                            }
                        }
                        .foregroundStyle(pane == "Home" ? Palette.primary : Palette.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(pane == "Home" ? Palette.raised : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer()
                }
                .padding(16)
                .frame(width: 190)
                .background(Palette.navigation)
                Rectangle().fill(Palette.border).frame(width: 1)
                VStack(alignment: .leading, spacing: 20) {
                    Text("Home")
                        .font(.system(size: 30, weight: .semibold))
                    HStack(spacing: 10) {
                        Image(systemName: model.outcome == .completed ? "checkmark.circle" : "minus.circle")
                            .foregroundStyle(model.outcome == .completed ? Palette.success : Palette.warning)
                        Text(model.outcome.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(
                        "Guided setup released the existing main-window shell. "
                            + "There is no separate summary destination."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
                    Button("Run setup again") { model.runAgain() }
                        .buttonStyle(QuietButtonStyle())
                    Button("Trigger returning-user permission recovery") {
                        model.triggerPermissionRecovery()
                    }
                    .buttonStyle(.link)
                    Spacer()
                }
                .padding(48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: Binding(
            get: { model.permissionGuidePresented },
            set: { model.permissionGuidePresented = $0 }
        )) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Permission recovery guide")
                    .font(.system(size: 22, weight: .semibold))
                Text("This sheet exists only after Guided setup has released the window.")
                    .foregroundStyle(Palette.secondary)
                Button("Done") { model.permissionGuidePresented = false }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(36)
            .frame(width: 460, height: 220)
            .background(Palette.canvas)
        }
    }
}

private struct ClosedWindowState: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(Palette.tertiary)
            Text("Main window is closed")
                .font(.system(size: 24, weight: .semibold))
            Text("The real app would now be menu-bar-only with activation policy .accessory.")
                .foregroundStyle(Palette.secondary)
            Text(model.outcome.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(model.outcome == .skipped ? Palette.warning : Palette.success)
            Button("Reopen main window") { model.reopenWindow() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }
}

private struct StateInspector: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("MECHANICS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.tertiary)
            fact("Representation", model.variant.name)
            fact("Activation", model.activationPolicy)
            fact("Window", model.windowVisible ? "shown" : "closed")
            fact("App sidebar", model.setupActive ? "unreachable" : "available")
            fact("Badge", model.badgeVisible ? "visible" : "hidden")
            fact("Outcome", model.outcome.rawValue)
            Divider().overlay(Palette.border)
            Text(model.variant.representation)
                .font(.system(size: 10))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.event)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 250, alignment: .leading)
        .background(Palette.surface.opacity(0.96))
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Palette.tertiary)
            Spacer()
            Text(value).foregroundStyle(Palette.primary)
        }
        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
    }
}

private struct BadgePreview: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text("Voice to Text")
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(Palette.surface)
        .overlay {
            Capsule().stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(Capsule())
    }
}

private struct PrototypeSwitcher: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        HStack(spacing: 10) {
            Button { model.cycle(-1) } label: {
                Image(systemName: "arrow.left")
            }
            Text("\(model.variant.key) — \(model.variant.name)")
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 150)
            Button { model.cycle(1) } label: {
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(configuration.isPressed ? Palette.accent.opacity(0.8) : Palette.accent)
            .foregroundStyle(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(configuration.isPressed ? Palette.raised : Palette.surface)
            .foregroundStyle(Palette.primary)
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
