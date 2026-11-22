'use strict';
// The only bridge between the window and the main process: named calls + two event streams. No Node access in the window.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('acore', {
  call: (name, arg) => ipcRenderer.invoke('api', name, arg),
  onOp: (cb) => { const h = (_e, p) => cb(p); ipcRenderer.on('op', h); return () => ipcRenderer.removeListener('op', h); },
});
