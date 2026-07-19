import { BrowserWindow, nativeTheme } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";

function windowBackgroundColor() {
  return nativeTheme.shouldUseDarkColors ? "#1e1e20" : "#f5f5f7";
}

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
    backgroundColor: windowBackgroundColor(),
    titleBarStyle: "hiddenInset",
    trafficLightPosition: { x: 20, y: 20 }, // centered in the 52px toolbar
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  const applyTheme = () => window.setBackgroundColor(windowBackgroundColor());
  nativeTheme.on("updated", applyTheme);
  window.on("closed", () => nativeTheme.removeListener("updated", applyTheme));

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
