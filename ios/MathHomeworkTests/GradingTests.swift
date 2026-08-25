import XCTest
@testable import MathHomework

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
