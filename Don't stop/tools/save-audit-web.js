// TowDownGame Web save-isolation audit (Playwright).
// Usage: node save-audit-web.js <url> [workDir]
// T5 fresh profile, T6 persistence (reload + browser restart), T7 profile
// isolation, plus an IndexedDB storage audit of what Godot's user:// maps to.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const url = process.argv[2];
const work = process.argv[3] || '/tmp/towdown-save-audit';
if (!url) { console.error('usage: node save-audit-web.js <url> [workDir]'); process.exit(2); }
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });

let fail = null;
const step = (name, ok, extra = '') => {
	console.log(`[save-audit] ${ok ? 'ok' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
	if (!ok && !fail) fail = name;
};

async function smokeRun(page, maxMs = 480000) {
	const log = [];
	page.on('console', m => { const t = m.text(); if (t.includes('[smoke]')) log.push(t); });
	await page.goto(url + '?smoke=1', { waitUntil: 'domcontentloaded' });
	await page.locator('#start').waitFor({ state: 'visible', timeout: 300000 });
	await page.locator('#start').click();
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
	// ---- T5 + T6: persistent profile A.
	const dirA = path.join(work, 'profileA');
	const ctxA = await chromium.launchPersistentContext(dirA, { headless: true, viewport: { width: 1280, height: 720 }, args: ['--enable-unsafe-swiftshader'] });
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
	{
		const ctxA2 = await chromium.launchPersistentContext(dirA, { headless: true, viewport: { width: 1280, height: 720 }, args: ['--enable-unsafe-swiftshader'] });
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
	}

	// ---- T7: different profile must not see profile A's save.
	{
		const dirB = path.join(work, 'profileB');
		const ctxB = await chromium.launchPersistentContext(dirB, { headless: true, viewport: { width: 1280, height: 720 }, args: ['--enable-unsafe-swiftshader'] });
		const page = await ctxB.newPage();
		const log = await smokeRun(page);
		step('T7-profile-isolation', isFresh(log), `fresh profile save_state: ${line(log, 'save_state')}`);
		await page.close();
		await ctxB.close();
	}

	if (fail) { console.log(`[save-audit] RESULT=FAIL (${fail})`); process.exit(1); }
	console.log('[save-audit] RESULT=PASS');
})().catch(e => { console.error('[save-audit] FATAL', e); process.exit(1); });
