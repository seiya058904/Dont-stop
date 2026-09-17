// Live check: does the DEPLOYED Pages build expose the Hell playtest entry to a real browser?
//
// Read-only where it matters: it loads the real URL, clicks the game's own start button and its
// own 出发 tab, and reports what the product's own probe channel says. It writes one screenshot.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
fs.mkdirSync(outDir, { recursive: true });

(async () => {
	const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
	const ctx = await browser.newContext({ viewport: { width: 1366, height: 768 } });
	const page = await ctx.newPage();
	let probe = null;
	const rects = {};
	page.on('console', m => {
		const t = m.text();
		if (t.startsWith('[probe] rect ')) {
			const g = t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+)/);
			if (g) rects[g[1]] = { text: g[3], cx: +g[8], cy: +g[9] };
			return;
		}
		if (t.startsWith('[probe] ') && t.includes('frames=')) probe = t;
	});
	await page.goto(url + '?probe=1', { waitUntil: 'domcontentloaded', timeout: 90000 });
	await page.waitForFunction(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	}, { timeout: 300000 }).catch(() => {});
	await new Promise(r => setTimeout(r, 8000));
	const rect = await page.evaluate(() => {
		const c = document.querySelector('#canvas-host canvas');
		if (!c) return null;
		const r = c.getBoundingClientRect();
		return { x: r.x, y: r.y, w: r.width, h: r.height };
	});
	const toCss = (dx, dy) => ({ x: rect.x + (dx / 410) * rect.w, y: rect.y + (dy / 230) * rect.h });
	async function click(dx, dy) {
		const c = toCss(dx, dy);
		await page.mouse.move(c.x, c.y); await new Promise(r => setTimeout(r, 150));
		await page.mouse.down(); await new Promise(r => setTimeout(r, 130)); await page.mouse.up();
	}
	// The game's own menu start button, then the camp's own 出发 tab.
	await click(41, 136);
	await new Promise(r => setTimeout(r, 6000));
	await click(361, 37);
	await new Promise(r => setTimeout(r, 6000));
	console.log('[live] probe:', probe ? probe.slice(-150) : 'NONE');
	console.log('[live] rects:', JSON.stringify(rects));
	console.log('[live] RESULT playtest_entry_visible=' + !!rects['hell-playtest-button'] +
		' formal_entries_locked=' + !Object.keys(rects).some(k => k.startsWith('stage-')));
	await page.screenshot({ path: path.join(outDir, 'live-playtest-entry.png') });
	await browser.close();
})().catch(e => { console.error('[live] FATAL', e.message); process.exit(1); });
