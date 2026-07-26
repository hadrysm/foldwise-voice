import CoreGraphics

struct StatsCalendarLayout: Equatable {
    static let columnCount = 7
    static let columnSpacing: CGFloat = 6
    static let rowSpacing: CGFloat = 6
    static let weekdayHeight: CGFloat = 11
    static let dayHeight: CGFloat = 44

    let width: CGFloat
    let leadingColumnOffset: Int
    let dayCount: Int

    var height: CGFloat {
        guard rowCount > 0 else { return Self.weekdayHeight }
        return Self.weekdayHeight
            + Self.rowSpacing
            + CGFloat(rowCount) * Self.dayHeight
            + CGFloat(rowCount - 1) * Self.rowSpacing
    }

    func weekdayFrame(at index: Int) -> CGRect {
        CGRect(
            x: CGFloat(index) * (columnWidth + Self.columnSpacing),
            y: 0,
            width: columnWidth,
            height: Self.weekdayHeight
        )
    }

    func dayFrame(at index: Int) -> CGRect {
        let position = leadingColumnOffset + index
        let column = position % Self.columnCount
        let row = position / Self.columnCount
        return CGRect(
            x: CGFloat(column) * (columnWidth + Self.columnSpacing),
            y: Self.weekdayHeight
                + Self.rowSpacing
                + CGFloat(row) * (Self.dayHeight + Self.rowSpacing),
            width: columnWidth,
            height: Self.dayHeight
        )
    }

    private var columnWidth: CGFloat {
        let spacing = CGFloat(Self.columnCount - 1) * Self.columnSpacing
        return max(0, (width - spacing) / CGFloat(Self.columnCount))
    }

    private var rowCount: Int {
        guard dayCount > 0 else { return 0 }
        return (leadingColumnOffset + dayCount + Self.columnCount - 1)
            / Self.columnCount
    }
}
