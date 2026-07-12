import SwiftUI

// MARK: - models (ASR + Ollama in one pane)

/// The merged Models pane (PRD #103): everything model-shaped in one place —
/// the speech (ASR) catalog on top, the Polish (Ollama) models below. Both
/// sections are the previous panes unchanged in behavior.
struct ModelsCombinedPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Speech recognition")
                SpeechPane(model: model)
            }
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader("Polish (Ollama)")
                ModelsPane(model: model)
            }
        }
    }
}
