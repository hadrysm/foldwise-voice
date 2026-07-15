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
    let polishStatus: PolishStatus
    let isFlagged: Bool
    let accessibilityDescription: String

    init(entry: HistoryEntry, calendar: Calendar = .current) {
        let time = Self.time(entry.createdAt, calendar: calendar)
        let text = Self.singleLine(entry.text)
        let status = PolishStatus(entry)
        let flaggedDescription = entry.flagged ? "Flagged" : "Not flagged"

        self.time = time
        self.text = text
        fullModeName = entry.modeName
        compactModeName = String(
            entry.modeName.lowercased().prefix(Self.maxCompactModeLength)
        )
        polishStatus = status
        isFlagged = entry.flagged
        accessibilityDescription = [
            time,
            text,
            "Mode \(entry.modeName)",
            status.label,
            flaggedDescription,
        ].joined(separator: ", ")
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
