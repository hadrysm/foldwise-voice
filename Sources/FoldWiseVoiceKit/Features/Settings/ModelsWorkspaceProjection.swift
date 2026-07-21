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
    case polishPlaceholder
    case installAnotherPolish
}

enum ModelsRowKind: Equatable {
    case model
    case utility
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
    case installCustomPolish
    case retryPolish

    var statusSymbol: String {
        switch self {
        case .selected: "checkmark.circle.fill"
        case .installed: "shippingbox.fill"
        case .selectASR: "circle"
        case .downloadASR, .installPolish, .installCustomPolish: "arrow.down.circle"
        case .retryPolish: "arrow.clockwise"
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

struct ModelsProgressPresentation: Equatable {
    let label: String
    let status: String
    let fraction: Double?

    var compactState: String {
        fraction.map { "\(Int($0 * 100))%" } ?? label
    }
}

struct ModelsOperationFailures: Equatable {
    private var messagesByTarget: [String: String]

    init(_ messagesByTarget: [String: String] = [:]) {
        self.messagesByTarget = messagesByTarget
    }

    mutating func record(_ message: String, for target: String) {
        messagesByTarget[target] = message
    }

    mutating func clear(for target: String) {
        messagesByTarget[target] = nil
    }

    func message(for target: String) -> String? {
        messagesByTarget[target]
    }

    func firstMessage(where targetMatches: (String) -> Bool) -> String? {
        messagesByTarget.first { targetMatches($0.key) }?.value
    }
}

struct ModelsPolishState: Equatable {
    let installed: [OllamaClient.InstalledModel]?
    let pullingModel: String?
    let pullStatus: String
    let pullFraction: Double?
    let deletingModel: String?
    let pullFailures: ModelsOperationFailures
    let deleteFailures: ModelsOperationFailures
    let customModel: String

    init(
        installed: [OllamaClient.InstalledModel]?,
        pullingModel: String? = nil,
        pullStatus: String = "",
        pullFraction: Double? = nil,
        deletingModel: String? = nil,
        pullFailures: ModelsOperationFailures = ModelsOperationFailures(),
        deleteFailures: ModelsOperationFailures = ModelsOperationFailures(),
        customModel: String = ""
    ) {
        self.installed = installed
        self.pullingModel = pullingModel
        self.pullStatus = pullStatus
        self.pullFraction = pullFraction
        self.deletingModel = deletingModel
        self.pullFailures = pullFailures
        self.deleteFailures = deleteFailures
        self.customModel = customModel
    }

    var mutationDisabledReason: String? {
        pullingModel == nil && deletingModel == nil
            ? nil
            : "Another Polish model operation is in progress."
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
    let progress: ModelsProgressPresentation?
    let managementDisabledReason: String?
    let inputDisabledReason: String?
    let errorMessage: String?
    let kind: ModelsRowKind

    init(
        id: ModelsRowID,
        family: ModelsFamilyID,
        name: String,
        fit: String,
        size: String,
        speed: ModelsRating,
        quality: ModelsRating,
        state: String,
        primaryAction: ModelsPrimaryAction,
        destructiveAction: ModelsDestructiveAction?,
        isSavedASRSelection: Bool,
        description: String?,
        progress: ModelsProgressPresentation? = nil,
        managementDisabledReason: String? = nil,
        inputDisabledReason: String? = nil,
        errorMessage: String? = nil,
        kind: ModelsRowKind = .model
    ) {
        self.id = id
        self.family = family
        self.name = name
        self.fit = fit
        self.size = size
        self.speed = speed
        self.quality = quality
        self.state = state
        self.primaryAction = primaryAction
        self.destructiveAction = destructiveAction
        self.isSavedASRSelection = isSavedASRSelection
        self.description = description
        self.progress = progress
        self.managementDisabledReason = managementDisabledReason
        self.inputDisabledReason = inputDisabledReason
        self.errorMessage = errorMessage
        self.kind = kind
    }

    var accessibilityLabel: String {
        if kind == .utility {
            return "Install another Polish model by name"
        }
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
    let progress: ModelsProgressPresentation?
    let managementDisabledReason: String?
    let inputDisabledReason: String?
    let errorMessage: String?
    let showsInstallByNameForm: Bool

    init(
        id: ModelsRowID,
        familyLabel: String,
        semanticLabel: String,
        name: String,
        fit: String,
        description: String?,
        status: String,
        familyExplanation: String,
        primaryAction: ModelsPrimaryAction,
        destructiveAction: ModelsDestructiveAction?,
        progress: ModelsProgressPresentation? = nil,
        managementDisabledReason: String? = nil,
        inputDisabledReason: String? = nil,
        errorMessage: String? = nil,
        showsInstallByNameForm: Bool = false
    ) {
        self.id = id
        self.familyLabel = familyLabel
        self.semanticLabel = semanticLabel
        self.name = name
        self.fit = fit
        self.description = description
        self.status = status
        self.familyExplanation = familyExplanation
        self.primaryAction = primaryAction
        self.destructiveAction = destructiveAction
        self.progress = progress
        self.managementDisabledReason = managementDisabledReason
        self.inputDisabledReason = inputDisabledReason
        self.errorMessage = errorMessage
        self.showsInstallByNameForm = showsInstallByNameForm
    }
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
        inspectedID: ModelsRowID?,
        previousPolishRowIDs: [ModelsRowID] = []
    ) -> ModelsWorkspaceProjection {
        make(
            asrSnapshot: asrSnapshot,
            polishState: ModelsPolishState(installed: installedPolishModels),
            modes: modes,
            inspectedID: inspectedID,
            previousPolishRowIDs: previousPolishRowIDs
        )
    }

    static func make(
        asrSnapshot: ASRModelLifecycleSnapshot?,
        polishState: ModelsPolishState,
        modes: [Mode] = [],
        inspectedID: ModelsRowID?,
        previousPolishRowIDs: [ModelsRowID] = []
    ) -> ModelsWorkspaceProjection {
        let speechRows = asrSnapshot?.models.map {
            speechRow($0, storedSelection: asrSnapshot?.storedSelection)
        } ?? []
        let polishRows: [ModelsRowPresentation] = if let installed = polishState.installed,
                                                     !installed.isEmpty {
            polishRows(installed: installed, modes: modes, state: polishState)
        } else {
            []
        }
        let polishPlaceholder: ModelsFamilyPlaceholder? = if polishState.installed == nil {
            .checking("Checking Ollama…")
        } else if polishState.installed?.isEmpty == true {
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
            snapshot: asrSnapshot,
            polishPlaceholder: polishPlaceholder,
            previousPolishRowIDs: previousPolishRowIDs
        )
        let inspectedRow = rows.first { $0.id == initialID }
        return ModelsWorkspaceProjection(
            sections: sections,
            inspector: inspectedRow.map(inspector(for:))
                ?? polishPlaceholderInspector(id: initialID, placeholder: polishPlaceholder)
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
        modes: [Mode],
        state: ModelsPolishState
    ) -> [ModelsRowPresentation] {
        let installedNames = Set(installed.map(\.name))
        let installedByName = installed.reduce(into: [String: OllamaClient.InstalledModel]()) {
            $0[$1.name] = $1
        }
        let catalogRows = ModelCatalog.entries.map { entry in
            if let model = installedByName[entry.name] {
                return installedPolishRow(model, entry: entry, modes: modes, state: state)
            }
            return availablePolishRow(entry, state: state)
        }
        let catalogNames = Set(ModelCatalog.entries.map(\.name))
        let externalRows = installed.filter { !catalogNames.contains($0.name) }.map {
            installedPolishRow($0, entry: nil, modes: modes, state: state)
        }
        let customTarget = state.pullingModel.flatMap { target in
            installedNames.contains(target) || catalogNames.contains(target)
                ? nil
                : target
        }
        let trimmedCustomModel = state.customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let customFailure = state.pullFailures.message(for: trimmedCustomModel)
            ?? state.pullFailures.firstMessage {
                !installedNames.contains($0) && !catalogNames.contains($0)
            }
        let progress = customTarget.map { target in
            ModelsProgressPresentation(
                label: "Installing",
                status: state.pullStatus.isEmpty ? "Installing \(target)…" : state.pullStatus,
                fraction: state.pullFraction
            )
        }
        let allRecommendedInstalled = ModelCatalog.entries.allSatisfy { installedNames.contains($0.name) }
        let installByNameDisabledReason = state.mutationDisabledReason
            ?? (trimmedCustomModel.isEmpty
                ? "Enter a model name."
                : nil)
        let utility = ModelsRowPresentation(
            id: .installAnotherPolish,
            family: .polish,
            name: "Install another model…",
            fit: "Any Ollama model name",
            size: "—",
            speed: .notRated,
            quality: .notRated,
            state: progress?.compactState ?? (customFailure == nil ? "" : "Error"),
            primaryAction: .installCustomPolish,
            destructiveAction: nil,
            isSavedASRSelection: false,
            description: allRecommendedInstalled
                ? "All recommended models are installed. You can still install any model from ollama.com/library by name."
                : "Install any model from ollama.com/library by entering its model:tag name.",
            progress: progress,
            managementDisabledReason: installByNameDisabledReason,
            inputDisabledReason: state.mutationDisabledReason,
            errorMessage: customFailure,
            kind: .utility
        )
        return catalogRows + externalRows + [utility]
    }

    private static func installedPolishRow(
        _ model: OllamaClient.InstalledModel,
        entry: ModelCatalog.Entry?,
        modes: [Mode],
        state: ModelsPolishState
    ) -> ModelsRowPresentation {
        let error = state.pullFailures.message(for: model.name)
            ?? state.deleteFailures.message(for: model.name)
        let progress = polishProgress(for: model.name, state: state)
        return ModelsRowPresentation(
            id: .polish(model.name),
            family: .polish,
            name: model.name,
            fit: entry?.fit ?? "External model",
            size: model.sizeText.isEmpty ? (entry?.size ?? "—") : model.sizeText,
            speed: entry.map { .rated($0.speed) } ?? .notRated,
            quality: entry.map { .rated($0.quality) } ?? .notRated,
            state: progress?.compactState ?? (error == nil ? "Installed" : "Error"),
            primaryAction: .installed,
            destructiveAction: destructivePolishAction(model, modes: modes),
            isSavedASRSelection: false,
            description: entry?.blurb,
            progress: progress,
            managementDisabledReason: state.mutationDisabledReason,
            errorMessage: error
        )
    }

    private static func availablePolishRow(
        _ entry: ModelCatalog.Entry,
        state: ModelsPolishState
    ) -> ModelsRowPresentation {
        let error = state.pullFailures.message(for: entry.name)
        let progress = polishProgress(for: entry.name, state: state)
        return ModelsRowPresentation(
            id: .polish(entry.name),
            family: .polish,
            name: entry.name,
            fit: entry.fit,
            size: entry.size,
            speed: .rated(entry.speed),
            quality: .rated(entry.quality),
            state: progress?.compactState ?? (error == nil ? "Install" : "Error"),
            primaryAction: .installPolish(entry.name),
            destructiveAction: nil,
            isSavedASRSelection: false,
            description: entry.blurb,
            progress: progress,
            managementDisabledReason: state.mutationDisabledReason,
            errorMessage: error
        )
    }

    private static func polishProgress(
        for target: String,
        state: ModelsPolishState
    ) -> ModelsProgressPresentation? {
        if state.pullingModel == target {
            return ModelsProgressPresentation(
                label: "Installing",
                status: state.pullStatus,
                fraction: state.pullFraction
            )
        }
        if state.deletingModel == target {
            return ModelsProgressPresentation(
                label: "Uninstalling",
                status: "Removing model from Ollama…",
                fraction: nil
            )
        }
        return nil
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
        snapshot: ASRModelLifecycleSnapshot?,
        polishPlaceholder: ModelsFamilyPlaceholder?,
        previousPolishRowIDs: [ModelsRowID]
    ) -> ModelsRowID? {
        if let requested, rows.contains(where: { $0.id == requested }) {
            return requested
        }
        if requested == .polishPlaceholder, polishPlaceholder != nil {
            return requested
        }
        if let requested,
           case .polish = requested,
           let previousIndex = previousPolishRowIDs.firstIndex(of: requested) {
            let currentIDs = Set(rows.filter { $0.family == .polish }.map(\.id))
            let following = previousPolishRowIDs.index(after: previousIndex)
            if following < previousPolishRowIDs.endIndex,
               let next = previousPolishRowIDs[following...].first(where: currentIDs.contains) {
                return next
            }
            if previousIndex > previousPolishRowIDs.startIndex,
               let previous = previousPolishRowIDs[..<previousIndex].reversed()
               .first(where: currentIDs.contains) {
                return previous
            }
            if polishPlaceholder != nil {
                return .polishPlaceholder
            }
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

    private static func polishPlaceholderInspector(
        id: ModelsRowID?,
        placeholder: ModelsFamilyPlaceholder?
    ) -> ModelsInspectorPresentation? {
        guard id == .polishPlaceholder,
              case .unavailable = placeholder else { return nil }
        return ModelsInspectorPresentation(
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
            destructiveAction: row.destructiveAction,
            progress: row.progress,
            managementDisabledReason: row.managementDisabledReason,
            inputDisabledReason: row.inputDisabledReason,
            errorMessage: row.errorMessage,
            showsInstallByNameForm: row.kind == .utility
        )
    }
}
