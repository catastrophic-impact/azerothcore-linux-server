'use strict';
// Launcher settings: one small JSON file inside the launcher's own data folder (portable: nothing outside the folder).
const fs = require('fs');
const path = require('path');
const { DATA_DIR } = require('./paths');

const FILE = () => path.join(DATA_DIR, 'settings.json');
const DEFAULTS = { clientPath: '', installed: {} };

function load() {
  try { return { ...DEFAULTS, ...JSON.parse(fs.readFileSync(FILE(), 'utf8')) }; } catch { return { ...DEFAULTS }; }
}
function save(s) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
  const tmp = FILE() + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(s, null, 2));
  fs.renameSync(tmp, FILE());
  return s;
}
function update(patch) { return save({ ...load(), ...patch }); }

module.exports = { load, save, update };
