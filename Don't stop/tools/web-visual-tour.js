// TowDownGame Web visual + frame-time tour (Playwright, real Chromium).
//
// Usage: node web-visual-tour.js <url> <outDir> [1920x1080 2560x1440 3840x2160]
//   E2E_HEADED=1   run a real windowed Chromium instead of headless
//
// The in-game harness runs with ?smoke=1&tour=1 and prints `[tour] screen=<name>`
// markers as it walks the product screens. This driver waits for each marker,
// captures a screenshot, and attributes the frame times measured *between*
// screenshots to that screen (screenshots themselves are excluded because the
// capture readback would be charged to the product).
//
// Exit code 0 = every screen was reached, no console errors, no HTTP errors.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
if (!url) { console.error('usage: node web-visual-tour.js <url> <outDir> [WxH ...]'); process.exit(2); }
const resolutions = (process.argv.slice(4).length ? process.argv.slice(4) : ['1920x1080', '2560x1440', '3840x2160'])
	.map(s => { const [w, h] = s.split('x').map(Number); return { w, h }; });
fs.mkdirSync(outDir, { recursive: true });

const headed = process.env.E2E_HEADED === '1';
const SCREENS = ['title', 'camp', 'shop', 'upgrades', 'talents', 'shop-owned', 'upgrades-owned', 'talents-owned', 'stats', 'training', 'combat', 'shooting', 'pause', 'boss', 'done'];

function percentile(sorted, p) {
	if (!sorted.length) return null;
	const idx = Math.min(sorted.length - 1, Math.max(0, Math.round((sorted.length - 1) * p)));
	return sorted[idx];
}

(async () => {
	const browser = await chromium.launch(headed
		? { headless: false, args: ['--window-size=1400,900'] }
		: { headless: true, args: ['--enable-unsafe-swiftshader'] });

	const report = { url, headed, resolutions: [], screens: SCREENS };
	let failures = 0;

	for (const { w, h } of resolutions) {
		const label = `${w}x${h}`;
		console.log(`\n=== ${label} ===`);
		const context = await browser.newContext({ viewport: { width: w, height: h } });
		const page = await context.newPage();
		const gameLines = [];
		const consoleErrors = [];
		const httpErrors = [];
		page.on('console', m => {
			if (m.type() === 'error') consoleErrors.push(m.text());
			const t = m.text();
			if (t.includes('[tour]')) gameLines.push(t);
		});
		page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));
		page.on('response', r => { if (r.status() >= 400) httpErrors.push(`${r.status()} ${r.url()}`); });

		await page.goto(url + (url.includes('?') ? '&' : '?') + 'smoke=1&tour=1', { waitUntil: 'domcontentloaded' });
		// The shell removes itself once the game reports the title menu is ready;
		// there is no click-to-start button any more.
		const ready = await page.waitForFunction(() => {
			const f = document.getElementById('frame');
			return !f || f.style.display === 'none' || f.classList.contains('gone');
		}, { timeout: 300000 }).then(() => true).catch(() => false);
		if (!ready) { console.log(`  FAIL loader never became ready at ${label}`); failures++; await context.close(); continue; }
		await page.waitForSelector('#canvas-host canvas', { timeout: 60000 });

		// Frame-time sampler: requestAnimationFrame deltas are exactly the frames
		// the compositor presented, independent of the engine's own counters.
		await page.evaluate(() => {
			window.__frames = [];
			window.__stop = false;
			let last = performance.now();
			const tick = now => {
				if (window.__stop) return;
				window.__frames.push(now - last);
				last = now;
				requestAnimationFrame(tick);
			};
			requestAnimationFrame(tick);
		});

		const perScreen = {};
		const missing = [];
		let cursor = 0;
		for (const screen of SCREENS) {
			let found = null;
			const t0 = Date.now();
			while (Date.now() - t0 < 600000) {
				for (let i = cursor; i < gameLines.length; i++) {
					if (gameLines[i].includes(`screen=${screen}`)) { found = gameLines[i]; cursor = i + 1; break; }
				}
				if (found) break;
				await page.waitForTimeout(250);
			}
			if (!found) { missing.push(screen); console.log(`  FAIL screen never reached: ${screen}`); continue; }
			// Frames measured up to this point belong to the previous screen; the
			// screenshot itself is taken after the sample so its readback cost is
			// never charged to the product.
			const frames = await page.evaluate(() => { const f = window.__frames; window.__frames = []; return f; });
			await page.screenshot({ path: path.join(outDir, `${screen}-${label}.png`) });
			if (screen !== 'done') {
				const sorted = frames.slice().sort((a, b) => a - b);
				const p50 = percentile(sorted, 0.50), p95 = percentile(sorted, 0.95), p99 = percentile(sorted, 0.99);
				const max = sorted.length ? sorted[sorted.length - 1] : null;
				// A tight ~1000 ms median is Chromium's background rAF throttle for
				// an occluded/hidden page, not product cost. Flag it so a throttled
				// resolution can never be read as a performance measurement.
				const throttled = sorted.length > 20 && p50 > 500;
				perScreen[screen] = {
					frames: sorted.length,
					p50_ms: p50 && +p50.toFixed(2), p95_ms: p95 && +p95.toFixed(2),
					p99_ms: p99 && +p99.toFixed(2), max_ms: max && +max.toFixed(2),
					over_33ms: sorted.filter(v => v > 33).length,
					over_50ms: sorted.filter(v => v > 50).length,
					throttled,
				};
				console.log(`  ok   ${screen.padEnd(9)} n=${sorted.length} p50=${p50 ? p50.toFixed(1) : '?'} p95=${p95 ? p95.toFixed(1) : '?'} p99=${p99 ? p99.toFixed(1) : '?'} max=${max ? max.toFixed(1) : '?'} >33ms=${perScreen[screen].over_33ms}${throttled ? ' THROTTLED(background rAF — not a perf number)' : ''}`);
			} else {
				console.log(`  ok   ${screen} (tour complete)`);
			}
		}
		await page.evaluate(() => { window.__stop = true; }).catch(() => {});

		// This revision does not use Pointer Lock at all, so there is no longer a
		// class of scripted-gesture lock rejections to excuse. Whatever the page
		// reports is reported as-is, apart from the noise list below.
		const blocking = consoleErrors.filter(e =>
			!/WebGL|GL_|AudioContext|download|currentTime|PagedAllocator|ObjectDB|still in use at exit/i.test(e));
		report.resolutions.push({
			label, screens: perScreen, missing,
			console_errors: blocking.length, http_errors: httpErrors.length,
		});
		if (missing.length || blocking.length || httpErrors.length) {
			failures++;
			if (blocking.length) console.log('  console errors: ' + blocking.slice(0, 3).join(' | '));
			if (httpErrors.length) console.log('  http errors: ' + httpErrors.slice(0, 3).join(' | '));
		} else {
			console.log(`  ${label} clean`);
		}
		await context.close();
	}

	fs.writeFileSync(path.join(outDir, 'web-visual-tour.json'), JSON.stringify(report, null, 2));
	console.log('\n[e2e] evidence -> ' + path.join(outDir, 'web-visual-tour.json'));
	// PNG sizes are reported so a blank/black capture is visible in the log.
	console.log('[e2e] screenshots:');
	for (const f of fs.readdirSync(outDir).filter(f => f.endsWith('.png')).sort()) {
		console.log(`  ${f.padEnd(34)} ${(fs.statSync(path.join(outDir, f)).size / 1024).toFixed(0)} KiB`);
	}
	await browser.close();
	if (failures) { console.log('[e2e] RESULT=FAIL'); process.exit(1); }
	console.log('[e2e] RESULT=PASS');
})().catch(e => { console.error('[e2e] FATAL', e && e.stack ? e.stack : e); process.exit(1); });
