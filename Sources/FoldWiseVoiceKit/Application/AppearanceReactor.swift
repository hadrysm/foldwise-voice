import AppKit

@MainActor
final class AppearanceReactor {
    typealias Apply = @MainActor (NSAppearance?) -> Void

    private let config: Config
    private let apply: Apply

    init(
        config: Config,
        apply: @escaping Apply = { NSApp.appearance = $0 }
    ) {
        self.config = config
        self.apply = apply
        applyPreference()
        config.onChange { [weak self] changes in
            guard changes.contains(.appearance) else { return }
            self?.applyPreference()
        }
    }

    private func applyPreference() {
        let applicationAppearance: NSAppearance? = switch config.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        apply(applicationAppearance)
    }
}
