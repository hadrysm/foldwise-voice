import XCTest
@testable import FoldWiseVoiceKit

private struct EngineConstructionFailure: LocalizedError {
    let errorDescription: String?

    init(modelID: String) {
        errorDescription = "No ASR engine can be constructed for \(modelID)."
    }
}

final class ASRModelLifecycleTests: XCTestCase {
    private struct DownloadFailure: LocalizedError {
        let errorDescription: String? = "disk full"
    }

    private struct EngineFailure: LocalizedError {
        let errorDescription: String? = "model data rejected"
    }

    private struct SelectionPersistenceFailure: LocalizedError {
        let errorDescription: String? = "config write failed"
    }

    private struct DeletionFailure: LocalizedError {
        let errorDescription: String? = "permission denied"
    }

    func testInitialSnapshotAndSessionProviderBothBlockUntilStartupCompletes() async {
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [
                FakeASRModelFamilyAdapter(
                    modelIDs: ["parakeet-v3"],
                    availableModelIDs: ["parakeet-v3"]
                ),
            ]
        )
        let sessionProvider: ASRSessionHandleProviding = lifecycle

        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            InitialBlockingState(
                snapshotIsBlocked: snapshot.isDictationBlocked,
                providerIsBlocked: sessionProvider.isDictationBlocked,
                effectiveSelection: snapshot.effectiveSelection
            ),
            InitialBlockingState(
                snapshotIsBlocked: true,
                providerIsBlocked: true,
                effectiveSelection: nil
            )
        )
    }

    func testUnavailableStoredSelectionUsesDefaultWithoutChangingStoredSelection() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3", "parakeet-v2"],
            availableModelIDs: ["parakeet-v3"]
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: []
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )

        await lifecycle.start()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            EffectiveSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                recovery: snapshot.recovery,
                loadedModelIDs: parakeet.loadedModelIDs + whisper.loadedModelIDs
            ),
            EffectiveSelectionState(
                storedSelection: "whisper-small",
                effectiveSelection: "parakeet-v3",
                recovery: .storedSelectionUnavailable(
                    modelID: "whisper-small",
                    fallbackModelID: "parakeet-v3"
                ),
                loadedModelIDs: ["parakeet-v3"]
            )
        )
    }

    func testMissingDefaultBootstrapsWithProgressThenLoadsAndUnblocks() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3", "parakeet-v2"],
            availableModelIDs: []
        )
        parakeet.suspendDownloads = true
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )

        let start = Task { await lifecycle.start() }
        await parakeet.waitForDownloadStart()
        parakeet.reportProgress(0.35)
        let progress = await snapshot(from: lifecycle) {
            $0.operation == .bootstrapping(fraction: 0.35)
        }
        parakeet.finishDownload(availableAfterDownload: true)
        await start.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            BootstrapBehaviorState(
                snapshots: [
                    BootstrapState(
                        operation: progress.operation,
                        effectiveSelection: progress.effectiveSelection,
                        isDictationBlocked: progress.isDictationBlocked,
                        failure: progress.failure
                    ),
                    BootstrapState(
                        operation: completed.operation,
                        effectiveSelection: completed.effectiveSelection,
                        isDictationBlocked: completed.isDictationBlocked,
                        failure: completed.failure
                    ),
                ],
                downloadedModelIDs: parakeet.downloadedModelIDs,
                loadedModelIDs: parakeet.loadedModelIDs
            ),
            BootstrapBehaviorState(
                snapshots: [
                    BootstrapState(
                        operation: .bootstrapping(fraction: 0.35),
                        effectiveSelection: nil,
                        isDictationBlocked: true,
                        failure: nil
                    ),
                    BootstrapState(
                        operation: nil,
                        effectiveSelection: "parakeet-v3",
                        isDictationBlocked: false,
                        failure: nil
                    ),
                ],
                downloadedModelIDs: ["parakeet-v3"],
                loadedModelIDs: ["parakeet-v3"]
            )
        )
    }

    func testBootstrapPreparationSerializesOtherManagementOperations() async {
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: []
        )
        parakeet.suspendDownloads = true
        parakeet.enginePreparation = preparation.run
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: []
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )

        let start = Task { await lifecycle.start() }
        await parakeet.waitForDownloadStart()
        parakeet.finishDownload(availableAfterDownload: true)
        await preparation.waitUntilStarted()
        await lifecycle.download("whisper-small")
        let preparing = await lifecycle.snapshot()
        preparation.finish()
        await start.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            BootstrapPreparationSerializationState(
                operationWhilePreparing: preparing.operation,
                overlappingDownloads: whisper.downloadedModelIDs,
                completedSelection: completed.effectiveSelection
            ),
            BootstrapPreparationSerializationState(
                operationWhilePreparing: .bootstrapping(fraction: nil),
                overlappingDownloads: [],
                completedSelection: "parakeet-v3"
            )
        )
    }

    func testFailedBootstrapDoesNotRepeatUntilExplicitRetry() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: []
        )
        parakeet.downloadError = DownloadFailure()
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )

        await lifecycle.start()
        await lifecycle.start()
        let failed = await lifecycle.snapshot()

        parakeet.downloadError = nil
        parakeet.completeDownloadsImmediatelyAsAvailable = true
        await lifecycle.retryBootstrap()
        let recovered = await lifecycle.snapshot()

        XCTAssertEqual(
            BootstrapBehaviorState(
                snapshots: [
                    BootstrapState(
                        operation: failed.operation,
                        effectiveSelection: failed.effectiveSelection,
                        isDictationBlocked: failed.isDictationBlocked,
                        failure: failed.failure
                    ),
                    BootstrapState(
                        operation: recovered.operation,
                        effectiveSelection: recovered.effectiveSelection,
                        isDictationBlocked: recovered.isDictationBlocked,
                        failure: recovered.failure
                    ),
                ],
                downloadedModelIDs: parakeet.downloadedModelIDs,
                loadedModelIDs: parakeet.loadedModelIDs
            ),
            BootstrapBehaviorState(
                snapshots: [
                    BootstrapState(
                        operation: nil,
                        effectiveSelection: nil,
                        isDictationBlocked: true,
                        failure: .bootstrapFailed(reason: "disk full")
                    ),
                    BootstrapState(
                        operation: nil,
                        effectiveSelection: "parakeet-v3",
                        isDictationBlocked: false,
                        failure: nil
                    ),
                ],
                downloadedModelIDs: ["parakeet-v3", "parakeet-v3"],
                loadedModelIDs: ["parakeet-v3"]
            )
        )
    }

    func testLifecycleCapturesTheWarmEngineThroughASessionHandle() async throws {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        parakeet.transcriptionTextByModelID = ["parakeet-v3": "hello from lifecycle"]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        await lifecycle.start()
        let session = try lifecycle.captureSession()
        let text = try await session.transcribe([0.1, 0.2])
        session.release()

        XCTAssertEqual(
            WarmEngineState(
                text: text,
                loadedModelIDs: parakeet.loadedModelIDs,
                transcribedSamples: parakeet.transcribedSamples
            ),
            WarmEngineState(
                text: "hello from lifecycle",
                loadedModelIDs: ["parakeet-v3"],
                transcribedSamples: [[0.1, 0.2]]
            )
        )
    }

    func testBlockedLifecycleThrowsTypedFailureWithoutRetryingBootstrap() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: []
        )
        parakeet.downloadError = DownloadFailure()
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        let sessionProvider: ASRSessionHandleProviding = lifecycle

        await lifecycle.start()
        let captureFailure = await failureDescription {
            _ = try lifecycle.captureSession()
        }

        XCTAssertEqual(
            BlockedRecognitionState(
                captureFailure: captureFailure,
                isDictationBlocked: sessionProvider.isDictationBlocked,
                downloadAttempts: parakeet.downloadedModelIDs
            ),
            BlockedRecognitionState(
                captureFailure: "Speech recognition is unavailable.",
                isDictationBlocked: true,
                downloadAttempts: ["parakeet-v3"]
            )
        )
    }

    func testAdapterWithoutEngineConstructionPublishesTypedBlockedFailure() async {
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [AvailabilityOnlyASRModelFamilyAdapter()]
        )

        await lifecycle.start()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            BootstrapState(
                operation: snapshot.operation,
                effectiveSelection: snapshot.effectiveSelection,
                isDictationBlocked: snapshot.isDictationBlocked,
                failure: snapshot.failure
            ),
            BootstrapState(
                operation: nil,
                effectiveSelection: nil,
                isDictationBlocked: true,
                failure: .engineLoadFailed(
                    modelID: "parakeet-v3",
                    reason: "No ASR engine can be constructed for parakeet-v3."
                )
            )
        )
    }

    func testMissingDefaultAdapterPublishesTypedBootstrapFailure() async {
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: []
        )

        await lifecycle.start()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            snapshot.failure,
            .bootstrapFailed(reason: "The default ASR model is unavailable.")
        )
    }

    func testRetryUsesExternallyRestoredDefaultWithoutDownloadingAgain() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: []
        )
        parakeet.downloadError = DownloadFailure()
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        await lifecycle.start()
        parakeet.setAvailable(true, id: "parakeet-v3")

        await lifecycle.retryBootstrap()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            BootstrapRecoveryState(
                selection: EffectiveSelectionState(
                    storedSelection: snapshot.storedSelection,
                    effectiveSelection: snapshot.effectiveSelection,
                    recovery: snapshot.recovery,
                    loadedModelIDs: parakeet.loadedModelIDs
                ),
                downloadedModelIDs: parakeet.downloadedModelIDs
            ),
            BootstrapRecoveryState(
                selection: EffectiveSelectionState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: "parakeet-v3",
                    recovery: nil,
                    loadedModelIDs: ["parakeet-v3"]
                ),
                downloadedModelIDs: ["parakeet-v3"]
            )
        )
    }

    func testReconcileDoesNotRetryRejectedDefaultEngineBeforeExplicitRetry() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        parakeet.removesAvailabilityOnPreparationFailure = false
        parakeet.enginePreparationErrors = ["parakeet-v3": EngineFailure()]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        await lifecycle.start()
        parakeet.enginePreparationErrors = [:]

        await lifecycle.reconcileAvailability()
        let reconciled = await lifecycle.snapshot()
        let reconciledLoadedModelIDs = parakeet.loadedModelIDs
        await lifecycle.retryBootstrap()
        let retried = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                LoadRetryState(
                    effectiveSelection: reconciled.effectiveSelection,
                    isDictationBlocked: reconciled.isDictationBlocked,
                    failure: reconciled.failure,
                    loadedModelIDs: reconciledLoadedModelIDs
                ),
                LoadRetryState(
                    effectiveSelection: retried.effectiveSelection,
                    isDictationBlocked: retried.isDictationBlocked,
                    failure: retried.failure,
                    loadedModelIDs: parakeet.loadedModelIDs
                ),
            ],
            [
                LoadRetryState(
                    effectiveSelection: nil,
                    isDictationBlocked: true,
                    failure: .engineLoadFailed(
                        modelID: "parakeet-v3",
                        reason: "model data rejected"
                    ),
                    loadedModelIDs: ["parakeet-v3"]
                ),
                LoadRetryState(
                    effectiveSelection: "parakeet-v3",
                    isDictationBlocked: false,
                    failure: nil,
                    loadedModelIDs: ["parakeet-v3", "parakeet-v3"]
                ),
            ]
        )
    }

    func testSelectionRequestIsIgnoredDuringDefaultBootstrap() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: []
        )
        parakeet.suspendDownloads = true
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"]
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )

        let start = Task { await lifecycle.start() }
        await parakeet.waitForDownloadStart()
        await lifecycle.select("whisper-small")
        let bootstrapping = await lifecycle.snapshot()
        parakeet.finishDownload(availableAfterDownload: true)
        await start.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                BootstrapState(
                    operation: bootstrapping.operation,
                    effectiveSelection: bootstrapping.effectiveSelection,
                    isDictationBlocked: bootstrapping.isDictationBlocked,
                    failure: bootstrapping.failure
                ),
                BootstrapState(
                    operation: completed.operation,
                    effectiveSelection: completed.effectiveSelection,
                    isDictationBlocked: completed.isDictationBlocked,
                    failure: completed.failure
                ),
            ],
            [
                BootstrapState(
                    operation: .bootstrapping(fraction: nil),
                    effectiveSelection: nil,
                    isDictationBlocked: true,
                    failure: nil
                ),
                BootstrapState(
                    operation: nil,
                    effectiveSelection: "parakeet-v3",
                    isDictationBlocked: false,
                    failure: nil
                ),
            ]
        )
    }

    func testSelectionUpdateReleasesWarmEngineBeforeLoadingTheNext() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )

        await lifecycle.start()
        await lifecycle.select("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            EngineSwitchState(
                effectiveSelection: snapshot.effectiveSelection,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            EngineSwitchState(
                effectiveSelection: "whisper-small",
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testSelectionLoadsCandidateBeforePersistingAndPublishingIt() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper],
            persistSelection: { id in residency.record("persist-\(id)") }
        )
        await lifecycle.start()

        await lifecycle.select("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            TransactionalSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                isDictationBlocked: snapshot.isDictationBlocked,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            TransactionalSelectionState(
                storedSelection: "whisper-small",
                effectiveSelection: "whisper-small",
                operation: nil,
                isDictationBlocked: false,
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                    "persist-whisper-small",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testCandidateLoadFailureRestoresPreviousSelectionWithoutPersisting() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparationErrors = ["whisper-small": EngineFailure()]
        var persisted: [String] = []
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper],
            persistSelection: { persisted.append($0) }
        )
        await lifecycle.start()

        await lifecycle.select("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            FailedTransactionalSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                failure: snapshot.failure,
                isDictationBlocked: snapshot.isDictationBlocked,
                persisted: persisted,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            FailedTransactionalSelectionState(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                failure: .selectionFailed(modelID: "whisper-small", reason: "model data rejected"),
                isDictationBlocked: false,
                persisted: [],
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-parakeet-v3",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testPersistenceFailurePublishesRestorationBeforeResumingPreviousSelection() async {
        let residency = EngineResidencyProbe()
        let restoration = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper],
            persistSelection: { _ in throw SelectionPersistenceFailure() }
        )
        await lifecycle.start()
        parakeet.enginePreparation = restoration.run

        let selection = Task { await lifecycle.select("whisper-small") }
        await restoration.waitUntilStarted()
        let restoring = await lifecycle.snapshot()
        restoration.finish()
        await selection.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                SelectionRestorationState(
                    storedSelection: restoring.storedSelection,
                    effectiveSelection: restoring.effectiveSelection,
                    operation: restoring.operation,
                    failure: restoring.failure,
                    isDictationBlocked: restoring.isDictationBlocked
                ),
                SelectionRestorationState(
                    storedSelection: completed.storedSelection,
                    effectiveSelection: completed.effectiveSelection,
                    operation: completed.operation,
                    failure: completed.failure,
                    isDictationBlocked: completed.isDictationBlocked
                ),
            ],
            [
                SelectionRestorationState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: nil,
                    operation: .restoring(modelID: "parakeet-v3"),
                    failure: .selectionFailed(
                        modelID: "whisper-small",
                        reason: "config write failed"
                    ),
                    isDictationBlocked: true
                ),
                SelectionRestorationState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: "parakeet-v3",
                    operation: nil,
                    failure: .selectionFailed(
                        modelID: "whisper-small",
                        reason: "config write failed"
                    ),
                    isDictationBlocked: false
                ),
            ]
        )
    }

    func testCancelSelectionRestoresPreviousEngineBeforeCompleting() async {
        let residency = EngineResidencyProbe()
        let preparation = CancellableSelectionPreparation()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        var persisted: [String] = []
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper],
            persistSelection: { persisted.append($0) }
        )
        await lifecycle.start()

        let selection = Task { await lifecycle.select("whisper-small") }
        await preparation.waitUntilStarted()
        await lifecycle.cancelCurrentOperation()
        await preparation.waitUntilCancelled()
        await selection.value
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            FailedTransactionalSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                failure: snapshot.failure,
                isDictationBlocked: snapshot.isDictationBlocked,
                persisted: persisted,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            FailedTransactionalSelectionState(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                failure: .selectionCanceled(modelID: "whisper-small"),
                isDictationBlocked: false,
                persisted: [],
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-parakeet-v3",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testCanceledCandidateFinishingLateCannotCommitOrReplaceRestoredEngine() async {
        let residency = EngineResidencyProbe()
        let preparation = CancellableSelectionPreparation(finishesOnCancellation: false)
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        var persisted: [String] = []
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper],
            persistSelection: { persisted.append($0) }
        )
        await lifecycle.start()

        let selection = Task { await lifecycle.select("whisper-small") }
        await preparation.waitUntilStarted()
        let cancellation = Task { await lifecycle.cancelCurrentOperation() }
        await preparation.waitUntilCancelled()
        preparation.finish()
        await cancellation.value
        await selection.value
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            FailedTransactionalSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                failure: snapshot.failure,
                isDictationBlocked: snapshot.isDictationBlocked,
                persisted: persisted,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            FailedTransactionalSelectionState(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                failure: .selectionCanceled(modelID: "whisper-small"),
                isDictationBlocked: false,
                persisted: [],
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-parakeet-v3",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testCancelWhileSessionIsHeldResumesCaptureWithoutReplacingEngine() async throws {
        let fixture = switchingLifecycle()
        await fixture.lifecycle.start()
        let heldSession = try fixture.lifecycle.captureSession()

        let selection = Task { await fixture.lifecycle.select("whisper-small") }
        _ = await snapshot(from: fixture.lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }
        var snapshots = await fixture.lifecycle.snapshots().makeAsyncIterator()
        _ = await snapshots.next()
        let nextSnapshot = Task { await snapshots.next() }
        await fixture.lifecycle.cancelCurrentOperation()
        let cancellationCompleted = await nextSnapshot.value
        let resumedSession = try fixture.lifecycle.captureSession()
        await selection.value
        let snapshot = await fixture.lifecycle.snapshot()

        heldSession.release()
        resumedSession.release()
        XCTAssertEqual(
            HeldSessionCancellationState(
                transaction: FailedTransactionalSelectionState(
                    storedSelection: snapshot.storedSelection,
                    effectiveSelection: snapshot.effectiveSelection,
                    operation: snapshot.operation,
                    failure: snapshot.failure,
                    isDictationBlocked: snapshot.isDictationBlocked,
                    persisted: [],
                    eventLog: fixture.residency.events,
                    maximumResidentEngines: fixture.residency.maximumResidentEngines
                ),
                publishedCompletionOperation: cancellationCompleted?.operation
            ),
            HeldSessionCancellationState(
                transaction: FailedTransactionalSelectionState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: "parakeet-v3",
                    operation: nil,
                    failure: .selectionCanceled(modelID: "whisper-small"),
                    isDictationBlocked: false,
                    persisted: [],
                    eventLog: ["construct-parakeet-v3"],
                    maximumResidentEngines: 1
                ),
                publishedCompletionOperation: nil
            )
        )
    }

    func testFailedPreviousRestorationUsesDefaultAsDegradedEffectiveModel() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small", "whisper-large-v3-turbo"],
            availableModelIDs: ["whisper-small", "whisper-large-v3-turbo"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        whisper.enginePreparationErrors = [
            "whisper-small": EngineFailure(),
            "whisper-large-v3-turbo": EngineFailure(),
        ]

        await lifecycle.select("whisper-large-v3-turbo")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            FailedTransactionalSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                failure: snapshot.failure,
                isDictationBlocked: snapshot.isDictationBlocked,
                persisted: [],
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            FailedTransactionalSelectionState(
                storedSelection: "whisper-small",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                failure: .selectionDegraded(
                    modelID: "whisper-small",
                    fallbackModelID: "parakeet-v3",
                    reason: "model data rejected"
                ),
                isDictationBlocked: false,
                persisted: [],
                eventLog: [
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-whisper-large-v3-turbo",
                    "release-whisper-large-v3-turbo",
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-parakeet-v3",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testFailedDefaultRestorationLeavesRecognitionBlocked() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        parakeet.enginePreparationErrors = ["parakeet-v3": EngineFailure()]
        whisper.enginePreparationErrors = ["whisper-small": EngineFailure()]

        await lifecycle.select("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            SelectionRestorationState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                failure: snapshot.failure,
                isDictationBlocked: snapshot.isDictationBlocked
            ),
            SelectionRestorationState(
                storedSelection: "parakeet-v3",
                effectiveSelection: nil,
                operation: nil,
                failure: .engineLoadFailed(
                    modelID: "parakeet-v3",
                    reason: "model data rejected"
                ),
                isDictationBlocked: true
            )
        )
    }

    func testSelectionRefreshKeepsSwitchStateCoherentWhileCandidatePrepares() async {
        let fixture = suspendedSelectionLifecycle()
        await fixture.lifecycle.start()

        let selection = Task { await fixture.lifecycle.select("whisper-small") }
        await fixture.preparation.waitUntilStarted()
        await fixture.lifecycle.reconcileAvailability()
        let whileSwitching = EngineSwitchState(
            effectiveSelection: await fixture.lifecycle.snapshot().effectiveSelection,
            eventLog: fixture.residency.events,
            maximumResidentEngines: fixture.residency.maximumResidentEngines
        )
        fixture.preparation.finish()
        await selection.value

        XCTAssertEqual(
            whileSwitching,
            EngineSwitchState(
                effectiveSelection: nil,
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testSelectionRejectsDownloadWhileCandidatePrepares() async {
        let fixture = suspendedSelectionLifecycle()
        await fixture.lifecycle.start()

        let selection = Task { await fixture.lifecycle.select("whisper-small") }
        await fixture.preparation.waitUntilStarted()
        await fixture.lifecycle.download("whisper-large-v3-turbo")
        let downloadedModelIDs = fixture.whisper.downloadedModelIDs
        fixture.preparation.finish()
        await selection.value

        XCTAssertEqual(downloadedModelIDs, [])
    }

    func testSelectionUpdateWaitsForActiveTranscriptionBeforeReplacingEngine() async throws {
        let residency = EngineResidencyProbe()
        let transcription = SuspendAsyncOperations()
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        parakeet.engineTranscription = transcription.run
        parakeet.transcriptionTextByModelID = ["parakeet-v3": "captured transcript"]
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        let updates = await lifecycle.snapshots()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let session = try lifecycle.captureSession()
        let transcriptionTask = Task {
            defer { session.release() }
            return try await session.transcribe([0.1])
        }
        await transcription.waitUntilStarted()
        let selection = Task { await lifecycle.select("whisper-small") }
        guard let transition = await iterator.next() else {
            return XCTFail("Expected a selection transition snapshot")
        }
        let whileTranscribing = ActiveTranscriptionTransitionState(
            effectiveSelection: transition.effectiveSelection,
            isDictationBlocked: transition.isDictationBlocked,
            eventLog: residency.events,
            maximumResidentEngines: residency.maximumResidentEngines
        )

        transcription.finish()
        let text = try await transcriptionTask.value
        await preparation.waitUntilStarted()
        preparation.finish()
        await selection.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            ActiveTranscriptionSwitchResult(
                text: text,
                states: [
                    whileTranscribing,
                    ActiveTranscriptionTransitionState(
                        effectiveSelection: completed.effectiveSelection,
                        isDictationBlocked: completed.isDictationBlocked,
                        eventLog: residency.events,
                        maximumResidentEngines: residency.maximumResidentEngines
                    ),
                ]
            ),
            ActiveTranscriptionSwitchResult(
                text: "captured transcript",
                states: [
                    ActiveTranscriptionTransitionState(
                        effectiveSelection: "parakeet-v3",
                        isDictationBlocked: true,
                        eventLog: ["construct-parakeet-v3"],
                        maximumResidentEngines: 1
                    ),
                    ActiveTranscriptionTransitionState(
                        effectiveSelection: "whisper-small",
                        isDictationBlocked: false,
                        eventLog: [
                            "construct-parakeet-v3",
                            "release-parakeet-v3",
                            "construct-whisper-small",
                        ],
                        maximumResidentEngines: 1
                    ),
                ]
            )
        )
    }

    func testCapturedSessionKeepsItsEngineUntilReleaseAllowsSelectionUpdate() async throws {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        parakeet.transcriptionTextByModelID = ["parakeet-v3": "captured transcript"]
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        let session = try lifecycle.captureSession()

        let selection = Task { await lifecycle.select("whisper-small") }
        let transition = await snapshot(from: lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }
        let text = try await session.transcribe([0.1])
        let whileSessionIsHeld = ActiveTranscriptionTransitionState(
            effectiveSelection: transition.effectiveSelection,
            isDictationBlocked: transition.isDictationBlocked,
            eventLog: residency.events,
            maximumResidentEngines: residency.maximumResidentEngines
        )

        session.release()
        await selection.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            ActiveTranscriptionSwitchResult(
                text: text,
                states: [
                    whileSessionIsHeld,
                    ActiveTranscriptionTransitionState(
                        effectiveSelection: completed.effectiveSelection,
                        isDictationBlocked: completed.isDictationBlocked,
                        eventLog: residency.events,
                        maximumResidentEngines: residency.maximumResidentEngines
                    ),
                ]
            ),
            ActiveTranscriptionSwitchResult(
                text: "captured transcript",
                states: [
                    ActiveTranscriptionTransitionState(
                        effectiveSelection: "parakeet-v3",
                        isDictationBlocked: true,
                        eventLog: ["construct-parakeet-v3"],
                        maximumResidentEngines: 1
                    ),
                    ActiveTranscriptionTransitionState(
                        effectiveSelection: "whisper-small",
                        isDictationBlocked: false,
                        eventLog: [
                            "construct-parakeet-v3",
                            "release-parakeet-v3",
                            "construct-whisper-small",
                        ],
                        maximumResidentEngines: 1
                    ),
                ]
            )
        )
    }

    func testAbandonedSessionHandleReleasesEngineForPendingSelection() async throws {
        let fixture = switchingLifecycle()
        await fixture.lifecycle.start()
        var session: (any ASRSessionHandle)? = try fixture.lifecycle.captureSession()
        XCTAssertNotNil(session)
        let selection = Task {
            await fixture.lifecycle.select("whisper-small")
        }
        _ = await snapshot(from: fixture.lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }

        session = nil
        await selection.value
        let completed = await fixture.lifecycle.snapshot()

        XCTAssertEqual(
            EngineSwitchState(
                effectiveSelection: completed.effectiveSelection,
                eventLog: fixture.residency.events,
                maximumResidentEngines: fixture.residency.maximumResidentEngines
            ),
            completedSwitchState
        )
    }

    func testTranscriptionFailureReleasesLifecycleSessionForPendingSelection() async {
        let fixture = switchingLifecycle(transcriptionError: EngineFailure())
        await fixture.lifecycle.start()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: fixture.lifecycle,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        let selection = Task {
            await fixture.lifecycle.select("whisper-small")
        }
        _ = await snapshot(from: fixture.lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }
        pipeline.stopRecording()
        await pipeline.awaitPendingJob()
        await selection.value
        let completed = await fixture.lifecycle.snapshot()

        XCTAssertEqual(
            EngineSwitchState(
                effectiveSelection: completed.effectiveSelection,
                eventLog: fixture.residency.events,
                maximumResidentEngines: fixture.residency.maximumResidentEngines
            ),
            completedSwitchState
        )
    }

    func testCanceledTranscriptionReleasesLifecycleSessionForPendingSelection() async {
        let transcription = SuspendAsyncOperations()
        let fixture = switchingLifecycle(transcription: transcription.run)
        await fixture.lifecycle.start()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: FakeRecorder(),
            sessionProvider: fixture.lifecycle,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        let selection = Task {
            await fixture.lifecycle.select("whisper-small")
        }
        _ = await snapshot(from: fixture.lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }
        pipeline.stopRecording()
        await transcription.waitUntilStarted()
        pipeline.shutdown()
        transcription.finish()
        await pipeline.awaitPendingJob()
        await selection.value
        let completed = await fixture.lifecycle.snapshot()

        XCTAssertEqual(
            EngineSwitchState(
                effectiveSelection: completed.effectiveSelection,
                eventLog: fixture.residency.events,
                maximumResidentEngines: fixture.residency.maximumResidentEngines
            ),
            completedSwitchState
        )
    }

    func testRecorderFailureReleasesLifecycleSessionForPendingSelection() async {
        let fixture = switchingLifecycle()
        await fixture.lifecycle.start()
        let recorder = FakeRecorder()
        let pipeline = Pipeline(
            config: makeTestConfig(),
            recorder: recorder,
            sessionProvider: fixture.lifecycle,
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        let selection = Task {
            await fixture.lifecycle.select("whisper-small")
        }
        _ = await snapshot(from: fixture.lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }
        recorder.fail(.configurationChanged)
        await selection.value
        let completed = await fixture.lifecycle.snapshot()

        XCTAssertEqual(
            EngineSwitchState(
                effectiveSelection: completed.effectiveSelection,
                eventLog: fixture.residency.events,
                maximumResidentEngines: fixture.residency.maximumResidentEngines
            ),
            completedSwitchState
        )
    }

    func testPipelineReleasesSessionForSwitchBeforePolishAndQueuesNextEngine() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        parakeet.transcriptionTextByModelID = [
            "parakeet-v3":
                "first transcript is unquestionably longer than the forty character threshold",
        ]
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.transcriptionTextByModelID = [
            "whisper-small":
                "second transcript is unquestionably longer than the forty character threshold",
        ]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        let polish = SuspendAsyncOperations()
        let inserted = InsertSpy()
        let mode = Mode(
            name: "Clean", asrModel: "", llmModel: "llama3", systemPrompt: nil, vocab: []
        )
        let pipeline = Pipeline(
            config: makeTestConfig(mode: mode),
            recorder: FakeRecorder(),
            sessionProvider: lifecycle,
            polish: { text, _ in
                await polish.run()
                return text
            },
            insert: { inserted.insert($0) },
            record: { _ in },
            frontmostApp: { nil }
        )

        pipeline.startRecording()
        let selection = Task { await lifecycle.select("whisper-small") }
        _ = await snapshot(from: lifecycle) {
            $0.operation == .switching(modelID: "whisper-small") && $0.isDictationBlocked
        }
        pipeline.stopRecording()
        await polish.waitUntilStarted()
        await selection.value
        pipeline.startRecording()
        pipeline.stopRecording()
        polish.finish()
        await pipeline.awaitPendingJob()
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            PipelineLifecycleTransitionState(
                effectiveSelection: completed.effectiveSelection,
                insertedTexts: inserted.texts,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            PipelineLifecycleTransitionState(
                effectiveSelection: "whisper-small",
                insertedTexts: [
                    "first transcript is unquestionably longer than the forty character threshold",
                    "second transcript is unquestionably longer than the forty character threshold",
                ],
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testSelectionUpdateWaitsForEveryActiveTranscriptionBeforeReplacingEngine() async throws {
        let residency = EngineResidencyProbe()
        let transcription = SuspendAsyncOperations(count: 2)
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        parakeet.engineTranscription = transcription.run
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        let updates = await lifecycle.snapshots()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let firstSession = try lifecycle.captureSession()
        let firstTranscription = Task {
            defer { firstSession.release() }
            return try await firstSession.transcribe([0.1])
        }
        await transcription.waitUntilStarted()
        let secondSession = try lifecycle.captureSession()
        let secondTranscription = Task {
            defer { secondSession.release() }
            return try await secondSession.transcribe([0.2])
        }
        await transcription.waitUntilStarted()
        let selection = Task { await lifecycle.select("whisper-small") }
        guard await iterator.next() != nil else {
            return XCTFail("Expected a selection transition snapshot")
        }

        transcription.finish()
        _ = try await firstTranscription.value
        let afterFirstTranscription = await lifecycle.snapshot()
        let whileSecondTranscriptionRuns = ActiveTranscriptionTransitionState(
            effectiveSelection: afterFirstTranscription.effectiveSelection,
            isDictationBlocked: afterFirstTranscription.isDictationBlocked,
            eventLog: residency.events,
            maximumResidentEngines: residency.maximumResidentEngines
        )

        transcription.finish()
        _ = try await secondTranscription.value
        await selection.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                whileSecondTranscriptionRuns,
                ActiveTranscriptionTransitionState(
                    effectiveSelection: completed.effectiveSelection,
                    isDictationBlocked: completed.isDictationBlocked,
                    eventLog: residency.events,
                    maximumResidentEngines: residency.maximumResidentEngines
                ),
            ],
            [
                ActiveTranscriptionTransitionState(
                    effectiveSelection: "parakeet-v3",
                    isDictationBlocked: true,
                    eventLog: ["construct-parakeet-v3"],
                    maximumResidentEngines: 1
                ),
                ActiveTranscriptionTransitionState(
                    effectiveSelection: "whisper-small",
                    isDictationBlocked: false,
                    eventLog: [
                        "construct-parakeet-v3",
                        "release-parakeet-v3",
                        "construct-whisper-small",
                    ],
                    maximumResidentEngines: 1
                ),
            ]
        )
    }

    func testRepeatedSelectionUpdateDoesNotLoadASecondCandidateEngine() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        let firstUpdate = Task { await lifecycle.select("whisper-small") }
        await preparation.waitUntilStarted()
        await lifecycle.select("whisper-small")
        preparation.finish()
        await firstUpdate.value
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            EngineSwitchState(
                effectiveSelection: snapshot.effectiveSelection,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            EngineSwitchState(
                effectiveSelection: "whisper-small",
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testSelectionPublishesCoherentBlockedStateBeforeReplacingTheEffectiveEngine() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        let updates = await lifecycle.snapshots()
        var iterator = updates.makeAsyncIterator()
        _ = await iterator.next()

        let selection = Task { await lifecycle.select("whisper-small") }
        guard let transition = await iterator.next() else {
            return XCTFail("Expected a selection transition snapshot")
        }
        await preparation.waitUntilStarted()
        preparation.finish()
        await selection.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                SelectionTransitionState(
                    storedSelection: transition.storedSelection,
                    effectiveSelection: transition.effectiveSelection,
                    operation: transition.operation,
                    isDictationBlocked: transition.isDictationBlocked
                ),
                SelectionTransitionState(
                    storedSelection: completed.storedSelection,
                    effectiveSelection: completed.effectiveSelection,
                    operation: completed.operation,
                    isDictationBlocked: completed.isDictationBlocked
                ),
            ],
            [
                SelectionTransitionState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: "parakeet-v3",
                    operation: .switching(modelID: "whisper-small"),
                    isDictationBlocked: true
                ),
                SelectionTransitionState(
                    storedSelection: "whisper-small",
                    effectiveSelection: "whisper-small",
                    operation: nil,
                    isDictationBlocked: false
                ),
            ]
        )
    }

    func testRepairingStoredSelectionWarmsItAfterStorageOnlyDownloadCompletes() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: [],
            residency: residency
        )
        whisper.completeDownloadsImmediatelyAsAvailable = true
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        await lifecycle.download("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            RepairedSelectionState(
                effectiveSelection: snapshot.effectiveSelection,
                recovery: snapshot.recovery,
                downloadedModelIDs: whisper.downloadedModelIDs,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            RepairedSelectionState(
                effectiveSelection: "whisper-small",
                recovery: nil,
                downloadedModelIDs: ["whisper-small"],
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testRepairedSelectionRestorationSerializesOtherManagementOperations() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3", "parakeet-v2"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: [],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        whisper.setAvailable(true, id: "whisper-small")

        let restoration = Task { await lifecycle.reconcileAvailability() }
        await preparation.waitUntilStarted()
        await lifecycle.download("parakeet-v2")
        let restoring = await lifecycle.snapshot()
        preparation.finish()
        await restoration.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            AutomaticRestorationSerializationState(
                operationWhilePreparing: restoring.operation,
                overlappingDownloads: parakeet.downloadedModelIDs,
                completedSelection: completed.effectiveSelection,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            AutomaticRestorationSerializationState(
                operationWhilePreparing: .restoring(modelID: "whisper-small"),
                overlappingDownloads: [],
                completedSelection: "whisper-small",
                maximumResidentEngines: 1
            )
        )
    }

    func testAnotherSelectionRequestIsIgnoredWhileCandidatePrepares() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        let first = Task { await lifecycle.select("whisper-small") }
        await preparation.waitUntilStarted()
        await lifecycle.select("parakeet-v3")
        let whileWhisperPrepares = EngineSwitchState(
            effectiveSelection: await lifecycle.snapshot().effectiveSelection,
            eventLog: residency.events,
            maximumResidentEngines: residency.maximumResidentEngines
        )
        preparation.finish()
        await first.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            [
                whileWhisperPrepares,
                EngineSwitchState(
                    effectiveSelection: completed.effectiveSelection,
                    eventLog: residency.events,
                    maximumResidentEngines: residency.maximumResidentEngines
                ),
            ],
            [
                EngineSwitchState(
                    effectiveSelection: nil,
                    eventLog: [
                        "construct-parakeet-v3",
                        "release-parakeet-v3",
                        "construct-whisper-small",
                    ],
                    maximumResidentEngines: 1
                ),
                EngineSwitchState(
                    effectiveSelection: "whisper-small",
                    eventLog: [
                        "construct-parakeet-v3",
                        "release-parakeet-v3",
                        "construct-whisper-small",
                    ],
                    maximumResidentEngines: 1
                ),
            ]
        )
    }

    func testReconcileWarmsRepairedSelectionAndFallsBackAfterExternalInvalidation() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: [],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        whisper.setAvailable(true, id: "whisper-small")
        await lifecycle.reconcileAvailability()
        let repaired = await lifecycle.snapshot()
        whisper.setAvailable(false, id: "whisper-small")
        await lifecycle.reconcileAvailability()
        let invalidated = await lifecycle.snapshot()

        XCTAssertEqual(
            ReconciledEngineState(
                effectiveSelections: [
                    repaired.effectiveSelection,
                    invalidated.effectiveSelection,
                ],
                finalRecovery: invalidated.recovery,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            ReconciledEngineState(
                effectiveSelections: ["whisper-small", "parakeet-v3"],
                finalRecovery: .storedSelectionUnavailable(
                    modelID: "whisper-small",
                    fallbackModelID: "parakeet-v3"
                ),
                eventLog: [
                    "construct-parakeet-v3",
                    "release-parakeet-v3",
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-parakeet-v3",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testSelectedEngineLoadFailureReconcilesAndFallsBackToDefault() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparationErrors = ["whisper-small": EngineFailure()]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )

        await lifecycle.start()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            LoadFailureState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                whisperIsAvailable: snapshot.models.first {
                    $0.id == "whisper-small"
                }?.isAvailable == true,
                recovery: snapshot.recovery,
                failure: snapshot.failure,
                isDictationBlocked: snapshot.isDictationBlocked,
                eventLog: residency.events,
                maximumResidentEngines: residency.maximumResidentEngines
            ),
            LoadFailureState(
                storedSelection: "whisper-small",
                effectiveSelection: "parakeet-v3",
                whisperIsAvailable: false,
                recovery: .storedSelectionUnavailable(
                    modelID: "whisper-small",
                    fallbackModelID: "parakeet-v3"
                ),
                failure: .engineLoadFailed(
                    modelID: "whisper-small",
                    reason: "model data rejected"
                ),
                isDictationBlocked: false,
                eventLog: [
                    "construct-whisper-small",
                    "release-whisper-small",
                    "construct-parakeet-v3",
                ],
                maximumResidentEngines: 1
            )
        )
    }

    func testAutomaticRestorationNamesFallbackWhileFallbackPrepares() async {
        let fallbackPreparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        parakeet.enginePreparation = fallbackPreparation.run
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"]
        )
        whisper.enginePreparationErrors = ["whisper-small": EngineFailure()]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )

        let start = Task { await lifecycle.start() }
        await fallbackPreparation.waitUntilStarted()
        let preparingFallback = await lifecycle.snapshot()
        fallbackPreparation.finish()
        await start.value

        XCTAssertEqual(
            preparingFallback.operation,
            .restoring(modelID: "parakeet-v3")
        )
    }

    func testSelectingEffectiveFallbackClearsPreviousEngineLoadFailure() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"]
        )
        whisper.enginePreparationErrors = ["whisper-small": EngineFailure()]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        await lifecycle.select("parakeet-v3")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            ExplicitFallbackSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                recovery: snapshot.recovery,
                failure: snapshot.failure
            ),
            ExplicitFallbackSelectionState(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                recovery: nil,
                failure: nil
            )
        )
    }

    func testUnknownStoredSelectionFallsBackWithoutSyntheticCatalogRow() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "legacy/custom-asr",
            adapters: [parakeet]
        )

        await lifecycle.start()
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            UnknownSelectionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                recovery: snapshot.recovery,
                catalogContainsStoredSelection: snapshot.models.contains {
                    $0.id == snapshot.storedSelection
                }
            ),
            UnknownSelectionState(
                storedSelection: "legacy/custom-asr",
                effectiveSelection: "parakeet-v3",
                recovery: .storedSelectionUnknown(
                    modelID: "legacy/custom-asr",
                    fallbackModelID: "parakeet-v3"
                ),
                catalogContainsStoredSelection: false
            )
        )
    }

    func testDeletingSelectedModelCommitsDefaultAndWaitsForCapturedSession() async throws {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.transcriptionTextByModelID = ["whisper-small": "captured whisper"]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper],
            persistSelection: { id in residency.record("persist-\(id)") }
        )
        await lifecycle.start()
        let session = try lifecycle.captureSession()

        let deletion = Task { await lifecycle.delete("whisper-small") }
        let deleting = await snapshot(from: lifecycle) {
            $0.operation == .deleting(modelID: "whisper-small")
                && $0.storedSelection == "parakeet-v3"
        }
        let blockedCapture = await failureDescription { _ = try lifecycle.captureSession() }
        let transcript = try await session.transcribe([0.2])
        let deletingState = DeletionState(
            storedSelection: deleting.storedSelection,
            effectiveSelection: deleting.effectiveSelection,
            operation: deleting.operation,
            isDictationBlocked: deleting.isDictationBlocked,
            targetIsAvailable: deleting.models.first { $0.id == "whisper-small" }?.isAvailable,
            failure: deleting.failure,
            transcript: transcript,
            captureFailure: blockedCapture,
            events: residency.events
        )

        session.release()
        await deletion.value
        let completed = await lifecycle.snapshot()

        XCTAssertEqual(
            DeletionTransition(
                deleting: deletingState,
                completed: DeletionState(
                    storedSelection: completed.storedSelection,
                    effectiveSelection: completed.effectiveSelection,
                    operation: completed.operation,
                    isDictationBlocked: completed.isDictationBlocked,
                    targetIsAvailable: completed.models.first {
                        $0.id == "whisper-small"
                    }?.isAvailable,
                    failure: completed.failure,
                    transcript: nil,
                    captureFailure: nil,
                    events: residency.events
                )
            ),
            DeletionTransition(
                deleting: DeletionState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: "whisper-small",
                    operation: .deleting(modelID: "whisper-small"),
                    isDictationBlocked: true,
                    targetIsAvailable: true,
                    failure: nil,
                    transcript: "captured whisper",
                    captureFailure: "Speech recognition is unavailable.",
                    events: ["construct-whisper-small", "persist-parakeet-v3"]
                ),
                completed: DeletionState(
                    storedSelection: "parakeet-v3",
                    effectiveSelection: "parakeet-v3",
                    operation: nil,
                    isDictationBlocked: false,
                    targetIsAvailable: false,
                    failure: nil,
                    transcript: nil,
                    captureFailure: nil,
                    events: [
                        "construct-whisper-small",
                        "persist-parakeet-v3",
                        "release-whisper-small",
                        "delete-whisper-small",
                        "construct-parakeet-v3",
                    ]
                )
            )
        )
    }

    func testSelectedModelDeletionFailureKeepsFallbackSelectionAndOldDataAvailable() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.deletionError = DeletionFailure()
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper],
            persistSelection: { id in residency.record("persist-\(id)") }
        )
        await lifecycle.start()

        await lifecycle.delete("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            DeletionOutcome(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                isDictationBlocked: snapshot.isDictationBlocked,
                availableModelIDs: snapshot.models.filter(\.isAvailable).map(\.id),
                failure: snapshot.failure,
                removedModelIDs: whisper.removedModelIDs,
                events: residency.events
            ),
            DeletionOutcome(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                isDictationBlocked: false,
                availableModelIDs: ["parakeet-v3", "whisper-small"],
                failure: .deletionFailed(modelID: "whisper-small", reason: "permission denied"),
                removedModelIDs: [],
                events: [
                    "construct-whisper-small",
                    "persist-parakeet-v3",
                    "release-whisper-small",
                    "delete-whisper-small",
                    "construct-parakeet-v3",
                ]
            )
        )
    }

    func testSelectedModelDeletionStopsWhenFallbackSelectionCannotPersist() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper],
            persistSelection: { id in
                residency.record("persist-\(id)")
                throw SelectionPersistenceFailure()
            }
        )
        await lifecycle.start()

        await lifecycle.delete("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            DeletionOutcome(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                isDictationBlocked: snapshot.isDictationBlocked,
                availableModelIDs: snapshot.models.filter(\.isAvailable).map(\.id),
                failure: snapshot.failure,
                removedModelIDs: whisper.removedModelIDs,
                events: residency.events
            ),
            DeletionOutcome(
                storedSelection: "whisper-small",
                effectiveSelection: "whisper-small",
                operation: nil,
                isDictationBlocked: false,
                availableModelIDs: ["parakeet-v3", "whisper-small"],
                failure: .deletionSelectionFailed(
                    modelID: "whisper-small",
                    reason: "config write failed"
                ),
                removedModelIDs: [],
                events: ["construct-whisper-small", "persist-parakeet-v3"]
            )
        )
    }

    func testDeletingNonSelectedAndAlreadyAbsentModelsPreservesWarmSelection() async {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3", "parakeet-v2"],
            availableModelIDs: ["parakeet-v3", "parakeet-v2"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: [],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        await lifecycle.delete("parakeet-v2")
        await lifecycle.delete("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            DeletionOutcome(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                isDictationBlocked: snapshot.isDictationBlocked,
                availableModelIDs: snapshot.models.filter(\.isAvailable).map(\.id),
                failure: snapshot.failure,
                removedModelIDs: parakeet.removedModelIDs + whisper.removedModelIDs,
                events: residency.events
            ),
            DeletionOutcome(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                isDictationBlocked: false,
                availableModelIDs: ["parakeet-v3"],
                failure: nil,
                removedModelIDs: ["parakeet-v2", "whisper-small"],
                events: [
                    "construct-parakeet-v3",
                    "delete-parakeet-v2",
                    "delete-whisper-small",
                ]
            )
        )
    }

    func testDeletingNonSelectedModelDoesNotWaitForUnrelatedSession() async throws {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        parakeet.transcriptionTextByModelID = ["parakeet-v3": "captured parakeet"]
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()
        let session = try lifecycle.captureSession()

        await lifecycle.delete("whisper-small")
        let transcript = try await session.transcribe([0.3])
        let snapshot = await lifecycle.snapshot()
        session.release()

        XCTAssertEqual(
            DeletionState(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                isDictationBlocked: snapshot.isDictationBlocked,
                targetIsAvailable: snapshot.models.first { $0.id == "whisper-small" }?.isAvailable,
                failure: snapshot.failure,
                transcript: transcript,
                captureFailure: nil,
                events: residency.events
            ),
            DeletionState(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                isDictationBlocked: false,
                targetIsAvailable: false,
                failure: nil,
                transcript: "captured parakeet",
                captureFailure: nil,
                events: ["construct-parakeet-v3", "delete-whisper-small"]
            )
        )
    }

    func testDeletingUnavailableStoredModelKeepsEffectiveFallbackReady() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: []
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "whisper-small",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        await lifecycle.delete("whisper-small")
        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            DeletionOutcome(
                storedSelection: snapshot.storedSelection,
                effectiveSelection: snapshot.effectiveSelection,
                operation: snapshot.operation,
                isDictationBlocked: snapshot.isDictationBlocked,
                availableModelIDs: snapshot.models.filter(\.isAvailable).map(\.id),
                failure: snapshot.failure,
                removedModelIDs: whisper.removedModelIDs,
                events: []
            ),
            DeletionOutcome(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                operation: nil,
                isDictationBlocked: false,
                availableModelIDs: ["parakeet-v3"],
                failure: nil,
                removedModelIDs: ["whisper-small"],
                events: []
            )
        )
    }

    func testDefaultDeletionIsUnavailable() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        await lifecycle.start()

        await lifecycle.delete("parakeet-v3")

        XCTAssertEqual(parakeet.removedModelIDs, [])
    }

    func testDeletionSerializesOtherManagementOperationsUntilAdapterFinishes() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small", "whisper-large-v3"],
            availableModelIDs: ["whisper-small", "whisper-large-v3"]
        )
        whisper.suspendDeletions = true
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet, whisper]
        )
        await lifecycle.start()

        let deletion = Task { await lifecycle.delete("whisper-small") }
        await whisper.waitForDeletionStart()
        await lifecycle.download("whisper-large-v3")
        await lifecycle.select("whisper-large-v3")
        let deleting = await lifecycle.snapshot()
        let deletingState = SerializedDeletionState(
            operation: deleting.operation,
            downloadedModelIDs: whisper.downloadedModelIDs,
            loadedModelIDs: whisper.loadedModelIDs,
            removedModelIDs: whisper.removedModelIDs
        )
        whisper.finishDeletion()
        await deletion.value

        XCTAssertEqual(
            deletingState,
            SerializedDeletionState(
                operation: .deleting(modelID: "whisper-small"),
                downloadedModelIDs: [],
                loadedModelIDs: [],
                removedModelIDs: []
            )
        )
    }

    func testDefaultDescriptorDoesNotAllowDeletion() async {
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: []
        )

        let defaultModel = await lifecycle.snapshot().models.first { $0.id == "parakeet-v3" }

        XCTAssertEqual(defaultModel?.allowsDeletion, false)
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
        await lifecycle.start()

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
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
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
        await lifecycle.start()

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

    private func switchingLifecycle(
        transcriptionError: Error? = nil,
        transcription: (() async -> Void)? = nil
    ) -> (lifecycle: ASRModelLifecycle, residency: EngineResidencyProbe) {
        let residency = EngineResidencyProbe()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        if let transcriptionError {
            parakeet.engineTranscriptionErrors = ["parakeet-v3": transcriptionError]
        }
        parakeet.engineTranscription = transcription
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        return (
            ASRModelLifecycle(
                storedSelection: "parakeet-v3",
                adapters: [parakeet, whisper]
            ),
            residency
        )
    }

    private func suspendedSelectionLifecycle() -> (
        lifecycle: ASRModelLifecycle,
        residency: EngineResidencyProbe,
        preparation: SuspendAsyncOperations,
        whisper: FakeASRModelFamilyAdapter
    ) {
        let residency = EngineResidencyProbe()
        let preparation = SuspendAsyncOperations()
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"],
            residency: residency
        )
        let whisper = FakeASRModelFamilyAdapter(
            modelIDs: ["whisper-small", "whisper-large-v3-turbo"],
            availableModelIDs: ["whisper-small"],
            residency: residency
        )
        whisper.enginePreparation = preparation.run
        return (
            ASRModelLifecycle(
                storedSelection: "parakeet-v3",
                adapters: [parakeet, whisper]
            ),
            residency,
            preparation,
            whisper
        )
    }

    private var completedSwitchState: EngineSwitchState {
        EngineSwitchState(
            effectiveSelection: "whisper-small",
            eventLog: [
                "construct-parakeet-v3",
                "release-parakeet-v3",
                "construct-whisper-small",
            ],
            maximumResidentEngines: 1
        )
    }

    private func failureDescription(
        _ operation: () async throws -> Void
    ) async -> String? {
        do {
            try await operation()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private struct DownloadState: Equatable {
        let operation: ASRModelLifecycleOperation?
        let storedSelection: String
        let isDictationBlocked: Bool
        let isAvailable: Bool
    }

    private struct InitialBlockingState: Equatable {
        let snapshotIsBlocked: Bool
        let providerIsBlocked: Bool
        let effectiveSelection: String?
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

    private struct EffectiveSelectionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let recovery: ASRModelLifecycleRecovery?
        let loadedModelIDs: [String]
    }

    private struct BootstrapState: Equatable {
        let operation: ASRModelLifecycleOperation?
        let effectiveSelection: String?
        let isDictationBlocked: Bool
        let failure: ASRModelLifecycleFailure?
    }

    private struct BootstrapBehaviorState: Equatable {
        let snapshots: [BootstrapState]
        let downloadedModelIDs: [String]
        let loadedModelIDs: [String]
    }

    private struct BootstrapRecoveryState: Equatable {
        let selection: EffectiveSelectionState
        let downloadedModelIDs: [String]
    }

    private struct BootstrapPreparationSerializationState: Equatable {
        let operationWhilePreparing: ASRModelLifecycleOperation?
        let overlappingDownloads: [String]
        let completedSelection: String?
    }

    private struct WarmEngineState: Equatable {
        let text: String
        let loadedModelIDs: [String]
        let transcribedSamples: [[Float]]
    }

    private struct BlockedRecognitionState: Equatable {
        let captureFailure: String?
        let isDictationBlocked: Bool
        let downloadAttempts: [String]
    }

    private struct EngineSwitchState: Equatable {
        let effectiveSelection: String?
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct ActiveTranscriptionTransitionState: Equatable {
        let effectiveSelection: String?
        let isDictationBlocked: Bool
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct ActiveTranscriptionSwitchResult: Equatable {
        let text: String
        let states: [ActiveTranscriptionTransitionState]
    }

    private struct PipelineLifecycleTransitionState: Equatable {
        let effectiveSelection: String?
        let insertedTexts: [String]
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct SelectionTransitionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let operation: ASRModelLifecycleOperation?
        let isDictationBlocked: Bool
    }

    private struct TransactionalSelectionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let operation: ASRModelLifecycleOperation?
        let isDictationBlocked: Bool
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct FailedTransactionalSelectionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let operation: ASRModelLifecycleOperation?
        let failure: ASRModelLifecycleFailure?
        let isDictationBlocked: Bool
        let persisted: [String]
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct HeldSessionCancellationState: Equatable {
        let transaction: FailedTransactionalSelectionState
        let publishedCompletionOperation: ASRModelLifecycleOperation?
    }

    private struct SelectionRestorationState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let operation: ASRModelLifecycleOperation?
        let failure: ASRModelLifecycleFailure?
        let isDictationBlocked: Bool
    }

    private struct RepairedSelectionState: Equatable {
        let effectiveSelection: String?
        let recovery: ASRModelLifecycleRecovery?
        let downloadedModelIDs: [String]
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct AutomaticRestorationSerializationState: Equatable {
        let operationWhilePreparing: ASRModelLifecycleOperation?
        let overlappingDownloads: [String]
        let completedSelection: String?
        let maximumResidentEngines: Int
    }

    private struct ReconciledEngineState: Equatable {
        let effectiveSelections: [String?]
        let finalRecovery: ASRModelLifecycleRecovery?
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct LoadFailureState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let whisperIsAvailable: Bool
        let recovery: ASRModelLifecycleRecovery?
        let failure: ASRModelLifecycleFailure?
        let isDictationBlocked: Bool
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct LoadRetryState: Equatable {
        let effectiveSelection: String?
        let isDictationBlocked: Bool
        let failure: ASRModelLifecycleFailure?
        let loadedModelIDs: [String]
    }

    private struct ExplicitFallbackSelectionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let recovery: ASRModelLifecycleRecovery?
        let failure: ASRModelLifecycleFailure?
    }

    private struct UnknownSelectionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let recovery: ASRModelLifecycleRecovery?
        let catalogContainsStoredSelection: Bool
    }

    private struct DeletionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let operation: ASRModelLifecycleOperation?
        let isDictationBlocked: Bool
        let targetIsAvailable: Bool?
        let failure: ASRModelLifecycleFailure?
        let transcript: String?
        let captureFailure: String?
        let events: [String]
    }

    private struct DeletionTransition: Equatable {
        let deleting: DeletionState
        let completed: DeletionState
    }

    private struct DeletionOutcome: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let operation: ASRModelLifecycleOperation?
        let isDictationBlocked: Bool
        let availableModelIDs: [String]
        let failure: ASRModelLifecycleFailure?
        let removedModelIDs: [String]
        let events: [String]
    }

    private struct SerializedDeletionState: Equatable {
        let operation: ASRModelLifecycleOperation?
        let downloadedModelIDs: [String]
        let loadedModelIDs: [String]
        let removedModelIDs: [String]
    }
}

private struct AvailabilityOnlyASRModelFamilyAdapter: ASRModelFamilyAdapting {
    let modelIDs: Set<String> = ["parakeet-v3"]

    func isModelDataAvailable(for id: String) -> Bool {
        id == "parakeet-v3"
    }

    func downloadModelData(
        for _: String,
        progress _: @escaping @Sendable (Double) -> Void
    ) async throws {}

    func makeEngine(for id: String) throws -> Transcribing {
        throw EngineConstructionFailure(modelID: id)
    }

    func removeModelData(for _: String) async throws {}
}

private final class FakeASRModelFamilyAdapter: ASRModelFamilyAdapting, @unchecked Sendable {
    let modelIDs: Set<String>
    var suspendDownloads = false
    var suspendDeletions = false
    var completeDownloadsImmediatelyAsAvailable = false
    var downloadError: Error?
    var deletionError: Error?
    var removesAvailabilityOnPreparationFailure = true
    var availableModelIDs: Set<String> {
        lock.withLock { _availableModelIDs }
    }

    var downloadedModelIDs: [String] {
        lock.withLock { _downloadedModelIDs }
    }

    var reusedPartialModelIDs: [String] {
        lock.withLock { _reusedPartialModelIDs }
    }

    var loadedModelIDs: [String] {
        lock.withLock { _loadedModelIDs }
    }

    var removedModelIDs: [String] {
        lock.withLock { _removedModelIDs }
    }

    var transcribedSamples: [[Float]] {
        lock.withLock { _transcribedSamples }
    }

    var transcriptionTextByModelID: [String: String] = [:]
    var engineTranscriptionErrors: [String: Error] = [:]
    var enginePreparationErrors: [String: Error] = [:]
    var enginePreparation: (() async -> Void)?
    var engineTranscription: (() async -> Void)?

    private let lock = NSLock()
    private var _availableModelIDs: Set<String>
    private var _downloadedModelIDs: [String] = []
    private var _partialModelIDs: Set<String> = []
    private var _reusedPartialModelIDs: [String] = []
    private var _loadedModelIDs: [String] = []
    private var _removedModelIDs: [String] = []
    private var _transcribedSamples: [[Float]] = []
    private var activeDownloadID: String?
    private var progress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private let downloadStarted = AsyncEvent()
    private let cancellationRequested = AsyncEvent()
    private let deletionStarted = AsyncEvent()
    private var deletionContinuation: CheckedContinuation<Void, Never>?

    private let residency: EngineResidencyProbe?

    init(
        modelIDs: Set<String>,
        availableModelIDs: Set<String>,
        residency: EngineResidencyProbe? = nil
    ) {
        self.modelIDs = modelIDs
        _availableModelIDs = availableModelIDs
        self.residency = residency
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
            if completeDownloadsImmediatelyAsAvailable {
                _ = lock.withLock { _availableModelIDs.insert(id) }
            }
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

    func makeEngine(for id: String) throws -> Transcribing {
        lock.withLock { _loadedModelIDs.append(id) }
        let text = transcriptionTextByModelID[id] ?? ""
        return FakeLifecycleTranscriber(
            modelID: id,
            text: text,
            residency: residency,
            preparationError: enginePreparationErrors[id],
            preparation: enginePreparation,
            transcription: engineTranscription,
            transcriptionError: engineTranscriptionErrors[id],
            onPreparationFailure: { [weak self] in
                guard self?.removesAvailabilityOnPreparationFailure == true else { return }
                _ = self?.lock.withLock { self?._availableModelIDs.remove(id) }
            },
            onTranscribe: { [weak self] samples in
                self?.lock.withLock { self?._transcribedSamples.append(samples) }
            }
        )
    }

    func removeModelData(for id: String) async throws {
        residency?.record("delete-\(id)")
        deletionStarted.signal()
        if suspendDeletions {
            await withCheckedContinuation { continuation in
                lock.withLock { deletionContinuation = continuation }
            }
        }
        if let deletionError { throw deletionError }
        _ = lock.withLock { _availableModelIDs.remove(id) }
        lock.withLock { _removedModelIDs.append(id) }
    }

    func waitForDeletionStart() async {
        await deletionStarted.wait()
    }

    func finishDeletion() {
        let continuation = lock.withLock {
            defer { deletionContinuation = nil }
            return deletionContinuation
        }
        continuation?.resume()
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

    func setAvailable(_ available: Bool, id: String) {
        lock.withLock {
            if available {
                _availableModelIDs.insert(id)
            } else {
                _availableModelIDs.remove(id)
            }
        }
    }
}

private final class FakeLifecycleTranscriber: Transcribing {
    private let modelID: String
    private let text: String
    private let residency: EngineResidencyProbe?
    private let preparationError: Error?
    private let preparation: (() async -> Void)?
    private let transcription: (() async -> Void)?
    private let transcriptionError: Error?
    private let onPreparationFailure: () -> Void
    private let onTranscribe: ([Float]) -> Void

    init(
        modelID: String,
        text: String,
        residency: EngineResidencyProbe?,
        preparationError: Error?,
        preparation: (() async -> Void)?,
        transcription: (() async -> Void)?,
        transcriptionError: Error?,
        onPreparationFailure: @escaping () -> Void,
        onTranscribe: @escaping ([Float]) -> Void
    ) {
        self.modelID = modelID
        self.text = text
        self.residency = residency
        self.preparationError = preparationError
        self.preparation = preparation
        self.transcription = transcription
        self.transcriptionError = transcriptionError
        self.onPreparationFailure = onPreparationFailure
        self.onTranscribe = onTranscribe
        residency?.constructed(modelID)
    }

    deinit {
        residency?.released(modelID)
    }

    func prepare() async throws {
        await preparation?()
        try Task.checkCancellation()
        if let preparationError {
            onPreparationFailure()
            throw preparationError
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        await transcription?()
        if let transcriptionError { throw transcriptionError }
        onTranscribe(samples)
        return text
    }
}

private final class SuspendAsyncOperations: @unchecked Sendable {
    private let lock = NSLock()
    private let started = AsyncEvent()
    private var remainingCount: Int
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(count: Int = 1) {
        remainingCount = count
    }

    func run() async {
        let suspends = lock.withLock {
            guard remainingCount > 0 else { return false }
            remainingCount -= 1
            return true
        }
        guard suspends else { return }
        await withCheckedContinuation { continuation in
            lock.withLock { continuations.append(continuation) }
            started.signal()
        }
    }

    func waitUntilStarted() async {
        await started.wait()
    }

    func finish() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            guard !continuations.isEmpty else { return nil }
            return continuations.removeFirst()
        }
        continuation?.resume()
    }
}

private final class CancellableSelectionPreparation: @unchecked Sendable {
    private let lock = NSLock()
    private let started = AsyncEvent()
    private let cancelled = AsyncEvent()
    private let finishesOnCancellation: Bool
    private var continuation: CheckedContinuation<Void, Never>?

    init(finishesOnCancellation: Bool = true) {
        self.finishesOnCancellation = finishesOnCancellation
    }

    func run() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock { self.continuation = continuation }
                started.signal()
            }
        } onCancel: {
            self.cancelled.signal()
            if self.finishesOnCancellation {
                self.finish()
            }
        }
    }

    func waitUntilStarted() async {
        await started.wait()
    }

    func waitUntilCancelled() async {
        await cancelled.wait()
    }

    func finish() {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

private final class EngineResidencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var residentEngines = 0
    private var maximum = 0
    private var log: [String] = []

    var events: [String] {
        lock.withLock { log }
    }

    var maximumResidentEngines: Int {
        lock.withLock { maximum }
    }

    func constructed(_ modelID: String) {
        lock.withLock {
            residentEngines += 1
            maximum = max(maximum, residentEngines)
            log.append("construct-\(modelID)")
        }
    }

    func released(_ modelID: String) {
        lock.withLock {
            residentEngines -= 1
            log.append("release-\(modelID)")
        }
    }

    func record(_ event: String) {
        lock.withLock { log.append(event) }
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
