import Foundation

struct ModeSelectionItem: Identifiable, Equatable {
    let id: DictationSelection
    let name: String
    let icon: String
    let summary: String
    let isSelected: Bool
    let isProtected: Bool

    var accessibilityLabel: String {
        isProtected ? "\(name), protected system selection" : name
    }

    var accessibilityValue: String {
        isSelected ? "Selected" : "Not selected"
    }

    var accessibilityHint: String {
        isProtected ? "Uses raw transcription without Polish." : summary
    }

    func selecting(_ selection: DictationSelection) -> ModeSelectionItem {
        ModeSelectionItem(
            id: id,
            name: name,
            icon: icon,
            summary: summary,
            isSelected: id == selection,
            isProtected: isProtected
        )
    }
}

struct ModeSelectionProjection: Equatable {
    let items: [ModeSelectionItem]

    var systemItem: ModeSelectionItem {
        items[0]
    }

    var editableItems: ArraySlice<ModeSelectionItem> {
        items.dropFirst()
    }

    func selecting(_ selection: DictationSelection) -> ModeSelectionProjection {
        ModeSelectionProjection(items: items.map { $0.selecting(selection) })
    }

    init(
        modes: [Mode],
        selection: DictationSelection,
        iconIsAvailable: (String) -> Bool
    ) {
        let voiceToText = ModeSelectionItem(
            id: .voiceToText,
            name: "Voice to Text",
            icon: "waveform",
            summary: "Raw transcription — no Polish",
            isSelected: selection == .voiceToText,
            isProtected: true
        )
        items = [voiceToText] + modes.map { mode in
            guard let modeID = mode.id else {
                preconditionFailure("Mode selection projection requires stable Mode IDs.")
            }
            let id = DictationSelection.mode(modeID)
            let transformation = switch mode.transformation {
            case .inPlace: "Keep wording"
            case .expanding: "Reshape"
            }
            return ModeSelectionItem(
                id: id,
                name: mode.name,
                icon: iconIsAvailable(mode.icon) ? mode.icon : "text.bubble",
                summary: "\(transformation) · \(mode.llmModel ?? "Unavailable model")",
                isSelected: selection == id,
                isProtected: false
            )
        }
    }

    private init(items: [ModeSelectionItem]) {
        self.items = items
    }
}
