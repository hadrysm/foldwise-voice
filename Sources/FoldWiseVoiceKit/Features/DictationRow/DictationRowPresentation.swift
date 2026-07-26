import AppKit
import Foundation

/// Immutable identity for one saved Dictation session wherever it is rendered.
/// Collection projections retain the exact source entry separately so this
/// value never becomes an action or persistence model.
struct DictationRowPresentation: Equatable {
    static let maxCompactModeLength = 16
    private static let symbolLock = NSLock()
    private static var resolvedSymbols: [String: String] = [:]

    let time: String
    let text: String
    let fullModeName: String
    let compactModeName: String
    let modeIcon: String
    let isDeletedMode: Bool
    let polishStatus: PolishStatus
    let polishStatusSymbolName: String
    let isFlagged: Bool
    let accessibilityDescription: String

    init(
        entry: HistoryEntry,
        modes: [Mode] = [],
        calendar: Calendar = .current
    ) {
        let currentMode = entry.modeID.flatMap { modeID in
            modes.first { $0.id == modeID }
        }
        self.init(
            entry: entry,
            attribution: HistoryModeAttribution(
                entry: entry,
                currentMode: currentMode
            ),
            calendar: calendar
        )
    }

    init(
        entry: HistoryEntry,
        attribution: HistoryModeAttribution,
        calendar: Calendar = .current
    ) {
        let time = Self.time(entry.createdAt, calendar: calendar)
        let text = Self.singleLine(entry.text)
        let status = PolishStatus(entry)
        let flaggedDescription = entry.flagged ? "Flagged" : "Not flagged"
        let icon = Self.resolvedSymbol(attribution.icon)

        self.time = time
        self.text = text
        fullModeName = attribution.name
        compactModeName = String(
            attribution.name.lowercased().prefix(Self.maxCompactModeLength)
        )
        modeIcon = icon
        isDeletedMode = attribution.isDeleted
        polishStatus = status
        polishStatusSymbolName = switch status {
        case .polished: "wand.and.stars"
        case .raw: "waveform"
        }
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

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func time(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(
            format: "%02d:%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    private static func resolvedSymbol(_ name: String) -> String {
        symbolLock.withLock {
            if let resolved = resolvedSymbols[name] {
                return resolved
            }
            let resolved = NSImage(
                systemSymbolName: name,
                accessibilityDescription: nil
            ) == nil ? "text.bubble" : name
            if resolvedSymbols.count >= 64 {
                resolvedSymbols.removeAll(keepingCapacity: true)
            }
            resolvedSymbols[name] = resolved
            return resolved
        }
    }
}
