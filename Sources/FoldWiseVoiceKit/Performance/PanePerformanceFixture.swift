import Foundation

enum PanePerformanceProfile: String, CaseIterable, Codable {
    case empty
    case tenThousand = "10000"
}

struct PanePerformanceFixture {
    let profile: PanePerformanceProfile
    let entries: [HistoryEntry]

    var identity: String {
        switch profile {
        case .empty:
            "pane-empty-v1"
        case .tenThousand:
            "pane-10000-v1"
        }
    }

    init(profile: PanePerformanceProfile) {
        self.profile = profile
        switch profile {
        case .empty:
            entries = []
        case .tenThousand:
            entries = (0 ..< 10000).map(Self.expectedEntry)
        }
    }

    static func expectedEntry(at index: Int) -> HistoryEntry {
        let vocabulary = [
            "meeting", "notes", "follow", "up", "team", "quarterly", "roadmap",
            "release", "review", "customer", "research", "design", "measure",
            "history", "calendar", "dictation", "session", "summary", "today",
        ]
        let wordCount = 12 + (index * 37) % 48
        let words = (0 ..< wordCount).map { offset in
            vocabulary[(index + offset * 13) % vocabulary.count]
        }
        let rawText = words.joined(separator: " ")
        let polished = index.isMultiple(of: 3)
        return HistoryEntry(
            id: stableUUID(at: index),
            createdAt: Date(timeIntervalSince1970: 1_783_075_200)
                .addingTimeInterval(-Double(index) * 37 * 60),
            text: polished ? rawText.capitalized + "." : rawText,
            rawText: rawText,
            isPolished: polished,
            modeName: polished ? "Performance Mode" : "Voice to Text",
            modeID: polished ? performanceModeID : nil,
            wordCount: wordCount,
            sourceApp: index.isMultiple(of: 5) ? "TextEdit" : nil,
            durationMs: wordCount * 390,
            flagged: index.isMultiple(of: 17),
            flagReason: nil
        )
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        var data = Data()
        for entry in entries {
            data.append(try encoder.encode(entry))
            data.append(0x0A)
        }
        try data.write(to: url, options: .atomic)
    }

    private static let performanceModeID = ModeID(
        rawValue: "11111111-1111-4111-8111-111111111111"
    )!

    private static func stableUUID(at index: Int) -> UUID {
        let value = String(
            format: "00000000-0000-4000-8000-%012lld",
            Int64(index)
        )
        // The fixed prefix plus a twelve-digit nonnegative fixture index is
        // UUID-shaped by construction.
        return UUID(uuidString: value)!
    }
}
