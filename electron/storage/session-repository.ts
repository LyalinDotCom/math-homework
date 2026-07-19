import fs from "node:fs/promises";
import path from "node:path";
import writeFileAtomic from "write-file-atomic";
import { z } from "zod";
import {
  PAGE_ID_PATTERN,
  HandwritingVerificationSchema,
  PageMetadataSchema,
  ReviewSchema,
  SESSION_ID_PATTERN,
  SESSION_SCHEMA_VERSION,
  SessionMetadataSchema,
  TranscriptionSchema,
  type Page,
  type PageMetadata,
  type HandwritingVerification,
  type Review,
  type Session,
  type SessionMetadata,
  type Transcription,
} from "../../shared/contracts";

const ARCHIVE_README = `Math Homework archive
=====================

Each timestamped folder is one session. session.json lists its pages.
The pages folder keeps the original JPEG, the final locally graded JSON,
and (for new scans) Gemini's transcription and verification JSON.

These are ordinary UTF-8 JSON and JPEG files. You can copy or back up this
folder without special software. Do not rename files referenced by session.json.
`;

function timestampId(date = new Date()) {
  return date.toISOString().replace(/:/g, "-").replace(/\./g, "-");
}

function requireSessionId(id: string) {
  if (!SESSION_ID_PATTERN.test(id))
    throw new Error("Invalid session identifier");
  return id;
}

function requirePageId(id: string) {
  if (!PAGE_ID_PATTERN.test(id)) throw new Error("Invalid page identifier");
  return id;
}

async function readValidatedJson<T>(
  file: string,
  schema: z.ZodType<T>,
): Promise<T> {
  const text = await fs.readFile(file, "utf8");
  return schema.parse(JSON.parse(text));
}

async function writeJson(file: string, value: unknown) {
  await writeFileAtomic(file, `${JSON.stringify(value, null, 2)}\n`, {
    encoding: "utf8",
  });
}

export class SessionRepository {
  constructor(readonly root: string) {}

  private sessionDirectory(id: string) {
    return path.join(this.root, requireSessionId(id));
  }

  private pagePaths(sessionId: string, pageId: string) {
    const directory = this.sessionDirectory(sessionId);
    const safePageId = requirePageId(pageId);
    return {
      image: path.join(directory, "pages", `${safePageId}.jpg`),
      review: path.join(directory, "pages", `${safePageId}.json`),
      transcription: path.join(
        directory,
        "pages",
        `${safePageId}.transcription.json`,
      ),
      verification: path.join(
        directory,
        "pages",
        `${safePageId}.verification.json`,
      ),
      backup: path.join(directory, "pages", `${safePageId}.pre-ocr-fix.json`),
    };
  }

  private metadataPath(id: string) {
    return path.join(this.sessionDirectory(id), "session.json");
  }

  async ensureRoot() {
    await fs.mkdir(this.root, { recursive: true });
    await fs
      .writeFile(path.join(this.root, "_README.txt"), ARCHIVE_README, {
        encoding: "utf8",
        flag: "wx",
      })
      .catch((error: NodeJS.ErrnoException) => {
        if (error.code !== "EEXIST") throw error;
      });
  }

  async readMetadata(id: string) {
    return readValidatedJson(this.metadataPath(id), SessionMetadataSchema);
  }

  async loadSession(id: string, includeImages = false): Promise<Session> {
    const metadata = await this.readMetadata(id);
    const pages: Page[] = [];

    for (const storedPage of metadata.pages) {
      const page = PageMetadataSchema.parse(storedPage);
      const expectedImageFile = `pages/${page.id}.jpg`;
      const expectedReviewFile = `pages/${page.id}.json`;
      const expectedTranscriptionFile = `pages/${page.id}.transcription.json`;
      const expectedVerificationFile = `pages/${page.id}.verification.json`;
      if (
        page.imageFile !== expectedImageFile ||
        page.reviewFile !== expectedReviewFile ||
        (page.transcriptionFile !== undefined &&
          page.transcriptionFile !== expectedTranscriptionFile) ||
        (page.verificationFile !== undefined &&
          page.verificationFile !== expectedVerificationFile)
      ) {
        throw new Error(`Unsafe file reference in ${metadata.id}/${page.id}`);
      }

      const paths = this.pagePaths(metadata.id, page.id);
      const review = await readValidatedJson(paths.review, ReviewSchema);
      const imageDataUrl = includeImages
        ? `data:image/jpeg;base64,${(await fs.readFile(paths.image)).toString("base64")}`
        : undefined;
      pages.push({ ...page, review, imageDataUrl });
    }

    return { ...metadata, pages };
  }

  async createSession(): Promise<SessionMetadata> {
    await this.ensureRoot();
    let id = "";
    let directory = "";
    for (let offset = 0; offset < 1_000; offset += 1) {
      id = timestampId(new Date(Date.now() + offset));
      directory = this.sessionDirectory(id);
      try {
        await fs.mkdir(directory);
        break;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
        if (offset === 999) throw new Error("Could not allocate a session ID");
      }
    }
    await fs.mkdir(path.join(directory, "pages"));
    const metadata = SessionMetadataSchema.parse({
      schemaVersion: SESSION_SCHEMA_VERSION,
      id,
      startedAt: new Date().toISOString(),
      endedAt: null,
      pages: [],
    });
    await writeJson(this.metadataPath(id), metadata);
    return metadata;
  }

  async resumeSession(id: string): Promise<Session> {
    const metadata = await this.readMetadata(id);
    const updated: SessionMetadata = {
      ...metadata,
      schemaVersion: SESSION_SCHEMA_VERSION,
      endedAt: null,
      resumedAt: [...(metadata.resumedAt ?? []), new Date().toISOString()],
    };
    await writeJson(this.metadataPath(id), updated);
    return this.loadSession(id, false);
  }

  async endSession(id: string): Promise<SessionMetadata> {
    const metadata = await this.readMetadata(id);
    const updated: SessionMetadata = {
      ...metadata,
      schemaVersion: SESSION_SCHEMA_VERSION,
      endedAt: new Date().toISOString(),
    };
    await writeJson(this.metadataPath(id), updated);
    return updated;
  }

  async preparePage(sessionId: string, imageBytes: Buffer) {
    const metadata = await this.readMetadata(sessionId);
    let number =
      metadata.pages.reduce(
        (maximum, page) => Math.max(maximum, page.number),
        0,
      ) + 1;
    // A crash between preparePage and commitPage can leave an orphaned JPEG
    // that session.json never listed; skip past it instead of failing on
    // the same id forever.
    for (; number <= 999_999; number += 1) {
      const id = `page-${String(number).padStart(3, "0")}`;
      const page = PageMetadataSchema.parse({
        id,
        number,
        capturedAt: new Date().toISOString(),
        imageFile: `pages/${id}.jpg`,
        reviewFile: `pages/${id}.json`,
        transcriptionFile: `pages/${id}.transcription.json`,
        verificationFile: `pages/${id}.verification.json`,
      });
      const paths = this.pagePaths(sessionId, id);
      try {
        await fs.writeFile(paths.image, imageBytes, { flag: "wx" });
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "EEXIST") continue;
        throw error;
      }
      return { page, paths };
    }
    throw new Error("Could not allocate a page ID");
  }

  async commitPage(
    sessionId: string,
    page: PageMetadata,
    review: Review,
    artifacts?: {
      transcription: Transcription;
      verification: HandwritingVerification;
    },
  ) {
    const paths = this.pagePaths(sessionId, page.id);
    if (
      (page.transcriptionFile || page.verificationFile) &&
      artifacts === undefined
    ) {
      throw new Error("OCR artifacts are required for this page");
    }
    if (artifacts) {
      await Promise.all([
        writeJson(
          paths.transcription,
          TranscriptionSchema.parse(artifacts.transcription),
        ),
        writeJson(
          paths.verification,
          HandwritingVerificationSchema.parse(artifacts.verification),
        ),
      ]);
    }
    await writeJson(paths.review, ReviewSchema.parse(review));
    // Re-read at commit time: the OCR await between preparePage and here can
    // span minutes, and writing the stale snapshot back would clobber any
    // endedAt/resumedAt stamped meanwhile.
    const metadata = await this.readMetadata(sessionId);
    const updated = SessionMetadataSchema.parse({
      ...metadata,
      schemaVersion: SESSION_SCHEMA_VERSION,
      pages: [...metadata.pages, page],
    });
    await writeJson(this.metadataPath(sessionId), updated);
  }

  async discardPreparedPage(sessionId: string, pageId: string) {
    const paths = this.pagePaths(sessionId, pageId);
    await Promise.all([
      fs.unlink(paths.image).catch(() => undefined),
      fs.unlink(paths.review).catch(() => undefined),
      fs.unlink(paths.transcription).catch(() => undefined),
      fs.unlink(paths.verification).catch(() => undefined),
    ]);
  }

  async updateReview(sessionId: string, pageId: string, review: Review) {
    const metadata = await this.readMetadata(sessionId);
    if (!metadata.pages.some((page) => page.id === pageId))
      throw new Error("Page not found");
    const parsed = ReviewSchema.parse(review);
    await writeJson(this.pagePaths(sessionId, pageId).review, parsed);
    return parsed;
  }

  async updateAnalysis(
    sessionId: string,
    pageId: string,
    review: Review,
    transcription: Transcription,
    verification: HandwritingVerification,
  ) {
    const metadata = await this.readMetadata(sessionId);
    if (!metadata.pages.some((page) => page.id === pageId))
      throw new Error("Page not found");
    const paths = this.pagePaths(sessionId, pageId);
    await Promise.all([
      writeJson(paths.transcription, TranscriptionSchema.parse(transcription)),
      writeJson(
        paths.verification,
        HandwritingVerificationSchema.parse(verification),
      ),
    ]);
    const parsedReview = ReviewSchema.parse(review);
    await writeJson(paths.review, parsedReview);
    const pages = metadata.pages.map((page) =>
      page.id === pageId
        ? {
            ...page,
            transcriptionFile: `pages/${pageId}.transcription.json`,
            verificationFile: `pages/${pageId}.verification.json`,
          }
        : page,
    );
    await writeJson(
      this.metadataPath(sessionId),
      SessionMetadataSchema.parse({
        ...metadata,
        schemaVersion: SESSION_SCHEMA_VERSION,
        pages,
      }),
    );
    return parsedReview;
  }

  async getPageImage(sessionId: string, pageId: string) {
    const metadata = await this.readMetadata(sessionId);
    if (!metadata.pages.some((page) => page.id === pageId))
      throw new Error("Page not found");
    const bytes = await fs.readFile(this.pagePaths(sessionId, pageId).image);
    return `data:image/jpeg;base64,${bytes.toString("base64")}`;
  }

  async listSessions(): Promise<Session[]> {
    await this.ensureRoot();
    const entries = await fs.readdir(this.root, { withFileTypes: true });
    const sessions: Session[] = [];
    for (const entry of entries
      .filter((item) => item.isDirectory())
      .sort((a, b) => b.name.localeCompare(a.name))) {
      try {
        sessions.push(await this.loadSession(entry.name, false));
      } catch (error) {
        console.warn(`Skipping unreadable session ${entry.name}:`, error);
      }
    }
    return sessions;
  }

  async readPageImage(sessionId: string, pageId: string) {
    return fs.readFile(this.pagePaths(sessionId, pageId).image);
  }

  async backupReview(sessionId: string, pageId: string) {
    const paths = this.pagePaths(sessionId, pageId);
    const backupExists = await fs
      .stat(paths.backup)
      .then(() => true)
      .catch(() => false);
    if (!backupExists) await fs.copyFile(paths.review, paths.backup);
  }
}
