// The Live transcript caption's rules (PRD #351): which Dictation session owns
// the surface, what it says at each stage, and where it sits beside the Badge.
//
// Presentation only. The caption renders Transcript snapshots that a Streaming
// ASR model publishes while the user speaks; the stream's own final stays the
// sole transcript authority (ADR-0009), so nothing here reaches insertion,
// Polish, or History.

import CoreGraphics
import Foundation

/// Everything the caption reacts to. Three Pipeline observers feed one reducer
/// because the surface's meaning is the join of all three: identity says whose
/// session it is, progress says which stage label to show, and snapshots carry
/// the words.
enum LiveTranscriptCaptionEvent: Equatable {
    case session(DictationSessionEvent)
    case pipeline(PipelineState)
    case transcript(DictationTranscript)
}

struct LiveTranscriptCaptionState: Equatable {
    /// How much of the caption may still change. Ordered: the raw text is live
    /// until hotkey release, frozen from then on, and the later stages only
    /// relabel what is already frozen.
    enum Stage: Equatable {
        /// The user is still speaking; the tentative tail may be rewritten.
        case live
        /// Hotkey released, before the session reports what it is doing.
        case locked
        /// The session is resolving its authoritative raw transcript.
        case finalizing
        /// The selected Mode is shaping a different final result.
        case shaping
    }

    fileprivate(set) var dictationSessionID: UUID?
    fileprivate(set) var snapshot: TranscriptSnapshot = .empty
    fileprivate(set) var stage: Stage = .live
    fileprivate(set) var modeName = ""

    static let dismissed = LiveTranscriptCaptionState()

    init(dictationSessionID: UUID? = nil) {
        self.dictationSessionID = dictationSessionID
    }
}

enum LiveTranscriptCaptionReducer {
    static func reduce(
        _ current: LiveTranscriptCaptionState,
        _ event: LiveTranscriptCaptionEvent
    ) -> LiveTranscriptCaptionState {
        switch event {
        case let .session(.started(id)):
            // The new session owns the surface from its first word, and the
            // previous session's text leaves with it: an overlapping session
            // publishes no snapshots, and showing someone else's sentence
            // beside it would misattribute the words on screen.
            return LiveTranscriptCaptionState(dictationSessionID: id)

        case let .session(.finished(id)):
            guard id == current.dictationSessionID else { return current }
            return .dismissed

        case let .transcript(transcript):
            guard transcript.dictationSessionID == current.dictationSessionID else {
                return current
            }
            var state = current
            state.snapshot = transcript.snapshot
            // The authoritative raw transcript also arrives locked, well after
            // finalization started, so locking only ever moves forward.
            if transcript.phase == .locked, state.stage == .live {
                state.stage = .locked
            }
            return state

        case let .pipeline(phase):
            return reduce(current, pipeline: phase)
        }
    }

    private static func reduce(
        _ current: LiveTranscriptCaptionState,
        pipeline phase: PipelineState
    ) -> LiveTranscriptCaptionState {
        var state = current
        switch phase {
        case let .listening(mode):
            state.modeName = mode

        case .transcribing:
            guard owns(current) else { return current }
            state.stage = .finalizing

        case .polishing:
            guard owns(current) else { return current }
            state.stage = .shaping

        case .inserted, .clipboard, .error, .idle:
            guard owns(current) else { return current }
            return .dismissed

        case .downloadingModel, .loadingModel, .switchingASRModel, .recognitionUnavailable:
            break
        }
        return state
    }

    /// Whether a progress state — which carries no session identity — belongs to
    /// the session the caption is showing. One that arrives while this session is
    /// still listening belongs to an earlier session that is still finishing, so
    /// it must neither relabel nor dismiss live text.
    private static func owns(_ state: LiveTranscriptCaptionState) -> Bool {
        state.stage != .live
    }
}

/// One frame of the caption. `nil` where the state has nothing honest to show:
/// a session whose Effective ASR model does not stream never publishes a
/// snapshot, so the caption never appears for it.
struct LiveTranscriptCaptionPresentation: Equatable {
    /// Two lines, head-truncated: on a long Dictation session the newest words
    /// are the ones worth keeping on screen.
    static let lineLimit = 2
    static let truncatesHead = true

    let header: String
    /// The stage label opposite the header; absent while the user is speaking.
    let handoff: String?
    let committed: String
    let tentative: String
    /// Whether the tentative tail ends in the live-frontier marker.
    let marksLiveFrontier: Bool
    /// Polish owns the outcome now, so the locked raw text steps back a level
    /// rather than competing with the Mode that is replacing it.
    let recedesCommitted: Bool
    let accessibilityLabel: String
    let accessibilityValue: String
}

extension LiveTranscriptCaptionState {
    var presentation: LiveTranscriptCaptionPresentation? {
        guard dictationSessionID != nil, !snapshot.isEmpty else { return nil }
        return LiveTranscriptCaptionPresentation(
            header: stage == .live ? "RAW · LIVE" : "RAW · LOCKED",
            handoff: handoff,
            committed: snapshot.committed,
            tentative: snapshot.tentative,
            marksLiveFrontier: !snapshot.tentative.isEmpty,
            recedesCommitted: stage == .shaping,
            accessibilityLabel: "Raw transcript",
            accessibilityValue: accessibilityValue
        )
    }

    private var handoff: String? {
        switch stage {
        case .live, .locked: nil
        case .finalizing: "finalizing speech…"
        case .shaping: "shaping as \(modeName)…"
        }
    }

    /// The same meaning as the visual spans, said as one sentence: VoiceOver
    /// gets the stage, the settled words, the words that may still change, and
    /// what the session is doing with them.
    private var accessibilityValue: String {
        var parts = [stage == .live ? "Live" : "Locked"]
        if let committed = spoken(snapshot.committed) {
            parts.append(committed)
        }
        if let tentative = spoken(snapshot.tentative) {
            parts.append("tentative \(tentative)")
        }
        if let spokenHandoff {
            parts.append(spokenHandoff)
        }
        return parts.joined(separator: ", ")
    }

    private var spokenHandoff: String? {
        switch stage {
        case .live, .locked: nil
        case .finalizing: "finalizing speech"
        case .shaping: "shaping as \(modeName)"
        }
    }

    private func spoken(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// How the caption arrives. It fades in once when it first has words, so a
/// stream that rewrites its tail does not restart the animation.
enum LiveTranscriptCaptionMotion: Equatable {
    case fade(duration: TimeInterval)
    case cut

    static func appearance(reduceMotion: Bool) -> LiveTranscriptCaptionMotion {
        reduceMotion ? .cut : .fade(duration: 0.16)
    }
}

/// Where the caption sits: a fixed companion above the Badge, clamped to the
/// screen the Badge is on, with a tether that keeps pointing at the Badge even
/// once clamping has pushed the two apart.
enum LiveTranscriptCaptionFramePolicy {
    static let size = CGSize(width: 420, height: 82)
    /// The tether draws into this gap, so the surfaces read as connected.
    static let badgeGap: CGFloat = 2
    static let screenInset: CGFloat = 4

    struct Placement: Equatable {
        let frame: CGRect
        /// How far the tether slides from the caption's centre, in points.
        let tetherOffset: CGFloat
    }

    static func placement(badge: CGRect, screen: CGRect?) -> Placement {
        var origin = CGPoint(
            x: badge.midX - size.width / 2,
            y: badge.maxY + badgeGap
        )
        if let screen {
            origin.x = max(
                screen.minX + screenInset,
                min(origin.x, screen.maxX - size.width - screenInset)
            )
            origin.y = max(
                screen.minY + screenInset,
                min(origin.y, screen.maxY - size.height - screenInset)
            )
        }
        return Placement(
            frame: CGRect(origin: origin, size: size),
            tetherOffset: badge.midX - (origin.x + size.width / 2)
        )
    }
}
