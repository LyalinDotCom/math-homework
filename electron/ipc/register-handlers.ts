import fs from "node:fs/promises";
import path from "node:path";
import {
  BrowserWindow,
  dialog,
  ipcMain,
  nativeImage,
  shell,
  type IpcMainInvokeEvent,
} from "electron";
import {
  ReviewImagePayloadSchema,
  SESSION_ID_PATTERN,
  SESSION_SCHEMA_VERSION,
  UpdatePagePayloadSchema,
  type Review,
} from "../../shared/contracts";
import { gradeReview } from "../grading/grade-problem";
import type { WorksheetOcr } from "../gemini/worksheet-ocr";
import type { SessionRepository } from "../storage/session-repository";
import { isTrustedRendererUrl } from "../window";

type Handler = (event: IpcMainInvokeEvent, ...args: unknown[]) => unknown;

function requireSessionId(value: unknown) {
  if (typeof value !== "string" || !SESSION_ID_PATTERN.test(value))
    throw new Error("Invalid session identifier");
  return value;
}

export function registerIpcHandlers(options: {
  repository: SessionRepository;
  ocr: WorksheetOcr;
  projectRoot: string;
  getActiveSessionId: () => string | null;
  setActiveSessionId: (id: string | null) => void;
}) {
  const {
    repository,
    ocr,
    projectRoot,
    getActiveSessionId,
    setActiveSessionId,
  } = options;
  const handle = (channel: string, handler: Handler) => {
    ipcMain.handle(channel, (event, ...args) => {
      const senderUrl = event.senderFrame?.url;
      if (!senderUrl || !isTrustedRendererUrl(senderUrl, projectRoot))
        throw new Error("Untrusted IPC sender");
      return handler(event, ...args);
    });
  };

  handle("session:start", async () => {
    const activeSessionId = getActiveSessionId();
    if (activeSessionId) {
      try {
        return await repository.loadSession(activeSessionId, false);
      } catch (error) {
        console.warn(
          `Replacing unloadable active session ${activeSessionId}:`,
          error,
        );
        setActiveSessionId(null);
      }
    }
    const created = await repository.createSession();
    setActiveSessionId(created.id);
    return { ...created, pages: [] };
  });

  handle("session:resume", async (_event, rawId) => {
    const id = requireSessionId(rawId);
    const resumed = await repository.resumeSession(id);
    setActiveSessionId(id);
    return resumed;
  });

  handle("session:end", async () => {
    const id = getActiveSessionId();
    if (!id) return null;
    try {
      const ended = await repository.endSession(id);
      return { ...ended, pages: [] };
    } finally {
      // Never leave the app stuck in a session whose metadata cannot be
      // stamped; endedAt: null is already a tolerated crash-recovery state.
      setActiveSessionId(null);
    }
  });

  handle("image:choose", async (event) => {
    const owner = BrowserWindow.fromWebContents(event.sender);
    if (!owner) throw new Error("Could not open the image picker");
    const selection = await dialog.showOpenDialog(owner, {
      title: "Choose a worksheet photo",
      properties: ["openFile"],
      filters: [
        { name: "Worksheet images", extensions: ["jpg", "jpeg", "png"] },
      ],
    });
    if (selection.canceled || selection.filePaths.length !== 1) return null;

    const selectedFile = selection.filePaths[0];
    if (!/\.(?:jpe?g|png)$/i.test(path.extname(selectedFile))) {
      throw new Error("Choose a JPEG or PNG image");
    }
    const file = await fs.stat(selectedFile);
    if (!file.isFile() || file.size < 1_000 || file.size > 30 * 1024 * 1024) {
      throw new Error("Selected image size is invalid");
    }

    const decoded = nativeImage.createFromPath(selectedFile);
    if (decoded.isEmpty())
      throw new Error("The selected image could not be read");
    const { width, height } = decoded.getSize();
    if (width < 200 || height < 200 || width * height > 80_000_000) {
      throw new Error("Selected image dimensions are invalid");
    }
    const scale = Math.min(1, 4_096 / width, 4_096 / height);
    const normalized =
      scale < 1
        ? decoded.resize({
            width: Math.round(width * scale),
            height: Math.round(height * scale),
            quality: "best",
          })
        : decoded;
    const jpeg = normalized.toJPEG(92);
    if (jpeg.length < 1_000 || jpeg.length > 18 * 1024 * 1024) {
      throw new Error("Selected image could not be normalized safely");
    }
    return `data:image/jpeg;base64,${jpeg.toString("base64")}`;
  });

  handle("page:review", async (_event, rawImageDataUrl) => {
    const activeSessionId = getActiveSessionId();
    if (!activeSessionId) throw new Error("Activate a scan session first");
    const imageDataUrl = ReviewImagePayloadSchema.parse(rawImageDataUrl);
    const imageBytes = Buffer.from(
      imageDataUrl.slice(imageDataUrl.indexOf(",") + 1),
      "base64",
    );
    if (imageBytes.length < 1_000 || imageBytes.length > 18 * 1024 * 1024) {
      throw new Error("Scan image size is invalid");
    }
    if (
      imageBytes[0] !== 0xff ||
      imageBytes[1] !== 0xd8 ||
      imageBytes[2] !== 0xff
    ) {
      throw new Error("Scan data is not a JPEG image");
    }

    const prepared = await repository.preparePage(activeSessionId, imageBytes);
    try {
      const analysis = await ocr.review(imageBytes);
      await repository.commitPage(
        activeSessionId,
        prepared.page,
        analysis.review,
        analysis,
      );
      return {
        sessionId: activeSessionId,
        ...prepared.page,
        review: analysis.review,
        imageDataUrl,
      };
    } catch (error) {
      await repository.discardPreparedPage(activeSessionId, prepared.page.id);
      throw error;
    }
  });

  handle("page:update", async (_event, rawPayload) => {
    const payload = UpdatePagePayloadSchema.parse(rawPayload);
    // Keep the review's own `model` field: it records which model performed
    // the OCR, not which model is currently configured.
    const review: Review = {
      ...gradeReview(payload.review),
      schemaVersion: SESSION_SCHEMA_VERSION,
      editedAt: new Date().toISOString(),
    };
    return repository.updateReview(payload.sessionId, payload.pageId, review);
  });

  handle("session:list", () => repository.listSessions());
  handle("session:get", (_event, rawId) =>
    repository.loadSession(requireSessionId(rawId), false),
  );
  handle("page:image", (_event, rawSessionId, rawPageId) => {
    const sessionId = requireSessionId(rawSessionId);
    if (typeof rawPageId !== "string")
      throw new Error("Invalid page identifier");
    return repository.getPageImage(sessionId, rawPageId);
  });
  handle("data:reveal", async () => {
    await repository.ensureRoot();
    const error = await shell.openPath(repository.root);
    if (error) throw new Error(error);
    return repository.root;
  });
}

export async function reprocessSession(
  repository: SessionRepository,
  ocr: WorksheetOcr,
  id: string,
) {
  const session = await repository.loadSession(id, false);
  const completed: Array<{ pageId: string; problems: number }> = [];
  for (const page of session.pages) {
    await repository.backupReview(id, page.id);
    const analysis = await ocr.review(
      await repository.readPageImage(id, page.id),
    );
    const updated = {
      ...analysis.review,
      reprocessedAt: new Date().toISOString(),
    };
    await repository.updateAnalysis(
      id,
      page.id,
      updated,
      analysis.transcription,
      analysis.verification,
    );
    completed.push({
      pageId: page.id,
      problems: analysis.review.problems.length,
    });
  }
  return completed;
}
