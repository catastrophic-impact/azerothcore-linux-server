'use strict';
// Launcher window. All data comes from the main process through window.acore.call(name, arg); nothing here touches the disk or the network.
const $ = (s, el = document) => el.querySelector(s);
const call = (n, a) => window.acore.call(n, a);

// replaceChildren() must ignore null / false (conditional bits of a view), not print them as text
const _rc = Element.prototype.replaceChildren;
Element.prototype.replaceChildren = function (...kids) { return _rc.apply(this, kids.flat().filter((k) => k != null && k !== false)); };

// ---- tiny DOM helper (text is always set as text, never as HTML) ----
function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v == null) continue;
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'value') el.value = v;
    else if (k === 'checked' || k === 'disabled' || k === 'hidden' || k === 'selected') el[k] = !!v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const k of kids.flat()) if (k != null && k !== false) el.append(k.nodeType ? k : document.createTextNode(String(k)));
  return el;
}

const state = { tab: 'server', status: null, stats: null, busy: '', info: null, timers: [], opOpen: false };
const TABS = [
  ['server', 'Server', '●'], ['output', 'Output', '▤'], ['logs', 'Logs', '☰'], ['accounts', 'Accounts', '☺'], ['modules', 'Modules', '▦'],
  ['backups', 'Backups', '⛁'], ['options', 'Options', '⚙'], ['config', 'Config', '⌘'], ['client', 'Client addons', '⇩'],
];

// ---- toasts, confirm / form dialogs ----
function toast(msg, bad) {
  const t = h('div', { class: 'toast' + (bad ? ' bad' : '') }, msg);
  $('#toasts').append(t);
  setTimeout(() => t.remove(), bad ? 9000 : 5000);
}
function dialog({ title, body, danger, fields = [], ok = 'OK', cancel = 'Cancel', backup, extra }) {
  return new Promise((resolve) => {
    const inputs = {};
    const fEls = fields.map((f) => {
      const inp = f.type === 'select'
        ? h('select', {}, f.options.map(([v, l]) => h('option', { value: v, selected: v === f.value }, l)))
        : h('input', { type: f.type || 'text', value: f.value || '', placeholder: f.placeholder || '', maxlength: f.max || false });
      inputs[f.name] = inp;
      return h('label', { class: 'f' }, f.label, inp);
    });
    const bk = backup ? h('input', { type: 'checkbox', checked: backup === 'default-on' }) : null;
    const close = (v) => { $('#modal').hidden = true; $('#modal').replaceChildren(); resolve(v); };
    const submit = () => {
      const vals = {}; for (const [k, el] of Object.entries(inputs)) vals[k] = el.value;
      close({ ok: true, values: vals, backup: bk ? bk.checked : false });
    };
    const okBtn = h('button', { class: danger ? 'danger' : 'primary', onclick: submit }, ok);
    const dlg = h('div', { class: 'dlg' + (danger ? ' bad' : '') },
      h('h3', {}, title), body ? h('div', { class: 'body' }, body) : null,
      fields.length ? h('div', { class: 'fields' }, fEls) : null,
      extra || null,
      bk ? h('label', { class: 'row muted' }, bk, 'Create a full backup first (recommended)') : null,
      h('div', { class: 'btns' }, h('button', { class: 'ghost', onclick: () => close(null) }, cancel), okBtn));
    $('#modal').replaceChildren(dlg); $('#modal').hidden = false;
    dlg.addEventListener('keydown', (e) => { if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type !== 'checkbox') submit(); if (e.key === 'Escape') close(null); });
    const first = dlg.querySelector('input:not([type=checkbox]),select'); if (first) first.focus(); else okBtn.focus();
  });
}
const confirmBox = (title, body, opts = {}) => dialog({ title, body, ...opts });

// run an API call, show errors as toasts
async function act(name, arg, { okToast = true } = {}) {
  try { const r = await call(name, arg); if (okToast && typeof r === 'string' && r && r !== 'ok') toast(r); return r; } catch (e) { toast(cleanIpc(e), true); return undefined; }
}
const cleanIpc = (e) => String((e && e.message) || e).replace(/^Error invoking remote method 'api': (Error: )?/, '');

// ---- operations bar ----
const op = { lines: [] };
window.acore.onOp((p) => {
  const bar = $('#opbar');
  if (p.phase === 'start') {
    state.busy = p.label; op.lines = []; bar.hidden = false;
    $('#opTitle').textContent = p.label; $('#opState').textContent = 'working…'; $('#opSpin').className = ''; $('#opClose').hidden = true; $('#opLog').textContent = '';
  } else if (p.phase === 'line') {
    op.lines.push(p.line); if (op.lines.length > 400) op.lines.shift();
    const log = $('#opLog'); log.textContent = op.lines.join('\n'); log.scrollTop = log.scrollHeight;
  } else if (p.phase === 'done') {
    state.busy = '';
    $('#opSpin').className = p.ok ? 'done' : 'fail'; $('#opState').textContent = (p.ok ? 'done: ' : 'failed: ') + p.message; $('#opClose').hidden = false;
    if (p.ok) setTimeout(() => { if (!state.busy && $('#opState').textContent.startsWith('done')) $('#opbar').hidden = true; }, 6000);
    refreshStatus(); if (state.render) state.render();
  }
  syncBusy();
});
$('#opClose').addEventListener('click', () => { $('#opbar').hidden = true; });
function syncBusy() {
  document.body.classList.toggle('busy', !!state.busy);
  for (const b of document.querySelectorAll('button[data-needidle]')) b.disabled = !!state.busy || b.dataset.forceoff === '1';
  const ban = $('#banner');
  ban.hidden = !state.busy; ban.textContent = state.busy ? `Working: ${state.busy}. Other actions are disabled until it finishes.` : '';
}
const idle = (b) => { b.dataset.forceoff = b.disabled ? '1' : '0'; b.dataset.needidle = '1'; b.disabled = !!state.busy || b.disabled; return b; };

// ---- status ----
function worldState() {
  const s = state.status; if (!s) return 'stopped';
  if (!s.world) return 'stopped';
  if (/shut|stopp|reset/.test(state.busy)) return 'stopping';
  return s.worldReady ? 'running' : 'starting';
}
function renderChips() {
  const s = state.status || {};
  const ws = worldState();
  const chip = (name, cls, txt) => h('div', { class: 'chip' }, h('span', { class: 'dot ' + cls }), `${name} ${txt}`);
  $('#chips').replaceChildren(
    chip('MySQL', s.mysql ? 'good' : '', s.mysql ? 'running' : 'stopped'),
    chip('Auth', s.auth ? 'good' : '', s.auth ? 'running' : 'stopped'),
    chip('World', ws === 'running' ? 'good' : ws === 'stopped' ? '' : 'warn', ws));
}
async function refreshStatus() {
  try { state.status = await call('status'); } catch { return; }
  renderChips();
  if (state.render && ['server'].includes(state.tab)) state.render(true);
}

// ---- navigation ----
function buildNav() {
  $('#nav').replaceChildren(...TABS.map(([id, label, ico]) => h('button', { class: id === state.tab ? 'on' : '', onclick: () => go(id) }, h('span', { class: 'ico' }, ico), label)));
}
function clearTimers() { state.timers.forEach(clearInterval); state.timers = []; }
const every = (ms, fn) => state.timers.push(setInterval(fn, ms));
async function go(tab) {
  state.tab = tab; clearTimers(); buildNav(); state.render = null;
  const view = $('#view'); view.replaceChildren(h('p', { class: 'muted' }, 'loading…'));
  try { await VIEWS[tab](view); } catch (e) { view.replaceChildren(h('div', { class: 'note bad' }, cleanIpc(e))); }
  syncBusy();
}

const fmtDur = (ms) => {
  if (!ms || ms < 0) return '-';
  const s = Math.round(ms / 1000), d = Math.floor(s / 86400), hh = Math.floor(s / 3600) % 24, m = Math.floor(s / 60) % 60;
  return d ? `${d}d ${hh}h` : hh ? `${hh}h ${m}m` : `${m}m ${s % 60}s`;
};
const lineClass = (l) => { const u = l.toUpperCase(); return /ERROR|FATAL|CRASH/.test(u) ? 'e' : /WARN/.test(u) ? 'w' : ''; };
const termLines = (lines) => lines.map((l) => h('div', { class: lineClass(l) }, l));
const needServer = () => !(state.status && state.status.world);

// ============================ views ============================
const VIEWS = {};

VIEWS.server = async (view) => {
  let lastStats = 0;
  const render = async () => {
    if (!$('#modal').hidden) return;   // a dialog is open: do not redraw under it
    const s = state.status || {}, ws = worldState();
    let st = state.stats;
    if (!st || Date.now() - lastStats > 8000) { try { st = state.stats = await call('stats'); lastStats = Date.now(); } catch { /* keep last */ } }
    st = st || {};
    const summary = ws === 'starting' ? ['Server is starting…', 'the world is loading (usually 1-2 minutes); you can connect when it says running']
      : ws === 'stopping' ? ['Server is stopping…', 'saving the world']
      : ws === 'running' ? ['Server is running', 'players can connect']
      : (s.mysql || s.auth) ? ['Game server is stopped', 'database or login service still up'] : ['Server is stopped', ''];
    const badge = (name, state_) => h('div', { class: 'chip' }, h('span', { class: 'dot ' + (state_ === 'running' ? 'good' : state_ === 'stopped' ? '' : 'warn') }), `${name} ${state_}`);
    view.replaceChildren(
      h('h1', {}, 'Server'), h('p', { class: 'sub' }, h('b', {}, summary[0]), ' ', summary[1]),
      h('div', { class: 'cards' },
        h('div', { class: 'card' }, h('div', { class: 't' }, 'Services'), badge('MySQL', s.mysql ? 'running' : 'stopped'), badge('Auth', s.auth ? 'running' : 'stopped'), badge('World', ws)),
        h('div', { class: 'card' }, h('div', { class: 't' }, 'World uptime'), h('div', { class: 'big' }, s.world ? fmtDur(st.uptimeMs) : '-')),
        h('div', { class: 'card' }, h('div', { class: 't' }, 'Characters online'), h('div', { class: 'big' }, s.world && st.dbOk ? st.characters : '-'), h('div', { class: 'small' }, s.world && st.dbOk ? `${st.accounts} account(s)` : '')),
        h('div', { class: 'card' }, h('div', { class: 't' }, 'Disk'), h('div', { class: 'big' }, st.diskTotal ? st.diskFreeH + ' free' : '-'), h('div', { class: 'small' }, st.diskTotal ? 'backups ' + st.backupsH : ''))),
      h('div', { class: 'row' },
        idle(h('button', { class: 'primary', disabled: s.world, onclick: () => act('serverStart') }, 'Start servers')),
        idle(h('button', { disabled: !(s.world || s.auth), onclick: async () => { const r = await confirmBox('Safe stop?', 'Players get an in-game countdown and the world is saved before the servers stop. MySQL is stopped too.', { ok: 'Stop servers' }); if (r) act('serverStop'); } }, 'Safe stop')),
        idle(h('button', { disabled: s.mysql, onclick: () => act('mysqlStart') }, 'Start MySQL only')),
        idle(h('button', { class: 'danger', onclick: async () => {
          const r = await confirmBox('Reset to fresh install?', 'Replaces ALL databases (accounts, characters, garrisons, everything) with the snapshot taken right after install. The servers are stopped for this and started again afterwards.\nThis cannot be undone unless you make a backup first.', { danger: true, ok: 'Reset server', backup: 'default-on' });
          if (r) act('serverReset', { backup: r.backup });
        } }, 'Reset to fresh install…'))),
      h('p', { class: 'muted' }, "The game server's text output is on the Output tab; log files are on Logs."));
    syncBusy();
  };
  state.render = render; await render();   // refreshStatus() redraws this tab every 2.5 s
};

VIEWS.output = async (view) => {
  const term = h('div', { class: 'term' });
  const inp = h('input', { class: 'grow', placeholder: 'worldserver console command, e.g. server info  /  announce hello', onkeydown: (e) => { if (e.key === 'Enter') send(); } });
  const send = async () => { const c = inp.value.trim(); if (!c) return; const r = await act('console', c, { okToast: false }); if (r) { inp.value = ''; setTimeout(tick, 600); } };
  view.replaceChildren(h('h1', {}, 'Output'), h('p', { class: 'sub' }, 'Live text of the game server (world.out). Type a console command below.'),
    h('div', { class: 'row' }, inp, h('button', { class: 'primary', onclick: send }, 'Send')), term);
  let stick = true; term.addEventListener('scroll', () => { stick = term.scrollTop + term.clientHeight >= term.scrollHeight - 30; });
  const tick = async () => { const lines = await call('worldTail', 300); term.replaceChildren(...termLines(lines)); if (stick) term.scrollTop = term.scrollHeight; };
  await tick(); every(1500, () => tick().catch(() => {}));
};

VIEWS.logs = async (view) => {
  const files = await call('logFiles');
  const q = { file: files[0] || '', filter: '', errorsOnly: false, paused: false };
  const term = h('div', { class: 'term' });
  const tabs = h('div', { class: 'row' });
  const filt = h('input', { placeholder: 'filter text…', oninput: () => { q.filter = filt.value; tick(); } });
  const eo = h('input', { type: 'checkbox', onchange: () => { q.errorsOnly = eo.checked; tick(); } });
  const pause = h('input', { type: 'checkbox', onchange: () => { q.paused = pause.checked; } });
  const buildTabs = () => tabs.replaceChildren(...files.map((f) => h('button', { class: f === q.file ? 'primary small' : 'small', onclick: () => { q.file = f; buildTabs(); tick(); } }, f)));
  const tick = async () => {
    if (q.paused || !q.file) return;
    const lines = await call('readLog', { file: q.file, lines: 400, filter: q.filter, errorsOnly: q.errorsOnly });
    const stick = term.scrollTop + term.clientHeight >= term.scrollHeight - 30;
    term.replaceChildren(...termLines(lines.length ? lines : ['(no matching lines)']));
    if (stick) term.scrollTop = term.scrollHeight;
  };
  buildTabs();
  view.replaceChildren(h('h1', {}, 'Logs'), h('p', { class: 'sub' }, 'Files in the server\'s logs/ folder. Errors are red, warnings yellow.'), tabs,
    h('div', { class: 'row' }, filt, h('label', { class: 'row muted' }, eo, 'errors/warnings only'), h('label', { class: 'row muted' }, pause, 'pause')), term);
  await tick(); every(2000, () => tick().catch(() => {}));
};

VIEWS.accounts = async (view) => {
  let filter = '';
  const wrap = h('div');
  const load = async () => {
    const { rows, bots } = await call('accounts');
    const up = !needServer();
    const vis = rows.filter((r) => !filter || r.name.toLowerCase().includes(filter.toLowerCase()));
    const tbl = h('table', {}, h('thead', {}, h('tr', {}, ['Id', 'Account', 'GM level', 'Characters', 'Online', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, vis.map((r) => h('tr', {},
        h('td', {}, r.id), h('td', {}, h('b', {}, r.name)), h('td', {}, ['player', 'moderator', 'GM', 'admin'][r.gm] + ` (${r.gm})`), h('td', {}, r.chars),
        h('td', {}, r.online ? h('span', { class: 'tag good' }, 'online') : h('span', { class: 'tag' }, 'offline')),
        h('td', {}, h('div', { class: 'row flush' },
          idle(h('button', { class: 'small', disabled: !up, onclick: async () => { const d = await dialog({ title: 'GM level for ' + r.name, fields: [{ name: 'gm', label: 'Level', type: 'select', value: String(r.gm), options: [['0', '0 - player'], ['1', '1 - moderator'], ['2', '2 - GM'], ['3', '3 - admin']] }], ok: 'Set level' }); if (d) { await act('acctGm', { name: r.name, gm: +d.values.gm }); load(); } } }, 'GM level')),
          idle(h('button', { class: 'small', disabled: !up, onclick: async () => { const d = await dialog({ title: 'New password for ' + r.name, body: 'Max 16 characters, no spaces or quotes.', fields: [{ name: 'pw', label: 'Password', type: 'password', max: 16 }], ok: 'Change password' }); if (d) await act('acctPass', { name: r.name, pass: d.values.pw }); } }, 'Password')),
          idle(h('button', { class: 'small danger', disabled: !up || r.name.toUpperCase() === 'AHBOT', onclick: async () => { const d = await confirmBox('Delete account ' + r.name + '?', 'This also deletes all of its characters. It cannot be undone.', { danger: true, ok: 'Delete' }); if (d) { await act('acctDelete', { name: r.name }); load(); } } }, 'Delete'))))))));
    wrap.replaceChildren(!up ? h('div', { class: 'note' }, 'Start the servers first (Server tab): account changes go through the running worldserver.') : null, tbl, h('p', { class: 'muted' }, `${rows.length} account(s)` + (bots ? `, plus ${bots} bot account(s) hidden` : '')));
    syncBusy();
  };
  state.render = load;
  const search = h('input', { placeholder: 'search accounts…', oninput: () => { filter = search.value; load(); } });
  view.replaceChildren(h('h1', {}, 'Accounts'), h('p', { class: 'sub' }, 'Player accounts of this server.'),
    h('div', { class: 'row' }, search, idle(h('button', { class: 'primary', onclick: async () => {
      const d = await dialog({ title: 'New account', fields: [{ name: 'name', label: 'Account name (letters, digits, _ ; max 17)', max: 17 }, { name: 'pw', label: 'Password (max 16, no spaces)', type: 'password', max: 16 }, { name: 'gm', label: 'GM level', type: 'select', value: '0', options: [['0', '0 - player'], ['1', '1 - moderator'], ['2', '2 - GM'], ['3', '3 - admin']] }], ok: 'Create account' });
      if (d) { await act('acctCreate', { name: d.values.name.trim(), pass: d.values.pw, gm: +d.values.gm }); load(); }
    } }, 'New account…'))), wrap);
  await load(); every(5000, () => load().catch(() => {}));
};

VIEWS.modules = async (view) => {
  const wrap = h('div');
  const load = async () => {
    const m = await call('modules');
    const tbl = h('table', {}, h('thead', {}, h('tr', {}, ['Enabled', 'Module', 'Commit', 'State', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, m.mods.map((e) => h('tr', {},
        h('td', {}, idle(h('input', { type: 'checkbox', checked: e.enabled, onchange: async (ev) => { await act('modToggle', { name: e.name, on: ev.target.checked }, { okToast: false }); load(); } }))),
        h('td', {}, h('b', {}, e.name), h('div', { class: 'muted mono' }, e.url || '')), h('td', { class: 'mono' }, (e.commit || '').slice(0, 8)),
        h('td', {}, !!e.enabled !== !!e.built ? h('span', { class: 'tag warn' }, e.enabled ? 'will be added' : 'will be removed') : h('span', { class: 'tag ' + (e.built ? 'good' : '') }, e.built ? 'built in' : 'off')),
        h('td', {}, idle(h('button', { class: 'small danger', onclick: async () => { const d = await confirmBox('Remove ' + e.name + '?', 'Deletes the module source. Apply afterwards to rebuild the server without it.', { danger: true, ok: 'Remove' }); if (d) { await act('modRemove', { name: e.name }); load(); } } }, 'Remove')))))));
    wrap.replaceChildren(
      m.pending ? h('div', { class: 'note' }, 'Changes are waiting: press "Apply (rebuild)" to build the server with the new module set. This takes a while and stops the servers.') : null,
      tbl,
      h('div', { class: 'row' },
        idle(h('button', { class: 'primary', disabled: !m.pending, onclick: async () => { const d = await confirmBox('Rebuild the server with these modules?', 'The server is stopped, rebuilt in the build box (this can take a long time) and the configs are regenerated.', { ok: 'Apply (rebuild)', backup: 'default-on' }); if (d) act('modApply', { backup: d.backup }); } }, 'Apply (rebuild)')),
        idle(h('button', { disabled: !m.canUndo, onclick: async () => { const d = await confirmBox('Undo the last module change?', 'Goes back to the previous module set (rebuild).', { ok: 'Undo' }); if (d) act('modUndo'); } }, 'Undo last change')),
        idle(h('button', { onclick: async () => { const d = await dialog({ title: 'Add a module', body: 'Plain https git URL of an AzerothCore module (folder name starts with mod-). It is added enabled; press Apply to build it.', fields: [{ name: 'url', label: 'Git URL', placeholder: 'https://github.com/user/mod-something' }], ok: 'Add' }); if (d) { await act('modAdd', { url: d.values.url.trim() }); load(); } } }, 'Add module…'))));
    syncBusy();
  };
  state.render = load;
  view.replaceChildren(h('h1', {}, 'Modules'), h('p', { class: 'sub' }, 'Server modules (the server is rebuilt when you apply changes).'), wrap);
  await load();
};

VIEWS.backups = async (view) => {
  const wrap = h('div');
  const load = async () => {
    const bs = await call('backups');
    wrap.replaceChildren(bs.length ? h('table', {}, h('thead', {}, h('tr', {}, ['Backup', 'Contains', 'Size', 'Created', ''].map((x) => h('th', {}, x)))),
      h('tbody', {}, bs.map((b) => h('tr', {},
        h('td', {}, h('b', {}, b.name), b.name === 'fresh' ? h('span', { class: 'tag blue ml' }, 'master') : null, b.label ? h('div', { class: 'muted' }, b.label) : null),
        h('td', { class: 'mono' }, b.dbs.map((d) => d.replace('acore_', '')).join(', ')), h('td', {}, b.sizeH), h('td', {}, new Date(b.time).toLocaleString()),
        h('td', {}, h('div', { class: 'row flush' },
          idle(h('button', { class: 'small', onclick: async () => {
            const boxes = b.dbs.map((d) => h('label', { class: 'row muted' }, h('input', { type: 'checkbox', checked: true, 'data-db': d }), d));
            const d = await dialog({ title: 'Restore ' + b.name + '?', body: 'REPLACES the ticked databases with this backup. The servers are stopped for the restore and started again afterwards.', danger: true, ok: 'Restore', backup: 'default-on', extra: h('div', { id: 'dbpick' }, boxes) });
            if (d) { act('backupRestore', { name: b.name, dbs: [...document.querySelectorAll('#dbpick input')].filter((i) => i.checked).map((i) => i.dataset.db), backup: d.backup }); }
          } }, 'Restore…')),
          b.name === 'fresh' ? null : idle(h('button', { class: 'small danger', onclick: async () => { const d = await confirmBox('Delete backup ' + b.name + '?', 'This removes the backup files for good.', { danger: true, ok: 'Delete' }); if (d) { await act('backupDelete', { name: b.name }); load(); } } }, 'Delete')))))))) : h('div', { class: 'note' }, 'No backups yet.'));
    syncBusy();
  };
  state.render = load;
  view.replaceChildren(h('h1', {}, 'Backups'), h('p', { class: 'sub' }, 'Database backups. The install-time master (fresh) is what "Reset" uses and cannot be deleted here.'),
    h('div', { class: 'row' },
      idle(h('button', { class: 'primary', onclick: async () => { const d = await dialog({ title: 'Full backup', body: 'All four databases (accounts, characters, bots, world).', fields: [{ name: 'label', label: 'Label (optional)', max: 40 }], ok: 'Create backup' }); if (d) { await act('backupCreate', { kind: 'full', label: d.values.label }); load(); } } }, 'Full backup…')),
      idle(h('button', { onclick: async () => { const d = await dialog({ title: 'Player-data backup', body: 'Accounts, characters and bots, without the re-creatable world data (smaller).', fields: [{ name: 'label', label: 'Label (optional)', max: 40 }], ok: 'Create backup' }); if (d) { await act('backupCreate', { kind: 'player', label: d.values.label }); load(); } } }, 'Player backup…')),
      h('button', { onclick: () => act('backupsOpen', null, { okToast: false }) }, 'Open backups folder')),
    wrap);
  await load();
};

VIEWS.options = async (view) => {
  const wrap = h('div');
  const load = async () => {
    const [tr, lt, gc] = await Promise.all([call('training'), call('logToggles'), call('garrisonCounts')]);
    const sw = (which, title, desc, on) => h('div', { class: 'addon' }, h('div', { class: 'grow' }, h('div', { class: 'nm' }, title), h('div', { class: 'ds' }, desc)),
      idle(h('button', { class: on ? 'primary' : '', onclick: async () => {
        const d = await confirmBox(`${title} -> ${on ? 'OFF (original prices come back)' : 'ON (training costs nothing)'}`, 'Only gold prices change; level, faction and quest requirements stay. The original prices are kept in the database and restored when you switch it off. A running world is restarted by the change.', { ok: 'Apply', backup: 'default-off' });
        if (d) { await act('trainingSet', { which, on: !on, backup: d.backup }); load(); }
      } }, on ? 'ON' : 'OFF')));
    wrap.replaceChildren(
      h('h2', {}, 'Free training'),
      h('div', { class: 'list' },
        sw('class', 'Free class training', 'class trainers cost nothing (all spells, ranks, Parry, Dual Wield, Mail/Plate, Mage portals)', tr.class),
        sw('riding', 'Free riding training', 'Apprentice to Cold Weather Flying cost nothing (levels unchanged; mounts not included)', tr.riding)),
      h('h2', {}, 'Log files'),
      h('table', {}, h('thead', {}, h('tr', {}, ['Log', 'What it holds', 'Size', 'Enabled'].map((x) => h('th', {}, x)))),
        h('tbody', {}, lt.map((t) => h('tr', {}, h('td', { class: 'mono' }, t.name), h('td', { class: 'muted' }, t.desc), h('td', {}, t.size < 0 ? '-' : humanB(t.size)),
          h('td', {}, h('input', { type: 'checkbox', checked: t.enabled, onchange: async (e) => { await act('logSet', { name: t.name, on: e.target.checked }); load(); } })))))),
      h('div', { class: 'row' },
        h('button', { onclick: () => act('clearMysqlLog') }, 'Clear mysqld.log'),
        h('button', { onclick: async () => { await act('emptyLogs'); load(); } }, 'Empty disabled log files')),
      h('h2', {}, 'Garrison data'),
      h('p', { class: 'muted' }, `Claimed garrisons: ${gc.owners} · placed items: ${gc.objects} · decor pieces: ${gc.decor}`),
      h('div', { class: 'row' },
        idle(h('button', { class: 'danger', onclick: async () => { const d = await confirmBox("Empty ALL players' garrison data?", `Removes every claimed garrison (${gc.owners}), placed item (${gc.objects}) and decor piece (${gc.decor}) of every account. The tables themselves stay; locations and the catalog are not touched. The servers are stopped for this and started again afterwards.\nThis cannot be undone.`, { danger: true, ok: 'Empty garrison data', backup: 'default-on' }); if (d) { await act('garrisonWipe', { backup: d.backup }); load(); } } }, 'Empty garrison data…')),
        idle(h('button', { onclick: async () => { const d = await confirmBox('Remove garrison data of deleted accounts?', 'Deletes leftover garrison claims, items and decor whose account no longer exists. Other players are not affected.', { ok: 'Clean up', backup: 'default-off' }); if (d) { await act('garrisonOrphans', { backup: d.backup }); load(); } } }, 'Clean deleted accounts…'))));
    syncBusy();
  };
  state.render = load;
  view.replaceChildren(h('h1', {}, 'Options'), h('p', { class: 'sub' }, 'Free training switches, log files and garrison maintenance.'), wrap);
  await load();
};
const humanB = (n) => { if (n < 1024) return n + ' B'; const u = ['KB', 'MB', 'GB']; let i = -1; do { n /= 1024; i++; } while (n >= 1024 && i < 2); return n.toFixed(n >= 10 ? 0 : 1) + ' ' + u[i]; };

VIEWS.config = async (view) => {
  const r = await call('realm');
  const a = h('input', { value: r.address, placeholder: 'address players connect to', class: 'grow' });
  const l = h('input', { value: r.local, placeholder: 'LAN address', class: 'grow' });
  const save = async () => { await act('realmSave', { address: a.value, local: l.value }); };
  view.replaceChildren(h('h1', {}, 'Config'), h('p', { class: 'sub' }, 'The address the login server hands to clients, and the client addon archive.'),
    !r.up ? h('div', { class: 'note' }, 'Start MySQL first (Server tab) to read or save the realmlist.') : null,
    h('h2', {}, 'Realmlist'),
    h('div', { class: 'row' }, h('label', { class: 'f grow' }, 'Address (what players put in their realmlist.wtf)', a), h('label', { class: 'f grow' }, 'Local / LAN address', l)),
    h('div', { class: 'row' },
      idle(h('button', { class: 'primary', disabled: !r.up, onclick: save }, 'Save')),
      h('button', { disabled: !r.up, onclick: async () => { const ips = await call('lanDetect'); if (!ips.length) { toast('no LAN address found (is this machine on a network?)', true); return; } l.value = ips[0]; await save(); toast('LAN address ' + ips[0] + (ips.length > 1 ? ' (other addresses found: ' + ips.slice(1).join(', ') + ')' : '')); } }, 'Detect LAN address'),
      h('button', { disabled: !r.up, onclick: async () => { a.value = '127.0.0.1'; l.value = '127.0.0.1'; await save(); toast('localhost: only this computer can connect'); } }, 'Use localhost')),
    h('h2', {}, 'Client addon archive'),
    h('p', { class: 'muted' }, 'Builds a zip / tar.gz of the addons that unpacks straight into a WoW client folder. Use the "Client addons" tab to install them for yourself; give the zip to friends.'),
    h('div', { class: 'row' }, idle(h('button', { onclick: () => act('clientPatch') }, 'Build client patch archive')), h('button', { onclick: () => act('clientPatchOpen', null, { okToast: false }) }, 'Open its folder')));
};

VIEWS.client = async (view) => {
  const wrap = h('div');
  const sel = new Set();
  const load = async () => {
    const g = await call('clientGet');
    const c = g.client;
    const stTag = (s) => s === 'current' ? h('span', { class: 'tag good' }, 'installed, up to date') : s === 'outdated' ? h('span', { class: 'tag warn' }, 'installed, differs from the server\'s copy') : s === 'missing' ? h('span', { class: 'tag' }, 'not installed') : h('span', { class: 'tag' }, '-');
    const names = g.addons.map((x) => x.name);
    const act2 = (verb, list) => act(verb, { names: list }).then(load);
    wrap.replaceChildren(
      h('h2', {}, 'Your WoW client'),
      h('div', { class: 'path' }, g.clientPath || 'No client folder chosen yet'),
      !c.valid && g.clientPath ? h('div', { class: 'note bad' }, c.reason) : null,
      h('div', { class: 'row' }, idle(h('button', { class: 'primary', onclick: async () => { const r = await act('clientPick', null, { okToast: false }); if (r && !r.canceled) { toast('client folder set'); load(); } } }, g.clientPath ? 'Change folder…' : 'Choose WoW folder…')),
        g.clientPath ? h('button', { class: 'ghost', onclick: async () => { await act('clientForget', null, { okToast: false }); load(); } }, 'Forget') : null),
      h('p', { class: 'muted' }, 'Pick the folder that holds Wow.exe and Data (or its Interface/AddOns folder). The launcher only ever copies or deletes OUR addons below, never your other AddOns, and it does not start the game.'),
      c.valid ? h('div', {}, h('div', { class: 'muted mono' }, 'AddOns folder: ' + c.addonsDir),
        h('h2', {}, 'Our addons'),
        h('div', { class: 'list' }, g.addons.map((a) => h('div', { class: 'addon' },
          h('input', { type: 'checkbox', checked: sel.has(a.name) || (a.required && false), onchange: (e) => { e.target.checked ? sel.add(a.name) : sel.delete(a.name); } }),
          h('div', { class: 'grow' }, h('div', { class: 'nm' }, a.title, a.name !== a.title ? h('span', { class: 'muted mono ml lite' }, a.name) : null, a.required ? h('span', { class: 'tag blue ml' }, 'required') : null, a.gmOnly ? h('span', { class: 'tag ml' }, 'GM only') : null), a.notes ? h('div', { class: 'ds' }, a.notes) : null),
          stTag(a.state)))),
        h('div', { class: 'row' },
          idle(h('button', { class: 'primary', onclick: () => { const l = [...sel]; if (!l.length) return toast('tick the addons to install or update first', true); act2('clientInstall', l); } }, 'Install / update ticked')),
          idle(h('button', { onclick: () => act2('clientInstall', g.addons.filter((a) => !a.gmOnly).map((a) => a.name)) }, 'Install / update all (players)')),
          idle(h('button', { class: 'danger', onclick: async () => { const l = [...sel]; if (!l.length) return toast('tick the addons to remove first', true); const d = await confirmBox('Remove ' + l.length + ' addon(s)?', 'Deletes these of OUR addon folders from your client: ' + l.join(', '), { danger: true, ok: 'Remove' }); if (d) act2('clientRemove', l); } }, 'Remove ticked')),
          idle(h('button', { class: 'danger', onclick: async () => { const d = await confirmBox('Remove all of our addons?', 'Deletes every addon of ours that is in your client: ' + names.join(', ') + '.\nOther AddOns are not touched.', { danger: true, ok: 'Remove all' }); if (d) act2('clientRemove', names); } }, 'Remove all ours'))),
        h('p', { class: 'muted' }, 'After installing: in game type /reload (a new addon needs a full log out and back in; check AddOns on the character screen).'),
        h('h2', {}, 'realmlist.wtf (optional)'),
        g.realmlist.length ? h('div', {}, g.realmlist.map((x) => h('div', { class: 'muted mono' }, `${x.file}  →  ${x.address || '(no realmlist line)'}`)),
          h('div', { class: 'row' }, idle(h('button', { onclick: async () => { const rl = await call('realm').catch(() => null); const d = await dialog({ title: 'Set the client realmlist', body: 'Writes "set realmlist <address>" into the client\'s realmlist.wtf. The original file is kept once as realmlist.wtf.bak-launcher.', fields: [{ name: 'addr', label: 'Server address', value: (rl && (rl.local || rl.address)) || '127.0.0.1' }], ok: 'Update realmlist.wtf' }); if (d) { await act('clientRealmSet', { address: d.values.addr.trim() }); load(); } } }, 'Set client realmlist…')))) : h('p', { class: 'muted' }, 'No realmlist.wtf found in this client.')) : null);
    syncBusy();
  };
  state.render = load;
  view.replaceChildren(h('h1', {}, 'Client addons'), h('p', { class: 'sub' }, 'Install or remove our addons in your WoW 3.3.5a client folder.'), wrap);
  await load();
};

// ---- start ----
(async () => {
  try { state.info = await call('appInfo'); } catch { state.info = {}; }
  $('#rootinfo').textContent = state.info.root ? 'Server: ' + state.info.root : 'No server folder found next to the launcher';
  if (!state.info.root) { buildNav(); $('#view').replaceChildren(h('h1', {}, 'No server found'), h('div', { class: 'note bad' }, 'The launcher must live in the server folder (next to acore-admin), or start it with ACORE_ROOT=/path/to/server. The Client addons tab still works if a client-addons folder is next to the launcher.')); return; }
  await refreshStatus();
  setInterval(refreshStatus, 2500);
  go('server');
})();
