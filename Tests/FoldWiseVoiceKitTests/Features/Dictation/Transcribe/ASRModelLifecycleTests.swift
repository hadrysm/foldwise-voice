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

    func testInitialSnapshotAndTranscribingSeamBothBlockUntilStartupCompletes() async {
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [
                FakeASRModelFamilyAdapter(
                    modelIDs: ["parakeet-v3"],
                    availableModelIDs: ["parakeet-v3"]
                ),
            ]
        )
        let transcriber: Transcribing = lifecycle

        let snapshot = await lifecycle.snapshot()

        XCTAssertEqual(
            InitialBlockingState(
                snapshotIsBlocked: snapshot.isDictationBlocked,
                transcriberIsBlocked: transcriber.isDictationBlocked,
                effectiveSelection: snapshot.effectiveSelection
            ),
            InitialBlockingState(
                snapshotIsBlocked: true,
                transcriberIsBlocked: true,
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

    func testLifecycleIsTheWarmTranscribingSeam() async throws {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        parakeet.transcriptionTextByModelID = ["parakeet-v3": "hello from lifecycle"]
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        let transcriber: Transcribing = lifecycle

        await lifecycle.start()
        let text = try await transcriber.transcribe([0.1, 0.2])

        XCTAssertEqual(
            WarmEngineState(
                text: text,
                ready: transcriber.ready,
                loadedModelIDs: parakeet.loadedModelIDs,
                transcribedSamples: parakeet.transcribedSamples
            ),
            WarmEngineState(
                text: "hello from lifecycle",
                ready: true,
                loadedModelIDs: ["parakeet-v3"],
                transcribedSamples: [[0.1, 0.2]]
            )
        )
    }

    func testWarmupForwardsEngineSignalsThroughTheTranscribingSeam() async {
        let parakeet = FakeASRModelFamilyAdapter(
            modelIDs: ["parakeet-v3"],
            availableModelIDs: ["parakeet-v3"]
        )
        let lifecycle = ASRModelLifecycle(
            storedSelection: "parakeet-v3",
            adapters: [parakeet]
        )
        let transcriber: Transcribing = lifecycle
        let callbacks = LifecycleCallbackProbe()
        transcriber.onLoading = { callbacks.recordLoading($0) }
        transcriber.onDownloadProgress = { callbacks.recordProgress($0) }

        transcriber.warmup()
        _ = await snapshot(from: lifecycle) { $0.effectiveSelection == "parakeet-v3" }
        parakeet.latestEngine?.onLoading?(true)
        parakeet.latestEngine?.onDownloadProgress?(0.4)

        XCTAssertEqual(
            LifecycleTranscribingState(
                ready: transcriber.ready,
                isDictationBlocked: transcriber.isDictationBlocked,
                hasLoadingCallback: transcriber.onLoading != nil,
                hasProgressCallback: transcriber.onDownloadProgress != nil,
                loadingEvents: callbacks.loadingEvents,
                progressEvents: callbacks.progressEvents
            ),
            LifecycleTranscribingState(
                ready: true,
                isDictationBlocked: false,
                hasLoadingCallback: true,
                hasProgressCallback: true,
                loadingEvents: [true],
                progressEvents: [0.4]
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
        let transcriber: Transcribing = lifecycle

        let transcriptionFailure = await failureDescription {
            _ = try await transcriber.transcribe([0.1])
        }
        let preparationFailure = await failureDescription {
            try await transcriber.prepare()
        }

        XCTAssertEqual(
            BlockedRecognitionState(
                transcriptionFailure: transcriptionFailure,
                preparationFailure: preparationFailure,
                isDictationBlocked: transcriber.isDictationBlocked,
                downloadAttempts: parakeet.downloadedModelIDs
            ),
            BlockedRecognitionState(
                transcriptionFailure: "Speech recognition is unavailable.",
                preparationFailure: "Speech recognition is unavailable.",
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

    func testSelectionUpdateCannotUnblockDictationDuringDefaultBootstrap() async {
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
        await lifecycle.updateStoredSelection("whisper-small")
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
                    effectiveSelection: "whisper-small",
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
        await lifecycle.updateStoredSelection("whisper-small")
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

    func testRepeatedSelectionUpdateDoesNotLoadASecondCandidateEngine() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendFirstEnginePreparation()
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

        let firstUpdate = Task { await lifecycle.updateStoredSelection("whisper-small") }
        await preparation.waitUntilStarted()
        await lifecycle.updateStoredSelection("whisper-small")
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

    func testSelectionUpdatePublishesBlockedStateBeforeReplacingTheEffectiveEngine() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendFirstEnginePreparation()
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

        let selection = Task { await lifecycle.updateStoredSelection("whisper-small") }
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
                    isDictationBlocked: transition.isDictationBlocked
                ),
                SelectionTransitionState(
                    storedSelection: completed.storedSelection,
                    effectiveSelection: completed.effectiveSelection,
                    isDictationBlocked: completed.isDictationBlocked
                ),
            ],
            [
                SelectionTransitionState(
                    storedSelection: "whisper-small",
                    effectiveSelection: nil,
                    isDictationBlocked: true
                ),
                SelectionTransitionState(
                    storedSelection: "whisper-small",
                    effectiveSelection: "whisper-small",
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

    func testDifferentSelectionUpdateDuringPreparationWaitsAndSupersedesStaleCandidate() async {
        let residency = EngineResidencyProbe()
        let preparation = SuspendFirstEnginePreparation()
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

        let first = Task { await lifecycle.updateStoredSelection("whisper-small") }
        await preparation.waitUntilStarted()
        await lifecycle.updateStoredSelection("parakeet-v3")
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
                    effectiveSelection: "parakeet-v3",
                    eventLog: [
                        "construct-parakeet-v3",
                        "release-parakeet-v3",
                        "construct-whisper-small",
                        "release-whisper-small",
                        "construct-parakeet-v3",
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
        let transcriberIsBlocked: Bool
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

    private struct WarmEngineState: Equatable {
        let text: String
        let ready: Bool
        let loadedModelIDs: [String]
        let transcribedSamples: [[Float]]
    }

    private struct LifecycleTranscribingState: Equatable {
        let ready: Bool
        let isDictationBlocked: Bool
        let hasLoadingCallback: Bool
        let hasProgressCallback: Bool
        let loadingEvents: [Bool]
        let progressEvents: [Double]
    }

    private struct BlockedRecognitionState: Equatable {
        let transcriptionFailure: String?
        let preparationFailure: String?
        let isDictationBlocked: Bool
        let downloadAttempts: [String]
    }

    private struct EngineSwitchState: Equatable {
        let effectiveSelection: String?
        let eventLog: [String]
        let maximumResidentEngines: Int
    }

    private struct SelectionTransitionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let isDictationBlocked: Bool
    }

    private struct RepairedSelectionState: Equatable {
        let effectiveSelection: String?
        let recovery: ASRModelLifecycleRecovery?
        let downloadedModelIDs: [String]
        let eventLog: [String]
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

    private struct UnknownSelectionState: Equatable {
        let storedSelection: String
        let effectiveSelection: String?
        let recovery: ASRModelLifecycleRecovery?
        let catalogContainsStoredSelection: Bool
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
}

private final class FakeASRModelFamilyAdapter: ASRModelFamilyAdapting, @unchecked Sendable {
    let modelIDs: Set<String>
    var suspendDownloads = false
    var completeDownloadsImmediatelyAsAvailable = false
    var downloadError: Error?
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

    var transcribedSamples: [[Float]] {
        lock.withLock { _transcribedSamples }
    }

    var latestEngine: FakeLifecycleTranscriber? {
        lock.withLock { _latestEngine }
    }

    var transcriptionTextByModelID: [String: String] = [:]
    var enginePreparationErrors: [String: Error] = [:]
    var enginePreparation: (() async -> Void)?

    private let lock = NSLock()
    private var _availableModelIDs: Set<String>
    private var _downloadedModelIDs: [String] = []
    private var _partialModelIDs: Set<String> = []
    private var _reusedPartialModelIDs: [String] = []
    private var _loadedModelIDs: [String] = []
    private var _transcribedSamples: [[Float]] = []
    private weak var _latestEngine: FakeLifecycleTranscriber?
    private var activeDownloadID: String?
    private var progress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private let downloadStarted = AsyncEvent()
    private let cancellationRequested = AsyncEvent()

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
        let engine = FakeLifecycleTranscriber(
            modelID: id,
            text: text,
            residency: residency,
            preparationError: enginePreparationErrors[id],
            preparation: enginePreparation,
            onPreparationFailure: { [weak self] in
                guard self?.removesAvailabilityOnPreparationFailure == true else { return }
                _ = self?.lock.withLock { self?._availableModelIDs.remove(id) }
            },
            onTranscribe: { [weak self] samples in
                self?.lock.withLock { self?._transcribedSamples.append(samples) }
            }
        )
        lock.withLock { _latestEngine = engine }
        return engine
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
    private let onPreparationFailure: () -> Void
    private let onTranscribe: ([Float]) -> Void
    private(set) var ready = false
    var onLoading: ((Bool) -> Void)?
    var onDownloadProgress: ((Double) -> Void)?

    init(
        modelID: String,
        text: String,
        residency: EngineResidencyProbe?,
        preparationError: Error?,
        preparation: (() async -> Void)?,
        onPreparationFailure: @escaping () -> Void,
        onTranscribe: @escaping ([Float]) -> Void
    ) {
        self.modelID = modelID
        self.text = text
        self.residency = residency
        self.preparationError = preparationError
        self.preparation = preparation
        self.onPreparationFailure = onPreparationFailure
        self.onTranscribe = onTranscribe
        residency?.constructed(modelID)
    }

    deinit {
        residency?.released(modelID)
    }

    func warmup() {}

    func prepare() async throws {
        await preparation?()
        if let preparationError {
            onPreparationFailure()
            throw preparationError
        }
        ready = true
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        onTranscribe(samples)
        return text
    }
}

private final class SuspendFirstEnginePreparation: @unchecked Sendable {
    private let lock = NSLock()
    private let started = AsyncEvent()
    private var shouldSuspend = true
    private var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        let suspends = lock.withLock {
            defer { shouldSuspend = false }
            return shouldSuspend
        }
        guard suspends else { return }
        started.signal()
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func waitUntilStarted() async {
        await started.wait()
    }

    func finish() {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume()
    }
}

private final class LifecycleCallbackProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var loading: [Bool] = []
    private var progress: [Double] = []

    var loadingEvents: [Bool] {
        lock.withLock { loading }
    }

    var progressEvents: [Double] {
        lock.withLock { progress }
    }

    func recordLoading(_ value: Bool) {
        lock.withLock { loading.append(value) }
    }

    func recordProgress(_ value: Double) {
        lock.withLock { progress.append(value) }
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
