import XCTest
@testable import FoldWiseVoiceKit

final class ModeEditorPolicyTests: XCTestCase {
    func testDuplicateNameUsesLowestFreeSuffixAcrossAlreadySuffixedNames() {
        let names = ["Email", "Email Copy", "Email Copy 3", "Email Copy 4"]

        XCTAssertEqual(
            [
                ModeEditorPolicy.duplicateName(for: "Email", existingNames: names),
                ModeEditorPolicy.duplicateName(for: "Email Copy 3", existingNames: names),
                ModeEditorPolicy.duplicateName(for: "Copy", existingNames: ["Copy"]),
            ],
            ["Email Copy 2", "Email Copy 2", "Copy Copy"]
        )
    }

    func testEvaluateNormalizesValidDraftForSubmission() {
        let draft = ModeEditorDraft(
            name: "  Café   Notes \n",
            icon: "  cup.and.saucer  ",
            model: "  qwen2.5:3b  ",
            transformation: .inPlace,
            systemPrompt: "  Keep the speaker's wording.\n  Preserve this indentation.  ",
            vocabularyText: "  FoldWise  \nfoldwise\n Café\nCafe\n\n"
        )

        let evaluation = ModeEditorPolicy.evaluate(
            draft,
            existingModes: [],
            editingID: nil,
            installedModels: ["qwen2.5:3b"]
        )

        XCTAssertEqual(
            evaluation,
            ModeEditorEvaluation(
                submission: ModeEditorSubmission(
                    name: "Café Notes",
                    icon: "cup.and.saucer",
                    model: "qwen2.5:3b",
                    transformation: .inPlace,
                    systemPrompt: "Keep the speaker's wording.\n  Preserve this indentation.",
                    vocabulary: ["FoldWise", "Café", "Cafe"]
                ),
                issues: .none
            )
        )
    }

    func testEditorChoicesProvideBroadTextualIconAndTransformationPresentation() {
        let icons = ModeIconCatalog.choices

        XCTAssertEqual(
            ModeEditorChoiceSummary(
                hasAtLeastThirtyIcons: icons.count >= 30,
                iconSymbolsAreUnique: Set(icons.map(\.symbolName)).count == icons.count,
                iconIDsMatchSymbols: icons.map(\.id) == icons.map(\.symbolName),
                everyIconHasText: icons.allSatisfy { !$0.label.isEmpty },
                includesCoreSymbols: ["wand.and.sparkles", "envelope", "person.3", "terminal"]
                    .allSatisfy { symbol in icons.contains { $0.symbolName == symbol } },
                transformations: ModeTransformationChoice.all,
                transformationIDs: ModeTransformationChoice.all.map(\.id)
            ),
            ModeEditorChoiceSummary(
                hasAtLeastThirtyIcons: true,
                iconSymbolsAreUnique: true,
                iconIDsMatchSymbols: true,
                everyIconHasText: true,
                includesCoreSymbols: true,
                transformations: [
                    ModeTransformationChoice(
                        transformation: .inPlace,
                        title: "Keep wording",
                        detail: "Stays close to the transcript while fixing punctuation and wording."
                    ),
                    ModeTransformationChoice(
                        transformation: .expanding,
                        title: "Reshape",
                        detail: "May reorder and rephrase while preserving meaning."
                    ),
                ],
                transformationIDs: [.inPlace, .expanding]
            )
        )
    }

    func testEvaluateReportsEveryRequiredFieldInOnePass() {
        let evaluation = ModeEditorPolicy.evaluate(
            ModeEditorDraft(
                name: "  \n ",
                icon: "text.bubble",
                model: " \t ",
                transformation: .inPlace,
                systemPrompt: " \n ",
                vocabularyText: ""
            ),
            existingModes: [],
            editingID: nil,
            installedModels: []
        )

        XCTAssertEqual(
            evaluation,
            ModeEditorEvaluation(
                submission: nil,
                issues: ModeEditorIssues(
                    name: "Enter a Mode name.",
                    model: "Choose an installed AI model.",
                    systemPrompt: "Enter Polish instructions."
                )
            )
        )
    }

    func testEvaluateReportsPendingModelInventoryWithoutCallingModelUnavailable() {
        let evaluation = ModeEditorPolicy.evaluate(
            ModeEditorDraft(
                name: "Notes",
                icon: "text.bubble",
                model: "qwen2.5:3b",
                transformation: .inPlace,
                systemPrompt: "Keep wording.",
                vocabularyText: ""
            ),
            existingModes: [],
            editingID: nil,
            installedModels: nil
        )

        XCTAssertEqual(
            evaluation.issues.model,
            "Installed AI models are still loading. Try again in a moment."
        )
    }

    func testEditingDraftClearsTransientValidationAndPersistenceState() {
        var state = ModeEditorState(
            purpose: .add,
            draft: ModeEditorDraft(
                name: "",
                icon: "text.bubble",
                model: "",
                transformation: .inPlace,
                systemPrompt: "",
                vocabularyText: ""
            ),
            issues: ModeEditorIssues(name: "Required", model: nil, systemPrompt: nil),
            persistenceError: "Disk is read-only"
        )

        state.updateDraft(\.name, to: "Notes")

        XCTAssertEqual(state.draft.name, "Notes")
        XCTAssertEqual(state.issues, .none)
        XCTAssertNil(state.persistenceError)
    }

    func testUnavailableModelWarningTracksCurrentDraftAndKnownInventory() {
        XCTAssertNil(
            ModeEditorPolicy.unavailableModelWarning(
                for: "missing:latest",
                installedModels: nil
            )
        )
        XCTAssertNil(
            ModeEditorPolicy.unavailableModelWarning(
                for: " qwen2.5:3b ",
                installedModels: ["qwen2.5:3b"]
            )
        )
        XCTAssertEqual(
            ModeEditorPolicy.unavailableModelWarning(
                for: "missing:latest",
                installedModels: ["qwen2.5:3b"]
            ),
            "missing:latest isn't installed. Polish will use the raw transcript until you "
                + "install it in Models."
        )
    }

    func testAccessibilityPresentationExposesFullStateAndKeyboardActions() {
        let state = ModeEditorState(
            purpose: .edit(ModeID.random()),
            draft: ModeEditorDraft(
                name: "A very long Mode name that compact controls may truncate",
                icon: "symbol.that.is.not.available",
                model: "missing:latest",
                transformation: .expanding,
                systemPrompt: "Reshape this.",
                vocabularyText: "FoldWise"
            ),
            issues: ModeEditorIssues(
                name: "A Mode named 'Example' already exists.",
                model: "missing:latest isn't installed.",
                systemPrompt: "Enter Polish instructions."
            ),
            persistenceError: "Couldn't save Mode: permission denied"
        )

        let presentation = ModeEditorAccessibilityPresentation(state: state)

        XCTAssertEqual(
            [
                presentation.nameValue,
                presentation.iconValue,
                presentation.transformationValue,
                presentation.persistenceErrorLabel,
            ],
            [
                "A very long Mode name that compact controls may truncate",
                "Stored symbol: symbol.that.is.not.available",
                "Reshape",
                "Save error: Couldn't save Mode: permission denied",
            ]
        )
        XCTAssertEqual(
            [
                ModeEditorAccessibilityPresentation.validationLabel(
                    field: "Name", message: state.issues.name
                ),
                ModeEditorAccessibilityPresentation.validationLabel(
                    field: "AI model", message: state.issues.model
                ),
                ModeEditorAccessibilityPresentation.validationLabel(
                    field: "System prompt", message: state.issues.systemPrompt
                ),
            ],
            [
                "Name validation error: A Mode named 'Example' already exists.",
                "AI model validation error: missing:latest isn't installed.",
                "System prompt validation error: Enter Polish instructions.",
            ]
        )
        XCTAssertEqual(
            [presentation.saveAction, presentation.cancelAction],
            [
                ModeEditorActionPresentation(
                    title: "Retry",
                    accessibilityHint: "Validates and saves this Mode atomically",
                    keyboardAction: .defaultAction
                ),
                ModeEditorActionPresentation(
                    title: "Cancel",
                    accessibilityHint: "Discards the complete draft",
                    keyboardAction: .cancelAction
                ),
            ]
        )
    }

    func testLibraryActionsExposeTextAndReorderAvailability() {
        let presentation = ModeLibraryActionPresentation(
            modeName: "A long planning Mode name",
            index: 1,
            modeCount: 3
        )

        XCTAssertEqual(
            presentation,
            ModeLibraryActionPresentation(
                duplicateLabel: "Duplicate A long planning Mode name",
                moveUpLabel: "Move A long planning Mode name up",
                moveDownLabel: "Move A long planning Mode name down",
                deleteLabel: "Delete A long planning Mode name",
                deleteHint: "Asks for confirmation. History remains and the AI model is not "
                    + "uninstalled.",
                canMoveUp: true,
                canMoveDown: true
            )
        )
    }

    private struct ModeEditorChoiceSummary: Equatable {
        let hasAtLeastThirtyIcons: Bool
        let iconSymbolsAreUnique: Bool
        let iconIDsMatchSymbols: Bool
        let everyIconHasText: Bool
        let includesCoreSymbols: Bool
        let transformations: [ModeTransformationChoice]
        let transformationIDs: [ModeTransformation]
    }
}
