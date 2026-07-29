import XCTest
@testable import FoldWiseVoiceKit

/// Holds the catalog's streaming flag and its engines' actual capability to
/// account, so no ASR model can be advertised as streaming when its engine
/// cannot stream (ADR-0009).
final class ASRModelStreamingContractTests: XCTestCase {
    func testShippedCatalogAgreesWithItsEngines() {
        let findings = ASRModelStreamingContract.audit(
            adapters: [
                ParakeetASRModelAdapter(),
                StreamingASRModelAdapter(),
                WhisperASRModelAdapter(),
            ],
            adaptersOnUnsupportedHardware: [
                ParakeetASRModelAdapter(),
                StreamingASRModelAdapter(hostIsAppleSilicon: false),
                WhisperASRModelAdapter(),
            ]
        )

        XCTAssertEqual(findings, [], findings.map(\.description).joined(separator: "; "))
    }

    func testHardwareRestrictedEntryBuiltOnUnsupportedHardwareIsReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [restrictedEntry(id: "nemotron-560")],
            adapters: [ContractAdapter(modelIDs: ["nemotron-560"], streams: true)],
            adaptersOnUnsupportedHardware: [
                ContractAdapter(modelIDs: ["nemotron-560"], streams: true),
            ]
        )

        XCTAssertEqual(findings, [.hardwareRestrictionNotEnforced(modelID: "nemotron-560")])
    }

    func testHardwareRestrictedEntryRefusedOnUnsupportedHardwareIsNotReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [restrictedEntry(id: "nemotron-560")],
            adapters: [ContractAdapter(modelIDs: ["nemotron-560"], streams: true)],
            adaptersOnUnsupportedHardware: [
                ContractAdapter(modelIDs: ["nemotron-560"], streams: true, failsToBuild: true),
            ]
        )

        XCTAssertEqual(findings, [])
    }

    /// The restriction is the engine's, so an entry running on any Mac is not
    /// expected to be refused anywhere.
    func testUnrestrictedEntryBuiltOnUnsupportedHardwareIsNotReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [entry(id: "parakeet-eou-320", streaming: true)],
            adapters: [ContractAdapter(modelIDs: ["parakeet-eou-320"], streams: true)],
            adaptersOnUnsupportedHardware: [
                ContractAdapter(modelIDs: ["parakeet-eou-320"], streams: true),
            ]
        )

        XCTAssertEqual(findings, [])
    }

    /// Built from the shipped Apple-silicon-only entry, because the requirement
    /// follows the engine the id names rather than anything a fixture can set.
    private func restrictedEntry(id: String) -> ASRModelCatalog.Entry {
        ASRModelCatalog.Entry(
            id: id,
            engine: .streaming(variant: .nemotron560),
            name: id,
            languages: "English",
            size: "627 MB",
            speed: 4,
            quality: 4,
            streaming: true,
            translate: false,
            blurb: "A fixture."
        )
    }

    func testStreamingClaimOverABatchEngineIsReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [entry(id: "pretender", streaming: true)],
            adapters: [ContractAdapter(modelIDs: ["pretender"], streams: false)]
        )

        XCTAssertEqual(
            findings,
            [.capabilityMismatch(modelID: "pretender", advertised: true, actual: false)]
        )
    }

    func testStreamingEngineHiddenAsBatchIsReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [entry(id: "quiet-streamer", streaming: false)],
            adapters: [ContractAdapter(modelIDs: ["quiet-streamer"], streams: true)]
        )

        XCTAssertEqual(
            findings,
            [.capabilityMismatch(modelID: "quiet-streamer", advertised: false, actual: true)]
        )
    }

    func testEntryWithNoAdapterIsReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [entry(id: "orphan", streaming: true)],
            adapters: []
        )

        XCTAssertEqual(
            findings,
            [.engineUnavailable(modelID: "orphan", reason: "No engine-family adapter.")]
        )
    }

    func testEntryWhoseEngineCannotBeBuiltIsReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [entry(id: "broken", streaming: true)],
            adapters: [ContractAdapter(modelIDs: ["broken"], streams: true, failsToBuild: true)]
        )

        XCTAssertEqual(
            findings,
            [.engineUnavailable(
                modelID: "broken",
                reason: ContractFailure().localizedDescription
            )]
        )
    }

    func testAgreeingEntryIsNotReported() {
        let findings = ASRModelStreamingContract.audit(
            entries: [entry(id: "honest-streamer", streaming: true)],
            adapters: [ContractAdapter(modelIDs: ["honest-streamer"], streams: true)]
        )

        XCTAssertEqual(findings, [])
    }

    private func entry(id: String, streaming: Bool) -> ASRModelCatalog.Entry {
        ASRModelCatalog.Entry(
            id: id,
            engine: .parakeet(version: .v3),
            name: id,
            languages: "English",
            size: "1 MB",
            speed: 5,
            quality: 5,
            streaming: streaming,
            translate: false,
            blurb: "A fixture."
        )
    }
}

private struct ContractAdapter: ASRModelFamilyAdapting {
    let modelIDs: Set<String>
    let streams: Bool
    var failsToBuild = false

    func isModelDataAvailable(for _: String) -> Bool {
        true
    }

    func downloadModelData(
        for _: String,
        progress _: @escaping @Sendable (Double) -> Void
    ) async throws {}

    func makeEngine(for _: String) throws -> Transcribing {
        if failsToBuild {
            throw ContractFailure()
        }
        return streams
            ? StreamingTranscriber(makeManager: { FakeStreamingASRManager() })
            : ContractBatchEngine()
    }

    func removeModelData(for _: String) async throws {}
}

private final class ContractBatchEngine: Transcribing {
    func prepare() async throws {}

    func transcribe(_: [Float]) async throws -> String {
        ""
    }
}

private struct ContractFailure: Error {}
