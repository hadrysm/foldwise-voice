actor UpdateRuntimeAcceptanceInsertionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func insert(_: String) async -> Bool {
        await wait()
        return true
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func isWaiting() -> Bool {
        !waiters.isEmpty
    }

    private func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
