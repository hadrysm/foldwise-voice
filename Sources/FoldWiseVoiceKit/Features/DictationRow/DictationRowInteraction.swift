import Combine
import Foundation

enum DictationRowInteraction {
    enum FocusTarget: Hashable {
        case row
        case copy
        case flag
        case more
    }

    static func actionsRevealed(
        isHovered: Bool,
        hasFocus: Bool,
        isCopyConfirmed: Bool
    ) -> Bool {
        isHovered || hasFocus || isCopyConfirmed
    }
}

@MainActor
final class DictationRowInteractionState: ObservableObject {
    @Published private(set) var isHovered = false
    @Published private(set) var focusedTarget: DictationRowInteraction.FocusTarget?
    private let hasMore: Bool

    init(hasMore: Bool) {
        self.hasMore = hasMore
    }

    var hasVisibleFocusIndicator: Bool {
        focusedTarget != nil
    }

    func setHovered(_ hovered: Bool) {
        isHovered = hovered
    }

    func setFocused(_ target: DictationRowInteraction.FocusTarget?) {
        focusedTarget = target
    }

    func handleTab(isShiftPressed: Bool) -> Bool {
        if isShiftPressed {
            moveFocusBackward()
        } else {
            moveFocusForward()
        }
    }

    private func moveFocusForward() -> Bool {
        switch focusedTarget {
        case nil, .row:
            focusedTarget = .copy
        case .copy:
            focusedTarget = .flag
        case .flag where hasMore:
            focusedTarget = .more
        case .flag, .more:
            return false
        }
        return true
    }

    private func moveFocusBackward() -> Bool {
        switch focusedTarget {
        case .more where hasMore:
            focusedTarget = .flag
        case .more:
            return false
        case .flag:
            focusedTarget = .copy
        case .copy:
            focusedTarget = .row
        case nil, .row:
            return false
        }
        return true
    }
}

/// Row-local copy confirmation. Scheduling is injected so reset and
/// cancellation behavior are deterministic without sleeping in tests.
@MainActor
final class DictationRowCopyFeedback: ObservableObject {
    typealias Cancel = @MainActor () -> Void
    typealias ScheduleReset = @MainActor (@escaping @MainActor () -> Void) -> Cancel

    @Published private(set) var isConfirmed = false
    private let scheduleReset: ScheduleReset
    private var cancelReset: Cancel?

    init(scheduleReset: @escaping ScheduleReset = DictationRowCopyFeedback.scheduleLiveReset) {
        self.scheduleReset = scheduleReset
    }

    func confirm(announce: () -> Void) {
        cancelReset?()
        isConfirmed = true
        announce()
        cancelReset = scheduleReset { [weak self] in
            self?.isConfirmed = false
        }
    }

    func cancel() {
        cancelReset?()
        cancelReset = nil
        isConfirmed = false
    }

    private static func scheduleLiveReset(
        _ reset: @escaping @MainActor () -> Void
    ) -> Cancel {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            reset()
        }
        return { task.cancel() }
    }
}

enum DictationRowAccessibility {
    static let copyLabel = "Copy text"
    static let copyHint = "Copies the displayed dictation text."
    static let moreLabel = "More actions"
    static let moreHint = "Shows additional actions for this dictation."
    static let copiedAnnouncement = "Copied"

    static func flagLabel(isFlagged: Bool) -> String {
        isFlagged ? "Remove flag" : "Flag for my review"
    }

    static func flagHint(isFlagged: Bool) -> String {
        isFlagged
            ? "Removes this dictation from your flagged items."
            : "Flags this dictation for later review."
    }
}
