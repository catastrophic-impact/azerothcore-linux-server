'use strict';
// LIVE operations test: drives the launcher's real api (the same functions the buttons call) against a REAL running server, including stop / start /
// restore / reset / wipe. DESTRUCTIVE by design and only safe with a baseline backup. Needs ACORE_LAUNCHER_ALLOW_LIVE=yes-i-am-off-the-server.
// Run (host with Electron + display, or xvfb):  ACORE_LAUNCHER_ALLOW_LIVE=... ACORE_LAUNCHER_SCRIPT=$PWD/test/live_ops.js ACORE_LAUNCHER_BASELINE=<backup set name> ./run.sh
const fs = require('fs');
const path = require('path');

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
let pass = 0, fail = 0;
const log = (m) => console.log('LIVE ' + m);
const ok = (name, cond, detail) => { if (cond) { pass++; log(`PASS ${name}${detail ? ' - ' + detail : ''}`); } else { fail++; log(`FAIL ${name}${detail ? ' - ' + detail : ''}`); } return !!cond; };

module.exports = async ({ api, app, admin, dialog, win }) => {
  if (process.env.ACORE_LAUNCHER_ALLOW_LIVE !== 'yes-i-am-off-the-server') { log('refusing to run: set ACORE_LAUNCHER_ALLOW_LIVE=yes-i-am-off-the-server'); app.exit(2); return; }
  const BASE = process.env.ACORE_LAUNCHER_BASELINE;
  const mode = process.env.ACORE_LAUNCHER_LIVE_MODE || 'ops';
  const waitFor = async (fn, ms, what) => { const t = Date.now(); for (;;) { try { const v = await fn(); if (v) return v; } catch { /* retry */ } if (Date.now() - t > ms) throw new Error('timeout waiting for ' + what); await wait(3000); } };
  const ready = () => waitFor(() => { const s = admin.status(); return s.mysql && s.auth && s.world && s.worldReady; }, 420000, 'the world to be ready');
  const snap = async () => {
    const q = async (x) => (await admin.sql(x)).trim();
    return { accounts: await q('SELECT COUNT(*) FROM acore_auth.account'), chars: await q('SELECT COUNT(*) FROM acore_characters.characters'), owner: await q('SELECT COUNT(*) FROM acore_characters.dc_garrison_owner'),
      object: await q('SELECT COUNT(*) FROM acore_characters.dc_garrison_object'), decor: await q('SELECT COUNT(*) FROM acore_characters.dc_garrison_decor'), realm: await q('select address,localaddress from acore_auth.realmlist where id=1') };
  };
  const step = async (name, fn) => { log(`--- ${name}`); try { await fn(); } catch (e) { ok(name + ' (no exception)', false, String(e.message || e).slice(0, 300)); } };

  if (mode === 'quit') {   // the close handler, with the native dialog answered by the test
    const answer = Number(process.env.ACORE_LAUNCHER_QUIT_ANSWER);
    let asked = 0; dialog.showMessageBox = async (_w, o) => { asked++; log(`dialog: "${o.message}" buttons=${JSON.stringify(o.buttons)} -> answering ${answer}`); return { response: answer }; };
    await wait(2500);
    log('status before close: ' + JSON.stringify(admin.status()));
    win.close();
    await wait(answer === 2 ? 3000 : 90000);
    if (answer === 2) { ok('Cancel keeps the window open', !win.isDestroyed() && asked === 1); app.exit(0); }
    return;
  }

  const startSnap = await snap();
  log('baseline snapshot: ' + JSON.stringify(startSnap));
  ok('servers are running at the start', (() => { const s = admin.status(); return s.mysql && s.auth && s.world; })());
  const restoreBaseline = async () => { log('restoring baseline ' + BASE); await api.backupRestore({ name: BASE, dbs: [], backup: false }); await ready(); };

  await step('Safe stop', async () => {
    await api.serverStop();
    const s = admin.status(); ok('all three services stopped', !s.mysql && !s.auth && !s.world, JSON.stringify(s));
  });
  await step('Start servers', async () => {
    await api.serverStart(); await ready(); const s = admin.status(); ok('all three running, world ready', s.mysql && s.auth && s.world && s.worldReady);
    ok('stats work again', (await admin.stats()).dbOk === true);
  });
  await step('Output console', async () => {
    const before = admin.worldTail(50).join('\n'); await api.console('server info'); await wait(2500); const after = admin.worldTail(30).join('\n');
    ok('console command produced output', /uptime|players|connected|revision|AzerothCore/i.test(after), after.split('\n').slice(-3).join(' | ').slice(0, 160));
    try { await api.console(''); ok('empty command rejected', false); } catch (e) { ok('empty command rejected', /empty/.test(e.message)); }
  });
  await step('Accounts', async () => {
    await api.acctCreate({ name: 'LTEST1', pass: 'testpw1', gm: 0 });
    let a = await api.accounts(); ok('created account is listed', a.rows.some((r) => r.name === 'LTEST1'));
    await api.acctGm({ name: 'LTEST1', gm: 1 }); a = await api.accounts(); ok('GM level 1 set', (a.rows.find((r) => r.name === 'LTEST1') || {}).gm === 1);
    await api.acctPass({ name: 'LTEST1', pass: 'testpw2' }); ok('password change accepted', true);
    try { await api.acctCreate({ name: 'LTEST1', pass: 'x', gm: 0 }); ok('duplicate rejected', false); } catch (e) { ok('duplicate rejected', /already exists/.test(e.message)); }
    await api.acctDelete({ name: 'LTEST1' }); a = await api.accounts(); ok('deleted account is gone', !a.rows.some((r) => r.name === 'LTEST1'));
    try { await api.acctDelete({ name: 'AHBOT' }); ok('AHBOT protected', false); } catch (e) { ok('AHBOT protected', /AHBOT/.test(e.message)); }
  });
  await step('Options: log switches', async () => {
    await api.logSet({ name: 'Playerbots.log', on: true }); ok('Playerbots.log switched on', (await api.logToggles()).find((t) => t.name === 'Playerbots.log').enabled);
    await api.logSet({ name: 'Playerbots.log', on: false }); ok('Playerbots.log switched back off', !(await api.logToggles()).find((t) => t.name === 'Playerbots.log').enabled);
    ok('empty disabled logs', /emptied/.test(await api.emptyLogs()));
  });
  await step('Options: free training', async () => {
    const before = await api.training();
    await api.trainingSet({ which: 'class', on: !before.class, backup: false }); await ready();
    ok('class training switched', (await api.training()).class === !before.class);
    await api.trainingSet({ which: 'class', on: before.class, backup: false }); await ready();
    ok('class training restored', (await api.training()).class === before.class);
  });
  await step('Config: realmlist', async () => {
    const r0 = await api.realm(); await api.realmSave({ address: r0.address, local: '192.168.50.149' });
    ok('LAN address saved', (await api.realm()).local === '192.168.50.149');
    await api.realmSave({ address: r0.address, local: r0.local }); const r1 = await api.realm(); ok('realmlist restored', r1.address === r0.address && r1.local === r0.local);
    ok('LAN detect returns an address', (await api.lanDetect()).length > 0);
  });
  await step('Backups: create / list / delete', async () => {
    await api.backupCreate({ kind: 'player', label: 'launcher test' }); const l = await api.backups(); const mine = l.find((b) => /launcher-test$|launcher_test$/.test(b.name) || /launcher.test/.test(b.name) && b.name !== BASE && !/baseline/.test(b.name));
    ok('player backup created + listed', !!mine && mine.dbs.length === 3, mine && mine.name);
    if (mine) { await api.backupDelete({ name: mine.name }); ok('backup deleted', !(await api.backups()).some((b) => b.name === mine.name)); }
    try { await api.backupDelete({ name: 'fresh' }); ok('master protected', false); } catch (e) { ok('master protected', /master/.test(e.message)); }
  });
  await step('Restore round trip', async () => {
    await api.acctCreate({ name: 'LTEST2', pass: 'testpw1', gm: 0 }); ok('marker account created after the baseline', (await api.accounts()).rows.some((r) => r.name === 'LTEST2'));
    await restoreBaseline();
    ok('marker account gone after restore', !(await api.accounts()).rows.some((r) => r.name === 'LTEST2'));
    const s = await snap(); ok('database numbers equal the baseline', JSON.stringify(s) === JSON.stringify(startSnap), JSON.stringify(s));
  });
  await step('Reset to fresh install (with backup first) then restore', async () => {
    const nBefore = (await api.backups()).length;
    await api.serverReset({ backup: true }); await ready();
    const s = await snap(); ok('reset emptied the accounts (fresh state)', Number(s.accounts) < Number(startSnap.accounts), JSON.stringify(s));
    ok('a backup was taken before the reset', (await api.backups()).length === nBefore + 1);
    await restoreBaseline();
    const s2 = await snap(); ok('baseline restored after reset', JSON.stringify(s2) === JSON.stringify(startSnap), JSON.stringify(s2));
  });
  await step('Garrison data tools', async () => {
    const g0 = await api.garrisonCounts(); ok('counts readable', g0.owners === startSnap.owner && g0.objects === startSnap.object && g0.decor === startSnap.decor, JSON.stringify(g0));
    ok('orphan clean-up runs', /removed \d+/.test(await api.garrisonOrphans({ backup: false })));
    await api.garrisonWipe({ backup: false }); await ready(); const g1 = await api.garrisonCounts(); ok('wipe emptied the garrison tables', g1.owners === '0' && g1.objects === '0' && g1.decor === '0', JSON.stringify(g1));
    await restoreBaseline(); const g2 = await api.garrisonCounts(); ok('garrison data back after restore', g2.owners === startSnap.owner && g2.objects === startSnap.object && g2.decor === startSnap.decor, JSON.stringify(g2));
  });
  await step('Modules add / remove', async () => {
    const mj = admin.p('modules', 'modules.json'); const before = fs.readFileSync(mj, 'utf8'); const dirsBefore = fs.readdirSync(admin.p('modules')).sort().join(',');
    try { await api.modAdd({ url: 'http://example.com/x/mod-x' }); ok('non-https rejected', false); } catch (e) { ok('non-https rejected', /https/.test(e.message)); }
    try { await api.modAdd({ url: 'https://github.com/azerothcore/mod-ale' }); ok('duplicate rejected', false); } catch (e) { ok('duplicate rejected', /already present/.test(e.message)); }
    try { await api.modAdd({ url: 'https://github.com/azerothcore/mod-launcher-test-does-not-exist' }); ok('missing repo fails cleanly', false); } catch (e) { ok('missing repo fails cleanly', /clone failed|not found|could not/i.test(e.message), e.message.slice(0, 120)); }
    ok('nothing left behind after the failures', fs.readdirSync(admin.p('modules')).sort().join(',') === dirsBefore);
    try {
      await api.modAdd({ url: 'https://github.com/azerothcore/mod-aoe-loot' });
      const m = await api.modules(); ok('real module added (pending)', m.mods.some((x) => x.name === 'mod-aoe-loot' && x.enabled && !x.built) && m.pending);
      await api.modToggle({ name: 'mod-aoe-loot', on: false }); ok('toggle off', !(await api.modules()).mods.find((x) => x.name === 'mod-aoe-loot').enabled);
      await api.modRemove({ name: 'mod-aoe-loot' }); ok('module removed again', !(await api.modules()).mods.some((x) => x.name === 'mod-aoe-loot'));
    } catch (e) { ok('real module add/remove', false, e.message.slice(0, 200)); }
    ok('modules.json identical to before', fs.readFileSync(mj, 'utf8') === before && fs.readdirSync(admin.p('modules')).sort().join(',') === dirsBefore);
  });
  const fin = await snap(); ok('FINAL: database numbers equal the baseline', JSON.stringify(fin) === JSON.stringify(startSnap), JSON.stringify(fin));
  ok('FINAL: servers running', (() => { const s = admin.status(); return s.mysql && s.auth && s.world && s.worldReady; })());
  log(`RESULT pass=${pass} fail=${fail}`);
  app.exit(fail ? 1 : 0);
};
