import AppKit
import SwiftUI

/// The compact 44-point rendering shared by Home and History. It receives no
/// observable application state: hover, keyboard focus, and copy feedback are
/// owned by this identified row, while the surface routes semantic commands.
struct DictationRow: View {
    let presentation: DictationRowPresentation
    let moreCapabilities: DictationRowMoreCapabilities?
    let onCommand: (DictationRowCommand) -> Void

    @StateObject private var interactionState: DictationRowInteractionState
    @StateObject private var copyFeedback = DictationRowCopyFeedback()

    init(
        presentation: DictationRowPresentation,
        moreCapabilities: DictationRowMoreCapabilities?,
        onCommand: @escaping (DictationRowCommand) -> Void
    ) {
        self.presentation = presentation
        self.moreCapabilities = moreCapabilities
        self.onCommand = onCommand
        _interactionState = StateObject(wrappedValue: DictationRowInteractionState(
            hasMore: moreCapabilities != nil
        ))
    }

    var body: some View {
        DictationRowContent(
            presentation: presentation,
            moreCapabilities: moreCapabilities,
            onCommand: onCommand,
            interactionState: interactionState,
            copyFeedback: copyFeedback
        )
    }
}

@MainActor
struct DictationRowContent: View {
    let presentation: DictationRowPresentation
    let moreCapabilities: DictationRowMoreCapabilities?
    let onCommand: (DictationRowCommand) -> Void

    @ObservedObject var interactionState: DictationRowInteractionState
    @ObservedObject var copyFeedback: DictationRowCopyFeedback
    @FocusState private var focusedTarget: DictationRowInteraction.FocusTarget?
    @State private var keyboardMonitor: Any?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actionsRevealed: Bool {
        DictationRowInteraction.actionsRevealed(
            isHovered: interactionState.isHovered,
            hasFocus: interactionState.hasVisibleFocusIndicator,
            isCopyConfirmed: copyFeedback.isConfirmed
        )
    }

    private var actionComposition: DictationRowActionComposition {
        DictationRowActionComposition.make(
            presentation: presentation,
            moreCapabilities: moreCapabilities
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(presentation.time)
                .font(Theme.timestamp)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 42, alignment: .leading)
            EmberIngress(color: Theme.accent)
                .frame(height: 22)
            Text(presentation.text)
                .font(Theme.ui(11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            trailingRegion
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(
            interactionState.isHovered
                ? Theme.hover
                : Theme.surface
        )
        .focusEffectDisabled()
        .emberInsetFocusRing(interactionState.focusedTarget == .row)
        .contentShape(Rectangle())
        .focusable(interactions: .activate)
        .focused($focusedTarget, equals: .row)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityDescription)
        .animation(
            Theme.ordinaryAnimation(reduceMotion: reduceMotion),
            value: actionsRevealed
        )
        .animation(
            Theme.ordinaryAnimation(reduceMotion: reduceMotion),
            value: interactionState.isHovered
        )
        .onHover { interactionState.setHovered($0) }
        .onChange(of: focusedTarget) { _, target in
            interactionState.setFocused(target)
        }
        .onChange(of: interactionState.focusedTarget) { _, target in
            focusedTarget = target
        }
        .onAppear {
            focusedTarget = interactionState.focusedTarget
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 48,
                      interactionState.hasVisibleFocusIndicator else { return event }
                return interactionState.handleTab(
                    isShiftPressed: event.modifierFlags.contains(.shift)
                ) ? nil : event
            }
        }
        .onDisappear {
            if let keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
            }
            keyboardMonitor = nil
            copyFeedback.cancel()
        }
    }

    private var trailingRegion: some View {
        ZStack(alignment: .trailing) {
            identity
                .opacity(actionsRevealed ? 0 : 1)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            actions
                .opacity(actionsRevealed ? 1 : 0)
                .allowsHitTesting(actionsRevealed)
        }
        .frame(width: 150, alignment: .trailing)
    }

    private var identity: some View {
        HStack(spacing: 5) {
            Image(systemName: presentation.polishStatusSymbolName)
                .font(Theme.ui(9, .semibold))
                .foregroundStyle(Theme.textTertiary)
                .help(presentation.polishStatus.label)
            Image(systemName: presentation.modeIcon)
                .font(Theme.ui(10, .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(presentation.compactModeName)
                .font(Theme.modeTag)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            if presentation.isDeletedMode {
                Text("deleted")
                    .font(Theme.ui(9, .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            if presentation.isFlagged {
                Image(systemName: "flag.fill")
                    .font(Theme.ui(11, .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .help(presentation.fullModeName)
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if actionComposition.directActions.contains(.copy) {
                copyButton
            }
            if actionComposition.directActions.contains(.flag) {
                flagButton
            }
            if actionComposition.directActions.contains(.more) {
                moreMenu(actionComposition.moreActions)
            }
        }
    }

    private var copyButton: some View {
        Button(action: copyDisplayedText) {
            Image(systemName: copyFeedback.isConfirmed ? "checkmark" : "doc.on.doc")
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(
                    copyFeedback.isConfirmed
                        ? AnyShapeStyle(Theme.success)
                        : AnyShapeStyle(Theme.textSecondary)
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .emberFocusRing(interactionState.focusedTarget == .copy)
        .focusable(interactions: .activate)
        .focused($focusedTarget, equals: .copy)
        .accessibilityLabel(DictationRowAccessibility.copyLabel)
        .accessibilityHint(DictationRowAccessibility.copyHint)
        .help(DictationRowAccessibility.copyLabel)
    }

    private var flagButton: some View {
        let label = DictationRowAccessibility.flagLabel(isFlagged: presentation.isFlagged)
        return Button {
            onCommand(.toggleFlag)
        } label: {
            Image(systemName: presentation.isFlagged ? "flag.fill" : "flag")
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(
                    presentation.isFlagged
                        ? AnyShapeStyle(Theme.accent)
                        : AnyShapeStyle(Theme.textSecondary)
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .emberFocusRing(interactionState.focusedTarget == .flag)
        .focusable(interactions: .activate)
        .focused($focusedTarget, equals: .flag)
        .accessibilityLabel(label)
        .accessibilityHint(
            DictationRowAccessibility.flagHint(isFlagged: presentation.isFlagged)
        )
        .help(label)
    }

    private func moreMenu(_ actions: [DictationRowActionComposition.MoreAction]) -> some View {
        Menu {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                moreMenuAction(action)
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .focusEffectDisabled()
        .emberFocusRing(interactionState.focusedTarget == .more)
        .focusable(interactions: .activate)
        .focused($focusedTarget, equals: .more)
        .accessibilityLabel(DictationRowAccessibility.moreLabel)
        .accessibilityHint(DictationRowAccessibility.moreHint)
        .help(DictationRowAccessibility.moreLabel)
    }

    @ViewBuilder
    private func moreMenuAction(_ action: DictationRowActionComposition.MoreAction) -> some View {
        switch action {
        case let .command(action):
            if action.isDestructive {
                Button(action.label, role: .destructive) {
                    perform(action.command)
                }
            } else {
                Button(action.label) {
                    perform(action.command)
                }
            }
        case let .submenu(label, commands):
            Menu(label) {
                ForEach(Array(commands.enumerated()), id: \.offset) { _, action in
                    Button(action.label) {
                        perform(action.command)
                    }
                }
            }
        case .separator:
            Divider()
        }
    }

    func perform(_ command: DictationRowCommand) {
        if command == .copyDisplayed {
            copyDisplayedText()
        } else {
            onCommand(command)
        }
    }

    private func copyDisplayedText() {
        onCommand(.copyDisplayed)
        copyFeedback.confirm {
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: DictationRowAccessibility.copiedAnnouncement,
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ]
            )
        }
    }
}
