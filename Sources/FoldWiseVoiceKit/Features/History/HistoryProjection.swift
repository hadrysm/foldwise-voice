import Foundation

/// The current semantic Mode attribution for one saved Dictation session.
/// Symbol validation remains presentation work and happens only for a visible
/// row.
struct HistoryModeAttribution: Equatable {
    let name: String
    let icon: String
    let isDeleted: Bool

    init(entry: HistoryEntry, currentMode: Mode?) {
        guard entry.modeID != nil else {
            name = entry.modeName
            icon = "text.bubble"
            isDeleted = false
            return
        }
        guard let currentMode else {
            name = entry.modeName
            icon = "text.bubble"
            isDeleted = true
            return
        }
        name = currentMode.name
        icon = currentMode.icon
        isDeleted = false
    }

    fileprivate init(name: String, icon: String, isDeleted: Bool) {
        self.name = name
        self.icon = icon
        self.isDeleted = isDeleted
    }
}

/// Search, filtering, ordering, and day grouping for the full History
/// collection. Rows retain semantic source data; their presentation is
/// materialized only when SwiftUI asks a lazy row to render.
final class HistoryProjection: Equatable, @unchecked Sendable {
    struct Input: Equatable {
        let entries: [HistoryEntry]
        let search: String
        let flaggedOnly: Bool
        let modes: [Mode]

        init(
            entries: [HistoryEntry],
            search: String,
            flaggedOnly: Bool,
            modes: [Mode] = []
        ) {
            self.entries = entries
            self.search = search
            self.flaggedOnly = flaggedOnly
            self.modes = modes
        }
    }

    struct Row: Equatable, Identifiable {
        let id: UUID

        fileprivate init(id: UUID) {
            self.id = id
        }
    }

    struct Section: Equatable {
        let header: String
        let rows: [Row]
    }

    let sections: [Section]
    let hasSourceEntries: Bool
    private let recordsByID: [UUID: HistoryIndex.Record]
    private let calendar: Calendar
    private let presentationLock = NSLock()
    private var presentationsByID: [UUID: DictationRowPresentation] = [:]

    var isEmpty: Bool {
        sections.isEmpty
    }

    private init(
        sections: [Section],
        hasSourceEntries: Bool,
        recordsByID: [UUID: HistoryIndex.Record],
        calendar: Calendar
    ) {
        self.sections = sections
        self.hasSourceEntries = hasSourceEntries
        self.recordsByID = recordsByID
        self.calendar = calendar
    }

    static let empty = HistoryProjection(
        sections: [],
        hasSourceEntries: false,
        recordsByID: [:],
        calendar: .current
    )

    static func == (lhs: HistoryProjection, rhs: HistoryProjection) -> Bool {
        lhs === rhs
    }

    func entry(for row: Row) -> HistoryEntry {
        record(for: row).entry
    }

    func presentation(for row: Row) -> DictationRowPresentation {
        presentationLock.withLock {
            if let presentation = presentationsByID[row.id] {
                return presentation
            }
            let record = record(for: row)
            let presentation = DictationRowPresentation(
                entry: record.entry,
                attribution: record.attribution,
                calendar: calendar
            )
            presentationsByID[row.id] = presentation
            return presentation
        }
    }

    private func record(for row: Row) -> HistoryIndex.Record {
        guard let record = recordsByID[row.id] else {
            preconditionFailure("History row lost its indexed source")
        }
        return record
    }

    static func project(
        _ input: Input,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HistoryProjection {
        var index = HistoryIndex()
        index.setModes(input.modes)
        index.setEntries(input.entries)
        let snapshot = index.snapshot(calendar: calendar)
        return project(
            snapshot,
            search: input.search,
            flaggedOnly: input.flaggedOnly,
            now: now,
            locale: locale
        ) ?? .empty
    }

    static func project(
        _ snapshot: HistoryIndex.Snapshot,
        search: String,
        flaggedOnly: Bool,
        now: Date,
        locale: Locale,
        shouldCancel: () -> Bool = { false }
    ) -> HistoryProjection? {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = dayFormatter(
            calendar: snapshot.calendar,
            locale: locale
        )
        var projectedGroups: [(header: String, records: [HistoryIndex.Record])] = []
        projectedGroups.reserveCapacity(snapshot.groups.count)
        var recordsByID: [UUID: HistoryIndex.Record] = [:]
        recordsByID.reserveCapacity(snapshot.sourceCount)

        for group in snapshot.groups {
            guard !shouldCancel() else { return nil }
            var records: [HistoryIndex.Record] = []
            records.reserveCapacity(group.records.count)
            for record in group.records {
                guard !shouldCancel() else { return nil }
                if flaggedOnly, !record.entry.flagged {
                    continue
                }
                if !query.isEmpty,
                   !record.entry.text.localizedCaseInsensitiveContains(query),
                   !record.entry.rawText.localizedCaseInsensitiveContains(query) {
                    continue
                }
                records.append(record)
            }
            guard !records.isEmpty else { continue }
            for record in records {
                recordsByID[record.entry.id] = record
            }
            projectedGroups.append((
                header: header(
                    for: group.day,
                    now: now,
                    calendar: snapshot.calendar,
                    formatter: formatter
                ),
                records: records
            ))
        }

        return HistoryProjection(
            sections: projectedGroups.map { group in
                Section(
                    header: group.header,
                    rows: group.records.map {
                        Row(id: $0.entry.id)
                    }
                )
            },
            hasSourceEntries: snapshot.sourceCount > 0,
            recordsByID: recordsByID,
            calendar: snapshot.calendar
        )
    }

    private static func header(
        for day: Date,
        now: Date,
        calendar: Calendar,
        formatter: DateFormatter
    ) -> String {
        let today = calendar.startOfDay(for: now)
        if day == today {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           day == yesterday {
            return "Yesterday"
        }
        return formatter.string(from: day)
    }

    private static func dayFormatter(
        calendar: Calendar,
        locale: Locale
    ) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

/// Controller-retained chronological and day-grouped index. The store mutates
/// this value on the main actor, then hands immutable snapshots to detached
/// projection tasks.
struct HistoryIndex {
    private static let incrementalUpdateLimit = 64

    fileprivate struct Group: Equatable {
        let day: Date
        var records: [Record]
    }

    struct Snapshot: Equatable {
        let calendar: Calendar
        fileprivate var groups: [Group]
        fileprivate(set) var sourceCount: Int

        fileprivate mutating func apply(
            removing removedIDs: Set<UUID>,
            inserting records: [Record]
        ) {
            if !removedIDs.isEmpty {
                groups = groups.compactMap { group in
                    let records = group.records.filter {
                        !removedIDs.contains($0.entry.id)
                    }
                    return records.isEmpty
                        ? nil
                        : Group(day: group.day, records: records)
                }
            }
            for record in records {
                insert(record)
            }
        }

        fileprivate mutating func refresh(
            ids: Set<UUID>,
            from recordsByID: [UUID: Record]
        ) {
            guard !ids.isEmpty else { return }
            for groupIndex in groups.indices {
                for recordIndex in groups[groupIndex].records.indices {
                    let id = groups[groupIndex].records[recordIndex].entry.id
                    guard ids.contains(id), let record = recordsByID[id] else {
                        continue
                    }
                    groups[groupIndex].records[recordIndex] = record
                }
            }
        }

        private mutating func insert(_ record: Record) {
            let day = calendar.startOfDay(for: record.entry.createdAt)
            if let groupIndex = groups.firstIndex(where: { $0.day == day }) {
                let recordIndex = groups[groupIndex].records.firstIndex {
                    HistoryIndex.isNewer(record, than: $0)
                } ?? groups[groupIndex].records.endIndex
                groups[groupIndex].records.insert(record, at: recordIndex)
                return
            }
            let groupIndex = groups.firstIndex { $0.day < day }
                ?? groups.endIndex
            groups.insert(
                Group(day: day, records: [record]),
                at: groupIndex
            )
        }
    }

    fileprivate struct Record: Equatable {
        let entry: HistoryEntry
        let attribution: HistoryModeAttribution
    }

    private struct ModeValue: Equatable {
        let name: String
        let icon: String
    }

    private struct CalendarKey: Equatable {
        let identifier: String
        let timeZoneIdentifier: String
    }

    private var recordsByID: [UUID: Record] = [:]
    private var orderedIDs: [UUID] = []
    private var entryIDsByModeID: [ModeID: Set<UUID>] = [:]
    private var modesByID: [ModeID: ModeValue] = [:]
    private var cachedSnapshot: (key: CalendarKey, value: Snapshot)?

    mutating func setModes(_ modes: [Mode]) {
        let nextModes = modes.reduce(into: [ModeID: ModeValue]()) { values, mode in
            guard let id = mode.id else { return }
            values[id] = ModeValue(name: mode.name, icon: mode.icon)
        }
        let changedModeIDs = Set(modesByID.keys)
            .union(nextModes.keys)
            .filter { modesByID[$0] != nextModes[$0] }
        modesByID = nextModes
        let affectedEntryIDs = changedModeIDs.reduce(into: Set<UUID>()) { ids, modeID in
            ids.formUnion(entryIDsByModeID[modeID] ?? [])
        }
        guard !affectedEntryIDs.isEmpty else { return }
        for id in affectedEntryIDs {
            guard let existing = recordsByID[id] else { continue }
            recordsByID[id] = record(for: existing.entry)
        }
        cachedSnapshot?.value.refresh(
            ids: affectedEntryIDs,
            from: recordsByID
        )
    }

    mutating func setEntries(_ entries: [HistoryEntry]) {
        var incomingByID: [UUID: HistoryEntry] = [:]
        var incomingIDs: [UUID] = []
        incomingIDs.reserveCapacity(entries.count)
        for entry in entries where incomingByID[entry.id] == nil {
            incomingByID[entry.id] = entry
            incomingIDs.append(entry.id)
        }

        let removedIDs = Set(recordsByID.keys).subtracting(incomingByID.keys)
        var changedIDs = Set<UUID>()
        var reorderedIDs = removedIDs
        for id in incomingIDs {
            guard let entry = incomingByID[id] else { continue }
            if let existing = recordsByID[id] {
                guard existing.entry != entry else { continue }
                changedIDs.insert(id)
                if existing.entry.createdAt != entry.createdAt {
                    reorderedIDs.insert(id)
                }
            } else {
                changedIDs.insert(id)
                reorderedIDs.insert(id)
            }
        }
        guard !removedIDs.isEmpty || !changedIDs.isEmpty else { return }

        for id in removedIDs.union(changedIDs) {
            removeModeMembership(for: recordsByID[id]?.entry)
        }
        for id in removedIDs {
            recordsByID[id] = nil
        }
        for id in changedIDs {
            guard let entry = incomingByID[id] else { continue }
            recordsByID[id] = record(for: entry)
            addModeMembership(for: entry)
        }

        let rebuildOrdering = orderedIDs.isEmpty
            || reorderedIDs.count > Self.incrementalUpdateLimit
        if rebuildOrdering {
            orderedIDs = recordsByID.values
                .sorted { Self.isNewer($0, than: $1) }
                .map(\.entry.id)
        } else {
            orderedIDs.removeAll { reorderedIDs.contains($0) }
            let recordsToInsert = reorderedIDs.compactMap { recordsByID[$0] }
                .sorted { Self.isNewer($0, than: $1) }
            for record in recordsToInsert {
                let insertionIndex = orderedIDs.firstIndex {
                    guard let existing = recordsByID[$0] else { return false }
                    return Self.isNewer(record, than: existing)
                } ?? orderedIDs.endIndex
                orderedIDs.insert(record.entry.id, at: insertionIndex)
            }
        }

        let replacedIDs = removedIDs.union(changedIDs)
        if rebuildOrdering || replacedIDs.count > Self.incrementalUpdateLimit {
            cachedSnapshot = nil
        } else {
            let replacements = changedIDs.compactMap { recordsByID[$0] }
            cachedSnapshot?.value.apply(
                removing: replacedIDs,
                inserting: replacements
            )
            cachedSnapshot?.value.sourceCount = recordsByID.count
        }
    }

    mutating func snapshot(calendar: Calendar) -> Snapshot {
        let key = CalendarKey(
            identifier: String(describing: calendar.identifier),
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        if let cachedSnapshot, cachedSnapshot.key == key {
            return cachedSnapshot.value
        }

        var groups: [Group] = []
        for id in orderedIDs {
            guard let record = recordsByID[id] else { continue }
            let day = calendar.startOfDay(for: record.entry.createdAt)
            if groups.last?.day == day {
                groups[groups.endIndex - 1].records.append(record)
            } else {
                groups.append(Group(day: day, records: [record]))
            }
        }
        let snapshot = Snapshot(
            calendar: calendar,
            groups: groups,
            sourceCount: recordsByID.count
        )
        cachedSnapshot = (key, snapshot)
        return snapshot
    }

    private mutating func removeModeMembership(for entry: HistoryEntry?) {
        guard let entry, let modeID = entry.modeID else { return }
        entryIDsByModeID[modeID]?.remove(entry.id)
        if entryIDsByModeID[modeID]?.isEmpty == true {
            entryIDsByModeID[modeID] = nil
        }
    }

    private mutating func addModeMembership(for entry: HistoryEntry) {
        guard let modeID = entry.modeID else { return }
        entryIDsByModeID[modeID, default: []].insert(entry.id)
    }

    private func record(for entry: HistoryEntry) -> Record {
        let attribution = if let modeID = entry.modeID, let mode = modesByID[modeID] {
            HistoryModeAttribution(
                name: mode.name,
                icon: mode.icon,
                isDeleted: false
            )
        } else {
            HistoryModeAttribution(
                name: entry.modeName,
                icon: "text.bubble",
                isDeleted: entry.modeID != nil
            )
        }
        return Record(entry: entry, attribution: attribution)
    }

    fileprivate static func isNewer(
        _ lhs: Record,
        than rhs: Record
    ) -> Bool {
        if lhs.entry.createdAt != rhs.entry.createdAt {
            return lhs.entry.createdAt > rhs.entry.createdAt
        }
        return lhs.entry.id.uuidString < rhs.entry.id.uuidString
    }
}
