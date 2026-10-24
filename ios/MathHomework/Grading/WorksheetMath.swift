import Foundation

/// Explicit, deterministic worksheet forms. Never infer a printed problem
/// from the student's answer or silently solve an arbitrary word problem.
enum WorksheetMath {
    struct Answer {
        let text: String
        let matches: Bool
    }

    static func evaluate(expression: String, studentAnswer: String) throws -> Answer? {
        let normalized = expression
            .replacingOccurrences(of: #"(?:\[\s*\]\s*)+"#, with: "?", options: .regularExpression)
            .replacingOccurrences(of: #"[□☐＿_]+"#, with: "?", options: .regularExpression)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
        guard normalized.contains("?") else { return nil }
        if normalized.contains(","), !normalized.contains("=") {
            return try sequence(normalized, studentAnswer: studentAnswer)
        }
        return try equation(normalized, studentAnswer: studentAnswer)
    }

    private static func equation(_ expression: String, studentAnswer: String) throws -> Answer {
        let sides = expression.components(separatedBy: "=")
        guard sides.count == 2, expression.filter({ $0 == "?" }).count == 1 else {
            throw MathEvaluationError.unsupported("Expected one missing number in an equation")
        }
        let missingSide = sides[0].contains("?") ? sides[0] : sides[1]
        let knownSide = sides[0].contains("?") ? sides[1] : sides[0]
        let target = try MathExpression.evaluate(knownSide).value
        let compact = missingSide.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
        let answer: Fraction
        if compact == "?" {
            answer = target
        } else {
            // Only one binary operator with a constant is accepted here.
            let pattern = #"^(\?|[+-]?(?:\d+(?:\.\d+)?|\.\d+))([+*/-])(\?|[+-]?(?:\d+(?:\.\d+)?|\.\d+))$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
                  let leftRange = Range(match.range(at: 1), in: compact),
                  let opRange = Range(match.range(at: 2), in: compact),
                  let rightRange = Range(match.range(at: 3), in: compact)
            else { throw MathEvaluationError.unsupported("Missing-number equation needs manual review") }
            let left = String(compact[leftRange]), right = String(compact[rightRange])
            let symbol = String(compact[opRange])
            let unknownLeft = left == "?"
            let constant = try MathExpression.evaluate(unknownLeft ? right : left).value
            switch symbol {
            case "+": answer = try Fraction.subtract(target, constant)
            case "-": answer = try unknownLeft ? Fraction.add(target, constant) : Fraction.subtract(constant, target)
            case "*": answer = try Fraction.divide(target, constant)
            case "/":
                if unknownLeft {
                    guard constant.numerator != 0 else { throw MathEvaluationError.divisionByZero }
                    answer = try Fraction.multiply(target, constant)
                } else {
                    guard constant.numerator != 0 else { throw MathEvaluationError.unsupported("No unique missing divisor") }
                    answer = try Fraction.divide(constant, target)
                }
            default: throw MathEvaluationError.unsupported("Unsupported equation")
            }
        }
        let student = try? MathExpression.evaluate(studentAnswer).value
        return Answer(text: MathExpression.formatAnswer(answer, normalizedExpression: expression), matches: student == answer)
    }

    private static func sequence(_ expression: String, studentAnswer: String) throws -> Answer {
        let terms = expression.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (4...100).contains(terms.count) else { throw MathEvaluationError.unsupported("Unsupported sequence size") }
        var known: [(Int, Fraction)] = []
        var missing: [Int] = []
        for (index, term) in terms.enumerated() {
            if term == "?" { missing.append(index) }
            else { known.append((index, try MathExpression.evaluate(term).value)) }
        }
        guard known.count >= 3, !missing.isEmpty, let first = known.first else {
            throw MathEvaluationError.unsupported("At least three printed terms are required")
        }
        let second = known[1]
        let step = try Fraction.divide(Fraction.subtract(second.1, first.1), Fraction(Int64(second.0 - first.0)))
        func value(at index: Int) throws -> Fraction {
            try Fraction.add(first.1, Fraction.multiply(step, Fraction(Int64(index - first.0))))
        }
        for (index, printedValue) in known {
            guard printedValue == (try value(at: index)) else {
                throw MathEvaluationError.unsupported("Sequence is not a consistent arithmetic progression")
            }
        }
        let expected = try missing.map { try value(at: $0) }
        let answers = studentAnswer.components(separatedBy: CharacterSet(charactersIn: ",;"))
        let parsed = answers.map { try? MathExpression.evaluate($0).value }
        let matches = parsed.count == expected.count && zip(parsed, expected).allSatisfy { $0.0 == $0.1 }
        return Answer(text: expected.map { MathExpression.formatAnswer($0, normalizedExpression: expression) }.joined(separator: ", "), matches: matches)
    }
}
