// The sidebar presentation rule (PRD #103): what the sidebar renders for a
// given window width, and how an explicit toggle updates the persisted
// preference. Pure value logic, kept apart from the SwiftUI shell so the
// "auto-collapse is transient, explicit toggle wins and persists" contract is
// unit-tested without a window.

import Foundation

/// How the sidebar is rendered: the 190pt labeled list or the 52pt icon rail.
enum SidebarMode: Equatable {
    case expanded
    case rail
}

/// Value-typed sidebar state. `prefersCollapsed` is the user's persisted
/// intent (Config's `sidebar_collapsed`); auto-collapse under a narrow window
/// is a render-time override that never writes the preference.
struct SidebarPresentation: Equatable {
    /// Below this window width the expanded layout (190 sidebar + ≥560 main +
    /// 212 rail + padding) no longer fits, so the sidebar renders as the rail.
    /// The spec says "~880pt"; the assembled layout stops fitting near ~940.
    static let autoCollapseWidth: Double = 940

    private(set) var prefersCollapsed: Bool
    /// Armed when the user explicitly expands while the window is narrow, so
    /// the explicit choice beats auto-collapse; disarmed once the window is
    /// wide again (the preference alone decides from there).
    private(set) var expandsWhileNarrow = false

    /// What to render at `width`: narrow windows collapse to the rail unless
    /// the user explicitly expanded at this narrowness; wide windows follow
    /// the persisted preference.
    func mode(forWidth width: Double) -> SidebarMode {
        if width < Self.autoCollapseWidth {
            return expandsWhileNarrow ? .expanded : .rail
        }
        return prefersCollapsed ? .rail : .expanded
    }

    /// An explicit toggle (titlebar button or ⌘\) flips whatever is currently
    /// rendered and persists the result as the new intent — the one path that
    /// writes the preference.
    mutating func toggle(width: Double) {
        switch mode(forWidth: width) {
        case .expanded:
            prefersCollapsed = true
            expandsWhileNarrow = false
        case .rail:
            prefersCollapsed = false
            expandsWhileNarrow = width < Self.autoCollapseWidth
        }
    }

    /// Resizing only affects the transient override: growing past the
    /// threshold disarms it. The preference is never touched, so an
    /// auto-collapse can't silently overwrite the user's saved choice.
    mutating func widthChanged(to width: Double) {
        if width >= Self.autoCollapseWidth {
            expandsWhileNarrow = false
        }
    }
}
