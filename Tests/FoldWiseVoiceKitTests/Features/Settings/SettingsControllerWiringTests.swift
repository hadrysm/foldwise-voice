import Combine
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
final class SettingsControllerWiringTests: XCTestCase {
    private let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-settings-controller-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: dir)
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

    func testPreferenceCallbackReachesWorkflow() {
        let store = JSONLHistoryStore(url: dir.appendingPathComponent("preference-history.jsonl"))
        let config = makeConfig()
        let controller = SettingsController(
            config: config, historyStore: store, statsStore: WiringStatsStore()
        )
        controller.model.pttKey = "F8"

        controller.model.onCommit?()

        XCTAssertEqual(config.hotkey, "F8")
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

        let published = expectation(description: "Input state published to Settings")
        var observation: AnyCancellable?
        observation = controller.model.$inputState.dropFirst().sink { state in
            if state == changed { published.fulfill() }
        }

        inputDevices.onInputStateChange?(changed)
        await fulfillment(of: [published], timeout: 1)
        withExtendedLifetime(observation) {}

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
            activeMode: "Voice to Text", hotkey: "F5", toggleHotkey: nil, pauseAudio: false,
            badgePosition: nil, modeOrder: ["Voice to Text"],
            modes: ["Voice to Text": Mode(
                name: "Voice to Text", asrModel: "", llmModel: nil,
                systemPrompt: nil, vocab: []
            )],
            path: dir.appendingPathComponent("modes.json")
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
