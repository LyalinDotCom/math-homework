import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { SessionRepository } from "../electron/storage/session-repository";
import type { Review } from "../shared/contracts";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => fs.rm(directory, { recursive: true, force: true })),
  );
});

describe("human-readable session repository", () => {
  it("writes and reads a complete folder session with derived page paths", async () => {
    const root = await fs.mkdtemp(
      path.join(os.tmpdir(), "math-homework-storage-"),
    );
    temporaryDirectories.push(root);
    const repository = new SessionRepository(root);
    const session = await repository.createSession();
    const prepared = await repository.preparePage(
      session.id,
      Buffer.from([0xff, 0xd8, 0xff, ...new Array(1_100).fill(0)]),
    );
    const review: Review = {
      schemaVersion: 2,
      worksheetTitle: "Test page",
      summary: "1 of 1 answers correct.",
      problems: [
        {
          number: "1",
          expression: "2 + 2",
          studentAnswer: "4",
          correctAnswer: "4",
          isCorrect: true,
          confidence: 1,
        },
      ],
      gradingMethod: "local-arithmetic",
    };
    await repository.commitPage(session.id, prepared.page, review, {
      transcription: {
        worksheetTitle: "Test page",
        problems: [
          {
            number: "1",
            expression: "2 + 2",
            studentAnswer: "4",
            confidence: 1,
          },
        ],
      },
      verification: {
        problems: [
          {
            index: 0,
            studentAnswer: "4",
            confidence: 1,
            needsConfirmation: false,
            verificationNote: "Agreed.",
          },
        ],
      },
    });

    const loaded = await repository.loadSession(session.id, false);
    expect(loaded.pages).toHaveLength(1);
    expect(loaded.pages[0].review).toEqual(review);
    expect(
      JSON.parse(
        await fs.readFile(path.join(root, session.id, "session.json"), "utf8"),
      ),
    ).toMatchObject({ schemaVersion: 2 });
    expect(await fs.readdir(path.join(root, session.id, "pages"))).toEqual([
      "page-001.jpg",
      "page-001.json",
      "page-001.transcription.json",
      "page-001.verification.json",
    ]);
    expect(await fs.readFile(path.join(root, "_README.txt"), "utf8")).toMatch(
      /ordinary UTF-8 JSON and JPEG files/,
    );
  });

  it("rejects unsafe file references in human-edited metadata", async () => {
    const root = await fs.mkdtemp(
      path.join(os.tmpdir(), "math-homework-storage-"),
    );
    temporaryDirectories.push(root);
    const repository = new SessionRepository(root);
    const session = await repository.createSession();
    const metadataFile = path.join(root, session.id, "session.json");
    const metadata = JSON.parse(await fs.readFile(metadataFile, "utf8"));
    metadata.pages = [
      {
        id: "page-001",
        number: 1,
        capturedAt: new Date().toISOString(),
        imageFile: "pages/page-002.jpg",
        reviewFile: "pages/page-001.json",
      },
    ];
    await fs.writeFile(metadataFile, JSON.stringify(metadata));
    await expect(repository.loadSession(session.id)).rejects.toThrow();
  });
});
