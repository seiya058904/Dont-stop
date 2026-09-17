// Throwaway diagnostic: is the probe's new `scroll=` field present, and does the wheel move it?
const { chromium } = require('playwright');
const url = process.argv[2];
(async () => {
	const b = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
	const ctx = await b.newContext({ viewport: { width: 1366, height: 768 } });
	const page = await ctx.newPage();
	let last = null;
	page.on('console', m => {
		const t = m.text();
		if (t.startsWith('[probe] ') && t.includes('frames=')) last = t;
	});
	await page.goto(url + '?probe=1', { waitUntil: 'domcontentloaded', timeout: 60000 });
	await page.waitForFunction(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	}, { timeout: 300000 }).catch(() => {});
	await new Promise(r => setTimeout(r, 6000));
	console.log('probe line tail:', last ? last.slice(-160) : 'NONE');
	const rect = await page.evaluate(() => {
		const c = document.querySelector('#canvas-host canvas');
		const r = c.getBoundingClientRect();
		return { x: r.x, y: r.y, w: r.width, h: r.height };
	});
	const toCss = (dx, dy) => ({ x: rect.x + (dx / 410) * rect.w, y: rect.y + (dy / 230) * rect.h });
	const c = toCss(41, 136);
	await page.mouse.move(c.x, c.y); await new Promise(r => setTimeout(r, 150));
	await page.mouse.down(); await new Promise(r => setTimeout(r, 120)); await page.mouse.up();
	await new Promise(r => setTimeout(r, 3000));
	console.log('after start click:', last ? last.slice(-160) : 'NONE');
	const lp = toCss(80, 140);
	await page.mouse.move(lp.x, lp.y); await new Promise(r => setTimeout(r, 200));
	for (let i = 0; i < 6; i++) {
		await page.mouse.wheel(0, 500);
		await new Promise(r => setTimeout(r, 300));
		console.log('wheel down', i, last ? last.match(/scroll=(-?\d+)/) : null);
	}
	for (let i = 0; i < 6; i++) {
		await page.mouse.wheel(0, -500);
		await new Promise(r => setTimeout(r, 300));
		console.log('wheel up  ', i, last ? last.match(/scroll=(-?\d+)/) : null);
	}
	await b.close();
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
