import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class HotkeyBindingCoordinatorTests: XCTestCase {
    private final class CannedListener: HotkeyListening {
        let name: String
        let events: (String) -> Void
        var startError: Error?
        var onHealthChange: ((ShortcutListenerHealth) -> Void)?
        let onStart: () -> Void

        init(
            name: String,
            events: @escaping (String) -> Void,
            startError: Error? = nil,
            onStart: @escaping () -> Void = {}
        ) {
            self.name = name
            self.events = events
            self.startError = startError
            self.onStart = onStart
        }

        func start() throws {
            events("start \(name)")
            if let startError { throw startError }
            onStart()
        }

        func stop() {
            events("stop \(name)")
        }
    }

    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("foldwise-listener-transaction-tests-\(UUID().uuidString)")

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testSuccessfulChangePreparesPersistsSwitchesThenPublishes() throws {
        let path = directory.appendingPathComponent("config.json")
        let config = Config.defaultConfig(path: path)
        try config.save()
        var events: [String] = []
        var generation = 0
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { bindings, _ in
                generation += 1
                events.append("prepare \(generation) \(bindings.modeCycle ?? "none")")
                return CannedListener(name: "\(generation)") { event in
                    if event == "stop 1" {
                        let persisted = try? Config.load(from: path).modeCycleHotkey
                        events.append("persisted \(persisted ?? "none")")
                    }
                    events.append(event)
                }
            }
        )
        config.onChange { _ in events.append("publish") }
        try coordinator.start()

        try coordinator.update(
            ShortcutBindings(
                pushToTalk: config.hotkey,
                toggleRecording: config.toggleHotkey,
                modeCycle: "F8"
            )
        )

        XCTAssertEqual(
            events,
            [
                "prepare 1 none", "start 1", "prepare 2 F8", "start 2",
                "persisted F8", "stop 1", "publish",
            ]
        )
    }

    func testPreparationFailureLeavesOldListenerAndConfigUntouched() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        try config.save()
        var events: [String] = []
        var generation = 0
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { _, _ in
                generation += 1
                events.append("prepare \(generation)")
                if generation == 2 { throw Failure(errorDescription: "prepare failed") }
                return CannedListener(name: "old", events: { events.append($0) })
            }
        )
        try coordinator.start()

        XCTAssertThrowsError(try coordinator.update(bindings(config, cycle: "F8")))

        XCTAssertEqual(events, ["prepare 1", "start old", "prepare 2"])
        XCTAssertNil(config.modeCycleHotkey)
    }

    func testInitialActivationFailureDestroysCandidateAndLeavesCoordinatorStopped() {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        var events: [String] = []
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { _, _ in
                CannedListener(
                    name: "candidate",
                    events: { events.append($0) },
                    startError: Failure(errorDescription: "activate failed")
                )
            }
        )

        XCTAssertThrowsError(try coordinator.start())
        coordinator.stop()

        XCTAssertEqual(events, ["start candidate", "stop candidate"])
    }

    func testPersistenceFailureDestroysCandidateWithoutStoppingOldListener() throws {
        let path = directory.appendingPathComponent("missing/config.json")
        let config = Config.defaultConfig(path: path)
        var events: [String] = []
        var generation = 0
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { _, _ in
                generation += 1
                return CannedListener(name: "\(generation)", events: { events.append($0) })
            }
        )
        try coordinator.start()

        XCTAssertThrowsError(try coordinator.update(bindings(config, cycle: "F8")))

        XCTAssertEqual(events, ["start 1", "start 2", "stop 2"])
        XCTAssertNil(config.modeCycleHotkey)
    }

    func testCandidateActivationFailureLeavesPersistedBindingAndOldListenerUntouched() throws {
        let path = directory.appendingPathComponent("config.json")
        let config = Config.defaultConfig(path: path)
        try config.save()
        var events: [String] = []
        var generation = 0
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { _, _ in
                generation += 1
                return CannedListener(
                    name: "\(generation)", events: { events.append($0) },
                    startError: generation == 2 ? Failure(errorDescription: "activate failed") : nil
                )
            }
        )
        try coordinator.start()

        XCTAssertThrowsError(try coordinator.update(bindings(config, cycle: "F8")))

        XCTAssertEqual(events, ["start 1", "start 2", "stop 2"])
        XCTAssertNil(config.modeCycleHotkey)
        XCTAssertNil(try Config.load(from: path).modeCycleHotkey)
    }

    func testNoOpUpdateKeepsListenerAndStopDestroysItOnce() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        var events: [String] = []
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { _, _ in
                CannedListener(name: "active", events: { events.append($0) })
            }
        )
        try coordinator.start()

        try coordinator.update(coordinator.bindings)
        coordinator.stop()

        XCTAssertEqual(events, ["start active", "stop active"])
    }

    func testCandidateCannotDispatchUntilOldListenerIsRetired() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        try config.save()
        var callbacks: [HotkeyCallbacks] = []
        var suspensionDuringStart: [Bool] = []
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: .empty,
            prepare: { _, preparedCallbacks in
                callbacks.append(preparedCallbacks)
                let index = callbacks.count - 1
                return CannedListener(
                    name: "\(index)",
                    events: { _ in },
                    onStart: {
                        suspensionDuringStart.append(preparedCallbacks.isSuspended())
                    }
                )
            }
        )

        try coordinator.start()
        try coordinator.update(bindings(config, cycle: "F8"))

        XCTAssertEqual(suspensionDuringStart, [false, true])
        XCTAssertTrue(callbacks[0].isSuspended())
        XCTAssertFalse(callbacks[1].isSuspended())
    }

    func testHealthChangesPublishOnlyFromTheActiveListener() throws {
        let config = Config.defaultConfig(path: directory.appendingPathComponent("config.json"))
        try config.save()
        var callbacks: [HotkeyCallbacks] = []
        var healthChanges: [ShortcutListenerHealth] = []
        let coordinator = HotkeyBindingCoordinator(
            config: config,
            callbacks: HotkeyCallbacks(
                isSuspended: { false },
                onPress: {},
                onRelease: {},
                onToggle: {},
                onCycle: {},
                onHealthChange: { healthChanges.append($0) }
            ),
            prepare: { _, preparedCallbacks in
                callbacks.append(preparedCallbacks)
                let generation = callbacks.count
                return CannedListener(
                    name: "\(generation)",
                    events: { _ in },
                    onStart: {
                        if generation == 2 {
                            preparedCallbacks.onHealthChange(.focusedAppOnly)
                        }
                    }
                )
            }
        )

        try coordinator.start()
        callbacks[0].onHealthChange(.global)
        try coordinator.update(bindings(config, cycle: "F8"))
        callbacks[0].onHealthChange(.focusedAppOnly)
        callbacks[1].onHealthChange(.global)

        XCTAssertEqual(healthChanges, [.global, .focusedAppOnly, .global])
    }

    func testEmptyCallbacksAcceptEveryEvent() {
        let callbacks = HotkeyCallbacks.empty

        XCTAssertFalse(callbacks.isSuspended())
        callbacks.onPress()
        callbacks.onRelease()
        callbacks.onToggle()
        callbacks.onCycle()
        callbacks.onHealthChange(.global)
    }

    private func bindings(_ config: Config, cycle: String?) -> ShortcutBindings {
        ShortcutBindings(
            pushToTalk: config.hotkey,
            toggleRecording: config.toggleHotkey,
            modeCycle: cycle
        )
    }
}
