import fs from "node:fs";
import path from "node:path";
import { createHash } from "node:crypto";
import { describe, expect, it } from "vitest";
import { ReviewSchema, SessionMetadataSchema } from "../shared/contracts";
import { gradeLocally } from "../electron/grading/grade-problem";

const archiveRoot =
  process.env.MATH_HOMEWORK_REGRESSION_ARCHIVE ??
  "/Users/dmitrylyalin/Documents/Math Homework Backups/2026-07-19-before-hardening/meta";
const hasArchive = fs.existsSync(archiveRoot);

function sha256(file: string) {
  return createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}

describe.skipIf(!hasArchive)("saved archive regression", () => {
  const sessionDirectories = fs
    .readdirSync(archiveRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory());

  it("validates every session, saved review, and original JPEG", () => {
    let checkedPages = 0;
    let checkedImages = 0;
    let checkedReviews = 0;
    for (const directory of sessionDirectories) {
      const sessionRoot = path.join(archiveRoot, directory.name);
      const session = SessionMetadataSchema.parse(
        JSON.parse(
          fs.readFileSync(path.join(sessionRoot, "session.json"), "utf8"),
        ),
      );
      for (const page of session.pages) {
        const image = path.join(sessionRoot, "pages", `${page.id}.jpg`);
        const review = path.join(sessionRoot, "pages", `${page.id}.json`);
        expect(fs.existsSync(image)).toBe(true);
        expect(fs.existsSync(review)).toBe(true);
        checkedPages += 1;
      }
      const pagesRoot = path.join(sessionRoot, "pages");
      for (const file of fs.readdirSync(pagesRoot)) {
        const absoluteFile = path.join(pagesRoot, file);
        if (file.endsWith(".jpg")) {
          expect(fs.readFileSync(absoluteFile).subarray(0, 3)).toEqual(
            Buffer.from([0xff, 0xd8, 0xff]),
          );
          expect(sha256(absoluteFile)).toMatch(/^[a-f0-9]{64}$/);
          checkedImages += 1;
        } else if (/^page-\d+(?:\.pre-ocr-fix)?\.json$/.test(file)) {
          ReviewSchema.parse(JSON.parse(fs.readFileSync(absoluteFile, "utf8")));
          checkedReviews += 1;
        }
      }
    }
    expect(checkedPages).toBeGreaterThan(0);
    expect(checkedImages).toBeGreaterThanOrEqual(checkedPages);
    expect(checkedReviews).toBeGreaterThanOrEqual(checkedPages);
  });

  it("produces the same grades for every problem in every saved review", () => {
    const drift: string[] = [];
    let checkedProblems = 0;
    for (const directory of sessionDirectories) {
      const sessionRoot = path.join(archiveRoot, directory.name);
      const pagesRoot = path.join(sessionRoot, "pages");
      for (const file of fs
        .readdirSync(pagesRoot)
        .filter((name) => /^page-\d+(?:\.pre-ocr-fix)?\.json$/.test(name))) {
        const review = ReviewSchema.parse(
          JSON.parse(fs.readFileSync(path.join(pagesRoot, file), "utf8")),
        );
        review.problems.forEach((problem, index) => {
          if (problem.gradingMethod !== "local-arithmetic") return;
          const result = gradeLocally(
            problem.expression,
            problem.studentAnswer,
            problem.manualIsCorrect,
          );
          checkedProblems += 1;
          if (
            result.correctAnswer !== problem.correctAnswer ||
            result.isCorrect !== problem.isCorrect
          ) {
            drift.push(
              `${directory.name}/${file} problem ${index + 1}: ${problem.expression} / ${problem.studentAnswer} was ${problem.correctAnswer}:${problem.isCorrect}, now ${result.correctAnswer}:${result.isCorrect}`,
            );
          }
        });
      }
    }
    expect(checkedProblems).toBeGreaterThan(0);
    expect(drift, drift.join("\n")).toEqual([]);
  });
});
