'use strict';

// Real Chromium + real IndexedDB, using WEB_CONFIRM extracted without edits.
// Usage: node web-confirm-real-idb.cjs CampSaveStore.gd output-dir [chromium-path]
// Resolve Playwright through NODE_PATH or PLAYWRIGHT_MODULE. A fresh local HTTP
// origin and browser context isolate this test from every game/user save.
// All slow cases run together against the unchanged 18-second production
// deadline. The one late-completion fault stalls a native complete event for
// at most about 0.8 s; performance.now/setTimeout/bridge code are never replaced.

const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const playwrightName = process.env.PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = require(playwrightName);
const [sourceArg, outArg, executablePath] = process.argv.slice(2);
assert(sourceArg && outArg, 'usage: node web-confirm-real-idb.cjs CampSaveStore.gd output-dir [chromium-path]');
const sourcePath = path.resolve(sourceArg), out = path.resolve(outArg);
const source = fs.readFileSync(sourcePath, 'utf8');
const match = /const WEB_CONFIRM = """([\s\S]*?)"""/.exec(source);
assert(match, 'production WEB_CONFIRM exists');
const bridge = match[1];
fs.mkdirSync(out, { recursive: true });

(async () => {
  const consoleLog = [], pageErrors = [], responses = [];
  const server = http.createServer((_request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end('<!doctype html><meta charset="utf-8"><title>Don’t Stop isolated persistence contract</title>');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  let browser, watchdog;
  const report = {
    sourcePath,
    sourceSha256: crypto.createHash('sha256').update(source).digest('hex'),
    bridgeSha256: crypto.createHash('sha256').update(bridge).digest('hex'),
    playwright: require(playwrightName + '/package.json').version,
    realIndexedDB: true,
    productionDeadlineMs: 18000,
    pageErrors, responses,
  };
  const started = performance.now();
  try {
    browser = await chromium.launch({
      headless: true,
      ...(executablePath ? { executablePath } : {}),
      args: ['--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows'],
    });
    report.browser = browser.version();
    const context = await browser.newContext();
    const page = await context.newPage();
    page.on('console', message => {
      consoleLog.push(message.type() + ' ' + message.text());
      if (message.type() === 'error') pageErrors.push(message.text());
    });
    page.on('pageerror', error => pageErrors.push(String(error)));
    page.on('response', response => { if (response.status() >= 400) responses.push({ status: response.status(), url: response.url() }); });
    await page.goto('http://127.0.0.1:' + server.address().port + '/', { waitUntil: 'domcontentloaded', timeout: 5000 });
    const evaluation = page.evaluate(async bridgeCode => {
      const encoder = new TextEncoder();
      const text = '{"schema_version":6,"gold":100}';
      const otherText = '{"schema_version":6,"gold":101}';
      const bytes = encoder.encode(text), otherBytes = encoder.encode(otherText);
      const padded = Uint8Array.from([0xff, 0xee, 0xdd, ...bytes, 0xcc]);
      const contentsBytes = contents => contents instanceof ArrayBuffer ? new Uint8Array(contents)
        : ArrayBuffer.isView(contents) ? new Uint8Array(contents.buffer, contents.byteOffset, contents.byteLength) : null;
      const sameBytes = (left, right) => !!left && left.length === right.length && left.every((value, index) => value === right[index]);
      const hex = contents => {
        const value = contentsBytes(contents);
        return value ? Array.from(value, byte => byte.toString(16).padStart(2, '0')).join('') : null;
      };
      const openDatabase = () => new Promise((resolve, reject) => {
        const request = indexedDB.open('/userfs', 1);
        request.onupgradeneeded = () => request.result.createObjectStore('FILE_DATA');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
        request.onblocked = () => reject(new Error('unexpected blocked isolated database'));
      });
      const setupDatabase = await openDatabase();
      const put = (key, contents, abort = false) => new Promise((resolve, reject) => {
        const transaction = setupDatabase.transaction('FILE_DATA', 'readwrite');
        transaction.objectStore('FILE_DATA').put({ timestamp: new Date(), contents }, key);
        transaction.oncomplete = () => abort ? reject(new Error('injected aborted write unexpectedly committed')) : resolve({ committed: true });
        transaction.onabort = () => abort ? resolve({ aborted: true }) : reject(transaction.error || new Error('unexpected write abort'));
        transaction.onerror = () => { /* onabort records the terminal expected/error result */ };
        if (abort) transaction.abort();
      });
      const specs = [
        { name: 'exact Uint8Array', text, contents: bytes, success: true },
        { name: 'exact ArrayBuffer', text, contents: bytes.buffer, success: true },
        { name: 'exact offset DataView', text, contents: new DataView(padded.buffer, 3, bytes.length), success: true },
        { name: 'BOM is not exact bytes', text, contents: Uint8Array.from([0xef, 0xbb, 0xbf, ...bytes]), success: false, deadline: true },
        { name: 'invalid UTF-8 is not replacement character bytes', text: '{"label":"\ufffd"}',
          contents: Uint8Array.from([...encoder.encode('{"label":"'), 0xff, ...encoder.encode('"}')]), success: false, deadline: true },
        { name: 'different durable snapshot', text, contents: otherBytes, success: false, deadline: true },
        { name: 'missing durable row', text, missing: true, success: false, deadline: true },
        { name: 'malformed string contents', text, contents: text, success: false, deadline: true },
        { name: 'real read transaction abort after exact read', text, contents: bytes, success: false, abortRead: true },
        { name: 'real aborted upstream write leaves predecessor', text, contents: otherBytes, success: false, abortWrite: true, deadline: true },
        { name: 'exact row completed after hard deadline', text, contents: otherBytes, success: false, deadline: true, lateComplete: true },
      ];
      for (let index = 0; index < specs.length; index++) {
        const spec = specs[index];
        spec.path = '/userfs/audit/' + index + '.json';
        spec.revision = 100 + index;
        spec.expectedBytes = encoder.encode(spec.text);
        if (!spec.missing) await put(spec.path, spec.contents);
        if (spec.abortWrite) spec.upstreamWriteResult = await put(spec.path, spec.expectedBytes, true);
      }

      // The native method still creates every request. Instrumentation only
      // observes native events or injects an explicit native abort/event stall.
      const nativeGet = IDBObjectStore.prototype.get;
      const states = new Map();
      IDBObjectStore.prototype.get = function (key) {
        const request = Reflect.apply(nativeGet, this, [key]);
        const state = states.get(key);
        if (!state || this.name !== 'FILE_DATA') return request;
        const transaction = this.transaction;
        state.nativeTransactions = state.nativeTransactions && transaction instanceof IDBTransaction;
        state.reads += 1;
        request.addEventListener('success', () => {
          state.readSuccesses += 1;
          state.lastReadHex = hex(request.result?.contents);
        }, { once: true });
        // This listener is registered before production assigns tx.oncomplete.
        // Thus a bounded real main-thread stall can postpone that production
        // handler beyond 18 s without changing its clock or its timers.
        transaction.addEventListener('complete', () => {
          state.completes += 1;
          if (state.spec.lateComplete && !state.stall && sameBytes(contentsBytes(request.result?.contents), state.spec.expectedBytes)) {
            const entered = performance.now();
            const until = state.started + 18100;
            if (entered < state.started + 18000) {
              while (performance.now() < until) { /* injected event-loop starvation */ }
              state.stall = { enteredMs: entered - state.started, releasedMs: performance.now() - state.started };
            } else state.stall = { enteredMs: entered - state.started, arrivedAfterDeadline: true };
          }
        }, { once: true });
        transaction.addEventListener('abort', () => { state.aborts += 1; }, { once: true });
        if (state.spec.abortRead) {
          // The bridge installs read.onsuccess synchronously after get returns.
          // Register this listener one microtask later so production observes
          // exact bytes first; the native transaction is then really aborted.
          queueMicrotask(() => request.addEventListener('success', () => {
            state.abortInjected = true;
            transaction.abort();
          }, { once: true }));
        }
        return request;
      };
      (0, eval)(bridgeCode);
      window.towdownSave.diagnosticsEnabled = true;
      const fixtureErrors = [], lateWrites = [];
      try {
        const completion = specs.map(spec => new Promise(resolve => {
          const state = { spec, started: performance.now(), callbacks: [], reads: 0, readSuccesses: 0,
            completes: 0, aborts: 0, nativeTransactions: true, abortInjected: false, stall: null };
          states.set(spec.path, state);
          window.towdownSave.verify(spec.path, spec.text, spec.revision, (revision, success, reason) => {
            state.callbacks.push({ revision, success, reason, elapsedMs: performance.now() - state.started,
              nativeCompletesAtCallback: state.completes, nativeAbortsAtCallback: state.aborts });
            resolve(state);
          });
          if (spec.lateComplete) lateWrites.push(new Promise(writeDone => setTimeout(() => {
            put(spec.path, spec.expectedBytes).then(result => { state.lateWriteResult = result; writeDone(); })
              .catch(error => { fixtureErrors.push('late real write: ' + String(error)); writeDone(); });
          }, 17400)));
        }));
        await Promise.all(completion);
        await Promise.all(lateWrites);
        // Pending scheduled polls and duplicate callbacks remain observable.
        await new Promise(resolve => setTimeout(resolve, 200));
      } finally {
        IDBObjectStore.prototype.get = nativeGet;
      }
      const readFinal = key => new Promise((resolve, reject) => {
        const transaction = setupDatabase.transaction('FILE_DATA', 'readonly');
        const request = transaction.objectStore('FILE_DATA').get(key);
        transaction.oncomplete = () => resolve(request.result);
        transaction.onabort = () => reject(transaction.error || new Error('unexpected final read abort'));
      });
      const results = [];
      for (const spec of specs) {
        const state = states.get(spec.path);
        const callback = state.callbacks[0];
        const durableRow = await readFinal(spec.path);
        const events = window.towdownSave.diagnostics.filter(event => event.revision === spec.revision &&
          ['verify-callback', 'verify-timeout', 'transaction-abort', 'verify-match'].includes(event.event));
        const problems = [];
        if (!state.nativeTransactions) problems.push('transaction was not native IndexedDB');
        if (state.reads < 1 || state.readSuccesses < 1) problems.push('no real successful IndexedDB row request was observed');
        if (state.callbacks.length !== 1) problems.push('terminal callback count differs from one');
        if (callback.revision !== spec.revision) problems.push('callback revision differs');
        if (callback.success !== spec.success) problems.push('success differs from byte/transaction contract');
        if (callback.success && callback.nativeCompletesAtCallback < 1) problems.push('success preceded native read transaction completion');
        if (spec.deadline && (callback.elapsedMs < 18000 || !callback.reason.includes('未确认'))) problems.push('nonmatching/late snapshot did not obey 18-second failure deadline');
        if (spec.abortRead && (!state.abortInjected || state.aborts !== 1 || !callback.reason.includes('读取失败'))) problems.push('native read abort was not propagated');
        if (spec.abortWrite && (!spec.upstreamWriteResult?.aborted || hex(durableRow?.contents) !== hex(otherBytes))) problems.push('aborted upstream transaction changed durable predecessor');
        if (spec.lateComplete && (!state.lateWriteResult?.committed || !state.stall ||
          !events.some(event => event.event === 'verify-timeout' && event.observed_after_deadline === true))) problems.push('exact native transaction did not exercise late-completion guard');
        results.push({ name: spec.name, revision: spec.revision, expectedSuccess: spec.success,
          expectedHex: hex(spec.expectedBytes), durableHex: hex(durableRow?.contents),
          callbacks: state.callbacks, reads: state.reads, readSuccesses: state.readSuccesses,
          nativeCompletes: state.completes, nativeAborts: state.aborts, stall: state.stall,
          upstreamWriteResult: spec.upstreamWriteResult || null, events,
          problems, success: problems.length === 0 });
      }
      setupDatabase.close();
      return { results, fixtureErrors, diagnosticsRetained: window.towdownSave.diagnostics.length,
        productionDirtyGuardPresent: window.towdownSave.dirty === true,
        success: fixtureErrors.length === 0 && results.every(result => result.success) };
    }, bridge);
    report.result = await Promise.race([
      evaluation,
      new Promise((_resolve, reject) => { watchdog = setTimeout(() => reject(new Error('real IndexedDB fixture exceeded 26-second harness watchdog')), 26000); }),
    ]);
    report.success = report.result.success && pageErrors.length === 0 && responses.length === 0;
  } catch (error) {
    report.error = String(error.stack || error);
    report.success = false;
  } finally {
    clearTimeout(watchdog);
    report.wallSeconds = (performance.now() - started) / 1000;
    fs.writeFileSync(path.join(out, 'result.json'), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(out, 'console.log'), consoleLog.join('\n') + '\n');
    if (browser) await browser.close();
    await new Promise(resolve => server.close(resolve));
  }
  console.log(JSON.stringify({ success: report.success, cases: report.result?.results.length || 0,
    failed: report.result?.results.filter(result => !result.success).map(result => ({ name: result.name, problems: result.problems })) || [],
    browser: report.browser, wallSeconds: report.wallSeconds, out, error: report.error || null }));
  process.exitCode = report.success ? 0 : 1;
})().catch(error => { console.error(error); process.exitCode = 2; });
