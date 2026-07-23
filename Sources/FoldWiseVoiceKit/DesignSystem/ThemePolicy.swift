import CoreGraphics

enum ThemeBoundaryStrength: Equatable {
    case standard
    case strong

    var width: CGFloat {
        switch self {
        case .standard: 1
        case .strong: 2
        }
    }
}

enum ThemeEnvironmentPolicy {
    static func boundary(increaseContrast: Bool) -> ThemeBoundaryStrength {
        increaseContrast ? .strong : .standard
    }

    static func ordinaryMotionDuration(reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : 0.16
    }
}

enum EmberSemanticColorRole: String {
    case success
    case warning
    case error
}

enum EmberStatusKind: CaseIterable {
    case success
    case warning
    case error

    var accessibilityName: String {
        switch self {
        case .success: "Success"
        case .warning: "Warning"
        case .error: "Error"
        }
    }

    var symbolName: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var colorRole: EmberSemanticColorRole {
        switch self {
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}

enum ThemeTypographyWeight: Equatable {
    case regular
    case medium
    case semibold
    case bold
}

struct ThemeTypographyRole: Equatable {
    let size: CGFloat
    let weight: ThemeTypographyWeight
    let isMonospaced: Bool
    let tracking: CGFloat
}

enum ThemeTypographyPolicy {
    static let display = ThemeTypographyRole(
        size: 30, weight: .semibold, isMonospaced: false, tracking: -0.5
    )
    static let section = ThemeTypographyRole(
        size: 11, weight: .bold, isMonospaced: false, tracking: 0.7
    )
    static let body = ThemeTypographyRole(
        size: 13.5, weight: .regular, isMonospaced: false, tracking: 0
    )
    static let data = ThemeTypographyRole(
        size: 11, weight: .medium, isMonospaced: true, tracking: 0
    )
    static let compactData = ThemeTypographyRole(
        size: 10.5, weight: .medium, isMonospaced: true, tracking: 0
    )
}
