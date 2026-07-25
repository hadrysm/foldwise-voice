import Foundation

enum ApplicationTerminationDecision: Equatable {
    case terminateNow
    case terminateLater
}

final class DictationLifecycleCoordinator {
    private let tearDown: () -> Void
    private var activeDictationSessionIDs: Set<UUID> = []
    private var pendingTerminationReply: (() -> Void)?
    private var pendingRelaunchHandler: (() -> Void)?
    private var didTearDown = false

    init(tearDown: @escaping () -> Void) {
        self.tearDown = tearDown
    }

    func sessionDidChange(_ event: DictationSessionEvent) {
        switch event {
        case let .started(id):
            activeDictationSessionIDs.insert(id)
        case let .finished(id):
            completeDictationSession(id)
        }
    }

    func applicationShouldTerminate(
        reply: @escaping () -> Void
    ) -> ApplicationTerminationDecision {
        guard !activeDictationSessionIDs.isEmpty else {
            performTearDown()
            return .terminateNow
        }
        if pendingTerminationReply == nil {
            pendingTerminationReply = reply
        }
        return .terminateLater
    }

    func shouldPostponeRelaunch(untilInvoking installHandler: @escaping () -> Void) -> Bool {
        guard !activeDictationSessionIDs.isEmpty else { return false }
        if pendingRelaunchHandler == nil {
            pendingRelaunchHandler = installHandler
        }
        return true
    }

    private func completeDictationSession(_ id: UUID) {
        guard activeDictationSessionIDs.remove(id) != nil,
              activeDictationSessionIDs.isEmpty
        else { return }

        let relaunchHandler = pendingRelaunchHandler
        pendingRelaunchHandler = nil
        relaunchHandler?()

        if let reply = pendingTerminationReply {
            pendingTerminationReply = nil
            performTearDown()
            reply()
        }
    }

    private func performTearDown() {
        guard !didTearDown else { return }
        didTearDown = true
        tearDown()
    }
}
