import AppKit
import SwiftUI

// The accepted shell-takeover direction for Guided setup.
// PROTOTYPE — throw away after issue #333.

private enum Palette {
    static let canvas = Color(red: 7 / 255, green: 9 / 255, blue: 11 / 255)
    static let navigation = Color(red: 9 / 255, green: 11 / 255, blue: 14 / 255)
    static let surface = Color(red: 13 / 255, green: 16 / 255, blue: 19 / 255)
    static let raised = Color(red: 19 / 255, green: 23 / 255, blue: 27 / 255)
    static let hover = Color(red: 26 / 255, green: 32 / 255, blue: 38 / 255)
    static let border = Color(red: 38 / 255, green: 44 / 255, blue: 50 / 255)
    static let primary = Color(red: 244 / 255, green: 245 / 255, blue: 246 / 255)
    static let secondary = Color(red: 164 / 255, green: 170 / 255, blue: 176 / 255)
    static let tertiary = Color(red: 116 / 255, green: 124 / 255, blue: 133 / 255)
    static let accent = Color(red: 1, green: 106 / 255, blue: 26 / 255)
    static let success = Color(red: 67 / 255, green: 209 / 255, blue: 122 / 255)
    static let warning = Color(red: 240 / 255, green: 180 / 255, blue: 75 / 255)
}

private enum SetupStep: String, CaseIterable, Identifiable {
    case accessibility = "Accessibility"
    case speechModel = "Speech model"
    case microphone = "Microphone"
    case shortcut = "Push-to-Talk shortcut"
    case polish = "Polish"

    var id: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .accessibility: "hand.raised"
        case .speechModel: "waveform.badge.magnifyingglass"
        case .microphone: "mic"
        case .shortcut: "option"
        case .polish: "sparkles"
        }
    }

    var title: String {
        switch self {
        case .accessibility: "Choose how text reaches your apps"
        case .speechModel: "Prepare on-device transcription"
        case .microphone: "Let FoldWise hear you"
        case .shortcut: "Choose how recording starts"
        case .polish: "Choose whether FoldWise rewrites"
        }
    }

    var summary: String {
        switch self {
        case .accessibility:
            "FoldWise can paste automatically, use a narrower shortcut permission, "
                + "or work entirely from the Badge and clipboard."
        case .speechModel:
            "Speech stays on this Mac. FoldWise needs one local model before it "
                + "can turn your voice into text."
        case .microphone:
            "Microphone access is the only required permission. Without it, "
                + "FoldWise cannot record a Dictation session."
        case .shortcut:
            "Hold the shortcut while speaking, then release it to transcribe "
                + "and insert the result."
        case .polish:
            "Voice to Text is complete without an LLM. Polish is an optional "
                + "local rewrite for Modes such as Email and Bullets."
        }
    }
}

private enum InsertionChoice: String {
    case automatic
    case shortcutFallback
    case badgeOnly
}

private enum ShortcutChoice: String {
    case rightOption
    case custom
}

private enum PolishChoice: String {
    case voiceToText
    case polish
}

private enum TakeoverOutcome: String {
    case active = "Active"
    case completed = "Setup completed"
    case skipped = "Setup skipped"
}

@MainActor
private final class PrototypeModel: ObservableObject {
    @Published var stepIndex = 0
    @Published var outcome: TakeoverOutcome = .active
    @Published var windowVisible = true
    @Published var recoveryRequestSuppressed = false
    @Published var permissionGuidePresented = false
    @Published var insertionChoice: InsertionChoice?
    @Published var speechDownloadStarted = false
    @Published var speechDownloadProgress = 0.0
    @Published var microphoneGranted = false
    @Published var shortcutChoice: ShortcutChoice?
    @Published var polishChoice: PolishChoice?
    @Published var badgeVisibleDuringSetup = true
    @Published var confirmsBeforeClose = true
    @Published var closeConfirmationPresented = false
    @Published var transitionDirection = 1
    @Published var event = "First launch opened Guided setup."

    var currentStep: SetupStep {
        SetupStep.allCases[min(stepIndex, SetupStep.allCases.count - 1)]
    }

    var setupActive: Bool {
        outcome == .active
    }

    var badgeVisible: Bool {
        !setupActive || badgeVisibleDuringSetup
    }

    var activationPolicy: String {
        windowVisible ? ".regular" : ".accessory"
    }

    var currentStepSatisfied: Bool {
        switch currentStep {
        case .accessibility: insertionChoice != nil
        case .speechModel: speechDownloadStarted
        case .microphone: microphoneGranted
        case .shortcut: shortcutChoice != nil
        case .polish: polishChoice != nil
        }
    }

    func advance(reduceMotion: Bool) {
        guard setupActive, currentStepSatisfied else { return }
        guard stepIndex < SetupStep.allCases.count - 1 else {
            finish()
            return
        }
        transitionDirection = 1
        animate(reduceMotion: reduceMotion) {
            self.stepIndex += 1
        }
        event = "Advanced to \(currentStep.rawValue)."
    }

    func back(reduceMotion: Bool) {
        guard setupActive, stepIndex > 0 else { return }
        transitionDirection = -1
        animate(reduceMotion: reduceMotion) {
            self.stepIndex -= 1
        }
        event = "Returned to \(currentStep.rawValue)."
    }

    func startSpeechDownload() {
        speechDownloadStarted = true
        speechDownloadProgress = 0.18
        event = "Started the Parakeet download; it may continue behind later Setup steps."
    }

    func tickSpeechDownload() {
        guard speechDownloadStarted else { return }
        speechDownloadProgress = min(speechDownloadProgress + 0.21, 1)
        event = speechDownloadProgress == 1
            ? "Speech model is ready."
            : "Speech-model progress updated in the window corner."
    }

    func triggerPermissionRecovery() {
        if setupActive {
            recoveryRequestSuppressed = true
            permissionGuidePresented = false
            event = "Recovery presentation was suppressed; Guided setup refreshed permission state inline."
        } else {
            permissionGuidePresented = true
            event = "Returning-user Permission recovery guide presented."
        }
    }

    func requestClose() {
        if setupActive, confirmsBeforeClose {
            closeConfirmationPresented = true
            event = "Close requested; confirmation keeps the outcome explicit."
        } else {
            commitClose()
        }
    }

    func commitClose() {
        closeConfirmationPresented = false
        windowVisible = false
        if setupActive {
            outcome = .skipped
            event = "Window close committed Setup skipped and restored .accessory."
        } else {
            event = "Window closed; app returned to menu-bar-only mode."
        }
    }

    func reopenWindow() {
        windowVisible = true
        event = setupActive ? "Reopened into Guided setup." : "Reopened to Home."
    }

    func finish() {
        outcome = .completed
        recoveryRequestSuppressed = false
        event = "Released the existing main-window shell to Home."
    }

    func runAgain() {
        stepIndex = 0
        outcome = .active
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
        insertionChoice = nil
        speechDownloadStarted = false
        speechDownloadProgress = 0
        microphoneGranted = false
        shortcutChoice = nil
        polishChoice = nil
        closeConfirmationPresented = false
        event = "Prototype reset to a fresh first launch."
    }

    private func animate(reduceMotion: Bool, changes: @escaping () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(.easeInOut(duration: 0.28), changes)
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !model.windowVisible {
                ClosedWindowState(model: model)
            } else if model.setupActive {
                ShellTakeover(model: model, reduceMotion: reduceMotion)
            } else {
                ReleasedHome(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .foregroundStyle(Palette.primary)
        .overlay(alignment: .topTrailing) {
            PrototypeInspector(model: model)
                .padding(.top, 64)
                .padding(.trailing, 16)
        }
        .overlay(alignment: .topTrailing) {
            if model.badgeVisible {
                BadgePreview()
                    .offset(x: -24, y: -31)
            }
        }
        .alert("Skip Guided setup?", isPresented: $model.closeConfirmationPresented) {
            Button("Keep setting up", role: .cancel) {}
            Button("Skip setup", role: .destructive) { model.commitClose() }
        } message: {
            Text("You can run setup again later from Settings.")
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
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            ProductionTitlebar(showsSidebarToggle: false)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    StepProgress(model: model)
                    ZStack(alignment: .topLeading) {
                        StepContent(model: model)
                            .id(model.currentStep)
                            .transition(stepTransition)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    StepNavigation(model: model, reduceMotion: reduceMotion)
                }
                .padding(.leading, 56)
                .padding(.trailing, 300)
                .padding(.top, 34)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Palette.canvas)
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        let insertionEdge: Edge = model.transitionDirection > 0 ? .trailing : .leading
        let removalEdge: Edge = model.transitionDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }
}

private struct StepProgress: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(index <= model.stepIndex ? Palette.accent : Palette.raised)
                            .frame(width: 22, height: 22)
                        if index < model.stepIndex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.black)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(index == model.stepIndex ? Color.black : Palette.tertiary)
                        }
                    }
                    if index == model.stepIndex {
                        Text(step.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                if index < SetupStep.allCases.count - 1 {
                    Rectangle()
                        .fill(index < model.stepIndex ? Palette.accent : Palette.border)
                        .frame(maxWidth: 34)
                        .frame(height: 1)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.stepIndex)
    }
}

private struct StepContent: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: model.currentStep.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("SETUP STEP \(model.stepIndex + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Palette.tertiary)
            }
            Text(model.currentStep.title)
                .font(.system(size: 30, weight: .semibold))
            Text(model.currentStep.summary)
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(4)
                .frame(maxWidth: 560, alignment: .leading)
            detail
                .frame(maxWidth: 590, alignment: .leading)
            if model.recoveryRequestSuppressed {
                StatusNotice(
                    title: "Permission state refreshed here",
                    detail: "The returning-user guide did not compete with Guided setup."
                )
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.currentStep {
        case .accessibility:
            AccessibilityDetail(model: model)
        case .speechModel:
            SpeechModelDetail(model: model)
        case .microphone:
            MicrophoneDetail(model: model)
        case .shortcut:
            ShortcutDetail(model: model)
        case .polish:
            PolishDetail(model: model)
        }
    }
}

private struct AccessibilityDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 10) {
            ChoiceRow(
                selected: model.insertionChoice == .automatic,
                symbol: "arrow.down.doc",
                title: "Paste automatically",
                detail: "Accessibility lets FoldWise paste into the app you were using. "
                    + "It also supports the global shortcut."
            ) {
                model.insertionChoice = .automatic
            }
            ChoiceRow(
                selected: model.insertionChoice == .shortcutFallback,
                symbol: "keyboard",
                title: "Use the narrower shortcut fallback",
                detail: "Input Monitoring keeps the global shortcut; completed text "
                    + "stays on the clipboard for you to paste."
            ) {
                model.insertionChoice = .shortcutFallback
            }
            ChoiceRow(
                selected: model.insertionChoice == .badgeOnly,
                symbol: "capsule",
                title: "Use the Badge and clipboard",
                detail: "Decline both permissions. Start from the Badge and paste "
                    + "completed text from the clipboard."
            ) {
                model.insertionChoice = .badgeOnly
            }
        }
    }
}

private struct SpeechModelDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FactSurface(
                facts: [
                    ("MODEL", "Parakeet TDT v3"),
                    ("DOWNLOAD", "About 600 MB"),
                    ("RUNS ON", "Apple Neural Engine"),
                    ("REQUIRED FOR", "Turning speech into text"),
                ]
            )
            if model.speechDownloadStarted {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(model.speechDownloadProgress == 1 ? "Ready" : "Downloading in background")
                        Spacer()
                        Text("\(Int(model.speechDownloadProgress * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    ProgressView(value: model.speechDownloadProgress)
                        .tint(model.speechDownloadProgress == 1 ? Palette.success : Palette.accent)
                    Text("You may continue. Dictation becomes ready only after the model is complete.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondary)
                }
            } else {
                Button("Start 600 MB download") { model.startSpeechDownload() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

private struct MicrophoneDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FactSurface(
                facts: [
                    ("WHY", "Capture your voice for Dictation"),
                    ("DATA", "Audio is processed on this Mac"),
                    ("GATE", "Required before setup can continue"),
                ]
            )
            Button(model.microphoneGranted ? "Microphone allowed" : "Allow microphone") {
                model.microphoneGranted = true
                model.event = "Microphone authorization observed; the hard gate is satisfied."
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(model.microphoneGranted)
        }
    }
}

private struct ShortcutDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 10) {
            ChoiceRow(
                selected: model.shortcutChoice == .rightOption,
                symbol: "option",
                title: "Keep Right Option",
                detail: "Hold Right Option while speaking and release it when finished. "
                    + "This valid default works immediately."
            ) {
                model.shortcutChoice = .rightOption
            }
            ChoiceRow(
                selected: model.shortcutChoice == .custom,
                symbol: "keyboard.badge.ellipsis",
                title: "Choose another shortcut",
                detail: "Capture a different key that does not collide with Toggle "
                    + "Recording or Mode cycle."
            ) {
                model.shortcutChoice = .custom
            }
        }
    }
}

private struct PolishDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(spacing: 10) {
            ChoiceRow(
                selected: model.polishChoice == .voiceToText,
                symbol: "text.quote",
                title: "Keep Voice to Text",
                detail: "Insert the raw transcript. No LLM, extra app, or additional "
                    + "model download is required."
            ) {
                model.polishChoice = .voiceToText
            }
            ChoiceRow(
                selected: model.polishChoice == .polish,
                symbol: "sparkles",
                title: "Set up Polish",
                detail: "Install and start Ollama, then download qwen2.5:3b "
                    + "(about 1.9 GB) for local Mode-based rewriting."
            ) {
                model.polishChoice = .polish
            }
        }
    }
}

private struct StepNavigation: View {
    @ObservedObject var model: PrototypeModel
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 10) {
            if model.stepIndex > 0 {
                Button("Back") { model.back(reduceMotion: reduceMotion) }
                    .buttonStyle(QuietButtonStyle())
                    .transition(.opacity)
            }
            Button(model.stepIndex == SetupStep.allCases.count - 1 ? "Finish setup" : "Continue") {
                model.advance(reduceMotion: reduceMotion)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.currentStepSatisfied)
            Spacer()
        }
        .animation(.easeOut(duration: 0.16), value: model.stepIndex)
    }
}

private struct ChoiceRow: View {
    let selected: Bool
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Palette.accent : Palette.tertiary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Palette.accent : Palette.tertiary)
            }
            .padding(14)
            .background(selected ? Palette.raised : Palette.surface)
            .overlay(alignment: .leading) {
                if selected {
                    Rectangle().fill(Palette.accent).frame(width: 2)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FactSurface: View {
    let facts: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                HStack {
                    Text(fact.0)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Palette.tertiary)
                    Spacer()
                    Text(fact.1)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                if index < facts.count - 1 {
                    Rectangle().fill(Palette.border).frame(height: 1)
                }
            }
        }
        .background(Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusNotice: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Palette.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
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

private struct PrototypeInspector: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROTOTYPE CONTROLS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(Palette.tertiary)
            fact("Representation", "Shell takeover")
            fact("Activation", model.activationPolicy)
            fact("App sidebar", model.setupActive ? "unreachable" : "available")
            fact("Outcome", model.outcome.rawValue)
            Toggle("Show Badge during setup", isOn: $model.badgeVisibleDuringSetup)
                .toggleStyle(.switch)
                .font(.system(size: 11))
            Toggle("Confirm before close", isOn: $model.confirmsBeforeClose)
                .toggleStyle(.switch)
                .font(.system(size: 11))
            if model.speechDownloadStarted, model.speechDownloadProgress < 1 {
                Button("Advance model download") { model.tickSpeechDownload() }
                    .buttonStyle(InspectorButtonStyle())
            }
            Button("Trigger permission recovery") { model.triggerPermissionRecovery() }
                .buttonStyle(InspectorButtonStyle())
            Button("Simulate main-window close") { model.requestClose() }
                .buttonStyle(InspectorButtonStyle())
            Button("Reset prototype") { model.reset() }
                .buttonStyle(InspectorButtonStyle())
            Text(model.event)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(Palette.surface.opacity(0.98))
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
                    Text("Home").font(.system(size: 30, weight: .semibold))
                    HStack(spacing: 10) {
                        Image(systemName: model.outcome == .completed ? "checkmark.circle" : "minus.circle")
                            .foregroundStyle(model.outcome == .completed ? Palette.success : Palette.warning)
                        Text(model.outcome.rawValue)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Guided setup released the existing main-window shell.")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.secondary)
                    Button("Run setup again") { model.runAgain() }
                        .buttonStyle(QuietButtonStyle())
                    Button("Open Permission recovery guide") {
                        model.triggerPermissionRecovery()
                    }
                    .buttonStyle(QuietButtonStyle())
                    Spacer()
                }
                .padding(48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $model.permissionGuidePresented) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Permission recovery guide")
                    .font(.system(size: 22, weight: .semibold))
                Text("This sheet exists only after Guided setup releases the window.")
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
            Text("The app is menu-bar-only again with activation policy .accessory.")
                .foregroundStyle(Palette.secondary)
            Text(model.outcome.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(model.outcome == .skipped ? Palette.warning : Palette.success)
            Button("Reopen main window") { model.reopenWindow() }
                .buttonStyle(PrimaryButtonStyle())
        }
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

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(isEnabled ? Palette.accent : Palette.raised)
            .foregroundStyle(isEnabled ? Color.black : Palette.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(configuration.isPressed ? Palette.hover : Palette.surface)
            .foregroundStyle(isEnabled ? Palette.primary : Palette.tertiary)
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct InspectorButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(configuration.isPressed ? Palette.hover : Palette.raised)
            .foregroundStyle(Palette.secondary)
            .overlay {
                RoundedRectangle(cornerRadius: 5).stroke(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
