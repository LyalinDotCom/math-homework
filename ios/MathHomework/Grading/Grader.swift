import Foundation

/// Swift port of electron/grading/grade-problem.ts. Gemini never decides
/// whether the math is right: grading happens here, on device.
enum Grader {
    struct Outcome: Equatable {
        var correctAnswer: String
        var calculatedIsCorrect: Bool?
        var manualIsCorrect: Bool?
        var isCorrect: Bool
        var gradingMethod: GradingMethod
    }

    static func gradeLocally(
        expression: String,
        studentAnswer: String,
        manualIsCorrect: Bool?
    ) -> Outcome {
        do {
            let correct = try MathExpression.evaluate(expression)
            let trimmedAnswer = studentAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let student = trimmedAnswer.isEmpty ? nil : try MathExpression.evaluate(trimmedAnswer)
            let calculated = student.map { $0.value == correct.value } ?? false
            return Outcome(
                correctAnswer: MathExpression.formatAnswer(
                    correct.value,
                    normalizedExpression: correct.normalized
                ),
                calculatedIsCorrect: calculated,
                manualIsCorrect: manualIsCorrect,
                isCorrect: manualIsCorrect ?? calculated,
                gradingMethod: .localArithmetic
            )
        } catch {
            return Outcome(
                correctAnswer: "Check manually",
                calculatedIsCorrect: nil,
                manualIsCorrect: manualIsCorrect,
                isCorrect: manualIsCorrect ?? false,
                gradingMethod: .manualRequired
            )
        }
    }

    static func gradeProblem(_ problem: Problem) -> Problem {
        let outcome = gradeLocally(
            expression: problem.expression,
            studentAnswer: problem.studentAnswer,
            manualIsCorrect: problem.manualIsCorrect
        )
        var graded = problem
        graded.correctAnswer = outcome.correctAnswer
        graded.calculatedIsCorrect = outcome.calculatedIsCorrect
        graded.manualIsCorrect = outcome.manualIsCorrect
        graded.isCorrect = outcome.isCorrect
        graded.gradingMethod = outcome.gradingMethod
        return graded
    }

    static func gradeReview(_ review: Review) -> Review {
        var graded = review
        graded.problems = review.problems.map(gradeProblem)
        let correctCount = graded.problems.filter(\.isCorrect).count
        graded.summary = "\(correctCount) of \(graded.problems.count) answers correct."
        graded.gradingMethod = .localArithmetic
        return graded
    }
}
