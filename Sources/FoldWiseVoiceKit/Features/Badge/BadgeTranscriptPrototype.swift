#if BADGE_TRANSCRIPT_PROTOTYPE

    // PROTOTYPE — throw away after issue #346 answers the Badge preview question.
    // Three live-transcript treatments are switchable from a non-activating
    // companion control while the real Dictation pipeline drives Badge phases.

    import Combine
    import Foundation

    enum BadgeTranscriptPrototypeVariant: String, CaseIterable {
        case ticker = "A"
        case caption = "B"
        case stack = "C"

        var name: String {
            switch self {
            case .ticker: "Ticker"
            case .caption: "Caption"
            case .stack: "Stack"
            }
        }

        var next: Self {
            let variants = Self.allCases
            let index = variants.firstIndex(of: self) ?? 0
            return variants[(index + 1) % variants.count]
        }

        var previous: Self {
            let variants = Self.allCases
            let index = variants.firstIndex(of: self) ?? 0
            return variants[(index - 1 + variants.count) % variants.count]
        }
    }

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
        @Published var variant: BadgeTranscriptPrototypeVariant = .ticker
        @Published private(set) var phase: BadgeTranscriptPrototypePhase = .idle
        @Published private(set) var confirmed = ""
        @Published private(set) var tentative = ""
        @Published private(set) var modeName = "Email"

        private struct Step {
            let time: TimeInterval
            let confirmed: String
            let tentative: String
        }

        /// Directional EOU 320 simulation: first non-empty text at ~1 second,
        /// lowercase/unpunctuated output, and trailing words that revise as right
        /// context arrives. The final step is deliberately long enough to exercise
        /// each variant's overflow behaviour.
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

        private func settleTentative() {
            confirmed = fullTranscript
            tentative = ""
        }
    }

#endif
