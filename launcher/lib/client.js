'use strict';
// Installing / removing OUR addons in a WoW client the user picked. The launcher never starts the client and never touches an addon
// that is not in our own addon list (no other AddOns, no client files except the optional realmlist.wtf).
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { addonSources } = require('./paths');

const REQUIRED = 'AcoreLib';

// ---- our addons ----
function parseToc(file) {
  const meta = {};
  try {
    for (const l of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
      const m = /^##\s*([A-Za-z-]+)\s*:\s*(.*)$/.exec(l);
      if (m) meta[m[1].toLowerCase()] = m[2].trim();
    }
  } catch { /* no toc */ }
  return meta;
}
const stripColor = (s) => String(s || '').replace(/\|c[0-9a-fA-F]{8}/g, '').replace(/\|r/g, '').trim();

function listOurAddons(root) {
  const out = new Map();
  for (const src of addonSources(root)) {
    let ents = [];
    try { ents = fs.readdirSync(src, { withFileTypes: true }); } catch { continue; }
    for (const e of ents) {
      if (!e.isDirectory()) continue;
      const dir = path.join(src, e.name);
      const toc = path.join(dir, e.name + '.toc');
      if (!fs.existsSync(toc)) continue;
      const meta = parseToc(toc);
      const deps = (meta.dependencies || meta.requireddeps || '').split(/[,\s]+/).filter(Boolean);
      out.set(e.name, {
        name: e.name, dir, title: stripColor(meta.title) || e.name, notes: stripColor(meta.notes), version: meta.version || '',
        deps, required: e.name === REQUIRED, gmOnly: /_admin$/.test(e.name),
      });
    }
  }
  return [...out.values()].sort((a, b) => (b.required - a.required) || a.name.localeCompare(b.name));
}

// stable fingerprint of a folder (paths + contents)
function hashDir(dir) {
  const h = crypto.createHash('sha1');
  const walk = (d, rel) => {
    let ents = [];
    try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return; }
    ents.sort((a, b) => a.name.localeCompare(b.name));
    for (const e of ents) {
      const r = rel ? rel + '/' + e.name : e.name;
      if (e.isDirectory()) walk(path.join(d, e.name), r);
      else if (e.isFile()) { h.update(r + '\0'); h.update(fs.readFileSync(path.join(d, e.name))); h.update('\0'); }
    }
  };
  walk(dir, '');
  return h.digest('hex');
}

// ---- the client folder ----
// Accepts the client root (has Data/ and Wow.exe or Interface/), its Interface folder, or its AddOns folder.
function resolveClient(picked) {
  const res = { valid: false, root: '', addonsDir: '', reason: '' };
  if (!picked) { res.reason = 'no client folder chosen yet'; return res; }
  let p = path.resolve(picked);
  try { if (!fs.statSync(p).isDirectory()) { res.reason = 'not a folder'; return res; } } catch { res.reason = 'folder not found'; return res; }
  if (path.basename(p).toLowerCase() === 'addons' && path.basename(path.dirname(p)).toLowerCase() === 'interface') p = path.dirname(path.dirname(p));
  else if (path.basename(p).toLowerCase() === 'interface') p = path.dirname(p);
  const has = (n) => { try { return fs.readdirSync(p).find((x) => x.toLowerCase() === n.toLowerCase()); } catch { return undefined; } };
  const data = has('Data'); const iface = has('Interface'); const exe = has('Wow.exe');
  if (!data || !(exe || iface)) { res.reason = 'this does not look like a WoW 3.3.5a client folder (expected Data/ and Wow.exe or Interface/)'; return res; }
  res.root = p;
  const ifaceDir = path.join(p, iface || 'Interface');
  let addons = null;
  try { addons = fs.readdirSync(ifaceDir).find((x) => x.toLowerCase() === 'addons'); } catch { /* no Interface yet */ }
  res.addonsDir = path.join(ifaceDir, addons || 'AddOns');
  res.valid = true;
  return res;
}

function inside(parent, child) {
  const r = path.relative(parent, child);
  return !!r && !r.startsWith('..') && !path.isAbsolute(r);
}

// state of each of our addons in the chosen client
function addonStates(root, clientPath, installedMap = {}) {
  const ours = listOurAddons(root);
  const c = resolveClient(clientPath);
  const rows = ours.map((a) => {
    const row = { ...a, state: 'unknown', installedByUs: !!installedMap[a.name] };
    if (c.valid) {
      const dest = path.join(c.addonsDir, a.name);
      if (!fs.existsSync(dest)) row.state = 'missing';
      else row.state = hashDir(dest) === hashDir(a.dir) ? 'current' : 'outdated';
    }
    return row;
  });
  return { client: c, addons: rows };
}

function copyAddon(src, dest) {
  const tmp = dest + '.launcher-new';
  const old = dest + '.launcher-old';
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.rmSync(old, { recursive: true, force: true });
  fs.cpSync(src, tmp, { recursive: true });
  const had = fs.existsSync(dest);
  try {
    if (had) fs.renameSync(dest, old);
    fs.renameSync(tmp, dest);
  } catch (e) {
    if (had && !fs.existsSync(dest) && fs.existsSync(old)) fs.renameSync(old, dest);   // put the previous copy back
    fs.rmSync(tmp, { recursive: true, force: true });
    throw e;
  }
  fs.rmSync(old, { recursive: true, force: true });
}

// install (or update) the named addons; AcoreLib and declared dependencies of ours are added automatically
function installAddons(root, clientPath, names, installedMap = {}) {
  const c = resolveClient(clientPath);
  if (!c.valid) throw new Error(c.reason);
  const ours = new Map(listOurAddons(root).map((a) => [a.name, a]));
  const want = new Set();
  const add = (n) => { const a = ours.get(n); if (!a || want.has(n)) return; want.add(n); a.deps.forEach(add); };
  names.forEach(add);
  if (want.size && ours.has(REQUIRED)) want.add(REQUIRED);
  if (!want.size) throw new Error('nothing selected');
  fs.mkdirSync(c.addonsDir, { recursive: true });
  const done = [];
  const next = { ...installedMap };
  for (const n of want) {
    const a = ours.get(n);
    const dest = path.join(c.addonsDir, n);
    if (!inside(c.addonsDir, dest)) throw new Error('bad addon name ' + n);
    copyAddon(a.dir, dest);
    next[n] = { hash: hashDir(a.dir), at: new Date().toISOString() };
    done.push(n);
  }
  return { done, installed: next };
}

// remove the named addons (only ones in our own list)
function removeAddons(root, clientPath, names, installedMap = {}) {
  const c = resolveClient(clientPath);
  if (!c.valid) throw new Error(c.reason);
  const ours = new Set(listOurAddons(root).map((a) => a.name));
  const done = []; const warnings = []; const next = { ...installedMap };
  for (const n of names) {
    if (!ours.has(n)) continue;
    const dest = path.join(c.addonsDir, n);
    if (!inside(c.addonsDir, dest)) throw new Error('bad addon name ' + n);
    if (fs.existsSync(dest)) { fs.rmSync(dest, { recursive: true, force: true }); done.push(n); }
    delete next[n];
  }
  if (done.includes(REQUIRED)) {
    const left = [...ours].filter((n) => n !== REQUIRED && fs.existsSync(path.join(c.addonsDir, n)));
    if (left.length) warnings.push(`${REQUIRED} was removed but these addons still need it: ${left.join(', ')}`);
  }
  return { done, warnings, installed: next };
}

// ---- optional: the client's realmlist.wtf ----
function realmlistFiles(clientPath) {
  const c = resolveClient(clientPath);
  if (!c.valid) return [];
  const out = [];
  const roots = [c.root, path.join(c.root, 'Data')];
  for (const r of roots) {
    let ents = [];
    try { ents = fs.readdirSync(r, { withFileTypes: true }); } catch { continue; }
    for (const e of ents) {
      if (e.isFile() && e.name.toLowerCase() === 'realmlist.wtf') out.push(path.join(r, e.name));
      if (e.isDirectory() && /^[a-z]{2}[A-Z]{2}$/.test(e.name)) {
        try { for (const f of fs.readdirSync(path.join(r, e.name))) if (f.toLowerCase() === 'realmlist.wtf') out.push(path.join(r, e.name, f)); } catch { /* ignore */ }
      }
    }
  }
  return out;
}
function readRealmlist(clientPath) {
  return realmlistFiles(clientPath).map((file) => {
    let text = ''; try { text = fs.readFileSync(file, 'utf8'); } catch { /* ignore */ }
    const m = /set\s+realmlist\s+(\S+)/i.exec(text);
    return { file, address: m ? m[1] : '' };
  });
}
function setRealmlist(clientPath, address) {
  const a = String(address || '').trim();
  if (!a || /[\s"';]/.test(a)) throw new Error('invalid address');
  const files = realmlistFiles(clientPath);
  if (!files.length) throw new Error('no realmlist.wtf found in this client');
  const changed = [];
  for (const f of files) {
    const bak = f + '.bak-launcher';
    if (!fs.existsSync(bak)) fs.copyFileSync(f, bak);   // keep the original once
    fs.writeFileSync(f, `set realmlist ${a}\n`);
    changed.push(f);
  }
  return changed;
}

module.exports = { listOurAddons, resolveClient, addonStates, installAddons, removeAddons, hashDir, readRealmlist, setRealmlist, REQUIRED };
