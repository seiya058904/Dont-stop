// Don't stop — Web mouse-aim and launch-handshake acceptance E2E (Playwright).
//
// Usage: node web-aim-e2e.js <url> [evidenceDir]
//   E2E_HEADED=1   run a real windowed Chromium (required for the OS focus phase)
//
// Phases, in order:
//   0  calibration  - a diagnostic page load that only MEASURES where the camp
//                     panel's own "返回 [Esc]" button is. It performs no action.
//   A  normal entry - the REAL entry point: no ?smoke / ?e2e / ?tour, and no Esc
//                     at any point before the aim and fire assertions have passed.
//   F  fault inject - ?noready=1 suppresses the game's completion notice; the
//                     start must FAIL rather than quietly pass through the timer.
//   B  measured     - state streaming, to assert cursor -> aim -> crosshair ->
//                     gun -> projectile and the Esc pause/resume semantics.
//
// Why the shell handshake is asserted and not just "the overlay disappeared":
// the shell has a 20 s fallback so a player is never stranded. A broken
// completion notice therefore still looked like a successful start until this
// script started checking the *outcome* (window.__dontStopState.outcome) instead
// of only waiting for the overlay to go away.
//
// Why the crosshair check is not "the screenshot changed": the scene animates by
// itself. The check compares how much each region changed when the cursor moved -
// the pixels at the cursor must change much more than a control region away from
// it - so a random scene flicker cannot pass as "the crosshair follows".

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
const q = (u, extra) => u + (u.includes('?') ? '&' : '?') + extra;

(async () => {
	const browser = await chromium.launch(headed
		? { headless: false, args: ['--window-size=1400,900'] }
		: { headless: true, args: ['--enable-unsafe-swiftshader'] });
	const context = await browser.newContext({ viewport: { width: VIEW.w, height: VIEW.h } });
	const page = await context.newPage();

	const consoleErrors = [];
	const pageErrors = [];
	const badResponses = [];
	const failedRequests = [];
	let engineLog = [];
	// Error listeners stay attached for every phase, including the normal entry.
	page.on('console', m => {
		const t = m.text();
		if (m.type() === 'error') consoleErrors.push(t);
		if (t.includes('[e2e]') || t.includes('[boot]') || t.includes('[smoke]') || t.includes('[loader]')) engineLog.push(t);
	});
	page.on('pageerror', e => pageErrors.push('pageerror: ' + e.message));
	page.on('response', r => { if (r.status() >= 400) badResponses.push(r.status() + ' ' + r.url()); });
	page.on('requestfailed', r => failedRequests.push(r.url() + ' :: ' + ((r.failure() && r.failure().errorText) || '?')));

	const shellGone = () => page.evaluate(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	});
	const shellState = () => page.evaluate(() => window.__dontStopState || null);
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
	async function crop(rect, cx, cy, w, h) {
		return page.screenshot({
			clip: {
				x: Math.max(rect.x, cx - w / 2),
				y: Math.max(rect.y, cy - h / 2),
				width: w, height: h,
			},
		});
	}
	// Real pixel comparison, decoded by the browser itself (no image library):
	// mean absolute per-channel difference, 0 = identical.
	async function meanAbsDiff(bufA, bufB) {
		return page.evaluate(async ([a, b]) => {
			async function pixels(base64) {
				const img = new Image();
				img.src = 'data:image/png;base64,' + base64;
				await img.decode();
				const c = document.createElement('canvas');
				c.width = img.width; c.height = img.height;
				const ctx = c.getContext('2d', { willReadFrequently: true });
				ctx.drawImage(img, 0, 0);
				return ctx.getImageData(0, 0, c.width, c.height).data;
			}
			const da = await pixels(a);
			const db = await pixels(b);
			if (da.length !== db.length) return 255;
			let sum = 0;
			for (let i = 0; i < da.length; i++) sum += Math.abs(da[i] - db[i]);
			return sum / da.length;
		}, [bufA.toString('base64'), bufB.toString('base64')]);
	}

	// =========================================================== Phase 0: locate
	// Diagnostic page load used ONLY to measure the camp panel's close button
	// rectangle. It clicks nothing; the real click happens in Phase A.
	let closeButton = null;
	{
		engineLog = [];
		await page.goto(q(url, 'smoke=1&e2e=1'), { waitUntil: 'domcontentloaded', timeout: 60000 });
		const got = await waitFor(() => Promise.resolve(engineLog.some(l => l.includes('camp-close-button'))), 300000, 250);
		const line = engineLog.find(l => l.includes('camp-close-button'));
		if (got && line) {
			const m = line.match(/text="([^"]*)".*w=([\d.]+) h=([\d.]+) cx=([\d.]+) cy=([\d.]+)/);
			if (m) closeButton = { text: m[1], w: parseFloat(m[2]), h: parseFloat(m[3]), cx: parseFloat(m[4]), cy: parseFloat(m[5]) };
		}
		const st0 = await shellState();
		note(`calibration shell outcome=${st0 && st0.outcome} readyNotice=${st0 && st0.readyNoticeAt ? Math.round(st0.readyNoticeAt) : null}ms`);
		note('calibration close button: ' + JSON.stringify(closeButton));
		token('CALIBRATION_FOUND_CAMP_CLOSE_BUTTON', !!closeButton && /返回/.test(closeButton.text), JSON.stringify(closeButton));
		if (!closeButton || !/返回/.test(closeButton.text)) throw new Error('could not locate the camp panel close button');
	}

	// ======================================================== Phase A: real entry
	// No query flags, no engine cooperation, and NO Escape key anywhere before the
	// aim and fire assertions have passed.
	engineLog = [];
	await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });

	const shellAtStart = await page.evaluate(() => {
		const f = document.getElementById('frame');
		return {
			visible: !!f && getComputedStyle(f).display !== 'none',
			text: f ? f.innerText : '',
			startButtons: document.querySelectorAll('#start, #start-button, .start-button').length,
			domButtons: Array.from(document.querySelectorAll('button')).map(x => (x.innerText || '').trim()),
		};
	});
	token('SINGLE_START_ENTRY_POINT',
		shellAtStart.startButtons === 0 &&
		!/点击开始|立即开始|点击任意|click to start|start game/i.test(shellAtStart.text),
		'shell buttons=' + JSON.stringify(shellAtStart.domButtons));
	token('LOADING_FEEDBACK_PRESENT', shellAtStart.visible && shellAtStart.text.trim().length > 0,
		JSON.stringify(shellAtStart.text.replace(/\s+/g, ' ').slice(0, 80)));

	const shown = await waitFor(shellGone, 300000);
	token('SHELL_HIDES_WITHOUT_A_START_CLICK', shown, shown ? '' : 'shell never hid by itself');
	if (!shown) throw new Error('loader shell never revealed the game');

	// HOW it was revealed is the actual acceptance: the game's completion notice,
	// not the shell's last-resort timer.
	const st = await shellState();
	token('SHELL_READY_VIA_GAME_NOTICE', !!st && st.outcome === 'game-reported-ready',
		`outcome=${st && st.outcome} fallbackUsed=${st && st.fallbackUsed}`);
	token('SHELL_READY_NOT_A_FALLBACK', !!st && st.fallbackUsed === false && st.outcome !== 'timeout-fallback',
		`fallbackUsed=${st && st.fallbackUsed} outcome=${st && st.outcome}`);
	token('SHELL_READY_NOT_AN_ERROR', !!st && st.outcome !== 'engine-error', `errorMessage=${st && st.errorMessage}`);
	if (st && st.readyNoticeAt && st.engineStartedAt) {
		const latency = Math.round(st.readyNoticeAt - st.engineStartedAt);
		token('READY_NOTICE_ARRIVED_BEFORE_FALLBACK', latency > 0 && latency < 20000,
			`notice ${latency}ms after the engine started (fallback fires at 20000ms)`);
	} else {
		token('READY_NOTICE_ARRIVED_BEFORE_FALLBACK', false, 'no notice timing recorded');
	}
	const bootLines = engineLog.filter(l => l.includes('[boot]'));
	note('boot timing: ' + bootLines.map(l => l.replace(/^\[boot\]\s*/, '')).join(' | '));

	const rect = await canvasRect();
	token('CANVAS_VISIBLE_AFTER_LOAD', !!rect && rect.w > 100 && rect.h > 100, JSON.stringify(rect));
	await page.waitForTimeout(3000);
	await page.screenshot({ path: path.join(outDir, 'aim-01-normal-entry-title.png') });

	const toCss = (dx, dy) => ({ x: rect.x + (dx / 410) * rect.w, y: rect.y + (dy / 230) * rect.h });
	const menuStart = toCss(41, 137);
	await page.mouse.click(menuStart.x, menuStart.y);
	await page.waitForTimeout(4000);
	await page.screenshot({ path: path.join(outDir, 'aim-02-after-menu-start.png') });

	// Close the camp panel with a REAL mouse click on its own "返回 [Esc]" button.
	const closeCss = toCss(closeButton.cx, closeButton.cy);
	await page.mouse.move(closeCss.x, closeCss.y);
	await page.waitForTimeout(400);
	await page.mouse.click(closeCss.x, closeCss.y);
	await page.waitForTimeout(2500);
	await page.screenshot({ path: path.join(outDir, 'aim-03-after-mouse-closed-panel.png') });
	token('ESC_NEVER_PRESSED_BEFORE_AIM', !engineLog.some(l => /Escape/i.test(l)),
		'the test sent no Escape key before the aim assertions');

	// The crosshair check: move the cursor and compare how much changed at the
	// cursor versus at a control region far away.
	const posA = { x: rect.x + rect.w * 0.34, y: rect.y + rect.h * 0.40 };
	const posB = { x: rect.x + rect.w * 0.66, y: rect.y + rect.h * 0.60 };
	const control = { x: rect.x + rect.w * 0.18, y: rect.y + rect.h * 0.82 };
	await page.mouse.move(posA.x, posA.y);
	await page.waitForTimeout(1500);
	const aAtA = await crop(rect, posA.x, posA.y, 56, 56);
	const aAtC = await crop(rect, control.x, control.y, 56, 56);
	await page.mouse.move(posB.x, posB.y);
	await page.waitForTimeout(1500);
	const bAtA = await crop(rect, posA.x, posA.y, 56, 56);
	const bAtC = await crop(rect, control.x, control.y, 56, 56);
	await page.mouse.move(posA.x, posA.y);
	await page.waitForTimeout(1500);
	const backAtA = await crop(rect, posA.x, posA.y, 56, 56);
	const backAtC = await crop(rect, control.x, control.y, 56, 56);
	const diffCursor = await meanAbsDiff(aAtA, bAtA);
	const diffControl = await meanAbsDiff(aAtC, bAtC);
	const diffReturn = await meanAbsDiff(bAtA, backAtA);
	const diffControl2 = await meanAbsDiff(bAtC, backAtC);
	fs.writeFileSync(path.join(outDir, 'aim-crosshair-a.png'), aAtA);
	fs.writeFileSync(path.join(outDir, 'aim-crosshair-after-move.png'), bAtA);
	fs.writeFileSync(path.join(outDir, 'aim-crosshair-returned.png'), backAtA);
	// Localisation, measured twice: the pixels around the cursor change more than
	// a control region away from it, both while the cursor leaves and again when
	// it comes back. The bar is a ratio rather than an absolute number on purpose:
	// this is a live animated scene and the exact pixel budget of a rotating
	// sprite is not stable across machines. The precise claim - that the aim
	// indicator sits exactly on the aim point - is asserted from engine state in
	// Phase B (CROSSHAIR_FOLLOWS_AIM), not from pixels.
	token('CROSSHAIR_IS_LOCATED_AT_THE_CURSOR',
		diffCursor > 2 && diffCursor > diffControl * 1.2,
		`pixels at the cursor changed by ${diffCursor.toFixed(1)} vs ${diffControl.toFixed(1)} at a control region away from it`);
	token('CROSSHAIR_STILL_AT_CURSOR_AFTER_RETURN',
		diffReturn > 2 && diffReturn > diffControl2 * 1.2,
		`after moving away and back the cursor region changed by ${diffReturn.toFixed(1)} vs ${diffControl2.toFixed(1)} at the control region`);

	// A real click must reach the running game (it is the same click that fires).
	await page.mouse.down();
	await page.waitForTimeout(500);
	await page.mouse.up();
	await page.waitForTimeout(1500);
	await page.screenshot({ path: path.join(outDir, 'aim-04-fired-from-normal-entry.png') });
	token('PAGE_ALIVE_AFTER_NORMAL_ENTRY_INPUT', await page.evaluate(() => !!document.querySelector('#canvas-host canvas')));
	token('NO_POINTER_LOCK_ANYWHERE', await page.evaluate(() => !document.pointerLockElement));

	// ====================================================== Phase F: fault inject
	// Suppress the game's completion notice on purpose. A start that only happened
	// because the shell gave up waiting must NOT be accepted.
	engineLog = [];
	await page.goto(q(url, 'noready=1'), { waitUntil: 'domcontentloaded', timeout: 60000 });
	const faultShown = await waitFor(shellGone, 120000);
	const faultState = await shellState();
	token('FAULT_INJECTION_SUPPRESSES_NOTICE',
		!!faultState && faultState.readyNoticeSuppressed === true,
		`readyNoticeSuppressed=${faultState && faultState.readyNoticeSuppressed}`);
	token('FAULT_INJECTION_REVEALED_BY_FALLBACK',
		faultShown && !!faultState && faultState.outcome === 'timeout-fallback',
		`outcome=${faultState && faultState.outcome} fallbackUsed=${faultState && faultState.fallbackUsed}`);
	// The point of the injection: the Phase A acceptance condition must be FALSE
	// here, i.e. a missing completion notice fails instead of passing late.
	token('FAULT_INJECTION_FAILS_THE_NORMAL_ASSERTION',
		!!faultState && faultState.outcome !== 'game-reported-ready',
		`outcome=${faultState && faultState.outcome} would not satisfy SHELL_READY_VIA_GAME_NOTICE`);

	// ==================================================== Phase B: measured chain
	const gameLines = [];
	page.removeAllListeners('console');
	page.on('console', m => {
		const t = m.text();
		if (m.type() === 'error') consoleErrors.push(t);
		if (t.includes('[e2e]')) gameLines.push(t);
	});
	await page.goto(q(url, 'smoke=1&e2e=1'), { waitUntil: 'domcontentloaded' });
	const diagReady = await waitFor(shellGone, 300000);
	token('DIAGNOSTIC_ENTRY_READY', diagReady);
	if (!diagReady) throw new Error('diagnostic entry never became ready');
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
	token('CROSSHAIR_FOLLOWS_AIM', Math.hypot(chk.crh.x - chk.aimvp.x, chk.crh.y - chk.aimvp.y) < 2.5,
		`crh=(${chk.crh.x.toFixed(1)}, ${chk.crh.y.toFixed(1)}) aimvp=(${chk.aimvp.x.toFixed(1)}, ${chk.aimvp.y.toFixed(1)})`);
	token('GAMEPLAY_POINTER_IS_NOT_LOCKED', chk.mousemode === 1 && !(await page.evaluate(() => !!document.pointerLockElement)),
		`mousemode=${chk.mousemode} (1 = HIDDEN: product crosshair, un-captured absolute cursor)`);

	let accumulated = 0;
	let prev = await freshState();
	for (let i = 0; i < 6; i++) {
		for (const [dx, dy] of [[STEP, 0], [0, STEP], [-STEP, 0], [0, -STEP]]) {
			await page.mouse.move(baseCss.x + dx, baseCss.y + dy);
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

	async function aimAt(dx, dy) {
		await page.mouse.move(baseCss.x + dx * STEP, baseCss.y + dy * STEP);
		await page.waitForTimeout(500);
		return freshState();
	}
	async function fire(name, dirX, dirY, cmp, relocateKey) {
		if (relocateKey) {
			// Level layout is a precondition, not an input property: a muzzle that
			// starts inside a wall kills the projectile on its first physics frame.
			await page.keyboard.down(relocateKey);
			await page.waitForTimeout(900);
			await page.keyboard.up(relocateKey);
			await page.waitForTimeout(400);
		}
		for (let attempt = 0; attempt < 4; attempt++) {
			for (let i = 0; i < 4; i++) {
				const s = await freshState();
				if (s && s.bullets > 0) break;
				await page.keyboard.press('r');
				await page.waitForTimeout(1200);
			}
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

	// Esc semantics are tested on their own, after the no-Esc phase above.
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
	await page.mouse.move(baseCss.x + STEP, baseCss.y);
	await page.waitForTimeout(500);
	const afterResume = await freshState();
	token('AIM_STILL_WORKS_AFTER_RESUME', Math.abs(afterResume.aimvp.x - base.aimvp.x) > 5,
		`dx=${(afterResume.aimvp.x - base.aimvp.x).toFixed(1)}`);

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
		!/WebGL|GL_|AudioContext|download|currentTime|PagedAllocator|ObjectDB|could not be resolved|still in use at exit/i.test(e));
	token('NO_UNEXPECTED_ENGINE_ERRORS', unexpectedErrors.length === 0, unexpectedErrors.slice(0, 3).join(' | '));
	token('NO_PAGE_ERRORS', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));
	token('NO_NETWORK_ERRORS', badResponses.length === 0 && failedRequests.length === 0,
		`http>=400 ${badResponses.length}, failed requests ${failedRequests.length}`);
	token('NO_POINTER_LOCK_EVER', !(await page.evaluate(() => !!document.pointerLockElement)));

	await page.screenshot({ path: path.join(outDir, 'aim-06-final.png') });
	fs.writeFileSync(path.join(outDir, 'web-aim-e2e.json'), JSON.stringify({
		url, headed, viewport: VIEW, tokens, notes, camp_close_button: closeButton,
		crosshair_pixel_diff: { cursor: diffCursor, control: diffControl, returned: diffReturn },
		boot_timing_lines: bootLines,
		console_errors: consoleErrors, page_errors: pageErrors,
		http_errors: badResponses, failed_requests: failedRequests,
		sample_state_line: (lastState() || {}).raw || null,
	}, null, 2));

	await browser.close();

	const required = [
		'CALIBRATION_FOUND_CAMP_CLOSE_BUTTON',
		'SINGLE_START_ENTRY_POINT', 'LOADING_FEEDBACK_PRESENT', 'SHELL_HIDES_WITHOUT_A_START_CLICK',
		'SHELL_READY_VIA_GAME_NOTICE', 'SHELL_READY_NOT_A_FALLBACK', 'SHELL_READY_NOT_AN_ERROR',
		'READY_NOTICE_ARRIVED_BEFORE_FALLBACK',
		'CANVAS_VISIBLE_AFTER_LOAD', 'ESC_NEVER_PRESSED_BEFORE_AIM', 'NO_POINTER_LOCK_ANYWHERE',
		'CROSSHAIR_IS_LOCATED_AT_THE_CURSOR', 'CROSSHAIR_STILL_AT_CURSOR_AFTER_RETURN',
		'PAGE_ALIVE_AFTER_NORMAL_ENTRY_INPUT',
		'FAULT_INJECTION_SUPPRESSES_NOTICE', 'FAULT_INJECTION_REVEALED_BY_FALLBACK',
		'FAULT_INJECTION_FAILS_THE_NORMAL_ASSERTION',
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
		'NO_UNEXPECTED_ENGINE_ERRORS', 'NO_PAGE_ERRORS', 'NO_NETWORK_ERRORS', 'NO_POINTER_LOCK_EVER',
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
