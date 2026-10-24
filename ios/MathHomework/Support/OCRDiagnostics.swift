import Foundation
import OSLog

/// Timings and error codes only: no key, worksheet text, or image contents.
enum OCRDiagnostics {
    private static let lock = NSLock()
    private static let logger = Logger(subsystem: "com.lyalin.mathhomework", category: "OCR")

    static func record(_ event: String, fields: [String: String] = [:]) {
        var record = fields
        record["event"] = event
        record["time"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: .sortedKeys),
              let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        data.append(0x0A)
        logger.info("\(String(data: data, encoding: .utf8) ?? event, privacy: .public)")
        lock.lock()
        defer { lock.unlock() }
        do {
            let folder = directory.appendingPathComponent("Diagnostics", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("ocr.jsonl")
            if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 2_000_000 {
                let previous = folder.appendingPathComponent("ocr.previous.jsonl")
                if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
                try FileManager.default.moveItem(at: file, to: previous)
            }
            if !FileManager.default.fileExists(atPath: file.path) {
                try data.write(to: file, options: .atomic)
            } else {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            }
        } catch {
            logger.error("Could not write OCR timing log")
        }
    }
}
