import AppKit
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class ModeSelectionProjectionTests: XCTestCase {
    private struct MenuItemState: Equatable {
        let title: String
        let selection: DictationSelection?
        let toolTip: String?
        let accessibilityLabel: String?
        let accessibilityValue: String?
        let accessibilityHelp: String?
        let state: NSControl.StateValue
    }

    func testProjectionOrdersProtectedSystemSelectionBeforeStableModes() throws {
        let casualID = try XCTUnwrap(
            ModeID(rawValue: "11111111-1111-4111-8111-111111111111")
        )
        let emailID = try XCTUnwrap(
            ModeID(rawValue: "22222222-2222-4222-8222-222222222222")
        )
        let modes = [
            Mode(
                id: casualID,
                name: "Casual",
                icon: "wand.and.sparkles",
                asrModel: "parakeet-v3",
                llmModel: "qwen2.5:3b",
                transformation: .inPlace,
                systemPrompt: "Clean it.",
                vocabulary: []
            ),
            Mode(
                id: emailID,
                name: "A very long professional email Mode name",
                icon: "future.unknown.symbol",
                asrModel: "parakeet-v3",
                llmModel: "llama3.2:3b",
                transformation: .expanding,
                systemPrompt: "Rewrite it.",
                vocabulary: []
            ),
        ]

        let projection = ModeSelectionProjection(
            modes: modes,
            selection: .mode(emailID),
            iconIsAvailable: { $0 != "future.unknown.symbol" }
        )

        XCTAssertEqual(
            projection.items,
            [
                ModeSelectionItem(
                    id: .voiceToText,
                    name: "Voice to Text",
                    icon: "waveform",
                    summary: "Raw transcription — no Polish",
                    isSelected: false,
                    isProtected: true
                ),
                ModeSelectionItem(
                    id: .mode(casualID),
                    name: "Casual",
                    icon: "wand.and.sparkles",
                    summary: "Keep wording · qwen2.5:3b",
                    isSelected: false,
                    isProtected: false
                ),
                ModeSelectionItem(
                    id: .mode(emailID),
                    name: "A very long professional email Mode name",
                    icon: "text.bubble",
                    summary: "Reshape · llama3.2:3b",
                    isSelected: true,
                    isProtected: false
                ),
            ]
        )
    }

    func testAccessibilityExposesFullModeAndSelectionState() throws {
        let id = try XCTUnwrap(
            ModeID(rawValue: "33333333-3333-4333-8333-333333333333")
        )
        let mode = Mode(
            id: id,
            name: "A full Mode name that a compact menu may truncate",
            icon: "text.bubble",
            asrModel: "parakeet-v3",
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "Clean it.",
            vocabulary: []
        )

        let projection = ModeSelectionProjection(
            modes: [mode],
            selection: .mode(id),
            iconIsAvailable: { _ in true }
        )

        XCTAssertEqual(
            projection.editableItems.map {
                [$0.accessibilityLabel, $0.accessibilityValue, $0.accessibilityHint]
            },
            [[
                "A full Mode name that a compact menu may truncate",
                "Selected",
                "Keep wording · qwen2.5:3b",
            ]]
        )
    }

    func testZeroModesKeepsVoiceToTextAsProtectedSelection() {
        let projection = ModeSelectionProjection(
            modes: [],
            selection: .voiceToText,
            iconIsAvailable: { _ in true }
        )

        XCTAssertEqual(
            [
                projection.systemItem.accessibilityLabel,
                projection.systemItem.accessibilityValue,
                projection.systemItem.accessibilityHint,
            ],
            [
                "Voice to Text, protected system selection",
                "Selected",
                "Uses raw transcription without Polish.",
            ]
        )
    }

    func testSelectingChangesOnlyIDBasedChecks() throws {
        let id = try XCTUnwrap(
            ModeID(rawValue: "44444444-4444-4444-8444-444444444444")
        )
        let mode = Mode(
            id: id,
            name: "Email",
            icon: "envelope",
            asrModel: "parakeet-v3",
            llmModel: "qwen2.5:3b",
            transformation: .expanding,
            systemPrompt: "Rewrite it.",
            vocabulary: []
        )
        let initial = ModeSelectionProjection(
            modes: [mode],
            selection: .mode(id),
            iconIsAvailable: { _ in true }
        )

        let updated = initial.selecting(.voiceToText)

        XCTAssertEqual(
            updated.items,
            [
                ModeSelectionItem(
                    id: .voiceToText,
                    name: "Voice to Text",
                    icon: "waveform",
                    summary: "Raw transcription — no Polish",
                    isSelected: true,
                    isProtected: true
                ),
                ModeSelectionItem(
                    id: .mode(id),
                    name: "Email",
                    icon: "envelope",
                    summary: "Reshape · qwen2.5:3b",
                    isSelected: false,
                    isProtected: false
                ),
            ]
        )
    }

    func testMenuItemCarriesStableIdentityAndAccessibility() throws {
        let id = try XCTUnwrap(
            ModeID(rawValue: "55555555-5555-4555-8555-555555555555")
        )
        let projectionItem = ModeSelectionItem(
            id: .mode(id),
            name: "Email",
            icon: "envelope",
            summary: "Reshape · qwen2.5:3b",
            isSelected: true,
            isProtected: false
        )

        let item = ModePresentationFactory.menuItem(
            for: projectionItem,
            target: nil,
            action: NSSelectorFromString("selectMode:")
        )

        XCTAssertEqual(
            MenuItemState(
                title: item.title,
                selection: item.representedObject as? DictationSelection,
                toolTip: item.toolTip,
                accessibilityLabel: item.accessibilityLabel(),
                accessibilityValue: item.accessibilityValue() as? String,
                accessibilityHelp: item.accessibilityHelp(),
                state: item.state
            ),
            MenuItemState(
                title: "Email",
                selection: .mode(id),
                toolTip: "Reshape · qwen2.5:3b",
                accessibilityLabel: "Email",
                accessibilityValue: "Selected",
                accessibilityHelp: "Reshape · qwen2.5:3b",
                state: .on
            )
        )
    }
}
