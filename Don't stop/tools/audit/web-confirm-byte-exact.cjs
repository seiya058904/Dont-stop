'use strict';

// Exercises WEB_CONFIRM extracted verbatim from production CampSaveStore.gd.
// Only IndexedDB completion and scheduling are adapted: no bridge algorithm is
// reimplemented. This is a unit reproduction, NOT a browser/Godot acceptance.
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');

const sourcePath = process.argv[2] || path.join(process.cwd(), "Don't stop/game/config/CampSaveStore.gd");
const source = fs.readFileSync(sourcePath, 'utf8');
const match = /const WEB_CONFIRM = """([\s\S]*?)"""/.exec(source);
assert(match, 'production WEB_CONFIRM constant exists');
const bridge = match[1];

async function runCase(name, text, rowBytes) {
  const callbacks = [];
  const timers = new Map();
  let nextTimer = 1;
  let dbClosed = false;
  let transactionCompleted = false;
  const db = {
    name: '/userfs', version: 1, objectStoreNames: {
      contains: name => name === 'FILE_DATA',
      [Symbol.iterator]: function* () { yield 'FILE_DATA'; },
    },
    close() { dbClosed = true; },
    transaction(store, mode) {
      assert.equal(store, 'FILE_DATA');
      assert.equal(mode, 'readonly');
      const tx = {
        objectStore(name) {
          assert.equal(name, store);
          return {
            get() {
              const request = {};
              queueMicrotask(() => {
                request.result = { contents: rowBytes };
                request.onsuccess();
                queueMicrotask(() => {
                  transactionCompleted = true;
                  tx.oncomplete();
                });
              });
              return request;
            },
          };
        },
      };
      return tx;
    },
  };
  const sandbox = {
    window: { addEventListener() {} },
    indexedDB: { open() {
      const open = {};
      queueMicrotask(() => { open.result = db; open.onsuccess(); });
      return open;
    } },
    TextEncoder, TextDecoder, Uint8Array, ArrayBuffer,
    performance: { now: () => 123 },
    setTimeout(callback, milliseconds) {
      const id = nextTimer++;
      timers.set(id, { callback, milliseconds });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
  };
  vm.runInNewContext(bridge, sandbox, { filename: sourcePath + ':WEB_CONFIRM' });
  sandbox.window.towdownSave.verify('/userfs/camp-v1.json', text, 17,
    (revision, success, reason) => callbacks.push({ revision, success, reason }));
  await new Promise(resolve => setImmediate(resolve));
  assert(transactionCompleted, 'row was observed through completed read transaction');
  const expected = Buffer.from(new TextEncoder().encode(text));
  const actual = Buffer.from(rowBytes.buffer, rowBytes.byteOffset, rowBytes.byteLength);
  const byteEqual = expected.equals(actual);
  const confirmedSuccess = callbacks.some(result => result.success);
  return { name, expectedHex: expected.toString('hex'), actualHex: actual.toString('hex'),
    byteEqual, confirmedSuccess, dbClosed, callbacks,
    contractHolds: confirmedSuccess === byteEqual };
}

(async () => {
  const text = '{"schema_version":6,"gold":100}';
  const bytes = new TextEncoder().encode(text);
  const bom = Uint8Array.from([0xef, 0xbb, 0xbf, ...bytes]);
  const replacementText = '{"label":"\ufffd"}';
  const invalidUtf8 = Uint8Array.from([...new TextEncoder().encode('{"label":"'), 0xff,
    ...new TextEncoder().encode('"}')]);
  const results = [];
  results.push(await runCase('exact stored bytes', text, bytes));
  results.push(await runCase('different ordinary snapshot is not confirmed', text,
    new TextEncoder().encode('{"schema_version":6,"gold":101}')));
  results.push(await runCase('BOM prepended to otherwise exact snapshot', text, bom));
  results.push(await runCase('invalid UTF-8 aliases a replacement character', replacementText, invalidUtf8));
  console.log(JSON.stringify({ sourcePath, results }, null, 2));
  process.exitCode = results.every(result => result.contractHolds) ? 0 : 1;
})().catch(error => { console.error(error); process.exitCode = 2; });
