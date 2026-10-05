'use strict';
// Actual canvas controls + transaction fault injection + refresh recovery.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const [url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
(async () => {
 const browser = await chromium.launch({ headless: process.env.E2E_HEADED !== '1', executablePath: process.env.CHROME_EXE,
  args: ['--enable-unsafe-swiftshader', '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows'] });
 const context = await browser.newContext({ viewport: { width: 1280, height: 720 }, serviceWorkers: 'block' });
 await context.addInitScript(() => {
  const put = IDBObjectStore.prototype.put;
  IDBObjectStore.prototype.put = function (...args) {
   if (window.saveFault === 'quota') throw new DOMException('Injected full storage', 'QuotaExceededError');
   const request = put.apply(this, args);
   if (window.saveFault === 'abort') this.transaction.abort();
   return request;
  };
 });
 const lines = [], rects = {}, report = { checks: [] };
 let page = await context.newPage();
 let carry, canvas, camp, recovery;
 function observe() { page.on('console', m => {
  const t = m.text(); lines.push(t);
  if (t.startsWith('[loadout] ')) carry = JSON.parse(t.slice(10));
  if (t.startsWith('[camp] ')) camp = JSON.parse(t.slice(7));
  if (t.startsWith('[save-recovery] ')) recovery = JSON.parse(t.slice(16));
  const r = t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)/);
  if (r) rects[r[1]] = { id: r[2], x: +r[8], y: +r[9], visible: r[10] === 'true', text: r[3] };
 });
 page.on('pageerror', e => lines.push('PAGEERROR ' + e.message)); }
 observe();
 async function until(fn, label, ms = 60000) {
  const end = Date.now() + ms;
  while (!fn()) { if (Date.now() > end) throw Error('timeout: ' + label); await page.waitForTimeout(100); }
 }
 async function click(tag) {
  await until(() => rects[tag]?.visible, tag);
  const r = rects[tag], scale = Math.min(canvas.width / 410, canvas.height / 230);
  await page.mouse.click(canvas.x + (canvas.width - 410 * scale) / 2 + r.x * scale,
   canvas.y + (canvas.height - 230 * scale) / 2 + r.y * scale);
  await page.waitForTimeout(500);
 }
 function check(ok, title) { assert(ok, title); report.checks.push(title); console.log('PASS ' + title); }
 async function start() {
  await page.waitForFunction(() => window.__dontStopState?.outcome === 'game-reported-ready'
   && document.getElementById('frame')?.style.display === 'none');
  await until(() => rects['menu-start-button']?.visible, 'menu');
  canvas = await page.locator('canvas').boundingBox();
  await click('menu-start-button');
  await until(() => carry, 'camp');
 }
 async function reload(beforeStart) {
  for (const key of Object.keys(rects)) delete rects[key]; carry = null; camp = null; recovery = null;
  await page.reload(); if (beforeStart) await beforeStart(); await start(); await settleStartupSave();
 }
 async function settleStartupSave() {
  // The nominal purchase test starts after startup's own save has settled.
  // Otherwise a slow renderer makes two different transactions overlap and
  // tests a startup-sync race instead of post-recovery purchasing.
  await until(() => carry?.saved || /不可用|未确认|失败/.test(carry?.message || ''), 'startup save result');
  if (!carry.saved) {
   const gold = carry.gold, owned = [...carry.owned], slots = [...carry.slots];
   (report.startupConfirmationFailures ||= []).push({ message: carry.message, disk: await disk(), carry });
   check(await page.evaluate(() => window.towdownSave.dirty), 'startup confirmation failure retains the unload guard');
   await click('camp-save-retry');
   await until(() => carry?.saved, 'startup save retry');
   check(carry.gold === gold && JSON.stringify(carry.owned) === JSON.stringify(owned) && JSON.stringify(carry.slots) === JSON.stringify(slots),
    'startup save retry confirms without charging or changing restored state');
  }
 }
 async function select(id) {
  const tag = 'camp-entry-' + id, previous = rects[tag]?.id;
  await click('camp-search-box'); await page.keyboard.press('Control+A'); await page.keyboard.type(String(id));
  // render() replaces list controls after text_changed. A retained rectangle
  // from the old list can be visible but point to a different row after filtering.
  await until(() => camp?.order[0] === String(id) && rects[tag]?.visible && rects[tag].id !== previous
   && rects[tag].y > rects['camp-search-box'].y, 'filtered control layout ' + id);
  await click(tag);
 }
 async function disk() {
  return page.evaluate(async () => {
   const db = await new Promise((resolve, reject) => { const q = indexedDB.open('/userfs'); q.onsuccess = () => resolve(q.result); q.onerror = () => reject(q.error); });
   try {
    const row = await new Promise((resolve, reject) => {
     const tx = db.transaction('FILE_DATA'); const q = tx.objectStore('FILE_DATA').get('/userfs/TowDownGame/camp-v1.json');
     let result; q.onsuccess = () => result = q.result; tx.oncomplete = () => resolve(result); tx.onabort = () => reject(tx.error);
    });
    return row ? JSON.parse(new TextDecoder().decode(row.contents)) : null;
   } finally { db.close(); }
  });
 }
 try {
  await page.goto(url + '?probe=1'); await start();
  await settleStartupSave();
  const initial = await disk(); check(initial && initial.weapons.length === 0, 'initial snapshot is committed in IndexedDB');
  for (const [fault, id] of [['abort', 1], ['quota', 6]]) {
   await select(id); await page.evaluate(f => window.saveFault = f, fault);
   await click('camp-action-0');
   await until(() => carry?.owned.includes(id) && carry.saved === false, 'unsaved purchase');
   const paid = carry.gold;
   // Timer delivery and Godot's visible callback need not have completed at a
   // fixed wall-clock sleep on a software-rendered runner. Observe the actual
   // terminal failure before checking it; keep all failure/disk assertions.
   await until(() => !carry.saved && /未确认|不可用|失败/.test(carry.message), fault + ' confirmation failure');
   check(carry.saved === false && /未确认|不可用|失败/.test(carry.message), fault + ': failure is visible and memory stays dirty');
   check(!(await disk()).weapons.some(w => +w.id === id), fault + ': old durable snapshot survives failed transaction');
   await page.screenshot({ path: path.join(out, fault + '-failed.png') });
   await page.evaluate(() => window.saveFault = '');
   await click('camp-save-retry'); await until(() => carry?.saved === true, 'durable retry');
   check(carry.gold === paid, fault + ': retry never charges purchase again');
   check((await disk()).weapons.some(w => +w.id === id), fault + ': retry is actually committed');
   await reload();
   check(carry.owned.includes(id) && carry.slots.includes(id), fault + ': refresh restores ownership and loadout');
  }
  await select(2); await page.evaluate(() => window.saveFault = 'abort'); await click('camp-action-0');
  await until(() => carry?.owned.includes(2) && !carry.saved, 'discard test purchase');
  await until(() => !carry.saved && /未确认|不可用|失败/.test(carry.message), 'discard purchase confirmation failure');
  await click('camp-settings-button'); await click('leave-entry');
  delete rects['menu-start-button']; carry = null;
  await click('save-discard');
  await start();
  check(!carry.owned.includes(2) && carry.owned.includes(1) && carry.owned.includes(6), 'explicit discard returns to the committed loadout instead of pending MEMFS bytes');
  await page.evaluate(() => window.saveFault = '');
  await until(() => carry?.saved === true, 'post-discard durable save');
  const bytes = [123, 34, 120, 34, 58, 255, 0, 10];
  await page.evaluate(async data => {
   const db = await new Promise(r => { const q = indexedDB.open('/userfs'); q.onsuccess = () => r(q.result); });
   await new Promise((resolve, reject) => {
    const tx = db.transaction('FILE_DATA', 'readwrite'), store = tx.objectStore('FILE_DATA');
    const q = store.get('/userfs/TowDownGame/camp-v1.json');
    q.onsuccess = () => { const row = q.result; row.contents = new Uint8Array(data); row.timestamp = new Date(); store.put(row, '/userfs/TowDownGame/camp-v1.json'); };
    tx.oncomplete = resolve; tx.onabort = () => reject(tx.error);
   }); db.close();
  }, bytes);
  for (const key of Object.keys(rects)) delete rects[key]; carry = null; camp = null; recovery = null;
  // Probe rectangles can exist behind the loader. Corrupt recovery uses the
  // same real input-ready barrier as a healthy start, without awaiting a save.
  await page.reload(); await start();
  await until(() => rects['save-export-original']?.visible, 'recovery dialog');
  const download = page.waitForEvent('download'); await click('save-export-original');
  const file = await download; const filename = path.join(out, file.suggestedFilename()); await file.saveAs(filename);
  check(fs.readFileSync(filename).equals(Buffer.from(bytes)), 'corrupt original download preserves every byte including invalid UTF-8');
  await page.screenshot({ path: path.join(out, 'original-downloaded.png') });
  await page.evaluate(() => window.saveFault = 'abort');
  const takeoverDownload = page.waitForEvent('download'); await click('save-create-new'); await takeoverDownload;
  await until(() => recovery?.pending === false && recovery.dialog && /未确认|不可用|失败/.test(carry?.message || ''), 'failed takeover confirmation');
  const afterFailure = page.waitForEvent('download'); await click('save-export-original');
  const restoredOriginal = await afterFailure, restoredPath = path.join(out, 'failed-takeover-original.json'); await restoredOriginal.saveAs(restoredPath);
  check(fs.readFileSync(restoredPath).equals(Buffer.from(bytes)), 'failed new-save takeover retains the corrupt original byte for byte');
  await until(() => recovery?.pending === false && recovery.dialog, 'failed recovery unlocks its dialog');
  await click('save-temporary'); await until(() => recovery?.dialog === false, 'failed recovery can be dismissed');
  await click('camp-talent-tab'); await select('T01');
  await until(() => camp?.selection === 'T01' && camp.rank === 0, 'prepare real T01 purchase control');
  await click('camp-save-retry'); await until(() => recovery?.dialog, 'retry opens recovery again');
  await page.evaluate(() => window.saveFault = '');
  // Hold delivery of a real successful IndexedDB confirmation. We neither fake
  // persistence nor invoke a game mutation: only the callback delivery is delayed.
  await page.evaluate(() => {
   window.recoveryConfirmations = [];
   const verify = window.towdownSave.verify;
   window.towdownSave.verify = function (path, text, revision, callback) {
    return verify.call(this, path, text, revision, (...args) => {
     window.recoveryConfirmations.push({ args, release: () => callback(...args) });
    });
   };
  });
  const retryDownload = page.waitForEvent('download'); await click('save-create-new'); await retryDownload;
  await page.waitForFunction(() => window.recoveryConfirmations.length === 1);
  await until(() => recovery?.pending && recovery.dialog && recovery.leave_disabled, 'pending transaction locks recovery exit');
  const pendingRevision = recovery.revision, pendingGold = carry.gold;
  check(await page.evaluate(() => window.recoveryConfirmations[0].args[1] === true), 'pending takeover has a real durable confirmation awaiting delivery');
  await click('save-temporary'); await page.keyboard.press('Escape');
  await click('camp-action-0'); await page.keyboard.press('Enter');
  await page.waitForTimeout(1000);
  check(recovery.pending && recovery.dialog && recovery.leave_disabled && recovery.revision === pendingRevision,
   'DS-001 pending close and Escape cannot leave or replace recovery');
  check(camp.selection === 'T01' && camp.rank === 0 && carry.gold === pendingGold,
   'DS-001 pending real T01 purchase accepts no charge or rank change');
  check(await page.evaluate(() => window.towdownSave.dirty), 'DS-001 pending takeover retains the unload guard');
  await page.screenshot({ path: path.join(out, 'ds001-pending-blocked.png') });
  await page.evaluate(() => window.recoveryConfirmations.shift().release());
  await until(() => recovery?.pending === false && recovery.dialog === false, 'confirmation releases recovery');
  await until(() => carry?.saved === true && carry.owned.length === 0, 'confirmed new-save takeover');
  check(camp.rank === 0 && carry.gold === 9999, 'DS-001 completed takeover contains no overwritten accepted pending purchase');
  // Restore the original verifier for ordinary saving after this transaction.
  await reload(); await click('camp-talent-tab'); await select('T01');
  await until(() => camp?.selection === 'T01' && camp.rank === 0, 'confirmed fresh profile survives refresh');
  await click('camp-action-0'); await until(() => camp.rank === 1 && carry.saved, 'post-confirmation T01 purchase saves');
  const paidTalentGold = carry.gold, talentDisk = await disk();
  check(talentDisk.talents.T01 === 1 && talentDisk.gold === paidTalentGold,
   'DS-001 post-confirmation purchase is committed with its charge');
  let restoredTalentDisk;
  await reload(async () => { restoredTalentDisk = await disk(); }); await click('camp-talent-tab'); await select('T01');
  await until(() => camp?.selection === 'T01', 'reloaded confirmed purchase');
  // reload() already confirmed startup before these read-only UI operations.
  check(restoredTalentDisk.talents.T01 === 1 && restoredTalentDisk.gold === paidTalentGold
   && restoredTalentDisk.talent_payments.filter(p => p.id === 'T01').length === 1
   && camp.rank === 1 && carry.gold === Math.max(9999, paidTalentGold) && carry.owned.length === 0 && carry.saved,
   'DS-001 confirmed purchase survives a full reload without rollback or duplicate charge');
  await context.close();
  // No durable snapshot exists in these fresh contexts. The older discard test
  // above only covered rollback to an already committed file, so it could not
  // catch autoload talents leaking into the next session after explicit discard.
  for (const fault of ['unavailable', 'abort', 'quota']) {
   const blocked = await browser.newContext({ viewport: { width: 1280, height: 720 }, serviceWorkers: 'block' });
   await blocked.addInitScript(kind => {
    if (kind === 'unavailable') {
     IDBFactory.prototype.open = () => { throw new DOMException('Injected storage disabled', 'SecurityError'); };
    } else {
     const put = IDBObjectStore.prototype.put;
     IDBObjectStore.prototype.put = function (...args) {
      if (kind === 'quota') throw new DOMException('Injected full storage', 'QuotaExceededError');
      const request = put.apply(this, args); this.transaction.abort(); return request;
     };
    }
   }, fault);
   const lineStart = lines.length;
   for (const key of Object.keys(rects)) delete rects[key]; carry = null; camp = null;
   page = await blocked.newPage(); observe();
   await page.goto(url + '?probe=1');
   await page.waitForFunction(() => window.__dontStopState?.outcome === 'game-reported-ready');
   await start();
   await until(() => carry?.saved === false && /不可用|未确认|失败/.test(carry.message), 'first-save failure');
   check(await page.evaluate(() => window.towdownSave.dirty), fault + ': failed first save keeps the unload guard');
   await click('camp-talent-tab');
   for (const id of ['T01', 'T07']) {
    await select(id); await until(() => camp?.selection === id, 'talent selection');
    check(camp.rank === 0, fault + ': fresh ' + id + ' starts at rank zero');
    await click('camp-action-0'); await until(() => camp?.selection === id && camp.rank === 1, 'talent purchase');
   }
   await click('camp-settings-button'); await click('leave-entry');
   async function downloadProgress(name) {
    const pending = page.waitForEvent('download'); await click('save-export-progress');
    const progress = await pending, progressPath = path.join(out, fault + '-' + name + '.json');
    await progress.saveAs(progressPath); return JSON.parse(fs.readFileSync(progressPath, 'utf8'));
   }
   const beforeDiscard = await downloadProgress('before-discard');
   check(beforeDiscard.schema_version === 6 && beforeDiscard.talents.T01 === 1 && beforeDiscard.talents.T07 === 1,
    fault + ': real progress export contains both unsaved purchases');
   check(await page.evaluate(() => window.towdownSave.dirty), fault + ': export does not claim browser persistence');
   check(!lines.slice(lineStart).some(t => t.startsWith('[save-durable]') && t.includes('success=true')),
    fault + ': no snapshot was ever durably committed');
   await page.screenshot({ path: path.join(out, fault + '-first-save-discard.png') });
   delete rects['menu-start-button']; carry = null; camp = null;
   await click('save-discard'); await start(); await click('camp-talent-tab'); await select('T01');
   await until(() => camp?.selection === 'T01', 'restarted talent selection');
   await page.screenshot({ path: path.join(out, fault + '-after-discard.png') });
   check(camp.rank === 0, fault + ': same-page restart rolls back the discarded talent');
   await click('camp-settings-button'); await click('leave-entry');
   const afterDiscard = await downloadProgress('after-discard');
   check(Object.keys(afterDiscard.talents).length === 0 && afterDiscard.talent_payments.length === 0,
    fault + ': discard clears talent ranks and purchase receipts');
   check(afterDiscard.hp === 5 && afterDiscard.hp_max === 5 && afterDiscard.level === 1 && afterDiscard.exp === 0,
    fault + ': discard restores legal initial health and progression');
   check(afterDiscard.gold === 9999 && afterDiscard.points === 9999 && afterDiscard.reserve_magazines === 10
    && afterDiscard.weapons.length === 0 && afterDiscard.owned_global_upgrades.length === 0,
    fault + ': discard restores the initial wallet, supplies and ownership');
   check(afterDiscard.weapon_slots.every(id => id === -1) && afterDiscard.equipped === '' && !afterDiscard.unequipped
    && !afterDiscard.campaign_complete && !afterDiscard.hell_complete && afterDiscard.next_stage === 1
    && afterDiscard.selected_stage === 1 && afterDiscard.legacy.length === 0
    && Object.keys(afterDiscard.legacy_state).length === 0,
    fault + ': discard restores empty loadout, legacy ownership and stage progress');
   for (const key of Object.keys(rects)) delete rects[key]; carry = null; camp = null;
   await page.reload(); await page.waitForFunction(() => window.__dontStopState?.outcome === 'game-reported-ready');
   await start(); await click('camp-talent-tab'); await select('T01');
   await until(() => camp?.selection === 'T01', 'reloaded talent selection');
   check(camp.rank === 0, fault + ': full-page reload remains a fresh session');
   await blocked.close();
  }
  const unexpected = lines.filter(t => t.includes('SCRIPT ERROR:') || t.startsWith('PAGEERROR '));
  check(!unexpected.length, 'no engine script errors or uncaught browser errors');
  report.success = true;
 } catch (e) {
  report.error = String(e); process.exitCode = 1;
  report.failureState = { url: page.url(), carry, camp, recovery, disk: await disk().catch(err => ({ error: String(err) })) };
  console.error(report.error);
  await page.screenshot({ path: path.join(out, 'failure.png') }).catch(() => {});
 }
 finally { fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(report, null, 2)); fs.writeFileSync(path.join(out, 'console.log'), lines.join('\n')); await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
