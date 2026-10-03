'use strict';
// Deterministic shell lifecycle/fault checks. This stubs only the engine boot;
// web-aim-e2e and web-first-shot separately exercise the real exported game.
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path');
const [url, out = 'output/loader-check'] = process.argv.slice(2);
if (!url) throw new Error('usage: node web-loader-check.js <export URL> [evidence directory]');
fs.mkdirSync(out, {recursive: true});
const engine = `window.Engine = class {
 startGame(options) { window.bootOptions = options; return new Promise((resolve, reject) => { window.bootResolve = resolve; window.bootReject = reject; }); }
};`;
(async () => {
 const browser = await chromium.launch({headless: true});
 const results = [], errors = [];
 try {
  for (const [name, viewport, reducedMotion] of [
   ['desktop', {width:1280,height:720}, 'no-preference'],
   ['4k', {width:3840,height:2160}, 'no-preference'],
   ['portrait', {width:390,height:844}, 'reduce']
  ]) {
   const context = await browser.newContext({viewport, reducedMotion, serviceWorkers:'block'});
   const page = await context.newPage();
   page.on('pageerror', e => errors.push(String(e)));
   await page.clock.install();
   await page.route('**/index.js', route => route.fulfill({contentType:'application/javascript',body:engine}));
   await page.goto(url);
   await page.waitForFunction(() => window.bootOptions);
   await page.clock.runFor(1100);
   assert(await page.locator('#frame').isVisible(), 'cover visible during startup');
   assert(await page.locator('#world').evaluate(el => el.complete && el.naturalWidth > 0), 'shared artwork decodes');
   const embedded = (await page.locator('#world').getAttribute('src')).split(',')[1];
   assert.deepEqual(Buffer.from(embedded,'base64'),fs.readFileSync(path.join(__dirname,'../boot/loading-world.webp')), 'Web and Windows share the same source artwork');
   await page.evaluate(() => window.bootOptions.onProgress(50,100));
   assert.equal(await page.locator('#phase-current').textContent(), '01');
   await page.screenshot({path:path.join(out, name+'-loading.png')});
   for (const selector of ['#brand','#departure','#status','#stages','#field-note']) {
    const box = await page.locator(selector).boundingBox();
    assert(box && box.x >= 0 && box.y >= 0 && box.x+box.width <= viewport.width+1 && box.y+box.height <= viewport.height+1, name+' fits '+selector);
   }
   if (reducedMotion === 'reduce') {
    assert.equal(await page.locator('#world').evaluate(el => getComputedStyle(el).animationName), 'none');
    assert.equal(await page.locator('.motes').evaluate(el => getComputedStyle(el).display), 'none');
   }
   await page.evaluate(() => window.bootOptions.onProgress(100,100));
   assert.equal(await page.locator('#phase-current').textContent(), '02');
   await page.evaluate(() => window.bootResolve());
   await page.waitForFunction(() => window.__dontStopState.completedStageFraction === 2/3);
   assert(await page.locator('#frame').isVisible(), 'engine completion alone cannot reveal the game');
   assert.equal(await page.locator('#phase-current').textContent(), '03');
   await page.clock.fastForward(45001);
   assert.equal(await page.evaluate(() => window.__dontStopState.outcome), 'stalled');
   assert(await page.locator('#retry').isVisible(), 'stalled startup offers retry');
   await page.screenshot({path:path.join(out,name+'-stalled.png')});
   await Promise.all([page.waitForEvent('framenavigated'), page.locator('#retry').click()]);
   await page.waitForFunction(() => window.bootOptions && window.__dontStopState.outcome === 'pending');
   await page.evaluate(() => window.__dontStop.failed('资源传输中断，请重新连接。'));
   assert(await page.locator('#frame').isVisible(), 'failure keeps the cover');
   assert.equal(await page.locator('#bar').getAttribute('aria-valuetext'), '加载失败');
   await page.locator('#retry').focus();
   await page.screenshot({path:path.join(out,name+'-error.png')});
   await Promise.all([page.waitForEvent('framenavigated'), page.keyboard.press('Enter')]);
   await page.waitForFunction(() => window.bootOptions && window.__dontStopState.outcome === 'pending');
   await page.evaluate(() => window.__dontStop.ready());
   await page.clock.runFor(350);
   assert(!(await page.locator('#frame').isVisible()), 'real ready notice retires cover');
   assert.equal(await page.evaluate(() => window.__dontStopState.revealedBy), 'game-reported-ready');
   results.push({name,viewport,reducedMotion,pass:true});
   await context.close();
  }
  assert.deepEqual(errors, []);
  console.log('PASS loading shell: stages, bounds, reduced motion, stall retry, failure retry, ready handover');
 } finally {
  fs.writeFileSync(path.join(out,'result.json'),JSON.stringify({results,errors},null,2));
  await browser.close();
 }
})().catch(error => { console.error(error); process.exitCode = 1; });
