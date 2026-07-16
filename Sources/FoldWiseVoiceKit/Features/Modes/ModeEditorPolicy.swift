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
    case edit(ModeID)
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
        installedModels: Set<String>
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
        if model.isEmpty {
            issues.model = "Choose an installed AI model."
        } else if !installedModels.contains(model) {
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
