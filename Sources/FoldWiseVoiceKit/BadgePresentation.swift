// The Badge's presentation state machine (PRD #103): one pure reducer mapping
// pipeline phases and pointer events onto the pill's states — idle ⇄ hover →
// recording → working → done/error → idle — plus each state's width, dwell,
// and content flags. The controller and view are thin shells over this, so
// the whole machine (including recording's exit-only-via-stop rule) is
// unit-tested without a panel.

import Foundation

enum BadgeState: Equatable {
    case idle
    case hover
    case recording
    /// The pipeline is still running after the hotkey was released. A nil
    /// `status` shows the small spinner (transcribe/polish); model downloads
    /// keep a mono progress word ("downloading 45%") because the wait is
    /// long and the percentage is real information.
    case working(status: String?)
    /// The brief confirmation beat after text lands.
    case done
    /// Something needs the user's eye — a failure, or text left on the
    /// clipboard. Auto-dismisses after `dwell`; a click dismisses it early.
    case error(message: String)

    /// Pill width in points; height is a constant `Theme.badgeHeight`.
    var width: Double {
        switch self {
        case .idle: 88
        case .hover: 132
        case .recording, .working, .done, .error: 208
        }
    }

    /// How long the state stays on screen before `.dwellElapsed` returns the
    /// pill to idle; nil for states that wait on events instead of time.
    var dwell: TimeInterval? {
        switch self {
        case .done: 0.6
        case .error: 3.0
        default: nil
        }
    }

    /// Whether the silk-ribbon canvas is on show.
    var showsRibbons: Bool {
        switch self {
        case .recording, .working: true
        default: false
        }
    }

    /// Ribbons dance with the mic only while recording; working keeps them
    /// moving at the slow idle-preview speed with a low fixed amplitude.
    var ribbonsFollowMic: Bool {
        self == .recording
    }

    /// The mono line beside the ribbons: the working progress word (nil →
    /// the spinner) or the error message. Recording shows the timer instead
    /// (view-owned).
    var statusText: String? {
        switch self {
        case let .working(status): status
        case let .error(message): message
        default: nil
        }
    }
}

enum BadgeEvent: Equatable {
    case pipeline(PipelineState)
    case hoverChanged(Bool)
    /// A click anywhere on the pill (the hover buttons handle themselves).
    case clicked
    /// The current state's `dwell` ran out.
    case dwellElapsed
}

/// Side effect a transition asks the controller to perform.
enum BadgeCommand: Equatable {
    case stopRecording
}

struct BadgeTransition: Equatable {
    var state: BadgeState
    var command: BadgeCommand?
}

enum BadgeReducer {
    static func reduce(_ state: BadgeState, _ event: BadgeEvent) -> BadgeTransition {
        switch event {
        case let .pipeline(phase):
            BadgeTransition(state: map(phase, from: state), command: nil)
        case let .hoverChanged(over):
            switch (state, over) {
            case (.idle, true): BadgeTransition(state: .hover, command: nil)
            case (.hover, false): BadgeTransition(state: .idle, command: nil)
            default: BadgeTransition(state: state, command: nil)
            }
        case .clicked:
            switch state {
            // Recording exits only via stop: the click IS the stop request,
            // and the state waits for the pipeline to move on.
            case .recording: BadgeTransition(state: .recording, command: .stopRecording)
            case .done, .error: BadgeTransition(state: .idle, command: nil)
            default: BadgeTransition(state: state, command: nil)
            }
        case .dwellElapsed:
            switch state {
            case .done, .error: BadgeTransition(state: .idle, command: nil)
            default: BadgeTransition(state: state, command: nil)
            }
        }
    }

    private static func map(_ phase: PipelineState, from state: BadgeState) -> BadgeState {
        switch phase {
        case .listening:
            .recording
        case .transcribing, .polishing:
            // The post-talk stages show the spinner, not a word — the user
            // is waiting for their text, not watching stage names.
            .working(status: nil)
        case let .downloadingModel(fraction):
            .working(status: "downloading \(Int(fraction * 100))%")
        case .loadingModel:
            .working(status: "preparing…")
        case .inserted:
            .done
        case .clipboard:
            .error(message: "copied — press ⌘V")
        case .error:
            .error(message: "something went wrong")
        case .idle:
            // A session that produced nothing (too short, silence). Keep a
            // dwelling state on screen — its own timer ends it.
            switch state {
            case .done, .error: state
            default: .idle
            }
        }
    }
}
