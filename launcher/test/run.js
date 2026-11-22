'use strict';
// Backend tests (node --test). Everything runs against throw-away folders in the OS temp dir: a fake server root (with a fake `acore-admin`)
// and a fake WoW client. No Electron, no real server, no network.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Admin, fileContains, tailFile, lineLevel, appenderRe } = require('../lib/admin');
const client = require('../lib/client');
const { findRoot } = require('../lib/paths');

const tmp = (n) => fs.mkdtempSync(path.join(os.tmpdir(), 'acl-' + n + '-'));
const write = (f, s = '') => { fs.mkdirSync(path.dirname(f), { recursive: true }); fs.writeFileSync(f, s); };

// ---- a fake server root ----
function fakeRoot(adminScript) {
  const root = tmp('root');
  write(path.join(root, 'acore-admin'), adminScript || '#!/bin/sh\necho "args: $*"\n');
  fs.chmodSync(path.join(root, 'acore-admin'), 0o755);
  return root;
}

test('findRoot: env, parent, release', () => {
  const root = fakeRoot();
  assert.equal(findRoot({ ACORE_ROOT: root }, '/nonexistent/launcher'), fs.realpathSync(root));
  assert.equal(findRoot({ ACORE_ROOT: root + '/sub/..' }, '/nonexistent/launcher'), fs.realpathSync(root));   // normalised
  const server = fakeRoot(); const ld = path.join(server, 'launcher'); fs.mkdirSync(ld);
  assert.equal(findRoot({}, ld), fs.realpathSync(server));                      // installed layout: <server>/launcher
  const repo = tmp('repo'); const rel = path.join(repo, 'release'); fs.mkdirSync(rel); write(path.join(rel, 'acore-admin'), '#!/bin/sh\n'); fs.mkdirSync(path.join(repo, 'launcher'));
  assert.equal(findRoot({}, path.join(repo, 'launcher')), fs.realpathSync(rel));  // dev layout: <repo>/release
  assert.equal(findRoot({}, '/nonexistent/x'), null);
});

test('log helpers', () => {
  assert.equal(lineLevel('all fine'), 0);
  assert.equal(lineLevel('Some WARNING here'), 1);
  assert.equal(lineLevel('ERROR: boom'), 2);
  assert.equal(lineLevel('worldserver CRASH'), 2);
  const f = path.join(tmp('log'), 'x.log');
  write(f, Array.from({ length: 1000 }, (_, i) => `line ${i}`).join('\n') + '\n');
  const t = tailFile(f, 5);
  assert.deepEqual(t, ['line 995', 'line 996', 'line 997', 'line 998', 'line 999']);
  assert.deepEqual(tailFile(path.join(tmp('none'), 'missing'), 5), []);
  write(f, '\x1b[31mred\x1b[0m text\n');
  assert.deepEqual(tailFile(f, 3), ['red text']);              // colour codes stripped
});

test('fileContains finds text across chunk borders and in huge files', () => {
  const f = path.join(tmp('big'), 'w.out');
  const pad = 'a'.repeat((1 << 20) - 3);                       // "ready..." straddles the 1 MiB chunk border
  write(f, pad + 'ready...' + 'b'.repeat(100));
  assert.equal(fileContains(f, 'ready...'), true);
  write(f, pad + 'ready.. nope');
  assert.equal(fileContains(f, 'ready...'), false);
  assert.equal(fileContains(path.join(tmp('x'), 'missing'), 'x'), false);
});

test('world readiness is remembered per process', () => {
  const root = fakeRoot(); const a = new Admin(root);
  write(root + '/logs/world.out', 'loading\n');
  assert.equal(a.worldReady(111), false);
  write(root + '/logs/world.out', 'loading\nAzerothCore ready...\n');
  assert.equal(a.worldReady(111), true);
  write(root + '/logs/world.out', 'x\n'.repeat(5000));       // the line scrolled away / file replaced
  assert.equal(a.worldReady(111), true);                      // same process: stays ready
  assert.equal(a.worldReady(222), false);                     // a new process starts again
});

test('readLog: filter, errors only, path safety', () => {
  const root = fakeRoot(); const a = new Admin(root);
  write(root + '/logs/Server.log', 'ok one\nWARN two\nERROR three\nok four\n');
  assert.equal(a.readLog('Server.log', {}).length, 4);
  assert.deepEqual(a.readLog('Server.log', { filter: 'ok' }), ['ok one', 'ok four']);
  assert.deepEqual(a.readLog('Server.log', { errorsOnly: true }), ['WARN two', 'ERROR three']);
  assert.deepEqual(a.readLog('../../etc/passwd', {}), []);     // no traversal
  assert.deepEqual(a.logFiles(), ['Server.log']);
});

test('log switches edit the conf like the TUI', () => {
  const root = fakeRoot(); const a = new Admin(root);
  write(root + '/etc/worldserver.conf', 'Appender.Playerbots=2,5,0,Playerbots.log,w\nAppender.Server=2,5,0,Server.log,w\nAppender.Errors=2,2,0,Errors.log,w\nOther=1\n');
  write(root + '/etc/authserver.conf', 'Appender.Auth=2,5,0,Auth.log,w\n');
  assert.ok(a.logToggles().every((t) => t.enabled));
  assert.match(a.setLog('Playerbots.log', false), /OFF/);
  let conf = fs.readFileSync(root + '/etc/worldserver.conf', 'utf8');
  assert.match(conf, /Appender\.Playerbots=2,0,0,Playerbots\.log,w/);
  assert.match(conf, /Appender\.Server=2,5,0/);                // others untouched
  assert.equal(a.logToggles().find((t) => t.name === 'Playerbots.log').enabled, false);
  a.setLog('Playerbots.log', true);
  assert.match(fs.readFileSync(root + '/etc/worldserver.conf', 'utf8'), /Appender\.Playerbots=2,5,0/);
  assert.throws(() => a.setLog('Nope.log', true), /unknown/);
  // empty disabled logs
  a.setLog('Server.log', false); write(root + '/logs/Server.log', 'x'.repeat(100)); write(root + '/logs/Errors.log', 'keep');
  assert.match(a.emptyDisabledLogs(), /emptied 1/);
  assert.equal(fs.statSync(root + '/logs/Server.log').size, 0);
  assert.equal(fs.readFileSync(root + '/logs/Errors.log', 'utf8'), 'keep');
  assert.ok(appenderRe('Appender.Auth').test('Appender.Auth=2,5,0,Auth.log,w'));
});

test('backups: list order, delete guards', () => {
  const root = fakeRoot(); const a = new Admin(root);
  for (const [n, t] of [['fresh', 1000], ['2026-01-01_000000_full', 3000], ['2026-02-01_000000_player', 5000]]) {
    const d = path.join(root, 'backups', n);
    write(path.join(d, 'acore_auth.sql.gz'), 'x'.repeat(10)); write(path.join(d, 'acore_world.sql'), 'y'.repeat(5)); write(path.join(d, 'meta.txt'), 'full my label\ncreated x\n');
    fs.utimesSync(d, t, t);
  }
  write(root + '/backups/empty/readme.txt', 'no dumps');        // not a backup set
  const l = a.listBackups();
  assert.deepEqual(l.map((b) => b.name), ['fresh', '2026-02-01_000000_player', '2026-01-01_000000_full']);   // master pinned, then newest first
  assert.equal(l[0].size, 15); assert.deepEqual(l[0].dbs, ['acore_auth', 'acore_world']); assert.equal(l[0].label, 'full my label');
  assert.throws(() => a.deleteBackup('fresh'), /master/);
  assert.throws(() => a.deleteBackup('../etc'), /bad name/);
  assert.throws(() => a.deleteBackup(''), /bad name/);
  assert.match(a.deleteBackup('2026-01-01_000000_full'), /deleted/);
  assert.equal(a.listBackups().length, 2);
});

test('modules.json', () => {
  const root = fakeRoot(); const a = new Admin(root);
  assert.deepEqual(a.modules().mods, []);
  write(root + '/modules/modules.json', JSON.stringify({ mods: [{ name: 'mod-b', enabled: true, built: true }, { name: 'mod-a', enabled: true, built: false, url: 'https://x' }], prevEnabled: [] }));
  const m = a.modules();
  assert.deepEqual(m.mods.map((x) => x.name), ['mod-a', 'mod-b']);
  assert.equal(m.pending, true);
});

test('detectLAN: private addresses only, virtual interfaces skipped, 192.168 first', () => {
  const a = new Admin(fakeRoot());
  const ifs = {
    lo: [{ family: 'IPv4', address: '127.0.0.1', internal: true }],
    docker0: [{ family: 'IPv4', address: '172.17.0.1', internal: false }],
    eth0: [{ family: 'IPv4', address: '10.0.0.5', internal: false }, { family: 'IPv6', address: 'fe80::1', internal: false }],
    wlan0: [{ family: 'IPv4', address: '192.168.1.20', internal: false }, { family: 'IPv4', address: '8.8.8.8', internal: false }],
  };
  assert.deepEqual(a.detectLAN(ifs), ['192.168.1.20', '10.0.0.5']);
});

test('accounts: validation before anything is sent', async () => {
  const a = new Admin(fakeRoot());
  await assert.rejects(a.createAccount('bad name', 'pw'), /name/);
  await assert.rejects(a.createAccount('good', 'has space'), /password/);
  await assert.rejects(a.createAccount('good', 'x'.repeat(17)), /password/);
  await assert.rejects(a.createAccount('good', 'pw', 7), /GM level/);
  await assert.rejects(a.createAccount('good', 'pw'), /start the servers first/);   // world not running
  await assert.rejects(a.deleteAccount('AHBOT'), /AHBOT/);
  await assert.rejects(a.deleteAccount("x';drop"), /bad account name/);
  await assert.rejects(a.setGm('good', 9), /GM level/);
});

test('calls acore-admin with the right arguments (fake binary)', async () => {
  const root = fakeRoot('#!/bin/sh\necho "ARGS[$*]"\ncase "$1" in training) echo "class training free: true, riding training free: false";; sql) echo "x";; esac\n');
  const a = new Admin(root);
  assert.match(await a.must(['stop']), /ARGS\[stop\]/);
  assert.deepEqual(await a.training(), { class: true, riding: false });
  assert.match(await a.setTraining('riding', true), /ARGS\[training riding on\]/);
  await assert.rejects(async () => a.setTraining('bogus', true), /bad switch/);
  assert.match(await a.addModule('https://github.com/a/mod-x'), /ARGS\[modules add https:\/\/github.com\/a\/mod-x\]/);
  assert.match(await a.createBackup('full', 'my label!!'), /ARGS\[backup full my label\]/);   // label sanitised
  assert.throws(() => a.createBackup('weird'), /unknown backup kind/);
  const lines = []; await a.run(['start'], { onLine: (l) => lines.push(l) });
  assert.deepEqual(lines, ['ARGS[start]']);
  const bad = new Admin(fakeRoot('#!/bin/sh\necho "error: boom" >&2\nexit 1\n'));
  await assert.rejects(bad.must(['start']), /boom/);
});

test('realm validation', async () => {
  const a = new Admin(fakeRoot());
  await assert.rejects(a.saveRealm("1.2.3.4'; drop", '1.2.3.4'), /invalid address/);
  await assert.rejects(a.saveRealm('', ''), /invalid address/);
});

// ---------------- client addons ----------------
function fakeAddons(root) {
  const src = path.join(root, 'client-addons');
  for (const [n, extra] of [['AcoreLib', ''], ['wotlk_shop', '## Dependencies: AcoreLib\n'], ['wotlk_pets', ''], ['wotlk_garrison_admin', '']]) {
    write(path.join(src, n, n + '.toc'), `## Title: ${n} title\n## Notes: notes of ${n}\n${extra}file.lua\n`);
    write(path.join(src, n, 'file.lua'), '-- ' + n);
  }
  write(path.join(src, 'NotAnAddon', 'readme.txt'), 'no toc');   // ignored: no .toc
  return src;
}
function fakeClient() {
  const c = tmp('wow');
  write(path.join(c, 'Wow.exe'), 'x'); fs.mkdirSync(path.join(c, 'Data')); fs.mkdirSync(path.join(c, 'Interface', 'AddOns'), { recursive: true });
  write(path.join(c, 'Data', 'enUS', 'realmlist.wtf'), 'set realmlist old.example.com\n');
  write(path.join(c, 'Interface', 'AddOns', 'Atlas', 'Atlas.toc'), '## Title: Atlas\n');   // somebody else's addon
  return c;
}

test('our addon list: toc parsing, required first, GM-only flag', () => {
  const root = fakeRoot(); fakeAddons(root);
  const l = client.listOurAddons(root);
  assert.deepEqual(l.map((a) => a.name), ['AcoreLib', 'wotlk_garrison_admin', 'wotlk_pets', 'wotlk_shop']);
  assert.equal(l[0].required, true);
  assert.equal(l.find((a) => a.name === 'wotlk_garrison_admin').gmOnly, true);
  assert.deepEqual(l.find((a) => a.name === 'wotlk_shop').deps, ['AcoreLib']);
  assert.equal(l[0].title, 'AcoreLib title');
});

test('client folder validation: root, Interface, AddOns accepted; junk rejected', () => {
  const c = fakeClient();
  for (const p of [c, path.join(c, 'Interface'), path.join(c, 'Interface', 'AddOns')]) {
    const r = client.resolveClient(p);
    assert.ok(r.valid, p); assert.equal(r.root, c); assert.equal(r.addonsDir, path.join(c, 'Interface', 'AddOns'));
  }
  assert.equal(client.resolveClient(os.tmpdir()).valid, false);
  assert.equal(client.resolveClient('/nonexistent').valid, false);
  assert.equal(client.resolveClient('').valid, false);
});

test('install pulls in AcoreLib + dependencies, never touches other addons, update + remove', () => {
  const root = fakeRoot(); fakeAddons(root); const c = fakeClient();
  const before = client.addonStates(root, c, {});
  assert.ok(before.addons.every((a) => a.state === 'missing'));
  let r = client.installAddons(root, c, ['wotlk_shop'], {});
  assert.deepEqual(r.done.sort(), ['AcoreLib', 'wotlk_shop']);
  const add = path.join(c, 'Interface', 'AddOns');
  assert.ok(fs.existsSync(path.join(add, 'AcoreLib', 'file.lua')) && fs.existsSync(path.join(add, 'wotlk_shop', 'file.lua')));
  assert.ok(fs.existsSync(path.join(add, 'Atlas', 'Atlas.toc')));             // someone else's addon untouched
  assert.equal(client.addonStates(root, c, r.installed).addons.find((a) => a.name === 'wotlk_shop').state, 'current');
  // server copy changes -> outdated -> update brings it current, and removes stale files
  write(path.join(root, 'client-addons', 'wotlk_shop', 'file.lua'), '-- changed');
  assert.equal(client.addonStates(root, c, r.installed).addons.find((a) => a.name === 'wotlk_shop').state, 'outdated');
  write(path.join(add, 'wotlk_shop', 'stale.lua'), 'old');
  r = client.installAddons(root, c, ['wotlk_shop'], r.installed);
  assert.equal(fs.readFileSync(path.join(add, 'wotlk_shop', 'file.lua'), 'utf8'), '-- changed');
  assert.ok(!fs.existsSync(path.join(add, 'wotlk_shop', 'stale.lua')));
  assert.ok(!fs.readdirSync(add).some((x) => x.includes('launcher-')));        // no temp folders left behind
  // remove: only ours; warns when AcoreLib goes while another of ours remains
  const rm = client.removeAddons(root, c, ['AcoreLib'], r.installed);
  assert.deepEqual(rm.done, ['AcoreLib']); assert.match(rm.warnings[0], /wotlk_shop/);
  const rm2 = client.removeAddons(root, c, ['wotlk_shop', 'Atlas', '../Data'], rm.installed);   // Atlas / traversal are not ours: ignored
  assert.deepEqual(rm2.done, ['wotlk_shop']);
  assert.ok(fs.existsSync(path.join(add, 'Atlas', 'Atlas.toc')) && fs.existsSync(path.join(c, 'Data')));
  assert.deepEqual(rm2.installed, {});
});

test('install errors: no client, nothing selected, unknown names', () => {
  const root = fakeRoot(); fakeAddons(root);
  assert.throws(() => client.installAddons(root, '', ['wotlk_shop'], {}), /no client folder/);
  const c = fakeClient();
  assert.throws(() => client.installAddons(root, c, [], {}), /nothing selected/);
  assert.throws(() => client.installAddons(root, c, ['Atlas', '../x'], {}), /nothing selected/);
});

test('creates Interface/AddOns when the client has none yet', () => {
  const root = fakeRoot(); fakeAddons(root);
  const c = tmp('wow2'); write(path.join(c, 'Wow.exe'), 'x'); fs.mkdirSync(path.join(c, 'Data'));
  const r = client.installAddons(root, c, ['wotlk_pets'], {});
  assert.deepEqual(r.done.sort(), ['AcoreLib', 'wotlk_pets']);
  assert.ok(fs.existsSync(path.join(c, 'Interface', 'AddOns', 'wotlk_pets', 'file.lua')));
});

test('client realmlist.wtf: read, set, original kept once', () => {
  const c = fakeClient();
  const r0 = client.readRealmlist(c); assert.equal(r0.length, 1); assert.equal(r0[0].address, 'old.example.com');
  client.setRealmlist(c, '192.168.1.20');
  assert.equal(client.readRealmlist(c)[0].address, '192.168.1.20');
  client.setRealmlist(c, '10.0.0.2');
  const f = r0[0].file;
  assert.equal(fs.readFileSync(f + '.bak-launcher', 'utf8'), 'set realmlist old.example.com\n');   // first original, not overwritten
  assert.throws(() => client.setRealmlist(c, 'bad address'), /invalid/);
  assert.throws(() => client.setRealmlist(c, '1.2.3.4;x'), /invalid/);
});
