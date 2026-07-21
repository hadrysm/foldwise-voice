import XCTest
@testable import FoldWiseVoiceKit

final class ModelsWorkspaceProjectionTests: XCTestCase {
    func testSplitGeometryProtectsBothMinimumsAtCompactWidth() {
        let ledgerWidth = ModelsSplitGeometry.initialLedgerWidth(
            totalWidth: 617,
            dividerWidth: 1
        )

        XCTAssertEqual(ledgerWidth, 340)
        XCTAssertGreaterThanOrEqual(617 - 1 - ledgerWidth, 270)
    }

    func testSplitGeometryStartsNearFiftyFivePercentAtWideWidth() {
        XCTAssertEqual(
            ModelsSplitGeometry.initialLedgerWidth(totalWidth: 1001, dividerWidth: 1),
            550
        )
    }

    func testProjectionOrdersSpeechRecognitionBeforePolish() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            installedPolishModels: nil,
            inspectedID: nil
        )

        XCTAssertEqual(
            projection.sections.map { "\($0.id.rawValue):\($0.semanticLabel)" },
            ["speechRecognition:Global selection", "polish:Mode inventory"]
        )
    }

    func testProjectionKeepsFamilyLocalCheckingPlaceholders() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            installedPolishModels: nil,
            inspectedID: nil
        )

        XCTAssertEqual(
            projection.sections.map(\.placeholder),
            [
                .checking("Checking speech models…"),
                .checking("Checking Ollama…"),
            ]
        )
    }

    func testKnownUnavailableSavedSpeechModelPreservesIntentAndExplainsFallback() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "whisper-small",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"],
                recovery: .storedSelectionUnavailable(
                    modelID: "whisper-small",
                    fallbackModelID: "parakeet-v3"
                )
            ),
            installedPolishModels: nil,
            inspectedID: .speechRecognition("whisper-small")
        )
        let speech = projection.sections.first { $0.id == .speechRecognition }
        let saved = speech?.rows.first { $0.id == .speechRecognition("whisper-small") }
        let fallback = speech?.rows.first { $0.id == .speechRecognition("parakeet-v3") }

        XCTAssertEqual(
            SpeechRecoverySummary(
                notice: speech?.recoveryNotice?.message,
                savedState: saved?.state,
                savedAction: saved?.primaryAction,
                savedIndicator: saved?.isSavedASRSelection,
                fallbackState: fallback?.state,
                fallbackIndicator: fallback?.isSavedASRSelection,
                inspectorStatusExplanation: projection.inspector?.statusExplanation
            ),
            SpeechRecoverySummary(
                notice: "Whisper small is saved but unavailable. Parakeet TDT v3 is the "
                    + "Effective ASR model until you download Whisper small again.",
                savedState: "Saved · unavailable",
                savedAction: .downloadAgainASR("whisper-small"),
                savedIndicator: true,
                fallbackState: "Effective fallback",
                fallbackIndicator: false,
                inspectorStatusExplanation: "Parakeet TDT v3 remains the Effective ASR model "
                    + "until this saved model is downloaded and restored."
            )
        )
    }

    func testUnknownSavedSpeechIdentifierAppearsOnlyInRecoveryNotice() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "retired/private-model",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"],
                recovery: .storedSelectionUnknown(
                    modelID: "retired/private-model",
                    fallbackModelID: "parakeet-v3"
                )
            ),
            installedPolishModels: nil,
            inspectedID: nil
        )
        let speech = projection.sections.first { $0.id == .speechRecognition }

        XCTAssertEqual(
            UnknownSpeechRecoverySummary(
                notice: speech?.recoveryNotice?.message,
                rowIDs: speech?.rows.map(\.id),
                inspectedID: projection.inspector?.id,
                fallbackState: speech?.rows.first {
                    $0.id == .speechRecognition("parakeet-v3")
                }?.state
            ),
            UnknownSpeechRecoverySummary(
                notice: "The saved ASR model “retired/private-model” isn't recognized. "
                    + "Parakeet TDT v3 is the Effective ASR model; the saved identifier is unchanged.",
                rowIDs: ASRModelCatalog.entries.map { .speechRecognition($0.id) },
                inspectedID: .speechRecognition("parakeet-v3"),
                fallbackState: "Effective fallback"
            )
        )
    }

    func testOptionalASRDownloadProjectsCancelableProgressAndFamilyLocalExclusion() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"],
                operation: .downloading(modelID: "whisper-small", fraction: 0.42)
            ),
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
            ],
            inspectedID: .speechRecognition("whisper-small")
        )
        let speechRows = projection.sections.first { $0.id == .speechRecognition }?.rows ?? []
        let target = speechRows.first { $0.id == .speechRecognition("whisper-small") }
        let polish = projection.sections.first { $0.id == .polish }?.rows.first

        XCTAssertEqual(
            ASROperationSummary(
                targetState: target?.state,
                progress: target?.progress,
                disabledReasons: Set(speechRows.compactMap(\.managementDisabledReason)),
                inspectorProgress: projection.inspector?.progress,
                polishDisabledReason: polish?.managementDisabledReason
            ),
            ASROperationSummary(
                targetState: "42%",
                progress: ModelsProgressPresentation(
                    label: "Downloading",
                    status: "Downloading Whisper small…",
                    fraction: 0.42,
                    allowsCancellation: true
                ),
                disabledReasons: ["Another Speech recognition model operation is in progress."],
                inspectorProgress: ModelsProgressPresentation(
                    label: "Downloading",
                    status: "Downloading Whisper small…",
                    fraction: 0.42,
                    allowsCancellation: true
                ),
                polishDisabledReason: nil
            )
        )
    }

    func testASROperationMatrixProjectsCompactAndFullStatus() {
        let cases: [(ASRModelLifecycleOperation, String, ModelsProgressPresentation)] = [
            (
                .bootstrapping(fraction: nil),
                "parakeet-v3",
                ModelsProgressPresentation(
                    label: "Preparing",
                    status: "Preparing Parakeet TDT v3…",
                    fraction: nil
                )
            ),
            (
                .switching(modelID: "whisper-small"),
                "whisper-small",
                ModelsProgressPresentation(
                    label: "Switching",
                    status: "Switching to Whisper small…",
                    fraction: nil,
                    allowsCancellation: true
                )
            ),
            (
                .restoring(modelID: "whisper-small"),
                "whisper-small",
                ModelsProgressPresentation(
                    label: "Restoring",
                    status: "Restoring Whisper small as the Effective ASR model…",
                    fraction: nil
                )
            ),
            (
                .deleting(modelID: "whisper-small"),
                "whisper-small",
                ModelsProgressPresentation(
                    label: "Deleting",
                    status: "Deleting Whisper small's downloaded data…",
                    fraction: nil
                )
            ),
        ]

        XCTAssertEqual(
            cases.map { operation, targetID, _ in
                let projection = speechProjection(operation: operation, inspectedID: targetID)
                let row = projection.sections.first { $0.id == .speechRecognition }?.rows.first {
                    $0.id == .speechRecognition(targetID)
                }
                return row?.progress
            },
            cases.map { Optional($0.2) }
        )
    }

    func testTypedASRFailuresProjectPersistentTargetedRecovery() {
        let cases: [(ASRModelLifecycleFailure, String, String, ModelsPrimaryAction?)] = [
            (
                .downloadFailed(modelID: "whisper-small", reason: "disk full"),
                "whisper-small",
                "Couldn't download Whisper small: disk full",
                .downloadASR("whisper-small")
            ),
            (
                .downloadedDataInvalid(modelID: "whisper-small"),
                "whisper-small",
                "Downloaded data for Whisper small is incomplete or corrupt.",
                .downloadASR("whisper-small")
            ),
            (
                .bootstrapFailed(reason: "network unavailable"),
                "parakeet-v3",
                "Couldn't prepare the default speech model: network unavailable",
                .retryASRBootstrap
            ),
            (
                .engineLoadFailed(modelID: "whisper-small", reason: "CoreML rejected it"),
                "whisper-small",
                "Couldn't load Whisper small: CoreML rejected it",
                .selectASR("whisper-small")
            ),
            (
                .selectionFailed(modelID: "whisper-small", reason: "out of memory"),
                "whisper-small",
                "Couldn't switch to Whisper small: out of memory",
                .selectASR("whisper-small")
            ),
            (
                .selectionDegraded(
                    modelID: "whisper-small",
                    fallbackModelID: "parakeet-v3",
                    reason: "restore failed"
                ),
                "whisper-small",
                "Couldn't restore Whisper small. Using Parakeet TDT v3: restore failed",
                .selectASR("whisper-small")
            ),
            (
                .deletionFailed(modelID: "whisper-small", reason: "permission denied"),
                "whisper-small",
                "Couldn't delete Whisper small: permission denied",
                .selectASR("whisper-small")
            ),
            (
                .deletionSelectionFailed(modelID: "whisper-small", reason: "config is read-only"),
                "whisper-small",
                "Couldn't delete Whisper small: config is read-only",
                .selectASR("whisper-small")
            ),
        ]

        XCTAssertEqual(
            cases.map { failure, targetID, _, _ in
                let projection = speechFailureProjection(failure, inspectedID: targetID)
                let row = projection.sections.first { $0.id == .speechRecognition }?.rows.first {
                    $0.id == .speechRecognition(targetID)
                }
                return ASRFailureSummary(
                    state: row?.state,
                    message: projection.inspector?.errorMessage,
                    action: projection.inspector?.primaryAction
                )
            },
            cases.map { _, _, message, action in
                ASRFailureSummary(state: "Error", message: message, action: action)
            }
        )
    }

    func testModelFailureRemainsVisibleDuringUnrelatedASRWork() {
        let failure = ASRModelLifecycleFailure.downloadFailed(
            modelID: "whisper-small",
            reason: "disk full"
        )
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"],
                operation: .downloading(modelID: "whisper-large-v3-turbo", fraction: 0.2)
            ),
            asrFailures: ModelsASRFailures(["whisper-small": failure]),
            installedPolishModels: nil,
            inspectedID: .speechRecognition("whisper-small")
        )

        XCTAssertEqual(
            ASRFailureSummary(
                state: projection.inspector?.status,
                message: projection.inspector?.errorMessage,
                action: projection.inspector?.primaryAction
            ),
            ASRFailureSummary(
                state: "Error",
                message: "Couldn't download Whisper small: disk full",
                action: .downloadASR("whisper-small")
            )
        )
    }

    func testPersistedBootstrapFailureKeepsRetryWhileRecognitionRemainsBlockedAndIdle() {
        let failure = ASRModelLifecycleFailure.bootstrapFailed(reason: "network unavailable")
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: nil,
                availableIDs: [],
                isDictationBlocked: true
            ),
            asrFailures: ModelsASRFailures(["parakeet-v3": failure]),
            installedPolishModels: nil,
            inspectedID: .speechRecognition("parakeet-v3")
        )

        XCTAssertEqual(projection.inspector?.primaryAction, .retryASRBootstrap)
    }

    func testSelectedASRDeletionExplainsCommittedFallbackDuringTeardown() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "whisper-small",
                availableIDs: ["parakeet-v3", "whisper-small"],
                operation: .deleting(modelID: "whisper-small")
            ),
            installedPolishModels: nil,
            inspectedID: .speechRecognition("whisper-small")
        )

        XCTAssertEqual(
            projection.inspector?.statusExplanation,
            "Parakeet TDT v3 is now the saved ASR model selection. Existing Dictation sessions "
                + "may still be using Whisper small until deletion finishes."
        )
    }

    func testCanceledASRSelectionDoesNotProjectAnError() {
        let projection = speechFailureProjection(
            .selectionCanceled(modelID: "whisper-small"),
            inspectedID: "whisper-small"
        )
        let target = projection.sections.first { $0.id == .speechRecognition }?.rows.first {
            $0.id == .speechRecognition("whisper-small")
        }

        XCTAssertEqual(
            ASRFailureSummary(
                state: target?.state,
                message: projection.inspector?.errorMessage,
                action: projection.inspector?.primaryAction
            ),
            ASRFailureSummary(
                state: "Ready",
                message: nil,
                action: .selectASR("whisper-small")
            )
        )
    }

    func testCancelableASROperationStartFocusesInlineCancelWithoutChangingInspection() {
        let idle = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"]
        )
        let downloading = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"],
            operation: .downloading(modelID: "whisper-small", fraction: nil)
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: idle,
                to: downloading,
                inspectedID: .polish("qwen2.5:3b")
            ),
            ModelsASRFocusTransition(
                inspectedID: .polish("qwen2.5:3b"),
                target: .inlineCancel(.speechRecognition("whisper-small"))
            )
        )
    }

    func testNonCancelableASROperationStartReturnsFocusToInspectedRow() {
        let idle = snapshot(
            storedSelection: "whisper-small",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"]
        )
        let restoring = snapshot(
            storedSelection: "whisper-small",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            operation: .restoring(modelID: "whisper-small")
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: idle,
                to: restoring,
                inspectedID: .polish("qwen2.5:3b")
            ),
            ModelsASRFocusTransition(
                inspectedID: .polish("qwen2.5:3b"),
                target: .row(.polish("qwen2.5:3b"))
            )
        )
    }

    func testCompletedASROperationFocusesResultingInspectorAction() {
        let downloading = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"],
            operation: .downloading(modelID: "whisper-small", fraction: nil)
        )
        let completed = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"]
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: downloading,
                to: completed,
                inspectedID: .polish("qwen2.5:3b")
            ),
            ModelsASRFocusTransition(
                inspectedID: .speechRecognition("whisper-small"),
                target: .inspectorPrimary(.speechRecognition("whisper-small"))
            )
        )
    }

    func testCanceledASRSwitchReturnsFocusWithoutChangingInspection() {
        let switching = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: nil,
            availableIDs: ["parakeet-v3", "whisper-small"],
            operation: .switching(modelID: "whisper-small")
        )
        let canceled = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            failure: .selectionCanceled(modelID: "whisper-small")
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: switching,
                to: canceled,
                inspectedID: .polish("qwen2.5:3b")
            ),
            ModelsASRFocusTransition(
                inspectedID: .polish("qwen2.5:3b"),
                target: .row(.polish("qwen2.5:3b"))
            )
        )
    }

    func testASRDeletionFailureFocusesDestructiveRecoveryAction() {
        let deleting = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            operation: .deleting(modelID: "whisper-small")
        )
        let failed = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            failure: .deletionFailed(modelID: "whisper-small", reason: "permission denied")
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: deleting,
                to: failed,
                inspectedID: .polish("qwen2.5:3b")
            ),
            ModelsASRFocusTransition(
                inspectedID: .speechRecognition("whisper-small"),
                target: .inspectorDestructive(.speechRecognition("whisper-small"))
            )
        )
    }

    func testASRDeletionFailureFocusesPrimaryRecoveryWhenDataWasAlreadyRemoved() {
        let deleting = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            operation: .deleting(modelID: "whisper-small")
        )
        let failed = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"],
            failure: .deletionFailed(modelID: "whisper-small", reason: "cleanup failed")
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: deleting,
                to: failed,
                inspectedID: .speechRecognition("parakeet-v3")
            ),
            ModelsASRFocusTransition(
                inspectedID: .speechRecognition("whisper-small"),
                target: .inspectorPrimary(.speechRecognition("whisper-small"))
            )
        )
    }

    func testFailedASRSwitchFocusesTheFailedTargetAfterRestoringThePriorModel() {
        let restoring = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            operation: .restoring(modelID: "parakeet-v3")
        )
        let failed = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-small"],
            failure: .selectionFailed(modelID: "whisper-small", reason: "out of memory")
        )

        XCTAssertEqual(
            ModelsASRFocusTransition.resolve(
                from: restoring,
                to: failed,
                inspectedID: .polish("qwen2.5:3b")
            ),
            ModelsASRFocusTransition(
                inspectedID: .speechRecognition("whisper-small"),
                target: .inspectorPrimary(.speechRecognition("whisper-small"))
            )
        )
    }

    func testASRProgressUpdatesDoNotMoveFocusAgain() {
        let started = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"],
            operation: .downloading(modelID: "whisper-small", fraction: nil)
        )
        let progressing = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"],
            operation: .downloading(modelID: "whisper-small", fraction: 0.37)
        )

        XCTAssertNil(
            ModelsASRFocusTransition.resolve(
                from: started,
                to: progressing,
                inspectedID: .speechRecognition("parakeet-v3")
            )
        )
    }

    func testUnavailablePolishPlaceholderOffersDirectedRetry() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"]
            ),
            installedPolishModels: [],
            inspectedID: .polishPlaceholder
        )

        XCTAssertEqual(
            projection.inspector,
            ModelsInspectorPresentation(
                id: .polishPlaceholder,
                familyLabel: "Polish",
                semanticLabel: "Mode inventory",
                name: "Ollama isn't running",
                fit: "Inventory unavailable",
                description: "Start the Ollama app or run `brew services start ollama`, then retry.",
                status: "Unavailable",
                familyExplanation: "Speech recognition remains available while Polish inventory is unavailable.",
                primaryAction: .retryPolish,
                destructiveAction: nil
            )
        )
    }

    func testProjectionBuildsBaselineComparisonRowsAndActions() {
        let snapshot = snapshot(
            storedSelection: "parakeet-v3",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3", "whisper-large-v3-turbo"]
        )
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot,
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 0),
                OllamaClient.InstalledModel(name: "acme/custom:Q4", sizeBytes: 0),
            ],
            inspectedID: nil
        )

        XCTAssertEqual(
            projection.sections.flatMap(\.rows).compactMap { row -> RowSummary? in
                guard [
                    ModelsRowID.speechRecognition("parakeet-v3"),
                    ModelsRowID.speechRecognition("whisper-large-v3-turbo"),
                    ModelsRowID.speechRecognition("whisper-small"),
                    ModelsRowID.polish("qwen2.5:3b"),
                    ModelsRowID.polish("acme/custom:Q4"),
                    ModelsRowID.polish("gemma3:4b"),
                ].contains(row.id) else { return nil }
                return RowSummary(
                    id: row.id,
                    fit: row.fit,
                    size: row.size,
                    speed: row.speed,
                    quality: row.quality,
                    state: row.state,
                    action: row.primaryAction,
                    saved: row.isSavedASRSelection
                )
            },
            [
                RowSummary(
                    id: .speechRecognition("parakeet-v3"), fit: "25 languages", size: "600 MB",
                    speed: .rated(5), quality: .rated(4), state: "Selected",
                    action: .selected, saved: true
                ),
                RowSummary(
                    id: .speechRecognition("whisper-large-v3-turbo"), fit: "~99 languages",
                    size: "632 MB", speed: .rated(3), quality: .rated(4), state: "Ready",
                    action: .selectASR("whisper-large-v3-turbo"), saved: false
                ),
                RowSummary(
                    id: .speechRecognition("whisper-small"), fit: "~99 languages", size: "483 MB",
                    speed: .rated(4), quality: .rated(3), state: "Download",
                    action: .downloadASR("whisper-small"), saved: false
                ),
                RowSummary(
                    id: .polish("qwen2.5:3b"), fit: "Multilingual Modes", size: "1.9 GB",
                    speed: .rated(4), quality: .rated(3), state: "Installed",
                    action: .installed, saved: false
                ),
                RowSummary(
                    id: .polish("gemma3:4b"), fit: "Cleanup + rewrites", size: "3.3 GB",
                    speed: .rated(4), quality: .rated(4), state: "Install",
                    action: .installPolish("gemma3:4b"), saved: false
                ),
                RowSummary(
                    id: .polish("acme/custom:Q4"), fit: "External model", size: "—",
                    speed: .notRated, quality: .notRated, state: "Installed",
                    action: .installed, saved: false
                ),
            ]
        )
    }

    func testPolishPullProjectsProgressToLedgerAndInspector() {
        let projection = determinatePolishPullProjection()
        let polishRows = projection.sections.first { $0.id == .polish }?.rows ?? []

        XCTAssertEqual(
            PolishProgressSummary(
                targetProgress: polishRows.first { $0.id == .polish("gemma3:4b") }?.progress,
                inspectorFraction: projection.inspector?.progress?.fraction
            ),
            PolishProgressSummary(
                targetProgress: ModelsProgressPresentation(
                    label: "Installing",
                    status: "pulling layers",
                    fraction: 0.41
                ),
                inspectorFraction: 0.41
            )
        )
    }

    func testPolishPullDisablesCompetingMutationActions() {
        let projection = determinatePolishPullProjection()
        let polishRows = projection.sections.first { $0.id == .polish }?.rows ?? []

        XCTAssertEqual(
            polishRows.first { $0.id == .polish("qwen2.5:3b") }?.managementDisabledReason,
            "Another Polish model operation is in progress."
        )
    }

    func testPolishInstallFailureStaysWithAffectedRowAndInspector() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "acme/custom:Q4", sizeBytes: 0),
                ],
                pullFailures: ModelsOperationFailures([
                    "gemma3:4b": "Couldn't install gemma3:4b: connection refused after a long wait",
                ])
            ),
            inspectedID: .polish("gemma3:4b")
        )
        let polishRows = projection.sections.first { $0.id == .polish }?.rows ?? []

        XCTAssertEqual(
            PolishFailureSummary(
                rowFailures: polishRows.compactMap { row -> String? in
                    guard row.state == "Error" else { return nil }
                    return "\(row.name):\(row.errorMessage ?? "")"
                },
                inspectorError: projection.inspector?.errorMessage
            ),
            PolishFailureSummary(
                rowFailures: [
                    "gemma3:4b:Couldn't install gemma3:4b: connection refused after a long wait",
                ],
                inspectorError: "Couldn't install gemma3:4b: connection refused after a long wait"
            )
        )
    }

    func testPolishUninstallFailureStaysWithAffectedRow() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "acme/custom:Q4", sizeBytes: 0),
                ],
                deleteFailures: ModelsOperationFailures([
                    "acme/custom:Q4": "Couldn't uninstall acme/custom:Q4: model is still in use",
                ])
            ),
            inspectedID: .polish("acme/custom:Q4")
        )

        XCTAssertEqual(
            projection.inspector?.errorMessage,
            "Couldn't uninstall acme/custom:Q4: model is still in use"
        )
    }

    func testPolishEndsWithAnUnscoredInstallByNameUtilityRow() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ],
                customModel: "acme/very-long-custom-model:Q4"
            ),
            inspectedID: .installAnotherPolish
        )
        let utility = projection.sections.first { $0.id == .polish }?.rows.last

        XCTAssertEqual(
            PolishUtilitySummary(
                id: utility?.id,
                kind: utility?.kind,
                accessibilityLabel: utility?.accessibilityLabel,
                showsForm: projection.inspector?.showsInstallByNameForm,
                primaryAction: projection.inspector?.primaryAction,
                speed: utility?.speed,
                quality: utility?.quality
            ),
            PolishUtilitySummary(
                id: .installAnotherPolish,
                kind: .utility,
                accessibilityLabel: "Install another Polish model by name",
                showsForm: true,
                primaryAction: .installCustomPolish,
                speed: .notRated,
                quality: .notRated
            )
        )
    }

    func testInstallByNameRejectsWhitespace() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ],
                customModel: " \n\t "
            ),
            inspectedID: .installAnotherPolish
        )
        XCTAssertEqual(
            projection.inspector?.managementDisabledReason,
            "Enter a model name."
        )
    }

    func testWhitespaceInstallDraftDoesNotDisableOtherPolishControls() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ],
                customModel: " \n\t "
            ),
            inspectedID: .installAnotherPolish
        )
        let polishRows = projection.sections.first { $0.id == .polish }?.rows ?? []

        XCTAssertEqual(
            [
                projection.inspector?.inputDisabledReason,
                polishRows.first { $0.id == .polish("gemma3:4b") }?.managementDisabledReason,
            ],
            [nil, nil]
        )
    }

    func testInstallByNameDoesNotShowFailureForAnotherCustomDraft() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ],
                pullFailures: ModelsOperationFailures([
                    "old/custom:model": "Couldn't install old/custom:model: timed out",
                ]),
                customModel: "new/custom:model"
            ),
            inspectedID: .installAnotherPolish
        )

        XCTAssertNil(projection.inspector?.errorMessage)
    }

    func testPolishIndeterminatePullProjectsSpinnerStatus() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ],
                pullingModel: "gemma3:4b",
                pullStatus: "waiting for Ollama"
            ),
            inspectedID: .polish("gemma3:4b")
        )

        XCTAssertEqual(
            projection.inspector?.progress,
            ModelsProgressPresentation(
                label: "Installing",
                status: "waiting for Ollama",
                fraction: nil
            )
        )
    }

    func testCompleteCuratedLibraryExplainsThatAllRecommendationsAreInstalled() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: ModelCatalog.entries.map {
                    OllamaClient.InstalledModel(name: $0.name, sizeBytes: 1)
                }
            ),
            inspectedID: .installAnotherPolish
        )

        XCTAssertEqual(
            projection.inspector?.description,
            "All recommended models are installed. You can still install any model from "
                + "ollama.com/library by name."
        )
    }

    func testRemovedExternalPolishInspectionFallsToNextPolishRow() {
        let priorIDs: [ModelsRowID] = [
            .polish("qwen2.5:3b"),
            .polish("acme/custom:Q4"),
            .polish("gemma3:4b"),
            .installAnotherPolish,
        ]
        let withNextRow = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"]
            ),
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ]
            ),
            inspectedID: .polish("acme/custom:Q4"),
            previousPolishRowIDs: priorIDs
        )
        XCTAssertEqual(withNextRow.inspector?.id, .polish("gemma3:4b"))
    }

    func testRemovedOnlyExternalPolishInspectionFallsToEmptyPlaceholder() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"]
            ),
            polishState: ModelsPolishState(installed: []),
            inspectedID: .polish("acme/custom:Q4"),
            previousPolishRowIDs: [.polish("acme/custom:Q4")]
        )

        XCTAssertEqual(projection.inspector?.id, .polishPlaceholder)
    }

    func testRemovedLastExternalPolishInspectionFallsBackToPreviousRow() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ]
            ),
            inspectedID: .polish("acme/custom:Q4"),
            previousPolishRowIDs: [
                .polish("qwen2.5:3b"),
                .polish("acme/custom:Q4"),
            ]
        )

        XCTAssertEqual(projection.inspector?.id, .polish("qwen2.5:3b"))
    }

    func testPolishUninstallProjectsIndeterminateNonCancelableProgress() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "acme/custom:Q4", sizeBytes: 0),
                ],
                deletingModel: "acme/custom:Q4"
            ),
            inspectedID: .polish("acme/custom:Q4")
        )

        XCTAssertEqual(
            projection.inspector?.progress,
            ModelsProgressPresentation(
                label: "Uninstalling",
                status: "Removing model from Ollama…",
                fraction: nil
            )
        )
    }

    func testRemovedCatalogPolishModelTransitionsInPlaceToInstall() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: nil,
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1),
                ]
            ),
            inspectedID: .polish("gemma3:4b")
        )
        let rows = projection.sections.first { $0.id == .polish }?.rows ?? []
        let row = rows.first { $0.id == .polish("gemma3:4b") }

        XCTAssertEqual(
            CatalogTransitionSummary(
                rowIndex: rows.firstIndex { $0.id == .polish("gemma3:4b") },
                action: row?.primaryAction
            ),
            CatalogTransitionSummary(
                rowIndex: ModelCatalog.entries.firstIndex { $0.name == "gemma3:4b" },
                action: .installPolish("gemma3:4b")
            )
        )
    }

    func testInitialInspectionPrefersKnownSavedSpeechModel() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "whisper-large-v3-turbo",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3", "whisper-large-v3-turbo"]
            ),
            installedPolishModels: [],
            inspectedID: .polish("qwen2.5:3b")
        )

        XCTAssertEqual(
            projection.inspector,
            ModelsInspectorPresentation(
                id: .speechRecognition("whisper-large-v3-turbo"),
                familyLabel: "Speech recognition",
                semanticLabel: "Global selection",
                name: "Whisper large-v3-turbo",
                fit: "~99 languages",
                description: "OpenAI's Whisper, near-large-v3 accuracy at a fraction of the size. "
                    + "Downloads on first use, then runs on-device across ~99 languages.",
                status: "Selected",
                familyExplanation: "One global ASR model selection applies to every Dictation session.",
                primaryAction: .selected,
                destructiveAction: ModelsDestructiveAction(
                    command: .deleteASR("whisper-large-v3-turbo"),
                    menuTitle: "Delete download…",
                    confirmationTitle: "Delete Whisper large-v3-turbo?",
                    confirmationButtonTitle: "Delete",
                    confirmationMessage: "This removes Whisper large-v3-turbo's downloaded "
                        + "weights and frees 632 MB. It's your current speech model, so deletion "
                        + "selects Parakeet instead.",
                    accessibilityLabel: "Model download actions"
                )
            )
        )
    }

    func testRowsExposeCompleteAccessibleComparisonValues() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"]
            ),
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "acme/custom:Q4", sizeBytes: 0),
            ],
            inspectedID: nil
        )
        let rows = projection.sections.flatMap(\.rows)

        XCTAssertEqual(
            rows.compactMap { row -> String? in
                guard [
                    ModelsRowID.speechRecognition("parakeet-v3"),
                    ModelsRowID.polish("acme/custom:Q4"),
                ].contains(row.id) else { return nil }
                return row.accessibilityLabel
            },
            [
                "Parakeet TDT v3, 25 languages, Size 600 MB, Speed 5 out of 5, "
                    + "Quality 4 out of 5, Selected, Saved global ASR model selection",
                "acme/custom:Q4, External model, Size Not available, Speed Not rated, "
                    + "Quality Not rated, Installed",
            ]
        )
    }

    func testInitialInspectionUsesEffectiveFallbackForUnknownSavedModel() {
        let snapshot = snapshot(
            storedSelection: "retired-model",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"]
        )
        let initial = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot,
            installedPolishModels: [],
            inspectedID: nil
        )

        XCTAssertEqual(initial.inspector?.id, .speechRecognition("parakeet-v3"))
    }

    func testInspectionPreservesAvailableRequestAcrossRefresh() {
        let snapshot = snapshot(
            storedSelection: "retired-model",
            effectiveSelection: "parakeet-v3",
            availableIDs: ["parakeet-v3"]
        )
        let refreshed = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot,
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "acme/custom:Q4", sizeBytes: 0),
            ],
            inspectedID: .polish("qwen2.5:7b")
        )

        XCTAssertEqual(refreshed.inspector?.id, .polish("qwen2.5:7b"))
    }

    func testInitialInspectionUsesFirstSpeechRowWithoutKnownOrEffectiveSelection() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "retired-model",
                effectiveSelection: nil,
                availableIDs: []
            ),
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 0),
            ],
            inspectedID: nil
        )

        XCTAssertEqual(projection.inspector?.id, .speechRecognition("parakeet-v3"))
    }

    func testInitialInspectionUsesFirstPolishRowWithoutSpeechRows() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: ASRModelLifecycleSnapshot(
                models: [],
                storedSelection: "retired-model",
                effectiveSelection: nil,
                recovery: nil,
                operation: nil,
                failure: nil,
                isDictationBlocked: true
            ),
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 0),
            ],
            inspectedID: nil
        )

        XCTAssertEqual(projection.inspector?.id, .polish("gemma3:1b"))
    }

    func testPolishUninstallActionExplainsAffectedModesAndRawTextFallback() {
        let projection = ModelsWorkspaceProjection.make(
            asrSnapshot: ASRModelLifecycleSnapshot(
                models: [],
                storedSelection: "retired-model",
                effectiveSelection: nil,
                recovery: nil,
                operation: nil,
                failure: nil,
                isDictationBlocked: true
            ),
            installedPolishModels: [
                OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 0),
            ],
            modes: [mode(name: "Email"), mode(name: "Bullets")],
            inspectedID: .polish("qwen2.5:3b")
        )

        XCTAssertEqual(
            projection.inspector?.destructiveAction?.confirmationMessage,
            "This permanently removes qwen2.5:3b from Ollama. It's used by Email, Bullets, "
                + "so those Modes will use raw text until another model is assigned."
        )
    }

    private struct PolishProgressSummary: Equatable {
        let targetProgress: ModelsProgressPresentation?
        let inspectorFraction: Double?
    }

    private struct SpeechRecoverySummary: Equatable {
        let notice: String?
        let savedState: String?
        let savedAction: ModelsPrimaryAction?
        let savedIndicator: Bool?
        let fallbackState: String?
        let fallbackIndicator: Bool?
        let inspectorStatusExplanation: String?
    }

    private struct UnknownSpeechRecoverySummary: Equatable {
        let notice: String?
        let rowIDs: [ModelsRowID]?
        let inspectedID: ModelsRowID?
        let fallbackState: String?
    }

    private struct ASROperationSummary: Equatable {
        let targetState: String?
        let progress: ModelsProgressPresentation?
        let disabledReasons: Set<String>
        let inspectorProgress: ModelsProgressPresentation?
        let polishDisabledReason: String?
    }

    private struct ASRFailureSummary: Equatable {
        let state: String?
        let message: String?
        let action: ModelsPrimaryAction?
    }

    private struct PolishFailureSummary: Equatable {
        let rowFailures: [String]
        let inspectorError: String?
    }

    private struct PolishUtilitySummary: Equatable {
        let id: ModelsRowID?
        let kind: ModelsRowKind?
        let accessibilityLabel: String?
        let showsForm: Bool?
        let primaryAction: ModelsPrimaryAction?
        let speed: ModelsRating?
        let quality: ModelsRating?
    }

    private struct CatalogTransitionSummary: Equatable {
        let rowIndex: Int?
        let action: ModelsPrimaryAction?
    }

    private func determinatePolishPullProjection() -> ModelsWorkspaceProjection {
        ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3"]
            ),
            polishState: ModelsPolishState(
                installed: [
                    OllamaClient.InstalledModel(name: "qwen2.5:3b", sizeBytes: 1_900_000_000),
                ],
                pullingModel: "gemma3:4b",
                pullStatus: "pulling layers",
                pullFraction: 0.41
            ),
            inspectedID: .polish("gemma3:4b")
        )
    }

    private func speechProjection(
        operation: ASRModelLifecycleOperation,
        inspectedID: String
    ) -> ModelsWorkspaceProjection {
        ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: ["parakeet-v3", "whisper-small"],
                operation: operation
            ),
            installedPolishModels: nil,
            inspectedID: .speechRecognition(inspectedID)
        )
    }

    private func speechFailureProjection(
        _ failure: ASRModelLifecycleFailure,
        inspectedID: String
    ) -> ModelsWorkspaceProjection {
        let availableIDs: Set<String> = switch failure {
        case .downloadFailed, .downloadedDataInvalid:
            ["parakeet-v3"]
        case .bootstrapFailed, .engineLoadFailed, .selectionFailed, .selectionCanceled,
             .selectionDegraded, .deletionFailed, .deletionSelectionFailed:
            ["parakeet-v3", "whisper-small"]
        }
        return ModelsWorkspaceProjection.make(
            asrSnapshot: snapshot(
                storedSelection: "parakeet-v3",
                effectiveSelection: "parakeet-v3",
                availableIDs: availableIDs,
                failure: failure,
                isDictationBlocked: failure.allowsBootstrapRetry
            ),
            installedPolishModels: nil,
            inspectedID: .speechRecognition(inspectedID)
        )
    }

    private struct RowSummary: Equatable {
        let id: ModelsRowID
        let fit: String
        let size: String
        let speed: ModelsRating
        let quality: ModelsRating
        let state: String
        let action: ModelsPrimaryAction
        let saved: Bool
    }

    private func snapshot(
        storedSelection: String,
        effectiveSelection: String?,
        availableIDs: Set<String>,
        recovery: ASRModelLifecycleRecovery? = nil,
        operation: ASRModelLifecycleOperation? = nil,
        failure: ASRModelLifecycleFailure? = nil,
        isDictationBlocked: Bool = false
    ) -> ASRModelLifecycleSnapshot {
        ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map {
                ASRModelDescriptor(entry: $0, isAvailable: availableIDs.contains($0.id))
            },
            storedSelection: storedSelection,
            effectiveSelection: effectiveSelection,
            recovery: recovery,
            operation: operation,
            failure: failure,
            isDictationBlocked: isDictationBlocked
        )
    }

    private func mode(name: String) -> Mode {
        Mode(
            id: .random(),
            name: name,
            icon: "text.bubble",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "Keep wording.",
            vocabulary: []
        )
    }
}
