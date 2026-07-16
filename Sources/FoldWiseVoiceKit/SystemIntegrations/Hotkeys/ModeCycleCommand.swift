import Foundation

struct ModeCycleTransition: Equatable {
    let from: DictationSelection
    let to: ModeID
}

@MainActor
final class ModeCycleCommand {
    private let config: Config
    private let onCommitted: (ModeCycleTransition) -> Void
    private let onFailure: (Error) -> Void

    init(
        config: Config,
        onCommitted: @escaping (ModeCycleTransition) -> Void = { _ in },
        onFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.config = config
        self.onCommitted = onCommitted
        self.onFailure = onFailure
    }

    func perform() {
        let current = config.selection
        let ids = config.orderedModes.compactMap(\.id)
        guard let next = ModeCyclePolicy.nextSelection(
            after: current,
            orderedModeIDs: ids
        ), case let .mode(id) = next else { return }
        do {
            try config.select(next)
            onCommitted(ModeCycleTransition(from: current, to: id))
        } catch {
            onFailure(error)
        }
    }
}
