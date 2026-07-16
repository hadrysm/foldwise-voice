import Foundation

struct ModeIconChoice: Identifiable, Equatable {
    let symbolName: String
    let label: String

    var id: String {
        symbolName
    }
}

enum ModeIconCatalog {
    static let choices: [ModeIconChoice] = [
        .init(symbolName: "wand.and.sparkles", label: "Magic wand"),
        .init(symbolName: "envelope", label: "Email"),
        .init(symbolName: "text.bubble", label: "Text bubble"),
        .init(symbolName: "bubble.left.and.bubble.right", label: "Conversation"),
        .init(symbolName: "quote.bubble", label: "Quotation"),
        .init(symbolName: "doc.text", label: "Document"),
        .init(symbolName: "newspaper", label: "Article"),
        .init(symbolName: "book.closed", label: "Notes"),
        .init(symbolName: "list.bullet", label: "List"),
        .init(symbolName: "checklist", label: "Checklist"),
        .init(symbolName: "tablecells", label: "Table"),
        .init(symbolName: "person.3", label: "Team"),
        .init(symbolName: "briefcase", label: "Work"),
        .init(symbolName: "calendar", label: "Schedule"),
        .init(symbolName: "clock", label: "Time"),
        .init(symbolName: "paperplane", label: "Send"),
        .init(symbolName: "megaphone", label: "Announcement"),
        .init(symbolName: "lightbulb", label: "Idea"),
        .init(symbolName: "graduationcap", label: "Study"),
        .init(symbolName: "terminal", label: "Terminal"),
        .init(symbolName: "chevron.left.forwardslash.chevron.right", label: "Code"),
        .init(symbolName: "hammer", label: "Build"),
        .init(symbolName: "wrench.and.screwdriver", label: "Tools"),
        .init(symbolName: "pencil.and.outline", label: "Writing"),
        .init(symbolName: "signature", label: "Signature"),
        .init(symbolName: "heart", label: "Personal"),
        .init(symbolName: "star", label: "Favorite"),
        .init(symbolName: "flag", label: "Goal"),
        .init(symbolName: "globe", label: "Language"),
        .init(symbolName: "chart.bar", label: "Report"),
    ]

    static func label(for symbolName: String) -> String {
        choices.first { $0.symbolName == symbolName }?.label
            ?? "Stored symbol: \(symbolName)"
    }
}

struct ModeTransformationChoice: Identifiable, Equatable {
    let transformation: ModeTransformation
    let title: String
    let detail: String

    var id: ModeTransformation {
        transformation
    }

    static let all = [
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
    ]
}

enum ModeEditorKeyboardAction: Equatable {
    case defaultAction
    case cancelAction
}

struct ModeEditorActionPresentation: Equatable {
    let title: String
    let accessibilityHint: String
    let keyboardAction: ModeEditorKeyboardAction
}

struct ModeEditorAccessibilityPresentation: Equatable {
    let nameValue: String
    let iconValue: String
    let transformationValue: String
    let validationLabels: [String]
    let persistenceErrorLabel: String?
    let saveAction: ModeEditorActionPresentation
    let cancelAction: ModeEditorActionPresentation

    init(state: ModeEditorState) {
        nameValue = state.draft.name
        iconValue = ModeIconCatalog.label(for: state.draft.icon)
        transformationValue = ModeTransformationChoice.all.first {
            $0.transformation == state.draft.transformation
        }?.title ?? ""
        validationLabels = [
            Self.validationLabel(field: "Name", message: state.issues.name),
            Self.validationLabel(field: "AI model", message: state.issues.model),
            Self.validationLabel(field: "System prompt", message: state.issues.systemPrompt),
        ].compactMap { $0 }
        persistenceErrorLabel = state.persistenceError.map { "Save error: \($0)" }
        saveAction = ModeEditorActionPresentation(
            title: state.saveActionTitle,
            accessibilityHint: "Validates and saves this Mode atomically",
            keyboardAction: .defaultAction
        )
        cancelAction = ModeEditorActionPresentation(
            title: "Cancel",
            accessibilityHint: "Discards the complete draft",
            keyboardAction: .cancelAction
        )
    }

    static func validationLabel(field: String, message: String?) -> String? {
        message.map { "\(field) validation error: \($0)" }
    }
}
