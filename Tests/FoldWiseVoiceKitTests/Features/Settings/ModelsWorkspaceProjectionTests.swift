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
        availableIDs: Set<String>
    ) -> ASRModelLifecycleSnapshot {
        ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map {
                ASRModelDescriptor(entry: $0, isAvailable: availableIDs.contains($0.id))
            },
            storedSelection: storedSelection,
            effectiveSelection: effectiveSelection,
            recovery: nil,
            operation: nil,
            failure: nil,
            isDictationBlocked: false
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
