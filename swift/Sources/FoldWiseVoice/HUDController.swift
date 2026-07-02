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
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HUDController {
    static let miniSize = CGSize(width: 90, height: 16)
    static let hoverSize = CGSize(width: 150, height: 26)
    static let fullSize = CGSize(width: 340, height: 64)
    static let bottomMargin: CGFloat = 96

    let model = HUDModel()
    private let config: Config
    private let onSettings: () -> Void
    weak var recorder: AudioRecorder?

    private var panel: HUDPanel?
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
        if let pos = config.hudPosition, pos.count == 2 {
            anchor = CGPoint(x: pos[0], y: pos[1])
        }
    }

    // MARK: - public API (main thread)

    func idle() {
        ensurePanel()
        cancelHide()
        stopLevelTimer()
        model.phase = .idle
        model.label = ""
        setSize(model.hovering ? Self.hoverSize : Self.miniSize)
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
        setSize(Self.fullSize)
        panel?.orderFrontRegardless()
    }

    func flash(_ phase: HUDModel.Phase, _ label: String, seconds: TimeInterval = 1.4) {
        show(phase, label)
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) {
            [weak self] _ in
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
        let rect = NSRect(origin: .zero, size: Self.miniSize)
        let p = HUDPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
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
            onGear: { [weak self] in self?.onSettings() })
        p.contentView = NSHostingView(rootView: view)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: p, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.windowMoved() }
        }

        panel = p
        setSize(Self.miniSize, animate: false)
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
            NSAnimationContext.runAnimationGroup(
                { ctx in
                    ctx.duration = 0.22
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(frame, display: true)
                },
                completionHandler: { [weak self] in
                    Task { @MainActor in self?.programmaticMove = false }
                })
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
            setSize(over ? Self.hoverSize : Self.miniSize)
        }
    }

    // MARK: - drag persistence

    private func windowMoved() {
        guard let panel else { return }
        let f = panel.frame
        anchor = CGPoint(x: f.midX, y: f.minY)
        guard !programmaticMove else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistAnchor() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func persistAnchor() {
        guard let anchor else { return }
        let new = [Double(anchor.x), Double(anchor.y)]
        if let old = config.hudPosition, old.count == 2,
            abs(old[0] - new[0]) < 0.5, abs(old[1] - new[1]) < 0.5
        {
            return
        }
        config.hudPosition = new.map { ($0 * 10).rounded() / 10 }
        try? config.save()
    }

    // MARK: - timers

    private func startLevelTimer() {
        guard levelTimer == nil else { return }
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
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
