import Foundation

/// Stored next to the original scan before any network work begins.
struct ScanItem: Identifiable, Equatable, Codable {
    enum Status: Equatable, Codable {
        case waiting
        case processing
        case failed(String)
        case qualityWarning(String)
    }

    var id: String { sessionId + "/" + page.id }
    let sessionId: String
    let page: PageMetadata
    var status: Status = .waiting
    var qualityChecked = false
    var completedReadings = 0
    var retryWhenConnected = false
    var isRecheck: Bool?
}
