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
        /// The catalog restricts the entry to hardware this Mac lacks, but its
        /// family adapter built the engine anyway.
        case hardwareRestrictionNotEnforced(modelID: String)

        var description: String {
            switch self {
            case let .capabilityMismatch(modelID, advertised, actual):
                "\(modelID) advertises streaming: \(advertised) but its engine streams: \(actual)"
            case let .engineUnavailable(modelID, reason):
                "\(modelID) has no usable engine: \(reason)"
            case let .hardwareRestrictionNotEnforced(modelID):
                "\(modelID) is restricted by hardware its adapter built an engine without"
            }
        }
    }

    /// - Parameter adaptersOnUnsupportedHardware: the same families built as if
    ///   the host met none of the catalog's hardware requirements. An entry the
    ///   catalog restricts must be refused there, or its restriction is copy.
    static func audit(
        entries: [ASRModelCatalog.Entry] = ASRModelCatalog.entries,
        adapters: [any ASRModelFamilyAdapting],
        adaptersOnUnsupportedHardware: [any ASRModelFamilyAdapting] = []
    ) -> [Finding] {
        entries.flatMap { entry -> [Finding] in
            guard let adapter = adapters.first(where: { $0.modelIDs.contains(entry.id) }) else {
                return [.engineUnavailable(modelID: entry.id, reason: "No engine-family adapter.")]
            }
            do {
                let streams = try adapter.makeEngine(for: entry.id) is any StreamCapableTranscribing
                let capability: [Finding] = streams == entry.streaming
                    ? []
                    : [.capabilityMismatch(
                        modelID: entry.id,
                        advertised: entry.streaming,
                        actual: streams
                    )]
                return capability + hardwareFindings(
                    for: entry,
                    adapters: adaptersOnUnsupportedHardware
                )
            } catch {
                return [.engineUnavailable(
                    modelID: entry.id,
                    reason: error.localizedDescription
                )]
            }
        }
    }

    private static func hardwareFindings(
        for entry: ASRModelCatalog.Entry,
        adapters: [any ASRModelFamilyAdapting]
    ) -> [Finding] {
        guard entry.hardware != .anyMac,
              let adapter = adapters.first(where: { $0.modelIDs.contains(entry.id) }),
              (try? adapter.makeEngine(for: entry.id)) != nil else { return [] }
        return [.hardwareRestrictionNotEnforced(modelID: entry.id)]
    }
}
