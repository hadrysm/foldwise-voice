// Pins the on-disk cache-path resolution for the ASR engines (slice 5, #95) —
// the one library-coupled seam. These assert the path *shape* each library
// downloads into, without touching the filesystem, so a library changing its
// storage layout is caught here rather than by a delete that silently frees
// nothing. Deletion itself is I/O at the boundary and isn't unit-tested.

import XCTest
@testable import FoldWiseVoiceKit

final class ASRModelStoreTests: XCTestCase {
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
}
