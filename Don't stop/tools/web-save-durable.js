'use strict';
// Actual canvas controls + transaction fault injection + refresh recovery.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const [url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
(async () => {
 const browser = await chromium.launch({ headless: false, executablePath: process.env.CHROME_EXE,
  args: ['--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows'] });
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
 let carry, canvas;
 function observe() { page.on('console', m => {
  const t = m.text(); lines.push(t);
  if (t.startsWith('[loadout] ')) carry = JSON.parse(t.slice(10));
  const r = t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+) on_screen=(true|false)/);
  if (r) rects[r[1]] = { x: +r[8], y: +r[9], visible: r[10] === 'true', text: r[3] };
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
  await until(() => rects['menu-start-button']?.visible, 'menu');
  canvas = await page.locator('canvas').boundingBox();
  await click('menu-start-button');
  await until(() => carry, 'camp');
 }
 async function reload() {
  for (const key of Object.keys(rects)) delete rects[key]; carry = null;
  await page.reload(); await start();
 }
 async function select(id) {
  await click('camp-search-box'); await page.keyboard.press('Control+A'); await page.keyboard.type(String(id));
  await page.waitForTimeout(400); await click('camp-entry-' + id);
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
  await until(() => carry?.saved === true, 'initial durable save');
  const initial = await disk(); check(initial && initial.weapons.length === 0, 'initial snapshot is committed in IndexedDB');
  for (const [fault, id] of [['abort', 1], ['quota', 6]]) {
   await select(id); await page.evaluate(f => window.saveFault = f, fault);
   await click('camp-action-0');
   await until(() => carry?.owned.includes(id) && carry.saved === false, 'unsaved purchase');
   const paid = carry.gold;
   await page.waitForTimeout(8500);
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
  await page.waitForTimeout(8500); await click('camp-settings-button'); await click('leave-entry');
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
  for (const key of Object.keys(rects)) delete rects[key]; carry = null;
  await page.reload(); await until(() => rects['menu-start-button']?.visible, 'menu');
  canvas = await page.locator('canvas').boundingBox(); await click('menu-start-button');
  await until(() => rects['save-export-original']?.visible, 'recovery dialog');
  const download = page.waitForEvent('download'); await click('save-export-original');
  const file = await download; const filename = path.join(out, file.suggestedFilename()); await file.saveAs(filename);
  check(fs.readFileSync(filename).equals(Buffer.from(bytes)), 'corrupt original download preserves every byte including invalid UTF-8');
  await page.screenshot({ path: path.join(out, 'original-downloaded.png') });
  await page.evaluate(() => window.saveFault = 'abort');
  const takeoverDownload = page.waitForEvent('download'); await click('save-create-new'); await takeoverDownload;
  await page.waitForTimeout(8500);
  const afterFailure = page.waitForEvent('download'); await click('save-export-original');
  const restoredOriginal = await afterFailure, restoredPath = path.join(out, 'failed-takeover-original.json'); await restoredOriginal.saveAs(restoredPath);
  check(fs.readFileSync(restoredPath).equals(Buffer.from(bytes)), 'failed new-save takeover retains the corrupt original byte for byte');
  await page.evaluate(() => window.saveFault = '');
  const retryDownload = page.waitForEvent('download'); await click('save-create-new'); await retryDownload;
  await until(() => carry?.saved === true && carry.owned.length === 0, 'confirmed new-save takeover');
  await reload(); check(carry.owned.length === 0 && carry.saved, 'new-save takeover becomes usable only after durable confirmation and survives refresh');
  await context.close();
  const blocked = await browser.newContext({ viewport: { width: 1280, height: 720 }, serviceWorkers: 'block' });
  await blocked.addInitScript(() => { IDBFactory.prototype.open = () => { throw new DOMException('Injected storage disabled', 'SecurityError'); }; });
  for (const key of Object.keys(rects)) delete rects[key]; carry = null;
  page = await blocked.newPage(); observe();
  await page.goto(url + '?probe=1'); await start();
  await until(() => carry?.saved === false && /不可用/.test(carry.message), 'disabled storage warning');
  check(await page.evaluate(() => window.towdownSave.dirty), 'disabled storage keeps an unsaved-session unload guard');
  await click('camp-settings-button'); await click('leave-entry');
  await until(() => rects['save-export-progress']?.visible, 'unsaved quit dialog');
  const backup = page.waitForEvent('download'); await click('save-export-progress');
  const progress = await backup, progressPath = path.join(out, 'disabled-storage-progress.json'); await progress.saveAs(progressPath);
  check(JSON.parse(fs.readFileSync(progressPath, 'utf8')).schema_version === 6, 'disabled storage still allows a real current-progress backup download');
  check(await page.evaluate(() => window.towdownSave.dirty), 'export does not falsely claim browser persistence');
  await page.screenshot({ path: path.join(out, 'disabled-storage.png') });
  const unexpected = lines.filter(t => t.includes('SCRIPT ERROR:') || t.startsWith('PAGEERROR '));
  check(!unexpected.length, 'no engine script errors or uncaught browser errors');
  report.success = true;
 } catch (e) { report.error = String(e); process.exitCode = 1; await page.screenshot({ path: path.join(out, 'failure.png') }).catch(() => {}); }
 finally { fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(report, null, 2)); fs.writeFileSync(path.join(out, 'console.log'), lines.join('\n')); await browser.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
