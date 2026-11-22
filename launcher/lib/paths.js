'use strict';
// Where everything lives. The launcher is PORTABLE: all of its own state sits inside the launcher folder (data/), and it works on the
// server folder it is installed in (the folder that holds `acore-admin`). It never writes to the user's home or ~/.config.
const fs = require('fs');
const path = require('path');

const LAUNCHER_DIR = path.resolve(__dirname, '..');
const DATA_DIR = path.join(LAUNCHER_DIR, 'data');

// server root: $ACORE_ROOT, else the parent folder (installed layout: <server>/launcher), else ../release (dev checkout)
function findRoot(env = process.env, launcherDir = LAUNCHER_DIR) {
  const cands = [];
  if (env.ACORE_ROOT) cands.push(env.ACORE_ROOT);
  cands.push(path.resolve(launcherDir, '..'), path.resolve(launcherDir, '..', 'release'));
  for (const c of cands) if (fs.existsSync(path.join(c, 'acore-admin'))) { try { return fs.realpathSync(c); } catch { return path.resolve(c); } }
  return null;
}

// folder holding OUR client addons: installed layout <server>/client-addons, else the dev checkout <repo>/addons (+ the GM admin tool)
function addonSources(root) {
  const a = path.join(root, 'client-addons');
  if (fs.existsSync(a) && fs.statSync(a).isDirectory()) return [a];
  const repo = path.resolve(root, '..');
  const out = [];
  if (fs.existsSync(path.join(repo, 'addons'))) out.push(path.join(repo, 'addons'));
  return out;
}

module.exports = { LAUNCHER_DIR, DATA_DIR, findRoot, addonSources };
