enum HomeOverviewLayout: Equatable {
    case wide
    case compact

    static func forWindowWidth(_ width: Double) -> HomeOverviewLayout {
        width >= Theme.homeCompactBreakpoint ? .wide : .compact
    }
}
