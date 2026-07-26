enum SetupStep: String, CaseIterable, Hashable {
    case accessibility = "Accessibility"
    case speechModel = "Speech model"
    case microphone = "Microphone"
    case shortcut = "Push-to-Talk shortcut"
    case polish = "Polish"

    var next: SetupStep? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let nextIndex = Self.allCases.index(after: index)
        return nextIndex == Self.allCases.endIndex ? nil : Self.allCases[nextIndex]
    }

    var previous: SetupStep? {
        guard let index = Self.allCases.firstIndex(of: self),
              index != Self.allCases.startIndex
        else {
            return nil
        }
        return Self.allCases[Self.allCases.index(before: index)]
    }

    var requirement: String {
        switch self {
        case .microphone:
            "Required · the only hard navigation gate · not deferrable."
        case .speechModel:
            "Required for Dictation ready · advance after an explicit download starts."
        case .accessibility:
            "Optional and deferrable · Input Monitoring is the narrower fallback."
        case .shortcut:
            "Optional choice · a valid Right Option default already ships."
        case .polish:
            "Optional · explicitly declinable · Voice to Text remains the default."
        }
    }

    var decliningCost: String {
        switch self {
        case .microphone:
            "FoldWise cannot hear or transcribe you."
        case .speechModel:
            "Still unresolved: the dedicated speech-model ticket decides whether decline exists."
        case .accessibility:
            "Text lands on the clipboard instead of pasting itself; without Input Monitoring, use the Badge."
        case .shortcut:
            "None when keeping Right Option; it remains editable later."
        case .polish:
            "Dictation inserts the raw transcript without an LLM rewrite."
        }
    }

    var satisfiedBy: String {
        switch self {
        case .microphone:
            "A live permission poll reports Microphone authorized."
        case .speechModel:
            "The user starts the disclosed download; Dictation ready waits for lifecycle readiness."
        case .accessibility:
            "A live poll sees either permission, or the user explicitly declines both."
        case .shortcut:
            "The user keeps the current valid binding or captures a valid replacement."
        case .polish:
            "The user declines, or Ollama is ready with qwen2.5:3b and Polish is enabled."
        }
    }

    var reentry: String {
        switch self {
        case .microphone, .accessibility:
            "Permission recovery guide, macOS System Settings, or Run setup again."
        case .speechModel:
            "Models, or Run setup again."
        case .shortcut:
            "Settings, or Run setup again."
        case .polish:
            "Models and Modes, or Run setup again."
        }
    }
}

enum SetupStatus: String {
    case active = "In progress"
    case completed = "Setup completed"
    case skipped = "Setup skipped"
}

enum StepOutcome: String {
    case completed
    case declined
}

enum MicrophoneState: String {
    case notDetermined = "not requested"
    case denied
    case authorized
}

enum SpeechModelState: Equatable {
    case missing
    case downloading(percent: Int)
    case ready
    case failed

    var description: String {
        switch self {
        case .missing:
            "not downloaded"
        case let .downloading(percent):
            "downloading (\(percent)%)"
        case .ready:
            "ready"
        case .failed:
            "download failed"
        }
    }

    var hasStarted: Bool {
        switch self {
        case .missing:
            false
        case .downloading, .ready, .failed:
            true
        }
    }
}

enum InsertionRoute: String {
    case undecided
    case accessibility = "Accessibility: paste automatically + global shortcut"
    case inputMonitoring = "Input Monitoring: clipboard + global shortcut"
    case badgeOnly = "No permission: clipboard + Badge"
}

enum OllamaState: String {
    case notDetected = "not detected"
    case runningWithoutModel = "running, qwen2.5:3b missing"
    case ready = "running, qwen2.5:3b ready"
}

enum PolishChoice: String {
    case undecided
    case declined = "Voice to Text"
    case enabled = "Polish enabled"
}

struct GuidedSetupState {
    var status: SetupStatus = .active
    var step: SetupStep = .accessibility
    var outcomes: [SetupStep: StepOutcome] = [:]

    var microphone: MicrophoneState = .notDetermined
    var speechModel: SpeechModelState = .missing
    var insertionRoute: InsertionRoute = .undecided
    var shortcut = "Right Option (alt_r)"
    var shortcutConfirmed = false
    var ollama: OllamaState = .notDetected
    var polish: PolishChoice = .undecided

    var notice = "Try the happy path, then Run setup again and decline optional steps."

    var isDictationReady: Bool {
        microphone == .authorized && speechModel == .ready
    }

    var backgroundProgress: String? {
        switch speechModel {
        case let .downloading(percent):
            "Speech model \(percent)%"
        case .failed:
            "Speech model failed — Retry belongs to the speech-model contract"
        case .missing, .ready:
            nil
        }
    }
}

enum GuidedSetupAction {
    case grantMicrophone
    case denyMicrophone
    case startSpeechDownload
    case tickBackgroundDownload
    case failBackgroundDownload
    case grantAccessibility
    case grantInputMonitoring
    case declineInsertionPermissions
    case keepShortcut
    case replaceShortcut
    case detectOllamaRunning
    case makePolishModelReady
    case enablePolish
    case declinePolish
    case back
    case skipSetup
    case runSetupAgain
    case simulateRelaunch
}

enum GuidedSetupReducer {
    static func reduce(_ state: inout GuidedSetupState, _ action: GuidedSetupAction) {
        switch action {
        case .grantMicrophone:
            guard state.status == .active, state.step == .microphone else {
                return reject(&state)
            }
            state.microphone = .authorized
            advance(&state, as: .completed)

        case .denyMicrophone:
            guard state.status == .active, state.step == .microphone else {
                return reject(&state)
            }
            state.microphone = .denied
            state.notice = "Microphone was denied. This is the one hard gate, so the cursor stays here."

        case .startSpeechDownload:
            guard state.status == .active, state.step == .speechModel else {
                return reject(&state)
            }
            if !state.speechModel.hasStarted || state.speechModel == .failed {
                state.speechModel = .downloading(percent: 0)
            }
            advance(&state, as: .completed)
            state.notice = "Download started. Its readiness is now visible independently of the Setup cursor."

        case .tickBackgroundDownload:
            guard case let .downloading(percent) = state.speechModel else {
                state.notice = "There is no active speech-model download to advance."
                return
            }
            let next = min(percent + 25, 100)
            state.speechModel = next == 100 ? .ready : .downloading(percent: next)
            state.notice = next == 100
                ? "The speech model is ready; Dictation readiness updates without moving the Setup cursor."
                : "Background speech-model progress advanced."

        case .failBackgroundDownload:
            guard case .downloading = state.speechModel else {
                state.notice = "There is no active speech-model download to fail."
                return
            }
            state.speechModel = .failed
            state.notice = "The download failed. Retry/failure presentation is intentionally left to the next ticket."

        case .grantAccessibility:
            guard state.status == .active, state.step == .accessibility else {
                return reject(&state)
            }
            state.insertionRoute = .accessibility
            advance(&state, as: .completed)

        case .grantInputMonitoring:
            guard state.status == .active, state.step == .accessibility else {
                return reject(&state)
            }
            state.insertionRoute = .inputMonitoring
            advance(&state, as: .completed)

        case .declineInsertionPermissions:
            guard state.status == .active, state.step == .accessibility else {
                return reject(&state)
            }
            state.insertionRoute = .badgeOnly
            advance(&state, as: .declined)

        case .keepShortcut:
            guard state.status == .active, state.step == .shortcut else {
                return reject(&state)
            }
            state.shortcutConfirmed = true
            advance(&state, as: .completed)

        case .replaceShortcut:
            guard state.status == .active, state.step == .shortcut else {
                return reject(&state)
            }
            state.shortcut = "Control + Space (prototype value)"
            state.shortcutConfirmed = true
            advance(&state, as: .completed)

        case .detectOllamaRunning:
            guard state.status == .active, state.step == .polish else {
                return reject(&state)
            }
            state.ollama = .runningWithoutModel
            state.notice = "Ollama is reachable but the compatibility model is absent."

        case .makePolishModelReady:
            guard state.status == .active, state.step == .polish,
                  state.ollama == .runningWithoutModel
            else {
                return reject(&state)
            }
            state.ollama = .ready
            state.notice = "qwen2.5:3b is now ready. Enable Polish or decline it."

        case .enablePolish:
            guard state.status == .active, state.step == .polish,
                  state.ollama == .ready
            else {
                state.notice = "Polish cannot be promised until Ollama and qwen2.5:3b are ready."
                return
            }
            state.polish = .enabled
            finish(&state, as: .completed)

        case .declinePolish:
            guard state.status == .active, state.step == .polish else {
                return reject(&state)
            }
            state.polish = .declined
            finish(&state, as: .declined)

        case .back:
            guard state.status == .active, let previous = state.step.previous else {
                state.notice = "There is no earlier Setup step."
                return
            }
            state.step = previous
            state.notice = "Re-entered \(previous.rawValue); live configuration is preserved."

        case .skipSetup:
            guard state.status == .active else {
                return reject(&state)
            }
            state.status = .skipped
            state.notice = "The cursor is terminal. Current configuration and background work are preserved."

        case .runSetupAgain:
            state.status = .active
            state.step = .accessibility
            state.outcomes = [:]
            state.notice = "Re-run started from live configuration; nothing was reset."

        case .simulateRelaunch:
            guard state.status == .active else {
                state.notice = "A terminal cursor suppresses Guided setup on relaunch."
                return
            }
            state.notice = "Simulated quit/relaunch: the mid-step cursor resumes at \(state.step.rawValue)."
        }
    }

    private static func advance(_ state: inout GuidedSetupState, as outcome: StepOutcome) {
        state.outcomes[state.step] = outcome
        guard let next = state.step.next else {
            return finish(&state, as: outcome)
        }
        state.step = next
        state.notice = "Advanced to \(next.rawValue)."
    }

    private static func finish(_ state: inout GuidedSetupState, as outcome: StepOutcome) {
        state.outcomes[state.step] = outcome
        state.status = .completed
        state.notice = state.isDictationReady
            ? "Setup completed, and Dictation is ready."
            : "Setup completed, but Dictation is not ready yet."
    }

    private static func reject(_ state: inout GuidedSetupState) {
        state.notice = "That action is not available from the current Setup step."
    }
}
