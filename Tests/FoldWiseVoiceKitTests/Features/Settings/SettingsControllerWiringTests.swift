import XCTest
@testable import FoldWiseVoiceKit

private final class WiringStatsStore: StatsStore {
    private(set) var resetCount = 0
    private var record: StreakRecord?

    func load() -> StreakRecord? {
        record
    }

    func advance(on day: Date, calendar: Calendar) {
        record = StreakRules.advance(record, on: day, calendar: calendar)
    }

    func reset() {
        resetCount += 1
        record = nil
    }
}

private final class WiringInputDevices: AudioInputStateProviding {
    var inputState: AudioInputState
    var onInputStateChange: ((AudioInputState) -> Void)?

    init(_ inputState: AudioInputState) {
        self.inputState = inputState
    }
}

@MainActor
private extension SettingsController {
    convenience init(
        config: Config,
        historyStore: HistoryStore,
        statsStore: StatsStore,
        inputDevices: (any AudioInputStateProviding)? = nil,
        hotkeys: HotkeyBindingCoordinator? = nil,
        captureGate: ShortcutCaptureGate = ShortcutCaptureGate(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent,
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            config: config,
            historyStore: historyStore,
            statsStore: statsStore,
            inputDevices: inputDevices,
            hotkeys: hotkeys,
            captureGate: captureGate,
            asrLifecycle: ASRModelLifecycle(
                storedSelection: config.asrModel,
                adapters: []
            ),
            now: now,
            calendar: calendar,
            notificationCenter: notificationCenter
        )
    }
}

@MainActor
final class SettingsControllerWiringTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-settings-controller-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
    }

    func testMainHostingControllerSkipsIntrinsicSizeNegotiation() {
        let hosting = SettingsController.makeHostingController(
            model: SettingsModel()
        )

        XCTAssertTrue(hosting.sizingOptions.isEmpty)
    }

    func testSemanticHistoryCommandReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("flag-history.jsonl"))
        let row = entry(text: "stored words")
        store.append(row)
        let controller = SettingsController(
            config: makeConfig(), historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onHistoryCommand?(row, .toggleFlag)

        XCTAssertEqual(store.load().first?.flagged, true)
    }

    func testDeleteHistoryCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("delete-history.jsonl"))
        let row = entry(text: "stored words")
        store.append(row)
        let controller = SettingsController(
            config: makeConfig(), historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onHistoryCommand?(row, .delete)

        XCTAssertTrue(store.load().isEmpty)
    }

    func testClearHistoryCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("clear-history.jsonl"))
        let stats = WiringStatsStore()
        let controller = SettingsController(
            config: makeConfig(), historyStore: store, statsStore: stats
        )

        controller.model.onClearHistory?()

        XCTAssertEqual(stats.resetCount, 1)
    }

    func testCalendarDayAndTimeZoneNotificationsRefreshControllerOwnedStreak() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let notifications = NotificationCenter()
        let activeDay = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 20, hour: 12
        )))
        var currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: activeDay))
        let stats = WiringStatsStore()
        stats.advance(on: activeDay, calendar: calendar)
        let controller = SettingsController(
            config: makeConfig(),
            historyStore: JSONLHistoryStore(url: dir.appendingPathComponent("boundary-history.jsonl")),
            statsStore: stats,
            now: { currentNow },
            calendar: calendar,
            notificationCenter: notifications
        )

        notifications.post(name: .NSCalendarDayChanged, object: nil)
        let afterDayChange = controller.model.currentStreak
        currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentNow))
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)

        XCTAssertEqual([afterDayChange, controller.model.currentStreak], [1, nil])
    }

    func testPreferenceCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("preference-history.jsonl"))
        let config = makeConfig()
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )
        controller.model.pttKey = "F8"

        controller.model.onCommit?(.global)

        XCTAssertEqual(config.hotkey, "F8")
    }

    func testUpdaterConfigurationReachesSettingsCommand() {
        let controller = SettingsController(
            config: makeConfig(),
            historyStore: JSONLHistoryStore(
                url: dir.appendingPathComponent("updater-configuration-history.jsonl")
            ),
            statsStore: WiringStatsStore()
        )
        var checkCount = 0

        controller.configureUpdates(canCheckForUpdates: true) {
            checkCount += 1
        }
        controller.model.onCheckUpdates?()

        XCTAssertEqual(checkCount, 1)
    }

    func testUpdaterAvailabilityReachesSettingsModel() {
        let controller = SettingsController(
            config: makeConfig(),
            historyStore: JSONLHistoryStore(
                url: dir.appendingPathComponent("updater-availability-history.jsonl")
            ),
            statsStore: WiringStatsStore()
        )

        controller.configureUpdates(canCheckForUpdates: true, checkForUpdates: {})
        controller.setCanCheckForUpdates(false)

        XCTAssertFalse(controller.model.canCheckForUpdates)
    }

    func testModeEditorCallbacksReachAtomicWorkflow() throws {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("mode-editor-history.jsonl"))
        let config = makeConfig()
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )
        controller.model.installed = [.init(name: "qwen2.5:3b", sizeBytes: 42)]

        controller.model.onAddMode?()
        var editor = try XCTUnwrap(controller.model.modeEditor)
        editor.draft.name = "Meeting notes"
        editor.draft.systemPrompt = "Turn the transcript into concise meeting notes."
        controller.model.modeEditor = editor
        controller.model.onSaveModeEditor?()

        let saved = try XCTUnwrap(config.orderedModes.first)
        let savedID = try XCTUnwrap(saved.id)
        XCTAssertEqual(
            [
                saved.name,
                saved.llmModel,
                config.selection == .mode(savedID) ? "selected" : "not selected",
                controller.model.modeEditor == nil ? "dismissed" : "open",
            ],
            ["Meeting notes", "qwen2.5:3b", "selected", "dismissed"]
        )
    }

    func testDuplicateModeCallbackOpensCopiedDraft() throws {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("mode-lifecycle-history.jsonl"))
        let config = Config.defaultConfig(path: dir.appendingPathComponent("mode-lifecycle.json"))
        let firstID = try XCTUnwrap(config.orderedModes.first?.id)
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onDuplicateMode?(firstID)

        XCTAssertEqual(controller.model.modeEditor?.purpose, .duplicate(firstID))
    }

    func testMoveModeCallbackReordersCommittedLibrary() throws {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("move-mode-history.jsonl"))
        let config = Config.defaultConfig(path: dir.appendingPathComponent("move-mode.json"))
        let firstID = try XCTUnwrap(config.orderedModes.first?.id)
        let secondID = try XCTUnwrap(config.orderedModes.last?.id)
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onMoveMode?(firstID, .down)

        XCTAssertEqual(config.orderedModes.map(\.id), [secondID, firstID])
    }

    func testDeleteModeCallbacksConfirmCommittedRemoval() throws {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("delete-mode-history.jsonl"))
        let config = Config.defaultConfig(path: dir.appendingPathComponent("delete-mode.json"))
        let firstID = try XCTUnwrap(config.orderedModes.first?.id)
        let secondID = try XCTUnwrap(config.orderedModes.last?.id)
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )

        controller.model.onRequestModeDeletion?(secondID)
        controller.model.onConfirmModeDeletion?()

        XCTAssertEqual(config.orderedModes.map(\.id), [firstID])
    }

    func testInputDeviceProjectionInitializesSettingsModel() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("input-history.jsonl"))
        let config = makeConfig()
        let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Microphone")
        let usb = AudioInputDevice(uid: "usb-1", name: "Studio Mic")
        let state = AudioInputState(
            devices: [builtIn, usb], systemDefault: builtIn, preferredUID: nil,
            preferredName: nil, effectiveDevice: builtIn, pendingDevice: nil,
            status: .ready
        )
        let inputDevices = WiringInputDevices(state)
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore(),
            inputDevices: inputDevices
        )

        XCTAssertEqual(controller.model.inputState, state)
    }

    func testInputDeviceSelectionReachesSettingsWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("input-history.jsonl"))
        let config = makeConfig()
        let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Microphone")
        let usb = AudioInputDevice(uid: "usb-1", name: "Studio Mic")
        let state = AudioInputState(
            devices: [builtIn, usb], systemDefault: builtIn, preferredUID: nil,
            preferredName: nil, effectiveDevice: builtIn, pendingDevice: nil,
            status: .ready
        )
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore(),
            inputDevices: WiringInputDevices(state)
        )

        controller.model.onSelectInputDevice?(usb.uid)

        XCTAssertEqual(config.inputDevice, usb.uid)
    }

    func testInputDeviceProjectionPublishesLiveChanges() async {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("input-live-history.jsonl"))
        let config = makeConfig()
        let builtIn = AudioInputDevice(uid: "built-in", name: "MacBook Microphone")
        let initial = AudioInputState(
            devices: [builtIn], systemDefault: builtIn, preferredUID: nil,
            preferredName: nil, effectiveDevice: builtIn, pendingDevice: nil,
            status: .ready
        )
        let inputDevices = WiringInputDevices(initial)
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore(),
            inputDevices: inputDevices
        )
        let changed = AudioInputState(
            devices: [], systemDefault: nil, preferredUID: nil, preferredName: nil,
            effectiveDevice: nil, pendingDevice: nil,
            status: .unavailable(message: "No input device is available.")
        )

        let invalidated = expectation(description: "Input state invalidated Settings")
        withObservationTracking {
            _ = controller.model.inputState
        } onChange: {
            invalidated.fulfill()
        }

        inputDevices.onInputStateChange?(changed)
        await fulfillment(of: [invalidated], timeout: 1)

        XCTAssertEqual(controller.model.inputState, changed)
    }

    func testClosingWindowStopsShortcutRecordingMonitor() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("close-monitor-history.jsonl"))
        let config = makeConfig()
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )
        let app = NSApplication.shared
        let existingWindows = Set(app.windows.map(ObjectIdentifier.init))
        controller.show()
        controller.model.onRecord?(.ptt)

        guard let window = app.windows.first(where: {
            !existingWindows.contains(ObjectIdentifier($0))
        }) else {
            return XCTFail("Settings window was not built")
        }
        window.close()
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0
        ) else {
            return XCTFail("Key event could not be created")
        }
        app.sendEvent(event)

        XCTAssertEqual(config.hotkey, "F5")
    }

    private func makeConfig() -> Config {
        Config(
            preferences: Config.Preferences(
                selection: .voiceToText,
                hotkey: "F5",
                toggleHotkey: nil,
                pauseAudio: false,
                inputDevice: nil,
                asrModel: ASRModelCatalog.defaultID,
                appearance: .system,
                saveHistory: true,
                historyRetention: .default,
                sidebarCollapsed: false
            ),
            badgePosition: nil, orderedModes: [],
            path: dir.appendingPathComponent("config.json")
        )
    }

    private func entry(text: String) -> HistoryEntry {
        HistoryEntry(
            id: UUID(), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: text, rawText: text, isPolished: false, modeName: "Voice to Text",
            wordCount: 2, sourceApp: nil, durationMs: nil, flagged: false, flagReason: nil
        )
    }
}
