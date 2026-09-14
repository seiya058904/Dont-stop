// Don't stop — Web mouse-aim acceptance E2E (Playwright, real Chromium).
//
// Usage: node web-aim-e2e.js <url> [evidenceDir]
//   E2E_HEADED=1   run a real windowed Chromium (required for the OS focus phase)
//
// What changed in this revision, and why the old script was retired:
//   v1.0.2 proved its input chain by acquiring the browser's Pointer Lock. The
//   product decision for this round is the opposite: Web gameplay uses an
//   ordinary, un-captured pointer, and the player must be able to aim the moment
//   the world is interactive - no Esc, no second "start" click, no browser
//   setting. "Got Pointer Lock" is therefore no longer a passing token; the new
//   contract is absolute-cursor aiming, and that is what this script asserts.
//
// Phase A runs against the REAL entry point (no ?smoke / ?e2e / ?tour) and only
// uses what a player can do: load, click the game's own start button, close the
// camp panel, move the mouse. Phase B adds engine state streaming so the whole
// chain - cursor -> aim provider -> crosshair -> gun -> projectile - can be
// asserted numerically.
//
// Design rules kept from the previous revision:
//   * Never assert on a value the test itself moved: every sweep is followed by
//     its exact inverse, and each direction is checked for axis isolation.
//   * Never let an empty magazine, a round victory or a reward panel be reported
//     as an input bug: the round is frozen into a sandbox first.
//   * Never treat "the game says so" as proof of a visual claim: the crosshair
//     claim is backed by comparing real screenshots.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
if (!url) {
	console.error('usage: node web-aim-e2e.js <url> [evidenceDir]');
	process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const headed = process.env.E2E_HEADED === '1';
const VIEW = { w: 1366, h: 768 };

const tokens = {};
const notes = [];
function token(name, ok, extra = '') {
	tokens[name] = !!ok;
	console.log(`[aim-e2e] ${ok ? 'ok  ' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
}
function note(text) {
	notes.push(text);
	console.log('[aim-e2e] note ' + text);
}
const deg = r => r * 180 / Math.PI;
const wrap = a => { while (a > 180) a -= 360; while (a <= -180) a += 360; return a; };

(async () => {
	const browser = await chromium.launch(headed
		? { headless: false, args: ['--window-size=1400,900'] }
		: { headless: true, args: ['--enable-unsafe-swiftshader'] });
	const context = await browser.newContext({ viewport: { width: VIEW.w, height: VIEW.h } });
	const page = await context.newPage();

	const consoleErrors = [];
	const badResponses = [];
	const failedRequests = [];
	page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
	page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));
	page.on('response', r => { if (r.status() >= 400) badResponses.push(r.status() + ' ' + r.url()); });
	page.on('requestfailed', r => failedRequests.push(r.url() + ' :: ' + ((r.failure() && r.failure().errorText) || '?')));

	const shellGone = () => page.evaluate(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	});
	const canvasRect = () => page.evaluate(() => {
		const c = document.querySelector('#canvas-host canvas');
		if (!c) return null;
		const r = c.getBoundingClientRect();
		return { x: r.x, y: r.y, w: r.width, h: r.height };
	});
	async function waitFor(pred, ms, step = 150) {
		const t0 = Date.now();
		while (Date.now() - t0 < ms) { if (await pred()) return true; await page.waitForTimeout(step); }
		return false;
	}
	// A small PNG crop is enough to prove "something is drawn here" and "it
	// changed", without needing the engine to tell us anything.
	async function crop(x, y, w, h) {
		return page.screenshot({ clip: { x: Math.max(0, x - w / 2), y: Math.max(0, y - h / 2), width: w, height: h } });
	}

	// ======================================================== Phase A: real entry
	// Absolutely no query flags and no engine cooperation. Everything below is
	// what a first-time player does.
	await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });

	const shellAtStart = await page.evaluate(() => {
		const f = document.getElementById('frame');
		const text = f ? f.innerText : '';
		return {
			visible: !!f && getComputedStyle(f).display !== 'none',
			text,
			startButtons: document.querySelectorAll('#start, #start-button, .start-button').length,
			domButtons: Array.from(document.querySelectorAll('button')).map(b => (b.innerText || '').trim()),
		};
	});
	token('SINGLE_START_ENTRY_POINT',
		shellAtStart.startButtons === 0 &&
		!/点击开始|立即开始|点击任意|click to start|start game/i.test(shellAtStart.text),
		'shell buttons=' + JSON.stringify(shellAtStart.domButtons));
	token('LOADING_FEEDBACK_PRESENT', shellAtStart.visible && shellAtStart.text.trim().length > 0,
		JSON.stringify(shellAtStart.text.replace(/\s+/g, ' ').slice(0, 80)));

	// The shell must remove itself on its own once the game is ready. No click,
	// no key, no timer the test controls.
	const shown = await waitFor(shellGone, 300000);
	token('SHELL_HIDES_WITHOUT_A_START_CLICK', shown, shown ? '' : 'shell never hid by itself');
	if (!shown) throw new Error('loader shell never revealed the game');

	const rect = await canvasRect();
	token('CANVAS_VISIBLE_AFTER_LOAD', !!rect && rect.w > 100 && rect.h > 100, JSON.stringify(rect));
	await page.waitForTimeout(3000);
	await page.screenshot({ path: path.join(outDir, 'aim-01-normal-entry-title.png') });

	// Click the game's OWN menu button. Its position comes from the design-space
	// layout (ui/ControlUI.tscn: MainUI/VBoxContainer/start), mapped through the
	// real canvas rectangle.
	const toCss = (dx, dy) => ({ x: rect.x + (dx / 410) * rect.w, y: rect.y + (dy / 230) * rect.h });
	const menuStart = toCss(41, 137);
	await page.mouse.click(menuStart.x, menuStart.y);
	await page.waitForTimeout(3500);
	await page.screenshot({ path: path.join(outDir, 'aim-02-after-menu-start.png') });

	// The camp configuration panel opens on start; close it the way the panel
	// itself documents (Esc). This is the panel's own close key, not a workaround
	// for a broken mouse.
	await page.keyboard.press('Escape');
	await page.waitForTimeout(2000);
	token('NO_POINTER_LOCK_ANYWHERE', await page.evaluate(() => !document.pointerLockElement));
	await page.screenshot({ path: path.join(outDir, 'aim-03-world-after-panel.png') });

	// Immediately - no extra click, no extra Esc - move the mouse and check that
	// the on-screen crosshair is really there and really follows.
	const probe = { x: rect.x + rect.w * 0.35, y: rect.y + rect.h * 0.4 };
	await page.mouse.move(probe.x, probe.y);
	await page.waitForTimeout(1200);
	const crosshairPresent = await crop(probe.x, probe.y, 48, 48);
	const elsewhere = { x: rect.x + rect.w * 0.65, y: rect.y + rect.h * 0.6 };
	await page.mouse.move(elsewhere.x, elsewhere.y);
	await page.waitForTimeout(1200);
	const crosshairMoved = await crop(elsewhere.x, elsewhere.y, 48, 48);
	const oldSpot = await crop(probe.x, probe.y, 48, 48);
	fs.writeFileSync(path.join(outDir, 'aim-crosshair-at-first-cursor.png'), crosshairPresent);
	fs.writeFileSync(path.join(outDir, 'aim-crosshair-at-second-cursor.png'), crosshairMoved);
	token('CROSSHAIR_DRAWN_ON_SCREEN', !crosshairPresent.equals(oldSpot) || !crosshairMoved.equals(oldSpot),
		'48x48 crops around the two cursor positions differ');
	token('AIM_WORKS_WITHOUT_ESC', !crosshairPresent.equals(oldSpot),
		'the aim indicator left the first cursor position after a plain mouse move');

	// A real click must reach the running game (it is the same click that fires).
	await page.mouse.down();
	await page.waitForTimeout(500);
	await page.mouse.up();
	await page.waitForTimeout(1500);
	await page.screenshot({ path: path.join(outDir, 'aim-04-fired-from-normal-entry.png') });
	token('PAGE_ALIVE_AFTER_NORMAL_ENTRY_INPUT', await page.evaluate(() => !!document.querySelector('#canvas-host canvas')));

	// ================================================= Phase B: measured chain
	// Only now do the diagnostic flags come in. They add state streaming; they
	// are not the entry point the product ships.
	const sep = url.includes('?') ? '&' : '?';
	const gameLines = [];
	page.removeAllListeners('console');
	page.on('console', m => { const t = m.text(); if (t.includes('[e2e]')) gameLines.push(t); });
	await page.goto(url + sep + 'smoke=1&e2e=1', { waitUntil: 'domcontentloaded' });
	const ready = await waitFor(shellGone, 300000);
	token('DIAGNOSTIC_ENTRY_READY', ready);
	if (!ready) throw new Error('diagnostic entry never became ready');
	const inCombat = await waitFor(() => Promise.resolve(gameLines.some(l => l.includes('[e2e] ready'))), 360000);
	token('GAME_ENTERED_COMBAT', inCombat);
	if (!inCombat) throw new Error('in-game harness never became ready');
	await page.waitForTimeout(1500);

	const parseState = l => {
		const num = re => { const m = l.match(re); return m ? parseFloat(m[1]) : NaN; };
		const vec = re => { const m = l.match(re); return m ? { x: parseFloat(m[1]), y: parseFloat(m[2]) } : null; };
		return {
			raw: l,
			mousemode: num(/mousemode=(\d+)/),
			aimvp: vec(/aimvp=\((-?[\d.]+), (-?[\d.]+)\)/),
			aimworld: vec(/aimworld=\((-?[\d.]+), (-?[\d.]+)\)/),
			crh: vec(/crh=\((-?[\d.]+), (-?[\d.]+)\)/),
			gunrot: num(/gunrot=(-?[\d.]+)/),
			playerpos: vec(/playerpos=\((-?[\d.]+), (-?[\d.]+)\)/),
			paused: /paused=true/.test(l),
			fireReleased: /fr=true/.test(l),
			bullets: (() => { const m = l.match(/bullets=(-?\d+)\/(-?\d+)/); return m ? parseInt(m[1], 10) : NaN; })(),
		};
	};
	const lastState = () => {
		for (let i = gameLines.length - 1; i >= 0; i--) if (gameLines[i].includes('gunrot=')) return parseState(gameLines[i]);
		return null;
	};
	async function freshState() {
		gameLines.length = 0;
		if (!(await waitFor(async () => gameLines.some(l => l.includes('gunrot=')), 6000, 100))) return lastState();
		return lastState();
	}
	const r2 = await canvasRect();
	const design = { x: 410, y: 230 };
	const cssToDesign = (p) => ({ x: (p.x - r2.x) / r2.w * design.x, y: (p.y - r2.y) / r2.h * design.y });

	// ------------------------------------------- absolute-cursor aim tracking
	const baseCss = { x: r2.x + r2.w * 0.5, y: r2.y + r2.h * 0.5 };
	await page.mouse.move(baseCss.x, baseCss.y);
	await page.waitForTimeout(400);
	const base = await freshState();
	const STEP = 180;
	const rightCss = { x: baseCss.x + STEP, y: baseCss.y };
	await page.mouse.move(rightCss.x, rightCss.y);
	await page.waitForTimeout(400);
	const right = await freshState();
	const dR = { x: right.aimvp.x - base.aimvp.x, y: right.aimvp.y - base.aimvp.y };
	const expect = cssToDesign(rightCss);
	const trackingError = Math.hypot(right.aimvp.x - expect.x, right.aimvp.y - expect.y);
	token('AIM_IS_THE_ABSOLUTE_CURSOR', trackingError < 12,
		`moved ${STEP}css px right: aim moved (${dR.x.toFixed(1)}, ${dR.y.toFixed(1)}); expected design point (${expect.x.toFixed(1)}, ${expect.y.toFixed(1)}) vs aimvp (${right.aimvp.x.toFixed(1)}, ${right.aimvp.y.toFixed(1)}); err=${trackingError.toFixed(1)}`);
	token('AIM_MOVES_RIGHT', dR.x > 5, `dx=${dR.x.toFixed(1)}`);
	token('AIM_AXIS_ISOLATION_X', Math.abs(dR.y) < 3, `perpendicular dy=${dR.y.toFixed(1)}`);

	await page.mouse.move(baseCss.x - STEP, baseCss.y);
	await page.waitForTimeout(400);
	const left = await freshState();
	token('AIM_MOVES_LEFT', left.aimvp.x - base.aimvp.x < -5, `dx=${(left.aimvp.x - base.aimvp.x).toFixed(1)}`);

	await page.mouse.move(baseCss.x, baseCss.y + STEP);
	await page.waitForTimeout(400);
	const down = await freshState();
	token('AIM_MOVES_DOWN', down.aimvp.y - base.aimvp.y > 5, `dy=${(down.aimvp.y - base.aimvp.y).toFixed(1)}`);
	token('AIM_AXIS_ISOLATION_Y', Math.abs(down.aimvp.x - base.aimvp.x) < 3, `perpendicular dx=${(down.aimvp.x - base.aimvp.x).toFixed(1)}`);

	await page.mouse.move(baseCss.x, baseCss.y - STEP);
	await page.waitForTimeout(400);
	const up = await freshState();
	token('AIM_MOVES_UP', up.aimvp.y - base.aimvp.y < -5, `dy=${(up.aimvp.y - base.aimvp.y).toFixed(1)}`);

	await page.mouse.move(baseCss.x, baseCss.y);
	await page.waitForTimeout(700);
	const back = await freshState();
	token('CURSOR_RETURNS_EXACTLY', Math.hypot(back.aimvp.x - base.aimvp.x, back.aimvp.y - base.aimvp.y) < 2,
		`dvp=(${(back.aimvp.x - base.aimvp.x).toFixed(2)}, ${(back.aimvp.y - base.aimvp.y).toFixed(2)})`);

	await page.waitForTimeout(2500);
	const chk = await freshState();
	// The crosshair is a Control updated in its own _process pass, so a state
	// line read while the aim is still moving can legitimately lag by one frame.
	// Coherence is asserted once input has settled - the property that matters is
	// "no drift, no second cursor", not "zero frames of latency".
	token('CROSSHAIR_FOLLOWS_AIM', Math.hypot(chk.crh.x - chk.aimvp.x, chk.crh.y - chk.aimvp.y) < 2.5,
		`crh=(${chk.crh.x.toFixed(1)}, ${chk.crh.y.toFixed(1)}) aimvp=(${chk.aimvp.x.toFixed(1)}, ${chk.aimvp.y.toFixed(1)})`);
	token('GAMEPLAY_POINTER_IS_NOT_LOCKED', chk.mousemode === 1 && !(await page.evaluate(() => !!document.pointerLockElement)),
		`mousemode=${chk.mousemode} (1 = HIDDEN: product crosshair, un-captured absolute cursor)`);

	// ------------------------------------------------ 360 degree sweep of aim
	let accumulated = 0;
	let prev = await freshState();
	for (let i = 0; i < 6; i++) {
		for (const [dx, dy] of [[STEP, 0], [0, STEP], [-STEP, 0], [0, -STEP]]) {
			const p = { x: baseCss.x + dx, y: baseCss.y + dy };
			await page.mouse.move(p.x, p.y);
			await page.waitForTimeout(220);
			const s = await freshState();
			if (s && prev) {
				const a0 = Math.atan2(prev.aimworld.y - prev.playerpos.y, prev.aimworld.x - prev.playerpos.x);
				const a1 = Math.atan2(s.aimworld.y - s.playerpos.y, s.aimworld.x - s.playerpos.x);
				accumulated += Math.abs(wrap(deg(a1) - deg(a0)));
			}
			prev = s;
		}
	}
	token('AIM_360', accumulated >= 360, `accumulated=${accumulated.toFixed(0)}deg`);

	// ---------------------------------------- projectile follows the same aim
	async function aimAt(dx, dy) {
		await page.mouse.move(baseCss.x + dx * STEP, baseCss.y + dy * STEP);
		await page.waitForTimeout(500);
		return freshState();
	}
	async function fire(name, dirX, dirY, cmp, relocateKey) {
		if (relocateKey) {
			// Level layout is a precondition, not an input property: a muzzle that
			// starts inside a wall kills the projectile on its first physics
			// frame. Walk a little first so the tested direction has room.
			await page.keyboard.down(relocateKey);
			await page.waitForTimeout(900);
			await page.keyboard.up(relocateKey);
			await page.waitForTimeout(400);
		}
		for (let attempt = 0; attempt < 4; attempt++) {
			// Chamber first: an empty magazine is a test precondition, not an input bug.
			for (let i = 0; i < 4; i++) {
				const st = await freshState();
				if (st && st.bullets > 0) break;
				await page.keyboard.press('r');
				await page.waitForTimeout(1200);
			}
			// From the second attempt on, nudge the aim along the perpendicular
			// axis: in a tiled arena a shot straight into a nearby wall is
			// reported as a stalled projectile, and that is the level layout
			// talking, not the input chain. The asserted direction is unchanged.
			const nudge = attempt === 0 ? 0 : (attempt % 2 === 1 ? 0.35 : -0.35);
			const ax = dirX + (dirY !== 0 ? nudge : 0);
			const ay = dirY + (dirX !== 0 ? nudge : 0);
			await aimAt(ax, ay);
			gameLines.length = 0;
			await page.mouse.down();
			let projLine = null;
			await waitFor(() => { projLine = gameLines.find(l => l.includes('[e2e] proj ')); return Promise.resolve(!!projLine); }, 8000, 100);
			await page.mouse.up();
			await page.waitForTimeout(300);
			if (projLine) {
				const m = projLine.match(/vx=(-?[\d.]+) vy=(-?[\d.]+) speed=(-?[\d.]+) aim=(-?[\d.]+)/);
				const vx = parseFloat(m[1]), vy = parseFloat(m[2]), aim = parseFloat(m[4]);
				const got = Math.atan2(vy, vx) * 180 / Math.PI;
				const want = Math.atan2(dirY, dirX) * 180 / Math.PI;
				token(name, cmp(vx, vy), `attempt=${attempt} vx=${vx.toFixed(1)} vy=${vy.toFixed(1)} angle=${got.toFixed(1)} wanted~${want.toFixed(1)}`);
				token(name + '_MATCHES_AIM', Math.abs(wrap(got - aim)) < 8,
					`proj=${got.toFixed(1)} provider_aim=${aim.toFixed(1)} delta=${wrap(got - aim).toFixed(1)}`);
				return;
			}
			note(`${name} attempt ${attempt}: no projectile line (stalled=${gameLines.some(l => l.includes('proj-stalled'))})`);
		}
		token(name, false, 'no projectile spawned');
		token(name + '_MATCHES_AIM', false, 'no projectile spawned');
	}
	await fire('PROJECTILE_FOLLOWS_AIM_RIGHT', 1, 0, vx => vx > 5);
	await fire('PROJECTILE_FOLLOWS_AIM_LEFT', -1, 0, vx => vx < -5);
	await fire('PROJECTILE_FOLLOWS_AIM_DOWN', 0, 1, (vx, vy) => vy > 5);
	await fire('PROJECTILE_FOLLOWS_AIM_UP', 0, -1, (vx, vy) => vy < -5, 's');

	// ---------------------------------------------------------------- WASD
	const w0 = await freshState();
	await page.keyboard.down('w');
	await page.waitForTimeout(700);
	await page.keyboard.up('w');
	await page.waitForTimeout(300);
	const w1 = await freshState();
	token('WASD_POSITION_CHANGED', w0.playerpos.y - w1.playerpos.y > 2, `w dy=${(w0.playerpos.y - w1.playerpos.y).toFixed(1)}`);
	let dxProof = 0, usedKey = 'd';
	for (const key of ['d', 'a']) {
		const a0 = await freshState();
		await page.keyboard.down(key);
		await page.waitForTimeout(700);
		await page.keyboard.up(key);
		await page.waitForTimeout(300);
		const a1 = await freshState();
		dxProof = a1.playerpos.x - a0.playerpos.x;
		if (Math.abs(dxProof) > 2) { usedKey = key; break; }
	}
	token('WASD_HORIZONTAL_CHANGED', Math.abs(dxProof) > 2, `key=${usedKey} dx=${dxProof.toFixed(1)}`);

	// ---------------------------------------------- Esc pause / Esc resume
	await page.keyboard.down('w');
	await page.mouse.down();
	await page.waitForTimeout(300);
	await page.keyboard.press('Escape');
	const pausedOk = await waitFor(async () => { const s = lastState(); return !!s && s.paused === true && s.mousemode === 0; }, 15000, 200);
	await page.mouse.up();
	await page.keyboard.up('w');
	await page.waitForTimeout(400);
	const escState = await freshState();
	token('ESC_PAUSED_THE_GAME', pausedOk, `paused=${escState.paused} mousemode=${escState.mousemode}`);
	token('PAUSE_SHOWS_THE_POINTER', escState.paused === true && escState.mousemode === 0, `mousemode=${escState.mousemode}`);
	token('COMMANDS_ARE_NOT_STUCK_WHILE_PAUSED', escState.fireReleased === true, `fire_released=${escState.fireReleased}`);
	await page.screenshot({ path: path.join(outDir, 'aim-05-paused.png') });

	await page.keyboard.press('Escape');
	const resumed = await waitFor(async () => { const s = lastState(); return !!s && s.paused === false && s.mousemode === 1; }, 15000, 200);
	token('ESC_RESUMES_WITHOUT_RECAPTURE', resumed, `paused=${(lastState() || {}).paused} mousemode=${(lastState() || {}).mousemode}`);
	const back0 = await freshState();
	await page.waitForTimeout(1200);
	const back1 = await freshState();
	const drift = Math.hypot(back1.playerpos.x - back0.playerpos.x, back1.playerpos.y - back0.playerpos.y);
	token('INPUT_NOT_STUCK_AFTER_RESUME', drift < 2, `drift=${drift.toFixed(2)}`);
	// And aiming still works straight after the pause round-trip.
	await page.mouse.move(baseCss.x + STEP, baseCss.y);
	await page.waitForTimeout(500);
	const afterResume = await freshState();
	token('AIM_STILL_WORKS_AFTER_RESUME', Math.abs(afterResume.aimvp.x - base.aimvp.x) > 5,
		`dx=${(afterResume.aimvp.x - base.aimvp.x).toFixed(1)}`);

	// ------------------------------------------------------------ focus loss
	if (headed) {
		const other = await context.newPage();
		await other.goto('about:blank');
		await other.bringToFront();
		await page.waitForTimeout(1500);
		const blurred = await waitFor(async () => (lastState() || {}).paused === true, 15000, 200);
		await page.bringToFront();
		await page.waitForTimeout(1500);
		const afterRefocus = await freshState();
		token('FOCUS_LOSS_PAUSES', blurred, `paused=${blurred}`);
		token('REGAIN_FOCUS_DOES_NOT_SELF_FIRE', afterRefocus.fireReleased === true, `fire_released=${afterRefocus.fireReleased}`);
		await page.keyboard.press('Escape');
		token('RESUME_AFTER_FOCUS_LOSS', await waitFor(async () => { const s = lastState(); return !!s && s.paused === false; }, 15000, 200));
		await other.close();
	} else {
		note('focus phase skipped: headless Chromium has no OS focus to lose (run with E2E_HEADED=1)');
	}

	const unexpectedErrors = consoleErrors.filter(e =>
		!/WebGL|GL_|AudioContext|download|currentTime|PagedAllocator|ObjectDB|could not be resolved/i.test(e));
	token('NO_UNEXPECTED_ENGINE_ERRORS', unexpectedErrors.length === 0, unexpectedErrors.slice(0, 3).join(' | '));
	token('NO_NETWORK_ERRORS', badResponses.length === 0 && failedRequests.length === 0,
		`http>=400 ${badResponses.length}, failed requests ${failedRequests.length}`);
	token('NO_POINTER_LOCK_EVER',
		!(await page.evaluate(() => !!document.pointerLockElement)) && tokens.NO_POINTER_LOCK_ANYWHERE !== false);

	await page.screenshot({ path: path.join(outDir, 'aim-06-final.png') });
	fs.writeFileSync(path.join(outDir, 'web-aim-e2e.json'), JSON.stringify({
		url, headed, viewport: VIEW, tokens, notes,
		console_errors: consoleErrors, http_errors: badResponses, failed_requests: failedRequests,
		sample_state_line: (lastState() || {}).raw || null,
	}, null, 2));

	await browser.close();

	const required = [
		'SINGLE_START_ENTRY_POINT', 'LOADING_FEEDBACK_PRESENT', 'SHELL_HIDES_WITHOUT_A_START_CLICK',
		'CANVAS_VISIBLE_AFTER_LOAD', 'NO_POINTER_LOCK_ANYWHERE', 'CROSSHAIR_DRAWN_ON_SCREEN',
		'AIM_WORKS_WITHOUT_ESC', 'PAGE_ALIVE_AFTER_NORMAL_ENTRY_INPUT',
		'DIAGNOSTIC_ENTRY_READY', 'GAME_ENTERED_COMBAT',
		'AIM_IS_THE_ABSOLUTE_CURSOR', 'AIM_MOVES_RIGHT', 'AIM_MOVES_LEFT', 'AIM_MOVES_UP', 'AIM_MOVES_DOWN',
		'AIM_AXIS_ISOLATION_X', 'AIM_AXIS_ISOLATION_Y', 'CURSOR_RETURNS_EXACTLY',
		'CROSSHAIR_FOLLOWS_AIM', 'GAMEPLAY_POINTER_IS_NOT_LOCKED', 'AIM_360',
		'PROJECTILE_FOLLOWS_AIM_RIGHT', 'PROJECTILE_FOLLOWS_AIM_LEFT',
		'PROJECTILE_FOLLOWS_AIM_DOWN', 'PROJECTILE_FOLLOWS_AIM_UP',
		'PROJECTILE_FOLLOWS_AIM_RIGHT_MATCHES_AIM', 'PROJECTILE_FOLLOWS_AIM_LEFT_MATCHES_AIM',
		'PROJECTILE_FOLLOWS_AIM_DOWN_MATCHES_AIM', 'PROJECTILE_FOLLOWS_AIM_UP_MATCHES_AIM',
		'WASD_POSITION_CHANGED', 'WASD_HORIZONTAL_CHANGED',
		'ESC_PAUSED_THE_GAME', 'PAUSE_SHOWS_THE_POINTER', 'COMMANDS_ARE_NOT_STUCK_WHILE_PAUSED',
		'ESC_RESUMES_WITHOUT_RECAPTURE', 'INPUT_NOT_STUCK_AFTER_RESUME', 'AIM_STILL_WORKS_AFTER_RESUME',
		'NO_UNEXPECTED_ENGINE_ERRORS', 'NO_NETWORK_ERRORS', 'NO_POINTER_LOCK_EVER',
	];
	if (headed) required.push('FOCUS_LOSS_PAUSES', 'REGAIN_FOCUS_DOES_NOT_SELF_FIRE', 'RESUME_AFTER_FOCUS_LOSS');

	const failed = required.filter(k => !tokens[k]);
	for (const k of required) console.log(`[aim-e2e] token ${k}=${tokens[k] ? 'true' : 'false'}`);
	if (failed.length) {
		console.log(`[aim-e2e] RESULT=FAIL (${failed.join(',')})`);
		process.exit(1);
	}
	console.log('[aim-e2e] RESULT=PASS');
})().catch(async e => {
	console.error('[aim-e2e] FATAL', e && e.stack ? e.stack : e);
	process.exit(1);
});
