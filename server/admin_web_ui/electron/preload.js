const { contextBridge, ipcRenderer } = require('electron');

// Expose secure APIs to the renderer process
contextBridge.exposeInMainWorld('electronAPI', {
  // Functions for communication with the main process
  getVersion: () => ipcRenderer.invoke('get-version'),
  getPlatform: () => process.platform,
  
  // Functions for file handling (if you need them)
  openFile: () => ipcRenderer.invoke('open-file'),
  saveFile: (data) => ipcRenderer.invoke('save-file', data),
  
  // Functions for notifications
  showNotification: (title, body) => ipcRenderer.invoke('show-notification', title, body)
});

// Handle DOM events
window.addEventListener('DOMContentLoaded', () => {
  console.log('Preload script loaded');
}); 