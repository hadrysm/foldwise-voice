import CoreGraphics

enum HomeOverviewLayout: Equatable {
    case wide
    case compact

    static func forWindowWidth(_ width: Double) -> HomeOverviewLayout {
        width >= Theme.homeCompactBreakpoint ? .wide : .compact
    }

    var metricColumnCount: Int {
        self == .wide ? 4 : 2
    }

    var contentPadding: CGFloat {
        self == .wide ? Theme.contentPaddingWide : Theme.contentPaddingCompact
    }
}
