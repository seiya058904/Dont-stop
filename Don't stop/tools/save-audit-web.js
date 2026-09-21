// Don't stop — Web save-isolation audit (Playwright).
//
// Usage: node save-audit-web.js <url> [workDir]
//
// T5 fresh profile, T6 persistence (reload + browser restart), T7 profile
// isolation, plus an IndexedDB storage audit of what Godot's user:// maps to.
//
// SAFETY: this script used to `rmSync(workDir, {recursive:true, force:true})` on
// whatever path the caller passed, which deletes an unrelated directory if the
// argument is wrong. It now only ever creates and removes a subdirectory it
// created itself, marked with an ownership file, and it removes that subdirectory
// on every exit path - including failures.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const os = require('os');

const url = process.argv[2];
const baseDir = process.argv[3] || path.join(os.tmpdir(), 'dontstop-save-audit');
if (!url) { console.error('usage: node save-audit-web.js <url> [workDir]'); process.exit(2); }

const OWNER_MARKER = '.dontstop-save-audit-owned';
const stamp = `${process.pid}-${Date.now().toString(36)}`;
const work = path.join(baseDir, `run-${stamp}`);

function makeWorkDir() {
	fs.mkdirSync(work, { recursive: true });
	// Ownership marker: only a directory carrying this file may be cleaned up.
	fs.writeFileSync(path.join(work, OWNER_MARKER), `dontstop save-audit ${stamp}\n`);
}

function cleanWorkDir() {
	try {
		if (!fs.existsSync(path.join(work, OWNER_MARKER))) return;
		fs.rmSync(work, { recursive: true, force: true });
		console.log(`[save-audit] cleaned ${work}`);
	} catch (err) {
		console.error(`[save-audit] could not clean ${work}: ${err.message}`);
	}
}

let fail = null;
let browser = null;
const step = (name, ok, extra = '') => {
	console.log(`[save-audit] ${ok ? 'ok' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
	if (!ok && !fail) fail = name;
};

// The shell (web/loader.html) removes itself once the game reports the title
// menu is ready; there is no click-to-start button any more.
async function waitForShellGone(page, maxMs = 300000) {
	await page.waitForFunction(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	}, null, { timeout: maxMs });
}

async function smokeRun(page, maxMs = 480000) {
	const log = [];
	page.on('console', m => { const t = m.text(); if (t.includes('[smoke]')) log.push(t); });
	await page.goto(url + '?smoke=1', { waitUntil: 'domcontentloaded' });
	await waitForShellGone(page);
	await page.waitForSelector('#canvas-host canvas', { timeout: 30000 });
	const t0 = Date.now();
	while (Date.now() - t0 < maxMs) {
		if (log.some(l => l.includes('[smoke] result='))) break;
		await page.waitForTimeout(1000);
	}
	return log;
}
const line = (log, key) => log.find(l => l.includes(key));
const field = (log, key, name) => {
	const l = line(log, key); if (!l) return null;
	const m = l.match(new RegExp(name + '="([^"]*)"'));
	return m ? m[1] : null;
};
const isFresh = log => !!line(log, 'save_state')?.includes('save_state none');

(async () => {
	makeWorkDir();
	try {
		// ---- T5 + T6: persistent profile A.
		const dirA = path.join(work, 'profileA');
		const ctxA = await chromium.launchPersistentContext(dirA, { headless: true, viewport: { width: 1280, height: 720 }, args: ['--enable-unsafe-swiftshader'] });
		browser = ctxA;
		{
			const page = await ctxA.newPage();
			const log = await smokeRun(page);
			step('T5-fresh-profile', isFresh(log), 'first-run save_state: ' + line(log, 'save_state'));
			// T6a: reload in same context.
			const log2 = await smokeRun(page);
			const eq2 = field(log2, 'save_state', 'equipped');
			const gold2 = field(log2, 'save_state', 'gold');
			step('T6a-reload-restores', !isFresh(log2) && gold2 !== null, `after reload equipped=${eq2} gold=${gold2}`);
			await page.close();
		}
		// T6b: full browser restart (new process, same profile dir).
		await ctxA.close();
		browser = null;
		{
			const ctxA2 = await chromium.launchPersistentContext(dirA, { headless: true, viewport: { width: 1280, height: 720 }, args: ['--enable-unsafe-swiftshader'] });
			browser = ctxA2;
			const page = await ctxA2.newPage();
			const log = await smokeRun(page);
			const eq = field(log, 'save_state', 'equipped');
			const gold = field(log, 'save_state', 'gold');
			step('T6b-browser-restart-restores', !isFresh(log) && gold !== null, `equipped=${eq} gold=${gold}`);
			// IndexedDB audit inside the live origin.
			const audit = await page.evaluate(async () => {
				const dbs = await (indexedDB.databases ? indexedDB.databases() : Promise.resolve([]));
				const names = dbs.map(d => d.name);
				let godotObjects = null;
				if (names.includes('/userfs')) {
					godotObjects = await new Promise(res => {
						const req = indexedDB.open('/userfs');
						req.onsuccess = () => {
							const db = req.result;
							const out = [];
							let pending = db.objectStoreNames.length;
							if (!pending) return res(out);
							for (const store of db.objectStoreNames) {
								const r = db.transaction(store).objectStore(store).getAllKeys();
								r.onsuccess = () => { out.push(store + ':' + r.result.length + 'keys'); if (--pending === 0) res(out); };
								r.onerror = () => { if (--pending === 0) res(out); };
							}
						};
						req.onerror = () => res(['open-failed']);
					});
				}
				return { names, godotObjects };
			});
			step('userfs-in-indexeddb', audit.names.some(n => n.includes('userfs')) && (audit.godotObjects === null || audit.godotObjects.length > 0),
				JSON.stringify(audit));
			await page.close();
			await ctxA2.close();
			browser = null;
		}

		// ---- T7: different profile must not see profile A's save.
		{
			const dirB = path.join(work, 'profileB');
			const ctxB = await chromium.launchPersistentContext(dirB, { headless: true, viewport: { width: 1280, height: 720 }, args: ['--enable-unsafe-swiftshader'] });
			browser = ctxB;
			const page = await ctxB.newPage();
			const log = await smokeRun(page);
			step('T7-profile-isolation', isFresh(log), `fresh profile save_state: ${line(log, 'save_state')}`);
			await page.close();
			await ctxB.close();
			browser = null;
		}
	} finally {
		if (browser) { try { await browser.close(); } catch (e) { /* already gone */ } }
		cleanWorkDir();
	}

	if (fail) { console.log(`[save-audit] RESULT=FAIL (${fail})`); process.exit(1); }
	console.log('[save-audit] RESULT=PASS');
})().catch(e => {
	console.error('[save-audit] FATAL', e);
	cleanWorkDir();
	process.exit(1);
});
