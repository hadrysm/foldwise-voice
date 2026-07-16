// The Badge's presentation state machines (PRDs #103 and #169): pure reducers mapping
// pipeline phases and pointer events onto the pill's states — idle ⇄ hover →
// recording → working → done/error → idle — plus each state's width, dwell,
// and content flags. The controller and view are thin shells over this, so
// the whole machine (including recording's exit-only-via-stop rule) is
// unit-tested without a panel. Mode-cycle confirmation separately owns its
// queue, timing, pipeline priority, failure deferral, and Reduce Motion path.

import Foundation

struct BadgeModeCycleItem: Equatable {
    let selection: DictationSelection
    let name: String
    let icon: String
}

enum BadgeHoverAccessibility {
    static func selectionLabel(currentSelection: String) -> String {
        "Change Dictation selection, current selection \(currentSelection)"
    }

    static func recordLabel(shortcut: String) -> String {
        "Start Dictation, shortcut \(shortcut)"
    }

    static let openAppLabel = "Open FoldWise"
}

enum BadgeModeCycleMotion: Equatable {
    case standard
    case reduced
}

enum BadgeModeCyclePhase: Equatable {
    case prepared
    case swapping
    case settled
}

enum BadgeModeCycleDisplay: Equatable {
    case prepared(
        from: BadgeModeCycleItem,
        to: BadgeModeCycleItem,
        motion: BadgeModeCycleMotion
    )
    case swapping(
        from: BadgeModeCycleItem,
        to: BadgeModeCycleItem,
        motion: BadgeModeCycleMotion
    )
    case settled(BadgeModeCycleItem, motion: BadgeModeCycleMotion)

    var motion: BadgeModeCycleMotion {
        switch self {
        case let .prepared(_, _, motion), let .swapping(_, _, motion),
             let .settled(_, motion):
            motion
        }
    }

    var destination: BadgeModeCycleItem {
        switch self {
        case let .prepared(_, to, _), let .swapping(_, to, _): to
        case let .settled(item, _): item
        }
    }

    var accessibilityLabel: String {
        destination.name
    }

    var phase: BadgeModeCyclePhase {
        switch self {
        case .prepared: .prepared
        case .swapping: .swapping
        case .settled: .settled
        }
    }

    var animatesSwap: Bool {
        phase == .swapping
    }

    var outgoing: BadgeModeCycleItem? {
        switch self {
        case let .prepared(from, _, _), let .swapping(from, _, _): from
        case .settled: nil
        }
    }

    var outgoingOpacity: Double {
        phase == .prepared ? 1 : 0
    }

    var outgoingOffset: Double {
        phase == .swapping && motion == .standard ? -18 : 0
    }

    var incomingOpacity: Double {
        phase == .prepared ? 0 : 1
    }

    var incomingOffset: Double {
        phase == .prepared && motion == .standard ? 18 : 0
    }
}

struct BadgeModeCycleState: Equatable {
    var display: BadgeModeCycleDisplay?
    var queued: [BadgeModeCycleItem]
    var visiblyConfirmed: BadgeModeCycleItem?
    var badgeIsAvailable: Bool
    var deferredFrom: BadgeModeCycleItem?
    var deferredTo: BadgeModeCycleItem?
    var deferredFailure: Bool
    var reducedMotion: Bool

    init(
        display: BadgeModeCycleDisplay? = nil,
        queued: [BadgeModeCycleItem] = [],
        visiblyConfirmed: BadgeModeCycleItem? = nil,
        badgeIsAvailable: Bool = true,
        deferredFrom: BadgeModeCycleItem? = nil,
        deferredTo: BadgeModeCycleItem? = nil,
        deferredFailure: Bool = false,
        reducedMotion: Bool = false
    ) {
        self.display = display
        self.queued = queued
        self.visiblyConfirmed = visiblyConfirmed
        self.badgeIsAvailable = badgeIsAvailable
        self.deferredFrom = deferredFrom
        self.deferredTo = deferredTo
        self.deferredFailure = deferredFailure
        self.reducedMotion = reducedMotion
    }

    static func idle(reducedMotion: Bool = false) -> BadgeModeCycleState {
        BadgeModeCycleState(reducedMotion: reducedMotion)
    }

    var allowsHover: Bool {
        display == nil
    }
}

enum BadgeModeCycleEvent: Equatable {
    case committed(from: BadgeModeCycleItem, to: BadgeModeCycleItem)
    case selectionChanged(DictationSelection)
    case failed
    case badgeBecameBusy
    case badgeBecameAvailable
    case swapBegan
    case swapElapsed
    case dwellElapsed
    case reduceMotionChanged(Bool)
    case presentationsChanged([BadgeModeCycleItem])
}

enum BadgeModeCycleEffect: Equatable {
    case cancelScheduled
    case send(BadgeModeCycleEvent)
    case schedule(BadgeModeCycleEvent, after: TimeInterval)
    case showError(String)
}

struct BadgeModeCycleTransition: Equatable {
    let state: BadgeModeCycleState
    let effects: [BadgeModeCycleEffect]
}

enum BadgeModeCycleReducer {
    static let expandedWidth = 176.0
    static let resizeDuration = 0.300
    static let swapDuration = 0.260
    static let reducedSwapDuration = 0.180
    static let settledDwell = 0.900

    static func reduce(
        _ current: BadgeModeCycleState,
        _ event: BadgeModeCycleEvent
    ) -> BadgeModeCycleTransition {
        var state = current
        var effects: [BadgeModeCycleEffect] = []

        switch event {
        case let .committed(from, to):
            guard state.badgeIsAvailable else {
                state.deferredFrom = state.deferredFrom ?? from
                state.deferredTo = to
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            switch state.display {
            case .prepared, .swapping:
                state.queued.append(to)
            case let .settled(item, _):
                effects.append(.cancelScheduled)
                begin(from: item, to: to, state: &state, effects: &effects)
            case nil:
                begin(from: from, to: to, state: &state, effects: &effects)
            }

        case let .selectionChanged(selection):
            let finalSelection = state.deferredTo?.selection
                ?? state.queued.last?.selection
                ?? state.display?.destination.selection
            if let finalSelection, finalSelection != selection {
                cancelSuccess(in: &state, effects: &effects)
            }

        case .failed:
            guard state.badgeIsAvailable else {
                state.deferredFailure = true
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            if state.display != nil {
                deferCurrentSuccess(in: &state)
                effects.append(.cancelScheduled)
            }
            state.badgeIsAvailable = false
            effects.append(.showError("couldn’t switch Mode"))

        case .badgeBecameBusy:
            guard state.badgeIsAvailable else {
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            state.badgeIsAvailable = false
            if state.display != nil {
                deferCurrentSuccess(in: &state)
                effects.append(.cancelScheduled)
            }

        case .badgeBecameAvailable:
            state.badgeIsAvailable = true
            if state.deferredFailure {
                state.deferredFailure = false
                state.badgeIsAvailable = false
                effects.append(.showError("couldn’t switch Mode"))
            } else if let from = state.deferredFrom, let to = state.deferredTo {
                state.deferredFrom = nil
                state.deferredTo = nil
                if from.selection != to.selection {
                    begin(from: from, to: to, state: &state, effects: &effects)
                }
            }

        case .swapBegan:
            guard case let .prepared(from, to, motion) = state.display else {
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            state.display = .swapping(from: from, to: to, motion: motion)
            let duration = motion == .reduced ? reducedSwapDuration : swapDuration
            effects.append(.schedule(.swapElapsed, after: duration))

        case .swapElapsed:
            guard case let .swapping(_, to, motion) = state.display else {
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            state.visiblyConfirmed = to
            if state.queued.isEmpty {
                state.display = .settled(to, motion: motion)
                effects.append(.schedule(.dwellElapsed, after: settledDwell))
            } else {
                let next = state.queued.removeFirst()
                begin(from: to, to: next, state: &state, effects: &effects)
            }

        case .dwellElapsed:
            guard case .settled = state.display else {
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            state.display = nil
            state.queued = []
            state.visiblyConfirmed = nil
            effects.append(.cancelScheduled)

        case let .reduceMotionChanged(reducedMotion):
            state.reducedMotion = reducedMotion
            if case .swapping = state.display {
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            state.display = state.display.map {
                replacingMotion(in: $0, with: reducedMotion ? .reduced : .standard)
            }

        case let .presentationsChanged(items):
            let availableSelections = Set(items.map(\.selection))
            if referencedItems(in: state).contains(where: {
                !availableSelections.contains($0.selection)
            }) {
                cancelSuccess(in: &state, effects: &effects)
                return BadgeModeCycleTransition(state: state, effects: effects)
            }
            state.display = state.display.map { replacingItems(in: $0, with: items) }
            state.queued = state.queued.map { refreshed($0, with: items) }
            state.visiblyConfirmed = state.visiblyConfirmed.map { refreshed($0, with: items) }
            state.deferredFrom = state.deferredFrom.map { refreshed($0, with: items) }
            state.deferredTo = state.deferredTo.map { refreshed($0, with: items) }
        }

        return BadgeModeCycleTransition(state: state, effects: effects)
    }

    private static func begin(
        from: BadgeModeCycleItem,
        to: BadgeModeCycleItem,
        state: inout BadgeModeCycleState,
        effects: inout [BadgeModeCycleEffect]
    ) {
        let motion: BadgeModeCycleMotion = state.reducedMotion ? .reduced : .standard
        state.display = .prepared(from: from, to: to, motion: motion)
        state.visiblyConfirmed = from
        effects.append(.send(.swapBegan))
    }

    private static func deferCurrentSuccess(in state: inout BadgeModeCycleState) {
        guard let display = state.display else { return }
        state.deferredFrom = state.visiblyConfirmed
        state.deferredTo = state.queued.last ?? display.destination
        state.display = nil
        state.queued = []
        state.visiblyConfirmed = nil
    }

    private static func cancelSuccess(
        in state: inout BadgeModeCycleState,
        effects: inout [BadgeModeCycleEffect]
    ) {
        if state.display != nil {
            effects.append(.cancelScheduled)
        }
        state.display = nil
        state.queued = []
        state.visiblyConfirmed = nil
        state.deferredFrom = nil
        state.deferredTo = nil
    }

    private static func referencedItems(in state: BadgeModeCycleState) -> [BadgeModeCycleItem] {
        var items = state.queued
        if let outgoing = state.display?.outgoing {
            items.append(outgoing)
        }
        if let destination = state.display?.destination {
            items.append(destination)
        }
        for item in [state.visiblyConfirmed, state.deferredFrom, state.deferredTo] {
            if let item {
                items.append(item)
            }
        }
        return items
    }

    private static func replacingMotion(
        in display: BadgeModeCycleDisplay,
        with motion: BadgeModeCycleMotion
    ) -> BadgeModeCycleDisplay {
        switch display {
        case let .prepared(from, to, _): .prepared(from: from, to: to, motion: motion)
        case let .swapping(from, to, _): .swapping(from: from, to: to, motion: motion)
        case let .settled(item, _): .settled(item, motion: motion)
        }
    }

    private static func replacingItems(
        in display: BadgeModeCycleDisplay,
        with items: [BadgeModeCycleItem]
    ) -> BadgeModeCycleDisplay {
        switch display {
        case let .prepared(from, to, motion):
            .prepared(
                from: refreshed(from, with: items),
                to: refreshed(to, with: items),
                motion: motion
            )
        case let .swapping(from, to, motion):
            .swapping(
                from: refreshed(from, with: items),
                to: refreshed(to, with: items),
                motion: motion
            )
        case let .settled(item, motion):
            .settled(refreshed(item, with: items), motion: motion)
        }
    }

    private static func refreshed(
        _ item: BadgeModeCycleItem,
        with items: [BadgeModeCycleItem]
    ) -> BadgeModeCycleItem {
        items.first { $0.selection == item.selection } ?? item
    }
}

enum BadgeFramePolicy {
    static func frame(size: CGSize, anchor: CGPoint, screen: CGRect?) -> CGRect {
        var x = anchor.x - size.width / 2
        var y = anchor.y
        if let screen {
            x = max(screen.minX + 4, min(x, screen.maxX - size.width - 4))
            y = max(screen.minY + 4, min(y, screen.maxY - size.height - 4))
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}

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

    var ownsModeCyclePresentation: Bool {
        switch self {
        case .recording, .working, .done, .error: true
        case .idle, .hover: false
        }
    }
}

enum BadgeEvent: Equatable {
    case pipeline(PipelineState)
    case modeSelectionFailed
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
    var deferredModeSelectionError = false
}

enum BadgeReducer {
    static func reduce(
        _ state: BadgeState,
        _ event: BadgeEvent,
        deferredModeSelectionError: Bool = false
    ) -> BadgeTransition {
        var transition = switch event {
        case let .pipeline(phase):
            BadgeTransition(state: map(phase, from: state), command: nil)
        case .modeSelectionFailed:
            switch state {
            case .idle, .hover:
                BadgeTransition(state: .error(message: "couldn’t select Mode"), command: nil)
            case .recording, .working, .done, .error:
                BadgeTransition(
                    state: state,
                    command: nil,
                    deferredModeSelectionError: true
                )
            }
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
        transition.deferredModeSelectionError =
            deferredModeSelectionError || transition.deferredModeSelectionError
        if transition.state == .idle, transition.deferredModeSelectionError {
            transition.state = .error(message: "couldn’t select Mode")
            transition.deferredModeSelectionError = false
        }
        return transition
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
