// Id → entry resolution for the ASR catalog, mirroring how `ModelCatalog`
// resolves Ollama model names. The catalog is our own stable id vocabulary
// (ADR-0006), so an old `mlx-community/...` fossil id resolves to no entry and
// falls back to the Parakeet engine.

import XCTest
@testable import FoldWiseVoiceKit

final class ASRModelCatalogTests: XCTestCase {
    func testResolvesKnownParakeetID() {
        let entry = ASRModelCatalog.entry(for: "parakeet-v3")
        XCTAssertEqual(entry?.id, "parakeet-v3")
        XCTAssertEqual(entry?.engine, .parakeet(version: .v3))
    }

    func testResolvesParakeetV2ToTheEnglishOnlyCheckpoint() {
        let entry = ASRModelCatalog.entry(for: "parakeet-v2")
        XCTAssertEqual(entry?.engine, .parakeet(version: .v2))
        XCTAssertEqual(entry?.languages, "English")
    }

    func testResolvesWhisperSmallToItsVariant() {
        let entry = ASRModelCatalog.entry(for: "whisper-small")
        XCTAssertEqual(entry?.engine, .whisper(variant: "openai_whisper-small"))
    }

    func testDefaultIDIsAKnownEntry() {
        XCTAssertNotNil(ASRModelCatalog.entry(for: ASRModelCatalog.defaultID))
    }

    func testUnknownFossilIDResolvesToNoEntry() {
        XCTAssertNil(ASRModelCatalog.entry(for: "mlx-community/whisper-large-v3-turbo"))
    }

    func testLookupNormalizesCanonicalIDWhitespaceAndCase() {
        let entry = ASRModelCatalog.entry(for: "  WHISPER-SMALL\n")
        XCTAssertEqual(entry?.id, "whisper-small")
    }

    func testLookupResolvesEngineCheckpointAlias() {
        let entry = ASRModelCatalog.entry(
            for: "openai_whisper-large-v3-v20240930_turbo_632MB"
        )
        XCTAssertEqual(entry?.id, "whisper-large-v3-turbo")
    }

    func testMalformedIdentifierResolvesToNoEntry() {
        XCTAssertNil(ASRModelCatalog.entry(for: "whisper-small/../../"))
    }

    func testUnknownIDFallsBackToParakeetEngine() {
        XCTAssertEqual(
            ASRModelCatalog.engine(forSelected: "mlx-community/whisper-large-v3-turbo"),
            .parakeet(version: .v3)
        )
    }

    func testKnownIDResolvesToItsEngine() {
        XCTAssertEqual(ASRModelCatalog.engine(forSelected: "parakeet-v3"), .parakeet(version: .v3))
    }

    func testResolvesWhisperTurboToItsEngineAndVariant() {
        let entry = ASRModelCatalog.entry(for: "whisper-large-v3-turbo")
        XCTAssertEqual(entry?.id, "whisper-large-v3-turbo")
        XCTAssertEqual(
            entry?.engine,
            .whisper(variant: "openai_whisper-large-v3-v20240930_turbo_632MB")
        )
    }

    func testWhisperEngineResolvesFromSelectedID() {
        XCTAssertEqual(
            ASRModelCatalog.engine(forSelected: "whisper-large-v3-turbo"),
            .whisper(variant: "openai_whisper-large-v3-v20240930_turbo_632MB")
        )
    }

    func testCatalogListsTheFullCuratedRoster() {
        XCTAssertEqual(
            ASRModelCatalog.entries.map(\.id),
            [
                "parakeet-v3", "parakeet-v2", "parakeet-eou-320", "nemotron-560",
                "whisper-large-v3-turbo", "whisper-small", "whisper-large-v3",
            ]
        )
    }

    // MARK: - EOU 320, the first Streaming ASR model (ADR-0009)

    private var eou: ASRModelCatalog.Entry {
        // Force-unwrap: the entry is a compile-time-constant catalog member.
        // swiftlint:disable:next force_unwrapping
        ASRModelCatalog.entry(for: "parakeet-eou-320")!
    }

    func testResolvesEouToItsStreamingCheckpoint() {
        XCTAssertEqual(eou.engine, .streaming(variant: .parakeetEou320))
    }

    func testOnlyTheStreamingEntriesAdvertiseStreaming() {
        XCTAssertEqual(
            ASRModelCatalog.entries.filter(\.streaming).map(\.id),
            ["parakeet-eou-320", "nemotron-560"]
        )
    }

    func testEouStatesItsEnglishOnlyCoverage() {
        XCTAssertEqual(eou.languages, "English")
    }

    /// The pinned downloader transfers roughly twice EOU's ~224 MB logical
    /// required set, and the size a user reads is what actually crosses the wire.
    func testEouSizeIsWhatThePinnedDownloaderTransfers() {
        XCTAssertEqual(eou.size, "448 MB")
    }

    func testEouBlurbCallsOutItsLowercaseUnpunctuatedOutput() {
        XCTAssertTrue(
            eou.blurb.contains("lowercase and unpunctuated"),
            "EOU's honest raw output is not stated: \(eou.blurb)"
        )
    }

    func testEouBlurbCallsOutTheDownloaderOverTransfer() {
        XCTAssertTrue(
            eou.blurb.contains("about 224 MB") && eou.blurb.contains("about 448 MB"),
            "EOU's over-transfer is not stated: \(eou.blurb)"
        )
    }

    // MARK: - Nemotron 560, the punctuated Streaming ASR model (ADR-0009)

    private var nemotron: ASRModelCatalog.Entry {
        // Force-unwrap: the entry is a compile-time-constant catalog member.
        // swiftlint:disable:next force_unwrapping
        ASRModelCatalog.entry(for: "nemotron-560")!
    }

    func testResolvesNemotronToItsStreamingCheckpoint() {
        XCTAssertEqual(nemotron.engine, .streaming(variant: .nemotron560))
    }

    func testNemotronStatesItsEnglishOnlyCoverage() {
        XCTAssertEqual(nemotron.languages, "English")
    }

    /// The 560 ms tier transfers a measured 626.4 MB; the copy rounds up so the
    /// number never promises a smaller download than the one that happens.
    func testNemotronSizeIsRoundedUpFromWhatItTransfers() {
        XCTAssertEqual(nemotron.size, "627 MB")
    }

    func testNemotronBlurbCallsOutItsPunctuatedOutput() {
        XCTAssertTrue(
            nemotron.blurb.contains("capitalized and punctuated"),
            "Nemotron's output shape is not stated: \(nemotron.blurb)"
        )
    }

    func testNemotronBlurbCallsOutItsAppleSiliconRequirement() {
        XCTAssertTrue(
            nemotron.blurb.contains("Apple silicon") && nemotron.blurb.contains("Intel"),
            "Nemotron's hardware requirement is not stated: \(nemotron.blurb)"
        )
    }

    func testNemotronBlurbCallsOutItsMemoryCost() {
        XCTAssertTrue(
            nemotron.blurb.contains("about 1.2 GB of memory"),
            "Nemotron's memory tradeoff is not stated: \(nemotron.blurb)"
        )
    }

    func testNemotronRequiresAppleSilicon() {
        XCTAssertEqual(nemotron.hardware, .appleSilicon)
    }

    func testEveryOtherEntryRunsOnAnyMac() {
        XCTAssertEqual(
            ASRModelCatalog.entries.filter { $0.hardware == .appleSilicon }.map(\.id),
            ["nemotron-560"]
        )
    }

    // MARK: - hardware requirements

    func testAppleSiliconRequirementIsUnmetOnAnIntelMac() {
        XCTAssertFalse(ASRModelCatalog.HardwareRequirement.appleSilicon.isMet(byAppleSilicon: false))
    }

    func testAppleSiliconRequirementIsMetOnAppleSilicon() {
        XCTAssertTrue(ASRModelCatalog.HardwareRequirement.appleSilicon.isMet(byAppleSilicon: true))
    }

    func testAnyMacRequirementIsMetOnAnIntelMac() {
        XCTAssertTrue(ASRModelCatalog.HardwareRequirement.anyMac.isMet(byAppleSilicon: false))
    }

    func testAnyMacRequirementNamesNoMissingHardware() {
        XCTAssertNil(ASRModelCatalog.HardwareRequirement.anyMac.missingHardware)
    }

    func testAppleSiliconRequirementNamesWhatAMacIsMissing() {
        XCTAssertEqual(
            ASRModelCatalog.HardwareRequirement.appleSilicon.missingHardware,
            "Apple silicon"
        )
    }

    func testDefaultRemainsANonStreamingModel() {
        XCTAssertEqual(ASRModelCatalog.entry(for: ASRModelCatalog.defaultID)?.streaming, false)
    }

    /// No Whisper `.en` entries and no tiny/base tier: the roster stays
    /// multilingual-led so Whisper's language reach is the headline (ADR-0006).
    func testCatalogExcludesEnglishOnlyWhisperAndTinyBaseTiers() {
        for entry in ASRModelCatalog.entries {
            if case let .whisper(variant) = entry.engine {
                XCTAssertFalse(variant.contains(".en"), "\(variant) is an English-only Whisper")
                XCTAssertFalse(variant.contains("tiny"), "\(variant) is a tiny-tier Whisper")
                XCTAssertFalse(variant.contains("base"), "\(variant) is a base-tier Whisper")
            }
        }
    }

    // MARK: - download outcome (pure, mirrors OllamaDeleteOutcomeTests)

    private var whisper: ASRModelCatalog.Entry {
        // Force-unwrap: the entry is a compile-time-constant catalog member.
        // swiftlint:disable:next force_unwrapping
        ASRModelCatalog.entry(for: "whisper-large-v3-turbo")!
    }

    func testDownloadSuccessMapsToNoError() {
        XCTAssertNil(ASRModelCatalog.downloadError(for: whisper, failure: nil))
    }

    func testEmptyFailureMapsToNoError() {
        XCTAssertNil(ASRModelCatalog.downloadError(for: whisper, failure: ""))
    }

    func testFailureMapsToNamedError() {
        let message = ASRModelCatalog.downloadError(for: whisper, failure: "network down")
        XCTAssertEqual(message, "Couldn't download Whisper large-v3-turbo: network down")
    }
}
