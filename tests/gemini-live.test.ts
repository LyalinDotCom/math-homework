import fs from "node:fs";
import path from "node:path";
import dotenv from "dotenv";
import { describe, expect, it } from "vitest";
import { GEMINI_MODEL, WorksheetOcr } from "../electron/gemini/worksheet-ocr";
import { gradeLocally } from "../electron/grading/grade-problem";

const runLive = process.env.RUN_GEMINI_INTEGRATION === "1";

describe.skipIf(!runLive)("live Gemini OCR integration", () => {
  it("performs two structured OCR passes and leaves every grade to local code", async () => {
    dotenv.config({ path: path.resolve(".env"), quiet: true });
    const apiKey = process.env.GEMINI_API_KEY;
    expect(apiKey, "GEMINI_API_KEY is required for the live test").toBeTruthy();
    const image =
      process.env.MATH_HOMEWORK_GEMINI_TEST_IMAGE ??
      "/Users/dmitrylyalin/Documents/Math Homework Backups/2026-07-19-before-hardening/meta/2026-07-19T13-56-23-088Z/pages/page-001.jpg";

    const analysis = await new WorksheetOcr(apiKey!, GEMINI_MODEL).review(
      fs.readFileSync(image),
    );

    expect(analysis.transcription.problems.length).toBeGreaterThan(0);
    expect(analysis.verification.problems).toHaveLength(
      analysis.transcription.problems.length,
    );
    expect(analysis.review.model).toBe(GEMINI_MODEL);
    expect(analysis.review.ocrPasses).toBe(2);
    expect(analysis.review.problems).toHaveLength(
      analysis.transcription.problems.length,
    );
    for (const problem of analysis.review.problems) {
      const local = gradeLocally(problem.expression, problem.studentAnswer);
      expect(problem.correctAnswer).toBe(local.correctAnswer);
      expect(problem.calculatedIsCorrect).toBe(local.calculatedIsCorrect);
      expect(problem.isCorrect).toBe(local.isCorrect);
    }
  }, 210_000);
});
