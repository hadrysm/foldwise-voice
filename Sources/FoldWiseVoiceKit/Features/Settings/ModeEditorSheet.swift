import AppKit
import SwiftUI

struct ModeEditorSheet: View {
    @ObservedObject var model: SettingsModel
    @State private var iconPickerPresented = false
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        if let editor = model.modeEditor {
            VStack(spacing: 0) {
                header(editor)
                EmberHairline(axis: .horizontal)
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 28) {
                        identityColumn(editor)
                        EmberHairline(axis: .vertical)
                        instructionsColumn(editor)
                    }
                    .padding(24)
                }
                EmberHairline(axis: .horizontal)
                footer(editor)
            }
            .frame(width: 820, height: 570)
            .background(Theme.canvas)
            .interactiveDismissDisabled()
        }
    }

    private func header(_ editor: ModeEditorState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: displayIcon(editor.draft.icon))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(editorTitle(editor.purpose))
                    .font(Theme.ui(20, .semibold))
                Text("Changes affect future Dictation sessions after Save.")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { model.onCancelModeEditor?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EmberPlainButtonStyle())
            .accessibilityLabel("Close Mode editor")
            .accessibilityHint("Discards changes")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(Theme.raised)
    }

    private func identityColumn(_ editor: ModeEditorState) -> some View {
        let accessibility = ModeEditorAccessibilityPresentation(state: editor)
        return VStack(alignment: .leading, spacing: 18) {
            columnHeading("Identity", detail: "How this Mode appears across FoldWise")
            editorField("Name") {
                TextField("Mode name", text: draftBinding(\.name, fallback: ""))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Mode name")
                    .accessibilityValue(accessibility.nameValue)
            }
            validationMessage(editor.issues.name, field: "Name")

            editorField("Icon") {
                Button {
                    iconPickerPresented.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: displayIcon(editor.draft.icon))
                            .frame(width: 18)
                            .accessibilityHidden(true)
                        Text(iconLabel(editor.draft.icon))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .emberControlSurface()
                }
                .buttonStyle(EmberPlainButtonStyle())
                .accessibilityLabel("Mode icon")
                .accessibilityValue(accessibility.iconValue)
                .accessibilityHint("Opens a palette of labeled symbols")
                .popover(isPresented: $iconPickerPresented, arrowEdge: .bottom) {
                    iconPalette(editor.draft.icon)
                }
            }

            editorField("AI model") {
                Picker("AI model", selection: draftBinding(\.model, fallback: "")) {
                    if model.installed == nil {
                        Text(
                            editor.draft.model.isEmpty
                                ? "Checking installed models…"
                                : editor.draft.model
                        )
                        .tag(editor.draft.model)
                    } else if editor.draft.model.isEmpty, installedModelNames.isEmpty {
                        Text("No installed models").tag("")
                    } else if !editor.draft.model.isEmpty,
                              !installedModelNames.contains(editor.draft.model) {
                        Text("\(editor.draft.model) — unavailable")
                            .tag(editor.draft.model)
                    }
                    ForEach(installedModelNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .accessibilityLabel("Installed AI model")
            }
            validationMessage(editor.issues.model, field: "AI model")
            if let warning = unavailableModelWarning(editor) {
                warningNotice(warning)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func instructionsColumn(_ editor: ModeEditorState) -> some View {
        let accessibility = ModeEditorAccessibilityPresentation(state: editor)
        return VStack(alignment: .leading, spacing: 18) {
            columnHeading("Polish instructions", detail: "How the transcript should change")
            editorField("Transformation") {
                Picker(
                    "Transformation",
                    selection: draftBinding(\.transformation, fallback: .inPlace)
                ) {
                    ForEach(ModeTransformationChoice.all) { choice in
                        Text(choice.title).tag(choice.transformation)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Polish transformation")
                .accessibilityValue(accessibility.transformationValue)
            }
            if let choice = ModeTransformationChoice.all.first(where: {
                $0.transformation == editor.draft.transformation
            }) {
                Text(choice.detail)
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("\(choice.title). \(choice.detail)")
            }

            editorField("System prompt") {
                TextEditor(text: draftBinding(\.systemPrompt, fallback: ""))
                    .font(Theme.ui(12))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 150)
                    .emberControlSurface()
                    .accessibilityLabel("System prompt")
                    .accessibilityHint("Required instructions for Polish")
            }
            validationMessage(editor.issues.systemPrompt, field: "System prompt")

            editorField("Preserved vocabulary · optional") {
                TextEditor(text: draftBinding(\.vocabularyText, fallback: ""))
                    .font(Theme.mono(11))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 86)
                    .emberControlSurface()
                    .accessibilityLabel("Preserved vocabulary")
                    .accessibilityHint("Enter one term per line; order is preserved")
            }
            Text("One term per line. Empty and repeated terms are removed on Save.")
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func footer(_ editor: ModeEditorState) -> some View {
        let accessibility = ModeEditorAccessibilityPresentation(state: editor)
        return HStack(alignment: .center, spacing: 12) {
            if let error = editor.persistenceError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.ui(11))
                    .foregroundStyle(Theme.error)
                    .accessibilityLabel(accessibility.persistenceErrorLabel ?? error)
            }
            Spacer()
            Button(accessibility.cancelAction.title) { model.onCancelModeEditor?() }
                .buttonStyle(EmberButtonStyle(kind: .quiet))
                .modeEditorKeyboardAction(accessibility.cancelAction.keyboardAction)
                .accessibilityHint(accessibility.cancelAction.accessibilityHint)
            Button(accessibility.saveAction.title) { model.onSaveModeEditor?() }
                .buttonStyle(EmberButtonStyle(kind: .primary))
                .modeEditorKeyboardAction(accessibility.saveAction.keyboardAction)
                .accessibilityHint(accessibility.saveAction.accessibilityHint)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.raised)
    }

    private func columnHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.ui(15, .semibold))
            Text(detail)
                .font(Theme.ui(11))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func editorField(
        _ label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.ui(11, .semibold))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    @ViewBuilder
    private func validationMessage(_ message: String?, field: String) -> some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.error)
                .accessibilityLabel(
                    ModeEditorAccessibilityPresentation.validationLabel(
                        field: field,
                        message: message
                    ) ?? message
                )
        }
    }

    private func warningNotice(_ warning: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.ui(10.5))
                .foregroundStyle(Theme.warning)
            Button("Open Models") { model.pane = .models }
                .buttonStyle(.link)
                .accessibilityHint("Shows Models after this sheet closes")
        }
        .accessibilityElement(children: .contain)
    }

    private func iconPalette(_ selected: String) -> some View {
        ScrollView {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(ModeIconCatalog.choices) { choice in
                    let isSelected = selected == choice.symbolName
                    Button {
                        setDraft(\.icon, to: choice.symbolName)
                        iconPickerPresented = false
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: choice.symbolName)
                                .font(.system(size: 18, weight: .medium))
                                .accessibilityHidden(true)
                            Text(choice.label)
                                .font(Theme.ui(10.5))
                                .lineLimit(1)
                        }
                        .foregroundStyle(
                            isSelected ? Theme.accent : Theme.textPrimary
                        )
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(
                            isSelected ? Theme.raised : Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.surfaceRadius)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.surfaceRadius)
                                .strokeBorder(
                                    isSelected
                                        ? Theme.accent
                                        : Theme.essentialBorderColor(
                                            increaseContrast: usesStrongBoundary
                                        ),
                                    lineWidth: Theme.essentialBorderWidth(
                                        increaseContrast: usesStrongBoundary
                                    )
                                )
                        )
                        .overlay(alignment: .topTrailing) {
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(5)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(EmberPlainButtonStyle(
                        cornerRadius: Theme.surfaceRadius
                    ))
                    .accessibilityLabel(choice.label)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(12)
        }
        .frame(width: 360, height: 280)
        .accessibilityLabel("Mode icon palette")
    }

    private var installedModelNames: [String] {
        model.installed?.map(\.name).sorted() ?? []
    }

    private var usesStrongBoundary: Bool {
        colorSchemeContrast == .increased
    }

    private func unavailableModelWarning(_ editor: ModeEditorState) -> String? {
        ModeEditorPolicy.unavailableModelWarning(
            for: editor.draft.model,
            installedModels: model.installed.map { Set($0.map(\.name)) }
        )
    }

    private func editorTitle(_ purpose: ModeEditorPurpose) -> String {
        switch purpose {
        case .add: "Add Mode"
        case .duplicate: "Duplicate Mode"
        case .edit: "Edit Mode"
        }
    }

    private func iconLabel(_ symbolName: String) -> String {
        ModeIconCatalog.label(for: symbolName)
    }

    private func displayIcon(_ symbolName: String) -> String {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) == nil
            ? "text.bubble"
            : symbolName
    }

    private func draftBinding<Value>(
        _ keyPath: WritableKeyPath<ModeEditorDraft, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { model.modeEditor?.draft[keyPath: keyPath] ?? fallback },
            set: { setDraft(keyPath, to: $0) }
        )
    }

    private func setDraft<Value>(
        _ keyPath: WritableKeyPath<ModeEditorDraft, Value>,
        to value: Value
    ) {
        guard var editor = model.modeEditor else { return }
        editor.updateDraft(keyPath, to: value)
        model.modeEditor = editor
    }
}

private extension View {
    @ViewBuilder
    func modeEditorKeyboardAction(_ action: ModeEditorKeyboardAction) -> some View {
        switch action {
        case .defaultAction:
            keyboardShortcut(.defaultAction)
        case .cancelAction:
            keyboardShortcut(.cancelAction)
        }
    }
}
