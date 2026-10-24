import Foundation
import UIKit
import Observation
import Network

@MainActor
@Observable
final class AppModel {
    let repository: SessionRepository
    private(set) var apiKey = ""
    var activeSession: Session?
    private(set) var scanQueue: [ScanItem] = []
    var history: [Session] = []
    var lastError: String?
    private(set) var isConnected = true
    private(set) var importingCount = 0

    @ObservationIgnored private var workers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let network = NWPathMonitor()
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var mayProcess = true
    @ObservationIgnored private var isActive = true

    static let concurrentPages = 3 // Two independent requests each; six total.
    var hasAPIKey: Bool { !apiKey.isEmpty }
    var currentQueue: [ScanItem] { scanQueue.filter { $0.sessionId == activeSession?.id } }
    var pendingSessionIds: [String] { Array(Set(scanQueue.map(\.sessionId))).sorted().reversed() }
    var isQueueBusy: Bool { importingCount > 0 || scanQueue.contains { $0.status == .waiting || $0.status == .processing } }

    init(repository: SessionRepository = SessionRepository()) {
        self.repository = repository
        KeychainStore.seedFromBundleIfNeeded()
        apiKey = KeychainStore.loadAPIKey()
        do { scanQueue = try repository.loadPending() }
        catch { lastError = "Could not restore unfinished scans: \(error.localizedDescription)" }
        network.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let reconnected = connected && !self.isConnected
                self.isConnected = connected
                if reconnected { self.retryFailed(automaticOnly: true) }
                self.schedule()
            }
        }
        network.start(queue: DispatchQueue(label: "com.lyalin.mathhomework.network"))
    }

    func saveAPIKey(_ key: String) {
        guard KeychainStore.saveAPIKey(key) else {
            lastError = "The key could not be saved to the Keychain. Try again."
            return
        }
        apiKey = KeychainStore.loadAPIKey()
        schedule()
    }

    func startSession() {
        guard activeSession == nil else { return }
        do { activeSession = try repository.createSession(); lastError = nil }
        catch { lastError = error.localizedDescription }
    }

    func resumeSession(_ id: String) {
        do {
            activeSession = try repository.resumeSession(id)
            lastError = nil
            schedule()
        } catch { lastError = error.localizedDescription }
    }

    func endSession() {
        guard let session = activeSession else { return }
        do { try repository.endSession(session.id) }
        catch { lastError = error.localizedDescription; return }
        // Closing a session never discards captured pages or its durable jobs.
        activeSession = nil
        refreshHistory()
    }

    func refreshHistory() {
        do { history = try repository.listSessions() }
        catch { lastError = error.localizedDescription }
    }

    @discardableResult
    func enqueue(images: [UIImage], replacing itemId: String? = nil) -> Task<Void, Never> {
        let sessionId = activeSession?.id
        importingCount += images.count
        beginBackgroundTime()
        return Task {
            guard let sessionId else { importingCount -= images.count; return }
            var replacementSaved = false
            for image in images {
                defer {
                    importingCount -= 1
                    if importingCount == 0, workers.isEmpty { endBackgroundTime() }
                }
                do {
                    let jpeg = try await Task.detached(priority: .userInitiated) {
                        try ImageNormalizer.normalizedJPEG(from: image)
                    }.value
                    let page = try repository.preparePage(sessionId: sessionId, jpegData: jpeg)
                    let item = ScanItem(sessionId: sessionId, page: page)
                    try repository.savePending(item)
                    scanQueue.append(item)
                    if !replacementSaved, let itemId {
                        replacementSaved = true
                        discard(itemId: itemId)
                    }
                    OCRDiagnostics.record("page_saved", fields: ["page": item.id])
                    schedule()
                } catch { lastError = "A page could not be saved: \(error.localizedDescription)" }
            }
        }
    }

    func retry(itemId: String, acceptQuality: Bool = false) {
        guard let index = scanQueue.firstIndex(where: { $0.id == itemId }), workers[itemId] == nil else { return }
        if case .qualityWarning = scanQueue[index].status, !acceptQuality { return }
        var item = scanQueue[index]
        item.status = .waiting
        item.retryWhenConnected = false
        if acceptQuality { item.qualityChecked = true }
        guard persist(item) else {
            item.status = .failed("Scan progress could not be saved. Free space and retry.")
            update(item)
            return
        }
        scanQueue[index] = item
        schedule()
    }

    func retryFailed(automaticOnly: Bool = false) {
        let ids = scanQueue.filter {
            if case .failed = $0.status { return !automaticOnly || $0.retryWhenConnected }
            return false
        }.map(\.id)
        for id in ids { retry(itemId: id) }
    }

    func recheckPage(sessionId: String, page: SessionPage) {
        var item = ScanItem(sessionId: sessionId, page: page.metadata)
        guard !scanQueue.contains(where: { $0.id == item.id }) else { resumeSession(sessionId); return }
        item.isRecheck = true
        do {
            try repository.clearReadings(item)
            try repository.savePending(item)
            scanQueue.append(item)
            resumeSession(sessionId)
        } catch { lastError = "Could not queue another reading: \(error.localizedDescription)" }
    }

    func discard(itemId: String) {
        guard let item = scanQueue.first(where: { $0.id == itemId }), workers[itemId] == nil else { return }
        do {
            try repository.discardPending(item)
            scanQueue.removeAll { $0.id == itemId }
        } catch { lastError = "The page could not be removed: \(error.localizedDescription)" }
    }

    func imageURL(for item: ScanItem) -> URL? {
        try? repository.imageURL(sessionId: item.sessionId, pageId: item.page.id)
    }

    func sceneBecameActive() {
        isActive = true
        mayProcess = true
        endBackgroundTime()
        retryFailed(automaticOnly: true)
        schedule()
    }

    func sceneEnteredBackground() {
        isActive = false
        beginBackgroundTime()
    }

    private func beginBackgroundTime() {
        guard !isActive, (!workers.isEmpty || importingCount > 0), backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish worksheet readings") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.mayProcess = false
                for task in self.workers.values { task.cancel() }
                self.endBackgroundTime()
                OCRDiagnostics.record("background_paused")
            }
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func persist(_ item: ScanItem) -> Bool {
        do { try repository.savePending(item); return true }
        catch { lastError = "Could not save scan progress: \(error.localizedDescription)"; return false }
    }

    private func schedule() {
        guard mayProcess, isConnected, hasAPIKey else { return }
        for item in scanQueue where item.status == .waiting && workers[item.id] == nil {
            guard workers.count < Self.concurrentPages else { break }
            workers[item.id] = Task { [weak self] in
                guard let self else { return }
                await self.process(item)
                self.workers[item.id] = nil
                if self.workers.isEmpty, self.importingCount == 0 { self.endBackgroundTime() }
                self.schedule()
            }
        }
        beginBackgroundTime()
    }

    private func update(_ item: ScanItem) {
        guard let index = scanQueue.firstIndex(where: { $0.id == item.id }) else { return }
        scanQueue[index] = item
    }

    private func process(_ original: ScanItem) async {
        var item = original
        item.status = .processing
        guard persist(item) else {
            item.status = .failed("Scan progress could not be saved. Free space and retry.")
            update(item)
            return
        }
        update(item)
        let started = Date()
        do {
            guard let url = imageURL(for: item) else { throw SessionRepository.RepositoryError.invalidIdentifier }
            let jpeg = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
            try Task.checkCancellation()
            if !item.qualityChecked {
                let quality = try await Task.detached(priority: .userInitiated) {
                    try ImageQualityAnalyzer.assess(jpeg)
                }.value
                try Task.checkCancellation()
                if let warning = quality.warning {
                    item.status = .qualityWarning(warning)
                    try repository.savePending(item)
                    update(item)
                    return
                }
                item.qualityChecked = true
                try repository.savePending(item)
                update(item)
            }
            let first = repository.loadReading(item, second: false)
            let second = repository.loadReading(item, second: true)
            item.completedReadings = (first == nil ? 0 : 1) + (second == nil ? 0 : 1)
            update(item)
            let job = item
            let analysis = try await WorksheetOCR(apiKey: apiKey, model: WorksheetOCR.geminiModel).review(
                jpegData: jpeg, firstReading: first, secondReading: second, context: item.id
            ) { [self] reading, second in
                try Task.checkCancellation()
                try await saveCheckpoint(reading, item: job, second: second)
            }
            try Task.checkCancellation()
            try repository.commitPage(sessionId: item.sessionId, page: item.page, review: analysis.review,
                transcription: analysis.transcription, verification: analysis.verification)
            try repository.removePending(item)
            scanQueue.removeAll { $0.id == item.id }
            if activeSession?.id == item.sessionId { activeSession = try repository.loadSession(item.sessionId) }
            refreshHistory()
            Haptics.success()
            OCRDiagnostics.record("page_completed", fields: ["page": item.id,
                "duration_ms": String(Int(Date().timeIntervalSince(started) * 1_000)),
                "problems": String(analysis.review.problems.count)])
        } catch {
            if let current = scanQueue.first(where: { $0.id == item.id }) { item = current }
            if Task.isCancelled || error is CancellationError {
                item.status = .waiting
            } else {
                item.status = .failed(error.localizedDescription)
                item.retryWhenConnected = GeminiInteractionsClient.canRetryAutomatically(error)
                Haptics.error()
            }
            _ = persist(item)
            update(item)
            OCRDiagnostics.record("page_paused", fields: ["page": item.id, "error_code": String((error as NSError).code)])
        }
    }

    private func saveCheckpoint(_ reading: Transcription, item: ScanItem, second: Bool) throws {
        try repository.saveReading(reading, item: item, second: second)
        if var current = scanQueue.first(where: { $0.id == item.id }) {
            current.completedReadings = (repository.loadReading(item, second: false) == nil ? 0 : 1)
                + (repository.loadReading(item, second: true) == nil ? 0 : 1)
            try repository.savePending(current)
            update(current)
        }
    }

    func saveReview(sessionId: String, pageId: String, review: Review) throws -> Review {
        var regraded = Grader.gradeReview(review)
        regraded.schemaVersion = Contracts.sessionSchemaVersion
        regraded.editedAt = Timestamps.isoString()
        let saved = try repository.updateReview(sessionId: sessionId, pageId: pageId, review: regraded)
        if activeSession?.id == sessionId,
           let index = activeSession?.pages.firstIndex(where: { $0.id == pageId }) {
            activeSession?.pages[index].review = saved
        }
        if let sessionIndex = history.firstIndex(where: { $0.id == sessionId }),
           let pageIndex = history[sessionIndex].pages.firstIndex(where: { $0.id == pageId }) {
            history[sessionIndex].pages[pageIndex].review = saved
        }
        return saved
    }
}
