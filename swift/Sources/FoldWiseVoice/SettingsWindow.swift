// Settings window: SwiftUI grouped form — Ollama model, active mode,
// hotkey recorders, audio ducking toggle, permission status.

import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var ollamaModels: [String] = []
    @Published var modelNote = ""
    @Published var selectedModel = ""
    @Published var activeMode = ""
    @Published var pttKey = ""
    @Published var toggleKey = ""
    @Published var pauseAudio = true
    @Published var axTrusted = false
    @Published var status = ""
    @Published var statusIsError = false
    @Published var recordingField: RecordingField? = nil

    enum RecordingField { case ptt, toggle }

    var modeNames: [String] = []
    var onSave: (() -> Void)?
    var onEditFile: (() -> Void)?
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onRecord: (SettingsModel.RecordingField) -> Void
    var onSave: () -> Void

    private static let axPaneURL = URL(
        string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Speech recognition") {
                    LabeledContent("Engine", value: "Parakeet TDT v3 · Apple Neural Engine")
                    Text("Runs fully on-device (FluidAudio). The model downloads once on first launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Polish · Ollama") {
                    if model.ollamaModels.isEmpty {
                        LabeledContent("Model", value: model.selectedModel.isEmpty ? "—" : model.selectedModel)
                    } else {
                        Picker("Model", selection: $model.selectedModel) {
                            ForEach(pickerModels, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Text(model.modelNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Dictation") {
                    Picker("Active mode", selection: $model.activeMode) {
                        ForEach(model.modeNames, id: \.self) { Text($0).tag($0) }
                    }
                    hotkeyRow(
                        label: "Push-to-talk key", value: $model.pttKey, field: .ptt,
                        placeholder: "e.g. alt_r")
                    hotkeyRow(
                        label: "Toggle key", value: $model.toggleKey, field: .toggle,
                        placeholder: "empty = disabled")
                    Text("Key names: alt_r, cmd_r, ctrl_r, f19, … or a single character. Hold the push-to-talk key while speaking.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Pause music & mute other audio while dictating", isOn: $model.pauseAudio)
                }

                Section("Permissions") {
                    HStack {
                        Image(
                            systemName: model.axTrusted
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(model.axTrusted ? .green : .orange)
                        Text(
                            model.axTrusted
                                ? "Accessibility granted — auto-paste is on"
                                : "Accessibility missing — clipboard only")
                        Spacer()
                        Button("Open Accessibility…") {
                            NSWorkspace.shared.open(Self.axPaneURL)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Edit modes.json…") { model.onEditFile?() }
                Spacer()
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(model.statusIsError ? .red : .green)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 500, height: 560)
    }

    private var pickerModels: [String] {
        var models = model.ollamaModels
        if !model.selectedModel.isEmpty, !models.contains(model.selectedModel) {
            models.append(model.selectedModel)
        }
        return models
    }

    @ViewBuilder
    private func hotkeyRow(
        label: String, value: Binding<String>, field: SettingsModel.RecordingField,
        placeholder: String
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                TextField(placeholder, text: value)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button(model.recordingField == field ? "Press a key…" : "Record…") {
                    onRecord(field)
                }
            }
        }
    }
}

@MainActor
final class SettingsController {
    private let config: Config
    private let onSaved: () -> Void
    private let model = SettingsModel()
    private var window: NSWindow?
    private var keyMonitor: Any?

    init(config: Config, onSaved: @escaping () -> Void) {
        self.config = config
        self.onSaved = onSaved
    }

    func show() {
        if window == nil { build() }
        populate()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let view = SettingsView(
            model: model,
            onRecord: { [weak self] field in self?.startRecording(field) },
            onSave: { [weak self] in self?.save() })
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "FoldWise Voice Settings"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        model.onEditFile = { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(self.config.path)
        }
        window = win
    }

    private func populate() {
        model.modeNames = config.modeOrder
        model.activeMode = config.activeMode
        model.selectedModel = config.llmModel ?? ""
        model.pttKey = config.hotkey
        model.toggleKey = config.toggleHotkey ?? ""
        model.pauseAudio = config.pauseAudio
        model.axTrusted = TextInserter.accessibilityTrusted()
        model.status = ""
        model.ollamaModels = []
        model.modelNote = "Checking Ollama…"
        Task { @MainActor in
            let models = await OllamaClient.listModels()
            self.model.ollamaModels = models
            self.model.modelNote =
                models.isEmpty
                ? "Ollama isn't running — showing the configured model only."
                : "Installed Ollama models. Applies to all LLM modes."
        }
    }

    // MARK: - key recording

    private func startRecording(_ field: SettingsModel.RecordingField) {
        stopRecording()
        model.recordingField = field
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            guard let self else { return event }
            var name: String?
            if event.type == .flagsChanged {
                // Capture modifiers on press only (flag bit present).
                let keycode = CGKeyCode(event.keyCode)
                let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
                let isDown = KeyMap.modifierFlag[keycode].map { flags.contains($0) } ?? false
                guard isDown else { return nil }
                name = KeyMap.codeToName[keycode]
            } else {
                name = KeyMap.codeToName[CGKeyCode(event.keyCode)]
                    ?? event.charactersIgnoringModifiers?.lowercased()
            }
            if let name, !name.isEmpty {
                switch field {
                case .ptt: self.model.pttKey = name
                case .toggle: self.model.toggleKey = name
                }
            }
            self.stopRecording()
            return nil  // swallow the keystroke
        }
    }

    private func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        model.recordingField = nil
    }

    // MARK: - save

    private func save() {
        stopRecording()
        let ptt = model.pttKey.trimmingCharacters(in: .whitespaces)
        let toggle = model.toggleKey.trimmingCharacters(in: .whitespaces)
        do {
            _ = try KeyMap.parse(ptt)
            if !toggle.isEmpty { _ = try KeyMap.parse(toggle) }
        } catch {
            model.status = "⚠️ \(error.localizedDescription)"
            model.statusIsError = true
            return
        }

        if !model.selectedModel.isEmpty {
            config.setLLMModel(model.selectedModel)
        }
        config.setActiveMode(model.activeMode)
        config.hotkey = ptt
        config.toggleHotkey = toggle.isEmpty ? nil : toggle
        config.pauseAudio = model.pauseAudio
        do {
            try config.save()
        } catch {
            model.status = "⚠️ save failed: \(error.localizedDescription)"
            model.statusIsError = true
            return
        }
        model.status = "Saved ✓"
        model.statusIsError = false
        onSaved()
    }
}
