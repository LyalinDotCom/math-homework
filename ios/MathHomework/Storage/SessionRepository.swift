import Foundation

/// Swift port of electron/storage/session-repository.ts. The archive layout is
/// identical to the desktop app's: one timestamped folder per session with
/// session.json plus pages/page-NNN.{jpg,json,transcription.json,verification.json}.
/// On iOS the root is the app's Documents folder, which UIFileSharingEnabled
/// exposes in the Files app as ordinary JPEG and JSON files.
struct SessionRepository {
    enum RepositoryError: LocalizedError {
        case invalidIdentifier
        case pageNotFound
        case exhaustedIdentifiers

        var errorDescription: String? {
            switch self {
            case .invalidIdentifier: return "Invalid session or page identifier"
            case .pageNotFound: return "Page not found"
            case .exhaustedIdentifiers: return "Could not allocate an identifier"
            }
        }
    }

    private static let archiveReadme = """
    Math Homework archive
    =====================

    Each timestamped folder is one session. session.json lists its pages.
    The pages folder keeps the original JPEG, the final locally graded JSON,
    and (for new scans) Gemini's transcription and verification JSON.

    These are ordinary UTF-8 JSON and JPEG files. You can copy or back up this
    folder without special software. Do not rename files referenced by session.json.

    """

    let root: URL

    init(root: URL? = nil) {
        self.root =
            root
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Paths

    private func sessionDirectory(_ id: String) throws -> URL {
        guard Contracts.isValidSessionId(id) else { throw RepositoryError.invalidIdentifier }
        return root.appendingPathComponent(id, isDirectory: true)
    }

    struct PagePaths {
        let image: URL
        let review: URL
        let transcription: URL
        let verification: URL
    }

    private func pagePaths(sessionId: String, pageId: String) throws -> PagePaths {
        let directory = try sessionDirectory(sessionId).appendingPathComponent(
            "pages", isDirectory: true
        )
        guard Contracts.isValidPageId(pageId) else { throw RepositoryError.invalidIdentifier }
        return PagePaths(
            image: directory.appendingPathComponent("\(pageId).jpg"),
            review: directory.appendingPathComponent("\(pageId).json"),
            transcription: directory.appendingPathComponent("\(pageId).transcription.json"),
            verification: directory.appendingPathComponent("\(pageId).verification.json")
        )
    }

    private func metadataPath(_ id: String) throws -> URL {
        try sessionDirectory(id).appendingPathComponent("session.json")
    }

    func imageURL(sessionId: String, pageId: String) throws -> URL {
        try pagePaths(sessionId: sessionId, pageId: pageId).image
    }

    // MARK: - JSON helpers

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        var data = try Self.encoder.encode(value)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    // MARK: - Session lifecycle

    private static func timestampId(_ date: Date) -> String {
        Timestamps.isoString(date)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let readme = root.appendingPathComponent("_README.txt")
        if !FileManager.default.fileExists(atPath: readme.path) {
            try Self.archiveReadme.write(to: readme, atomically: true, encoding: .utf8)
        }
    }

    func readMetadata(_ id: String) throws -> SessionMetadata {
        try readJSON(SessionMetadata.self, from: metadataPath(id))
    }

    func loadSession(_ id: String) throws -> Session {
        let metadata = try readMetadata(id)
        var pages: [SessionPage] = []
        for page in metadata.pages {
            try page.validateFileReferences()
            let paths = try pagePaths(sessionId: metadata.id, pageId: page.id)
            let review = Grader.gradeReview(try readJSON(Review.self, from: paths.review))
            pages.append(SessionPage(metadata: page, review: review, imageURL: paths.image))
        }
        return Session(metadata: metadata, pages: pages)
    }

    func createSession() throws -> Session {
        try ensureRoot()
        let started = Date()
        for offset in 0..<1_000 {
            let id = Self.timestampId(started.addingTimeInterval(Double(offset) / 1_000))
            let directory = try sessionDirectory(id)
            if FileManager.default.fileExists(atPath: directory.path) { continue }
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent("pages", isDirectory: true),
                withIntermediateDirectories: true
            )
            let metadata = SessionMetadata(
                schemaVersion: Contracts.sessionSchemaVersion,
                id: id,
                startedAt: Timestamps.isoString(started),
                endedAt: nil,
                pages: []
            )
            try writeJSON(metadata, to: metadataPath(id))
            return Session(metadata: metadata, pages: [])
        }
        throw RepositoryError.exhaustedIdentifiers
    }

    func resumeSession(_ id: String) throws -> Session {
        var metadata = try readMetadata(id)
        metadata.schemaVersion = Contracts.sessionSchemaVersion
        metadata.endedAt = nil
        metadata.resumedAt = (metadata.resumedAt ?? []) + [Timestamps.isoString()]
        try writeJSON(metadata, to: metadataPath(id))
        return try loadSession(id)
    }

    func endSession(_ id: String) throws {
        var metadata = try readMetadata(id)
        metadata.schemaVersion = Contracts.sessionSchemaVersion
        metadata.endedAt = Timestamps.isoString()
        try writeJSON(metadata, to: metadataPath(id))
    }

    // MARK: - Pages

    func preparePage(sessionId: String, jpegData: Data) throws -> PageMetadata {
        let metadata = try readMetadata(sessionId)
        var number = metadata.pages.map(\.number).max() ?? 0
        number += 1
        // A crash between preparePage and commitPage can leave an orphaned
        // JPEG that session.json never listed; skip past it instead of
        // failing on the same id forever.
        while number <= 999_999 {
            let id = "page-" + String(format: "%03d", number)
            let paths = try pagePaths(sessionId: sessionId, pageId: id)
            if FileManager.default.fileExists(atPath: paths.image.path) {
                number += 1
                continue
            }
            // Matches the desktop's "wx" open flag: fail rather than overwrite.
            try jpegData.write(to: paths.image, options: .withoutOverwriting)
            return PageMetadata(
                id: id,
                number: number,
                capturedAt: Timestamps.isoString(),
                imageFile: "pages/\(id).jpg",
                reviewFile: "pages/\(id).json",
                transcriptionFile: "pages/\(id).transcription.json",
                verificationFile: "pages/\(id).verification.json"
            )
        }
        throw RepositoryError.exhaustedIdentifiers
    }

    func commitPage(
        sessionId: String,
        page: PageMetadata,
        review: Review,
        transcription: Transcription,
        verification: HandwritingVerification
    ) throws {
        try page.validateFileReferences()
        let paths = try pagePaths(sessionId: sessionId, pageId: page.id)
        try writeJSON(transcription, to: paths.transcription)
        try writeJSON(verification, to: paths.verification)
        try writeJSON(review, to: paths.review)
        // Re-read at commit time: the OCR await between preparePage and here
        // can span minutes, and writing a stale snapshot back would clobber
        // any endedAt/resumedAt stamped meanwhile.
        var metadata = try readMetadata(sessionId)
        metadata.schemaVersion = Contracts.sessionSchemaVersion
        if !metadata.pages.contains(where: { $0.id == page.id }) {
            metadata.pages.append(page)
            metadata.pages.sort { $0.number < $1.number }
        }
        try writeJSON(metadata, to: metadataPath(sessionId))
    }

    // MARK: - Durable scan queue and independent-reading checkpoints

    private func pendingURL(sessionId: String, pageId: String) throws -> URL {
        guard Contracts.isValidPageId(pageId) else { throw RepositoryError.invalidIdentifier }
        return try sessionDirectory(sessionId).appendingPathComponent("pending", isDirectory: true)
            .appendingPathComponent(pageId + ".json")
    }

    func savePending(_ item: ScanItem) throws {
        try item.page.validateFileReferences()
        let url = try pendingURL(sessionId: item.sessionId, pageId: item.page.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeJSON(item, to: url)
    }

    func removePending(_ item: ScanItem) throws {
        let url = try pendingURL(sessionId: item.sessionId, pageId: item.page.id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func loadPending() throws -> [ScanItem] {
        try ensureRoot()
        var items: [ScanItem] = []
        for session in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let sessionId = session.lastPathComponent
            guard Contracts.isValidSessionId(sessionId), let metadata = try? readMetadata(sessionId) else { continue }
            let folder = session.appendingPathComponent("pending", isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "json" {
                do {
                    var item = try readJSON(ScanItem.self, from: file)
                    guard item.sessionId == sessionId, file.lastPathComponent == item.page.id + ".json" else {
                        throw RepositoryError.invalidIdentifier
                    }
                    try item.page.validateFileReferences()
                    // Commit may have succeeded just before the app stopped.
                    if item.isRecheck != true, metadata.pages.contains(where: { $0.id == item.page.id }) {
                        try removePending(item)
                        continue
                    }
                    if item.status == .processing { item.status = .waiting }
                    items.append(item)
                } catch {
                    OCRDiagnostics.record("pending_load_failed", fields: ["session": sessionId])
                }
            }
            // Recover originals left behind by the older in-memory queue, or
            // an interruption between saving an image and its queue record.
            let images = (try? FileManager.default.contentsOfDirectory(
                at: session.appendingPathComponent("pages"), includingPropertiesForKeys: nil
            )) ?? []
            for image in images where image.pathExtension == "jpg" {
                let id = image.deletingPathExtension().lastPathComponent
                guard Contracts.isValidPageId(id),
                      !metadata.pages.contains(where: { $0.id == id }),
                      !items.contains(where: { $0.sessionId == sessionId && $0.page.id == id }),
                      let number = Int(id.dropFirst(5)) else { continue }
                let page = PageMetadata(id: id, number: number, capturedAt: metadata.startedAt,
                    imageFile: "pages/\(id).jpg", reviewFile: "pages/\(id).json",
                    transcriptionFile: "pages/\(id).transcription.json", verificationFile: "pages/\(id).verification.json")
                let item = ScanItem(sessionId: sessionId, page: page)
                try savePending(item)
                items.append(item)
            }
        }
        return items.sorted { $0.id < $1.id }
    }

    private func readingURL(_ item: ScanItem, second: Bool) throws -> URL {
        let image = try imageURL(sessionId: item.sessionId, pageId: item.page.id)
        return image.deletingPathExtension().appendingPathExtension(second ? "reading-2.json" : "reading-1.json")
    }

    func saveReading(_ reading: Transcription, item: ScanItem, second: Bool) throws {
        try reading.validate()
        try writeJSON(reading, to: readingURL(item, second: second))
    }

    func loadReading(_ item: ScanItem, second: Bool) -> Transcription? {
        guard let url = try? readingURL(item, second: second),
              let reading = try? readJSON(Transcription.self, from: url),
              (try? reading.validate()) != nil else { return nil }
        return reading
    }

    func clearReadings(_ item: ScanItem) throws {
        for second in [false, true] {
            let url = try readingURL(item, second: second)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }

    func discardPending(_ item: ScanItem) throws {
        // Never remove a committed page when cleaning up a stale queue entry.
        guard !(try readMetadata(item.sessionId)).pages.contains(where: { $0.id == item.page.id }) else {
            try removePending(item)
            return
        }
        for second in [false, true] {
            let url = try readingURL(item, second: second)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        discardPreparedPage(sessionId: item.sessionId, pageId: item.page.id)
        try removePending(item)
    }

    func discardPreparedPage(sessionId: String, pageId: String) {
        guard let paths = try? pagePaths(sessionId: sessionId, pageId: pageId) else { return }
        for url in [paths.image, paths.review, paths.transcription, paths.verification] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func updateReview(sessionId: String, pageId: String, review: Review) throws -> Review {
        let metadata = try readMetadata(sessionId)
        guard metadata.pages.contains(where: { $0.id == pageId }) else {
            throw RepositoryError.pageNotFound
        }
        try writeJSON(review, to: pagePaths(sessionId: sessionId, pageId: pageId).review)
        return review
    }

    func listSessions() throws -> [Session] {
        try ensureRoot()
        let entries = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        )
        var sessions: [Session] = []
        for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { continue }
            do {
                sessions.append(try loadSession(entry.lastPathComponent))
            } catch {
                // Skip unreadable/foreign folders the same way the desktop does.
                continue
            }
        }
        return sessions
    }
}
