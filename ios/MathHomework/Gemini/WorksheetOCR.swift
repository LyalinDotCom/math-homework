import Foundation

/// Swift port of electron/gemini/worksheet-ocr.ts: two independent OCR-only
/// passes (structured transcription, then a handwriting check), merged and
/// graded locally.
struct WorksheetOCR {
    static let geminiModel = "gemini-3.5-flash"

    let apiKey: String
    let model: String

    struct Analysis {
        let review: Review
        let transcription: Transcription
        let verification: HandwritingVerification
    }

    func review(jpegData: Data) async throws -> Analysis {
        let client = GeminiInteractionsClient(apiKey: apiKey, model: model)

        let transcriptionText = try await client.createStructuredInteraction(
            promptText: Prompts.transcription,
            jpegData: jpegData,
            schema: GeminiSchemas.parsed(GeminiSchemas.transcription),
            label: "transcription"
        )
        let transcription = try Self.decodeValidated(
            Transcription.self, from: transcriptionText, label: "transcription"
        )
        try transcription.validate()

        let firstPassJSON = String(
            data: try JSONEncoder().encode(transcription),
            encoding: .utf8
        ) ?? "{}"
        let verificationText = try await client.createStructuredInteraction(
            promptText: Prompts.verification(firstPassJSON: firstPassJSON),
            jpegData: jpegData,
            schema: GeminiSchemas.parsed(GeminiSchemas.verification),
            label: "handwriting verification"
        )
        let verification = try Self.decodeValidated(
            HandwritingVerification.self, from: verificationText, label: "handwriting verification"
        )
        try verification.validate()

        let review = try Self.buildReview(
            transcription: transcription,
            verification: verification,
            model: model
        )
        return Analysis(review: review, transcription: transcription, verification: verification)
    }

    private static func decodeValidated<T: Decodable>(
        _ type: T.Type,
        from text: String,
        label: String
    ) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw GeminiInteractionsClient.ClientError.emptyOutput(label)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw GeminiInteractionsClient.ClientError.api(
                "Gemini returned a malformed \(label)"
            )
        }
    }

    static func buildReview(
        transcription: Transcription,
        verification: HandwritingVerification,
        model: String,
        reviewedAt: String = Timestamps.isoString()
    ) throws -> Review {
        var byIndex: [Int: HandwritingVerificationItem] = [:]
        for item in verification.problems {
            byIndex[item.index] = item
        }
        guard byIndex.count == transcription.problems.count else {
            throw ContractError.invalid(
                "Gemini returned duplicate or missing handwriting verification entries"
            )
        }

        var problems: [Problem] = []
        for (index, transcribed) in transcription.problems.enumerated() {
            guard let check = byIndex[index] else {
                throw ContractError.invalid("Gemini did not verify problem \(index + 1)")
            }
            problems.append(
                Problem(
                    number: transcribed.number,
                    expression: transcribed.expression,
                    studentAnswer: check.studentAnswer,
                    confidence: check.confidence,
                    correctAnswer: "",
                    isCorrect: false,
                    initialStudentAnswer: transcribed.studentAnswer,
                    handwritingVerified: !check.needsConfirmation && check.confidence >= 0.85,
                    verificationNote: check.verificationNote
                )
            )
        }

        let review = Review(
            schemaVersion: Contracts.sessionSchemaVersion,
            worksheetTitle: transcription.worksheetTitle,
            summary: "",
            problems: problems,
            model: model,
            reviewedAt: reviewedAt,
            ocrPasses: 2,
            verificationPasses: 2,
            gradingMethod: .localArithmetic
        )
        return Grader.gradeReview(review)
    }
}
