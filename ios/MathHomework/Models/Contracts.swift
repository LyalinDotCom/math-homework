import Foundation

// Swift port of shared/contracts.ts. Field names and JSON layout must stay
// byte-compatible with the desktop archive (schemaVersion 2) so a synced
// folder opens identically in both apps.

enum Contracts {
    static let sessionSchemaVersion = 2
    static let sessionIdPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z$"#
    static let pageIdPattern = #"^page-\d{3,6}$"#

    static func isValidSessionId(_ id: String) -> Bool {
        id.range(of: sessionIdPattern, options: .regularExpression) != nil
    }

    static func isValidPageId(_ id: String) -> Bool {
        id.range(of: pageIdPattern, options: .regularExpression) != nil
    }
}

enum ContractError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

enum GradingMethod: String, Codable, Equatable {
    case localArithmetic = "local-arithmetic"
    case manualRequired = "manual-required"
}

struct TranscribedProblem: Codable, Equatable {
    var number: String
    var expression: String
    var studentAnswer: String
    var confidence: Double
}

struct Transcription: Codable, Equatable {
    var worksheetTitle: String
    var problems: [TranscribedProblem]

    func validate() throws {
        guard (1...500).contains(problems.count) else {
            throw ContractError.invalid("Transcription problem count is out of range")
        }
        guard worksheetTitle.count <= 500 else {
            throw ContractError.invalid("Worksheet title is too long")
        }
        for problem in problems {
            guard !problem.expression.isEmpty, problem.expression.count <= 500,
                  problem.number.count <= 500, problem.studentAnswer.count <= 200,
                  problem.confidence.isFinite, (0...1).contains(problem.confidence)
            else { throw ContractError.invalid("Transcription entry failed validation") }
        }
    }
}

struct HandwritingVerificationItem: Codable, Equatable {
    var index: Int
    var studentAnswer: String
    var confidence: Double
    var needsConfirmation: Bool
    var verificationNote: String
}

struct HandwritingVerification: Codable, Equatable {
    var problems: [HandwritingVerificationItem]

    func validate() throws {
        guard (1...500).contains(problems.count) else {
            throw ContractError.invalid("Verification problem count is out of range")
        }
        for problem in problems {
            guard (0...499).contains(problem.index), problem.studentAnswer.count <= 200,
                  problem.confidence.isFinite, (0...1).contains(problem.confidence),
                  problem.verificationNote.count <= 500
            else { throw ContractError.invalid("Verification entry failed validation") }
        }
    }
}

struct Problem: Codable, Equatable {
    var number: String
    var expression: String
    var studentAnswer: String
    var confidence: Double
    var correctAnswer: String
    var isCorrect: Bool
    var initialStudentAnswer: String?
    var handwritingVerified: Bool?
    var verificationNote: String?
    var gradingMethod: GradingMethod?
    var calculatedIsCorrect: Bool?
    var manualIsCorrect: Bool?
}

struct Review: Codable, Equatable {
    var schemaVersion: Int?
    var worksheetTitle: String
    var summary: String
    var problems: [Problem]
    var model: String?
    var reviewedAt: String?
    var editedAt: String?
    var reprocessedAt: String?
    var ocrPasses: Int?
    var verificationPasses: Int?
    var gradingMethod: GradingMethod?
}

struct PageMetadata: Codable, Equatable, Identifiable {
    var id: String
    var number: Int
    var capturedAt: String
    var imageFile: String
    var reviewFile: String
    var transcriptionFile: String?
    var verificationFile: String?

    func validateFileReferences() throws {
        guard Contracts.isValidPageId(id) else {
            throw ContractError.invalid("Invalid page identifier")
        }
        guard imageFile == "pages/\(id).jpg", reviewFile == "pages/\(id).json",
              transcriptionFile.map({ $0 == "pages/\(id).transcription.json" }) ?? true,
              verificationFile.map({ $0 == "pages/\(id).verification.json" }) ?? true
        else { throw ContractError.invalid("Unsafe file reference in \(id)") }
    }
}

struct SessionMetadata: Codable, Equatable {
    var schemaVersion: Int?
    var id: String
    var startedAt: String
    // Present in every archive file: null while the session is active. The
    // desktop Zod schema requires the key, so encode nil as an explicit null.
    var endedAt: String?
    var resumedAt: [String]?
    var pages: [PageMetadata]

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, startedAt, endedAt, resumedAt, pages
    }

    init(schemaVersion: Int?, id: String, startedAt: String, endedAt: String?,
         resumedAt: [String]? = nil, pages: [PageMetadata]) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.resumedAt = resumedAt
        self.pages = pages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
        id = try container.decode(String.self, forKey: .id)
        startedAt = try container.decode(String.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(String.self, forKey: .endedAt)
        resumedAt = try container.decodeIfPresent([String].self, forKey: .resumedAt)
        pages = try container.decode([PageMetadata].self, forKey: .pages)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
        try container.encodeIfPresent(resumedAt, forKey: .resumedAt)
        try container.encode(pages, forKey: .pages)
    }
}

/// A fully loaded page: archive metadata plus its review and image location.
struct SessionPage: Identifiable, Equatable {
    var metadata: PageMetadata
    var review: Review
    var imageURL: URL

    var id: String { metadata.id }
}

/// A fully loaded session as used by the UI.
struct Session: Identifiable, Equatable {
    var metadata: SessionMetadata
    var pages: [SessionPage]

    var id: String { metadata.id }
}

enum Timestamps {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        // Matches JavaScript's Date.toISOString(), which the archive uses.
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()

    static func isoString(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    static func parseISO(_ value: String) -> Date? {
        formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
