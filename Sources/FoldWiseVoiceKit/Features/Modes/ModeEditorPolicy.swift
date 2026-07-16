import Foundation

struct ModeEditorDraft: Equatable {
    var name: String
    var icon: String
    var model: String
    var transformation: ModeTransformation
    var systemPrompt: String
    var vocabularyText: String
}

enum ModeEditorPurpose: Equatable {
    case add
    case duplicate(ModeID)
    case edit(ModeID)
}

enum ModeMoveDirection: Equatable {
    case up
    case down
}

struct ModeDeletionState: Equatable {
    let id: ModeID
    let title: String
    let message: String
}

struct ModeLibraryCandidate: Equatable {
    let modes: [Mode]
    let selection: DictationSelection
}

enum ModeLibraryPolicy {
    static func insertingDuplicate(
        _ duplicate: Mode,
        after sourceID: ModeID,
        in modes: [Mode]
    ) -> ModeLibraryCandidate? {
        guard let duplicateID = duplicate.id,
              let sourceIndex = modes.firstIndex(where: { $0.id == sourceID })
        else { return nil }
        var candidate = modes
        candidate.insert(duplicate, at: sourceIndex + 1)
        return ModeLibraryCandidate(modes: candidate, selection: .mode(duplicateID))
    }

    static func moving(
        _ id: ModeID,
        direction: ModeMoveDirection,
        in modes: [Mode],
        selection: DictationSelection
    ) -> ModeLibraryCandidate? {
        guard let sourceIndex = modes.firstIndex(where: { $0.id == id }) else { return nil }
        let destinationIndex = switch direction {
        case .up: sourceIndex - 1
        case .down: sourceIndex + 1
        }
        guard modes.indices.contains(destinationIndex) else { return nil }
        var candidate = modes
        candidate.swapAt(sourceIndex, destinationIndex)
        return ModeLibraryCandidate(modes: candidate, selection: selection)
    }

    static func deleting(
        _ id: ModeID,
        from modes: [Mode],
        selection: DictationSelection
    ) -> ModeLibraryCandidate? {
        guard modes.contains(where: { $0.id == id }) else { return nil }
        let nextSelection: DictationSelection = selection == .mode(id)
            ? .voiceToText
            : selection
        return ModeLibraryCandidate(
            modes: modes.filter { $0.id != id },
            selection: nextSelection
        )
    }
}

struct ModeEditorState: Equatable {
    let purpose: ModeEditorPurpose
    var draft: ModeEditorDraft
    var issues: ModeEditorIssues
    var persistenceError: String?

    init(
        purpose: ModeEditorPurpose,
        draft: ModeEditorDraft,
        issues: ModeEditorIssues = .none,
        persistenceError: String? = nil
    ) {
        self.purpose = purpose
        self.draft = draft
        self.issues = issues
        self.persistenceError = persistenceError
    }

    var saveActionTitle: String {
        persistenceError == nil ? "Save" : "Retry"
    }

    mutating func updateDraft<Value>(
        _ keyPath: WritableKeyPath<ModeEditorDraft, Value>,
        to value: Value
    ) {
        draft[keyPath: keyPath] = value
        issues = .none
        persistenceError = nil
    }
}

struct ModeEditorSubmission: Equatable {
    let name: String
    let icon: String
    let model: String
    let transformation: ModeTransformation
    let systemPrompt: String
    let vocabulary: [String]
}

struct ModeEditorIssues: Equatable {
    var name: String?
    var model: String?
    var systemPrompt: String?

    static let none = ModeEditorIssues()

    var isEmpty: Bool {
        name == nil && model == nil && systemPrompt == nil
    }
}

struct ModeEditorEvaluation: Equatable {
    let submission: ModeEditorSubmission?
    let issues: ModeEditorIssues
}

enum ModeEditorPolicy {
    static func duplicateName(for sourceName: String, existingNames: [String]) -> String {
        let source = ModeTextPolicy.cleanName(sourceName)
        var words = source.split(separator: " ").map(String.init)
        if words.count >= 2, words.last?.lowercased() == "copy" {
            words.removeLast()
        } else if words.count >= 3,
                  Int(words[words.count - 1]) != nil,
                  words[words.count - 2].lowercased() == "copy" {
            words.removeLast(2)
        }
        let base = words.joined(separator: " ")
        let existing = Set(existingNames.map(ModeTextPolicy.comparisonKey))
        var suffix = 1
        while true {
            let candidate = suffix == 1 ? "\(base) Copy" : "\(base) Copy \(suffix)"
            if !existing.contains(ModeTextPolicy.comparisonKey(candidate)) {
                return candidate
            }
            suffix += 1
        }
    }

    static func unavailableModelWarning(
        for value: String,
        installedModels: Set<String>?
    ) -> String? {
        let model = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              let installedModels,
              !installedModels.contains(model)
        else { return nil }
        return "\(model) isn't installed. Polish will use the raw transcript until you "
            + "install it in Models."
    }

    static func evaluate(
        _ draft: ModeEditorDraft,
        existingModes: [Mode],
        editingID: ModeID?,
        installedModels: Set<String>?
    ) -> ModeEditorEvaluation {
        let name = ModeTextPolicy.cleanName(draft.name)
        let model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = draft.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        var issues = ModeEditorIssues.none

        if name.isEmpty {
            issues.name = "Enter a Mode name."
        } else if existingModes.contains(where: {
            $0.id != editingID
                && ModeTextPolicy.comparisonKey($0.name) == ModeTextPolicy.comparisonKey(name)
        }) {
            issues.name = "A Mode named '\(name)' already exists."
        }
        if installedModels == nil {
            issues.model = "Installed AI models are still loading. Try again in a moment."
        } else if model.isEmpty {
            issues.model = "Choose an installed AI model."
        } else if let installedModels, !installedModels.contains(model) {
            issues.model = "\(model) isn't installed. Install it in Models before saving."
        }
        if prompt.isEmpty {
            issues.systemPrompt = "Enter Polish instructions."
        }

        guard issues.isEmpty else {
            return ModeEditorEvaluation(submission: nil, issues: issues)
        }
        return ModeEditorEvaluation(
            submission: ModeEditorSubmission(
                name: name,
                icon: draft.icon.trimmingCharacters(in: .whitespacesAndNewlines),
                model: model,
                transformation: draft.transformation,
                systemPrompt: prompt,
                vocabulary: ModeTextPolicy.cleanVocabulary(
                    draft.vocabularyText.components(separatedBy: .newlines)
                )
            ),
            issues: issues
        )
    }
}
