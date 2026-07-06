// Load and save modes.json — same file and format as the Python app, so the
// two implementations stay interchangeable. `asr_model` is preserved on save
// but ignored here: this app always transcribes with Parakeet v3 (FluidAudio).

import Foundation
import os

let MIN_CHARS_FOR_LLM = 40
let OLLAMA_CHAT_URL = "http://localhost:11434/v1/chat/completions"
let OLLAMA_TAGS_URL = "http://localhost:11434/api/tags"
let OLLAMA_PULL_URL = "http://localhost:11434/api/pull"
let OLLAMA_DELETE_URL = "http://localhost:11434/api/delete"

struct Mode {
    var name: String
    var asrModel: String
    var llmModel: String?
    var systemPrompt: String?
    var vocab: [String]
    /// In-place vs Expanding calibration (ADR-0004): an In-place Mode's polish
    /// tracks the transcript closely (`false`); an Expanding Mode legitimately
    /// restructures and grows it (`true`). Sizes the Polish token cap and, in
    /// #72, calibrates the off-task check. Internal and NOT persisted — there is
    /// no config-schema change — so it is re-derived from the Mode name on load.
    /// Defaults to `true` (loose): an unknown/user-defined Mode skews
    /// generative, and a false fallback (discarding a good polish) is worse than
    /// letting a mildly off-task reply through — the output is inert either way.
    var expands: Bool = true

    var usesLLM: Bool {
        !(llmModel ?? "").isEmpty
    }

    /// Built-in In-place Mode names. Every other Mode — a built-in Expanding
    /// Mode (Email, Bullets) or any user-defined Mode — is Expanding. This is
    /// the single source of truth for `expands`, applied both when building the
    /// defaults and when loading, since the flag is never written to disk.
    static func expands(forName name: String) -> Bool {
        !["Clean", "Voice to Text"].contains(name)
    }
}

final class Config {
    var activeMode: String {
        didSet { if oldValue != activeMode { pendingChanges.insert(.activeMode) } }
    }

    var hotkey: String {
        didSet { if oldValue != hotkey { pendingChanges.insert(.hotkeys) } }
    }

    var toggleHotkey: String? {
        didSet { if oldValue != toggleHotkey { pendingChanges.insert(.hotkeys) } }
    }

    var pauseAudio: Bool
    /// Master "Save dictation history" switch (PRD #78). When false the
    /// Pipeline records nothing and no `history.jsonl` is written. Persisted in
    /// modes.json; like `pauseAudio` nobody re-reads it through change
    /// propagation, so it has no `ChangeSet` member — the Pipeline reads it
    /// fresh when the dictation session stops (frozen at stop time alongside
    /// `mode`), not at session start.
    var saveHistory: Bool
    /// How long history is kept before the launch sweep prunes it (PRD #78).
    /// Persisted in modes.json as a day count; like `saveHistory` nobody
    /// re-reads it through change propagation, so it has no `ChangeSet` member —
    /// the launch sweep reads it once at startup.
    var historyRetention: RetentionWindow
    var hudPosition: [Double]?
    /// HUDStyle raw value; unknown values fall back to .classic at use sites.
    var hudStyle: String {
        didSet { if oldValue != hudStyle { pendingChanges.insert(.hudStyle) } }
    }

    private(set) var modeOrder: [String]
    var modes: [String: Mode]
    let path: URL

    init(
        activeMode: String, hotkey: String, toggleHotkey: String?, pauseAudio: Bool,
        saveHistory: Bool = true, historyRetention: RetentionWindow = .default,
        hudPosition: [Double]?, hudStyle: String = "classic",
        modeOrder: [String], modes: [String: Mode], path: URL
    ) {
        self.activeMode = activeMode
        self.hotkey = hotkey
        self.toggleHotkey = toggleHotkey
        self.pauseAudio = pauseAudio
        self.saveHistory = saveHistory
        self.historyRetention = historyRetention
        self.hudPosition = hudPosition
        self.hudStyle = hudStyle
        self.modeOrder = modeOrder
        self.modes = modes
        self.path = path
    }

    var mode: Mode {
        // load() guarantees at least one mode, but modes.json is hand-editable
        // and `modes` is mutable — degrade to raw dictation rather than crash
        // if the invariant is ever broken.
        if let m = modes[activeMode] { return m }
        // Local copy: Logger messages are autoclosures, where the formatter's
        // redundantSelf rule and the compiler's explicit-self rule collide.
        let requested = activeMode
        if let first = modeOrder.first, let m = modes[first] {
            Log.config.error("""
            Active mode '\(requested, privacy: .public)' not in modes.json — \
            using '\(first, privacy: .public)'
            """)
            return m
        }
        Log.config.error("modes.json has no usable modes — using built-in raw dictation")
        return Mode(name: "Voice to Text", asrModel: "", llmModel: nil, systemPrompt: nil, vocab: [])
    }

    /// The Ollama model used by LLM modes (they share one by convention).
    var llmModel: String? {
        for name in modeOrder {
            if let m = modes[name], m.usesLLM { return m.llmModel }
        }
        return nil
    }

    /// Point every LLM-enabled mode at `model`.
    func setLLMModel(_ model: String) {
        for name in modeOrder where modes[name]?.usesLLM == true {
            modes[name]?.llmModel = model
        }
    }

    func setActiveMode(_ name: String) {
        guard modes[name] != nil else { return }
        activeMode = name
    }

    // MARK: - change propagation

    /// One member per thing subscribers *act on*, not per property: both
    /// hotkeys share `.hotkeys` because the listener can only rebind both at
    /// once, and properties nobody re-reads (`hudPosition`, `pauseAudio`)
    /// have no member at all — persisting them notifies no one.
    struct ChangeSet: OptionSet {
        let rawValue: Int

        static let activeMode = ChangeSet(rawValue: 1 << 0)
        static let hotkeys = ChangeSet(rawValue: 1 << 1)
        static let hudStyle = ChangeSet(rawValue: 1 << 2)
    }

    /// Changed keys accumulated by the tracked properties' `didSet`s,
    /// delivered and cleared by `saveAndNotify()`.
    private var pendingChanges: ChangeSet = []
    /// Observers are app-lifetime singletons, so this list is append-only.
    private var observers: [(ChangeSet) -> Void] = []

    @MainActor
    func onChange(_ observer: @escaping (ChangeSet) -> Void) {
        observers.append(observer)
    }

    /// The mutate → persist → notify transaction. A failed save throws
    /// before the pending set is touched, so nobody is told about a change
    /// that never reached disk — and a later retry still carries it.
    @MainActor
    func saveAndNotify() throws {
        try save()
        let changes = pendingChanges
        pendingChanges = []
        guard !changes.isEmpty else { return }
        for observer in observers {
            observer(changes)
        }
    }

    // MARK: - persistence

    func save() throws {
        var top: [(String, Any?)] = [
            ("active_mode", activeMode),
            ("hotkey", hotkey),
            ("toggle_hotkey", toggleHotkey),
            ("pause_audio", pauseAudio),
            ("save_history", saveHistory),
            ("retention_days", historyRetention.days),
            ("hud_position", hudPosition),
            ("hud_style", hudStyle),
        ]
        var modesJSON = "{\n"
        for (i, name) in modeOrder.enumerated() {
            guard let m = modes[name] else { continue }
            let fields: [(String, Any?)] = [
                ("asr_model", m.asrModel),
                ("llm_model", m.llmModel),
                ("system_prompt", m.systemPrompt),
                ("vocab", m.vocab),
            ]
            modesJSON += "    \(Self.jsonString(name)): {\n"
            modesJSON += fields.map { "      \(Self.jsonString($0.0)): \(Self.jsonValue($0.1))" }
                .joined(separator: ",\n")
            modesJSON += "\n    }" + (i < modeOrder.count - 1 ? ",\n" : "\n")
        }
        modesJSON += "  }"
        top.append(("modes", RawJSON(text: modesJSON)))

        var out = "{\n"
        out += top.map { "  \(Self.jsonString($0.0)): \(Self.jsonValue($0.1))" }
            .joined(separator: ",\n")
        out += "\n}\n"
        try Data(out.utf8).write(to: path, options: .atomic)
    }

    private struct RawJSON { let text: String }

    private static func jsonString(_ s: String) -> String {
        // Serializing a single-element string array can't realistically fail,
        // but a save must never crash dictation — degrade to "" instead.
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              var text = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        text.removeFirst() // [
        text.removeLast() // ]
        return text
    }

    private static func jsonValue(_ v: Any?) -> String {
        switch v {
        case nil: "null"
        case let raw as RawJSON: raw.text
        case let s as String: jsonString(s)
        case let b as Bool: b ? "true" : "false"
        case let i as Int: String(i)
        case let arr as [String]:
            "[" + arr.map { jsonString($0) }.joined(separator: ", ") + "]"
        case let arr as [Double]:
            "[" + arr.map { String(format: "%.1f", $0) }.joined(separator: ", ") + "]"
        default: "null"
        }
    }

    // MARK: - loading

    static func load(from url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modesRaw = raw["modes"] as? [String: Any], !modesRaw.isEmpty
        else {
            throw NSError(
                domain: "FoldWiseVoice", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "\(url.path): 'modes' must contain at least one mode"]
            )
        }

        var modes: [String: Mode] = [:]
        for (name, any) in modesRaw {
            let m = any as? [String: Any] ?? [:]
            modes[name] = Mode(
                name: name,
                asrModel: (m["asr_model"] as? String) ?? "mlx-community/whisper-large-v3-turbo",
                llmModel: m["llm_model"] as? String,
                systemPrompt: m["system_prompt"] as? String,
                vocab: (m["vocab"] as? [String]) ?? [],
                expands: Mode.expands(forName: name)
            )
        }

        let order = modeOrder(in: String(data: data, encoding: .utf8) ?? "", names: Array(modes.keys))

        var active = raw["active_mode"] as? String ?? ""
        if modes[active] == nil { active = order[0] }

        var hudPosition: [Double]?
        if let pos = raw["hud_position"] as? [Any], pos.count == 2,
           let x = pos[0] as? Double ?? (pos[0] as? Int).map(Double.init),
           let y = pos[1] as? Double ?? (pos[1] as? Int).map(Double.init) {
            hudPosition = [x, y]
        }

        return Config(
            activeMode: active,
            hotkey: (raw["hotkey"] as? String) ?? "alt_r",
            toggleHotkey: raw["toggle_hotkey"] as? String,
            pauseAudio: (raw["pause_audio"] as? Bool) ?? true,
            saveHistory: (raw["save_history"] as? Bool) ?? true,
            historyRetention: RetentionWindow(
                days: (raw["retention_days"] as? Int) ?? RetentionWindow.default.days
            ),
            hudPosition: hudPosition,
            hudStyle: (raw["hud_style"] as? String) ?? "classic",
            modeOrder: order,
            modes: modes,
            path: url
        )
    }

    /// JSONSerialization loses key order; recover the modes' on-disk order by
    /// locating each `"<name>":` after the "modes" key in the raw text.
    private static func modeOrder(in text: String, names: [String]) -> [String] {
        guard let modesKey = text.range(of: "\"modes\"") else { return names.sorted() }
        let tail = text[modesKey.upperBound...]
        var positions: [(String, String.Index)] = []
        for name in names {
            let quoted = jsonString(name)
            if let r = tail.range(of: quoted) {
                positions.append((name, r.lowerBound))
            } else {
                positions.append((name, tail.endIndex))
            }
        }
        return positions.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Resolution order: --config arg, $FOLDWISE_CONFIG, ./modes.json,
    /// ../modes.json (running from swift/), Application Support.
    static func resolvePath(cliPath: String?) -> URL {
        let fm = FileManager.default
        if let p = cliPath { return URL(fileURLWithPath: p) }
        if let p = ProcessInfo.processInfo.environment["FOLDWISE_CONFIG"], !p.isEmpty {
            return URL(fileURLWithPath: p)
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath)
        for candidate in [cwd.appendingPathComponent("modes.json"),
                          cwd.deletingLastPathComponent().appendingPathComponent("modes.json")]
            where fm.fileExists(atPath: candidate.path) {
            return candidate
        }
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldWise Voice", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("modes.json")
    }

    static func loadOrCreate(at url: URL) -> Config {
        if let config = try? load(from: url) { return config }
        let defaults = defaultConfig(path: url)
        try? defaults.save()
        return defaults
    }

    static func defaultConfig(path: URL) -> Config {
        let asr = "mlx-community/whisper-large-v3-turbo"
        let clean = Mode(
            name: "Clean", asrModel: asr, llmModel: "qwen2.5:3b",
            systemPrompt: "You clean up dictated speech. Fix punctuation, capitalization, "
                + "and obvious transcription errors. Remove filler words (um, uh, "
                + "like, you know). Do NOT change meaning, add content, or answer "
                + "questions. Output ONLY the cleaned text.",
            vocab: ["FoldWise", "Ollama", "Anthropic"],
            expands: Mode.expands(forName: "Clean")
        )
        let raw = Mode(
            name: "Voice to Text", asrModel: asr, llmModel: nil, systemPrompt: nil,
            vocab: [], expands: Mode.expands(forName: "Voice to Text")
        )
        let email = Mode(
            name: "Email", asrModel: asr, llmModel: "qwen2.5:3b",
            systemPrompt: "Rewrite this dictation as a clear, concise, professional email "
                + "body. Output only the email text.",
            vocab: [], expands: Mode.expands(forName: "Email")
        )
        let bullets = Mode(
            name: "Bullets", asrModel: asr, llmModel: "qwen2.5:3b",
            systemPrompt: "Convert this dictation into a tight bulleted list, one idea per "
                + "bullet. Output only the list.",
            vocab: [], expands: Mode.expands(forName: "Bullets")
        )
        return Config(
            activeMode: "Clean", hotkey: "alt_r", toggleHotkey: nil, pauseAudio: true,
            hudPosition: nil,
            modeOrder: ["Voice to Text", "Clean", "Email", "Bullets"],
            modes: ["Voice to Text": raw, "Clean": clean, "Email": email, "Bullets": bullets],
            path: path
        )
    }
}
