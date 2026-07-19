import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("mathHomework", {
  startSession: () => ipcRenderer.invoke("session:start"),
  resumeSession: (sessionId: string) =>
    ipcRenderer.invoke("session:resume", sessionId),
  endSession: () => ipcRenderer.invoke("session:end"),
  reviewPage: (imageDataUrl: string) =>
    ipcRenderer.invoke("page:review", imageDataUrl),
  updatePage: (sessionId: string, pageId: string, review: unknown) =>
    ipcRenderer.invoke("page:update", { sessionId, pageId, review }),
  listSessions: () => ipcRenderer.invoke("session:list"),
  getSession: (sessionId: string) =>
    ipcRenderer.invoke("session:get", sessionId),
  getPageImage: (sessionId: string, pageId: string) =>
    ipcRenderer.invoke("page:image", sessionId, pageId),
  revealData: () => ipcRenderer.invoke("data:reveal"),
});
