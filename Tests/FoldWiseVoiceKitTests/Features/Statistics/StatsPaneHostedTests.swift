import AppKit
import Observation
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class StatsPaneHostedTests: XCTestCase {
    private struct KeyInput {
        let code: UInt16
        let characters: String
    }

    private struct HostedAXNode {
        let identifier: String?
        let label: String?
        let value: String?
        let position: CGPoint?
    }

    func testHostedStatsExposesFourSemanticMetricTiles() throws {
        let (hosting, window) = hostFullSettings(width: 880, height: 640)
        defer { window.orderOut(nil) }

        let identifiers = try statsNodes(in: window)
            .compactMap(\.identifier)
            .filter { $0.hasPrefix("stats.metric.") }
            .sorted()
        _ = hosting

        XCTAssertEqual(identifiers, [
            "stats.metric.currentStreak",
            "stats.metric.speakingSpeed",
            "stats.metric.timeSaved",
            "stats.metric.wordsDictated",
        ])
    }

    func testHostedStatsReusesProjectionForUnrelatedSettingsPublication() {
        let calendar = utcCalendar()
        let store = PaneProjectionStore()
        let model = SettingsModel(
            panePerformance: PaneNavigationPerformance(),
            paneProjections: store
        )
        _ = store.stats(in: .init(
            now: Date(),
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ))
        let hosting = host(StatsPane(
            interface: model.statsPaneInterface,
            calendar: { calendar },
            locale: Locale(identifier: "en_US")
        ))
        let initialGeneration = store.completedStats?.generation

        model.customModel = "unrelated publication"
        render(hosting)

        XCTAssertEqual(store.completedStats?.generation, initialGeneration)
    }

    func testHostedStatsRefreshesProjectionWhenSavedHistoryChanges() throws {
        let model = SettingsModel()
        let (hosting, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        model.historyEntries = [entry(rawText: "saved words", day: 1)]
        waitUntilStatsCurrent(model)
        render(hosting)

        XCTAssertEqual(try node(identifier: "stats.calendar", in: window).value, "2 spoken words, 1 active day")
    }

    func testHostedStatsRefreshesProjectionWhenSavingStateChanges() throws {
        let model = SettingsModel()
        let (hosting, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        model.saveHistory = false
        waitUntilStatsCurrent(model)
        render(hosting)

        XCTAssertEqual(try noticeIdentifiers(in: window), ["stats.notice.savingOff"])
    }

    func testHostedStatsRefreshesProjectionForDayAndTimeZoneNotifications() {
        let notifications = NotificationCenter()
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        var currentCalendar = utcCalendar()
        let store = PaneProjectionStore()
        let model = SettingsModel(
            panePerformance: PaneNavigationPerformance(),
            paneProjections: store
        )
        _ = store.stats(in: .init(
            now: currentNow,
            calendar: currentCalendar,
            locale: Locale(identifier: "en_US")
        ))
        let hosting = host(StatsPane(
            interface: model.statsPaneInterface,
            now: { currentNow },
            calendar: { currentCalendar },
            locale: Locale(identifier: "en_US"),
            notificationCenter: notifications
        ))
        let initialGeneration = store.completedStats?.generation

        currentNow = currentNow.addingTimeInterval(86400)
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        waitUntilStatsCurrent(model, after: initialGeneration)
        render(hosting)
        let dayGeneration = store.completedStats?.generation
        currentCalendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? currentCalendar.timeZone
        notifications.post(name: .NSSystemTimeZoneDidChange, object: nil)
        waitUntilStatsCurrent(model, after: dayGeneration)
        render(hosting)

        XCTAssertEqual(
            [
                initialGeneration != dayGeneration,
                dayGeneration != store.completedStats?.generation,
            ],
            [true, true]
        )
    }

    func testHostedStatsRefreshesProjectionForLocaleEnvironmentChanges() {
        let calendar = utcCalendar()
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 12
        )) ?? .distantPast
        let store = PaneProjectionStore()
        let model = SettingsModel(
            panePerformance: PaneNavigationPerformance(),
            paneProjections: store
        )
        let pane = StatsPane(
            interface: model.statsPaneInterface,
            now: { now },
            calendar: { calendar }
        )
        _ = store.stats(in: .init(
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ))
        let hosting = host(pane.environment(\.locale, Locale(identifier: "en_US")))
        render(hosting)
        let english = store.completedStats

        hosting.rootView = pane.environment(\.locale, Locale(identifier: "pl_PL"))
        render(hosting)
        waitUntilStatsCurrent(model, after: english?.generation)
        render(hosting)
        let polish = store.completedStats

        XCTAssertEqual(
            [english?.value.month.title, polish?.value.month.title],
            ["July 2026", "lipiec 2026"]
        )
    }

    func testHostedMetricTilesRemainOneRowAtRequiredWindowSizes() throws {
        let rows = try [(880.0, 640.0), (980.0, 720.0)].map { width, height in
            let (_, window) = hostFullSettings(width: width, height: height)
            defer { window.orderOut(nil) }
            let metrics = try statsNodes(in: window).filter {
                $0.identifier?.hasPrefix("stats.metric.") == true
            }
            return Set(metrics.compactMap { $0.position.map { Int($0.y.rounded()) } }).count
        }

        XCTAssertEqual(rows, [1, 1])
    }

    func testHostedCalendarRemainsSevenColumnsAtRequiredWindowSizes() throws {
        let columnCounts = try [(880.0, 640.0), (980.0, 720.0)].map { width, height in
            let (_, window) = hostFullSettings(width: width, height: height)
            defer { window.orderOut(nil) }
            let days = try statsNodes(in: window).filter {
                $0.identifier?.hasPrefix("stats.day.") == true
            }
            return Set(days.compactMap { $0.position.map { Int($0.x.rounded()) } }).count
        }

        XCTAssertEqual(columnCounts, [7, 7])
    }

    func testHostedStatsKeepsCompactMetricRowAcrossEveryDataState() throws {
        let rowCounts = try dataStateModels().map { model in
            let (_, window) = hostFullSettings(width: 880, height: 640, model: model)
            defer { window.orderOut(nil) }
            let nodes = try statsNodes(in: window)
            return Set(nodes.compactMap { node -> Int? in
                guard node.identifier?.hasPrefix("stats.metric.") == true else { return nil }
                return node.position.map { Int($0.y.rounded()) }
            }).count
        }

        XCTAssertEqual(rowCounts, Array(repeating: 1, count: 4))
    }

    func testHostedStatsKeepsSevenCalendarColumnsAcrossEveryDataState() throws {
        let columnCounts = try dataStateModels().map { model in
            let (_, window) = hostFullSettings(width: 880, height: 640, model: model)
            defer { window.orderOut(nil) }
            let nodes = try statsNodes(in: window)
            return Set(nodes.compactMap { node -> Int? in
                guard node.identifier?.hasPrefix("stats.day.") == true else { return nil }
                return node.position.map { Int($0.x.rounded()) }
            }).count
        }

        XCTAssertEqual(columnCounts, Array(repeating: 7, count: 4))
    }

    func testHostedIncreaseContrastRendersStrongerCalendarBoundaries() throws {
        let standard = host(fixedStatsPane(
            model: SettingsModel(),
            environment: StatsEnvironmentAdaptations(
                reduceMotion: false,
                increaseContrast: false
            )
        ).environment(\.colorScheme, .light))
        let increased = host(fixedStatsPane(
            model: SettingsModel(),
            environment: StatsEnvironmentAdaptations(
                reduceMotion: false,
                increaseContrast: true
            )
        ).environment(\.colorScheme, .light))
        render(standard)
        render(increased)

        XCTAssertGreaterThan(
            try renderedTokenCount(Theme.borderStrong, in: increased),
            try renderedTokenCount(Theme.borderStrong, in: standard)
        )
    }

    func testHostedReduceMotionCommitsActivityCueOnTheNextRender() throws {
        let model = SettingsModel()
        let hosting = host(fixedStatsPane(
            model: model,
            environment: StatsEnvironmentAdaptations(
                reduceMotion: true,
                increaseContrast: false
            )
        ).environment(\.colorScheme, .light))
        render(hosting)
        let initialAccentCount = try renderedTokenCount(Theme.accent, in: hosting)

        model.historyEntries = [entry(rawText: "two words", day: 1)]
        waitUntilStatsCurrent(model)
        render(hosting)

        XCTAssertGreaterThan(
            try renderedTokenCount(Theme.accent, in: hosting),
            initialAccentCount
        )
    }

    func testHostedCalendarHoverUpdatesTheRenderedDay() throws {
        let (hosting, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        window.appearance = NSAppearance(named: .aqua)
        render(hosting)
        let grid = try XCTUnwrap(calendarGrid(in: hosting))
        let dayFrame = calendarDayFrame(at: 0, in: grid)
        let samplePoint = CGPoint(x: dayFrame.midX, y: dayFrame.midY)
        let initialColor = try renderedColor(at: samplePoint, in: grid)

        moveMouse(
            to: samplePoint,
            in: grid,
            window: window
        )
        render(hosting)
        let hoveredColor = try waitForRenderedColorChange(
            at: samplePoint,
            in: grid,
            from: initialColor
        )

        XCTAssertGreaterThan(
            colorDistance(initialColor, hoveredColor),
            0.1
        )
    }

    func testHostedCalendarHoverIsImmediateWithReducedMotion() throws {
        let hosting = host(fixedStatsPane(
            model: SettingsModel(),
            environment: StatsEnvironmentAdaptations(
                reduceMotion: true,
                increaseContrast: false
            )
        ))
        let window = hostInWindow(hosting)
        render(hosting)
        defer { window.orderOut(nil) }
        let grid = try XCTUnwrap(calendarGrid(in: hosting))
        let dayFrame = calendarDayFrame(at: 0, in: grid)
        let samplePoint = CGPoint(x: dayFrame.midX, y: dayFrame.midY)
        let initialColor = try renderedColor(at: samplePoint, in: grid)
        moveMouse(to: CGPoint(x: -10, y: -10), in: grid, window: window)

        moveMouse(
            to: samplePoint,
            in: grid,
            window: window
        )
        render(hosting)

        XCTAssertGreaterThan(
            colorDistance(initialColor, try renderedColor(at: samplePoint, in: grid)),
            0.1
        )
    }

    func testHostedCalendarFollowsWindowAppearance() throws {
        let (lightHosting, lightWindow) = hostInteractiveStats(model: SettingsModel())
        defer { lightWindow.orderOut(nil) }
        lightWindow.appearance = NSAppearance(named: .aqua)
        render(lightHosting)
        let lightGrid = try XCTUnwrap(calendarGrid(in: lightHosting))
        let lightDay = calendarDayFrame(at: 0, in: lightGrid)
        let lightColor = try renderedColor(
            at: CGPoint(x: lightDay.midX, y: lightDay.midY),
            in: lightGrid
        )

        let (darkHosting, darkWindow) = hostInteractiveStats(model: SettingsModel())
        defer { darkWindow.orderOut(nil) }
        darkWindow.appearance = NSAppearance(named: .darkAqua)
        render(darkHosting)
        let darkGrid = try XCTUnwrap(calendarGrid(in: darkHosting))
        let darkDay = calendarDayFrame(at: 0, in: darkGrid)
        let darkColor = try renderedColor(
            at: CGPoint(x: darkDay.midX, y: darkDay.midY),
            in: darkGrid
        )

        XCTAssertGreaterThan(colorDistance(lightColor, darkColor), 1)
    }

    func testHostedCalendarAppliesContextOnce() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        let labels = try statsNodes(in: window).compactMap(\.label)

        XCTAssertEqual(labels.filter { $0 == "July 2026 activity calendar" }.count, 1)
    }

    func testHostedCalendarAppliesSummaryOnce() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        let values = try statsNodes(in: window).compactMap(\.value)

        XCTAssertEqual(values.filter { $0 == "0 spoken words, 0 active days" }.count, 1)
    }

    func testHostedCalendarAppliesContextLabel() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.calendar", in: window).label, "July 2026 activity calendar")
    }

    func testHostedCalendarAppliesSummaryValue() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.calendar", in: window).value, "0 spoken words, 0 active days")
    }

    func testHostedCalendarAppliesActiveElapsedDayLabel() throws {
        let model = SettingsModel()
        model.historyEntries = [entry(rawText: "two words", day: 1)]
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.day.1", in: window).label, "Wednesday, July 1, 2026")
    }

    func testHostedCalendarAppliesActiveElapsedDayValue() throws {
        let model = SettingsModel()
        model.historyEntries = [entry(rawText: "two words", day: 1)]
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            try node(identifier: "stats.day.1", in: window).value,
            "2 spoken words across 1 saved session. Timing unavailable"
        )
    }

    func testHostedCalendarAppliesEmptyElapsedDayLabel() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.day.2", in: window).label, "Thursday, July 2, 2026")
    }

    func testHostedCalendarAppliesEmptyElapsedDayValue() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        XCTAssertEqual(
            try node(identifier: "stats.day.2", in: window).value,
            "No dictated words. No saved Dictation sessions"
        )
    }

    func testHostedCalendarExcludesFutureDaysFromAccessibilityTree() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        let dayNumbers = try statsNodes(in: window)
            .compactMap(\.identifier)
            .filter { $0.hasPrefix("stats.day.") }
            .compactMap { Int($0.replacingOccurrences(of: "stats.day.", with: "")) }
            .sorted()

        XCTAssertEqual(dayNumbers, Array(1 ... 22))
    }

    func testHostedCalendarExcludesHiddenRegionsFromAccessibilityTree() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        let hiddenPrefixes = ["stats.weekday.", "stats.spacer.", "stats.decoration.", "stats.duplicate."]
        let exposedHiddenRegions = try statsNodes(in: window)
            .compactMap(\.identifier)
            .filter { identifier in hiddenPrefixes.contains { identifier.hasPrefix($0) } }

        XCTAssertTrue(exposedHiddenRegions.isEmpty)
    }

    func testHostedStatsRendersRetainedActivityState() throws {
        let model = SettingsModel()
        model.historyEntries = [entry(rawText: "saved words", day: 1)]
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertNil(try statsNodes(in: window).first { $0.identifier?.hasPrefix("stats.notice.") == true })
    }

    func testHostedStatsRendersRetainedActivityInCalendar() throws {
        let model = SettingsModel()
        model.historyEntries = [entry(rawText: "saved words", day: 1)]
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.calendar", in: window).value, "2 spoken words, 1 active day")
    }

    func testHostedStatsRendersEmptyHistoryState() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        XCTAssertEqual(try noticeIdentifiers(in: window), ["stats.notice.noHistory"])
    }

    func testHostedStatsRendersSavingOffRetainedState() throws {
        let model = SettingsModel()
        model.historyEntries = [entry(rawText: "saved words", day: 1)]
        model.saveHistory = false
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try noticeIdentifiers(in: window), ["stats.notice.savingOff"])
    }

    func testHostedStatsKeepsRetainedCalendarActivityWhenSavingIsOff() throws {
        let model = SettingsModel()
        model.historyEntries = [entry(rawText: "saved words", day: 1)]
        model.saveHistory = false
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.calendar", in: window).value, "2 spoken words, 1 active day")
    }

    func testHostedStatsRendersSavingOffEmptyState() throws {
        let model = SettingsModel()
        model.saveHistory = false
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try noticeIdentifiers(in: window), ["stats.notice.savingOff"])
    }

    func testHostedStatsKeepsEmptyCalendarWhenSavingIsOff() throws {
        let model = SettingsModel()
        model.saveHistory = false
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }

        XCTAssertEqual(try node(identifier: "stats.calendar", in: window).value, "0 spoken words, 0 active days")
    }

    func testHostedCalendarEntersOnTodayAsTheOnlyFocusedDay() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        sendKeys([tab], to: window)

        XCTAssertEqual(try focusedDayIdentifier(in: window), "stats.day.22")
    }

    func testHostedCalendarUsesTodayAsItsOnlyDayTabStop() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        var focusedDays = Set<String>()

        for _ in 0 ..< 3 {
            sendKeys([tab], to: window)
            if let identifier = try focusedDayIdentifier(in: window) {
                focusedDays.insert(identifier)
            }
        }

        XCTAssertEqual(focusedDays, ["stats.day.22"])
    }

    func testHostedCalendarRoutesNativeArrowKeysThroughRenderedDays() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }
        var focusedDays: [String] = []

        for key in [tab, left, up, right, down] {
            sendKeys([key], to: window)
            focusedDays.append(try XCTUnwrap(focusedDayIdentifier(in: window)))
        }

        XCTAssertEqual(focusedDays, [
            "stats.day.22", "stats.day.21", "stats.day.14", "stats.day.15", "stats.day.22",
        ])
    }

    func testHostedCalendarStopsNativeArrowKeysAtToday() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        sendKeys([tab, right, down], to: window)

        XCTAssertEqual(try focusedDayIdentifier(in: window), "stats.day.22")
    }

    func testHostedCalendarStopsNativeArrowKeysAtFirstDay() throws {
        let (_, window) = hostInteractiveStats(model: SettingsModel())
        defer { window.orderOut(nil) }

        for key in [tab, up, up, up, left, up] {
            sendKeys([key], to: window)
        }

        XCTAssertEqual(try focusedDayIdentifier(in: window), "stats.day.1")
    }

    func testHostedCalendarKeepsReturnInert() throws {
        let model = SettingsModel()
        model.pane = .stats
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }
        sendKeys([tab, returnKey], to: window)

        XCTAssertEqual(try focusedDayIdentifier(in: window), "stats.day.22")
    }

    func testHostedCalendarKeepsSpaceInert() throws {
        let model = SettingsModel()
        model.pane = .stats
        let (_, window) = hostInteractiveStats(model: model)
        defer { window.orderOut(nil) }
        sendKeys([tab, space], to: window)

        XCTAssertEqual(try focusedDayIdentifier(in: window), "stats.day.22")
    }

    func testHostedCalendarRepairsInvalidFocusToTodayAfterMonthChange() throws {
        let model = SettingsModel()
        let notifications = NotificationCenter()
        let calendar = utcCalendar()
        var currentNow = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 12
        )) ?? .distantPast
        let pane = StatsPane(
            interface: model.statsPaneInterface,
            now: { currentNow },
            calendar: { calendar },
            locale: Locale(identifier: "en_US"),
            notificationCenter: notifications
        )
        _ = model.paneProjections.stats(in: .init(
            now: currentNow,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ))
        let hosting = host(pane)
        let window = hostInWindow(hosting)
        defer { window.orderOut(nil) }
        sendKeys([tab], to: window)

        currentNow = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 1, hour: 12
        )) ?? .distantPast
        let julyGeneration = model.paneProjections.completedStats?.generation
        notifications.post(name: .NSCalendarDayChanged, object: nil)
        waitUntilStatsCurrent(model, after: julyGeneration)
        render(hosting)

        XCTAssertEqual(try focusedDayIdentifier(in: window), "stats.day.1")
    }

    func testSavingOffActionOpensHistory() throws {
        let model = SettingsModel()
        model.saveHistory = false
        model.pane = .stats
        _ = model.paneProjections.stats(in: .init(
            now: Date(),
            calendar: .autoupdatingCurrent,
            locale: .autoupdatingCurrent
        ))
        let hosting = host(StatsPane(interface: model.statsPaneInterface))

        let button = try XCTUnwrap(Self.button(named: "Open History", in: hosting))
        button.performClick(nil)

        XCTAssertEqual(model.pane, .history)
    }

    func testHostedHistoryButtonRefreshesAccessibilityLabelWhenTitleChanges() throws {
        let hosting = host(StatsHistoryButton(title: "Open History", action: {}))
        let initialButton = try XCTUnwrap(Self.button(named: "Open History", in: hosting))
        XCTAssertEqual(initialButton.accessibilityLabel(), "Open History")

        hosting.rootView = StatsHistoryButton(title: "View History", action: {})
        render(hosting)

        let updatedButton = try XCTUnwrap(Self.button(named: "View History", in: hosting))
        XCTAssertEqual(updatedButton.accessibilityLabel(), "View History")
    }

    private static func button(named title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap { button(named: title, in: $0) }.first
    }

    private func calendarGrid(in view: NSView) -> StatsCalendarGridNSView? {
        if let grid = view as? StatsCalendarGridNSView {
            return grid
        }
        return view.subviews.lazy.compactMap(calendarGrid).first
    }

    private func calendarDayFrame(
        at index: Int,
        in grid: StatsCalendarGridNSView
    ) -> CGRect {
        StatsCalendarLayout(
            width: grid.bounds.width,
            leadingColumnOffset: 3,
            dayCount: 31
        ).dayFrame(at: index)
    }

    private func moveMouse(
        to point: CGPoint,
        in grid: StatsCalendarGridNSView,
        window: NSWindow
    ) {
        guard let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: grid.convert(point, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ) else {
            XCTFail("Expected a mouse-moved event")
            return
        }
        grid.mouseMoved(with: event)
    }

    private func host<Content: View>(
        _ content: Content,
        width: CGFloat = 755,
        height: CGFloat = 900
    ) -> NSHostingView<Content> {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func fixedStatsPane(
        model: SettingsModel,
        environment: StatsEnvironmentAdaptations? = nil
    ) -> StatsPane {
        let calendar = utcCalendar()
        let now = calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 22, hour: 12
        )) ?? .distantPast
        _ = model.paneProjections.stats(in: .init(
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        ))
        return StatsPane(
            interface: model.statsPaneInterface,
            now: { now },
            calendar: { calendar },
            locale: Locale(identifier: "en_US"),
            environmentOverride: environment
        )
    }

    private func hostInteractiveStats(
        model: SettingsModel
    ) -> (NSHostingView<StatsPane>, NSWindow) {
        let hosting = host(fixedStatsPane(model: model))
        let window = hostInWindow(hosting)
        render(hosting)
        return (hosting, window)
    }

    private func hostFullSettings(
        width: CGFloat,
        height: CGFloat,
        model: SettingsModel? = nil
    ) -> (NSHostingView<SettingsView>, NSWindow) {
        let model = model ?? SettingsModel()
        model.pane = .stats
        _ = model.paneProjections.stats(in: .init(
            now: Date(),
            calendar: .autoupdatingCurrent,
            locale: .autoupdatingCurrent
        ))
        let hosting = host(SettingsView(model: model), width: width, height: height)
        let window = hostInWindow(hosting)
        render(hosting)
        return (hosting, window)
    }

    private func waitUntilStatsCurrent(
        _ model: SettingsModel,
        after generation: PaneProjectionStore.Generation? = nil
    ) {
        let isReady: @MainActor () -> Bool = {
            model.paneProjections.statsProjection.isCurrent
                && (generation == nil
                    || model.paneProjections.completedStats?.generation != generation)
        }
        guard !isReady() else { return }
        let published = expectation(description: "Stats projection published")
        func observeUntilReady() {
            guard !isReady() else {
                published.fulfill()
                return
            }
            withObservationTracking {
                _ = isReady()
            } onChange: {
                Task { @MainActor in
                    observeUntilReady()
                }
            }
        }
        observeUntilReady()
        wait(for: [published], timeout: 1)
    }

    private func dataStateModels() -> [SettingsModel] {
        let retained = SettingsModel()
        retained.historyEntries = [entry(rawText: "saved words", day: 1)]

        let empty = SettingsModel()

        let savingOffRetained = SettingsModel()
        savingOffRetained.historyEntries = [entry(rawText: "saved words", day: 1)]
        savingOffRetained.saveHistory = false

        let savingOffEmpty = SettingsModel()
        savingOffEmpty.saveHistory = false

        return [retained, empty, savingOffRetained, savingOffEmpty]
    }

    private func entry(rawText: String, day: Int) -> HistoryEntry {
        let createdAt = utcCalendar().date(from: DateComponents(
            year: 2026, month: 7, day: day, hour: 8
        )) ?? .distantPast
        return HistoryEntry(
            id: UUID(),
            createdAt: createdAt,
            text: rawText,
            rawText: rawText,
            isPolished: false,
            modeName: "Clean",
            wordCount: nil,
            sourceApp: nil,
            durationMs: nil,
            flagged: false,
            flagReason: nil
        )
    }

    private func hostInWindow(_ hosting: NSView) -> NSWindow {
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Stats hosted test \(UUID().uuidString)"
        window.contentView = hosting
        NSApp.finishLaunching()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(hosting)
        hosting.layoutSubtreeIfNeeded()
        return window
    }

    private func render(_ hosting: NSView) {
        let rendered = expectation(description: "Stats rendered")
        DispatchQueue.main.async { rendered.fulfill() }
        wait(for: [rendered], timeout: 1)
        hosting.layoutSubtreeIfNeeded()
    }

    private func renderedTokenCount(
        _ token: Color,
        in hosting: NSView
    ) throws -> Int {
        hosting.needsDisplay = true
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        )
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let target = try renderedTokenColor(token)
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { continue }
                let distance = abs(pixel.redComponent - target.redComponent)
                    + abs(pixel.greenComponent - target.greenComponent)
                    + abs(pixel.blueComponent - target.blueComponent)
                if distance < 0.05 {
                    count += 1
                }
            }
        }
        return count
    }

    private func renderedTokenColor(_ color: Color) throws -> NSColor {
        let hosting = host(
            color
                .environment(\.colorScheme, .light),
            width: 2,
            height: 2
        )
        let bitmap = try XCTUnwrap(
            hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)
        )
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return try XCTUnwrap(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?
                .usingColorSpace(.sRGB)
        )
    }

    private func renderedColor(
        at point: CGPoint,
        in view: NSView
    ) throws -> NSColor {
        view.needsDisplay = true
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(
            view.bitmapImageRepForCachingDisplay(in: view.bounds)
        )
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let xScale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let yScale = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        return try XCTUnwrap(
            bitmap.colorAt(
                x: Int((point.x * xScale).rounded(.down)),
                y: Int((point.y * yScale).rounded(.down))
            )?.usingColorSpace(.sRGB)
        )
    }

    private func waitForRenderedColorChange(
        at point: CGPoint,
        in view: NSView,
        from initialColor: NSColor
    ) throws -> NSColor {
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            let color = try renderedColor(at: point, in: view)
            if colorDistance(initialColor, color) > 0.1 {
                return color
            }
            _ = RunLoop.current.run(
                mode: .default,
                before: min(deadline, Date().addingTimeInterval(0.01))
            )
        }
        XCTFail("Rendered calendar color did not change")
        return initialColor
    }

    private func colorDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        abs(lhs.redComponent - rhs.redComponent)
            + abs(lhs.greenComponent - rhs.greenComponent)
            + abs(lhs.blueComponent - rhs.blueComponent)
    }

    private func sendKeys(_ keys: [KeyInput], to window: NSWindow) {
        DispatchQueue.main.async {
            for key in keys {
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: key.characters,
                    charactersIgnoringModifiers: key.characters,
                    isARepeat: false,
                    keyCode: key.code
                ) else { continue }
                NSApp.sendEvent(event)
            }
            NSApp.abortModal()
        }
        runModalBounded(window)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func statsNodes(in window: NSWindow) throws -> [HostedAXNode] {
        let application = AXUIElementCreateApplication(getpid())
        let windows = axElements(attribute: kAXWindowsAttribute, from: application)
        let hostedWindow = try XCTUnwrap(windows.first {
            axString(attribute: kAXTitleAttribute, from: $0) == window.title
        })
        return axTree(root: hostedWindow)
    }

    private func node(identifier: String, in window: NSWindow) throws -> HostedAXNode {
        try XCTUnwrap(statsNodes(in: window).first { $0.identifier == identifier })
    }

    private func noticeIdentifiers(in window: NSWindow) throws -> [String] {
        try statsNodes(in: window)
            .compactMap(\.identifier)
            .filter { $0.hasPrefix("stats.notice.") }
    }

    private func focusedDayIdentifier(in window: NSWindow) throws -> String? {
        _ = try statsNodes(in: window)
        let application = AXUIElementCreateApplication(getpid())
        var current = axElement(attribute: kAXFocusedUIElementAttribute, from: application)
        while let element = current {
            if let identifier = axString(attribute: kAXIdentifierAttribute, from: element),
               identifier.hasPrefix("stats.day.") {
                return identifier
            }
            current = axElement(attribute: kAXParentAttribute, from: element)
        }
        return nil
    }

    private func axTree(root: AXUIElement) -> [HostedAXNode] {
        let node = HostedAXNode(
            identifier: axString(attribute: kAXIdentifierAttribute, from: root),
            label: axString(attribute: kAXDescriptionAttribute, from: root)
                ?? axString(attribute: kAXTitleAttribute, from: root),
            value: axString(attribute: kAXValueDescriptionAttribute, from: root),
            position: axPoint(attribute: kAXPositionAttribute, from: root)
        )
        return [node] + axElements(attribute: kAXChildrenAttribute, from: root).flatMap(axTree)
    }

    private func axElements(attribute: String, from element: AXUIElement) -> [AXUIElement] {
        axAttribute(attribute: attribute, from: element) as? [AXUIElement] ?? []
    }

    private func axElement(attribute: String, from element: AXUIElement) -> AXUIElement? {
        guard let value = axAttribute(attribute: attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // The Core Foundation type-ID check makes this conversion an API invariant.
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func axString(attribute: String, from element: AXUIElement) -> String? {
        axAttribute(attribute: attribute, from: element) as? String
    }

    private func axPoint(attribute: String, from element: AXUIElement) -> CGPoint? {
        guard let value = axAttribute(attribute: attribute, from: element),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // The Core Foundation type-ID check makes this conversion an API invariant.
        let axValue = unsafeBitCast(value, to: AXValue.self)
        guard
            AXValueGetType(axValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func axAttribute(attribute: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private var tab: KeyInput {
        KeyInput(code: 48, characters: "\t")
    }

    private var returnKey: KeyInput {
        KeyInput(code: 36, characters: "\r")
    }

    private var space: KeyInput {
        KeyInput(code: 49, characters: " ")
    }

    private var left: KeyInput {
        KeyInput(code: 123, characters: "\u{F702}")
    }

    private var right: KeyInput {
        KeyInput(code: 124, characters: "\u{F703}")
    }

    private var down: KeyInput {
        KeyInput(code: 125, characters: "\u{F701}")
    }

    private var up: KeyInput {
        KeyInput(code: 126, characters: "\u{F700}")
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}
