# Large module review

Issue #134 reviewed the largest feature areas after feature colocation. The
review used responsibility boundaries and existing behavioral seams, not line
count, as the reason to split.

- **Settings composition:** split `SettingsView.swift` at its existing view
  boundaries. The window/sidebar shell remains in `SettingsView.swift`, while
  the combined Models composition, ASR catalog, and Ollama catalog now live in
  `ModelsCombinedPane.swift`, `SpeechPane.swift`, and `ModelsPane.swift`. Each
  pane owns distinct view state and callbacks; their interfaces and behavior
  are unchanged.
- **Settings workflow:** retained intact. It is the settings transaction
  coordinator: preference persistence, status reporting, history refresh, and
  model-operation cancellation all mutate one `SettingsModel`. Splitting it
  would expose shared operation identifiers or add forwarding coordinators
  without hiding new complexity.
- **Configuration:** retained intact. `Config` is deliberately a deep module
  whose small interface hides strict schema parsing, ordered serialization,
  defaults, validation, persistence, and change propagation. Separating those
  rules would weaken the single owner of the `config.json` contract described by
  ADR-0003, ADR-0006, and ADR-0007.
- **Ollama client:** split pure Polish response policy into
  `OllamaPolishPolicy.swift`, as an extension of `OllamaClient`. Request sizing
  and shape, sanitization, and off-task decisions are independent of transport
  and model lifecycle operations. Keeping the existing type and static methods
  preserves all callers and avoids a forwarding abstraction.
- **History:** split reprocessing orchestration and list filtering into
  `HistoryReprocessor.swift` and `HistoryFilter.swift`. The remaining
  `History.swift` owns the persisted entry vocabulary and the `HistoryStore`
  persistence seam. The extracted responsibilities already have independent
  behavior tests and require no new interface.

No domain types, persisted formats, Stage ordering, model contracts, or UI
callbacks changed. The existing Config, Settings workflow, Ollama policy, and
History behavior tests remain the verification seams; no tests assert file
placement.
