import XCTest
@testable import MathHomework

/// Mirror of tests/gemini-live.test.ts: an opt-in check that makes both real
/// Gemini calls against a saved worksheet image and grades the result.
/// Enable with TEST_RUNNER_RUN_GEMINI_INTEGRATION=1.
final class GeminiLiveTests: XCTestCase {
    func testRealWorksheetReview() async throws {
        guard ProcessInfo.processInfo.environment["RUN_GEMINI_INTEGRATION"] == "1" else {
            throw XCTSkip("Set RUN_GEMINI_INTEGRATION=1 to run the live Gemini check.")
        }

        let imagePath = ProcessInfo.processInfo.environment["GEMINI_TEST_IMAGE"]
            ?? "/Users/dmitrylyalin/Documents/Math Homework/meta/2026-07-19T13-56-23-088Z/pages/page-001.jpg"
        let jpeg = try Data(contentsOf: URL(fileURLWithPath: imagePath))

        let apiKey = KeychainStore.loadAPIKey()
        XCTAssertFalse(apiKey.isEmpty, "No API key: seed Secrets.plist or the Keychain first")

        let ocr = WorksheetOCR(apiKey: apiKey, model: WorksheetOCR.geminiModel)
        let analysis = try await ocr.review(jpegData: jpeg)

        XCTAssertFalse(analysis.review.problems.isEmpty, "Expected at least one problem")
        XCTAssertEqual(analysis.review.gradingMethod, .localArithmetic)
        XCTAssertEqual(analysis.review.model, WorksheetOCR.geminiModel)
        XCTAssertEqual(
            analysis.verification.problems.count,
            analysis.transcription.problems.count
        )

        // Leave the graded result where the harness can inspect it.
        if let dump = ProcessInfo.processInfo.environment["GEMINI_TEST_OUTPUT"] {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(analysis.review).write(to: URL(fileURLWithPath: dump))
        }
    }
}
