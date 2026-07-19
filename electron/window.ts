import { BrowserWindow } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";

export function rendererUrl(projectRoot: string) {
  return (
    process.env.VITE_DEV_SERVER_URL ??
    pathToFileURL(path.join(projectRoot, "dist", "index.html")).href
  );
}

export function isTrustedRendererUrl(url: string, projectRoot: string) {
  try {
    const actual = new URL(url);
    if (process.env.VITE_DEV_SERVER_URL) {
      const expected = new URL(process.env.VITE_DEV_SERVER_URL);
      return actual.origin === expected.origin;
    }
    const expected = new URL(rendererUrl(projectRoot));
    return actual.protocol === "file:" && actual.pathname === expected.pathname;
  } catch {
    return false;
  }
}

export async function createMainWindow(projectRoot: string) {
  const window = new BrowserWindow({
    width: 1440,
    height: 920,
    minWidth: 1040,
    minHeight: 700,
    backgroundColor: "#f7f5ef",
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 18, y: 18 },
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  window.webContents.session.setPermissionRequestHandler(
    (webContents, permission, callback, details) => {
      const mediaTypes =
        permission === "media" && "mediaTypes" in details
          ? (details.mediaTypes ?? [])
          : [];
      callback(
        webContents.id === window.webContents.id &&
          permission === "media" &&
          mediaTypes.length > 0 &&
          mediaTypes.every((type) => type === "video"),
      );
    },
  );
  window.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  window.webContents.on("will-navigate", (event, url) => {
    if (!isTrustedRendererUrl(url, projectRoot)) event.preventDefault();
  });

  if (process.env.VITE_DEV_SERVER_URL)
    await window.loadURL(process.env.VITE_DEV_SERVER_URL);
  else await window.loadFile(path.join(projectRoot, "dist", "index.html"));
  return window;
}
