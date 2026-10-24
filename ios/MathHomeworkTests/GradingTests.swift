import XCTest
import UIKit
import CoreImage
@testable import MathHomework

final class GeminiSchemaTests: XCTestCase {
    func testEmbeddedSchemasAreValid() {
        for schema in [GeminiSchemas.transcription, GeminiSchemas.verification] {
            XCTAssertEqual(GeminiSchemas.parsed(schema)["type"] as? String, "object")
        }
    }

    func testInvalidSchemaLogsAndReturnsWithoutTrapping() {
        XCTAssertTrue(GeminiSchemas.parsed("invalid JSON").isEmpty)
    }
}

/// Mirror of tests/grading.test.ts so the Swift grader stays in lockstep with
/// the desktop implementation.
final class GradingTests: XCTestCase {
    func testKeepsOCRTextSeparateFromCalculatedAnswer() {
        let wrong = Grader.gradeLocally(expression: "13 + 4", studentAnswer: "7", manualIsCorrect: nil)
        XCTAssertEqual(wrong.correctAnswer, "17")
        XCTAssertFalse(wrong.isCorrect)

        let right = Grader.gradeLocally(expression: "13 + 4", studentAnswer: "17", manualIsCorrect: nil)
        XCTAssertEqual(right.correctAnswer, "17")
        XCTAssertTrue(right.isCorrect)
    }

    func testWorksheetOperatorsPrecedenceImplicitMultiplicationAndFractions() {
        XCTAssertTrue(Grader.gradeLocally(expression: "12 × 3", studentAnswer: "36", manualIsCorrect: nil).isCorrect)
        XCTAssertTrue(Grader.gradeLocally(expression: "(20 - 8) ÷ 3", studentAnswer: "4", manualIsCorrect: nil).isCorrect)
        XCTAssertTrue(Grader.gradeLocally(expression: "2(3 + 4)", studentAnswer: "14", manualIsCorrect: nil).isCorrect)

        let fractions = Grader.gradeLocally(expression: "1/3 + 1/6", studentAnswer: "1/2", manualIsCorrect: nil)
        XCTAssertEqual(fractions.correctAnswer, "1/2")
        XCTAssertTrue(fractions.isCorrect)
    }

    func testExactDecimalArithmetic() {
        let outcome = Grader.gradeLocally(expression: "0.1 + 0.2", studentAnswer: "0.3", manualIsCorrect: nil)
        XCTAssertEqual(outcome.correctAnswer, "0.3")
        XCTAssertTrue(outcome.isCorrect)
    }

    func testRejectsSymbolsAssignmentsFunctionsAndUnreasonablePowers() {
        for expression in ["x + 1", "a = 4", "sqrt(4)", "2^1000"] {
            let outcome = Grader.gradeLocally(expression: expression, studentAnswer: "2", manualIsCorrect: nil)
            XCTAssertEqual(outcome.gradingMethod, .manualRequired, "expected manual for \(expression)")
        }
    }

    func testAmbiguousSpacingGoesToManualReview() {
        XCTAssertEqual(
            Grader.gradeLocally(expression: "2 1/2 + 1/2", studentAnswer: "3", manualIsCorrect: nil).gradingMethod,
            .manualRequired
        )
        XCTAssertEqual(
            Grader.gradeLocally(expression: "13 + 4", studentAnswer: "1 7", manualIsCorrect: nil).gradingMethod,
            .manualRequired
        )
    }

    func testParenthesizedAndNegativeConstantExponents() {
        XCTAssertTrue(Grader.gradeLocally(expression: "2^(3)", studentAnswer: "8", manualIsCorrect: nil).isCorrect)

        let negative = Grader.gradeLocally(expression: "2^-3", studentAnswer: "1/8", manualIsCorrect: nil)
        XCTAssertEqual(negative.correctAnswer, "1/8")
        XCTAssertTrue(negative.isCorrect)
    }

    func testManualOverridePersistsForUnsupportedWork() {
        let outcome = Grader.gradeLocally(expression: "x + 1", studentAnswer: "4", manualIsCorrect: true)
        XCTAssertNil(outcome.calculatedIsCorrect)
        XCTAssertEqual(outcome.manualIsCorrect, true)
        XCTAssertTrue(outcome.isCorrect)
        XCTAssertEqual(outcome.gradingMethod, .manualRequired)
    }

    func testNormalizesCommonOCROperatorVariants() {
        XCTAssertEqual(MathExpression.normalize("1,200 − 200 ="), "1200-200")
    }

    func testUnaryMinusBindsLooserThanExponent() {
        // mathjs parity: -2^2 == -(2^2)
        let outcome = Grader.gradeLocally(expression: "-2^2", studentAnswer: "-4", manualIsCorrect: nil)
        XCTAssertEqual(outcome.correctAnswer, "-4")
        XCTAssertTrue(outcome.isCorrect)
    }

    func testDivisionByZeroRequiresManualReview() {
        XCTAssertEqual(
            Grader.gradeLocally(expression: "5 / 0", studentAnswer: "0", manualIsCorrect: nil).gradingMethod,
            .manualRequired
        )
    }
}

final class BuildReviewTests: XCTestCase {
    func testMergesVerificationAndGradesLocally() throws {
        let transcription = Transcription(
            worksheetTitle: "Addition Practice",
            problems: [
                TranscribedProblem(number: "1", expression: "13 + 4 =", studentAnswer: "17", confidence: 0.98),
                TranscribedProblem(number: "2", expression: "9 - 3 =", studentAnswer: "7", confidence: 0.6),
            ]
        )
        let verification = HandwritingVerification(problems: [
            HandwritingVerificationItem(
                index: 0, studentAnswer: "17", confidence: 0.97,
                needsConfirmation: false, verificationNote: ""
            ),
            HandwritingVerificationItem(
                index: 1, studentAnswer: "1", confidence: 0.55,
                needsConfirmation: true, verificationNote: "Overlaps the printed line."
            ),
        ])

        let review = try WorksheetOCR.buildReview(
            transcription: transcription,
            verification: verification,
            model: "gemini-3.5-flash"
        )

        XCTAssertEqual(review.summary, "1 of 2 answers correct.")
        XCTAssertEqual(review.problems[0].isCorrect, true)
        XCTAssertEqual(review.problems[0].handwritingVerified, true)
        // The verifier's reading replaces the first pass and the original is kept.
        XCTAssertEqual(review.problems[1].studentAnswer, "1")
        XCTAssertEqual(review.problems[1].initialStudentAnswer, "7")
        XCTAssertEqual(review.problems[1].handwritingVerified, false)
        XCTAssertEqual(review.problems[1].correctAnswer, "6")
        XCTAssertEqual(review.problems[1].isCorrect, false)
    }

    func testRejectsDuplicateVerificationIndexes() {
        let transcription = Transcription(
            worksheetTitle: "",
            problems: [
                TranscribedProblem(number: "1", expression: "1 + 1", studentAnswer: "2", confidence: 1),
                TranscribedProblem(number: "2", expression: "2 + 2", studentAnswer: "4", confidence: 1),
            ]
        )
        let verification = HandwritingVerification(problems: [
            HandwritingVerificationItem(index: 0, studentAnswer: "2", confidence: 1, needsConfirmation: false, verificationNote: ""),
            HandwritingVerificationItem(index: 0, studentAnswer: "2", confidence: 1, needsConfirmation: false, verificationNote: ""),
        ])
        XCTAssertThrowsError(
            try WorksheetOCR.buildReview(
                transcription: transcription, verification: verification, model: "m"
            )
        )
    }
}

final class SessionRepositoryTests: XCTestCase {
    func testSessionRoundTripMatchesArchiveLayout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = SessionRepository(root: root)

        let session = try repository.createSession()
        XCTAssertTrue(Contracts.isValidSessionId(session.id))

        // A JPEG-ish payload above the 1 KB floor.
        var jpeg = Data([0xFF, 0xD8, 0xFF])
        jpeg.append(Data(repeating: 0x11, count: 2_000))
        let page = try repository.preparePage(sessionId: session.id, jpegData: jpeg)
        XCTAssertEqual(page.id, "page-001")

        let review = try WorksheetOCR.buildReview(
            transcription: Transcription(
                worksheetTitle: "T",
                problems: [
                    TranscribedProblem(number: "1", expression: "2 + 2", studentAnswer: "4", confidence: 1)
                ]
            ),
            verification: HandwritingVerification(problems: [
                HandwritingVerificationItem(
                    index: 0, studentAnswer: "4", confidence: 1,
                    needsConfirmation: false, verificationNote: ""
                )
            ]),
            model: "gemini-3.5-flash"
        )
        try repository.commitPage(
            sessionId: session.id,
            page: page,
            review: review,
            transcription: Transcription(
                worksheetTitle: "T",
                problems: [TranscribedProblem(number: "1", expression: "2 + 2", studentAnswer: "4", confidence: 1)]
            ),
            verification: HandwritingVerification(problems: [
                HandwritingVerificationItem(
                    index: 0, studentAnswer: "4", confidence: 1,
                    needsConfirmation: false, verificationNote: ""
                )
            ])
        )

        let loaded = try repository.loadSession(session.id)
        XCTAssertEqual(loaded.pages.count, 1)
        XCTAssertEqual(loaded.pages[0].review.summary, "1 of 1 answers correct.")

        // The metadata file must keep endedAt as an explicit null while active.
        let metadataText = try String(
            contentsOf: root.appendingPathComponent("\(session.id)/session.json"),
            encoding: .utf8
        )
        XCTAssertTrue(metadataText.contains("\"endedAt\" : null"))

        try repository.endSession(session.id)
        let listed = try repository.listSessions()
        XCTAssertEqual(listed.count, 1)
        XCTAssertNotNil(listed[0].metadata.endedAt)
    }
}

final class WorksheetFormTests: XCTestCase {
    func testMissingNumbersFromPhoneArchive() {
        for (expression, student, expected, correct) in [
            ("12 + [ ] = 34", "22", "22", true),
            ("62 + [ ][ ] = 99", "37", "37", true),
            ("63 + [ ][ ] = 120", "87", "57", false),
            ("[] - 7 = 12", "19", "19", true),
            ("30 - [] = 12", "18", "18", true),
            ("4 * [] = 24", "6", "6", true),
            ("24 / [] = 6", "4", "4", true),
            ("[] / 4 = 6", "24", "24", true),
            ("5 + 7 = []", "12", "12", true)
        ] {
            let result = Grader.gradeLocally(expression: expression, studentAnswer: student, manualIsCorrect: nil)
            XCTAssertEqual(result.correctAnswer, expected, expression)
            XCTAssertEqual(result.isCorrect, correct, expression)
        }
    }

    func testSequencesDoNotInferPatternFromStudentAnswer() {
        let correct = Grader.gradeLocally(expression: "98, 100, 102, [ ], [ ]", studentAnswer: "104, 106", manualIsCorrect: nil)
        XCTAssertTrue(correct.isCorrect)
        let wrong = Grader.gradeLocally(expression: "370, 400, 430, [ ], [ ]", studentAnswer: "360, 390", manualIsCorrect: nil)
        XCTAssertFalse(wrong.isCorrect)
        XCTAssertEqual(wrong.correctAnswer, "460, 490")
        for expression in ["1, 2, 4, [], []", "1, 2, [], []", "[] * 0 = 0", "0 / [] = 0", "[] / 0 = 3"] {
            XCTAssertEqual(Grader.gradeLocally(expression: expression, studentAnswer: "0", manualIsCorrect: nil).gradingMethod,
                .manualRequired, expression)
        }
    }

    func testIndependentReadingsMatchProblemNumbersAcrossColumnOrder() {
        let first = Transcription(worksheetTitle: "", problems: [
            .init(number: "(1)", expression: "12 + [] = 34", studentAnswer: "22", confidence: 0.95),
            .init(number: "(5)", expression: "5 + 5", studentAnswer: "10", confidence: 0.98)
        ])
        let second = Transcription(worksheetTitle: "", problems: [
            .init(number: "5", expression: "5+5=", studentAnswer: "10", confidence: 0.98),
            .init(number: "1", expression: "12 + [ ][ ] = 34", studentAnswer: "21", confidence: 0.95)
        ])
        let check = WorksheetOCR.reconcile(first: first, second: second)
        XCTAssertEqual(check.problems.map(\.studentAnswer), ["21", "10"])
        XCTAssertTrue(check.problems[0].needsConfirmation)
        XCTAssertFalse(check.problems[1].needsConfirmation)
    }

    func testPrintedOperandDisagreementRequiresReview() {
        let first = Transcription(worksheetTitle: "", problems: [
            .init(number: "1", expression: "12 + 3", studentAnswer: "15", confidence: 0.95)
        ])
        let second = Transcription(worksheetTitle: "", problems: [
            .init(number: "1", expression: "12 + 8", studentAnswer: "15", confidence: 0.95)
        ])
        let check = WorksheetOCR.reconcile(first: first, second: second)
        XCTAssertTrue(check.problems[0].needsConfirmation)
        XCTAssertTrue(check.problems[0].verificationNote.hasPrefix("Printed problem differs"))
    }
}

final class PendingScanTests: XCTestCase {
    private func repository() -> SessionRepository {
        SessionRepository(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    }

    func testRestartRestoresImageAndCompletedReading() throws {
        let repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        let session = try repo.createSession()
        let page = try repo.preparePage(sessionId: session.id, jpegData: Data(repeating: 3, count: 2_000))
        var job = ScanItem(sessionId: session.id, page: page)
        job.status = .processing
        try repo.savePending(job)
        let reading = Transcription(worksheetTitle: "", problems: [
            .init(number: "1", expression: "12+3", studentAnswer: "15", confidence: 0.9)
        ])
        try repo.saveReading(reading, item: job, second: false)
        let restarted = SessionRepository(root: repo.root)
        let recovered = try XCTUnwrap(restarted.loadPending().first)
        XCTAssertEqual(recovered.status, .waiting)
        XCTAssertEqual(restarted.loadReading(recovered, second: false), reading)
        XCTAssertNil(restarted.loadReading(recovered, second: true))
        XCTAssertEqual(try Data(contentsOf: restarted.imageURL(sessionId: session.id, pageId: page.id)).count, 2_000)
        try restarted.endSession(session.id)
        XCTAssertEqual(try restarted.loadPending().count, 1, "Done must preserve unfinished work")
    }

    func testConcurrentReservationsAndOutOfOrderCommitsDoNotLosePages() throws {
        let repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        let session = try repo.createSession()
        let first = try repo.preparePage(sessionId: session.id, jpegData: Data([1]))
        let second = try repo.preparePage(sessionId: session.id, jpegData: Data([2]))
        XCTAssertNotEqual(first.id, second.id)
        let transcription = Transcription(worksheetTitle: "", problems: [.init(number: "1", expression: "1+1", studentAnswer: "2", confidence: 1)])
        let verification = WorksheetOCR.reconcile(first: transcription, second: transcription)
        let review = try WorksheetOCR.buildReview(transcription: transcription, verification: verification, model: "test")
        for page in [second, first, first] {
            try repo.commitPage(sessionId: session.id, page: page, review: review, transcription: transcription, verification: verification)
        }
        XCTAssertEqual(try repo.loadSession(session.id).pages.map(\.id), [first.id, second.id])
    }

    func testOrphanFromOldBuildIsRecoverableAndDiscardIsExplicit() throws {
        let repo = repository()
        defer { try? FileManager.default.removeItem(at: repo.root) }
        let session = try repo.createSession()
        let page = try repo.preparePage(sessionId: session.id, jpegData: Data([1, 2, 3]))
        let pending = try XCTUnwrap(repo.loadPending().first)
        XCTAssertEqual(pending.page.id, page.id)
        try repo.discardPending(pending)
        XCTAssertTrue(try repo.loadPending().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try repo.imageURL(sessionId: session.id, pageId: page.id).path))
    }
}

final class PhoneArchiveTests: XCTestCase {
    func testSavedExamplesAndImageQuality() throws {
        guard let path = ProcessInfo.processInfo.environment["WORKSHEET_ARCHIVE_ROOT"] else {
            throw XCTSkip("Set WORKSHEET_ARCHIVE_ROOT to the copied phone archive.")
        }
        let repo = SessionRepository(root: URL(fileURLWithPath: path))
        let sessions = try repo.listSessions()
        XCTAssertFalse(sessions.isEmpty)
        var pages = 0
        for session in sessions {
            for page in session.pages {
                pages += 1
                for problem in page.review.problems {
                    XCTAssertEqual(problem.gradingMethod, .localArithmetic, problem.expression)
                }
                let quality = try ImageQualityAnalyzer.assess(Data(contentsOf: page.imageURL))
                print("PHONE_FIXTURE_QUALITY \(page.id) score=\(quality.blurScore) regions=\(quality.recognizedRegions) warning=\(quality.warning ?? "none")")
                XCTAssertNil(quality.warning, "Saved page \(page.id) should not be blocked")
            }
        }
        XCTAssertEqual(pages, 9)
    }
}

private final class ParallelReadingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var waiting: [ParallelReadingProtocol] = []
    private(set) static var requests = 0

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        waiting = []; requests = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        Self.lock.lock()
        Self.requests += 1
        Self.waiting.append(self)
        let ready = Self.waiting.count == 2 ? Self.waiting : []
        if !ready.isEmpty { Self.waiting = [] }
        Self.lock.unlock()
        // Neither response is available until both requests have arrived.
        // A sequential implementation therefore cannot finish this test.
        for connection in ready {
            do {
                let reading = Transcription(worksheetTitle: "Parallel", problems: [
                    .init(number: "1", expression: "1+1", studentAnswer: "2", confidence: 0.98)
                ])
                let text = String(decoding: try JSONEncoder().encode(reading), as: UTF8.self)
                let data = try JSONSerialization.data(withJSONObject: [
                    "model": "test-model", "steps": [["type": "model_output", "content": [["type": "text", "text": text]]]]
                ])
                guard let url = connection.request.url,
                      let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { continue }
                connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
                connection.client?.urlProtocol(connection, didLoad: data)
                connection.client?.urlProtocolDidFinishLoading(connection)
            } catch { connection.client?.urlProtocol(connection, didFailWithError: error) }
        }
    }
}

final class ParallelReadingTests: XCTestCase {
    func testBothReadingsStartTogetherAndCachedReadingsAvoidNetwork() async throws {
        ParallelReadingProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ParallelReadingProtocol.self]
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let ocr = WorksheetOCR(apiKey: "test", model: "test-model", sessionOverride: session)
        let analysis = try await ocr.review(jpegData: Data([1]))
        XCTAssertEqual(ParallelReadingProtocol.requests, 2)
        XCTAssertTrue(analysis.review.problems[0].isCorrect)
        XCTAssertEqual(analysis.review.problems[0].handwritingVerified, true)
        let cached = try await ocr.review(jpegData: Data([1]), firstReading: analysis.transcription, secondReading: analysis.transcription)
        XCTAssertEqual(ParallelReadingProtocol.requests, 2, "Restart must reuse completed readings")
        XCTAssertTrue(cached.review.problems[0].isCorrect)
    }
}


final class CaptureQualityTests: XCTestCase {
    func testBlankPageIsHeldBeforeAnyGeminiRequest() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 1200))
        }
        let jpeg = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        XCTAssertNotNil(try ImageQualityAnalyzer.assess(jpeg).warning)
    }

    func testSeverelyBlurredWorksheetNeedsRetake() throws {
        guard let path = ProcessInfo.processInfo.environment["WORKSHEET_ARCHIVE_ROOT"] else {
            throw XCTSkip("Set WORKSHEET_ARCHIVE_ROOT to the copied phone archive.")
        }
        let repo = SessionRepository(root: URL(fileURLWithPath: path))
        let page = try XCTUnwrap(repo.listSessions().first?.pages.first)
        let input = try XCTUnwrap(CIImage(contentsOf: page.imageURL))
        let filter = try XCTUnwrap(CIFilter(name: "CIGaussianBlur"))
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(14, forKey: kCIInputRadiusKey)
        let output = try XCTUnwrap(filter.outputImage?.cropped(to: input.extent))
        let cgImage = try XCTUnwrap(CIContext().createCGImage(output, from: input.extent))
        let data = try XCTUnwrap(UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.9))
        let quality = try ImageQualityAnalyzer.assess(data)
        print("BLURRED_FIXTURE_QUALITY score=\(quality.blurScore) regions=\(quality.recognizedRegions)")
        XCTAssertNotNil(quality.warning)
    }
}
