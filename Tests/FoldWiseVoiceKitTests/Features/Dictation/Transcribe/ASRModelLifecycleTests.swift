import XCTest
@testable import FoldWiseVoiceKit

final class ASRModelLifecycleTests: XCTestCase {
    private struct DownloadFailure: LocalizedError {
        let errorDescription: String? = "disk full"
    }

    func testReconcilePublishesAvailableUnselectedModelsWithoutChangingSelection() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3", "parakeet-v2"],
            availableModelIDs: ["parakeet-v3"]
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-large-v3-turbo", "whisper-small", "whisper-large-v3"],
            availableModelIDs: ["whisper-small"]
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )

        await lifecycle.reconcileAvailability()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            ReconcileState(
                availableModelIDs: snapshot.models.filter(\.isAvailable).map(\.id),
                storedSelection: snapshot.storedSelection
            ),
            ReconcileState(
                availableModelIDs: ["parakeet-v3", "whisper-small"],
                storedSelection: "parakeet-v3"
            )
        )
    }

    func testOptionalDownloadPublishesProgressAndAvailabilityWithoutBlockingDictation() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3", "parakeet-v2"],
            availableModelIDs: ["parakeet-v3"]
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-large-v3-turbo", "whisper-small", "whisper-large-v3"],
            availableModelIDs: []
        )
        whisper.suspendDownloads = true
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )

        let download = Task { await lifecycle.download("whisper-small") }
        await whisper.waitForDownloadStart()
        whisper.reportProgress(0.6)
        let progressSnapshot = await snapshot(from: lifecycle) {
            $0.operation == .downloading(modelID: "whisper-small", fraction: 0.6)
        }

        let progressState = DownloadState(
            operation: progressSnapshot.operation,
            storedSelection: progressSnapshot.storedSelection,
            isDictationBlocked: progressSnapshot.isDictationBlocked,
            isAvailable: progressSnapshot.models.first {
                $0.id == "whisper-small"
            }?.isAvailable == true
        )

        whisper.finishDownload(availableAfterDownload: true)
        await download.value
        let completedSnapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                progressState,
                DownloadState(
                    operation: completedSnapshot.operation,
                    storedSelection: completedSnapshot.storedSelection,
                    isDictationBlocked: completedSnapshot.isDictationBlocked,
                    isAvailable: completedSnapshot.models.first {
                        $0.id == "whisper-small"
                    }?.isAvailable == true
                ),
            ],
            [
                DownloadState(
                    operation: .downloading(modelID: "whisper-small", fraction: 0.6),
                    storedSelection: "parakeet-v3",
                    isDictationBlocked: false,
                    isAvailable: false
                ),
                DownloadState(
                    operation: nil,
                    storedSelection: "parakeet-v3",
                    isDictationBlocked: false,
                    isAvailable: true
                ),
            ]
        )
    }

    func testCancelStaysSerializedUntilAdapterStopsThenReturnsToIdle() async {
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-large-v3-turbo", "whisper-small", "whisper-large-v3"],
            availableModelIDs: []
        )
        whisper.suspendDownloads = true
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [whisper]
        )

        let download = Task { await lifecycle.download("whisper-small") }
        await whisper.waitForDownloadStart()
        let cancellation = Task { await lifecycle.cancelCurrentOperation() }
        await whisper.waitForCancellationRequest()
        whisper.reportProgress(1)
        let cancelingSnapshot = await snapshot(from: lifecycle) {
            $0.operation == .downloading(modelID: "whisper-small", fraction: 1)
        }
        await lifecycle.download("whisper-large-v3")

        let cancelingState = CancellationState(
            download: DownloadState(
                operation: cancelingSnapshot.operation,
                storedSelection: cancelingSnapshot.storedSelection,
                isDictationBlocked: cancelingSnapshot.isDictationBlocked,
                isAvailable: cancelingSnapshot.models.first {
                    $0.id == "whisper-small"
                }?.isAvailable == true
            ),
            downloadedModelIDs: whisper.downloadedModelIDs,
            reusedPartialModelIDs: whisper.reusedPartialModelIDs,
            failure: cancelingSnapshot.failure
        )

        whisper.finishDownload(availableAfterDownload: false)
        await download.value
        await cancellation.value

        let completedSnapshot = await lifecycle.snapshot()
        let completedState = CancellationState(
            download: DownloadState(
                operation: completedSnapshot.operation,
                storedSelection: completedSnapshot.storedSelection,
                isDictationBlocked: completedSnapshot.isDictationBlocked,
                isAvailable: completedSnapshot.models.first {
                    $0.id == "whisper-small"
                }?.isAvailable == true
            ),
            downloadedModelIDs: whisper.downloadedModelIDs,
            reusedPartialModelIDs: whisper.reusedPartialModelIDs,
            failure: completedSnapshot.failure
        )

        let retry = Task { await lifecycle.download("whisper-small") }
        await whisper.waitForDownloadStart()
        whisper.finishDownload(availableAfterDownload: true)
        await retry.value
        let retriedSnapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                cancelingState,
                completedState,
                CancellationState(
                    download: DownloadState(
                        operation: retriedSnapshot.operation,
                        storedSelection: retriedSnapshot.storedSelection,
                        isDictationBlocked: retriedSnapshot.isDictationBlocked,
                        isAvailable: retriedSnapshot.models.first {
                            $0.id == "whisper-small"
                        }?.isAvailable == true
                    ),
                    downloadedModelIDs: whisper.downloadedModelIDs,
                    reusedPartialModelIDs: whisper.reusedPartialModelIDs,
                    failure: retriedSnapshot.failure
                ),
            ],
            [
                CancellationState(
                    download: DownloadState(
                        operation: .downloading(modelID: "whisper-small", fraction: 1),
                        storedSelection: "parakeet-v3",
                        isDictationBlocked: false,
                        isAvailable: false
                    ),
                    downloadedModelIDs: ["whisper-small"],
                    reusedPartialModelIDs: [],
                    failure: nil
                ),
                CancellationState(
                    download: DownloadState(
                        operation: nil,
                        storedSelection: "parakeet-v3",
                        isDictationBlocked: false,
                        isAvailable: false
                    ),
                    downloadedModelIDs: ["whisper-small"],
                    reusedPartialModelIDs: [],
                    failure: nil
                ),
                CancellationState(
                    download: DownloadState(
                        operation: nil,
                        storedSelection: "parakeet-v3",
                        isDictationBlocked: false,
                        isAvailable: true
                    ),
                    downloadedModelIDs: ["whisper-small", "whisper-small"],
                    reusedPartialModelIDs: ["whisper-small"],
                    failure: nil
                ),
            ]
        )
    }

    func testASecondManagementOperationCannotStartWhileDownloading() async {
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-large-v3-turbo", "whisper-small", "whisper-large-v3"],
            availableModelIDs: []
        )
        whisper.suspendDownloads = true
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [whisper]
        )

        let first = Task { await lifecycle.download("whisper-small") }
        await whisper.waitForDownloadStart()
        await lifecycle.download("whisper-large-v3")

        XCTAssertEqual(whisper.downloadedModelIDs, ["whisper-small"])
        whisper.finishDownload(availableAfterDownload: true)
        await first.value
    }

    func testSuccessfulDownloadWithInvalidDataPublishesTypedFailure() async {
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: []
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [whisper]
        )

        await lifecycle.download("whisper-small")
        let failure = await lifecycle.snapshot().failure

        XCTAssertEqual(
            failure,
            .downloadedDataInvalid(modelID: "whisper-small")
        )
    }

    func testAdapterDownloadFailurePublishesTypedFailure() async {
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: []
        )
        whisper.downloadError = DownloadFailure()
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [whisper]
        )

        await lifecycle.download("whisper-small")
        let failure = await lifecycle.snapshot().failure

        XCTAssertEqual(
            failure,
            .downloadFailed(modelID: "whisper-small", reason: "disk full")
        )
    }

    private func snapshot(
        from lifecycle: ASRModelLifecycle,
        matching predicate: @escaping @Sendable (ASRModelLifecycleSnapshot) -> Bool
    ) async -> ASRModelLifecycleSnapshot {
        for await snapshot in await lifecycle.snapshots() where predicate(snapshot) {
            return snapshot
        }
        preconditionFailure("Lifecycle snapshot stream ended")
    }

    private struct DownloadState: Equatable {
        let operation: ASRModelLifecycleOperation?
        let storedSelection: String
        let isDictationBlocked: Bool
        let isAvailable: Bool
    }

    private struct ReconcileState: Equatable {
        let availableModelIDs: [String]
        let storedSelection: String
    }

    private struct CancellationState: Equatable {
        let download: DownloadState
        let downloadedModelIDs: [String]
        let reusedPartialModelIDs: [String]
        let failure: ASRModelLifecycleFailure?
    }
}

private final class FakeASRModelFamilyAdapter: ASRModelFamilyAdapting, @unchecked Sendable {
    let modelIDs: Set<String>
    var suspendDownloads = false
    var downloadError: Error?
    var availableModelIDs: Set<String> {
        lock.withLock { _availableModelIDs }
    }

    var downloadedModelIDs: [String] {
        lock.withLock { _downloadedModelIDs }
    }

    var reusedPartialModelIDs: [String] {
        lock.withLock { _reusedPartialModelIDs }
    }

    private let lock = NSLock()
    private var _availableModelIDs: Set<String>
    private var _downloadedModelIDs: [String] = []
    private var _partialModelIDs: Set<String> = []
    private var _reusedPartialModelIDs: [String] = []
    private var activeDownloadID: String?
    private var progress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private let downloadStarted = AsyncEvent()
    private let cancellationRequested = AsyncEvent()

    init(modelIDs: Set<String>, availableModelIDs: Set<String>) {
        self.modelIDs = modelIDs
        _availableModelIDs = availableModelIDs
    }

    func isModelDataAvailable(for id: String) -> Bool {
        lock.withLock { _availableModelIDs.contains(id) }
    }

    func downloadModelData(
        for id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        lock.withLock {
            _downloadedModelIDs.append(id)
            if _partialModelIDs.contains(id) { _reusedPartialModelIDs.append(id) }
            activeDownloadID = id
            self.progress = progress
        }
        if let downloadError { throw downloadError }
        guard suspendDownloads else {
            downloadStarted.signal()
            return
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                downloadStarted.signal()
            }
        } onCancel: {
            self.lock.withLock {
                if let activeDownloadID = self.activeDownloadID {
                    self._partialModelIDs.insert(activeDownloadID)
                }
            }
            self.cancellationRequested.signal()
        }
    }

    func waitForDownloadStart() async {
        await downloadStarted.wait()
    }

    func waitForCancellationRequest() async {
        await cancellationRequested.wait()
    }

    func reportProgress(_ fraction: Double) {
        lock.withLock { progress }?(fraction)
    }

    func finishDownload(availableAfterDownload: Bool) {
        let continuation = lock.withLock {
            if availableAfterDownload, let id = _downloadedModelIDs.last {
                _availableModelIDs.insert(id)
            }
            activeDownloadID = nil
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: ())
    }
}

private final class AsyncEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingSignals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            guard !waiters.isEmpty else {
                pendingSignals += 1
                return nil
            }
            return waiters.removeFirst()
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard pendingSignals == 0 else {
                    pendingSignals -= 1
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if shouldResume { continuation.resume() }
        }
    }
}
