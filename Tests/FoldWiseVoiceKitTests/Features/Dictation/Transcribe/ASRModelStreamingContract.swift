// Runtime streaming capability is adapter conformance, never the catalog's
// `streaming` flag (ADR-0009): the flag drives the Models pane's copy, the
// engine's type drives behavior. This audit is the seam that holds the two to
// account for every catalog entry, so a model can never be advertised as
// streaming when its engine cannot stream. It lives in the test target because
// the agreement is an invariant the suite enforces, not a decision the app makes.
//
// It builds each entry's engine, which is cheap: an engine records its variant
// in `init` and loads model data only in `prepare()`.

import Foundation
@testable import FoldWiseVoiceKit

enum ASRModelStreamingContract {
    enum Finding: Equatable, CustomStringConvertible {
        /// The catalog's presentation flag and the engine's type disagree.
        case capabilityMismatch(modelID: String, advertised: Bool, actual: Bool)
        /// No adapter could build the entry's engine, so its advertised
        /// capability cannot be honored at all.
        case engineUnavailable(modelID: String, reason: String)

        var description: String {
            switch self {
            case let .capabilityMismatch(modelID, advertised, actual):
                "\(modelID) advertises streaming: \(advertised) but its engine streams: \(actual)"
            case let .engineUnavailable(modelID, reason):
                "\(modelID) has no usable engine: \(reason)"
            }
        }
    }

    static func audit(
        entries: [ASRModelCatalog.Entry] = ASRModelCatalog.entries,
        adapters: [any ASRModelFamilyAdapting]
    ) -> [Finding] {
        entries.compactMap { entry in
            guard let adapter = adapters.first(where: { $0.modelIDs.contains(entry.id) }) else {
                return .engineUnavailable(modelID: entry.id, reason: "No engine-family adapter.")
            }
            do {
                let streams = try adapter.makeEngine(for: entry.id) is any StreamCapableTranscribing
                guard streams != entry.streaming else { return nil }
                return .capabilityMismatch(
                    modelID: entry.id,
                    advertised: entry.streaming,
                    actual: streams
                )
            } catch {
                return .engineUnavailable(
                    modelID: entry.id,
                    reason: error.localizedDescription
                )
            }
        }
    }
}
