'use strict';
// Test hook (only active with ACORE_LAUNCHER_SHOTS=<dir>): renders every tab off-screen and saves PNGs, then quits. Never used in normal runs.
const fs = require('fs');
const path = require('path');
const settings = require('../lib/settings');

module.exports = function shots(win, app, dir) {
  fs.mkdirSync(dir, { recursive: true });
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  const js = (code) => win.webContents.executeJavaScript(code);
  win.webContents.once('did-finish-load', async () => {
    try {
      await wait(3500);
      const tabs = await js("[...document.querySelectorAll('#nav button')].map((b) => b.textContent)");
      for (let i = 0; i < tabs.length; i++) {
        await js(`document.querySelectorAll('#nav button')[${i}].click()`);
        await wait(3500);
        const img = await win.webContents.capturePage();
        const name = `${String(i + 1).padStart(2, '0')}-${tabs[i].replace(/[^A-Za-z]+/g, '').toLowerCase()}.png`;
        fs.writeFileSync(path.join(dir, name), img.toPNG());
        const errs = await js("[...document.querySelectorAll('.note.bad')].map((n) => n.textContent)");
        console.log('shot', name, errs.length ? 'ERRORS: ' + errs.join(' | ') : 'ok');
      }
      // client addons end to end (needs ACORE_LAUNCHER_SHOT_CLIENT = a fake WoW folder): choose it, install everything, then remove everything
      const fakeClient = process.env.ACORE_LAUNCHER_SHOT_CLIENT;
      if (fakeClient) {
        const addons = path.join(fakeClient, 'Interface', 'AddOns');
        const ls = () => fs.readdirSync(addons).sort().join(',');
        settings.update({ clientPath: fakeClient, installed: {} });
        await js("document.querySelectorAll('#nav button')[8].click()"); await wait(2500);
        fs.writeFileSync(path.join(dir, '11-client-before.png'), (await win.webContents.capturePage()).toPNG());
        console.log('addons before:', ls());
        await js("[...document.querySelectorAll('button')].find((b) => b.textContent.startsWith('Install / update all')).click()"); await wait(4000);
        fs.writeFileSync(path.join(dir, '12-client-installed.png'), (await win.webContents.capturePage()).toPNG());
        console.log('addons after install:', ls());
        await js("[...document.querySelectorAll('button')].find((b) => b.textContent === 'Remove all ours').click()"); await wait(600);
        await js("[...document.querySelectorAll('#modal button')].find((b) => b.textContent === 'Remove all').click()"); await wait(3000);
        console.log('addons after remove:', ls());
        settings.update({ clientPath: '', installed: {} });
      }
      // long operations against a FAKE server root (ACORE_LAUNCHER_SHOT_OP=1): progress streaming, success and failure display
      if (process.env.ACORE_LAUNCHER_SHOT_OP) {
        await js("document.querySelectorAll('#nav button')[0].click()"); await wait(1500);
        await js("[...document.querySelectorAll('button')].find((b) => b.textContent === 'Start servers').click()"); await wait(1800);
        fs.writeFileSync(path.join(dir, '13-op-running.png'), (await win.webContents.capturePage()).toPNG());
        console.log('op running; start button disabled while busy:', await js("[...document.querySelectorAll('button')].find((b) => b.textContent === 'Start servers').disabled"));
        await wait(3000);
        fs.writeFileSync(path.join(dir, '14-op-done.png'), (await win.webContents.capturePage()).toPNG());
        console.log('op state after:', await js("document.querySelector('#opState').textContent"));
        await js("[...document.querySelectorAll('button')].find((b) => b.textContent === 'Start MySQL only').click()"); await wait(2000);
        fs.writeFileSync(path.join(dir, '15-op-failed.png'), (await win.webContents.capturePage()).toPNG());
        console.log('op state after failure:', await js("document.querySelector('#opState').textContent"));
      }
      // dialogs: open the new-account form on the Accounts tab
      await js("document.querySelectorAll('#nav button')[3].click()"); await wait(2500);
      await js("[...document.querySelectorAll('button')].find((b) => b.textContent.startsWith('New account')).click()"); await wait(600);
      fs.writeFileSync(path.join(dir, '10-dialog.png'), (await win.webContents.capturePage()).toPNG());
      console.log('shot 10-dialog.png ok');
    } catch (e) { console.log('SHOT FAILED', e); }
    app.exit(0);
  });
};
