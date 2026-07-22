import Foundation

struct ASRModelDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
    let languages: String
    let size: String
    let speed: Int
    let quality: Int
    let blurb: String
    let isAvailable: Bool
    let isDefault: Bool
    let allowsDeletion: Bool

    init(entry: ASRModelCatalog.Entry, isAvailable: Bool) {
        id = entry.id
        name = entry.name
        languages = entry.languages
        size = entry.size
        speed = entry.speed
        quality = entry.quality
        blurb = entry.blurb
        self.isAvailable = isAvailable
        isDefault = entry.id == ASRModelCatalog.defaultID
        allowsDeletion = !isDefault
    }
}

struct ASRModelLifecycleSnapshot: Equatable {
    let models: [ASRModelDescriptor]
    let storedSelection: String
    let effectiveSelection: String?
    let recovery: ASRModelLifecycleRecovery?
    let operation: ASRModelLifecycleOperation?
    let failure: ASRModelLifecycleFailure?
    let isDictationBlocked: Bool
}

enum ASRModelLifecycleRecovery: Equatable {
    case storedSelectionUnavailable(modelID: String, fallbackModelID: String)
    case storedSelectionUnknown(modelID: String, fallbackModelID: String)
}

enum ASRModelLifecycleOperation: Equatable {
    case downloading(modelID: String, fraction: Double?)
    case bootstrapping(fraction: Double?)
    case switching(modelID: String)
    case restoring(modelID: String)
    case deleting(modelID: String)
}

enum ASRModelLifecycleFailure: Equatable {
    case downloadFailed(modelID: String, reason: String)
    case downloadedDataInvalid(modelID: String)
    case bootstrapFailed(reason: String)
    case engineLoadFailed(modelID: String, reason: String)
    case selectionFailed(modelID: String, reason: String)
    case selectionCanceled(modelID: String)
    case selectionDegraded(modelID: String, fallbackModelID: String, reason: String?)
    case deletionFailed(modelID: String, reason: String)
    case deletionSelectionFailed(modelID: String, reason: String)

    var allowsBootstrapRetry: Bool {
        switch self {
        case .bootstrapFailed:
            true
        case let .engineLoadFailed(modelID, _):
            modelID == ASRModelCatalog.defaultID
        case .downloadFailed, .downloadedDataInvalid, .selectionFailed, .selectionCanceled,
             .selectionDegraded, .deletionFailed, .deletionSelectionFailed:
            false
        }
    }
}

protocol ASRModelFamilyAdapting: Sendable {
    var modelIDs: Set<String> { get }
    func isModelDataAvailable(for id: String) -> Bool
    func downloadModelData(
        for id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
    func makeEngine(for id: String) throws -> Transcribing
    func removeModelData(for id: String) async throws
}

enum ASRModelLifecycleError: LocalizedError {
    case recognitionBlocked

    var errorDescription: String? {
        switch self {
        case .recognitionBlocked:
            "Speech recognition is unavailable."
        }
    }
}

actor ASRModelLifecycle: ASRSessionHandleProviding {
    typealias PersistSelection = @MainActor (String) throws -> Void

    private struct ActiveDownload {
        let id: UUID
        let modelID: String
        let task: Task<Void, Error>
    }

    private struct ActiveSelection {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var storedSelection: String
    private let adapters: [any ASRModelFamilyAdapting]
    private let persistSelection: PersistSelection
    private var availability: Set<String> = []
    private var rejectedEngineModelIDs: Set<String> = []
    private var effectiveSelection: String?
    private var activationInProgress = false
    private var engine: Transcribing?
    private var didStart = false
    private var dictationBlocked = true
    private var bootstrapOperationID: UUID?
    private var operation: ASRModelLifecycleOperation?
    private var failure: ASRModelLifecycleFailure?
    private var activeDownload: ActiveDownload?
    private var activeSelection: ActiveSelection?
    private var canceledDownloadIDs: Set<UUID> = []
    private var observers: [UUID: AsyncStream<ASRModelLifecycleSnapshot>.Continuation] = [:]
    private let sessionCoordinator = ASRLifecycleSessionCoordinator()

    init(
        storedSelection: String,
        adapters: [any ASRModelFamilyAdapting],
        persistSelection: @escaping PersistSelection = { _ in }
    ) {
        self.storedSelection = storedSelection
        self.adapters = adapters
        self.persistSelection = persistSelection
    }

    nonisolated var isDictationBlocked: Bool {
        sessionCoordinator.isDictationBlocked
    }

    nonisolated func captureSession() throws -> any ASRSessionHandle {
        try sessionCoordinator.captureSession()
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        dictationBlocked = true
        sessionCoordinator.setDictationBlocked(true)
        reconcileAvailabilityFromAdapters()
        guard availability.contains(ASRModelCatalog.defaultID) else {
            await bootstrapDefault()
            return
        }
        await ensureEffectiveEngine()
    }

    func retryBootstrap() async {
        guard didStart, dictationBlocked, operation == nil else { return }
        rejectedEngineModelIDs.remove(ASRModelCatalog.defaultID)
        reconcileAvailabilityFromAdapters()
        if availability.contains(ASRModelCatalog.defaultID) {
            failure = nil
            await ensureEffectiveEngine()
        } else {
            await bootstrapDefault()
        }
    }

    private func ensureEffectiveEngine() async {
        guard !activationInProgress else {
            publishSnapshot()
            return
        }
        activationInProgress = true
        var ownsAutomaticRestorationOperation = false
        defer {
            activationInProgress = false
            if ownsAutomaticRestorationOperation {
                operation = nil
                publishSnapshot()
            }
        }

        while true {
            let targetID = effectiveTargetID()
            guard availability.contains(targetID) else {
                await blockDictationThenReleaseEngine()
                publishSnapshot()
                return
            }
            guard targetID != effectiveSelection || engine == nil else {
                dictationBlocked = engine == nil
                sessionCoordinator.activate(engine, modelID: effectiveSelection)
                publishSnapshot()
                return
            }

            if operation == nil {
                operation = .restoring(modelID: targetID)
                ownsAutomaticRestorationOperation = true
            } else if ownsAutomaticRestorationOperation {
                operation = .restoring(modelID: targetID)
            }

            await blockDictationThenReleaseEngine()
            publishSnapshot()
            guard targetID == effectiveTargetID(), availability.contains(targetID) else {
                continue
            }
            guard let adapter = adapter(for: targetID) else {
                failure = .engineLoadFailed(
                    modelID: targetID,
                    reason: "No engine-family adapter is available."
                )
                publishSnapshot()
                return
            }
            do {
                let candidate = try adapter.makeEngine(for: targetID)
                try await candidate.prepare()
                guard targetID == effectiveTargetID(), availability.contains(targetID) else {
                    continue
                }
                engine = candidate
                effectiveSelection = targetID
                dictationBlocked = false
                sessionCoordinator.activate(candidate, modelID: targetID)
                publishSnapshot()
                return
            } catch {
                let failedCurrentTarget = targetID == effectiveTargetID()
                rejectedEngineModelIDs.insert(targetID)
                reconcileAvailabilityFromAdapters()
                if failedCurrentTarget {
                    failure = .engineLoadFailed(
                        modelID: targetID,
                        reason: error.localizedDescription
                    )
                }
                if targetID != ASRModelCatalog.defaultID,
                   availability.contains(ASRModelCatalog.defaultID) {
                    continue
                }
                if !failedCurrentTarget,
                   availability.contains(effectiveTargetID()) {
                    continue
                }
                publishSnapshot()
                return
            }
        }
    }

    private func blockDictationThenReleaseEngine() async {
        dictationBlocked = true
        if sessionCoordinator.beginBlockingSessions() {
            publishSnapshot()
        }
        await sessionCoordinator.waitForSessionsToDrain()
        engine = nil
        effectiveSelection = nil
    }

    private func blockDictationThenReleaseEngineForSelection() async throws {
        do {
            try await sessionCoordinator.waitForSessionsToDrainCancelable()
            try Task.checkCancellation()
        } catch {
            dictationBlocked = false
            sessionCoordinator.activate(engine, modelID: effectiveSelection)
            throw error
        }
        await releaseEffectiveEngineForExclusiveOperation()
    }

    private func releaseEffectiveEngineForExclusiveOperation() async {
        engine = nil
        effectiveSelection = nil
        // Let ARC finish engine teardown before replacement or storage removal begins.
        await Task.yield()
    }

    private func bootstrapDefault() async {
        guard operation == nil, let adapter = adapter(for: ASRModelCatalog.defaultID) else {
            failure = .bootstrapFailed(reason: "The default ASR model is unavailable.")
            publishSnapshot()
            return
        }
        let operationID = UUID()
        bootstrapOperationID = operationID
        failure = nil
        operation = .bootstrapping(fraction: nil)
        dictationBlocked = true
        sessionCoordinator.setDictationBlocked(true)
        publishSnapshot()
        let lifecycle = self
        let result = await Task {
            try await adapter.downloadModelData(for: ASRModelCatalog.defaultID) { fraction in
                Task { await lifecycle.publishBootstrapProgress(fraction, operationID: operationID) }
            }
        }.result
        guard bootstrapOperationID == operationID else { return }
        bootstrapOperationID = nil
        if case .success = result {
            rejectedEngineModelIDs.remove(ASRModelCatalog.defaultID)
        }
        reconcileAvailabilityFromAdapters()
        guard case .success = result,
              availability.contains(ASRModelCatalog.defaultID) else {
            operation = nil
            failure = switch result {
            case let .failure(error): .bootstrapFailed(reason: error.localizedDescription)
            case .success: .bootstrapFailed(reason: "Downloaded model data is incomplete or corrupt.")
            }
            publishSnapshot()
            return
        }
        operation = .bootstrapping(fraction: nil)
        publishSnapshot()
        await ensureEffectiveEngine()
        operation = nil
        publishSnapshot()
    }

    func reconcileAvailability() async {
        let requiresExplicitBootstrapRetry = dictationBlocked
            && failure?.allowsBootstrapRetry == true
        reconcileAvailabilityFromAdapters()
        guard didStart else {
            publishSnapshot()
            return
        }
        guard operation == nil else {
            publishSnapshot()
            return
        }
        guard !requiresExplicitBootstrapRetry else {
            publishSnapshot()
            return
        }
        let targetID = effectiveTargetID()
        guard targetID != effectiveSelection || !availability.contains(targetID) else {
            publishSnapshot()
            return
        }
        failure = nil
        await ensureEffectiveEngine()
    }

    func select(_ id: String) async {
        if !didStart {
            await start()
        }
        guard operation == nil,
              activeDownload == nil,
              activeSelection == nil,
              id != storedSelection,
              availability.contains(id),
              adapter(for: id) != nil
        else { return }

        let operationID = UUID()
        let previousSelection = storedSelection
        let previousEffectiveSelection = effectiveSelection ?? effectiveTargetID()
        operation = .switching(modelID: id)
        failure = nil
        dictationBlocked = true
        _ = sessionCoordinator.beginBlockingSessions()
        publishSnapshot()
        let lifecycle = self
        let task = Task {
            await lifecycle.performSelection(
                id,
                previousSelection: previousSelection,
                previousEffectiveSelection: previousEffectiveSelection,
                operationID: operationID
            )
        }
        activeSelection = ActiveSelection(id: operationID, task: task)
        await task.value
    }

    private func performSelection(
        _ id: String,
        previousSelection: String,
        previousEffectiveSelection: String,
        operationID: UUID
    ) async {
        guard activeSelection?.id == operationID,
              let adapter = adapter(for: id) else { return }
        do {
            try await blockDictationThenReleaseEngineForSelection()
        } catch {
            storedSelection = previousSelection
            failure = .selectionCanceled(modelID: id)
            operation = nil
            activeSelection = nil
            publishSnapshot()
            return
        }
        publishSnapshot()

        var candidate: Transcribing?
        var candidateLoaded = false
        do {
            candidate = try adapter.makeEngine(for: id)
            guard let candidate else { return }
            try await candidate.prepare()
            candidateLoaded = true
            try Task.checkCancellation()
            guard activeSelection?.id == operationID else { throw CancellationError() }
            try await persistSelection(id)
            storedSelection = id
            engine = candidate
            effectiveSelection = id
            operation = nil
            dictationBlocked = false
            activeSelection = nil
            sessionCoordinator.activate(candidate, modelID: id)
            publishSnapshot()
        } catch {
            candidate = nil
            if !candidateLoaded, !(error is CancellationError) {
                rejectedEngineModelIDs.insert(id)
                reconcileAvailabilityFromAdapters()
            }
            let interruption: ASRModelLifecycleFailure = if error is CancellationError {
                .selectionCanceled(modelID: id)
            } else {
                .selectionFailed(modelID: id, reason: error.localizedDescription)
            }
            await restorePreviousSelection(
                previousSelection,
                effectiveSelection: previousEffectiveSelection,
                after: interruption
            )
        }
    }

    private func restorePreviousSelection(
        _ previousSelection: String,
        effectiveSelection previousEffectiveSelection: String,
        after interruption: ASRModelLifecycleFailure
    ) async {
        failure = interruption
        storedSelection = previousSelection
        operation = .restoring(modelID: previousEffectiveSelection)
        publishSnapshot()
        let restoration = Task { await self.ensureEffectiveEngine() }
        await restoration.value
        if effectiveSelection == previousEffectiveSelection {
            failure = interruption
        } else if effectiveSelection == ASRModelCatalog.defaultID {
            let restorationReason: String? = if case let .engineLoadFailed(_, reason) = failure {
                reason
            } else {
                nil
            }
            failure = .selectionDegraded(
                modelID: previousSelection,
                fallbackModelID: ASRModelCatalog.defaultID,
                reason: restorationReason
            )
        }
        operation = nil
        activeSelection = nil
        publishSnapshot()
    }

    func snapshots() -> AsyncStream<ASRModelLifecycleSnapshot> {
        let observerID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[observerID] = continuation
            continuation.yield(makeSnapshot())
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
        }
    }

    func download(_ id: String) async {
        guard operation == nil, activeDownload == nil, let adapter = adapter(for: id) else { return }
        let operationID = UUID()
        failure = nil
        operation = .downloading(modelID: id, fraction: nil)
        publishSnapshot()
        let lifecycle = self
        let task = Task {
            try await adapter.downloadModelData(for: id) { fraction in
                Task { await lifecycle.publishProgress(fraction, operationID: operationID) }
            }
        }
        activeDownload = ActiveDownload(id: operationID, modelID: id, task: task)

        let result = await task.result
        await finishDownload(operationID: operationID, modelID: id, result: result)
    }

    func delete(_ id: String) async {
        if !didStart {
            await start()
        }
        guard operation == nil,
              activeDownload == nil,
              activeSelection == nil,
              id != ASRModelCatalog.defaultID,
              let adapter = adapter(for: id)
        else { return }

        let deletesSelectedModel = id == storedSelection
        let deletesEffectiveEngine = id == effectiveSelection
        operation = .deleting(modelID: id)
        failure = nil

        if deletesSelectedModel {
            dictationBlocked = true
            _ = sessionCoordinator.beginBlockingSessions()
            publishSnapshot()
            do {
                try await persistSelection(ASRModelCatalog.defaultID)
                storedSelection = ASRModelCatalog.defaultID
            } catch {
                operation = nil
                failure = .deletionSelectionFailed(
                    modelID: id,
                    reason: error.localizedDescription
                )
                dictationBlocked = engine == nil
                sessionCoordinator.activate(engine, modelID: effectiveSelection)
                publishSnapshot()
                return
            }
        }
        publishSnapshot()

        if sessionCoordinator.hasActiveSessions(for: id) {
            await sessionCoordinator.waitForSessionsToDrain(modelID: id)
        }
        if deletesEffectiveEngine {
            await releaseEffectiveEngineForExclusiveOperation()
        }

        let deletionFailure: Error?
        do {
            try await adapter.removeModelData(for: id)
            deletionFailure = nil
        } catch {
            deletionFailure = error
        }
        reconcileAvailabilityFromAdapters()
        if deletesEffectiveEngine {
            await ensureEffectiveEngine()
        } else if deletesSelectedModel {
            dictationBlocked = engine == nil
            sessionCoordinator.activate(engine, modelID: effectiveSelection)
        }
        operation = nil
        if let deletionFailure, failure == nil {
            failure = .deletionFailed(modelID: id, reason: deletionFailure.localizedDescription)
        }
        publishSnapshot()
    }

    func cancelCurrentOperation() async {
        if let activeDownload {
            canceledDownloadIDs.insert(activeDownload.id)
            activeDownload.task.cancel()
            let result = await activeDownload.task.result
            await finishDownload(
                operationID: activeDownload.id,
                modelID: activeDownload.modelID,
                result: result
            )
        } else if let activeSelection {
            activeSelection.task.cancel()
            await activeSelection.task.value
        }
    }

    private func finishDownload(
        operationID: UUID,
        modelID: String,
        result: Result<Void, Error>
    ) async {
        guard activeDownload?.id == operationID else { return }
        activeDownload = nil
        operation = nil
        if case .success = result {
            rejectedEngineModelIDs.remove(modelID)
        }
        reconcileAvailabilityFromAdapters()
        let wasCanceled = canceledDownloadIDs.remove(operationID) != nil
        failure = if wasCanceled {
            nil
        } else {
            switch result {
            case .success where !availability.contains(modelID):
                .downloadedDataInvalid(modelID: modelID)
            case let .failure(error) where !(error is CancellationError):
                .downloadFailed(modelID: modelID, reason: error.localizedDescription)
            case .success, .failure:
                nil
            }
        }
        if failure == nil,
           didStart,
           modelID == storedSelection,
           availability.contains(modelID),
           modelID != effectiveSelection {
            await ensureEffectiveEngine()
        } else {
            publishSnapshot()
        }
    }

    private func reconcileAvailabilityFromAdapters() {
        availability = Set(ASRModelCatalog.entries.compactMap { entry in
            adapter(for: entry.id)?.isModelDataAvailable(for: entry.id) == true
                ? entry.id
                : nil
        }).subtracting(rejectedEngineModelIDs)
    }

    private func publishProgress(_ fraction: Double, operationID: UUID) {
        guard activeDownload?.id == operationID,
              case let .downloading(modelID, _) = operation else { return }
        operation = .downloading(
            modelID: modelID,
            fraction: min(max(fraction, 0), 1)
        )
        publishSnapshot()
    }

    private func publishBootstrapProgress(_ fraction: Double, operationID: UUID) {
        guard bootstrapOperationID == operationID,
              case .bootstrapping = operation else { return }
        operation = .bootstrapping(fraction: min(max(fraction, 0), 1))
        publishSnapshot()
    }

    func snapshot() -> ASRModelLifecycleSnapshot {
        makeSnapshot()
    }

    private func makeSnapshot() -> ASRModelLifecycleSnapshot {
        ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map {
                ASRModelDescriptor(entry: $0, isAvailable: availability.contains($0.id))
            },
            storedSelection: storedSelection,
            effectiveSelection: effectiveSelection,
            recovery: recovery,
            operation: operation,
            failure: failure,
            isDictationBlocked: dictationBlocked
        )
    }

    private var recovery: ASRModelLifecycleRecovery? {
        guard storedSelection != ASRModelCatalog.defaultID,
              availability.contains(ASRModelCatalog.defaultID) else { return nil }
        if let entry = ASRModelCatalog.entry(for: storedSelection) {
            guard !availability.contains(entry.id) else { return nil }
            return .storedSelectionUnavailable(
                modelID: storedSelection,
                fallbackModelID: ASRModelCatalog.defaultID
            )
        }
        return .storedSelectionUnknown(
            modelID: storedSelection,
            fallbackModelID: ASRModelCatalog.defaultID
        )
    }

    private func publishSnapshot() {
        let snapshot = makeSnapshot()
        for observer in observers.values {
            observer.yield(snapshot)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func adapter(for id: String) -> (any ASRModelFamilyAdapting)? {
        adapters.first { $0.modelIDs.contains(id) }
    }

    private func effectiveTargetID() -> String {
        guard let selectedID = ASRModelCatalog.entry(for: storedSelection)?.id,
              availability.contains(selectedID) else {
            return ASRModelCatalog.defaultID
        }
        return selectedID
    }
}

private final class ASRLifecycleSessionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var _isDictationBlocked = true
    private var engine: Transcribing?
    private var engineModelID: String?
    private var activeSessionCount = 0
    private var activeSessionCountsByModelID: [String: Int] = [:]
    private var sessionDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var modelSessionDrainWaiters: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var cancellableSessionDrainWaiters: [
        UUID: CheckedContinuation<Void, Error>
    ] = [:]
    var isDictationBlocked: Bool {
        lock.withLock { _isDictationBlocked }
    }

    func setDictationBlocked(_ blocked: Bool) {
        lock.withLock { _isDictationBlocked = blocked }
    }

    func activate(_ engine: Transcribing?, modelID: String?) {
        lock.withLock {
            self.engine = engine
            engineModelID = modelID
            _isDictationBlocked = engine == nil
        }
    }

    func beginBlockingSessions() -> Bool {
        lock.withLock {
            engine = nil
            engineModelID = nil
            _isDictationBlocked = true
            return activeSessionCount > 0
        }
    }

    func captureSession() throws -> any ASRSessionHandle {
        let capture = try lock.withLock { () throws -> (Transcribing, String) in
            guard !_isDictationBlocked, let engine, let engineModelID else {
                throw ASRModelLifecycleError.recognitionBlocked
            }
            activeSessionCount += 1
            activeSessionCountsByModelID[engineModelID, default: 0] += 1
            return (engine, engineModelID)
        }
        return ASRLifecycleSessionHandle(engine: capture.0) { [weak self] in
            self?.releaseSession(modelID: capture.1)
        }
    }

    func hasActiveSessions(for modelID: String) -> Bool {
        lock.withLock { activeSessionCountsByModelID[modelID, default: 0] > 0 }
    }

    func waitForSessionsToDrain() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard activeSessionCount > 0 else { return true }
                sessionDrainWaiters.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func waitForSessionsToDrain(modelID: String) async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                guard activeSessionCountsByModelID[modelID, default: 0] > 0 else { return true }
                modelSessionDrainWaiters[modelID, default: []].append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func waitForSessionsToDrainCancelable() async throws {
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                let shouldResume = lock.withLock {
                    guard activeSessionCount > 0 else { return true }
                    cancellableSessionDrainWaiters[waiterID] = continuation
                    return false
                }
                if shouldResume {
                    continuation.resume(returning: ())
                } else if Task.isCancelled {
                    cancelSessionDrainWaiter(waiterID)
                }
            }
        } onCancel: {
            self.cancelSessionDrainWaiter(waiterID)
        }
    }

    private func releaseSession(modelID: String) {
        let waiters = lock.withLock { () -> (
            [CheckedContinuation<Void, Never>],
            [CheckedContinuation<Void, Error>],
            [CheckedContinuation<Void, Never>]
        ) in
            activeSessionCount -= 1
            let remainingModelSessions = activeSessionCountsByModelID[modelID, default: 1] - 1
            let modelWaiters: [CheckedContinuation<Void, Never>]
            if remainingModelSessions == 0 {
                activeSessionCountsByModelID.removeValue(forKey: modelID)
                modelWaiters = modelSessionDrainWaiters.removeValue(forKey: modelID) ?? []
            } else {
                activeSessionCountsByModelID[modelID] = remainingModelSessions
                modelWaiters = []
            }
            guard activeSessionCount == 0 else { return ([], [], modelWaiters) }
            defer {
                sessionDrainWaiters.removeAll()
                cancellableSessionDrainWaiters.removeAll()
            }
            return (
                sessionDrainWaiters,
                Array(cancellableSessionDrainWaiters.values),
                modelWaiters
            )
        }
        for waiter in waiters.0 {
            waiter.resume()
        }
        for waiter in waiters.1 {
            waiter.resume(returning: ())
        }
        for waiter in waiters.2 {
            waiter.resume()
        }
    }

    private func cancelSessionDrainWaiter(_ id: UUID) {
        let waiter = lock.withLock {
            cancellableSessionDrainWaiters.removeValue(forKey: id)
        }
        waiter?.resume(throwing: CancellationError())
    }
}

private final class ASRLifecycleSessionHandle: ASRSessionHandle, @unchecked Sendable {
    private let lease: ASRLifecycleSessionLease

    init(engine: Transcribing, onRelease: @escaping () -> Void) {
        lease = ASRLifecycleSessionLease(engine: engine, onRelease: onRelease)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        try await lease.transcribe(samples)
    }

    func release() {
        lease.release()
    }

    deinit {
        lease.release()
    }
}

/// Keeps release state alive during handle deinitialization so the engine is dropped
/// before the session coordinator is notified.
private final class ASRLifecycleSessionLease: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: Transcribing?
    private var onRelease: (() -> Void)?

    init(engine: Transcribing, onRelease: @escaping () -> Void) {
        self.engine = engine
        self.onRelease = onRelease
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard let engine = lock.withLock({ engine }) else {
            throw ASRModelLifecycleError.recognitionBlocked
        }
        return try await engine.transcribe(samples)
    }

    func release() {
        let callback = lock.withLock { () -> (() -> Void)? in
            engine = nil
            defer { onRelease = nil }
            return onRelease
        }
        callback?()
    }
}
