import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class SettingsModelTests: XCTestCase {
    func testASRPresentationDerivesCoherentStateFromOneLifecycleSnapshot() async {
        let lifecycle = ASRModelLifecycle(storedSelection: "whisper-small", adapters: [])
        let snapshot = await lifecycle.snapshot()
        let model = SettingsModel()

        model.applyASRLifecycleSnapshot(ASRModelLifecycleSnapshot(
            models: snapshot.models,
            storedSelection: "whisper-small",
            effectiveSelection: ASRModelCatalog.defaultID,
            recovery: .storedSelectionUnavailable(
                modelID: "whisper-small",
                fallbackModelID: ASRModelCatalog.defaultID
            ),
            operation: .downloading(modelID: "whisper-large-v3-turbo", fraction: 0.4),
            failure: nil,
            isDictationBlocked: false
        ))

        XCTAssertEqual(
            ASRPresentationState(
                selected: model.asrModel,
                downloading: model.asrDownloading,
                fraction: model.asrDownloadFraction,
                recovery: model.asrRecoveryMessage,
                effectiveModelName: model.effectiveASRModelName,
                actionsDisabled: model.hasActiveASRManagementOperation
            ),
            ASRPresentationState(
                selected: "whisper-small",
                downloading: "whisper-large-v3-turbo",
                fraction: 0.4,
                recovery: "Whisper small is unavailable. Using Parakeet TDT v3 until you download it again.",
                effectiveModelName: "Parakeet TDT v3",
                actionsDisabled: true
            )
        )
    }

    func testUnrelatedASROperationKeepsExistingModelFailure() {
        let model = SettingsModel()
        let failure = ASRModelLifecycleFailure.downloadFailed(
            modelID: "whisper-small",
            reason: "disk full"
        )
        model.applyASRLifecycleSnapshot(snapshot(failure: failure))
        model.applyASRLifecycleSnapshot(snapshot(
            operation: .downloading(modelID: "whisper-large-v3-turbo", fraction: 0.2)
        ))

        XCTAssertEqual(model.asrFailures.failure(for: "whisper-small"), failure)
    }

    func testRelevantASROperationClearsExistingModelFailure() {
        let model = SettingsModel()
        model.applyASRLifecycleSnapshot(snapshot(failure: .downloadFailed(
            modelID: "whisper-small",
            reason: "disk full"
        )))
        model.applyASRLifecycleSnapshot(snapshot(
            operation: .downloading(modelID: "whisper-small", fraction: nil)
        ))

        XCTAssertNil(model.asrFailures.failure(for: "whisper-small"))
    }

    func testPaneIDsMatchEachDestination() {
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(\.id),
            ["Home", "Modes", "Models", "History", "Stats", "Settings"]
        )
    }

    private func snapshot(
        operation: ASRModelLifecycleOperation? = nil,
        failure: ASRModelLifecycleFailure? = nil
    ) -> ASRModelLifecycleSnapshot {
        ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map { ASRModelDescriptor(entry: $0, isAvailable: true) },
            storedSelection: ASRModelCatalog.defaultID,
            effectiveSelection: ASRModelCatalog.defaultID,
            recovery: nil,
            operation: operation,
            failure: failure,
            isDictationBlocked: false
        )
    }

    func testPaneIconsMatchEachDestination() {
        XCTAssertEqual(
            SettingsModel.Pane.allCases.map(\.icon),
            ["house", "sparkles", "shippingbox", "clock", "chart.bar", "slider.horizontal.3"]
        )
    }

    func testOllamaDownOnlyWhenTheAvailableListIsEmpty() {
        let model = SettingsModel()
        XCTAssertFalse(model.ollamaDown)

        model.installed = []
        XCTAssertTrue(model.ollamaDown)

        model.installed = [installed("qwen2.5:3b")]
        XCTAssertFalse(model.ollamaDown)
    }

    func testPolishModelsStateCapturesOneCoherentLifecycleValue() {
        let model = SettingsModel()
        model.installed = [installed("qwen2.5:3b")]
        model.pullingModel = "gemma3:4b"
        model.pullStatus = "pulling layers"
        model.pullFraction = 0.4
        model.pullFailures = ModelsOperationFailures([
            "old:model": "Couldn't install old:model: failed",
        ])
        model.deleteFailures = ModelsOperationFailures([
            "stale:model": "Couldn't uninstall stale:model: busy",
        ])
        model.customModel = "custom:model"

        XCTAssertEqual(
            model.polishModelsState,
            ModelsPolishState(
                installed: [installed("qwen2.5:3b")],
                pullingModel: "gemma3:4b",
                pullStatus: "pulling layers",
                pullFraction: 0.4,
                pullFailures: ModelsOperationFailures([
                    "old:model": "Couldn't install old:model: failed",
                ]),
                deleteFailures: ModelsOperationFailures([
                    "stale:model": "Couldn't uninstall stale:model: busy",
                ]),
                customModel: "custom:model"
            )
        )
    }

    func testSelectedModelIsAllowedWhileAvailabilityIsUnknownOrOllamaIsDown() {
        let model = SettingsModel()
        model.selectedModel = "qwen2.5:3b"
        XCTAssertTrue(model.selectedModelInstalled)

        model.installed = []
        XCTAssertTrue(model.selectedModelInstalled)
    }

    func testSelectedModelInstalledReflectsTheAvailableModelList() {
        let model = SettingsModel()
        model.selectedModel = "qwen2.5:3b"
        model.installed = [installed("llama3.2:3b"), installed("qwen2.5:3b")]

        XCTAssertTrue(model.selectedModelInstalled)

        model.selectedModel = "missing:latest"
        XCTAssertFalse(model.selectedModelInstalled)
    }

    func testSelectedEditableModePresentationUsesProjectedIconFallback() {
        let model = SettingsModel()
        let id = ModeID.random()
        let mode = Mode(
            id: id,
            name: "Custom",
            icon: "symbol.that.is.not.available",
            asrModel: ASRModelCatalog.defaultID,
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "Keep wording.",
            vocabulary: []
        )
        model.modes = [mode]
        model.modeSelection = ModePresentationFactory.projection(
            modes: [mode],
            selection: .mode(id)
        )

        XCTAssertEqual(model.selectedEditableMode?.id, id)
        XCTAssertEqual(model.selectedEditableModeItem?.icon, "text.bubble")
    }

    private func installed(_ name: String) -> OllamaClient.InstalledModel {
        OllamaClient.InstalledModel(name: name, sizeBytes: 1)
    }
}

private struct ASRPresentationState: Equatable {
    let selected: String
    let downloading: String?
    let fraction: Double?
    let recovery: String?
    let effectiveModelName: String
    let actionsDisabled: Bool
}
