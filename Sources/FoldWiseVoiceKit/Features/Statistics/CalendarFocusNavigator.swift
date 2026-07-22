import Foundation

struct CalendarFocusNavigator {
    enum Direction {
        case left
        case right
        case up
        case down
    }

    private let eligibleDates: [Date]

    init(eligibleDates: [Date]) {
        self.eligibleDates = eligibleDates
    }

    func move(from date: Date, direction: Direction) -> Date? {
        guard let index = eligibleDates.firstIndex(of: date), !eligibleDates.isEmpty else {
            return eligibleDates.last
        }
        let offset = switch direction {
        case .left: -1
        case .right: 1
        case .up: -7
        case .down: 7
        }
        let destination = min(max(0, index + offset), eligibleDates.count - 1)
        return eligibleDates[destination]
    }

    func repair(_ date: Date?) -> Date? {
        guard let date, eligibleDates.contains(date) else {
            return eligibleDates.last
        }
        return date
    }

    static func detailDate(hovered: Date?, focused: Date?) -> Date? {
        hovered ?? focused
    }
}
