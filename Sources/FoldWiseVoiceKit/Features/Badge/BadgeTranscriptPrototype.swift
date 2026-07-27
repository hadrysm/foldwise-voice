#if BADGE_TRANSCRIPT_PROTOTYPE

    // PROTOTYPE — throw away after issue #346 answers the Badge preview question.
    // The selected caption treatment stays separate from the Badge while the
    // real Dictation pipeline drives both surfaces through their phases.

    import Combine
    import Foundation

    enum BadgeTranscriptPrototypePhase: Equatable {
        case idle
        case listening
        case transcribing
        case polishing
        case finished
        case failed

        var presentsPreview: Bool {
            switch self {
            case .listening, .transcribing, .polishing: true
            case .idle, .finished, .failed: false
            }
        }
    }

    final class BadgeTranscriptPrototypeModel: ObservableObject {
        @Published private(set) var phase: BadgeTranscriptPrototypePhase = .idle
        @Published private(set) var confirmed = ""
        @Published private(set) var tentative = ""
        @Published private(set) var modeName = "Email"
        @Published private(set) var captionTetherOffset: CGFloat = 0

        private struct Step {
            let time: TimeInterval
            let confirmed: String
            let tentative: String
        }

        /// Directional EOU 320 simulation: first non-empty text at ~1 second,
        /// lowercase/unpunctuated output, and trailing words that revise as right
        /// context arrives. The final step is deliberately long enough to exercise
        /// the caption's overflow behaviour.
        private static let steps = [
            Step(time: 1.0, confirmed: "", tentative: "hey sam"),
            Step(time: 1.7, confirmed: "hey sam i", tentative: "wanted to"),
            Step(
                time: 2.4,
                confirmed: "hey sam i wanted to see",
                tentative: "if we"
            ),
            Step(
                time: 3.1,
                confirmed: "hey sam i wanted to see if we can move",
                tentative: "our catch"
            ),
            Step(
                time: 3.8,
                confirmed: "hey sam i wanted to see if we can move our catch-up",
                tentative: "from thurs"
            ),
            Step(
                time: 4.5,
                confirmed: "hey sam i wanted to see if we can move our catch-up from thursday",
                tentative: "to friday after"
            ),
            Step(
                time: 5.2,
                confirmed: "hey sam i wanted to see if we can move our catch-up from thursday to friday afternoon",
                tentative: "because the"
            ),
            Step(
                time: 6.1,
                confirmed: "hey sam i wanted to see if we can move our catch-up "
                    + "from thursday to friday afternoon because the",
                tentative: "client review ran"
            ),
            Step(
                time: 7.0,
                confirmed: "hey sam i wanted to see if we can move our catch-up "
                    + "from thursday to friday afternoon because the client review ran",
                tentative: "a bit long"
            ),
        ]

        var fullTranscript: String {
            [confirmed, tentative]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        func apply(_ pipelineState: PipelineState, modeName: String) {
            self.modeName = modeName
            switch pipelineState {
            case .listening:
                guard phase != .listening else { return }
                phase = .listening
                confirmed = ""
                tentative = ""
            case .transcribing:
                phase = .transcribing
                settleTentative()
            case .polishing:
                phase = .polishing
                settleTentative()
            case .inserted, .clipboard:
                phase = .finished
            case .error:
                phase = .failed
            case .idle:
                phase = .idle
            case .downloadingModel, .loadingModel, .switchingASRModel,
                 .recognitionUnavailable:
                break
            }
        }

        func advance(elapsed: TimeInterval) {
            guard phase == .listening,
                  let step = Self.steps.last(where: { elapsed >= $0.time })
            else {
                return
            }
            guard confirmed != step.confirmed || tentative != step.tentative else {
                return
            }
            confirmed = step.confirmed
            tentative = step.tentative
        }

        func setCaptionTetherOffset(_ offset: CGFloat) {
            guard abs(captionTetherOffset - offset) >= 0.5 else { return }
            captionTetherOffset = offset
        }

        private func settleTentative() {
            confirmed = fullTranscript
            tentative = ""
        }
    }

#endif
