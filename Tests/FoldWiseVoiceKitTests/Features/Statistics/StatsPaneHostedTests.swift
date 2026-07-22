import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class StatsPaneHostedTests: XCTestCase {
    func testHostedStatsReusesProjectionForUnrelatedSettingsPublication() {
        let model = SettingsModel()
        var executionCount = 0
        let calendar = utcCalendar()
        let cache = StatsProjectionCache(project: { input, now, calendar, locale in
            executionCount += 1
            return StatsProjection.project(input, now: now, calendar: calendar, locale: locale)
        })
        let hosting = host(
            StatsPane(
                model: model,
                projectionCache: cache,
                calendar: { calendar },
                locale: Locale(identifier: "en_US")
            )
        )
        let initialExecutions = executionCount

        model.customModel = "unrelated publication"
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual([initialExecutions, executionCount], [1, 1])
    }

    func testHostedStatsRefreshesProjectionForDayAndTimeZoneNotifications() {
        let model = SettingsModel()
        let notifications = NotificationCenter()
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        var currentCalendar = utcCalendar()
        var executionCount = 0
        let cache = StatsProjectionCache(now: { currentNow }, project: { input, now, calendar, locale in
            executionCount += 1
            return StatsProjection.project(input, now: now, calendar: calendar, locale: locale)
        })
        let hosting = host(
            StatsPane(
                model: model,
                projectionCache: cache,
                calendar: { currentCalendar },
                locale: Locale(identifier: "en_US"),
                notificationCenter: notifications
            )
        )

        currentNow = currentNow.addingTimeInterval(86400)
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        currentCalendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? currentCalendar.timeZone
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(executionCount, 3)
    }

    func testHostedStatsFitsCompactAndWideContentWithoutHorizontalExpansion() {
        let model = SettingsModel()
        let compact = host(StatsPane(model: model), width: 755)
        let wide = host(StatsPane(model: model), width: 717)

        XCTAssertEqual(
            [compact.fittingSize.width <= 755, wide.fittingSize.width <= 717],
            [true, true]
        )
    }

    func testSavingOffActionOpensHistory() throws {
        let model = SettingsModel()
        model.saveHistory = false
        model.pane = .stats
        let hosting = host(StatsPane(model: model))

        let button = try XCTUnwrap(Self.button(named: "Open History", in: hosting))
        button.performClick(nil)

        XCTAssertEqual(model.pane, .history)
    }

    private static func button(named title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap { button(named: title, in: $0) }.first
    }

    private func host<Content: View>(
        _ content: Content,
        width: CGFloat = 755
    ) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
