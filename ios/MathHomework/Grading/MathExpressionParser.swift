import Foundation

/// Swift port of the restricted mathjs evaluator in
/// electron/grading/grade-problem.ts. Only literal numbers, parentheses,
/// `+ - * /`, implicit multiplication, and constant integer exponents in
/// -12...12 are accepted; anything else throws so the grader can fall back to
/// "Check manually", exactly like the desktop app.
enum MathExpression {
    struct Evaluation {
        let normalized: String
        let value: Fraction
    }

    static func normalize(_ source: String) -> String {
        var text = source
        if let stop = text.firstIndex(where: { $0 == "=" || $0 == "？" || $0 == "?" }) {
            text = String(text[..<stop])
        }
        var normalized = ""
        normalized.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "×", "x", "X", "·": normalized.append("*")
            case "÷": normalized.append("/")
            case "−", "–", "—": normalized.append("-")
            case ",": continue
            default:
                if character.isWhitespace { continue }
                normalized.append(character)
            }
        }
        return normalized
    }

    static func evaluate(_ source: String) throws -> Evaluation {
        // A space between two digits is usually a mixed number ("2 1/2") or an
        // OCR artifact; collapsing it would silently grade a different
        // expression, so send it to manual review instead.
        var probe = source
        if let stop = probe.firstIndex(where: { $0 == "=" || $0 == "？" || $0 == "?" }) {
            probe = String(probe[..<stop])
        }
        probe = probe.replacingOccurrences(of: ",", with: "")
        if probe.range(of: #"\d\s+\d"#, options: .regularExpression) != nil {
            throw MathEvaluationError.ambiguousSpacing
        }

        let normalized = normalize(source)
        guard !normalized.isEmpty, normalized.count <= 500 else {
            throw MathEvaluationError.unsupported("Unsupported math expression")
        }

        var parser = Parser(text: Array(normalized))
        let value = try parser.parseExpression(depth: 0)
        guard parser.isAtEnd else {
            throw MathEvaluationError.unsupported("Unexpected trailing input")
        }
        return Evaluation(normalized: normalized, value: value)
    }

    /// Formats a graded value the way the desktop app does: whole numbers as
    /// integers, decimal worksheets as decimals, everything else as a ratio.
    static func formatAnswer(_ value: Fraction, normalizedExpression: String) -> String {
        if value.isInteger { return String(value.numerator) }
        let hasDecimal =
            normalizedExpression.range(of: #"\d\.\d"#, options: .regularExpression) != nil
        if hasDecimal {
            var formatted = String(format: "%.14g", value.doubleValue)
            if formatted.contains("."), !formatted.contains("e") {
                while formatted.hasSuffix("0") { formatted.removeLast() }
                if formatted.hasSuffix(".") { formatted.removeLast() }
            }
            return formatted
        }
        return "\(value.numerator)/\(value.denominator)"
    }

    private struct Parser {
        let text: [Character]
        var position = 0

        var isAtEnd: Bool { position >= text.count }

        private var current: Character? { position < text.count ? text[position] : nil }

        private mutating func advance() -> Character? {
            guard position < text.count else { return nil }
            defer { position += 1 }
            return text[position]
        }

        private func requireDepth(_ depth: Int) throws {
            // Mirrors the desktop's 250-node traversal cap.
            guard depth < 80 else {
                throw MathEvaluationError.unsupported("Expression is too complex")
            }
        }

        mutating func parseExpression(depth: Int) throws -> Fraction {
            try requireDepth(depth)
            var value = try parseTerm(depth: depth + 1)
            while let symbol = current, symbol == "+" || symbol == "-" {
                position += 1
                let rhs = try parseTerm(depth: depth + 1)
                value = symbol == "+"
                    ? try Fraction.add(value, rhs)
                    : try Fraction.subtract(value, rhs)
            }
            return value
        }

        private mutating func parseTerm(depth: Int) throws -> Fraction {
            try requireDepth(depth)
            var value = try parseUnary(depth: depth + 1)
            while let symbol = current {
                if symbol == "*" || symbol == "/" {
                    position += 1
                    let rhs = try parseUnary(depth: depth + 1)
                    value = symbol == "*"
                        ? try Fraction.multiply(value, rhs)
                        : try Fraction.divide(value, rhs)
                } else if symbol == "(" {
                    // Implicit multiplication: 2(3 + 4)
                    let rhs = try parseUnary(depth: depth + 1)
                    value = try Fraction.multiply(value, rhs)
                } else {
                    break
                }
            }
            return value
        }

        private mutating func parseUnary(depth: Int) throws -> Fraction {
            try requireDepth(depth)
            if current == "-" {
                position += 1
                // Like mathjs, unary minus binds looser than ^: -2^2 == -(2^2).
                return try parseUnary(depth: depth + 1).negated()
            }
            if current == "+" {
                position += 1
                return try parseUnary(depth: depth + 1)
            }
            return try parsePower(depth: depth + 1)
        }

        private mutating func parsePower(depth: Int) throws -> Fraction {
            try requireDepth(depth)
            let base = try parsePrimary(depth: depth + 1)
            guard current == "^" else { return base }
            position += 1
            let exponent = try parseConstantExponent(depth: depth + 1)
            guard exponent.isInteger, abs(exponent.numerator) <= 12 else {
                throw MathEvaluationError.unsupported("Exponent is outside the supported range")
            }
            return try base.power(Int(exponent.numerator))
        }

        /// The desktop only accepts a constant exponent, possibly negated or
        /// parenthesized. Any operator inside the exponent is rejected there
        /// too (its AST check sees an OperatorNode and bails).
        private mutating func parseConstantExponent(depth: Int) throws -> Fraction {
            try requireDepth(depth)
            if current == "-" {
                position += 1
                return try parseConstantExponent(depth: depth + 1).negated()
            }
            if current == "(" {
                position += 1
                let inner = try parseConstantExponent(depth: depth + 1)
                guard current == ")" else {
                    throw MathEvaluationError.unsupported("Exponent must be a constant")
                }
                position += 1
                return inner
            }
            if let symbol = current, symbol.isNumber || symbol == "." {
                return try parseNumber()
            }
            throw MathEvaluationError.unsupported("Exponent must be a constant")
        }

        private mutating func parsePrimary(depth: Int) throws -> Fraction {
            try requireDepth(depth)
            guard let symbol = current else {
                throw MathEvaluationError.unsupported("Unexpected end of expression")
            }
            if symbol == "(" {
                position += 1
                let value = try parseExpression(depth: depth + 1)
                guard current == ")" else {
                    throw MathEvaluationError.unsupported("Missing closing parenthesis")
                }
                position += 1
                // Implicit multiplication: (2)3 or (2)(3)
                if let next = current, next.isNumber || next == "." {
                    let rhs = try parseNumber()
                    return try Fraction.multiply(value, rhs)
                }
                return value
            }
            if symbol.isNumber || symbol == "." {
                return try parseNumber()
            }
            throw MathEvaluationError.unsupported("Unsupported math node: \(symbol)")
        }

        private mutating func parseNumber() throws -> Fraction {
            var digits = ""
            var sawDot = false
            while let symbol = current {
                if symbol.isNumber {
                    digits.append(symbol)
                    position += 1
                } else if symbol == "." {
                    guard !sawDot else {
                        throw MathEvaluationError.unsupported("Malformed number")
                    }
                    sawDot = true
                    digits.append(symbol)
                    position += 1
                } else {
                    break
                }
            }
            guard !digits.isEmpty, digits != "." else {
                throw MathEvaluationError.unsupported("Malformed number")
            }
            let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
            let wholePart = parts.count > 0 ? String(parts[0]) : ""
            let fractionPart = parts.count > 1 ? String(parts[1]) : ""
            var numerator: Int64 = 0
            for character in wholePart + fractionPart {
                guard let digit = character.wholeNumberValue else {
                    throw MathEvaluationError.unsupported("Malformed number")
                }
                let (scaled, mulOverflow) = numerator.multipliedReportingOverflow(by: 10)
                guard !mulOverflow else { throw MathEvaluationError.overflow }
                let (added, addOverflow) = scaled.addingReportingOverflow(Int64(digit))
                guard !addOverflow else { throw MathEvaluationError.overflow }
                numerator = added
            }
            var denominator: Int64 = 1
            for _ in 0..<fractionPart.count {
                let (scaled, overflow) = denominator.multipliedReportingOverflow(by: 10)
                guard !overflow else { throw MathEvaluationError.overflow }
                denominator = scaled
            }
            return try Fraction(numerator, denominator)
        }
    }
}
