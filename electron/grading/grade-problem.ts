import { all, create, type MathNode } from "mathjs";
import type { Problem, Review } from "../../shared/contracts";

const math = create(all, {
  number: "Fraction",
  predictable: true,
});

const ALLOWED_OPERATORS = new Set(["+", "-", "*", "/", "^"]);

export function normalizeMathExpression(source: string) {
  return String(source)
    .replace(/[=？?].*$/, "")
    .replace(/[×xX·]/g, "*")
    .replace(/÷/g, "/")
    .replace(/[−–—]/g, "-")
    .replace(/,/g, "")
    .replace(/\s+/g, "")
    .trim();
}

function parseRestricted(source: string) {
  const normalized = normalizeMathExpression(source);
  if (!normalized || normalized.length > 500)
    throw new Error("Unsupported math expression");

  const node = math.parse(normalized);
  let nodeCount = 0;
  node.traverse((child: MathNode) => {
    nodeCount += 1;
    if (nodeCount > 250) throw new Error("Expression is too complex");
    if (child.type === "ConstantNode" || child.type === "ParenthesisNode")
      return;
    if (child.type !== "OperatorNode")
      throw new Error(`Unsupported math node: ${child.type}`);

    const operator = child as MathNode & { op: string; args: MathNode[] };
    if (!ALLOWED_OPERATORS.has(operator.op))
      throw new Error(`Unsupported operator: ${operator.op}`);
    if (operator.op === "^") {
      const exponent = operator.args[1];
      if (!exponent || exponent.type !== "ConstantNode")
        throw new Error("Exponent must be a constant");
      const numericExponent = Number(exponent.toString());
      if (
        !Number.isInteger(numericExponent) ||
        Math.abs(numericExponent) > 12
      ) {
        throw new Error("Exponent is outside the supported range");
      }
    }
  });

  return { normalized, value: node.evaluate() };
}

function formatAnswer(value: unknown, originalExpression: string) {
  const numericValue = Number(value);
  if (Number.isInteger(numericValue)) return String(numericValue);
  const hasDecimal = /\d\.\d/.test(originalExpression);
  if (hasDecimal) return math.format(numericValue, { precision: 14 });
  return math.format(value, { fraction: "ratio" });
}

export function gradeLocally(
  expression: string,
  studentAnswer: string,
  manualIsCorrect?: boolean | null,
) {
  try {
    const correct = parseRestricted(expression);
    const student =
      studentAnswer.trim() === "" ? null : parseRestricted(studentAnswer);
    const calculatedIsCorrect =
      student !== null && Boolean(math.equal(correct.value, student.value));
    return {
      correctAnswer: formatAnswer(correct.value, correct.normalized),
      calculatedIsCorrect,
      manualIsCorrect: manualIsCorrect ?? null,
      isCorrect: manualIsCorrect ?? calculatedIsCorrect,
      gradingMethod: "local-arithmetic" as const,
    };
  } catch {
    return {
      correctAnswer: "Check manually",
      calculatedIsCorrect: null,
      manualIsCorrect: manualIsCorrect ?? null,
      isCorrect: manualIsCorrect ?? false,
      gradingMethod: "manual-required" as const,
    };
  }
}

export function gradeProblem(problem: Problem): Problem {
  return {
    ...problem,
    ...gradeLocally(
      problem.expression,
      problem.studentAnswer,
      problem.manualIsCorrect,
    ),
  };
}

export function gradeReview(review: Review): Review {
  const problems = review.problems.map(gradeProblem);
  const correctCount = problems.filter((problem) => problem.isCorrect).length;
  return {
    ...review,
    problems,
    summary: `${correctCount} of ${problems.length} answers correct.`,
    gradingMethod: "local-arithmetic",
  };
}
