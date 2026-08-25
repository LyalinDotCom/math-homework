import Foundation

enum MathEvaluationError: Error {
    case unsupported(String)
    case divisionByZero
    case overflow
    case ambiguousSpacing
}

/// Exact rational arithmetic on checked 64-bit integers. Worksheet numbers are
/// tiny; anything that overflows is punted to manual review by the grader, the
/// same way mathjs failures are on the desktop.
struct Fraction: Equatable {
    let numerator: Int64
    let denominator: Int64 // always > 0; sign lives on the numerator

    init(_ numerator: Int64, _ denominator: Int64 = 1) throws {
        guard denominator != 0 else { throw MathEvaluationError.divisionByZero }
        var n = numerator
        var d = denominator
        if d < 0 {
            guard n != Int64.min, d != Int64.min else { throw MathEvaluationError.overflow }
            n = -n
            d = -d
        }
        let divisor = Fraction.gcd(n.magnitude, d.magnitude)
        if divisor > 1 {
            n /= Int64(divisor)
            d /= Int64(divisor)
        }
        self.numerator = n
        self.denominator = d
    }

    private static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }

    private static func checkedMultiply(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (result, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw MathEvaluationError.overflow }
        return result
    }

    private static func checkedAdd(_ a: Int64, _ b: Int64) throws -> Int64 {
        let (result, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw MathEvaluationError.overflow }
        return result
    }

    static func add(_ lhs: Fraction, _ rhs: Fraction) throws -> Fraction {
        try Fraction(
            checkedAdd(
                checkedMultiply(lhs.numerator, rhs.denominator),
                checkedMultiply(rhs.numerator, lhs.denominator)
            ),
            checkedMultiply(lhs.denominator, rhs.denominator)
        )
    }

    static func subtract(_ lhs: Fraction, _ rhs: Fraction) throws -> Fraction {
        try add(lhs, rhs.negated())
    }

    static func multiply(_ lhs: Fraction, _ rhs: Fraction) throws -> Fraction {
        try Fraction(
            checkedMultiply(lhs.numerator, rhs.numerator),
            checkedMultiply(lhs.denominator, rhs.denominator)
        )
    }

    static func divide(_ lhs: Fraction, _ rhs: Fraction) throws -> Fraction {
        guard rhs.numerator != 0 else { throw MathEvaluationError.divisionByZero }
        return try Fraction(
            checkedMultiply(lhs.numerator, rhs.denominator),
            checkedMultiply(lhs.denominator, rhs.numerator)
        )
    }

    func negated() throws -> Fraction {
        guard numerator != Int64.min else { throw MathEvaluationError.overflow }
        return try Fraction(-numerator, denominator)
    }

    func power(_ exponent: Int) throws -> Fraction {
        if exponent == 0 { return try Fraction(1) }
        let base = exponent < 0 ? try Fraction.divide(try Fraction(1), self) : self
        var result = try Fraction(1)
        for _ in 0..<abs(exponent) {
            result = try Fraction.multiply(result, base)
        }
        return result
    }

    var isInteger: Bool { denominator == 1 }
    var doubleValue: Double { Double(numerator) / Double(denominator) }
}
