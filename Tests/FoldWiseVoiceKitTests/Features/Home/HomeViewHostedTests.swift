import AppKit
import SwiftUI
import XCTest
@testable import FoldWiseVoiceKit

@MainActor
final class HomeViewHostedTests: XCTestCase {
    func testHostedHomeRefreshesRelativeHeadersWhenTheCalendarDayChanges() throws {
        let calendar = try utcCalendar()
        var currentNow = Date(timeIntervalSince1970: 1_783_512_000)
        let model = SettingsModel()
        model.historyEntries = [entry(createdAt: currentNow.addingTimeInterval(-60 * 60))]
        let notificationCenter = NotificationCenter()
        var projectedHeaders: [[String]] = []
        let hosting = NSHostingView(rootView: HomeView(
            model: model,
            now: { currentNow },
            calendar: calendar,
            locale: Locale(identifier: "en_US"),
            notificationCenter: notificationCenter,
            project: { input, now, calendar, locale in
                let projection = HomeProjection.project(
                    input,
                    now: now,
                    calendar: calendar,
                    locale: locale
                )
                projectedHeaders.append(projection.sections.map(\.header))
                return projection
            }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        hosting.layoutSubtreeIfNeeded()

        currentNow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: currentNow))
        notificationCenter.post(name: .NSCalendarDayChanged, object: nil)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(projectedHeaders, [["Today"], ["Yesterday"]])
    }

    private func entry(createdAt: Date) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            createdAt: createdAt,
            text: "Displayed words",
            rawText: "raw words",
            isPolished: true,
            modeName: "Clean",
            wordCount: 2,
            sourceApp: nil,
            durationMs: nil,
            flagged: false,
            flagReason: nil
        )
    }

    private func utcCalendar() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}
