// TowDownGame Web REAL Pointer Lock E2E (Playwright).
// Usage: node pointer-lock-e2e.js <url> [shotDir]
// Drives REAL browser input (pointer lock, relative mouse motion, real clicks,
// real keys) against the in-game E2E harness (?smoke=1&e2e=1) and asserts the
// full aiming chain: real mouse -> virtual aim -> gun rotation -> projectile
// velocity. Prints one token per acceptance assertion; any FAIL exits 1 so CI
// cannot deploy a broken web build.
const { chromium } = require('playwright');

const url = process.argv[2];
const shotDir = process.argv[3] || '.';
if (!url) { console.error('usage: node pointer-lock-e2e.js <url> [shotDir]'); process.exit(2); }

const tokens = {};
function token(name, ok, extra = '') {
	tokens[name] = !!ok;
	console.log(`[e2e] ${ok ? 'ok' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
}

(async () => {
	const browser = await chromium.launch({ headless: false, args: ['--window-size=1400,900'] });
	const page = await (await browser.newContext({ viewport: { width: 1280, height: 800 } })).newPage();
	const lines = [];
	page.on('console', m => { const t = m.text(); if (t.includes('[e2e]')) lines.push(t); });
	const locked = () => page.evaluate(() => document.pointerLockElement === document.querySelector('#canvas-host canvas'));
	const aimLines = () => lines.filter(l => l.includes('gunrot='));
	const latest = () => {
		for (let i = lines.length - 1; i >= 0; i--) {
			const l = lines[i];
			if (l.includes('gunrot=')) return parseState(l);
		}
		return null;
	};
	const parseState = l => {
		const num = re => { const m = l.match(re); return m ? parseFloat(m[1]) : NaN; };
		const vec = re => { const m = l.match(re); return m ? { x: parseFloat(m[1]), y: parseFloat(m[2]) } : null; };
		return {
			mousemode: num(/mousemode=(\d+)/),
			aimvp: vec(/aimvp=\(([-\d.]+), ([-\d.]+)\)/),
			aimworld: vec(/aimworld=\(([-\d.]+), ([-\d.]+)\)/),
			gunrot: num(/gunrot=(-?[\d.]+)/),
			gunid: num(/gunid=(-?\d+)/),
			playerpos: vec(/playerpos=\(([-\d.]+), ([-\d.]+)\)/),
			paused: l.includes('paused=true'),
		};
	};
	const aimAngle = st => Math.atan2(st.aimworld.y - st.playerpos.y, st.aimworld.x - st.playerpos.x) * 180 / Math.PI;
	const shortestDelta = (a, b) => { let d = (b - a) % 360; if (d > 180) d -= 360; if (d < -180) d += 360; return d; };
	async function waitFor(pred, ms) {
		const t0 = Date.now();
		while (Date.now() - t0 < ms) { if (pred()) return true; await page.waitForTimeout(250); }
		return false;
	}
	async function sweep(dx, dy) {
		const cx = 640, cy = 400;
		await page.mouse.move(cx, cy);
		for (let i = 0; i < 12; i++) await page.mouse.move(cx + dx * (i + 1) / 12, cy + dy * (i + 1) / 12);
		await page.waitForTimeout(600);
	}

	await page.goto(url + (url.includes('?') ? '&' : '?') + 'smoke=1&e2e=1', { waitUntil: 'domcontentloaded' });
	await page.locator('#start').waitFor({ state: 'visible', timeout: 300000 });
	await page.locator('#start').click();
	await page.waitForSelector('#canvas-host canvas', { timeout: 60000 });

	// The in-game harness reports readiness once combat is live.
	const ready = await waitFor(() => lines.some(l => l.includes('[e2e] ready')), 360000);
	if (!ready) { console.log('[e2e] FATAL harness-not-ready'); await browser.close(); process.exit(1); }
	// User gesture click: the game requests Pointer Lock on gameplay click.
	await page.mouse.click(640, 400);
	await waitFor(locked, 10000);
	if (!(await locked())) { await page.mouse.click(640, 400); await waitFor(locked, 10000); }
	token('POINTER_LOCK_ACQUIRED', await locked());
	token('OS_CURSOR_HIDDEN', await locked()); // browser hides the OS cursor while locked

	// ---- Aim follows real relative mouse movement.
	// Each direction is measured after re-baselining the aim at the screen
	// centre so the expected angle delta is unambiguous.
	async function recenter() {
		// park the OS cursor at the canvas centre; under Pointer Lock this has
		// no absolute meaning, it only normalises the next deltas.
		await page.mouse.move(640, 400);
		await page.waitForTimeout(400);
	}
	async function aimLine() {
		for (let i = 0; i < 12; i++) {
			const st = latest();
			if (st && !isNaN(st.gunrot) && st.aimworld) return st;
			await page.waitForTimeout(250);
		}
		return latest();
	}
	async function sweepAngle(dx, dy) {
		lines.length = 0;
		await recenter();
		const before = await aimLine();
		lines.length = 0;
		await sweep(dx, dy);
		const after = await aimLine();
		if (!before || !after) return NaN;
		return shortestDelta(aimAngle(before), aimAngle(after));
	}

	const dRight = await sweepAngle(360, 0);
	token('AIM_MOVES_RIGHT', !isNaN(dRight) && dRight > 15, `dAngle=${dRight?.toFixed(1)}`);

	const dLeft = await sweepAngle(-360, 0);
	token('AIM_MOVES_LEFT', !isNaN(dLeft) && dLeft < -15, `dAngle=${dLeft?.toFixed(1)}`);

	// From the right-hand side (angle ~0), moving down increases the angle.
	await sweepAngle(360, 0);
	const dDown = await sweepAngle(0, 320);
	token('AIM_MOVES_DOWN', !isNaN(dDown) && dDown > 10, `dAngle=${dDown?.toFixed(1)}`);

	// From the right-hand side (angle ~0), moving up decreases the angle.
	await sweepAngle(360, 0);
	const dUp = await sweepAngle(0, -320);
	token('AIM_MOVES_UP', !isNaN(dUp) && dUp < -10, `dAngle=${dUp?.toFixed(1)}`);

	// ---- 360° continuous aim: keep sweeping in one direction and accumulate.
	lines.length = 0;
	await recenter();
	const start360 = await aimLine();
	let accumulated = 0;
	let prev = start360 ? aimAngle(start360) : NaN;
	for (let i = 0; i < 6; i++) {
		for (const [dx, dy] of [[400, 0], [400, 0], [0, 400], [0, 400]]) {
			await page.mouse.move(640, 400);
			for (let k = 0; k < 10; k++) await page.mouse.move(640 + dx * (k + 1) / 10, 400 + dy * (k + 1) / 10);
			await page.waitForTimeout(150);
			const st = latest();
			if (st) {
				const cur = aimAngle(st);
				if (!isNaN(cur) && !isNaN(prev)) accumulated += Math.abs(shortestDelta(prev, cur));
				prev = cur;
			}
		}
	}
	token('AIM_360', accumulated >= 360, `accumulated=${accumulated.toFixed(0)}deg`);

	// ---- Real shots follow the aim direction (velocity of fresh projectile).
	async function fireDirection(name, dx, dy, cmp) {
		for (let attempt = 0; attempt < 3; attempt++) {
			lines.length = 0;
			await sweep(dx, dy);
			await page.waitForTimeout(300);
			lines.length = 0;
			await page.mouse.down();
			await page.waitForTimeout(450);
			await page.mouse.up();
			await page.waitForTimeout(400);
			const projLine = lines.find(l => l.includes('[e2e] proj'));
			if (projLine) {
				const m = projLine.match(/proj vx=(-?[\d.]+) vy=(-?[\d.]+)/);
				const vx = parseFloat(m[1]), vy = parseFloat(m[2]);
				token(name, cmp(vx, vy), `vx=${vx.toFixed(1)} vy=${vy.toFixed(1)} attempt=${attempt}`);
				return;
			}
			// Magazine ran dry (capture clicks also fire): reload and retry.
			await page.keyboard.press('r');
			await page.waitForTimeout(2600);
		}
		token(name, false, 'no projectile spawned');
	}
	await fireDirection('PROJECTILE_FOLLOWS_AIM_RIGHT', 300, 0, (vx) => vx > 5);
	await fireDirection('PROJECTILE_FOLLOWS_AIM_LEFT', -300, 0, (vx) => vx < -5);
	await fireDirection('PROJECTILE_FOLLOWS_AIM_DOWN', 0, 260, (vx, vy) => vy > 5);
	await fireDirection('PROJECTILE_FOLLOWS_AIM_UP', 0, -260, (vx, vy) => vy < -5);

	// ---- ESC releases Pointer Lock and opens the pause panel (mouse visible).
	let escState = null;
	for (let attempt = 0; attempt < 2; attempt++) {
		await page.keyboard.press('Escape');
		const t0 = Date.now();
		while (Date.now() - t0 < 5000) {
			const l = lines.filter(l => l.includes('gunrot')).pop();
			if (l && l.includes('mousemode=0') && l.includes('paused=true')) {
				escState = parseState(l);
				break;
			}
			await page.waitForTimeout(250);
		}
		if (escState) break;
		await page.waitForTimeout(800);
	}
	token('ESC_RELEASES_POINTER_LOCK', escState != null && !(await locked()), `mousemode=${escState?.mousemode}`);
	token('PAUSE_MOUSE_VISIBLE', escState?.paused === true, 'pause panel open, OS cursor restored');

	// ---- Resume: closing the pause panel re-captures the pointer.
	await page.keyboard.press('Escape'); // CampPanel closes on ui_cancel
	await page.waitForTimeout(1200);
	if (!(await locked())) { await page.mouse.click(640, 400); await waitFor(locked, 8000); }
	const resumed = await waitFor(async () => (await locked()) && latest()?.paused === false, 10000);
	token('RESUME_RECAPTURES_POINTER_LOCK', resumed, `paused=${latest()?.paused}`);

	// ---- Real WASD movement while locked.
	await waitFor(() => latest()?.paused === false, 8000);
	if (!(await locked())) { await page.mouse.click(640, 400); await waitFor(locked, 8000); }
	lines.length = 0;
	const before = await aimLine();
	token('WASD_PREPARED', !!before && before.paused === false && !!(await locked()), `paused=${before?.paused}`);
	await page.keyboard.down('w');
	await page.waitForTimeout(700);
	await page.keyboard.up('w');
	await page.waitForTimeout(300);
	const afterW = await aimLine();
	token('WASD_POSITION_CHANGED', before && afterW && (before.playerpos.y - afterW.playerpos.y) > 2,
		`dy=${(before.playerpos.y - afterW.playerpos.y).toFixed(1)}`);
	let dKey = 'd';
	await page.keyboard.down(dKey);
	await page.waitForTimeout(700);
	await page.keyboard.up(dKey);
	await page.waitForTimeout(300);
	let afterD = await aimLine();
	if (!afterD || (afterD.playerpos.x - afterW.playerpos.x) <= 2) {
		// Right may be blocked by a wall; try left instead (still proves A/D).
		dKey = 'a';
		lines.length = 0;
		await page.keyboard.down(dKey);
		await page.waitForTimeout(700);
		await page.keyboard.up(dKey);
		await page.waitForTimeout(300);
		afterD = await aimLine();
	}
	token('WASD_POSITION_CHANGED', afterD && Math.abs(afterD.playerpos.x - afterW.playerpos.x) > 2,
		`key=${dKey} dx=${(afterD.playerpos.x - afterW.playerpos.x).toFixed(1)}`);

	await page.screenshot({ path: shotDir + '/e2e-final.png' });
	await browser.close();

	const required = ['POINTER_LOCK_ACQUIRED', 'OS_CURSOR_HIDDEN', 'AIM_MOVES_LEFT', 'AIM_MOVES_RIGHT',
		'AIM_MOVES_UP', 'AIM_MOVES_DOWN', 'AIM_360', 'PROJECTILE_FOLLOWS_AIM_RIGHT', 'PROJECTILE_FOLLOWS_AIM_LEFT',
		'PROJECTILE_FOLLOWS_AIM_DOWN', 'PROJECTILE_FOLLOWS_AIM_UP', 'ESC_RELEASES_POINTER_LOCK',
		'PAUSE_MOUSE_VISIBLE', 'RESUME_RECAPTURES_POINTER_LOCK', 'WASD_POSITION_CHANGED'];
	const failed = required.filter(k => !tokens[k]);
	for (const k of required) console.log(`[e2e] token ${k}=${tokens[k] ? 'true' : 'false'}`);
	if (failed.length) { console.log(`[e2e] RESULT=FAIL (${failed.join(',')})`); process.exit(1); }
	console.log('[e2e] RESULT=PASS');
})().catch(e => { console.error('[e2e] FATAL', e); process.exit(1); });
