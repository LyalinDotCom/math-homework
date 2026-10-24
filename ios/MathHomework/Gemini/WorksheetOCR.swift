import Foundation

/// Two independent OCR-only readings run together, then are reconciled by
/// printed problem number and graded locally. Successful readings are cached.
struct WorksheetOCR {
    static let geminiModel = "gemini-3.8-flash"

    let apiKey: String
    let model: String
    var sessionOverride: URLSession? = nil

    struct Analysis {
        let review: Review
        let transcription: Transcription
        let verification: HandwritingVerification
    }

    func review(
        jpegData: Data,
        firstReading: Transcription? = nil,
        secondReading: Transcription? = nil,
        context: String = "worksheet",
        checkpoint: @escaping @Sendable (Transcription, Bool) async throws -> Void = { _, _ in }
    ) async throws -> Analysis {
        // Neither reader sees the other's output. Starting together both
        // removes first-pass anchoring and avoids a second serial API wait.
        async let first = read(jpegData: jpegData, cached: firstReading, second: false,
                               context: context, checkpoint: checkpoint)
        async let second = read(jpegData: jpegData, cached: secondReading, second: true,
                                context: context, checkpoint: checkpoint)
        let (transcription, independent) = try await (first, second)
        let verification = Self.reconcile(first: transcription, second: independent)
        var review = try Self.buildReview(transcription: transcription, verification: verification, model: model)
        // A disagreement about the printed problem cannot receive an automatic
        // grade. Correcting the expression in Review clears this requirement.
        for index in review.problems.indices {
            if verification.problems[index].verificationNote.hasPrefix("Printed problem differs") {
                review.problems[index].requiresExpressionConfirmation = true
            }
        }
        review = Grader.gradeReview(review)
        return Analysis(review: review, transcription: transcription, verification: verification)
    }

    private func read(
        jpegData: Data, cached: Transcription?, second: Bool, context: String,
        checkpoint: @escaping @Sendable (Transcription, Bool) async throws -> Void
    ) async throws -> Transcription {
        if let cached { return cached }
        let label = second ? "independent-reading" : "first-reading"
        let text = try await GeminiInteractionsClient(apiKey: apiKey, model: model, sessionOverride: sessionOverride).createStructuredInteraction(
            promptText: Prompts.transcription + (second ? "\n\nINDEPENDENT CHECK: Inspect every printed operand and the actual pencil strokes particularly carefully. Do not reconstruct handwriting from what would make the equation correct." : ""),
            jpegData: jpegData, schema: GeminiSchemas.parsed(GeminiSchemas.transcription),
            label: label, context: context
        )
        let reading = try Self.decodeValidated(Transcription.self, from: text, label: label)
        try reading.validate()
        try await checkpoint(reading, second)
        return reading
    }

    static func reconcile(first: Transcription, second: Transcription) -> HandwritingVerification {
        func identity(_ value: String) -> String {
            value.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        func expressionKey(_ value: String) -> String {
            value.replacingOccurrences(of: #"(?:\[\s*\]\s*)+"#, with: "?", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }
        let byNumber = Dictionary(grouping: second.problems, by: { identity($0.number) })
        let firstCounts = Dictionary(grouping: first.problems, by: { identity($0.number) })
        var result = first.problems.enumerated().map { index, initial in
            let id = identity(initial.number)
            let candidates = byNumber[id] ?? []
            guard !id.isEmpty, candidates.count == 1, firstCounts[id]?.count == 1,
                  let check = candidates.first else {
                return HandwritingVerificationItem(index: index, studentAnswer: initial.studentAnswer,
                    confidence: min(initial.confidence, 0.5), needsConfirmation: true,
                    verificationNote: "The independent reading could not uniquely match this problem. Confirm against the scan.")
            }
            let expressionMatches = expressionKey(initial.expression) == expressionKey(check.expression)
            let answerMatches = initial.studentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                == check.studentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let confidence = min(initial.confidence, check.confidence)
            return HandwritingVerificationItem(index: index, studentAnswer: check.studentAnswer,
                confidence: confidence, needsConfirmation: !expressionMatches || !answerMatches || confidence < 0.85,
                verificationNote: !expressionMatches
                    ? "Printed problem differs between readings: \(check.expression). Confirm the expression."
                    : (!answerMatches ? "Independent readings disagree about the handwriting. Confirm against the scan." : ""))
        }
        if second.problems.count != first.problems.count {
            for index in result.indices {
                result[index].needsConfirmation = true
                if !result[index].verificationNote.hasPrefix("Printed problem differs") {
                    result[index].verificationNote = "The readings found different problem counts. Check that the whole page was captured."
                }
            }
        }
        return HandwritingVerification(problems: result)
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
