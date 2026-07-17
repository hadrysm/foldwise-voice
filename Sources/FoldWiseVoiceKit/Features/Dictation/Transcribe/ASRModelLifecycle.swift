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
    }
}

struct ASRModelLifecycleSnapshot: Equatable {
    let models: [ASRModelDescriptor]
    let storedSelection: String
    let operation: ASRModelLifecycleOperation?
    let failure: ASRModelLifecycleFailure?
    let isDictationBlocked: Bool
}

enum ASRModelLifecycleOperation: Equatable {
    case downloading(modelID: String, fraction: Double?)
}

enum ASRModelLifecycleFailure: Equatable {
    case downloadFailed(modelID: String, reason: String)
    case downloadedDataInvalid(modelID: String)
}

protocol ASRModelFamilyAdapting: Sendable {
    var modelIDs: Set<String> { get }
    func isModelDataAvailable(for id: String) -> Bool
    func downloadModelData(
        for id: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

actor ASRModelLifecycle {
    private struct ActiveDownload {
        let id: UUID
        let modelID: String
        let task: Task<Void, Error>
    }

    private var storedSelection: String
    private let adapters: [any ASRModelFamilyAdapting]
    private var availability: Set<String> = []
    private var operation: ASRModelLifecycleOperation?
    private var failure: ASRModelLifecycleFailure?
    private var activeDownload: ActiveDownload?
    private var canceledDownloadIDs: Set<UUID> = []
    private var observers: [UUID: AsyncStream<ASRModelLifecycleSnapshot>.Continuation] = [:]

    init(
        storedSelection: String,
        adapters: [any ASRModelFamilyAdapting]
    ) {
        self.storedSelection = storedSelection
        self.adapters = adapters
    }

    func reconcileAvailability() {
        reconcileAvailabilityFromAdapters()
        publishSnapshot()
    }

    func updateStoredSelection(_ id: String) {
        storedSelection = id
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
        guard activeDownload == nil, let adapter = adapter(for: id) else { return }
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
        finishDownload(operationID: operationID, modelID: id, result: result)
    }

    func cancelCurrentOperation() async {
        guard let activeDownload else { return }
        canceledDownloadIDs.insert(activeDownload.id)
        activeDownload.task.cancel()
        let result = await activeDownload.task.result
        finishDownload(
            operationID: activeDownload.id,
            modelID: activeDownload.modelID,
            result: result
        )
    }

    private func finishDownload(
        operationID: UUID,
        modelID: String,
        result: Result<Void, Error>
    ) {
        guard activeDownload?.id == operationID else { return }
        activeDownload = nil
        operation = nil
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
        publishSnapshot()
    }

    private func reconcileAvailabilityFromAdapters() {
        availability = Set(ASRModelCatalog.entries.compactMap { entry in
            adapter(for: entry.id)?.isModelDataAvailable(for: entry.id) == true
                ? entry.id
                : nil
        })
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

    func snapshot() -> ASRModelLifecycleSnapshot {
        makeSnapshot()
    }

    private func makeSnapshot() -> ASRModelLifecycleSnapshot {
        ASRModelLifecycleSnapshot(
            models: ASRModelCatalog.entries.map {
                ASRModelDescriptor(entry: $0, isAvailable: availability.contains($0.id))
            },
            storedSelection: storedSelection,
            operation: operation,
            failure: failure,
            isDictationBlocked: false
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
}
