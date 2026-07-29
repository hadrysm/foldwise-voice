import XCTest
@testable import FoldWiseVoiceKit

/// What a Dictation session learns about streaming from its captured ASR session
/// handle: a yes/no capability and the operations to drive it — never which
/// model or engine the lifecycle activated (ADR-0009).
final class ASRSessionStreamingCapabilityTests: XCTestCase {
    func testBatchSessionReportsNoStreamingCapability() async throws {
        let handle = try await captureSession(from: BatchCapabilityAdapter())

        XCTAssertFalse(handle.canStream)
    }

    func testBatchSessionRefusesToOpenAStream() async throws {
        let handle = try await captureSession(from: BatchCapabilityAdapter())

        do {
            _ = try await handle.makeStream()
            XCTFail("A batch model must not hand out a live stream.")
        } catch {
            XCTAssertEqual(error as? TranscriptStreamError, .streamingUnavailable)
        }
    }

    func testStreamingSessionReportsItsCapability() async throws {
        let handle = try await captureSession(from: StreamingCapabilityAdapter())

        XCTAssertTrue(handle.canStream)
    }

    func testStreamingSessionFinalizesThroughItsOwnStream() async throws {
        let adapter = StreamingCapabilityAdapter()
        adapter.manager.finishResult = .success("The quick brown fox.")
        let handle = try await captureSession(from: adapter)

        let stream = try await handle.makeStream()
        try await stream.append([0.1])

        let final = try await stream.finish()
        XCTAssertEqual(final, "The quick brown fox.")
    }

    func testStreamingSessionPublishesSnapshotsWhileRecording() async throws {
        let adapter = StreamingCapabilityAdapter()
        let collected = SnapshotCollector()
        let handle = try await captureSession(from: adapter)
        let stream = try await handle.makeStream()
        stream.deliverSnapshots(to: { collected.append($0) })

        adapter.manager.reportTentative("the quick brown")

        XCTAssertEqual(collected.snapshots.map(\.text), ["the quick brown"])
    }

    func testReleasedSessionReportsNoStreamingCapability() async throws {
        let handle = try await captureSession(from: StreamingCapabilityAdapter())

        handle.release()

        XCTAssertFalse(handle.canStream)
    }

    func testReleasedSessionRefusesToOpenAStream() async throws {
        let handle = try await captureSession(from: StreamingCapabilityAdapter())
        handle.release()

        do {
            _ = try await handle.makeStream()
            XCTFail("A released session must not open a stream on a dropped engine.")
        } catch {
            XCTAssertEqual(error as? ASRModelLifecycleError, .recognitionBlocked)
        }
    }

    func testReleasingASessionAbandonsItsOpenStream() async throws {
        let handle = try await captureSession(from: StreamingCapabilityAdapter())
        let stream = try await handle.makeStream()

        handle.release()

        do {
            _ = try await stream.finish()
            XCTFail("An abandoned attempt must not finalize.")
        } catch {
            XCTAssertEqual(error as? TranscriptStreamError, .streamClosed)
        }
    }

    /// A handle that conforms without implementing either streaming member,
    /// pinning what every batch conformer inherits.
    func testHandleWithoutStreamingMembersReportsNoCapability() {
        XCTAssertFalse(InertSessionHandle().canStream)
    }

    func testHandleWithoutStreamingMembersRefusesToOpenAStream() async {
        do {
            _ = try await InertSessionHandle().makeStream()
            XCTFail("A batch conformer must not hand out a live stream.")
        } catch {
            XCTAssertEqual(error as? TranscriptStreamError, .streamingUnavailable)
        }
    }

    // MARK: - Reaching streaming through ordinary ASR model selection

    /// Streaming becomes reachable the same way any other model does: the user
    /// selects it, and the session the next Dictation captures answers yes.
    func testSelectingAStreamingCatalogModelMakesTheNextSessionStream() async throws {
        let lifecycle = mixedFamilyLifecycle()
        await lifecycle.start()

        await lifecycle.select("parakeet-eou-320")

        XCTAssertTrue(try lifecycle.captureSession().canStream)
    }

    /// Switching back leaves the next Dictation session usable and non-streaming,
    /// because exactly one engine stays resident (ADR-0005).
    func testSwitchingBackToTheDefaultRestoresABatchSession() async throws {
        let lifecycle = mixedFamilyLifecycle()
        await lifecycle.start()
        await lifecycle.select("parakeet-eou-320")

        await lifecycle.select(ASRModelCatalog.defaultID)

        let handle = try lifecycle.captureSession()
        let streams = handle.canStream
        let transcript = try await handle.transcribe([0.1])
        XCTAssertEqual(
            RestoredSession(streams: streams, transcript: transcript),
            RestoredSession(streams: false, transcript: "batch")
        )
    }

    func testDownloadingAStreamingModelDoesNotSelectIt() async throws {
        let lifecycle = mixedFamilyLifecycle()
        await lifecycle.start()

        await lifecycle.download("parakeet-eou-320")

        XCTAssertFalse(try lifecycle.captureSession().canStream)
    }

    private func mixedFamilyLifecycle() -> ASRModelLifecycle {
        ASRModelLifecycle(
            storedSelection: ASRModelCatalog.defaultID,
            adapters: [
                BatchCapabilityAdapter(),
                StreamingCapabilityAdapter(modelIDs: ["parakeet-eou-320"]),
            ]
        )
    }

    private func captureSession(
        from adapter: any ASRModelFamilyAdapting
    ) async throws -> any ASRSessionHandle {
        let lifecycle = ASRModelLifecycle(
            storedSelection: ASRModelCatalog.defaultID,
            adapters: [adapter]
        )
        await lifecycle.start()
        return try lifecycle.captureSession()
    }
}

private struct RestoredSession: Equatable {
    let streams: Bool
    let transcript: String
}

private final class InertSessionHandle: ASRSessionHandle {
    func transcribe(_: [Float]) async throws -> String {
        ""
    }

    func release() {}
}

private struct BatchCapabilityAdapter: ASRModelFamilyAdapting {
    let modelIDs: Set<String> = [ASRModelCatalog.defaultID]

    func isModelDataAvailable(for _: String) -> Bool {
        true
    }

    func downloadModelData(
        for _: String,
        progress _: @escaping @Sendable (Double) -> Void
    ) async throws {}

    func makeEngine(for _: String) throws -> Transcribing {
        BatchCapabilityEngine()
    }

    func removeModelData(for _: String) async throws {}
}

private final class BatchCapabilityEngine: Transcribing {
    func prepare() async throws {}

    func transcribe(_: [Float]) async throws -> String {
        "batch"
    }
}
