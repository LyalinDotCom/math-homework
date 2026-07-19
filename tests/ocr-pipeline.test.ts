import { describe, expect, it } from "vitest";
import { buildReview } from "../electron/gemini/worksheet-ocr";
import { TranscriptionSchema, toGeminiJsonSchema } from "../shared/contracts";

const transcription = {
  worksheetTitle: "Arithmetic",
  problems: [
    {
      number: "1",
      expression: "3/4 + 1/4",
      studentAnswer: "1",
      confidence: 0.7,
    },
    {
      number: "2",
      expression: "6 × 7",
      studentAnswer: "41",
      confidence: 0.6,
    },
  ],
};

describe("OCR-to-local-grading boundary", () => {
  it("emits the JSON Schema subset accepted by Gemini Interactions", () => {
    const schema = JSON.stringify(toGeminiJsonSchema(TranscriptionSchema));
    expect(schema).not.toContain("minItems");
    expect(schema).not.toContain("maxItems");
    expect(schema).toContain('"additionalProperties":false');
  });

  it("uses verified handwriting but computes every grade locally", () => {
    const review = buildReview(
      transcription,
      {
        problems: [
          {
            index: 0,
            studentAnswer: "1",
            confidence: 0.99,
            needsConfirmation: false,
            verificationNote: "Clear.",
          },
          {
            index: 1,
            studentAnswer: "42",
            confidence: 0.98,
            needsConfirmation: false,
            verificationNote: "The final digit is 2.",
          },
        ],
      },
      "test-ocr-model",
      "2026-07-19T12:00:00.000Z",
    );

    expect(
      review.problems.map((problem) => problem.initialStudentAnswer),
    ).toEqual(["1", "41"]);
    expect(review.problems.map((problem) => problem.studentAnswer)).toEqual([
      "1",
      "42",
    ]);
    expect(review.problems.map((problem) => problem.correctAnswer)).toEqual([
      "1",
      "42",
    ]);
    expect(review.problems.every((problem) => problem.isCorrect)).toBe(true);
    expect(review.gradingMethod).toBe("local-arithmetic");
  });

  it("rejects incomplete or duplicate verification indices", () => {
    expect(() =>
      buildReview(
        transcription,
        {
          problems: [
            {
              index: 0,
              studentAnswer: "1",
              confidence: 1,
              needsConfirmation: false,
              verificationNote: "Clear.",
            },
            {
              index: 0,
              studentAnswer: "42",
              confidence: 1,
              needsConfirmation: false,
              verificationNote: "Clear.",
            },
          ],
        },
        "test-ocr-model",
      ),
    ).toThrow(/duplicate or missing/);
  });
});
