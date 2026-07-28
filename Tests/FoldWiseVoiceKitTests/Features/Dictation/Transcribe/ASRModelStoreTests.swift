// Pins the library-coupled cache paths and deletion behavior without accessing
// downloaded model weights. Filesystem tests stay inside a throwaway directory.

import XCTest
@testable import FoldWiseVoiceKit

final class ASRModelStoreTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testWhisperResolvesToTheHuggingFaceHubCache() throws {
        let dir = try XCTUnwrap(
            ASRModelStore.modelDirectory(for: .whisper(variant: "openai_whisper-small"))
        )
        XCTAssertTrue(
            dir.path.hasSuffix(
                "huggingface/models/argmaxinc/whisperkit-coreml/openai_whisper-small"
            ),
            "unexpected Whisper cache path: \(dir.path)"
        )
    }

    func testParakeetResolvesToItsFluidAudioCheckpointFolder() throws {
        let dir = try XCTUnwrap(ASRModelStore.modelDirectory(for: .parakeet(version: .v2)))
        XCTAssertTrue(
            dir.path.contains("FluidAudio/Models/parakeet-tdt-0.6b-v2"),
            "unexpected Parakeet cache path: \(dir.path)"
        )
    }

    func testParakeetV2AndV3ResolveToDistinctFolders() throws {
        let v2 = try XCTUnwrap(ASRModelStore.modelDirectory(for: .parakeet(version: .v2)))
        let v3 = try XCTUnwrap(ASRModelStore.modelDirectory(for: .parakeet(version: .v3)))
        XCTAssertNotEqual(v2, v3)
    }

    func testStreamingResolvesToItsChunkTierFolder() throws {
        let dir = try XCTUnwrap(
            ASRModelStore.modelDirectory(for: .streaming(variant: .parakeetEou320))
        )
        XCTAssertTrue(
            dir.path.hasSuffix("FluidAudio/Models/parakeet-eou-streaming/320ms"),
            "unexpected EOU cache path: \(dir.path)"
        )
    }

    /// The pinned downloader re-appends the repository's own nested folder name,
    /// so the destination is the shared models root — one level above what the
    /// Parakeet checkpoints pass, and getting it wrong nests the tier twice.
    func testStreamingDownloadsIntoTheSharedModelsRoot() throws {
        let dir = try XCTUnwrap(
            ASRModelStore.modelDirectory(for: .streaming(variant: .parakeetEou320))
        )
        XCTAssertEqual(
            ASRModelStore.streamingDownloadRoot().standardizedFileURL,
            dir.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL
        )
    }

    func testStreamingAndParakeetResolveToDistinctFolders() throws {
        let streaming = try XCTUnwrap(
            ASRModelStore.modelDirectory(for: .streaming(variant: .parakeetEou320))
        )
        let parakeet = try XCTUnwrap(ASRModelStore.modelDirectory(for: .parakeet(version: .v3)))
        XCTAssertNotEqual(streaming, parakeet)
    }

    func testDeleteReportsUnresolvableModelDirectory() {
        let error = ASRModelStore.delete(
            .whisper(variant: "missing"),
            userDocumentsDirectory: nil
        )

        XCTAssertEqual(error, "Couldn't locate the model files to delete.")
    }

    func testDeleteTreatsAlreadyAbsentWeightsAsSuccess() {
        let error = ASRModelStore.delete(
            .whisper(variant: "missing"),
            userDocumentsDirectory: dir
        )

        XCTAssertNil(error)
    }

    func testDeleteRemovesDownloadedWeights() throws {
        let downloaded = try XCTUnwrap(
            ASRModelStore.modelDirectory(
                for: .whisper(variant: "downloaded"),
                userDocumentsDirectory: dir
            )
        )
        try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)

        let error = ASRModelStore.delete(
            .whisper(variant: "downloaded"),
            userDocumentsDirectory: dir
        )

        XCTAssertNil(error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.path))
    }

    func testDeleteReportsFilesystemFailure() throws {
        let downloaded = try XCTUnwrap(
            ASRModelStore.modelDirectory(
                for: .whisper(variant: "downloaded"),
                userDocumentsDirectory: dir
            )
        )
        try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)

        let error = ASRModelStore.delete(
            .whisper(variant: "downloaded"),
            userDocumentsDirectory: dir,
            removeItem: { _ in throw RemovalError.denied }
        )

        XCTAssertEqual(error, RemovalError.denied.localizedDescription)
    }
}

private enum RemovalError: LocalizedError {
    case denied

    var errorDescription: String? {
        "permission denied"
    }
}
