// Owns the floating NSPanel that hosts BadgeView, and drives BadgeModel
// through the pure BadgeReducer (PRD #103). The panel discipline is inherited
// from the retired HUD: non-blocking animator resizes, native dragging, an
// anchor that tracks live drags, and hover-exit hysteresis so edge flicker
// can't loop the grow/shrink animation. The panel never becomes key or main,
// so the Badge — hover, tooltips, and the mode menu included — can't steal
// focus from the app being dictated into.

import AppKit
import SwiftUI

final class BadgePanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class BadgeController: NSObject {
    static let bottomMargin: CGFloat = 96

    let model = BadgeModel()
    private let config: Config
    private let onOpenApp: () -> Void
    weak var recorder: AudioRecorder?
    /// Wired to Pipeline.stopRecording(); issued by the reducer's
    /// `.stopRecording` command (click anywhere on the recording pill).
    var onStop: (() -> Void)?
    /// Wired to Pipeline.toggleRecording(); the hover mic button.
    var onRecord: (() -> Void)?

    private var panel: BadgePanel?
    private weak var activeModeMenu: NSMenu?
    private var moveObserver: NSObjectProtocol?
    private var levelTimer: Timer?
    private var secondsTimer: Timer?
    private var dwellTimer: Timer?
    private var unhoverWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var deferredModeSelectionError = false
    private var programmaticMove = false
    private var smoother = LevelSmoother()
    /// Pill anchor: (capsule center-x, bottom-y) in screen points.
    private var anchor: CGPoint?

    init(config: Config, onOpenApp: @escaping () -> Void) {
        self.config = config
        self.onOpenApp = onOpenApp
        super.init()
        if let pos = config.badgePosition, pos.count == 2 {
            anchor = CGPoint(x: pos[0], y: pos[1])
        }
        model.activeModeName = config.activeMode
        model.hotkeyLabel = KeyMap.pretty(config.hotkey)
        config.onChange { [weak self] changes in
            guard let self else { return }
            if changes.contains(.selection) || changes.contains(.modeLibrary) {
                model.activeModeName = config.activeMode
            }
            if changes.contains(.modeLibrary), let menu = activeModeMenu {
                rebuildModeMenu(menu)
            } else if changes.contains(.selection), let menu = activeModeMenu {
                refreshModeMenuChecks(menu)
            }
            if changes.contains(.hotkeys) { model.hotkeyLabel = KeyMap.pretty(config.hotkey) }
            panel?.isMovableByWindowBackground = !config.isReadOnly
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    // MARK: - public API (main thread)

    /// Put the idle pill on screen (launch).
    func show() {
        ensurePanel()
        enter(model.state)
        panel?.orderFrontRegardless()
    }

    /// Fold a pipeline phase into the state machine.
    func apply(_ phase: PipelineState) {
        handle(.pipeline(phase))
    }

    func showModeSelectionError() {
        handle(.modeSelectionFailed)
    }

    func hide() {
        stopTimers()
        unhoverWork?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - reducer plumbing

    private func handle(_ event: BadgeEvent) {
        ensurePanel()
        let transition = BadgeReducer.reduce(model.state, event)
        switch transition.command {
        case .stopRecording:
            onStop?()
        case .deferModeSelectionError:
            deferredModeSelectionError = true
        case nil:
            break
        }
        if transition.state != model.state {
            enter(transition.state)
            panel?.orderFrontRegardless()
        }
        if model.state == .idle, deferredModeSelectionError {
            deferredModeSelectionError = false
            handle(.modeSelectionFailed)
        }
    }

    /// Make `state` current: swap the model, re-fit the pill, and start the
    /// state's timers (recording seconds + mic level, or a dwell that returns
    /// the pill to idle).
    private func enter(_ state: BadgeState) {
        let wasRecording = model.state == .recording
        model.state = state
        setSize(CGSize(width: state.width, height: Theme.badgeHeight))
        if state == .recording, !wasRecording {
            startRecordingTimers()
        } else if state != .recording, wasRecording {
            stopRecordingTimers()
        }
        dwellTimer?.invalidate()
        dwellTimer = nil
        if let dwell = state.dwell {
            dwellTimer = Timer.scheduledTimer(withTimeInterval: dwell, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.handle(.dwellElapsed) }
            }
        }
    }

    // MARK: - panel

    private func ensurePanel() {
        guard panel == nil else { return }
        let rect = NSRect(origin: .zero, size: CGSize(width: BadgeState.idle.width, height: Theme.badgeHeight))
        let p = BadgePanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        // The pill draws flat — shadows smudge light wallpapers — and
        // AppKit's window shadow would trace the panel's semi-transparent
        // bounds and draw its 1px rim as a rectangle around the pill.
        p.hasShadow = false
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = !config.isReadOnly
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = BadgeView(
            model: model,
            onHover: { [weak self] over in self?.setHover(over) },
            onClick: { [weak self] in self?.handle(.clicked) },
            onChangeMode: { [weak self] in self?.popUpModeMenu() },
            onRecord: { [weak self] in self?.onRecord?() },
            onOpenApp: { [weak self] in self?.onOpenApp() }
        )
        p.contentView = NSHostingView(rootView: view)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windowMoved() }
        }

        panel = p
        setSize(rect.size, animate: false)
    }

    /// The sparkle button's mode picker: every Mode with the active one
    /// checked, built fresh from config on every click so it can never go
    /// stale. NSMenu never activates the app, so focus stays put.
    private func popUpModeMenu() {
        let menu = NSMenu()
        rebuildModeMenu(menu)
        activeModeMenu = menu
        defer { activeModeMenu = nil }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func rebuildModeMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let projection = ModePresentationFactory.projection(
            modes: config.orderedModes,
            selection: config.selection
        )
        for (index, projectionItem) in projection.items.enumerated() {
            if index == 1 { menu.addItem(.separator()) }
            let item = ModePresentationFactory.menuItem(
                for: projectionItem,
                target: self,
                action: #selector(modeMenuItemPicked(_:))
            )
            item.isEnabled = !config.isReadOnly
            menu.addItem(item)
        }
    }

    private func refreshModeMenuChecks(_ menu: NSMenu) {
        for item in menu.items {
            guard let selection = item.representedObject as? DictationSelection else { continue }
            let isSelected = selection == config.selection
            item.state = isSelected ? .on : .off
            item.setAccessibilityValue(isSelected ? "Selected" : "Not selected")
        }
    }

    @objc private func modeMenuItemPicked(_ item: NSMenuItem) {
        guard let selection = item.representedObject as? DictationSelection else { return }
        do {
            try config.select(selection)
        } catch {
            showModeSelectionError()
            Log.config.error(
                "Could not select Mode from the Badge: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func defaultAnchor() -> CGPoint {
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            return CGPoint(x: f.midX, y: f.origin.y + Self.bottomMargin)
        }
        return CGPoint(x: 400, y: Self.bottomMargin)
    }

    private func screenFrame(at point: CGPoint) -> NSRect? {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame
    }

    /// Resize the pill around its anchor, clamped to the screen it sits on.
    /// 300ms with the spec's cubic-bezier(.4, 0, .2, 1) easing.
    private func setSize(_ size: CGSize, animate: Bool = true) {
        guard let panel else { return }
        let a = anchor ?? defaultAnchor()
        var x = a.x - size.width / 2
        var y = a.y
        if let f = screenFrame(at: a) {
            x = max(f.minX + 4, min(x, f.maxX - size.width - 4))
            y = max(f.minY + 4, min(y, f.maxY - size.height - 4))
        }
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        guard frame != panel.frame else { return }
        programmaticMove = true
        if animate {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
                panel.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.programmaticMove = false }
            }
        } else {
            panel.setFrame(frame, display: true)
            programmaticMove = false
        }
    }

    // MARK: - hover (with hysteresis)

    private func setHover(_ over: Bool) {
        unhoverWork?.cancel()
        unhoverWork = nil
        if over {
            handle(.hoverChanged(true))
        } else {
            let work = DispatchWorkItem { [weak self] in self?.handle(.hoverChanged(false)) }
            unhoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    // MARK: - drag persistence

    private func windowMoved() {
        // Only user drags move the anchor. Programmatic resizes can be
        // clamped at a screen edge, which shifts midX — tracking those would
        // drift the anchor toward the screen center on every dictation.
        guard let panel, !programmaticMove, !config.isReadOnly else { return }
        let f = panel.frame
        anchor = CGPoint(x: f.midX, y: f.minY)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistAnchor() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func persistAnchor() {
        guard let anchor else { return }
        let new = [Double(anchor.x), Double(anchor.y)]
        if let old = config.badgePosition, old.count == 2,
           abs(old[0] - new[0]) < 0.5, abs(old[1] - new[1]) < 0.5 {
            return
        }
        // badgePosition has no ChangeSet member, so this persists silently —
        // in particular it never rebuilds the TCC-sensitive hotkey tap.
        do {
            try config.setBadgePosition(new.map { ($0 * 10).rounded() / 10 })
        } catch {
            Log.config.error(
                "Could not save the Badge position: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - timers

    private func startRecordingTimers() {
        model.recordingSeconds = 0
        smoother.reset()
        model.amplitude = smoother.amplitude
        secondsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.recordingSeconds += 1 }
        }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.amplitude = self.smoother.add(
                    rms: Double(self.recorder?.level ?? 0), dt: 1.0 / 30.0
                )
            }
        }
    }

    private func stopRecordingTimers() {
        secondsTimer?.invalidate()
        secondsTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        smoother.reset()
        model.amplitude = smoother.amplitude
    }

    private func stopTimers() {
        stopRecordingTimers()
        dwellTimer?.invalidate()
        dwellTimer = nil
    }
}
