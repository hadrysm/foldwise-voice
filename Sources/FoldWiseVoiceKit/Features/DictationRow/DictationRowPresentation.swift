import AppKit
import Foundation

/// Immutable identity for one saved Dictation session wherever it is rendered.
/// Collection projections retain the exact source entry separately so this
/// value never becomes an action or persistence model.
struct DictationRowPresentation: Equatable {
    static let maxCompactModeLength = 16
    private static let formatterLock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    let time: String
    let text: String
    let fullModeName: String
    let compactModeName: String
    let modeIcon: String
    let isDeletedMode: Bool
    let polishStatus: PolishStatus
    let isFlagged: Bool
    let accessibilityDescription: String

    init(
        entry: HistoryEntry,
        modes: [Mode] = [],
        calendar: Calendar = .current
    ) {
        let time = Self.time(entry.createdAt, calendar: calendar)
        let text = Self.singleLine(entry.text)
        let status = PolishStatus(entry)
        let flaggedDescription = entry.flagged ? "Flagged" : "Not flagged"
        let attribution = Self.attribution(for: entry, modes: modes)

        self.time = time
        self.text = text
        fullModeName = attribution.name
        compactModeName = String(
            attribution.name.lowercased().prefix(Self.maxCompactModeLength)
        )
        modeIcon = attribution.icon
        isDeletedMode = attribution.isDeleted
        polishStatus = status
        isFlagged = entry.flagged
        var accessibilityParts = [
            time,
            text,
            "Mode \(attribution.name)",
            status.label,
            flaggedDescription,
        ]
        if attribution.isDeleted {
            accessibilityParts.insert("Deleted Mode", at: 3)
        }
        accessibilityDescription = accessibilityParts.joined(separator: ", ")
    }

    private static func attribution(
        for entry: HistoryEntry,
        modes: [Mode]
    ) -> (name: String, icon: String, isDeleted: Bool) {
        guard let modeID = entry.modeID else {
            return (entry.modeName, "text.bubble", false)
        }
        guard let current = modes.first(where: { $0.id == modeID }) else {
            return (entry.modeName, "text.bubble", true)
        }
        let icon = NSImage(
            systemSymbolName: current.icon,
            accessibilityDescription: nil
        ) == nil ? "text.bubble" : current.icon
        return (current.name, icon, false)
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        formatterLock.withLock {
            let key = "\(calendar.identifier)|\(calendar.timeZone.identifier)"
            if let formatter = formatters[key] {
                return formatter.string(from: date)
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            if formatters.count >= 16 {
                formatters.removeAll(keepingCapacity: true)
            }
            formatters[key] = formatter
            return formatter.string(from: date)
        }
    }
}
