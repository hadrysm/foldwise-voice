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

private enum PolishChoice: String {
    case voiceToText
    case polish
}

private enum OllamaSetupPhase: String {
    case notDetected
    case runningWithoutModel
    case pullingModel
    case ready
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
    @Published var shortcutLabel: String?
    @Published var isCapturingShortcut = false
    @Published var polishChoice: PolishChoice?
    @Published var ollamaPhase = OllamaSetupPhase.notDetected
    @Published var polishPullProgress = 0.0
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
        !setupActive
    }

    var activationPolicy: String {
        windowVisible ? ".regular" : ".accessory"
    }

    var currentStepSatisfied: Bool {
        switch currentStep {
        case .accessibility: insertionChoice != nil
        case .speechModel: speechDownloadStarted
        case .microphone: microphoneGranted
        case .shortcut: shortcutLabel != nil
        case .polish:
            polishChoice == .voiceToText
                || (polishChoice == .polish && ollamaPhase == .ready)
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

    func beginShortcutCapture() {
        isCapturingShortcut = true
        shortcutLabel = nil
        event = "Waiting for an explicit shortcut key."
    }

    func commitShortcut(_ label: String) {
        shortcutLabel = label
        isCapturingShortcut = false
        event = "Captured \(label) as Push to Talk."
    }

    func chooseVoiceToText() {
        polishChoice = .voiceToText
        event = "Voice to Text selected; no LLM setup is required."
    }

    func choosePolish() {
        polishChoice = .polish
        event = "Polish selected; checking the local Ollama dependency."
    }

    func retryOllamaProbe() {
        ollamaPhase = .runningWithoutModel
        event = "Ollama responded; no compatible Polish model is present yet."
    }

    func startPolishModelPull() {
        ollamaPhase = .pullingModel
        polishPullProgress = 0.12
        event = "FoldWise started the qwen2.5:3b pull through Ollama's local HTTP API."
    }

    func tickPolishModelPull() {
        guard ollamaPhase == .pullingModel else { return }
        polishPullProgress = min(polishPullProgress + 0.24, 1)
        if polishPullProgress == 1 {
            ollamaPhase = .ready
            event = "Ollama and qwen2.5:3b are ready for Polish."
        } else {
            event = "Polish-model download progress updated."
        }
    }

    func cancelPolishModelPull() {
        ollamaPhase = .runningWithoutModel
        polishPullProgress = 0
        event = "Polish-model download canceled; Ollama remains available."
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
        if setupActive {
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
        shortcutLabel = nil
        isCapturingShortcut = false
        polishChoice = nil
        ollamaPhase = .notDetected
        polishPullProgress = 0
        closeConfirmationPresented = false
        event = "Prototype reset to a fresh first launch."
    }

    private func animate(reduceMotion: Bool, changes: @escaping () -> Void) {
        if reduceMotion {
            changes()
        } else {
            withAnimation(
                .spring(response: 0.44, dampingFraction: 0.92, blendDuration: 0.12),
                changes
            )
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
                        ScrollView {
                            StepContent(model: model)
                                .id(model.currentStep)
                                .transition(stepTransition)
                                .padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
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
        let direction = CGFloat(model.transitionDirection)
        return .asymmetric(
            insertion: .modifier(
                active: StepMotionModifier(
                    opacity: 0,
                    offset: 34 * direction,
                    scale: 0.992,
                    blur: 3
                ),
                identity: StepMotionModifier()
            ),
            removal: .modifier(
                active: StepMotionModifier(
                    opacity: 0,
                    offset: -18 * direction,
                    scale: 0.996,
                    blur: 2
                ),
                identity: StepMotionModifier()
            )
        )
    }
}

private struct StepMotionModifier: ViewModifier {
    var opacity = 1.0
    var offset = 0.0
    var scale = 1.0
    var blur = 0.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .offset(x: offset)
            .scaleEffect(scale, anchor: .leading)
            .blur(radius: blur)
    }
}

private struct StepProgress: View {
    @ObservedObject var model: PrototypeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var activeStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.element.id) { index, step in
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(index < model.stepIndex ? Palette.accent : Palette.raised)
                            .frame(width: 20, height: 20)
                        if index < model.stepIndex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.black)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(
                                    index == model.stepIndex ? Palette.primary : Palette.tertiary
                                )
                        }
                    }
                    if index == model.stepIndex {
                        Text(step.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.primary)
                    }
                }
                .padding(.horizontal, index == model.stepIndex ? 9 : 0)
                .frame(height: 30)
                .background {
                    if index == model.stepIndex {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Palette.raised)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Palette.accent)
                                    .frame(height: 2)
                                    .padding(.horizontal, 8)
                            }
                            .matchedGeometryEffect(id: "active-step", in: activeStep)
                    }
                }
                if index < SetupStep.allCases.count - 1 {
                    Rectangle()
                        .fill(index < model.stepIndex ? Palette.accent : Palette.border)
                        .frame(maxWidth: 28)
                        .frame(height: 1)
                }
            }
        }
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.4, dampingFraction: 0.9, blendDuration: 0.1),
            value: model.stepIndex
        )
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Palette.raised)
                    SignalWave(
                        progress: model.speechDownloadStarted
                            ? max(model.speechDownloadProgress, 0.18)
                            : 0
                    )
                    .padding(18)
                }
                .frame(width: 168, height: 126)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PARAKEET TDT V3")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Palette.tertiary)
                    Text("≈ 600 MB")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("The default speech model")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Fast on-device transcription across 25 languages. "
                        + "Audio and transcripts stay on this Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(2)
                }
                Spacer()
            }
            .padding(16)
            .background(Palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                FeatureChip(symbol: "lock.shield", text: "Private")
                FeatureChip(symbol: "bolt", text: "Neural Engine")
                FeatureChip(symbol: "network.slash", text: "Works offline")
            }

            if model.speechDownloadStarted {
                DownloadProgress(
                    title: model.speechDownloadProgress == 1
                        ? "Parakeet is ready"
                        : "Preparing Parakeet",
                    detail: model.speechDownloadProgress == 1
                        ? "FoldWise can now transcribe Dictation sessions."
                        : "Keep going—this download continues behind the next steps.",
                    progress: model.speechDownloadProgress,
                    ready: model.speechDownloadProgress == 1
                )
            } else {
                HStack(spacing: 12) {
                    Button("Download Parakeet") { model.startSpeechDownload() }
                        .buttonStyle(PrimaryButtonStyle())
                    Text("One download. Required for Dictation.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
            }
        }
    }
}

private struct MicrophoneDetail: View {
    @ObservedObject var model: PrototypeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(
                            model.microphoneGranted ? Palette.success : Palette.border,
                            lineWidth: 2
                        )
                        .frame(width: 94, height: 94)
                    Circle()
                        .fill(Palette.raised)
                        .frame(width: 76, height: 76)
                    Image(systemName: model.microphoneGranted ? "mic.fill" : "mic")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(
                            model.microphoneGranted ? Palette.success : Palette.accent
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.microphoneGranted ? "MICROPHONE READY" : "SYSTEM PERMISSION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(
                            model.microphoneGranted ? Palette.success : Palette.tertiary
                        )
                    Text(
                        model.microphoneGranted
                            ? "FoldWise can hear your system microphone."
                            : "macOS will ask once for microphone access."
                    )
                    .font(.system(size: 15, weight: .semibold))
                    Text(
                        model.microphoneGranted
                            ? "You can change the input device later in Settings."
                            : "FoldWise records only while a Dictation session is active. "
                                + "Audio is processed locally."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(2)
                }
                Spacer()
            }
            .padding(20)
            .background(Palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        model.microphoneGranted ? Palette.success : Palette.border,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if model.microphoneGranted {
                MicrophoneMeter()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                HStack(spacing: 12) {
                    Button("Allow microphone") {
                        withAnimation(
                            reduceMotion
                                ? nil
                                : .spring(response: 0.38, dampingFraction: 0.9)
                        ) {
                            model.microphoneGranted = true
                        }
                        model.event = "Microphone authorization observed; the hard gate is satisfied."
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Label("Required to continue", systemImage: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.tertiary)
                }
            }
        }
    }
}

private struct ShortcutDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        ShortcutRecorder(model: model)
    }
}

private struct PolishDetail: View {
    @ObservedObject var model: PrototypeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.polishChoice {
            case nil:
                PolishChoiceDetail(model: model)
            case .voiceToText:
                VoiceToTextDecision(model: model)
            case .polish:
                OllamaSetupWorkbench(model: model)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.92),
            value: model.polishChoice
        )
    }
}

private struct PolishChoiceDetail: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        HStack(spacing: 12) {
            DecisionTile(
                symbol: "text.quote",
                eyebrow: "NO LLM",
                title: "Voice to Text",
                detail: "Insert exactly what FoldWise transcribes. Nothing else to install.",
                actionTitle: "Use Voice to Text"
            ) {
                model.chooseVoiceToText()
            }
            DecisionTile(
                symbol: "sparkles",
                eyebrow: "LOCAL LLM",
                title: "Polish",
                detail: "Rewrite transcripts with local Modes after setting up Ollama.",
                actionTitle: "Set up Polish"
            ) {
                model.choosePolish()
            }
        }
    }
}

private struct VoiceToTextDecision: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(Palette.success)
            VStack(alignment: .leading, spacing: 5) {
                Text("Voice to Text is ready")
                    .font(.system(size: 15, weight: .semibold))
                Text("Your raw transcript will be inserted without an LLM rewrite.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button("Choose Polish instead") { model.choosePolish() }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(18)
        .background(Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.success, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OllamaSetupWorkbench: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("‹ Voice to Text") {
                    model.polishChoice = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.secondary)
                Spacer()
                Text(phaseLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(phaseColor)
            }

            switch model.ollamaPhase {
            case .notDetected:
                OllamaNotDetected(model: model)
            case .runningWithoutModel:
                OllamaModelOffer(model: model)
            case .pullingModel:
                DownloadProgress(
                    title: "Downloading qwen2.5:3b",
                    detail: "FoldWise is pulling through Ollama's local HTTP API.",
                    progress: model.polishPullProgress,
                    ready: false,
                    cancel: model.cancelPolishModelPull
                )
            case .ready:
                HStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Palette.success)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Polish is ready")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Ollama is responding and qwen2.5:3b is available.")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                }
                .padding(18)
                .background(Palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Palette.success, lineWidth: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var phaseLabel: String {
        switch model.ollamaPhase {
        case .notDetected: "1 / 2 · OLLAMA"
        case .runningWithoutModel, .pullingModel: "2 / 2 · POLISH MODEL"
        case .ready: "READY"
        }
    }

    private var phaseColor: Color {
        model.ollamaPhase == .ready ? Palette.success : Palette.accent
    }
}

private struct OllamaNotDetected: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 38)
                VStack(alignment: .leading, spacing: 5) {
                    Text("FoldWise couldn't find Ollama")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Ollama runs the local model used by Polish. FoldWise can "
                        + "download the model after Ollama is running, but it does "
                        + "not install Ollama itself.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineSpacing(2)
                }
            }

            HStack(spacing: 10) {
                Button("Download Ollama for macOS") {
                    if let url = URL(string: "https://ollama.com/download/mac") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                Button("Installation help") {
                    if let url = URL(string: "https://docs.ollama.com/macos") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(QuietButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("OR INSTALL WITH HOMEBREW")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(Palette.tertiary)
                CommandRow(command: "brew install --cask ollama-app")
                CommandRow(command: "open -a Ollama")
            }

            HStack {
                Text("After Ollama is open, FoldWise checks its local service.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                Button("Check again") { model.retryOllamaProbe() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .padding(16)
        .background(Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct OllamaModelOffer: View {
    @ObservedObject var model: PrototypeModel

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Palette.raised)
                VStack(spacing: 3) {
                    Text("1.9")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("GB DOWNLOAD")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(Palette.tertiary)
                }
            }
            .frame(width: 128, height: 110)

            VStack(alignment: .leading, spacing: 7) {
                Label("Ollama is running", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.success)
                Text("Add qwen2.5:3b")
                    .font(.system(size: 18, weight: .semibold))
                Text("FoldWise's tested compatibility default for multilingual "
                    + "Mode-based rewriting.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(2)
                Button("Download model with FoldWise") { model.startPolishModelPull() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Spacer()
        }
        .padding(16)
        .background(Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct SignalWave: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let heights: [CGFloat] = [18, 34, 52, 28, 68, 44, 24, 58, 38, 20]

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                let filled = Double(index + 1) / Double(heights.count) <= progress
                Capsule()
                    .fill(filled ? Palette.accent : Palette.border)
                    .frame(width: 5, height: height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
            value: progress
        )
        .accessibilityHidden(true)
    }
}

private struct FeatureChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Palette.raised)
            .clipShape(Capsule())
    }
}

private struct DownloadProgress: View {
    let title: String
    let detail: String
    let progress: Double
    let ready: Bool
    var cancel: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: ready ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(ready ? Palette.success : Palette.accent)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(ready ? Palette.success : Palette.primary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.raised)
                    Capsule()
                        .fill(ready ? Palette.success : Palette.accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 5)
            HStack {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.secondary)
                Spacer()
                if let cancel, !ready {
                    Button("Cancel", action: cancel)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
            }
        }
        .padding(14)
        .background(Palette.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(ready ? Palette.success : Palette.accent)
                .frame(width: 3)
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.88),
            value: progress
        )
    }
}

private struct MicrophoneMeter: View {
    private let heights: [CGFloat] = [8, 16, 12, 26, 38, 24, 46, 30, 18, 10, 22, 14]

    var body: some View {
        HStack(spacing: 6) {
            Label("SYSTEM DEFAULT", systemImage: "waveform")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Palette.success)
            Spacer()
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                    Capsule()
                        .fill(index < 8 ? Palette.success : Palette.border)
                        .frame(width: 3, height: height)
                }
            }
            Text("INPUT DETECTED")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Palette.success)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShortcutRecorder: View {
    @ObservedObject var model: PrototypeModel
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(model.isCapturingShortcut ? Palette.raised : Palette.surface)
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            model.isCapturingShortcut ? Palette.accent : Palette.border,
                            lineWidth: model.isCapturingShortcut ? 2 : 1
                        )
                    if let shortcut = model.shortcutLabel {
                        Text(shortcut)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                            .foregroundStyle(Palette.primary)
                    } else if model.isCapturingShortcut {
                        VStack(spacing: 7) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 22))
                                .foregroundStyle(Palette.accent)
                            Text("PRESS KEYS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(Palette.accent)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(Palette.tertiary)
                    }
                }
                .frame(width: 176, height: 108)

                VStack(alignment: .leading, spacing: 8) {
                    Text(model.shortcutLabel == nil ? "Pick your exact shortcut" : "Shortcut captured")
                        .font(.system(size: 16, weight: .semibold))
                    Text(
                        model.isCapturingShortcut
                            ? "Press one key or a key combination now."
                            : "Choose the key you will hold while speaking. "
                                + "FoldWise rejects collisions with its other commands."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .lineSpacing(2)
                    Button(model.shortcutLabel == nil ? "Record shortcut" : "Change shortcut") {
                        model.beginShortcutCapture()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Spacer()
            }
            .padding(18)
            .background(Palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 10) {
                Label("Hold to record", systemImage: "hand.tap")
                Label("Release to transcribe", systemImage: "waveform")
                Label("Must be unique", systemImage: "checkmark.shield")
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Palette.secondary)
        }
        .onChange(of: model.isCapturingShortcut) { _, capturing in
            capturing ? installMonitor() : removeMonitor()
        }
        .onDisappear {
            removeMonitor()
        }
    }

    private func installMonitor() {
        removeMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard model.isCapturingShortcut else { return event }
            guard let label = shortcutLabel(for: event) else { return event }
            model.commitShortcut(label)
            return nil
        }
    }

    private func removeMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func shortcutLabel(for event: NSEvent) -> String? {
        if event.type == .flagsChanged {
            return modifierKeyLabel(for: event)
        }

        var parts: [String] = []
        if event.modifierFlags.contains(.control) {
            parts.append("⌃")
        }
        if event.modifierFlags.contains(.option) {
            parts.append("⌥")
        }
        if event.modifierFlags.contains(.shift) {
            parts.append("⇧")
        }
        if event.modifierFlags.contains(.command) {
            parts.append("⌘")
        }

        let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        parts.append(key == " " ? "Space" : key)
        return parts.joined(separator: " ")
    }

    private func modifierKeyLabel(for event: NSEvent) -> String? {
        let key: String? = switch event.keyCode {
        case 54: "Right Command"
        case 55: "Left Command"
        case 56: "Left Shift"
        case 58: "Left Option"
        case 59: "Left Control"
        case 60: "Right Shift"
        case 61: "Right Option"
        case 62: "Right Control"
        case 63: "Fn"
        default: nil
        }
        guard let key else { return nil }
        let stillPressed = !event.modifierFlags.isDisjoint(
            with: [.command, .shift, .option, .control, .function]
        )
        return stillPressed ? key : nil
    }
}

private struct DecisionTile: View {
    let symbol: String
    let eyebrow: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Text(eyebrow)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(Palette.tertiary)
            }
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineSpacing(2)
                .frame(maxHeight: .infinity, alignment: .top)
            Button(actionTitle, action: action)
                .buttonStyle(QuietButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .background(Palette.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CommandRow: View {
    let command: String

    var body: some View {
        HStack(spacing: 10) {
            Text(command)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.primary)
                .textSelection(.enabled)
            Spacer()
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(command, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondary)
            .help("Copy command")
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background(Palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: 5))
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
            if model.speechDownloadStarted, model.speechDownloadProgress < 1 {
                Button("Advance model download") { model.tickSpeechDownload() }
                    .buttonStyle(InspectorButtonStyle())
            }
            if model.ollamaPhase == .pullingModel {
                Button("Advance Polish download") { model.tickPolishModelPull() }
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
