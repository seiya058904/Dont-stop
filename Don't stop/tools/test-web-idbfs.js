'use strict';
// Real IndexedDB equivalence and busy-frame diagnostic; not a game FPS gate.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
	const project = path.join(__dirname, '..');
	const engine = fs.readFileSync(path.join(process.argv[2] || path.join(project, 'build/web'), 'index.js'), 'utf8');
	const start = engine.indexOf('getRemoteSet:') + 'getRemoteSet:'.length;
	const end = engine.indexOf(',loadLocalEntry:', start);
	assert.ok(start > 'getRemoteSet:'.length && end > start, 'pinned IDBFS implementation must be found');
	const original = engine.slice(start, end);
	const source = fs.readFileSync(path.join(project, 'autoload/Utils.gd'), 'utf8');
	const patch = source.match(/const WEB_IDBFS_BATCH := """([\s\S]*?)"""/)[1];
	const browser = await chromium.launch({ headless: true });
	try {
		const page = await browser.newPage();
		await page.route('http://idbfs.test/**', route => route.fulfill({ contentType: 'text/html', body: '<title>IDBFS contract</title>' }));
		await page.goto('http://idbfs.test/');
		const result = await page.evaluate(async ({ original, patch }) => {
			const db = await new Promise((resolve, reject) => {
				const request = indexedDB.open('isolated-idbfs-contract', 1);
				request.onupgradeneeded = () => request.result.createObjectStore('FILE_DATA').createIndex('timestamp', 'timestamp');
				request.onsuccess = () => resolve(request.result);
				request.onerror = () => reject(request.error);
			});
			const IDBFS = { DB_STORE_NAME: 'FILE_DATA', getDB: (_, callback) => callback(null, db) };
			IDBFS.getRemoteSet = eval('(' + original + ')');
			const cursorRead = IDBFS.getRemoteSet;
			const enumerate = fn => new Promise((resolve, reject) => fn({ mountpoint: '/userfs' }, (error, value) => error ? reject(error) : resolve(value)));
			const normalize = result => Object.entries(result.entries).map(([key, value]) => [key, value.timestamp.getTime()]).sort();
			const emptyBefore = normalize(await enumerate(cursorRead));
			const installed = eval(patch);
			const bulkRead = IDBFS.getRemoteSet;
			const idempotent = eval(patch) === false && IDBFS.getRemoteSet === bulkRead;
			const emptyAfter = normalize(await enumerate(bulkRead));
			await new Promise((resolve, reject) => {
				const tx = db.transaction('FILE_DATA', 'readwrite');
				for (let i = 0; i < 40; i++) tx.objectStore('FILE_DATA').put({ timestamp: new Date(1000 + i % 4), mode: 33206, contents: new Uint8Array([i]) }, '/userfs/file-' + i);
				tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);
			});
			const before = normalize(await enumerate(cursorRead));
			const after = normalize(await enumerate(bulkRead));
			let busy = true;
			const frame = () => { if (!busy) return; const end = performance.now() + 35; while (performance.now() < end) {} requestAnimationFrame(frame); };
			requestAnimationFrame(frame);
			await new Promise(resolve => requestAnimationFrame(resolve));
			const beginCursor = performance.now(); await enumerate(cursorRead); const cursorMs = performance.now() - beginCursor;
			const beginBulk = performance.now(); await enumerate(bulkRead); const bulkMs = performance.now() - beginBulk;
			busy = false;
			let abortCalls = 0;
			const transaction = db.transaction;
			db.transaction = function (...args) {
				const tx = Reflect.apply(transaction, this, args);
				queueMicrotask(() => tx.abort());
				return tx;
			};
			const aborted = await new Promise(resolve => bulkRead({ mountpoint: '/userfs' }, error => { abortCalls++; resolve(!!error); }));
			db.transaction = transaction;
			await new Promise(resolve => setTimeout(resolve, 20));
			let errorCalls = 0;
			db.close();
			const closedError = await new Promise(resolve => bulkRead({ mountpoint: '/userfs' }, error => { errorCalls++; resolve(error?.name); }));
			await new Promise(resolve => setTimeout(resolve, 20));
			delete IDBFS.dontStopBulkIndex;
			IDBFS.getRemoteSet = cursorRead;
			const getAll = IDBIndex.prototype.getAll;
			IDBIndex.prototype.getAll = undefined;
			const fallback = eval(patch) === false && IDBFS.getRemoteSet === cursorRead;
			IDBIndex.prototype.getAll = getAll;
			return { installed, idempotent, fallback, emptyBefore, emptyAfter, before, after, aborted, abortCalls, closedError, errorCalls, cursorMs, bulkMs };
		}, { original, patch });
		assert.equal(result.installed, true);
		assert.equal(result.idempotent, true);
		assert.equal(result.fallback, true, 'unsupported browsers must retain the native cursor path');
		assert.deepEqual(result.emptyAfter, result.emptyBefore);
		assert.deepEqual(result.after, result.before, 'all primary keys and duplicate timestamps must match');
		assert.equal(result.after.length, 40);
		assert.equal(result.closedError, 'InvalidStateError');
		assert.equal(result.errorCalls, 1, 'errors must reach the caller exactly once');
		assert.equal(result.aborted, true);
		assert.equal(result.abortCalls, 1, 'aborted reads cannot return partial success');
		console.log(JSON.stringify({ result: 'PASS', ...result, before: undefined, after: undefined }));
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
