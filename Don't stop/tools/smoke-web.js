// Don't Stop — Web browser smoke test (Playwright).
// Usage: node smoke-web.js <url> [screenshotDir]
//
// Fails (exit 1) on: HTTP errors/404s, page errors, default Godot branding, a
// loader shell that never goes away, a second "start" button in the shell,
// missing canvas, dead page, or failed in-game smoke markers.
//
// The shell (web/loader.html) no longer has a click-to-start button: it removes
// itself once the game reports the title menu is ready, and the player's first
// click is the game's own menu button.
const { chromium } = require('playwright');

const url = process.argv[2];
const shotDir = process.argv[3] || '.';
if (!url) { console.error('usage: node smoke-web.js <url> [shotDir]'); process.exit(2); }

(async () => {
	const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
	const context = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
	let fail = null;
	const badResponses = [];
	const pageErrors = [];
	let engineLog = [];

	context.on('response', r => { if (r.status() >= 400) badResponses.push(`${r.status()} ${r.url()}`); });

	const step = (name, ok, extra = '') => {
		console.log(`[smoke-web] ${ok ? 'ok' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
		if (!ok && !fail) fail = name;
	};

	async function newGamePage(query, maxLoadMs) {
		const page = await context.newPage();
		pageErrors.length = 0;
		engineLog = [];
		page.on('pageerror', e => pageErrors.push(String(e.message).slice(0, 300)));
		page.on('console', m => {
			const t = m.text();
			if (t.includes('[smoke]') || t.includes('[warmup]') || t.includes('[boot]')) engineLog.push(t);
		});
		await page.goto(url + query, { waitUntil: 'domcontentloaded', timeout: 60000 });
		const appeared = await page.waitForFunction(() => {
			const f = document.getElementById('frame');
			return !f || f.style.display === 'none' || f.classList.contains('gone');
		}, { timeout: maxLoadMs }).then(() => true).catch(() => false);
		if (!appeared) {
			step('loading-completes', false, 'status=' + await page.locator('#status').innerText().catch(() => '?'));
			return null;
		}
		step('loading-completes', true);
		await page.waitForSelector('#canvas-host canvas', { timeout: 30000 });
		await page.waitForTimeout(5000);
		return page;
	}

	// ---- Phase 1: branding / loading page checks + visual boot.
	{
		const page = await context.newPage();
		await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
		step('no-shell-start-button', (await page.locator('#start').count()) === 0);
		step('dont-stop-title', (await page.title()).includes("Don't Stop"));
		const frameText = await page.locator('#frame').innerText().catch(() => '');
		step('no-godot-branding', !/godot/i.test(frameText));
		step('no-second-start-prompt', !/点击开始|立即开始|点击任意|click to start/i.test(frameText));
		await page.close();
	}
	{
		const page = await newGamePage('', 300000);
		if (page) {
			await page.screenshot({ path: shotDir + '/01-title.png' });
			const canvasOk = await page.evaluate(() => {
				const c = document.querySelector('#canvas-host canvas');
				return !!c && c.width > 0 && c.height > 0;
			});
			step('canvas-alive', canvasOk);
			await page.close();
		}
	}

	// ---- Phase 2: in-game smoke run (?smoke=1).
	{
		const page = await newGamePage('?smoke=1', 300000);
		if (page) {
			const t0 = Date.now();
			let finished = false;
			while (Date.now() - t0 < 480000) {
				if (engineLog.some(l => l.includes('[smoke] result='))) { finished = true; break; }
				await page.waitForTimeout(1000);
			}
			const pass = engineLog.some(l => l.includes('[smoke] result=PASS'));
			step('in-game-smoke', finished && pass, engineLog.filter(l => l.includes('[smoke]')).join(' ; ').slice(0, 900));
			await page.screenshot({ path: shotDir + '/02-combat.png' });
			step('page-alive', await page.evaluate(() => !!document.querySelector('#canvas-host canvas')));

			// ---- Phase 3: keyboard + panel + weapon/fire input sanity.
			await page.keyboard.press('Tab');
			await page.waitForTimeout(1500);
			await page.screenshot({ path: shotDir + '/03-panel.png' });
			await page.keyboard.press('Escape');
			await page.waitForTimeout(800);
			await page.keyboard.press('2');
			await page.waitForTimeout(800);
			await page.mouse.move(960, 540);
			await page.mouse.down(); await page.waitForTimeout(400); await page.mouse.up();
			await page.waitForTimeout(500);
			await page.screenshot({ path: shotDir + '/04-fire.png' });
			step('still-alive-after-input', await page.evaluate(() => !!document.querySelector('#canvas-host canvas')));
			await page.close();
		}
	}

	const blocking = pageErrors.filter(e => !/WebGL|GL_|AudioContext|download|currentTime/i.test(e));
	step('no-blocking-console', blocking.length === 0, blocking.slice(0, 3).join(' | '));
	step('no-http-errors', badResponses.length === 0, badResponses.slice(0, 5).join(' | '));

	await browser.close();
	if (fail) { console.log(`[smoke-web] RESULT=FAIL (${fail})`); process.exit(1); }
	console.log('[smoke-web] RESULT=PASS');
})().catch(e => { console.error('[smoke-web] FATAL', e); process.exit(1); });
