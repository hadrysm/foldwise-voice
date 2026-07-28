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
            ]
        )

        XCTAssertEqual(findings, [], findings.map(\.description).joined(separator: "; "))
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
