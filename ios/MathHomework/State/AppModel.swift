import Foundation
import UIKit
import Observation

/// One scanned page moving through the OCR pipeline. Finished pages leave the
/// queue and become SessionPages on the active session.
struct ScanItem: Identifiable, Equatable {
    enum Status: Equatable {
        case waiting
        case processing
        case failed(String)
    }

    let id = UUID()
    let jpegData: Data
    var status: Status = .waiting
}

@MainActor
@Observable
final class AppModel {
    let repository = SessionRepository()

    private(set) var apiKey: String = ""
    var activeSession: Session?
    var scanQueue: [ScanItem] = []
    var history: [Session] = []
    var lastError: String?

    private var isProcessing = false

    var hasAPIKey: Bool { !apiKey.isEmpty }
    var isQueueBusy: Bool {
        scanQueue.contains { $0.status == .waiting || $0.status == .processing }
    }

    init() {
        KeychainStore.seedFromBundleIfNeeded()
        apiKey = KeychainStore.loadAPIKey()
    }

    func saveAPIKey(_ key: String) {
        KeychainStore.saveAPIKey(key)
        apiKey = KeychainStore.loadAPIKey()
    }

    // MARK: - Session lifecycle

    func startSession() {
        guard activeSession == nil else { return }
        do {
            activeSession = try repository.createSession()
            scanQueue = []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resumeSession(_ id: String) {
        do {
            activeSession = try repository.resumeSession(id)
            scanQueue = []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func endSession() {
        guard let session = activeSession else { return }
        // Drop anything unprocessed; captured pages that already committed
        // stay in the archive.
        scanQueue.removeAll()
        do {
            try repository.endSession(session.id)
        } catch {
            lastError = error.localizedDescription
        }
        activeSession = nil
        refreshHistory()
    }

    func refreshHistory() {
        do {
            history = try repository.listSessions()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Scan queue

    func enqueue(images: [UIImage]) {
        guard activeSession != nil else { return }
        Task {
            for image in images {
                do {
                    let jpeg = try await Task.detached(priority: .userInitiated) {
                        try ImageNormalizer.normalizedJPEG(from: image)
                    }.value
                    scanQueue.append(ScanItem(jpegData: jpeg))
                } catch {
                    scanQueue.append(
                        ScanItem(jpegData: Data(), status: .failed(error.localizedDescription))
                    )
                }
            }
            processQueueIfNeeded()
        }
    }

    func retry(itemId: UUID) {
        guard let index = scanQueue.firstIndex(where: { $0.id == itemId }),
              case .failed = scanQueue[index].status,
              !scanQueue[index].jpegData.isEmpty
        else { return }
        scanQueue[index].status = .waiting
        processQueueIfNeeded()
    }

    func discard(itemId: UUID) {
        scanQueue.removeAll { $0.id == itemId }
    }

    private func processQueueIfNeeded() {
        guard !isProcessing else { return }
        guard let item = scanQueue.first(where: { $0.status == .waiting }) else { return }
        isProcessing = true
        Task {
            await process(item: item)
            isProcessing = false
            processQueueIfNeeded()
        }
    }

    private func process(item: ScanItem) async {
        guard let session = activeSession,
              let index = scanQueue.firstIndex(where: { $0.id == item.id })
        else { return }
        scanQueue[index].status = .processing

        var prepared: PageMetadata?
        do {
            let page = try repository.preparePage(sessionId: session.id, jpegData: item.jpegData)
            prepared = page
            let ocr = WorksheetOCR(apiKey: apiKey, model: WorksheetOCR.geminiModel)
            let analysis = try await ocr.review(jpegData: item.jpegData)
            try repository.commitPage(
                sessionId: session.id,
                page: page,
                review: analysis.review,
                transcription: analysis.transcription,
                verification: analysis.verification
            )
            // The session may have been ended while OCR ran; the page is
            // safely on disk in its own session, so just drop the UI update.
            guard activeSession?.id == session.id else { return }
            let sessionPage = SessionPage(
                metadata: page,
                review: analysis.review,
                imageURL: try repository.imageURL(sessionId: session.id, pageId: page.id)
            )
            activeSession?.metadata.pages.append(page)
            activeSession?.pages.append(sessionPage)
            scanQueue.removeAll { $0.id == item.id }
            Haptics.success()
        } catch {
            if let page = prepared {
                repository.discardPreparedPage(sessionId: session.id, pageId: page.id)
            }
            if let queueIndex = scanQueue.firstIndex(where: { $0.id == item.id }) {
                scanQueue[queueIndex].status = .failed(error.localizedDescription)
            }
            Haptics.error()
        }
    }

    // MARK: - Reviews

    func saveReview(sessionId: String, pageId: String, review: Review) throws -> Review {
        var regraded = Grader.gradeReview(review)
        regraded.schemaVersion = Contracts.sessionSchemaVersion
        regraded.editedAt = Timestamps.isoString()
        let saved = try repository.updateReview(
            sessionId: sessionId, pageId: pageId, review: regraded
        )
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
