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

    fileprivate init(entry: ASRModelCatalog.Entry, isAvailable: Bool) {
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
}

enum ASRModelLifecycleFailure: Equatable {
    case downloadFailed(modelID: String, reason: String)
    case downloadedDataInvalid(modelID: String)
    case bootstrapFailed(reason: String)
    case engineLoadFailed(modelID: String, reason: String)

    var allowsBootstrapRetry: Bool {
        switch self {
        case .bootstrapFailed:
            true
        case let .engineLoadFailed(modelID, _):
            modelID == ASRModelCatalog.defaultID
        case .downloadFailed, .downloadedDataInvalid:
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

actor ASRModelLifecycle: Transcribing {
    private struct ActiveDownload {
        let id: UUID
        let modelID: String
        let task: Task<Void, Error>
    }

    private var storedSelection: String
    private let adapters: [any ASRModelFamilyAdapting]
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
    private var canceledDownloadIDs: Set<UUID> = []
    private var observers: [UUID: AsyncStream<ASRModelLifecycleSnapshot>.Continuation] = [:]
    nonisolated private let transcriberState = ASRLifecycleTranscriberState()

    init(
        storedSelection: String,
        adapters: [any ASRModelFamilyAdapting]
    ) {
        self.storedSelection = storedSelection
        self.adapters = adapters
    }

    nonisolated var ready: Bool {
        transcriberState.ready
    }

    nonisolated var isDictationBlocked: Bool {
        transcriberState.isDictationBlocked
    }

    nonisolated var onLoading: ((Bool) -> Void)? {
        get { transcriberState.onLoading }
        set { transcriberState.onLoading = newValue }
    }

    nonisolated var onDownloadProgress: ((Double) -> Void)? {
        get { transcriberState.onDownloadProgress }
        set { transcriberState.onDownloadProgress = newValue }
    }

    nonisolated func warmup() {
        Task { await start() }
    }

    func prepare() async throws {
        await start()
        guard !dictationBlocked else { throw ASRModelLifecycleError.recognitionBlocked }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        if !didStart { await start() }
        guard !dictationBlocked, let engine else {
            throw ASRModelLifecycleError.recognitionBlocked
        }
        return try await engine.transcribe(samples)
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        dictationBlocked = true
        transcriberState.setDictationBlocked(true)
        reconcileAvailabilityFromAdapters()
        guard availability.contains(ASRModelCatalog.defaultID) else {
            await bootstrapDefault()
            return
        }
        await loadEffectiveEngine()
    }

    func retryBootstrap() async {
        guard didStart, dictationBlocked, operation == nil else { return }
        rejectedEngineModelIDs.remove(ASRModelCatalog.defaultID)
        reconcileAvailabilityFromAdapters()
        if availability.contains(ASRModelCatalog.defaultID) {
            failure = nil
            await loadEffectiveEngine()
        } else {
            await bootstrapDefault()
        }
    }

    private func loadEffectiveEngine() async {
        await ensureEffectiveEngine()
    }

    private func ensureEffectiveEngine() async {
        guard !activationInProgress else {
            publishSnapshot()
            return
        }
        activationInProgress = true
        defer { activationInProgress = false }

        while true {
            let targetID = effectiveTargetID()
            guard availability.contains(targetID) else {
                blockDictationAndReleaseEngine()
                publishSnapshot()
                return
            }
            guard targetID != effectiveSelection || engine == nil else {
                dictationBlocked = false
                transcriberState.setReady(true)
                transcriberState.setDictationBlocked(false)
                publishSnapshot()
                return
            }

            blockDictationAndReleaseEngine()
            publishSnapshot()
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
                candidate.onLoading = { [transcriberState] in
                    transcriberState.notifyLoading($0)
                }
                candidate.onDownloadProgress = { [transcriberState] in
                    transcriberState.notifyDownloadProgress($0)
                }
                try await candidate.prepare()
                guard targetID == effectiveTargetID(), availability.contains(targetID) else {
                    continue
                }
                engine = candidate
                effectiveSelection = targetID
                dictationBlocked = false
                transcriberState.setReady(true)
                transcriberState.setDictationBlocked(false)
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

    private func blockDictationAndReleaseEngine() {
        dictationBlocked = true
        engine = nil
        effectiveSelection = nil
        transcriberState.setReady(false)
        transcriberState.setDictationBlocked(true)
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
        transcriberState.setDictationBlocked(true)
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
        operation = nil
        await loadEffectiveEngine()
    }

    func reconcileAvailability() async {
        let requiresExplicitBootstrapRetry = dictationBlocked
            && failure?.allowsBootstrapRetry == true
        reconcileAvailabilityFromAdapters()
        guard didStart else {
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

    func updateStoredSelection(_ id: String) async {
        storedSelection = id
        reconcileAvailabilityFromAdapters()
        guard didStart else {
            publishSnapshot()
            return
        }
        if case .bootstrapping = operation {
            publishSnapshot()
            return
        }
        let targetID = effectiveTargetID()
        guard targetID != effectiveSelection else {
            publishSnapshot()
            return
        }
        failure = nil
        await ensureEffectiveEngine()
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

    func cancelCurrentOperation() async {
        guard let activeDownload else { return }
        canceledDownloadIDs.insert(activeDownload.id)
        activeDownload.task.cancel()
        let result = await activeDownload.task.result
        await finishDownload(
            operationID: activeDownload.id,
            modelID: activeDownload.modelID,
            result: result
        )
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

private final class ASRLifecycleTranscriberState: @unchecked Sendable {
    private let lock = NSLock()
    private var _ready = false
    private var _isDictationBlocked = true
    private var _onLoading: ((Bool) -> Void)?
    private var _onDownloadProgress: ((Double) -> Void)?

    var ready: Bool {
        lock.withLock { _ready }
    }

    var isDictationBlocked: Bool {
        lock.withLock { _isDictationBlocked }
    }

    var onLoading: ((Bool) -> Void)? {
        get { lock.withLock { _onLoading } }
        set { lock.withLock { _onLoading = newValue } }
    }

    var onDownloadProgress: ((Double) -> Void)? {
        get { lock.withLock { _onDownloadProgress } }
        set { lock.withLock { _onDownloadProgress = newValue } }
    }

    func setReady(_ ready: Bool) {
        lock.withLock { _ready = ready }
    }

    func setDictationBlocked(_ blocked: Bool) {
        lock.withLock { _isDictationBlocked = blocked }
    }

    func notifyLoading(_ loading: Bool) {
        lock.withLock { _onLoading }?(loading)
    }

    func notifyDownloadProgress(_ fraction: Double) {
        lock.withLock { _onDownloadProgress }?(fraction)
    }
}
