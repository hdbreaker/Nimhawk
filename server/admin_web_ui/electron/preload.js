const { contextBridge, ipcRenderer } = require('electron');

// Exponer APIs seguras al proceso renderer
contextBridge.exposeInMainWorld('electronAPI', {
  // Funciones para comunicación con el proceso principal
  getVersion: () => ipcRenderer.invoke('get-version'),
  getPlatform: () => process.platform,
  
  // Funciones para manejo de archivos (si las necesitas)
  openFile: () => ipcRenderer.invoke('open-file'),
  saveFile: (data) => ipcRenderer.invoke('save-file', data),
  
  // Funciones para notificaciones
  showNotification: (title, body) => ipcRenderer.invoke('show-notification', title, body)
});

// Manejar eventos del DOM
window.addEventListener('DOMContentLoaded', () => {
  console.log('Preload script loaded');
}); 