final class UpdateRuntimeAcceptanceRelaunchDriver {
    private var didBeginInstallation = false
    private var didRequestTermination = false

    func beginImmediateInstallation(
        prepare: () throws -> Void,
        install: () -> Void
    ) rethrows -> Bool {
        guard !didBeginInstallation else { return true }
        try prepare()
        didBeginInstallation = true
        install()
        return true
    }

    func requestTerminationOnce(_ request: () -> Void) {
        guard !didRequestTermination else { return }
        didRequestTermination = true
        request()
    }
}
