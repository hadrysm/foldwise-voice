import Foundation

private let bold = "\u{001B}[1m"
private let dim = "\u{001B}[2m"
private let reset = "\u{001B}[0m"
private let clear = "\u{001B}[2J\u{001B}[H"

private func field(_ name: String, _ value: String) {
    print("\(bold)\(name):\(reset) \(value)")
}

private func render(_ state: GuidedSetupState) {
    print(clear, terminator: "")
    print("\(bold)GUIDED SETUP LOGIC PROTOTYPE\(reset)  \(dim)throwaway for issue #328\(reset)\n")

    field("Guided setup", state.status.rawValue)
    field("Cursor", state.status == .active ? state.step.rawValue : "terminal")
    field("Dictation ready", state.isDictationReady ? "yes" : "no")
    field("Microphone", state.microphone.rawValue)
    field("Speech model", state.speechModel.description)
    field("Insertion route", state.insertionRoute.rawValue)
    field("Shortcut", "\(state.shortcut)\(state.shortcutConfirmed ? " · confirmed" : "")")
    field("Polish", "\(state.polish.rawValue) · Ollama \(state.ollama.rawValue)")
    if let progress = state.backgroundProgress {
        field("Corner progress", progress)
    }

    print("\n\(bold)SETUP STEPS\(reset)")
    for (index, step) in SetupStep.allCases.enumerated() {
        let marker = if state.status == .active, state.step == step {
            "→"
        } else {
            switch state.outcomes[step] {
            case .completed:
                "✓"
            case .declined:
                "–"
            case nil:
                "·"
            }
        }
        print("\(marker) \(index + 1). \(step.rawValue)")
    }

    if state.status == .active {
        let step = state.step
        print("\n\(bold)CURRENT COMPLETION CONTRACT\(reset)")
        print("\(dim)Requirement\(reset)  \(step.requirement)")
        print("\(dim)Advance when\(reset) \(step.satisfiedBy)")
        print("\(dim)Declining costs\(reset) \(step.decliningCost)")
        print("\(dim)Re-enter via\(reset) \(step.reentry)")
    }

    print("\n\(bold)ACTIONS\(reset)")
    if state.status == .active {
        switch state.step {
        case .microphone:
            print("[g] grant Microphone   [d] deny Microphone")
        case .speechModel:
            print("[s] download and continue")
        case .accessibility:
            print("[a] grant Accessibility   [i] use Input Monitoring   [d] decline both")
        case .shortcut:
            print("[k] keep Right Option   [c] capture Control + Space")
        case .polish:
            print("[o] detect Ollama running   [m] make qwen ready   [e] enable Polish   [d] decline")
        }
        print("[b] back   [x] skip Guided setup   [z] simulate quit/relaunch")
    } else {
        print("[r] Run setup again from live configuration")
    }
    print("[t] tick speech-model download   [f] fail download   [q] quit")
    print("\n\(bold)NOTICE\(reset) \(state.notice)")
    print("\n\(dim)Type a key, then Return.\(reset)")
}

private func action(for input: String, state: GuidedSetupState) -> GuidedSetupAction? {
    switch input.lowercased() {
    case "t": .tickBackgroundDownload
    case "f": .failBackgroundDownload
    case "b": .back
    case "x": .skipSetup
    case "r": .runSetupAgain
    case "z": .simulateRelaunch
    case "g" where state.step == .microphone: .grantMicrophone
    case "d" where state.step == .microphone: .denyMicrophone
    case "s" where state.step == .speechModel: .startSpeechDownload
    case "a" where state.step == .accessibility: .grantAccessibility
    case "i" where state.step == .accessibility: .grantInputMonitoring
    case "d" where state.step == .accessibility: .declineInsertionPermissions
    case "k" where state.step == .shortcut: .keepShortcut
    case "c" where state.step == .shortcut: .replaceShortcut
    case "o" where state.step == .polish: .detectOllamaRunning
    case "m" where state.step == .polish: .makePolishModelReady
    case "e" where state.step == .polish: .enablePolish
    case "d" where state.step == .polish: .declinePolish
    default: nil
    }
}

var state = GuidedSetupState()

while true {
    render(state)
    guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        break
    }
    if input.lowercased() == "q" {
        break
    }
    guard let action = action(for: input, state: state) else {
        state.notice = "Unknown key for this Setup step."
        continue
    }
    GuidedSetupReducer.reduce(&state, action)
}
