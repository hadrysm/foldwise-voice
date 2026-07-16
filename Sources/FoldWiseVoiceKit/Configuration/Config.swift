import Foundation

let MIN_CHARS_FOR_LLM = 40
let OLLAMA_CHAT_URL = "http://localhost:11434/v1/chat/completions"
let OLLAMA_TAGS_URL = "http://localhost:11434/api/tags"
let OLLAMA_PULL_URL = "http://localhost:11434/api/pull"
let OLLAMA_DELETE_URL = "http://localhost:11434/api/delete"

enum AppearancePreference: String, CaseIterable, Codable {
    case system
    case light
    case dark
}

struct ModeID: RawRepresentable, Hashable, Codable, CustomStringConvertible {
    let rawValue: String

    init?(rawValue: String) {
        guard let uuid = UUID(uuidString: rawValue),
              uuid.uuidString.lowercased() == rawValue
        else { return nil }
        self.rawValue = rawValue
    }

    static func random() -> ModeID {
        ModeID(uncheckedRawValue: UUID().uuidString.lowercased())
    }

    var description: String {
        rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let id = ModeID(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Mode ID must be a canonical lowercase hyphenated UUID."
            )
        }
        self = id
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private init(uncheckedRawValue: String) {
        rawValue = uncheckedRawValue
    }
}

enum DictationSelection: Hashable {
    case voiceToText
    case mode(ModeID)
}

enum ModeTransformation: String, Codable {
    case inPlace = "in_place"
    case expanding
}

struct Mode: Equatable {
    let id: ModeID?
    var name: String
    var icon: String
    /// Transitional runtime projection. Schema 1 persists ASR selection once,
    /// at the top level; keeping it on the Pipeline value avoids coupling the
    /// Dictation slice to the configuration serializer.
    var asrModel: String
    var llmModel: String?
    var systemPrompt: String?
    var vocab: [String]
    var transformation: ModeTransformation

    init(
        id: ModeID? = nil,
        name: String,
        icon: String = "text.bubble",
        asrModel: String,
        llmModel: String?,
        systemPrompt: String?,
        vocab: [String],
        expands: Bool = true
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.asrModel = asrModel
        self.llmModel = llmModel
        self.systemPrompt = systemPrompt
        self.vocab = vocab
        transformation = expands ? .expanding : .inPlace
    }

    init(
        id: ModeID,
        name: String,
        icon: String,
        asrModel: String,
        llmModel: String,
        transformation: ModeTransformation,
        systemPrompt: String,
        vocabulary: [String]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.asrModel = asrModel
        self.llmModel = llmModel
        self.transformation = transformation
        self.systemPrompt = systemPrompt
        vocab = vocabulary
    }

    var expands: Bool {
        transformation == .expanding
    }

    var usesLLM: Bool {
        !(llmModel ?? "").isEmpty
    }

    func willPolish(_ transcript: String) -> Bool {
        usesLLM && transcript.count > MIN_CHARS_FOR_LLM
    }

    static func voiceToText(asrModel: String) -> Mode {
        Mode(
            name: "Voice to Text", icon: "waveform", asrModel: asrModel,
            llmModel: nil, systemPrompt: nil, vocab: [], expands: false
        )
    }
}

enum ConfigError: LocalizedError {
    case invalid(String)
    case readOnlyRecovery

    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        case .readOnlyRecovery:
            "Configuration is read-only until it is reset or FoldWise Voice quits."
        }
    }
}

final class Config {
    struct ChangeSet: OptionSet, Equatable {
        let rawValue: Int

        static let selection = ChangeSet(rawValue: 1 << 0)
        static let hotkeys = ChangeSet(rawValue: 1 << 1)
        static let asrModel = ChangeSet(rawValue: 1 << 2)
        static let inputDevice = ChangeSet(rawValue: 1 << 3)
        static let appearance = ChangeSet(rawValue: 1 << 4)
        static let modeLibrary = ChangeSet(rawValue: 1 << 5)
    }

    struct Preferences: Equatable {
        var selection: DictationSelection
        var hotkey: String
        var toggleHotkey: String?
        var pauseAudio: Bool
        var inputDevice: String?
        var asrModel: String
        var appearance: AppearancePreference
        var saveHistory: Bool
        var historyRetention: RetentionWindow
        var sidebarCollapsed: Bool
    }

    fileprivate struct Values: Equatable {
        var selection: DictationSelection
        var hotkey: String
        var toggleHotkey: String?
        var modeCycleHotkey: String?
        var pauseAudio: Bool
        var inputDevice: String?
        var asrModel: String
        var appearance: AppearancePreference
        var saveHistory: Bool
        var historyRetention: RetentionWindow
        var badgePosition: [Double]?
        var sidebarCollapsed: Bool
        var orderedModes: [Mode]
    }

    struct Recovery: Equatable {
        let message: String
        fileprivate let originalData: Data
    }

    private var values: Values
    private(set) var recovery: Recovery?
    let path: URL

    /// Observers are app-lifetime singletons, so this list is append-only.
    private var observers: [(ChangeSet) -> Void] = []

    private init(values: Values, path: URL, recovery: Recovery? = nil) {
        self.values = values
        self.path = path
        self.recovery = recovery
    }

    /// Compatibility construction for existing feature tests and thin shells.
    /// Voice to Text is removed from the editable array as the values are built.
    init(
        activeMode: String,
        hotkey: String,
        toggleHotkey: String?,
        pauseAudio: Bool,
        inputDevice: String? = nil,
        appearance: AppearancePreference = .system,
        saveHistory: Bool = true,
        historyRetention: RetentionWindow = .default,
        badgePosition: [Double]?,
        sidebarCollapsed: Bool = false,
        modeOrder: [String],
        modes: [String: Mode],
        path: URL
    ) {
        let asrModel = modeOrder.compactMap { modes[$0]?.asrModel }.first { !$0.isEmpty }
            ?? ASRModelCatalog.defaultID
        var editable: [Mode] = []
        for name in modeOrder where name != "Voice to Text" {
            guard let source = modes[name] else { continue }
            var mode = Mode(
                id: source.id ?? .random(),
                name: source.name,
                icon: source.icon,
                asrModel: asrModel,
                llmModel: source.llmModel,
                systemPrompt: source.systemPrompt,
                vocab: source.vocab,
                expands: source.expands
            )
            mode.transformation = source.transformation
            editable.append(mode)
        }
        let selection: DictationSelection = if activeMode == "Voice to Text" {
            .voiceToText
        } else if let id = editable.first(where: { $0.name == activeMode })?.id {
            .mode(id)
        } else {
            .voiceToText
        }
        values = Values(
            selection: selection,
            hotkey: hotkey,
            toggleHotkey: toggleHotkey,
            modeCycleHotkey: nil,
            pauseAudio: pauseAudio,
            inputDevice: inputDevice,
            asrModel: asrModel,
            appearance: appearance,
            saveHistory: saveHistory,
            historyRetention: historyRetention,
            badgePosition: badgePosition,
            sidebarCollapsed: sidebarCollapsed,
            orderedModes: editable
        )
        self.path = path
        recovery = nil
    }

    var selection: DictationSelection {
        values.selection
    }

    var hotkey: String {
        values.hotkey
    }

    var toggleHotkey: String? {
        values.toggleHotkey
    }

    var modeCycleHotkey: String? {
        values.modeCycleHotkey
    }

    var pauseAudio: Bool {
        values.pauseAudio
    }

    var inputDevice: String? {
        values.inputDevice
    }

    var asrModel: String {
        values.asrModel
    }

    var appearance: AppearancePreference {
        values.appearance
    }

    var saveHistory: Bool {
        values.saveHistory
    }

    var historyRetention: RetentionWindow {
        values.historyRetention
    }

    var badgePosition: [Double]? {
        values.badgePosition
    }

    var sidebarCollapsed: Bool {
        values.sidebarCollapsed
    }

    var orderedModes: [Mode] {
        values.orderedModes
    }

    var isReadOnly: Bool {
        recovery != nil
    }

    var preferences: Preferences {
        Preferences(
            selection: selection,
            hotkey: hotkey,
            toggleHotkey: toggleHotkey,
            pauseAudio: pauseAudio,
            inputDevice: inputDevice,
            asrModel: asrModel,
            appearance: appearance,
            saveHistory: saveHistory,
            historyRetention: historyRetention,
            sidebarCollapsed: sidebarCollapsed
        )
    }

    /// Temporary name projections keep the existing surfaces operational while
    /// stable-ID menu and editor work lands in the following slices.
    var activeMode: String {
        switch selection {
        case .voiceToText: "Voice to Text"
        case let .mode(id): mode(id: id)?.name ?? "Voice to Text"
        }
    }

    var modeOrder: [String] {
        ["Voice to Text"] + orderedModes.map(\.name)
    }

    var modes: [String: Mode] {
        var projection = Dictionary(uniqueKeysWithValues: orderedModes.map { ($0.name, $0) })
        projection["Voice to Text"] = .voiceToText(asrModel: asrModel)
        return projection
    }

    var mode: Mode {
        switch selection {
        case .voiceToText:
            .voiceToText(asrModel: asrModel)
        case let .mode(id):
            mode(id: id) ?? .voiceToText(asrModel: asrModel)
        }
    }

    var llmModel: String? {
        orderedModes.first(where: \.usesLLM)?.llmModel
    }

    func mode(id: ModeID) -> Mode? {
        orderedModes.first { $0.id == id }
    }

    func modeCycleSuccessor(after id: ModeID) -> ModeID? {
        guard orderedModes.count > 1,
              let currentIndex = orderedModes.firstIndex(where: { $0.id == id })
        else { return nil }
        let nextIndex = orderedModes.index(after: currentIndex)
        let successorIndex = nextIndex == orderedModes.endIndex
            ? orderedModes.startIndex
            : nextIndex
        return orderedModes[successorIndex].id
    }

    @MainActor
    func onChange(_ observer: @escaping (ChangeSet) -> Void) {
        observers.append(observer)
    }

    /// Builds and validates a complete candidate, persists it atomically, then
    /// makes it observable. No live value changes when validation or writing fails.
    @MainActor
    private func update(_ body: (inout Values) throws -> Void) throws {
        guard recovery == nil else { throw ConfigError.readOnlyRecovery }
        var candidate = values
        try body(&candidate)
        candidate = Self.normalized(candidate)
        try Self.validate(candidate, requireNormalized: true)
        try Self.persist(candidate, to: path)
        let changes = Self.changes(from: values, to: candidate)
        values = candidate
        publish(changes)
    }

    @MainActor
    func setActiveMode(_ name: String) throws {
        if name == "Voice to Text" {
            try update { $0.selection = .voiceToText }
            return
        }
        guard let id = orderedModes.first(where: { $0.name == name })?.id else { return }
        try update { $0.selection = .mode(id) }
    }

    @MainActor
    func select(_ selection: DictationSelection) throws {
        try update { $0.selection = selection }
    }

    @MainActor
    func apply(_ preferences: Preferences) throws {
        try update { candidate in
            candidate.selection = preferences.selection
            candidate.hotkey = preferences.hotkey
            candidate.toggleHotkey = preferences.toggleHotkey
            candidate.pauseAudio = preferences.pauseAudio
            candidate.inputDevice = preferences.inputDevice
            candidate.asrModel = preferences.asrModel
            candidate.appearance = preferences.appearance
            candidate.saveHistory = preferences.saveHistory
            candidate.historyRetention = preferences.historyRetention
            candidate.sidebarCollapsed = preferences.sidebarCollapsed
        }
    }

    @MainActor
    func replaceModes(_ modes: [Mode], selection: DictationSelection) throws {
        try update {
            $0.orderedModes = modes
            $0.selection = selection
        }
    }

    @MainActor
    func saveMode(_ mode: Mode) throws {
        guard let id = mode.id,
              let index = orderedModes.firstIndex(where: { $0.id == id })
        else { throw ConfigError.invalid("Mode does not exist.") }
        try update { $0.orderedModes[index] = mode }
    }

    @MainActor
    func setASRModel(_ id: String) throws {
        try update { $0.asrModel = id }
    }

    @MainActor
    func setInputDevice(_ uid: String?) throws {
        try update { $0.inputDevice = uid }
    }

    @MainActor
    func setBadgePosition(_ position: [Double]?) throws {
        try update { $0.badgePosition = position }
    }

    @MainActor
    func setAppearance(_ appearance: AppearancePreference) throws {
        try update { $0.appearance = appearance }
    }

    @MainActor
    func setHotkey(_ hotkey: String) throws {
        try update { $0.hotkey = hotkey }
    }

    @MainActor
    func setSaveHistory(_ saveHistory: Bool) throws {
        try update { $0.saveHistory = saveHistory }
    }

    @MainActor
    func setHistoryRetention(_ retention: RetentionWindow) throws {
        try update { $0.historyRetention = retention }
    }

    func save() throws {
        guard recovery == nil else { throw ConfigError.readOnlyRecovery }
        try Self.validate(values, requireNormalized: true)
        try Self.persist(values, to: path)
    }

    func save(to url: URL) throws {
        try Self.validate(values, requireNormalized: true)
        try Self.persist(values, to: url)
    }

    /// Recovery reset first preserves the rejected bytes, then atomically
    /// replaces config.json and publishes the fresh committed state.
    @MainActor
    @discardableResult
    func resetRecovery(now: Date = Date()) throws -> URL {
        guard let recovery else { throw ConfigError.invalid("Configuration is not in recovery.") }
        let backup = Self.backupURL(for: path, now: now)
        try recovery.originalData.write(to: backup, options: .atomic)
        let defaults = Self.defaultValues()
        try Self.persist(defaults, to: path)
        let changes = Self.changes(from: values, to: defaults)
        values = defaults
        self.recovery = nil
        publish(changes)
        return backup
    }

    private func publish(_ changes: ChangeSet) {
        guard !changes.isEmpty else { return }
        for observer in observers {
            observer(changes)
        }
    }

    private static func changes(from old: Values, to new: Values) -> ChangeSet {
        var result: ChangeSet = []
        if old.selection != new.selection { result.insert(.selection) }
        if old.hotkey != new.hotkey || old.toggleHotkey != new.toggleHotkey
            || old.modeCycleHotkey != new.modeCycleHotkey {
            result.insert(.hotkeys)
        }
        if old.asrModel != new.asrModel { result.insert(.asrModel) }
        if old.inputDevice != new.inputDevice { result.insert(.inputDevice) }
        if old.appearance != new.appearance { result.insert(.appearance) }
        if !libraryEqual(old.orderedModes, new.orderedModes) { result.insert(.modeLibrary) }
        return result
    }

    private static func libraryEqual(_ lhs: [Mode], _ rhs: [Mode]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
                && left.name == right.name
                && left.icon == right.icon
                && left.llmModel == right.llmModel
                && left.systemPrompt == right.systemPrompt
                && left.vocab == right.vocab
                && left.transformation == right.transformation
        }
    }

    // MARK: - Schema 1 persistence

    static func load(from url: URL) throws -> Config {
        let data = try Data(contentsOf: url)
        try validateKeys(in: data)
        let dto: DTO
        do {
            dto = try JSONDecoder().decode(DTO.self, from: data)
        } catch {
            throw ConfigError.invalid("Invalid configuration: \(error.localizedDescription)")
        }
        guard dto.schemaVersion == 1 else {
            throw ConfigError.invalid("Unsupported schema_version \(dto.schemaVersion).")
        }
        guard let retention = RetentionWindow(rawValue: dto.retentionDays) else {
            throw ConfigError.invalid("retention_days is not supported.")
        }
        let selection: DictationSelection
        switch dto.activeSelection.type {
        case .voiceToText:
            guard dto.activeSelection.modeID == nil else {
                throw ConfigError.invalid("Voice to Text selection cannot contain mode_id.")
            }
            selection = .voiceToText
        case .mode:
            guard let id = dto.activeSelection.modeID else {
                throw ConfigError.invalid("Mode selection requires mode_id.")
            }
            selection = .mode(id)
        }
        let modes = dto.modes.map {
            Mode(
                id: $0.id,
                name: $0.name,
                icon: $0.icon,
                asrModel: dto.asrModel,
                llmModel: $0.llmModel,
                transformation: $0.transformation,
                systemPrompt: $0.systemPrompt,
                vocabulary: $0.vocabulary
            )
        }
        let values = Values(
            selection: selection,
            hotkey: dto.hotkey,
            toggleHotkey: dto.toggleHotkey,
            modeCycleHotkey: dto.modeCycleHotkey,
            pauseAudio: dto.pauseAudio,
            inputDevice: dto.inputDevice,
            asrModel: dto.asrModel,
            appearance: dto.appearance,
            saveHistory: dto.saveHistory,
            historyRetention: retention,
            badgePosition: dto.badgePosition,
            sidebarCollapsed: dto.sidebarCollapsed,
            orderedModes: modes
        )
        try validate(values, requireNormalized: true)
        return Config(values: values, path: url)
    }

    static func loadOrCreate(at url: URL) -> Config {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            let config = defaultConfig(path: url)
            do {
                try config.save()
                return config
            } catch {
                return recoveryConfig(
                    path: url,
                    originalData: Data(),
                    message: "FoldWise Voice couldn't create config.json: \(error.localizedDescription)"
                )
            }
        }
        do {
            return try load(from: url)
        } catch {
            let original = (try? Data(contentsOf: url)) ?? Data()
            return recoveryConfig(
                path: url,
                originalData: original,
                message: error.localizedDescription
            )
        }
    }

    static func defaultConfig(path: URL) -> Config {
        Config(values: defaultValues(), path: path)
    }

    private static func defaultValues() -> Values {
        let asr = ASRModelCatalog.defaultID
        let casualID = ModeID.random()
        let casual = Mode(
            id: casualID,
            name: "Casual",
            icon: "wand.and.sparkles",
            asrModel: asr,
            llmModel: "qwen2.5:3b",
            transformation: .inPlace,
            systemPrompt: "You clean up dictated speech. Fix punctuation, capitalization, "
                + "and obvious transcription errors. Remove filler words (um, uh, "
                + "like, you know). Do NOT change meaning, add content, or answer "
                + "questions. Output ONLY the cleaned text.",
            vocabulary: []
        )
        let email = Mode(
            id: .random(),
            name: "Email",
            icon: "envelope",
            asrModel: asr,
            llmModel: "qwen2.5:3b",
            transformation: .expanding,
            systemPrompt: "Rewrite this dictation as a clear, concise, professional email "
                + "body. Output only the email text.",
            vocabulary: []
        )
        return Values(
            selection: .mode(casualID),
            hotkey: "alt_r",
            toggleHotkey: nil,
            modeCycleHotkey: nil,
            pauseAudio: true,
            inputDevice: nil,
            asrModel: asr,
            appearance: .system,
            saveHistory: true,
            historyRetention: .default,
            badgePosition: nil,
            sidebarCollapsed: false,
            orderedModes: [casual, email]
        )
    }

    private static func recoveryConfig(path: URL, originalData: Data, message: String) -> Config {
        var defaults = defaultValues()
        defaults.selection = .voiceToText
        return Config(
            values: defaults,
            path: path,
            recovery: Recovery(message: message, originalData: originalData)
        )
    }

    private static func persist(_ values: Values, to url: URL) throws {
        let dto = DTO(values: values)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(dto)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private static func normalized(_ source: Values) -> Values {
        var result = source
        result.hotkey = source.hotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        result.toggleHotkey = cleanedOptional(source.toggleHotkey)
        result.modeCycleHotkey = cleanedOptional(source.modeCycleHotkey)
        result.inputDevice = cleanedOptional(source.inputDevice)
        result.asrModel = source.asrModel.trimmingCharacters(in: .whitespacesAndNewlines)
        result.orderedModes = source.orderedModes.map { sourceMode in
            var mode = sourceMode
            mode.name = ModeTextPolicy.cleanName(sourceMode.name)
            mode.icon = sourceMode.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            mode.llmModel = cleanedOptional(sourceMode.llmModel)
            mode.systemPrompt = cleanedOptional(sourceMode.systemPrompt)
            mode.vocab = ModeTextPolicy.cleanVocabulary(sourceMode.vocab)
            mode.asrModel = result.asrModel
            return mode
        }
        return result
    }

    private static func validate(_ values: Values, requireNormalized: Bool) throws {
        guard !values.hotkey.isEmpty else { throw ConfigError.invalid("hotkey cannot be empty.") }
        try validateShortcut(values.hotkey, field: "hotkey")
        try validateOptionalShortcut(values.toggleHotkey, field: "toggle_hotkey")
        try validateOptionalShortcut(values.modeCycleHotkey, field: "mode_cycle_hotkey")
        guard !values.asrModel.isEmpty else { throw ConfigError.invalid("asr_model cannot be empty.") }
        if requireNormalized {
            guard values.hotkey == values.hotkey.trimmingCharacters(in: .whitespacesAndNewlines),
                  values.toggleHotkey == cleanedOptional(values.toggleHotkey),
                  values.modeCycleHotkey == cleanedOptional(values.modeCycleHotkey),
                  values.inputDevice == cleanedOptional(values.inputDevice),
                  values.asrModel
                  == values.asrModel.trimmingCharacters(in: .whitespacesAndNewlines)
            else { throw ConfigError.invalid("Top-level string fields must be normalized.") }
        }
        if let position = values.badgePosition {
            guard position.count == 2, position.allSatisfy(\.isFinite) else {
                throw ConfigError.invalid("badge_position must contain two finite numbers.")
            }
        }

        var ids = Set<ModeID>()
        var names = Set<String>()
        for mode in values.orderedModes {
            guard let id = mode.id else { throw ConfigError.invalid("Every Mode requires an id.") }
            guard ids.insert(id).inserted else { throw ConfigError.invalid("Mode IDs must be unique.") }
            let cleanedName = ModeTextPolicy.cleanName(mode.name)
            guard !cleanedName.isEmpty else { throw ConfigError.invalid("Mode name cannot be empty.") }
            if requireNormalized, cleanedName != mode.name {
                throw ConfigError.invalid("Mode names must use normalized whitespace and Unicode.")
            }
            guard names.insert(ModeTextPolicy.comparisonKey(cleanedName)).inserted else {
                throw ConfigError.invalid("Mode names must be unique.")
            }
            guard !mode.icon.isEmpty else { throw ConfigError.invalid("Mode icon cannot be empty.") }
            guard let model = mode.llmModel, !model.isEmpty else {
                throw ConfigError.invalid("Mode llm_model cannot be empty.")
            }
            guard let prompt = mode.systemPrompt, !prompt.isEmpty else {
                throw ConfigError.invalid("Mode system_prompt cannot be empty.")
            }
            if requireNormalized {
                guard model == model.trimmingCharacters(in: .whitespacesAndNewlines),
                      prompt == prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                      mode.icon == mode.icon.trimmingCharacters(in: .whitespacesAndNewlines),
                      mode.vocab == ModeTextPolicy.cleanVocabulary(mode.vocab)
                else { throw ConfigError.invalid("Mode fields must be normalized.") }
            }
        }

        switch values.selection {
        case .voiceToText:
            break
        case let .mode(id):
            guard ids.contains(id) else {
                throw ConfigError.invalid("active_selection refers to a missing Mode.")
            }
        }
        if values.orderedModes.isEmpty, values.selection != .voiceToText {
            throw ConfigError.invalid("Zero Modes requires Voice to Text selection.")
        }
    }

    private static func validateShortcut(_ value: String, field: String) throws {
        do {
            _ = try KeyMap.parse(value)
        } catch {
            throw ConfigError.invalid("\(field) is invalid: \(error.localizedDescription)")
        }
    }

    private static func validateOptionalShortcut(_ value: String?, field: String) throws {
        guard let value else { return }
        guard !value.isEmpty else { throw ConfigError.invalid("\(field) cannot be empty.") }
        try validateShortcut(value, field: field)
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func backupURL(for path: URL, now: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: now)
            .replacingOccurrences(of: ":", with: "-")
        let directory = path.deletingLastPathComponent()
        let base = path.lastPathComponent + ".backup-" + stamp
        var candidate = directory.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        return candidate
    }

    private static func validateKeys(in data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ConfigError.invalid("Malformed JSON: \(error.localizedDescription)")
        }
        guard let top = object as? [String: Any] else {
            throw ConfigError.invalid("Configuration must be a JSON object.")
        }
        let topKeys: Set = [
            "schema_version", "active_selection", "hotkey", "toggle_hotkey",
            "mode_cycle_hotkey", "pause_audio", "input_device", "asr_model",
            "appearance", "save_history", "retention_days", "badge_position",
            "sidebar_collapsed", "modes",
        ]
        guard Set(top.keys) == topKeys else {
            throw ConfigError.invalid("Configuration has unknown or missing top-level fields.")
        }
        guard let selection = top["active_selection"] as? [String: Any],
              let type = selection["type"] as? String
        else { throw ConfigError.invalid("active_selection must be an object.") }
        let selectionKeys: Set<String> = type == "mode" ? ["type", "mode_id"] : ["type"]
        guard Set(selection.keys) == selectionKeys else {
            throw ConfigError.invalid("active_selection has unknown or missing fields.")
        }
        guard let modes = top["modes"] as? [Any] else {
            throw ConfigError.invalid("modes must be an array.")
        }
        let modeKeys: Set = [
            "id", "name", "icon", "llm_model", "transformation", "system_prompt", "vocabulary",
        ]
        for value in modes {
            guard let mode = value as? [String: Any], Set(mode.keys) == modeKeys else {
                throw ConfigError.invalid("Each Mode has unknown or missing fields.")
            }
        }
    }

    /// Resolution order: explicit CLI path, environment override, config.json
    /// in the working directories, then Application Support.
    static func resolvePath(cliPath: String?) -> URL {
        let fileManager = FileManager.default
        if let cliPath { return URL(fileURLWithPath: cliPath) }
        if let environmentPath = ProcessInfo.processInfo.environment["FOLDWISE_CONFIG"],
           !environmentPath.isEmpty {
            return URL(fileURLWithPath: environmentPath)
        }
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        for candidate in [
            workingDirectory.appendingPathComponent("config.json"),
            workingDirectory.deletingLastPathComponent().appendingPathComponent("config.json"),
        ] where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FoldWise Voice", isDirectory: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("config.json")
    }
}

private extension Config {
    struct DTO: Codable {
        let schemaVersion: Int
        let activeSelection: SelectionDTO
        let hotkey: String
        let toggleHotkey: String?
        let modeCycleHotkey: String?
        let pauseAudio: Bool
        let inputDevice: String?
        let asrModel: String
        let appearance: AppearancePreference
        let saveHistory: Bool
        let retentionDays: Int
        let badgePosition: [Double]?
        let sidebarCollapsed: Bool
        let modes: [ModeDTO]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case activeSelection = "active_selection"
            case hotkey
            case toggleHotkey = "toggle_hotkey"
            case modeCycleHotkey = "mode_cycle_hotkey"
            case pauseAudio = "pause_audio"
            case inputDevice = "input_device"
            case asrModel = "asr_model"
            case appearance
            case saveHistory = "save_history"
            case retentionDays = "retention_days"
            case badgePosition = "badge_position"
            case sidebarCollapsed = "sidebar_collapsed"
            case modes
        }

        fileprivate init(values: Values) {
            schemaVersion = 1
            activeSelection = SelectionDTO(values.selection)
            hotkey = values.hotkey
            toggleHotkey = values.toggleHotkey
            modeCycleHotkey = values.modeCycleHotkey
            pauseAudio = values.pauseAudio
            inputDevice = values.inputDevice
            asrModel = values.asrModel
            appearance = values.appearance
            saveHistory = values.saveHistory
            retentionDays = values.historyRetention.rawValue
            badgePosition = values.badgePosition
            sidebarCollapsed = values.sidebarCollapsed
            modes = values.orderedModes.compactMap(ModeDTO.init)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(activeSelection, forKey: .activeSelection)
            try container.encode(hotkey, forKey: .hotkey)
            try encode(toggleHotkey, in: &container, forKey: .toggleHotkey)
            try encode(modeCycleHotkey, in: &container, forKey: .modeCycleHotkey)
            try container.encode(pauseAudio, forKey: .pauseAudio)
            try encode(inputDevice, in: &container, forKey: .inputDevice)
            try container.encode(asrModel, forKey: .asrModel)
            try container.encode(appearance, forKey: .appearance)
            try container.encode(saveHistory, forKey: .saveHistory)
            try container.encode(retentionDays, forKey: .retentionDays)
            if let badgePosition {
                try container.encode(badgePosition, forKey: .badgePosition)
            } else {
                try container.encodeNil(forKey: .badgePosition)
            }
            try container.encode(sidebarCollapsed, forKey: .sidebarCollapsed)
            try container.encode(modes, forKey: .modes)
        }

        private func encode(
            _ value: String?,
            in container: inout KeyedEncodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) throws {
            if let value {
                try container.encode(value, forKey: key)
            } else {
                try container.encodeNil(forKey: key)
            }
        }
    }

    struct SelectionDTO: Codable {
        enum Kind: String, Codable {
            case voiceToText = "voice_to_text"
            case mode
        }

        let type: Kind
        let modeID: ModeID?

        enum CodingKeys: String, CodingKey {
            case type
            case modeID = "mode_id"
        }

        init(_ selection: DictationSelection) {
            switch selection {
            case .voiceToText:
                type = .voiceToText
                modeID = nil
            case let .mode(id):
                type = .mode
                modeID = id
            }
        }
    }

    struct ModeDTO: Codable {
        let id: ModeID
        let name: String
        let icon: String
        let llmModel: String
        let transformation: ModeTransformation
        let systemPrompt: String
        let vocabulary: [String]

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case icon
            case llmModel = "llm_model"
            case transformation
            case systemPrompt = "system_prompt"
            case vocabulary
        }

        init?(_ mode: Mode) {
            guard let id = mode.id,
                  let llmModel = mode.llmModel,
                  let systemPrompt = mode.systemPrompt
            else { return nil }
            self.id = id
            name = mode.name
            icon = mode.icon
            self.llmModel = llmModel
            transformation = mode.transformation
            self.systemPrompt = systemPrompt
            vocabulary = mode.vocab
        }
    }
}
