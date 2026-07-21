import Foundation

enum ModelsSplitGeometry {
    static let ledgerMinimum: CGFloat = 340
    static let inspectorMinimum: CGFloat = 270

    static func initialLedgerWidth(totalWidth: CGFloat, dividerWidth: CGFloat) -> CGFloat {
        let availableWidth = totalWidth - dividerWidth
        return min(
            max(availableWidth * 0.55, ledgerMinimum),
            availableWidth - inspectorMinimum
        )
    }
}

enum ModelsFamilyID: String, Equatable {
    case speechRecognition
    case polish
}

enum ModelsRowID: Hashable {
    case speechRecognition(String)
    case polish(String)
}

enum ModelsRating: Equatable {
    case rated(Int)
    case notRated

    var displayText: String {
        switch self {
        case let .rated(value): "\(value)/5"
        case .notRated: "—"
        }
    }

    var accessibilityText: String {
        switch self {
        case let .rated(value): "\(value) out of 5"
        case .notRated: "Not rated"
        }
    }
}

enum ModelsPrimaryAction: Equatable {
    case selected
    case selectASR(String)
    case downloadASR(String)
    case installed
    case installPolish(String)

    var statusSymbol: String {
        switch self {
        case .selected: "checkmark.circle.fill"
        case .installed: "shippingbox.fill"
        case .selectASR: "circle"
        case .downloadASR, .installPolish: "arrow.down.circle"
        }
    }
}

enum ModelsDestructiveCommand: Equatable {
    case deleteASR(String)
    case uninstallPolish(String)
}

struct ModelsDestructiveAction: Equatable {
    let command: ModelsDestructiveCommand
    let menuTitle: String
    let confirmationTitle: String
    let confirmationButtonTitle: String
    let confirmationMessage: String
    let accessibilityLabel: String
}

enum ModelsFamilyPlaceholder: Equatable {
    case checking(String)
    case unavailable(String)

    var text: String {
        switch self {
        case let .checking(text), let .unavailable(text): text
        }
    }

    var showsProgress: Bool {
        if case .checking = self {
            return true
        }
        return false
    }
}

struct ModelsRowPresentation: Equatable {
    let id: ModelsRowID
    let family: ModelsFamilyID
    let name: String
    let fit: String
    let size: String
    let speed: ModelsRating
    let quality: ModelsRating
    let state: String
    let primaryAction: ModelsPrimaryAction
    let destructiveAction: ModelsDestructiveAction?
    let isSavedASRSelection: Bool
    let description: String?

    var accessibilityLabel: String {
        var parts = [
            name,
            fit,
            "Size \(size == "—" ? "Not available" : size)",
            "Speed \(speed.accessibilityText)",
            "Quality \(quality.accessibilityText)",
            state,
        ]
        if family == .speechRecognition {
            parts.append(
                isSavedASRSelection
                    ? "Saved global ASR model selection"
                    : "Not saved as the global ASR model selection"
            )
        }
        return parts.joined(separator: ", ")
    }
}

struct ModelsInspectorPresentation: Equatable {
    let id: ModelsRowID
    let familyLabel: String
    let semanticLabel: String
    let name: String
    let fit: String
    let description: String?
    let status: String
    let familyExplanation: String
    let primaryAction: ModelsPrimaryAction
    let destructiveAction: ModelsDestructiveAction?
}

struct ModelsFamilyPresentation: Equatable {
    let id: ModelsFamilyID
    let title: String
    let semanticLabel: String
    let placeholder: ModelsFamilyPlaceholder?
    let rows: [ModelsRowPresentation]
}

struct ModelsWorkspaceProjection: Equatable {
    let sections: [ModelsFamilyPresentation]
    let inspector: ModelsInspectorPresentation?

    static func make(
        asrSnapshot: ASRModelLifecycleSnapshot?,
        installedPolishModels: [OllamaClient.InstalledModel]?,
        modes: [Mode] = [],
        inspectedID: ModelsRowID?
    ) -> ModelsWorkspaceProjection {
        let speechRows = asrSnapshot?.models.map {
            speechRow($0, storedSelection: asrSnapshot?.storedSelection)
        } ?? []
        let polishRows: [ModelsRowPresentation] = if let installedPolishModels,
                                                     !installedPolishModels.isEmpty {
            polishRows(installed: installedPolishModels, modes: modes)
        } else {
            []
        }
        let polishPlaceholder: ModelsFamilyPlaceholder? = if installedPolishModels == nil {
            .checking("Checking Ollama…")
        } else if installedPolishModels?.isEmpty == true {
            .unavailable("Ollama isn't running")
        } else {
            nil
        }
        let sections = [
            ModelsFamilyPresentation(
                id: .speechRecognition,
                title: "Speech recognition",
                semanticLabel: "Global selection",
                placeholder: asrSnapshot == nil
                    ? .checking("Checking speech models…")
                    : nil,
                rows: speechRows
            ),
            ModelsFamilyPresentation(
                id: .polish,
                title: "Polish",
                semanticLabel: "Mode inventory",
                placeholder: polishPlaceholder,
                rows: polishRows
            ),
        ]
        let rows = sections.flatMap(\.rows)
        let initialID = initialInspectionID(
            requested: inspectedID,
            rows: rows,
            snapshot: asrSnapshot
        )
        let inspectedRow = rows.first { $0.id == initialID }
        return ModelsWorkspaceProjection(
            sections: sections,
            inspector: inspectedRow.map(inspector(for:))
        )
    }

    private static func speechRow(
        _ descriptor: ASRModelDescriptor,
        storedSelection: String?
    ) -> ModelsRowPresentation {
        let isSaved = descriptor.id == storedSelection
        let action: ModelsPrimaryAction
        let state: String
        if isSaved, descriptor.isAvailable {
            action = .selected
            state = "Selected"
        } else if descriptor.isAvailable {
            action = .selectASR(descriptor.id)
            state = "Ready"
        } else {
            action = .downloadASR(descriptor.id)
            state = "Download"
        }
        return ModelsRowPresentation(
            id: .speechRecognition(descriptor.id),
            family: .speechRecognition,
            name: descriptor.name,
            fit: descriptor.languages,
            size: descriptor.size,
            speed: .rated(descriptor.speed),
            quality: .rated(descriptor.quality),
            state: state,
            primaryAction: action,
            destructiveAction: destructiveASRAction(
                descriptor,
                isSavedSelection: isSaved
            ),
            isSavedASRSelection: isSaved,
            description: descriptor.blurb
        )
    }

    private static func polishRows(
        installed: [OllamaClient.InstalledModel],
        modes: [Mode]
    ) -> [ModelsRowPresentation] {
        let installedNames = Set(installed.map(\.name))
        let installedRows = installed.map { model in
            let entry = ModelCatalog.entries.first { $0.name == model.name }
            return ModelsRowPresentation(
                id: .polish(model.name),
                family: .polish,
                name: model.name,
                fit: entry?.fit ?? "External model",
                size: model.sizeText.isEmpty ? (entry?.size ?? "—") : model.sizeText,
                speed: entry.map { .rated($0.speed) } ?? .notRated,
                quality: entry.map { .rated($0.quality) } ?? .notRated,
                state: "Installed",
                primaryAction: .installed,
                destructiveAction: destructivePolishAction(model, modes: modes),
                isSavedASRSelection: false,
                description: entry?.blurb
            )
        }
        let availableRows: [ModelsRowPresentation] = ModelCatalog.entries.compactMap { entry in
            guard !installedNames.contains(entry.name) else { return nil }
            return ModelsRowPresentation(
                id: .polish(entry.name),
                family: .polish,
                name: entry.name,
                fit: entry.fit,
                size: entry.size,
                speed: .rated(entry.speed),
                quality: .rated(entry.quality),
                state: "Install",
                primaryAction: .installPolish(entry.name),
                destructiveAction: nil,
                isSavedASRSelection: false,
                description: entry.blurb
            )
        }
        return installedRows + availableRows
    }

    private static func destructiveASRAction(
        _ descriptor: ASRModelDescriptor,
        isSavedSelection: Bool
    ) -> ModelsDestructiveAction? {
        guard descriptor.isAvailable, descriptor.allowsDeletion else { return nil }
        var message = "This removes \(descriptor.name)'s downloaded weights "
            + "and frees \(descriptor.size)."
        if isSavedSelection {
            message += " It's your current speech model, so deletion selects Parakeet instead."
        }
        return ModelsDestructiveAction(
            command: .deleteASR(descriptor.id),
            menuTitle: "Delete download…",
            confirmationTitle: "Delete \(descriptor.name)?",
            confirmationButtonTitle: "Delete",
            confirmationMessage: message,
            accessibilityLabel: "Model download actions"
        )
    }

    private static func destructivePolishAction(
        _ installed: OllamaClient.InstalledModel,
        modes: [Mode]
    ) -> ModelsDestructiveAction {
        var message = installed.sizeText.isEmpty
            ? "This permanently removes \(installed.name) from Ollama."
            : "This permanently removes \(installed.name) and frees \(installed.sizeText)."
        let affectedModes = modes.filter { $0.llmModel == installed.name }.map(\.name)
        if !affectedModes.isEmpty {
            message += " It's used by \(affectedModes.joined(separator: ", ")), so those Modes "
                + "will use raw text until another model is assigned."
        }
        return ModelsDestructiveAction(
            command: .uninstallPolish(installed.name),
            menuTitle: "Uninstall…",
            confirmationTitle: "Uninstall \(installed.name)?",
            confirmationButtonTitle: "Uninstall",
            confirmationMessage: message,
            accessibilityLabel: "Installed model actions"
        )
    }

    private static func initialInspectionID(
        requested: ModelsRowID?,
        rows: [ModelsRowPresentation],
        snapshot: ASRModelLifecycleSnapshot?
    ) -> ModelsRowID? {
        if let requested, rows.contains(where: { $0.id == requested }) {
            return requested
        }
        if let storedSelection = snapshot?.storedSelection {
            let storedID = ModelsRowID.speechRecognition(storedSelection)
            if rows.contains(where: { $0.id == storedID }) {
                return storedID
            }
        }
        if let effectiveSelection = snapshot?.effectiveSelection {
            let effectiveID = ModelsRowID.speechRecognition(effectiveSelection)
            if rows.contains(where: { $0.id == effectiveID }) {
                return effectiveID
            }
        }
        return rows.first(where: { $0.family == .speechRecognition })?.id
            ?? rows.first(where: { $0.family == .polish })?.id
    }

    private static func inspector(
        for row: ModelsRowPresentation
    ) -> ModelsInspectorPresentation {
        let familyLabel: String
        let semanticLabel: String
        let familyExplanation: String
        switch row.family {
        case .speechRecognition:
            familyLabel = "Speech recognition"
            semanticLabel = "Global selection"
            familyExplanation = "One global ASR model selection applies to every Dictation session."
        case .polish:
            familyLabel = "Polish"
            semanticLabel = "Mode inventory"
            familyExplanation = "Install models here, then assign one separately in each Mode."
        }
        return ModelsInspectorPresentation(
            id: row.id,
            familyLabel: familyLabel,
            semanticLabel: semanticLabel,
            name: row.name,
            fit: row.fit,
            description: row.description,
            status: row.state,
            familyExplanation: familyExplanation,
            primaryAction: row.primaryAction,
            destructiveAction: row.destructiveAction
        )
    }
}
