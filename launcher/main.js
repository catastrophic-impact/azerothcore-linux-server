'use strict';
// AzerothCore Launcher: Electron main process.
// PORTABLE: Electron's own folders (profile, cache, logs, crash dumps) are redirected into launcher/data BEFORE the app is ready, so nothing is
// written to the user's home or ~/.config. The launcher never starts the WoW client.
const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const fs = require('fs');
const path = require('path');
const { LAUNCHER_DIR, DATA_DIR, findRoot } = require('./lib/paths');

// ---- portable paths (must run before 'ready') ----
const EL = path.join(DATA_DIR, 'electron');
for (const d of [DATA_DIR, EL, path.join(DATA_DIR, 'logs'), path.join(DATA_DIR, 'cache'), path.join(DATA_DIR, 'crash')]) fs.mkdirSync(d, { recursive: true });
app.setPath('appData', DATA_DIR);
app.setPath('userData', EL);
app.setPath('sessionData', EL);
app.setPath('logs', path.join(DATA_DIR, 'logs'));
app.setPath('cache', path.join(DATA_DIR, 'cache'));
app.setPath('crashDumps', path.join(DATA_DIR, 'crash'));
app.commandLine.appendSwitch('disk-cache-dir', path.join(DATA_DIR, 'cache'));
app.setAppLogsPath(path.join(DATA_DIR, 'logs'));

const { Admin, human } = require('./lib/admin');
const client = require('./lib/client');
const settings = require('./lib/settings');

const ROOT = findRoot();
const admin = ROOT ? new Admin(ROOT) : null;
let win = null;
let busy = '';               // label of the running long operation ('' = idle)
let forceQuit = false;

// ---- long operations: one at a time, progress pushed to the window ----
function send(ch, payload) { if (win && !win.isDestroyed()) win.webContents.send(ch, payload); }
async function runOp(label, fn) {
  if (busy) throw new Error(`busy: ${busy} - wait for it to finish`);
  busy = label;
  send('op', { phase: 'start', label });
  const onLine = (line) => send('op', { phase: 'line', label, line });
  try {
    const msg = await fn(onLine);
    send('op', { phase: 'done', label, ok: true, message: msg || 'done' });
    return msg || 'done';
  } catch (e) {
    const m = String((e && e.message) || e);
    send('op', { phase: 'done', label, ok: false, message: m });
    throw new Error(m);
  } finally { busy = ''; }
}
// optional "create a backup first" (the TUI asks the same question before risky changes)
async function maybeBackup(want, why, onLine) {
  if (!want) return;
  if (!admin.status().mysql) await admin.startMysql(onLine);
  onLine && onLine('creating a backup first…');
  await admin.createBackup('full', 'before ' + why, onLine);
}

// ---- API (whitelist; the window calls these by name) ----
const api = {
  appInfo: async () => ({ root: ROOT, launcherDir: LAUNCHER_DIR, dataDir: DATA_DIR, version: app.getVersion(), electron: process.versions.electron }),
  busy: async () => busy,

  // server
  status: async () => ({ ...admin.status(), busy }),
  stats: async () => { const s = await admin.stats(); return { ...s, diskFreeH: human(s.diskFree), backupsH: human(s.backupsSize) }; },
  serverStart: () => runOp('starting the servers', (l) => admin.start(l).then(() => 'servers started (the world takes a minute or two to load)')),
  serverStop: () => runOp('shutting down the servers', (l) => admin.stop(l).then(() => 'servers stopped')),
  mysqlStart: () => runOp('starting MySQL', (l) => admin.startMysql(l).then(() => 'MySQL running')),
  serverReset: (a) => runOp('resetting to fresh install', async (l) => { await maybeBackup(a && a.backup, 'reset', l); return admin.resetServer(l); }),

  // output + logs
  worldTail: async (n) => admin.worldTail(n || 200),
  console: async (cmd) => { cmd = String(cmd || '').trim(); if (!cmd) throw new Error('empty command'); if (!admin.status().world) throw new Error('the game server is not running'); await admin.worldCmd(cmd); return 'sent'; },
  logFiles: async () => admin.logFiles(),
  readLog: async (o) => admin.readLog(o && o.file, o || {}),

  // accounts
  accounts: async () => admin.accounts(),
  acctCreate: (a) => runOp('creating account ' + a.name, () => admin.createAccount(a.name, a.pass, a.gm)),
  acctDelete: (a) => runOp('deleting account ' + a.name, () => admin.deleteAccount(a.name)),
  acctGm: (a) => runOp('setting GM level', () => admin.setGm(a.name, a.gm)),
  acctPass: (a) => runOp('changing password', () => admin.setPassword(a.name, a.pass)),

  // modules
  modules: async () => admin.modules(),
  modToggle: async (a) => { await admin.setModuleEnabled(a.name, !!a.on); return 'ok'; },
  modAdd: (a) => runOp('adding module', async () => (await admin.addModule(a.url)) || 'module added'),
  modRemove: (a) => runOp('removing module', async () => (await admin.removeModule(a.name)) || 'module removed'),
  modApply: (a) => runOp('rebuilding modules', async (l) => { await maybeBackup(a && a.backup, 'module change', l); return admin.applyModules(l); }),
  modUndo: (a) => runOp('undoing the last module change', (l) => admin.undoModules(l)),

  // backups
  backups: async () => admin.listBackups().map((b) => ({ ...b, sizeH: human(b.size) })),
  backupCreate: (a) => runOp('creating a ' + a.kind + ' backup', async (l) => {
    if (!admin.status().mysql) throw new Error('MySQL is not running (start it on the Server tab)');
    await admin.createBackup(a.kind, a.label, l); return 'backup created';
  }),
  backupDelete: async (a) => admin.deleteBackup(a.name),
  backupRestore: (a) => runOp('restoring ' + a.name, async (l) => { await maybeBackup(a.backup, 'restore', l); return admin.restoreBackup(a.name, a.dbs, l); }),
  backupsOpen: async () => { const e = await shell.openPath(admin.backupsPath()); if (e) throw new Error(e); return 'opened'; },

  // options
  training: async () => admin.training(),
  trainingSet: (a) => runOp('free training switch', async (l) => { await maybeBackup(a.backup, 'training change', l); return (await admin.setTraining(a.which, a.on)) || 'saved'; }),
  logToggles: async () => admin.logToggles(),
  logSet: async (a) => admin.setLog(a.name, !!a.on),
  clearMysqlLog: async () => admin.clearMysqlLog(),
  emptyLogs: async () => admin.emptyDisabledLogs(),
  garrisonCounts: async () => admin.garrisonCounts(),
  garrisonWipe: (a) => runOp('emptying garrison data', async (l) => { await maybeBackup(a && a.backup, 'garrison wipe', l); return admin.wipeGarrisonData(l); }),
  garrisonOrphans: (a) => runOp('cleaning leftover garrison data', async (l) => { await maybeBackup(a && a.backup, 'garrison clean', l); return admin.cleanOrphanGarrisons(); }),

  // config
  realm: async () => admin.realm(),
  realmSave: (a) => runOp('saving realmlist', () => admin.saveRealm(a.address, a.local)),
  lanDetect: async () => admin.detectLAN(),
  clientPatch: (a) => runOp('building the client patch archive', async (l) => (await admin.buildClientPatch(l)) || 'built'),
  clientPatchOpen: async () => { fs.mkdirSync(admin.clientPatchDir(), { recursive: true }); const e = await shell.openPath(admin.clientPatchDir()); if (e) throw new Error(e); return 'opened'; },

  // client addons (the player's own WoW client folder)
  clientGet: async () => {
    const s = settings.load();
    return { clientPath: s.clientPath, ...client.addonStates(ROOT, s.clientPath, s.installed || {}), realmlist: client.readRealmlist(s.clientPath) };
  },
  clientPick: async () => {
    const r = await dialog.showOpenDialog(win, { title: 'Choose your WoW client folder', properties: ['openDirectory'], defaultPath: settings.load().clientPath || undefined });
    if (r.canceled || !r.filePaths.length) return { canceled: true };
    const c = client.resolveClient(r.filePaths[0]);
    if (!c.valid) throw new Error(c.reason);
    settings.update({ clientPath: c.root });
    return { canceled: false, path: c.root };
  },
  clientSet: async (a) => {
    const c = client.resolveClient(a.path);
    if (!c.valid) throw new Error(c.reason);
    settings.update({ clientPath: c.root });
    return c.root;
  },
  clientForget: async () => { settings.update({ clientPath: '' }); return 'ok'; },
  clientInstall: (a) => runOp('installing addons', async (l) => {
    const s = settings.load();
    const r = client.installAddons(ROOT, s.clientPath, a.names, s.installed || {});
    settings.update({ installed: r.installed });
    r.done.forEach((n) => l(`installed ${n}`));
    return `installed ${r.done.length} addon(s): ${r.done.join(', ')}. In game: /reload (new addons need a full log out and back in).`;
  }),
  clientRemove: (a) => runOp('removing addons', async (l) => {
    const s = settings.load();
    const r = client.removeAddons(ROOT, s.clientPath, a.names, s.installed || {});
    settings.update({ installed: r.installed });
    r.done.forEach((n) => l(`removed ${n}`));
    return `removed ${r.done.length} addon(s)` + (r.warnings.length ? '. ' + r.warnings.join('; ') : '');
  }),
  clientRealmSet: async (a) => { const ch = client.setRealmlist(settings.load().clientPath, a.address); return `realmlist.wtf updated (${ch.length} file(s); the original is kept as realmlist.wtf.bak-launcher)`; },
};

ipcMain.handle('api', async (_e, name, arg) => {
  const fn = api[name];
  if (!Object.prototype.hasOwnProperty.call(api, name) || typeof fn !== 'function') throw new Error('unknown call ' + name);
  if (!admin && !['appInfo', 'busy'].includes(name) && !name.startsWith('client')) throw new Error('no server folder found next to the launcher');
  return fn(arg);
});

// ---- window ----
function createWindow() {
  win = new BrowserWindow({
    width: 1180, height: 780, minWidth: 900, minHeight: 600, title: 'AzerothCore Launcher', backgroundColor: '#14161c',
    show: !process.env.ACORE_LAUNCHER_HIDDEN,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true, spellcheck: false },
  });
  win.setMenuBarVisibility(false);
  if (process.env.ACORE_LAUNCHER_SCRIPT) win.webContents.once('did-finish-load', () => require(process.env.ACORE_LAUNCHER_SCRIPT)({ api, win, app, admin, dialog }));   // test hook (live_ops.js)
  if (process.env.ACORE_LAUNCHER_SHOTS) require('./test/shots')(win, app, process.env.ACORE_LAUNCHER_SHOTS);   // test hook: off-screen screenshots of every tab
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.on('close', async (e) => {
    if (forceQuit || !admin) return;
    const st = admin.status();
    if (!busy && !(st.mysql || st.auth || st.world)) return;
    e.preventDefault();
    if (busy) {
      const r = await dialog.showMessageBox(win, { type: 'warning', buttons: ['Keep the launcher open', 'Quit anyway'], defaultId: 0, cancelId: 0, message: `"${busy}" is still running.`, detail: 'Quitting now leaves the operation running in the background without progress display.' });
      if (r.response === 0) return;
      forceQuit = true; app.quit(); return;
    }
    const r = await dialog.showMessageBox(win, {
      type: 'question', buttons: ['Stop the servers and quit', 'Quit and leave the servers running', 'Cancel'], defaultId: 0, cancelId: 2,
      message: 'The server is still running.', detail: 'Stopping saves the world safely (players get an in-game countdown).',
    });
    if (r.response === 2) return;
    if (r.response === 0) {
      try { win.webContents.send('op', { phase: 'start', label: 'shutting down the servers' }); await admin.stop(); } catch (err) {
        dialog.showErrorBox('Could not stop the servers', String(err.message || err));
        return;
      }
    }
    forceQuit = true; app.quit();
  });
}

// single instance: a second launch just focuses the first window
if (!app.requestSingleInstanceLock()) { app.quit(); } else {
  app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
  app.whenReady().then(createWindow);
  app.on('window-all-closed', () => app.quit());
}

module.exports = { api };
