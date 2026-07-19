import { app, BrowserWindow } from "electron";
import path from "node:path";
import dotenv from "dotenv";
import { GEMINI_MODEL, WorksheetOcr } from "./gemini/worksheet-ocr";
import { registerIpcHandlers, reprocessSession } from "./ipc/register-handlers";
import { SessionRepository } from "./storage/session-repository";
import { createMainWindow } from "./window";

const PROJECT_ROOT = path.join(__dirname, "..");
dotenv.config({ path: path.join(PROJECT_ROOT, ".env") });

let activeSessionId: string | null = null;
let mainWindow: BrowserWindow | null = null;

if (!app.requestSingleInstanceLock()) app.quit();

app.on("second-instance", () => {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.focus();
});

async function openMainWindow() {
  const window = await createMainWindow(PROJECT_ROOT);
  window.on("closed", () => {
    if (mainWindow === window) mainWindow = null;
  });
  mainWindow = window;
  return window;
}

app
  .whenReady()
  .then(async () => {
    const configuredRoot = process.env.MATH_HOMEWORK_DATA_ROOT;
    const repository = new SessionRepository(
      configuredRoot
        ? path.resolve(configuredRoot)
        : path.join(app.getPath("documents"), "Math Homework", "meta"),
    );
    const ocr = new WorksheetOcr(
      process.env.GEMINI_API_KEY ?? "",
      GEMINI_MODEL,
    );

    const requestedReprocessSession =
      process.env.MATH_HOMEWORK_REPROCESS_SESSION;
    if (requestedReprocessSession) {
      try {
        const completed = await reprocessSession(
          repository,
          ocr,
          requestedReprocessSession,
        );
        console.log(`Reprocessed ${completed.length} saved pages.`);
        app.exit(0);
      } catch (error) {
        console.error(error);
        app.exit(1);
      }
      return;
    }

    registerIpcHandlers({
      repository,
      ocr,
      projectRoot: PROJECT_ROOT,
      getActiveSessionId: () => activeSessionId,
      setActiveSessionId: (id) => {
        activeSessionId = id;
      },
    });
    await openMainWindow();
  })
  .catch((error) => {
    console.error("Math Homework failed to start:", error);
    app.exit(1);
  });

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

app.on("activate", async () => {
  if (BrowserWindow.getAllWindows().length === 0) await openMainWindow();
});
