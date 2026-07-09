// Performance lock for the History pane: opening it must stay O(visible rows),
// not O(all history). The pane once built every row eagerly (plain VStack /
// ForEach under paneScroll's ScrollView), so a 3000-entry history took ~5s to
// open and ~400ms to re-layout on every hover flip, keystroke, or unrelated
// SettingsModel publish; the fix made both the day-group list and each group's
// rows lazy, and gave rows row-local hover state. These tests host the pane
// exactly as SettingsView.paneScroll does and time the two costs a user feels:
// first layout ("open the tab") and one re-layout after a model publish. The
// thresholds carry >10x headroom over the lazy layout's measured times, and
// the dense-days case pins the shape group-level laziness alone would miss —
// thousands of entries packed into a few day-groups.

import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

final class HistoryPanePerfTests: XCTestCase {
    private static let entryCount = 3000
    private static let openBudget = 0.75
    private static let republishBudget = 0.25

    /// Deterministic entries: fixed seed vocabulary, sizes, and timestamps so
    /// every run measures the same tree. `minutesApart` shapes the day-groups:
    /// 37 spreads entries over ~77 days, 2 packs them into ~4 dense days.
    private static func entries(_ n: Int, minutesApart: Double) -> [HistoryEntry] {
        let vocab = [
            "meeting", "notes", "follow", "up", "with", "the", "team", "about",
            "the", "quarterly", "roadmap", "and", "ship", "dates", "please",
            "remember", "to", "send", "the", "summary", "email", "before",
            "friday", "afternoon", "thanks",
        ]
        let base = Date(timeIntervalSince1970: 1_783_000_000)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func rand(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        return (0 ..< n).map { i in
            let words = (0 ..< (10 + rand(50))).map { _ in vocab[rand(vocab.count)] }
            let text = words.joined(separator: " ")
            return HistoryEntry(
                id: UUID(),
                createdAt: base.addingTimeInterval(-Double(i) * minutesApart * 60),
                text: text,
                rawText: text + " uh",
                isPolished: i.isMultiple(of: 3),
                modeName: i.isMultiple(of: 3) ? "Clean" : "Voice to Text",
                wordCount: words.count,
                sourceApp: nil,
                durationMs: words.count * 400,
                flagged: i.isMultiple(of: 17),
                flagReason: nil
            )
        }
    }

    /// Hosts the pane the way SettingsView.paneScroll does — ScrollView, padded
    /// VStack, window-sized frame — and measures the initial layout plus one
    /// re-layout after an unrelated @Published mutation (the invalidation path
    /// every hover, keystroke, and status publish takes via @ObservedObject).
    @MainActor
    private func measure(minutesApart: Double) -> (open: Double, republish: Double) {
        let model = SettingsModel()
        model.historyEntries = Self.entries(Self.entryCount, minutesApart: minutesApart)

        let root = AnyView(
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HistoryPane(model: model)
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 900, height: 640)
        )
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        let window = NSWindow(
            contentRect: hosting.frame, styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        let clock = ContinuousClock()
        let open = clock.measure {
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
        }

        model.customModel = "poke"
        let republish = clock.measure {
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
        }
        window.contentView = nil
        return (open.inSeconds, republish.inSeconds)
    }

    @MainActor
    func testOpeningHistoryPaneWithManyEntriesSpreadOverManyDaysIsFast() {
        let m = measure(minutesApart: 37)
        XCTAssertLessThan(
            m.open, Self.openBudget,
            "opening History with \(Self.entryCount) entries must not build every row"
        )
        XCTAssertLessThan(
            m.republish, Self.republishBudget,
            "one model publish must re-layout only the visible rows"
        )
    }

    @MainActor
    func testOpeningHistoryPaneWithDenseDayGroupsIsFast() {
        let m = measure(minutesApart: 2)
        XCTAssertLessThan(
            m.open, Self.openBudget,
            "a day-group holding hundreds of rows must still lay out lazily"
        )
        XCTAssertLessThan(
            m.republish, Self.republishBudget,
            "one model publish must re-layout only the visible rows"
        )
    }
}

private extension Duration {
    var inSeconds: Double {
        let (s, atto) = components
        return Double(s) + Double(atto) * 1e-18
    }
}
