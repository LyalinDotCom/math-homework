import { describe, expect, it } from "vitest";
import {
  gradeLocally,
  normalizeMathExpression,
} from "../electron/grading/grade-problem";

describe("local arithmetic grading", () => {
  it("keeps OCR text separate from the calculated answer", () => {
    expect(gradeLocally("13 + 4", "7")).toMatchObject({
      correctAnswer: "17",
      isCorrect: false,
    });
    expect(gradeLocally("13 + 4", "17")).toMatchObject({
      correctAnswer: "17",
      isCorrect: true,
    });
  });

  it("handles worksheet operators, precedence, implicit multiplication, and exact fractions", () => {
    expect(gradeLocally("12 × 3", "36").isCorrect).toBe(true);
    expect(gradeLocally("(20 - 8) ÷ 3", "4").isCorrect).toBe(true);
    expect(gradeLocally("2(3 + 4)", "14").isCorrect).toBe(true);
    expect(gradeLocally("1/3 + 1/6", "1/2")).toMatchObject({
      correctAnswer: "1/2",
      isCorrect: true,
    });
  });

  it("uses exact decimal arithmetic", () => {
    expect(gradeLocally("0.1 + 0.2", "0.3")).toMatchObject({
      correctAnswer: "0.3",
      isCorrect: true,
    });
  });

  it("rejects symbols, assignments, functions, and unreasonable powers", () => {
    for (const expression of ["x + 1", "a = 4", "sqrt(4)", "2^1000"]) {
      expect(gradeLocally(expression, "2").gradingMethod).toBe(
        "manual-required",
      );
    }
  });

  it("sends mixed-number spacing to manual review instead of misgrading it", () => {
    expect(gradeLocally("2 1/2 + 1/2", "3").gradingMethod).toBe(
      "manual-required",
    );
    expect(gradeLocally("13 + 4", "1 7").gradingMethod).toBe("manual-required");
  });

  it("grades parenthesized and negative constant exponents", () => {
    expect(gradeLocally("2^(3)", "8").isCorrect).toBe(true);
    expect(gradeLocally("2^-3", "1/8")).toMatchObject({
      correctAnswer: "1/8",
      isCorrect: true,
    });
  });

  it("persists manual overrides for unsupported work", () => {
    expect(gradeLocally("x + 1", "4", true)).toMatchObject({
      calculatedIsCorrect: null,
      manualIsCorrect: true,
      isCorrect: true,
      gradingMethod: "manual-required",
    });
  });

  it("normalizes common OCR operator variants", () => {
    expect(normalizeMathExpression("1,200 − 200 =")).toBe("1200-200");
  });
});
