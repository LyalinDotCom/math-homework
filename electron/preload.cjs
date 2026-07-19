const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('mathHomework', {
  startSession: () => ipcRenderer.invoke('session:start'),
  resumeSession: (sessionId) => ipcRenderer.invoke('session:resume', sessionId),
  endSession: () => ipcRenderer.invoke('session:end'),
  reviewPage: (imageDataUrl) => ipcRenderer.invoke('page:review', imageDataUrl),
  updatePage: (sessionId, pageId, review) => ipcRenderer.invoke('page:update', { sessionId, pageId, review }),
  listSessions: () => ipcRenderer.invoke('session:list'),
  getSession: (sessionId) => ipcRenderer.invoke('session:get', sessionId),
  reprocessSession: (sessionId) => ipcRenderer.invoke('session:reprocess', sessionId),
  revealData: () => ipcRenderer.invoke('data:reveal'),
});
