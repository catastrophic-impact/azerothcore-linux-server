'use strict';
// Read-only smoke test against a REAL running server: node test/live_readonly.js [server root]. Changes nothing.
const { Admin, human } = require('../lib/admin');
const { findRoot } = require('../lib/paths');
const root = process.argv[2] || findRoot();
(async () => {
  console.log('root', root);
  const a = new Admin(root);
  console.log('status', JSON.stringify(a.status()));
  console.log('stats', JSON.stringify(await a.stats()));
  console.log('backups', a.listBackups().map((b) => `${b.name}(${human(b.size)})`).join(', '));
  console.log('modules', a.modules().mods.length, 'pending', a.modules().pending);
  console.log('training', JSON.stringify(await a.training()));
  console.log('realm', JSON.stringify(await a.realm()));
  const acc = await a.accounts(); console.log('accounts', acc.rows.length, 'bots', acc.bots, acc.rows.slice(0, 3).map((r) => r.name + ':' + r.gm).join(','));
  console.log('logFiles', a.logFiles().join(','));
  console.log('worldTail', a.worldTail(3).length, 'lines');
  console.log('toggles', a.logToggles().map((t) => `${t.name}=${t.enabled}`).join(' '));
  console.log('garrison', JSON.stringify(await a.garrisonCounts()));
  console.log('lan', a.detectLAN().join(','));
})().catch((e) => { console.error('FAILED', e); process.exit(1); });
