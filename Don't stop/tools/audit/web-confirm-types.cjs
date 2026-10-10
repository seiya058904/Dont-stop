'use strict';

// Extracts production bridge unchanged. The fake IDB adapter models request
// callbacks and a transaction abort on an uncaught request-handler exception.
// This is a JS contract test, not a real IndexedDB/Godot browser acceptance.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const sourcePath = process.argv[2] || path.join(process.cwd(), "Don't stop/game/config/CampSaveStore.gd");
const source = fs.readFileSync(sourcePath, 'utf8');
const bridge = /const WEB_CONFIRM = """([\s\S]*?)"""/.exec(source)[1];
const text = '{"schema_version":6,"gold":100}';
const bytes = new TextEncoder().encode(text);

async function runCase(name, contents, options = {}) {
  const callbacks = [], exceptions = [], timers = new Map();
  let transactionCompleted = false, dbClosed = false, nextTimer = 1;
  let context;
  const db = {
    name: '/userfs', version: 1,
    objectStoreNames: { contains: value => value === 'FILE_DATA', [Symbol.iterator]: function* () { yield 'FILE_DATA'; } },
    close() { dbClosed = true; },
    transaction(store, mode) {
      assert.equal(store, 'FILE_DATA'); assert.equal(mode, 'readonly');
      const tx = {
        objectStore() { return { get() {
          const read = {};
          queueMicrotask(() => {
            if (options.toggleTo !== undefined) context.window.towdownSave.diagnosticsEnabled = options.toggleTo;
            read.result = options.missing ? undefined : { contents };
            try { read.onsuccess(); }
            catch (error) {
              exceptions.push(String(error)); tx.error = error;
              if (tx.onabort) tx.onabort();
              return;
            }
            assert.equal(callbacks.length, 0, 'success cannot precede completed readonly transaction');
            queueMicrotask(() => {
              if (options.abort) { tx.error = new Error('injected read transaction abort'); tx.onabort(); return; }
              transactionCompleted = true; tx.oncomplete();
              if (options.duplicateCompletion) tx.oncomplete();
            });
          });
          return read;
        } }; },
      };
      return tx;
    },
  };
  context = {
    window: { addEventListener() {} },
    indexedDB: { open() { const request = {}; queueMicrotask(() => { request.result = db; request.onsuccess(); }); return request; } },
    TextEncoder, TextDecoder, Uint8Array, ArrayBuffer,
    performance: { now: () => 123 },
    setTimeout(callback, milliseconds) { const id = nextTimer++; timers.set(id, { callback, milliseconds }); return id; },
    clearTimeout(id) { timers.delete(id); },
  };
  vm.runInNewContext(bridge, context, { filename: sourcePath + ':WEB_CONFIRM' });
  context.window.towdownSave.diagnosticsEnabled = !!options.diagnostics;
  context.window.towdownSave.verify('/userfs/camp-v1.json', text, 91, (revision, success, reason) => callbacks.push({ revision, success, reason }));
  await new Promise(resolve => setImmediate(resolve));
  const shouldConfirm = options.shouldConfirm !== false;
  const confirmed = callbacks.some(entry => entry.success);
  const contractHolds = confirmed === shouldConfirm && exceptions.length === 0 && callbacks.length <= 1;
  return { name, shouldConfirm, confirmed, transactionCompleted, dbClosed, callbacks, exceptions, contractHolds };
}

(async () => {
  const padded = Uint8Array.from([0xff, 0xee, 0xdd, ...bytes, 0xcc]);
  const foreignRaw = vm.runInNewContext('new ArrayBuffer(' + bytes.length + ')');
  new Uint8Array(foreignRaw).set(bytes);
  const foreignTyped = vm.runInNewContext('new Uint8Array(' + bytes.length + ')');
  foreignTyped.set(bytes);
  const results = [];
  results.push(await runCase('plain ArrayBuffer', bytes.buffer));
  results.push(await runCase('Uint8Array view with nonzero byteOffset', padded.subarray(3, 3 + bytes.length)));
  results.push(await runCase('DataView with nonzero byteOffset', new DataView(padded.buffer, 3, bytes.length), { diagnostics: true }));
  results.push(await runCase('foreign-realm Uint8Array view', foreignTyped));
  // Actual IndexedDB structured-clones raw ArrayBuffer into the request realm;
  // this synthetic case is reported separately, not a product requirement.
  results.push(await runCase('synthetic foreign raw ArrayBuffer is rejected', foreignRaw, { shouldConfirm: false }));
  results.push(await runCase('array storage is rejected safely with diagnostics', [...bytes], { diagnostics: true, shouldConfirm: false }));
  results.push(await runCase('string storage is rejected safely with diagnostics', text, { diagnostics: true, shouldConfirm: false }));
  results.push(await runCase('missing contents is rejected safely with diagnostics', undefined, { diagnostics: true, shouldConfirm: false }));
  results.push(await runCase('missing row is rejected safely with diagnostics', undefined, { diagnostics: true, missing: true, shouldConfirm: false }));
  results.push(await runCase('duplicate transaction completion confirms at most once', bytes, { diagnostics: true, duplicateCompletion: true }));
  results.push(await runCase('abort after exact read cannot confirm', bytes, { diagnostics: true, abort: true, shouldConfirm: false }));
  results.push(await runCase('diagnostics true to false while read in flight', bytes, { diagnostics: true, toggleTo: false }));
  results.push(await runCase('diagnostics false to true while read in flight', bytes, { toggleTo: true }));
  console.log(JSON.stringify({ sourcePath, noRealIndexedDB: true, results }, null, 2));
  process.exitCode = results.every(result => result.contractHolds) ? 0 : 1;
})().catch(error => { console.error(error); process.exitCode = 2; });
