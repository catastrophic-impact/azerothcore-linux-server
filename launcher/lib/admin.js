'use strict';
// Server administration for the launcher: the same jobs as the Go admin TUI (tui/).
// Heavy and risky work (start / stop, MySQL, backups, restore, module rebuilds, client patch, free-training switches) is done by calling the
// proven `acore-admin` command line (the very code the TUI runs). Reading things (status, logs, accounts, backups list, realmlist ...) is done here.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');

const DB_NAMES = ['acore_auth', 'acore_characters', 'acore_world', 'acore_playerbots'];
const FRESH = 'fresh';
const LOG_TOGGLES = [
  { name: 'Playerbots.log', desc: 'bot setup chatter (large)', conf: 'worldserver.conf', key: 'Appender.Playerbots', onLevel: '5', file: 'Playerbots.log' },
  { name: 'Server.log', desc: 'normal server info: loading, sql, modules', conf: 'worldserver.conf', key: 'Appender.Server', onLevel: '5', file: 'Server.log' },
  { name: 'Errors.log', desc: 'errors only (keep on to see problems)', conf: 'worldserver.conf', key: 'Appender.Errors', onLevel: '2', file: 'Errors.log' },
  { name: 'Auth.log', desc: 'auth server / login log', conf: 'authserver.conf', key: 'Appender.Auth', onLevel: '5', file: 'Auth.log' },
];
const GARRISON_PLAYER_TABLES = [
  'acore_characters.dc_garrison_owner', 'acore_characters.dc_garrison_object', 'acore_characters.dc_garrison_decor', 'acore_characters.dc_garrison_setting',
];
const ACCT_NAME = /^[A-Za-z0-9_]{1,17}$/;
const ACCT_PASS = /^[^\s'";\\`]{1,16}$/;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

class Admin {
  constructor(root) {
    // the real path: acore-admin derives its MySQL socket name from the exact root path, so it must match what the server was started with
    try { this.root = fs.realpathSync(root); } catch { this.root = path.resolve(root); }
    this.exe = path.join(this.root, 'acore-admin');
  }
  p(...parts) { return path.join(this.root, ...parts); }

  // ---- running the command line ----
  run(args, { onLine, timeoutMs = 0 } = {}) {
    return new Promise((resolve) => {
      let out = '';
      const child = spawn(this.exe, args, { cwd: this.root, env: { ...process.env, ACORE_ROOT: this.root, GIT_TERMINAL_PROMPT: '0' }, stdio: ['ignore', 'pipe', 'pipe'] });
      let timer = null;
      if (timeoutMs) timer = setTimeout(() => child.kill('SIGKILL'), timeoutMs);
      const feed = (b) => {
        const s = b.toString();
        out += s;
        if (onLine) for (const l of s.split('\n')) if (l.trim()) onLine(l);
      };
      child.stdout.on('data', feed);
      child.stderr.on('data', feed);
      child.on('error', (e) => { if (timer) clearTimeout(timer); resolve({ code: -1, out: String(e.message || e) }); });
      child.on('close', (code) => { if (timer) clearTimeout(timer); resolve({ code, out: out.trim() }); });
    });
  }
  async must(args, opts) {
    const r = await this.run(args, opts);
    if (r.code !== 0) throw new Error(cleanErr(r.out) || `acore-admin ${args[0]} failed`);
    return r.out;
  }
  async sql(q) { return (await this.must(['sql', q])).replace(/\r/g, ''); }
  async trySql(q) { try { return await this.sql(q); } catch { return null; } }
  worldCmd(cmd) { return this.must(['console', cmd]); }

  // ---- processes (same /proc scan as the TUI) ----
  findPid(exe) {
    let ents = [];
    try { ents = fs.readdirSync('/proc'); } catch { return 0; }
    for (const e of ents) {
      if (!/^\d+$/.test(e)) continue;
      try { if (fs.readlinkSync(`/proc/${e}/exe`) === exe) return Number(e); continue; } catch (err) {
        if (err.code !== 'EACCES') continue;   // process gone
      }
      // exe link not readable (restricted /proc, e.g. inside a container): fall back to the command line's first word
      try {
        const argv0 = fs.readFileSync(`/proc/${e}/cmdline`, 'utf8').split('\0')[0];
        if (argv0 && path.resolve(this.root, argv0) === exe) return Number(e);
      } catch { /* ignore */ }
    }
    return 0;
  }
  status() {
    const my = this.findPid(this.p('mysql', 'bin', 'mysqld'));
    const au = this.findPid(this.p('bin', 'authserver'));
    const wo = this.findPid(this.p('bin', 'worldserver'));
    return { mysql: !!my, auth: !!au, world: !!wo, worldPid: wo, worldReady: wo ? this.worldReady(wo) : false };
  }
  // the world is ready once world.out has printed "ready...". Remembered per worldserver process (the line scrolls out of the log tail on a long-running server).
  worldReady(pid) {
    if (pid && this._readyPid === pid) return true;
    if (fileContains(this.p('logs', 'world.out'), 'ready...')) { this._readyPid = pid || null; return true; }
    return false;
  }

  // ---- dashboard numbers ----
  async stats() {
    const st = this.status();
    const s = { uptimeMs: 0, diskFree: 0, diskTotal: 0, backupsSize: 0, characters: 0, accounts: 0, dbOk: false };
    if (st.worldPid) { try { s.uptimeMs = Date.now() - fs.statSync(`/proc/${st.worldPid}`).mtimeMs; } catch { /* ignore */ } }
    try { const f = fs.statfsSync(this.root); s.diskFree = f.bavail * f.bsize; s.diskTotal = f.blocks * f.bsize; } catch { /* ignore */ }
    for (const b of this.listBackups()) s.backupsSize += b.size;
    if (st.mysql) {
      const c = await this.trySql('SELECT COUNT(*) FROM acore_characters.characters WHERE online=1');
      if (c !== null) { s.characters = parseInt(c, 10) || 0; s.dbOk = true; }
      const a = await this.trySql('SELECT COUNT(*) FROM acore_auth.account WHERE online=1');
      if (a !== null) s.accounts = parseInt(a, 10) || 0;
    }
    return s;
  }

  // ---- server control ----
  start(onLine) { return this.must(['start'], { onLine }); }
  stop(onLine) { return this.must(['stop'], { onLine }); }
  startMysql(onLine) { return this.must(['start-mysql'], { onLine }); }
  stopGame(onLine) { return this.must(['stop-game'], { onLine }); }

  // stop the game + login servers, run f(), start them again if they were up (the TUI's withServersStopped)
  async withServersStopped(restart, f, onLine) {
    const was = this.status();
    if (was.world || was.auth) { if (onLine) onLine('stopping the game servers…'); await this.stopGame(onLine); }
    await this.startMysql(onLine);
    const msg = await f();
    if (restart && (was.world || was.auth)) { if (onLine) onLine('starting the servers again…'); await this.start(onLine); return msg + ' Servers restarted (the world takes a minute or two to load).'; }
    return msg;
  }

  // ---- console + logs ----
  worldTail(n = 200) { return tailFile(this.p('logs', 'world.out'), n); }
  logFiles() {
    try {
      return fs.readdirSync(this.p('logs')).filter((f) => { try { return fs.statSync(this.p('logs', f)).isFile(); } catch { return false; } })
        .sort((a, b) => (a === 'world.out' ? -1 : b === 'world.out' ? 1 : a.localeCompare(b)));
    } catch { return []; }
  }
  readLog(file, { lines = 400, filter = '', errorsOnly = false } = {}) {
    if (!file || file !== path.basename(file)) return [];
    const fp = this.p('logs', file);
    if (!filter && !errorsOnly) return tailFile(fp, lines);
    const f = filter.toLowerCase();
    const out = tailFile(fp, 3000).filter((l) => (!f || l.toLowerCase().includes(f)) && (!errorsOnly || lineLevel(l) > 0));
    return out.slice(-lines);
  }

  // ---- accounts (changes go through the running worldserver, like the TUI) ----
  async accounts() {
    if (!this.status().mysql) return { rows: [], bots: 0 };
    const out = await this.sql("SELECT a.id, a.username, COALESCE(MAX(x.gmlevel),0), a.online, (SELECT COUNT(*) FROM acore_characters.characters c WHERE c.account=a.id) " +
      "FROM acore_auth.account a LEFT JOIN acore_auth.account_access x ON x.id=a.id WHERE a.username NOT LIKE 'RNDBOT%' GROUP BY a.id, a.username, a.online ORDER BY a.id");
    const rows = out.split('\n').map((l) => l.split('\t')).filter((f) => f.length === 5).map((f) => ({ id: +f[0], name: f[1], gm: +f[2], online: f[3] !== '0', chars: +f[4] }));
    const bots = parseInt((await this.trySql("SELECT COUNT(*) FROM acore_auth.account WHERE username LIKE 'RNDBOT%'")) || '0', 10) || 0;
    return { rows, bots };
  }
  async acctExists(name) {
    const o = await this.trySql("SELECT COUNT(*) FROM acore_auth.account WHERE username='" + String(name).toUpperCase().replace(/[^A-Z0-9_]/g, '') + "'");
    return (parseInt(o, 10) || 0) > 0;
  }
  needWorld() { if (!this.status().world) throw new Error('start the servers first (Server tab): account changes go through the running worldserver'); }
  async createAccount(name, pass, gm = 0) {
    if (!ACCT_NAME.test(name)) throw new Error('name: 1-17 letters, digits or _');
    if (!ACCT_PASS.test(pass)) throw new Error('password: 1-16 characters, no spaces or quotes');
    if (![0, 1, 2, 3].includes(Number(gm))) throw new Error('GM level must be 0, 1, 2 or 3');
    this.needWorld();
    if (await this.acctExists(name)) throw new Error(`account ${name} already exists`);
    await this.worldCmd(`account create ${name} ${pass}`);
    for (let i = 0; i < 10 && !(await this.acctExists(name)); i++) await sleep(500);
    if (!(await this.acctExists(name))) throw new Error('the server did not create the account');
    if (Number(gm) !== 0) { await this.worldCmd(`account set gmlevel ${name} ${gm} -1`); await sleep(1000); }
    return `created account ${name}`;
  }
  async deleteAccount(name) {
    if (!ACCT_NAME.test(name)) throw new Error('bad account name');
    if (name.toUpperCase() === 'AHBOT') throw new Error("AHBOT is needed by the auction house bot and can't be deleted");
    this.needWorld();
    await this.worldCmd(`account delete ${name}`);
    for (let i = 0; i < 10 && (await this.acctExists(name)); i++) await sleep(500);
    if (await this.acctExists(name)) throw new Error('the server did not delete the account');
    return `deleted account ${name} and its characters`;
  }
  async setGm(name, gm) {
    if (!ACCT_NAME.test(name)) throw new Error('bad account name');
    if (![0, 1, 2, 3].includes(Number(gm))) throw new Error('GM level must be 0, 1, 2 or 3');
    this.needWorld();
    await this.worldCmd(`account set gmlevel ${name} ${gm} -1`);
    await sleep(1000);
    return `${name} is now GM level ${gm}`;
  }
  async setPassword(name, pass) {
    if (!ACCT_NAME.test(name)) throw new Error('bad account name');
    if (!ACCT_PASS.test(pass)) throw new Error('password: 1-16 characters, no spaces or quotes');
    this.needWorld();
    await this.worldCmd(`account set password ${name} ${pass} ${pass}`);
    return `password change sent for ${name}`;
  }

  // ---- modules ----
  modules() {
    let m = { mods: [], lastSnapshot: '', prevEnabled: [] };
    try { m = { ...m, ...JSON.parse(fs.readFileSync(this.p('modules', 'modules.json'), 'utf8')) }; } catch { /* none yet */ }
    const mods = (m.mods || []).slice().sort((a, b) => a.name.localeCompare(b.name));
    return { mods, pending: mods.some((e) => !!e.enabled !== !!e.built), canUndo: !!(m.prevEnabled && m.prevEnabled.length) || !!m.lastSnapshot };
  }
  setModuleEnabled(name, on) { return this.must(['modules', on ? 'enable' : 'disable', name]); }
  addModule(url) { return this.must(['modules', 'add', url]); }
  removeModule(name) { return this.must(['modules', 'remove', name]); }
  applyModules(onLine) { return this.must(['modules', 'apply'], { onLine }); }
  undoModules(onLine) { return this.must(['modules', 'undo'], { onLine }); }

  // ---- backups ----
  listBackups() {
    let ents = [];
    try { ents = fs.readdirSync(this.p('backups'), { withFileTypes: true }); } catch { return []; }
    const out = [];
    for (const e of ents) {
      if (!e.isDirectory()) continue;
      const dir = this.p('backups', e.name);
      const set = { name: e.name, dbs: [], size: 0, time: 0, label: '' };
      let files = [];
      try { files = fs.readdirSync(dir); } catch { continue; }
      for (const f of files) {
        if (f.endsWith('.sql.gz') || f.endsWith('.sql')) {
          const base = f.replace(/\.gz$/, '').replace(/\.sql$/, '');
          if (base) { set.dbs.push(base); try { set.size += fs.statSync(path.join(dir, f)).size; } catch { /* ignore */ } }
        }
      }
      if (!set.dbs.length) continue;
      try { set.time = fs.statSync(dir).mtimeMs; } catch { /* ignore */ }
      try { set.label = fs.readFileSync(path.join(dir, 'meta.txt'), 'utf8').split('\n')[0].trim(); } catch { /* ignore */ }
      set.dbs.sort();
      out.push(set);
    }
    out.sort((a, b) => (a.name === FRESH) !== (b.name === FRESH) ? (a.name === FRESH ? -1 : 1) : b.time - a.time);
    return out;
  }
  createBackup(kind, label, onLine) {
    if (!['full', 'player'].includes(kind)) throw new Error('unknown backup kind');
    const args = ['backup', kind];
    if (label) args.push(String(label).replace(/[^A-Za-z0-9 _-]/g, '').slice(0, 40));
    return this.must(args, { onLine });
  }
  deleteBackup(set) {
    if (!set || /[\/\\.]/.test(set)) throw new Error('bad name');
    if (set === FRESH) throw new Error("the fresh-install master snapshot can't be deleted here (it is what Reset uses)");
    fs.rmSync(this.p('backups', set), { recursive: true, force: true });
    return `deleted backup ${set}`;
  }
  async restoreBackup(set, dbs, onLine) {
    const b = this.listBackups().find((x) => x.name === set);
    if (!b) throw new Error('backup not found');
    const use = (dbs && dbs.length ? dbs : b.dbs).filter((d) => b.dbs.includes(d));
    return this.withServersStopped(true, async () => {
      await this.must(['restore', set, use.join(',')], { onLine });
      return `restored ${use.join(', ')} from ${set}.`;
    }, onLine);
  }
  haveFresh() { return this.listBackups().some((b) => b.name === FRESH); }
  async resetServer(onLine) {
    if (!this.haveFresh()) throw new Error('cannot find the master backup (backups/fresh): this server has no fresh-install snapshot, so it cannot be reset');
    return this.withServersStopped(true, async () => {
      await this.must(['restore', FRESH, this.listBackups().find((b) => b.name === FRESH).dbs.join(',')], { onLine });
      return 'server reset to fresh install; create accounts on the Accounts tab.';
    }, onLine);
  }
  backupsPath() { return this.p('backups'); }

  // ---- options: free training + log files + garrison data ----
  async training() {
    const o = await this.must(['training']);
    const m = /class training free: (true|false), riding training free: (true|false)/.exec(o);
    return { class: !!m && m[1] === 'true', riding: !!m && m[2] === 'true' };
  }
  setTraining(which, on) {
    if (!['class', 'riding'].includes(which)) throw new Error('bad switch');
    return this.must(['training', which, on ? 'on' : 'off']);
  }
  logToggles() {
    return LOG_TOGGLES.map((t) => ({ ...t, enabled: this.logEnabled(t), size: fileSize(this.p('logs', t.file)) }));
  }
  logEnabled(t) {
    let b = ''; try { b = fs.readFileSync(this.p('etc', t.conf), 'utf8'); } catch { return false; }
    const m = appenderRe(t.key).exec(b);
    return !!m && m[3] !== '0';
  }
  setLog(name, on) {
    const t = LOG_TOGGLES.find((x) => x.name === name);
    if (!t) throw new Error('unknown log file');
    const fp = this.p('etc', t.conf);
    const b = fs.readFileSync(fp, 'utf8');
    const re = appenderRe(t.key);
    if (!re.test(b)) throw new Error(`${t.key} not found in ${t.conf}`);
    fs.writeFileSync(fp, b.replace(appenderRe(t.key), (_m, a, typ, _lvl, rest) => `${a}${typ},${on ? t.onLevel : '0'}${rest}`));
    return `${t.name} ${on ? 'ON' : 'OFF'} (applies after the next server restart)`;
  }
  clearMysqlLog() { try { fs.truncateSync(this.p('logs', 'mysqld.log'), 0); } catch (e) { throw new Error(e.message); } return 'mysqld.log cleared'; }
  emptyDisabledLogs() {
    let n = 0;
    for (const t of LOG_TOGGLES) if (!this.logEnabled(t)) { try { fs.truncateSync(this.p('logs', t.file), 0); n++; } catch { /* missing */ } }
    return `emptied ${n} disabled log file(s)`;
  }
  async garrisonCounts() {
    if (!this.status().mysql) return { owners: '?', objects: '?', decor: '?' };
    const q = async (t) => ((await this.trySql('SELECT COUNT(*) FROM ' + t)) || '?').trim();
    return { owners: await q('acore_characters.dc_garrison_owner'), objects: await q('acore_characters.dc_garrison_object'), decor: await q('acore_characters.dc_garrison_decor') };
  }
  async wipeGarrisonData(onLine) {
    return this.withServersStopped(true, async () => {
      for (const t of [...GARRISON_PLAYER_TABLES, 'acore_characters.dc_garrison_logout']) {
        try { await this.sql('DELETE FROM ' + t); } catch (e) { if (!/exist/.test(e.message)) throw new Error(`${t}: ${e.message}`); }
      }
      return "all players' garrison data emptied (the tables themselves are kept)";
    }, onLine);
  }
  async cleanOrphanGarrisons() {
    await this.startMysql();
    let total = 0;
    for (const t of GARRISON_PLAYER_TABLES) {
      try {
        const o = await this.sql(`DELETE t FROM ${t} t LEFT JOIN acore_auth.account a ON a.id = t.account WHERE a.id IS NULL; SELECT ROW_COUNT()`);
        total += parseInt(o, 10) || 0;
      } catch (e) { if (!/exist/.test(e.message)) throw new Error(`${t}: ${e.message}`); }
    }
    return `removed ${total} garrison row(s) of deleted accounts`;
  }

  // ---- config: realmlist, LAN address, client patch ----
  async realm() {
    if (!this.status().mysql) return { address: '', local: '', up: false };
    const o = await this.trySql('select address,localaddress from acore_auth.realmlist where id=1');
    const f = (o || '').split('\t');
    return { address: f[0] || '', local: f[1] || '', up: true };
  }
  async saveRealm(address, local) {
    let a = String(address || '').trim(); const l = String(local || '').trim();
    if (!a) a = l;
    for (const x of [a, l]) if (!x || /['";` \\]/.test(x)) throw new Error(`invalid address "${x}"`);
    if (!this.status().mysql) throw new Error('start MySQL first (Server tab) to save the address');
    await this.sql(`update acore_auth.realmlist set address='${a}', localaddress='${l}' where id=1`);
    return 'realmlist saved (no restart needed)';
  }
  detectLAN(ifaces = os.networkInterfaces()) {
    const skip = ['docker', 'podman', 'veth', 'br-', 'virbr', 'cni', 'tun', 'tap', 'wg', 'tailscale', 'zt', 'lo'];
    const found = [];
    for (const [name, list] of Object.entries(ifaces)) {
      const n = name.toLowerCase();
      if (skip.some((p) => n.startsWith(p))) continue;
      for (const a of list || []) {
        if (a.family !== 'IPv4' || a.internal) continue;
        const o = a.address.split('.').map(Number);
        const priv = o[0] === 10 || (o[0] === 172 && o[1] >= 16 && o[1] <= 31) || (o[0] === 192 && o[1] === 168);
        if (!priv) continue;
        found.push({ ip: a.address, rank: o[0] === 192 ? 0 : o[0] === 10 ? 1 : 2 });
      }
    }
    return found.sort((x, y) => x.rank - y.rank).map((x) => x.ip);
  }
  buildClientPatch(onLine) { return this.must(['client-patch'], { onLine }); }
  clientPatchDir() { return this.p('client-patch'); }
}

// ---- helpers ----
function cleanErr(s) { return String(s || '').replace(/^error:\s*/i, '').trim(); }
function appenderRe(key) { return new RegExp('^(\\s*' + key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\s*=\\s*)(\\d+)\\s*,\\s*(\\d+)(.*)$', 'm'); }
// does the file contain the text? (streams it in chunks; the file is only read until the first hit)
function fileContains(fp, needle) {
  let fd;
  try {
    fd = fs.openSync(fp, 'r');
    const size = fs.fstatSync(fd).size; const CH = 1 << 20; const keep = needle.length - 1;
    let carry = ''; const buf = Buffer.alloc(CH);
    for (let pos = 0; pos < size; pos += CH) {
      const n = fs.readSync(fd, buf, 0, Math.min(CH, size - pos), pos);
      const text = carry + buf.toString('latin1', 0, n);
      if (text.includes(needle)) return true;
      carry = text.slice(-keep);
    }
    return false;
  } catch { return false; } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch { /* ignore */ } }
}
function fileSize(fp) { try { return fs.statSync(fp).size; } catch { return -1; } }
function lineLevel(l) {
  const u = l.toUpperCase();
  if (u.includes('ERROR') || u.includes('FATAL') || u.includes('CRASH')) return 2;
  if (u.includes('WARN')) return 1;
  return 0;
}
// last n lines of a file without reading all of it
function tailFile(fp, n) {
  let fd;
  try {
    fd = fs.openSync(fp, 'r');
    const size = fs.fstatSync(fd).size;
    let want = Math.min(size, Math.max(64 * 1024, n * 400));
    let text = '';
    for (;;) {
      const buf = Buffer.alloc(want);
      fs.readSync(fd, buf, 0, want, size - want);
      text = buf.toString('utf8');
      if (text.split('\n').length > n + 1 || want >= size) break;
      want = Math.min(size, want * 4);
    }
    let lines = text.replace(/\r/g, '').replace(/\x1b\[[0-9;]*m/g, '').split('\n');
    if (lines.length && lines[lines.length - 1] === '') lines.pop();
    if (want < size) lines = lines.slice(1);
    return lines.slice(-n);
  } catch { return []; } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch { /* ignore */ } }
}
function human(n) {
  if (n < 1024) return n + ' B';
  const u = ['KB', 'MB', 'GB', 'TB']; let i = -1;
  do { n /= 1024; i++; } while (n >= 1024 && i < u.length - 1);
  return n.toFixed(n >= 10 ? 0 : 1) + ' ' + u[i];
}

module.exports = { Admin, fileContains, tailFile, lineLevel, appenderRe, human, LOG_TOGGLES, DB_NAMES, ACCT_NAME, ACCT_PASS };
