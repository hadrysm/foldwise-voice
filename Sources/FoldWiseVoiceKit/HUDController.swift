// Owns the floating NSPanel that hosts HUDView.
//
// Lessons from the Python HUD baked in:
//   * window resizes use the non-blocking animator (never a blocking
//     animation that queues mouse events),
//   * dragging is native (isMovableByWindowBackground) so it cannot fight a
//     hover resize,
//   * the anchor tracks the live frame during drags, and hover-exit has a
//     short hysteresis so edge flicker can't loop the grow/shrink animation.

import AppKit
import SwiftUI

final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Pill sizes per HUDStyle and phase.
extension HUDStyle {
    var miniSize: CGSize {
        switch self {
        case .classic: CGSize(width: 90, height: 16)
        case .minimal: CGSize(width: 64, height: 30)
        }
    }

    /// Idle pill while hovered (classic: gear; minimal: control panel).
    var hoverSize: CGSize {
        switch self {
        case .classic: CGSize(width: 150, height: 26)
        case .minimal: CGSize(width: 136, height: 36)
        }
    }

    var fullSize: CGSize {
        switch self {
        case .classic: CGSize(width: 340, height: 64)
        case .minimal: CGSize(width: 280, height: 36)
        }
    }

    /// Recording pill is a single label-free row, so it can be slimmer.
    var listeningSize: CGSize {
        switch self {
        case .classic: CGSize(width: 340, height: 44)
        case .minimal: CGSize(width: 190, height: 36)
        }
    }
}

@MainActor
final class HUDController: NSObject {
    static let bottomMargin: CGFloat = 96

    let model = HUDModel()
    private let config: Config
    private let onSettings: () -> Void
    weak var recorder: AudioRecorder?
    /// Invoked by the HUD's stop button; wired to Pipeline.stopRecording().
    var onStop: (() -> Void)?
    /// Invoked by the hover panel's record button; wired to toggleRecording().
    var onRecord: (() -> Void)?
    /// Fired after the hover panel's mode menu changes the active mode, so
    /// the menu-bar checkmarks stay in sync.
    var onModeChanged: (() -> Void)?

    private var panel: HUDPanel?
    private var moveObserver: NSObjectProtocol?
    private var levelTimer: Timer?
    private var hideTimer: Timer?
    private var unhoverWork: DispatchWorkItem?
    private var saveWork: DispatchWorkItem?
    private var programmaticMove = false
    /// Pill anchor: (capsule center-x, bottom-y) in screen points.
    private var anchor: CGPoint?

    init(config: Config, onSettings: @escaping () -> Void) {
        self.config = config
        self.onSettings = onSettings
        super.init()
        model.style = HUDStyle(rawValue: config.hudStyle) ?? .classic
        if let pos = config.hudPosition, pos.count == 2 {
            anchor = CGPoint(x: pos[0], y: pos[1])
        }
    }

    deinit {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
    }

    // MARK: - public API (main thread)

    func idle() {
        ensurePanel()
        cancelHide()
        stopLevelTimer()
        model.phase = .idle
        model.label = ""
        setSize(size(for: .idle))
        panel?.orderFrontRegardless()
    }

    func show(_ phase: HUDModel.Phase, _ label: String) {
        ensurePanel()
        cancelHide()
        model.phase = phase
        model.label = label
        if phase == .listening {
            startLevelTimer()
        } else {
            stopLevelTimer()
        }
        setSize(size(for: phase))
        panel?.orderFrontRegardless()
    }

    /// Re-read `config.hudStyle` (after a settings save) and re-fit the pill.
    func styleChanged() {
        let style = HUDStyle(rawValue: config.hudStyle) ?? .classic
        guard model.style != style else { return }
        model.style = style
        if panel != nil {
            setSize(size(for: model.phase))
        }
    }

    private func size(for phase: HUDModel.Phase) -> CGSize {
        let style = model.style
        switch phase {
        case .idle: return model.hovering ? style.hoverSize : style.miniSize
        case .listening: return style.listeningSize
        default: return style.fullSize
        }
    }

    func flash(_ phase: HUDModel.Phase, _ label: String, seconds: TimeInterval = 1.4) {
        show(phase, label)
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.idle() }
        }
    }

    func hide() {
        cancelHide()
        stopLevelTimer()
        unhoverWork?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - panel

    private func ensurePanel() {
        guard panel == nil else { return }
        let rect = NSRect(origin: .zero, size: model.style.miniSize)
        let p = HUDPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = HUDView(
            model: model,
            onHover: { [weak self] over in self?.setHover(over) },
            onGear: { [weak self] in self?.onSettings() },
            onStop: { [weak self] in self?.onStop?() },
            onChangeMode: { [weak self] in self?.popUpModeMenu() },
            onRecord: { [weak self] in self?.onRecord?() }
        )
        p.contentView = NSHostingView(rootView: view)

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windowMoved() }
        }

        panel = p
        setSize(model.style.miniSize, animate: false)
    }

    /// Built fresh from config on every click so it can never go stale.
    private func popUpModeMenu() {
        let menu = NSMenu()
        for name in config.modeOrder {
            let item = NSMenuItem(
                title: name, action: #selector(modeMenuItemPicked(_:)), keyEquivalent: ""
            )
            item.target = self
            item.state = name == config.activeMode ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func modeMenuItemPicked(_ item: NSMenuItem) {
        config.setActiveMode(item.title)
        try? config.save()
        onModeChanged?()
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
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
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
            applyHover(true)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.applyHover(false) }
            unhoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    private func applyHover(_ over: Bool) {
        guard model.hovering != over else { return }
        model.hovering = over
        if model.phase == .idle {
            setSize(size(for: .idle))
        }
    }

    // MARK: - drag persistence

    private func windowMoved() {
        // Only user drags move the anchor. Programmatic resizes can be
        // clamped at a screen edge, which shifts midX — tracking those would
        // drift the anchor toward the screen center on every dictation.
        guard let panel, !programmaticMove else { return }
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
        if let old = config.hudPosition, old.count == 2,
           abs(old[0] - new[0]) < 0.5, abs(old[1] - new[1]) < 0.5 {
            return
        }
        config.hudPosition = new.map { ($0 * 10).rounded() / 10 }
        try? config.save()
    }

    // MARK: - timers

    private func startLevelTimer() {
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.pushLevel(self.recorder?.level ?? 0)
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        model.levels = Array(repeating: 0, count: model.levels.count)
    }

    private func cancelHide() {
        hideTimer?.invalidate()
        hideTimer = nil
    }
}
