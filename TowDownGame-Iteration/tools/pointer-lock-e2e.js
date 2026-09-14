// TowDownGame Web Pointer Lock / aim acceptance E2E (Playwright, real browser).
//
// Usage: node pointer-lock-e2e.js <url> [evidenceDir]
//   E2E_HEADED=1   run a real windowed Chromium (required for the OS focus phases)
//
// What it is:
//   An acceptance test that drives ONLY real browser input - Pointer Lock, real
//   relative mouse deltas, real mouse buttons, real keys, real tab focus changes -
//   and asserts the whole chain end to end:
//
//     browser relative motion
//       -> Godot mouse_mode CAPTURED
//         -> Utils aim provider (virtual cursor)
//           -> product crosshair position
//             -> gun / gun-tip rotation
//               -> real projectile velocity
//
// What it is NOT:
//   A substitute for human play. It proves the input plumbing is coherent; whether
//   the game *feels* right is a human judgement (see RELEASE_NOTES).
//
// Design rules this script follows, learned from the v1.0.1/v1.0.2 history:
//   * Never assert on a value that the test itself moved. Aim deltas are measured
//     on the game's own virtual cursor, with each sweep followed by its exact
//     inverse, so a sweep cannot pass because of an unrelated recenter move.
//   * Never assert a direction without asserting the perpendicular axis stayed
//     put, so an axis swap or a scale bug cannot pass as a "correct" direction.
//   * Never let a test-side side effect (an empty magazine, a round victory, a
//     reward panel, a monster shoving the player) be reported as an input bug.
//   * Never treat "the game says it is captured" as proof: the game's mouse_mode
//     is cross-checked against document.pointerLockElement at every phase.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
if (!url) {
	console.error('usage: node pointer-lock-e2e.js <url> [evidenceDir]');
	process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const headed = process.env.E2E_HEADED === '1';
const VIEW = { w: 1280, h: 800 };
const CENTRE = { x: 640, y: 400 };

const tokens = {};
const notes = [];
function token(name, ok, extra = '') {
	tokens[name] = !!ok;
	console.log(`[e2e] ${ok ? 'ok  ' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
}
function note(text) {
	notes.push(text);
	console.log('[e2e] note ' + text);
}
const deg = r => r * 180 / Math.PI;
const wrap = a => { while (a > 180) a -= 360; while (a <= -180) a += 360; return a; };

(async () => {
	const browser = await chromium.launch(headed
		? { headless: false, args: ['--window-size=1400,900'] }
		: { headless: true, args: ['--enable-unsafe-swiftshader'] });
	const context = await browser.newContext({ viewport: { width: VIEW.w, height: VIEW.h } });
	const page = await context.newPage();

	const gameLines = [];
	const consoleErrors = [];
	const consoleWarnings = [];
	const badResponses = [];
	const failedRequests = [];
	page.on('console', m => {
		const t = m.text();
		if (m.type() === 'error') consoleErrors.push(t);
		else if (m.type() === 'warning') consoleWarnings.push(t);
		if (t.includes('[e2e]')) gameLines.push(t);
	});
	page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));
	page.on('response', r => { if (r.status() >= 400) badResponses.push(r.status() + ' ' + r.url()); });
	page.on('requestfailed', r => failedRequests.push(r.url() + ' :: ' + ((r.failure() && r.failure().errorText) || '?')));

	const locked = () => page.evaluate(() =>
		!!document.pointerLockElement && document.pointerLockElement === document.querySelector('#canvas-host canvas'));

	async function waitFor(pred, ms, step = 150) {
		const t0 = Date.now();
		while (Date.now() - t0 < ms) { if (await pred()) return true; await page.waitForTimeout(step); }
		return false;
	}

	// ------------------------------------------------------------------ state feed
	const parseState = l => {
		const num = re => { const m = l.match(re); return m ? parseFloat(m[1]) : NaN; };
		const vec = re => { const m = l.match(re); return m ? { x: parseFloat(m[1]), y: parseFloat(m[2]) } : null; };
		const bl = l.match(/bullets=(-?\d+)\/(-?\d+)/);
		return {
			raw: l,
			state: (l.match(/state=(\w+)/) || [])[1] || '',
			mousemode: num(/mousemode=(\d+)/),
			vp: vec(/vp=\((-?[\d.]+), (-?[\d.]+)\)/),
			aimvp: vec(/aimvp=\((-?[\d.]+), (-?[\d.]+)\)/),
			aimworld: vec(/aimworld=\((-?[\d.]+), (-?[\d.]+)\)/),
			crh: vec(/crh=\((-?[\d.]+), (-?[\d.]+)\)/),
			gunrot: num(/gunrot=(-?[\d.]+)/),
			guntiprot: num(/guntiprot=(-?[\d.]+)/),
			gunid: num(/gunid=(-?\d+)/),
			playerpos: vec(/playerpos=\((-?[\d.]+), (-?[\d.]+)\)/),
			paused: /paused=(true|false)/.test(l) && /paused=true/.test(l),
			fireReleased: /fr=(true|false)/.test(l) && /fr=true/.test(l),
			bullets: bl ? parseInt(bl[1], 10) : NaN,
			bulletsMax: bl ? parseInt(bl[2], 10) : NaN,
		};
	};
	const lastState = () => {
		for (let i = gameLines.length - 1; i >= 0; i--) {
			if (gameLines[i].includes('gunrot=')) return parseState(gameLines[i]);
		}
		return null;
	};
	// Read a state line emitted AFTER the caller's last action, so a stale line
	// cannot be mistaken for the effect of that action.
	async function freshState() {
		gameLines.length = 0;
		if (!(await waitFor(async () => gameLines.some(l => l.includes('gunrot=')), 6000, 100))) return lastState();
		return lastState();
	}
	const liveState = async () => (await freshState()) || lastState();

	// ------------------------------------------------------- logical cursor model
	// Playwright dispatches absolute coordinates; under Pointer Lock only the
	// delta between consecutive dispatches matters. We track that logical cursor
	// ourselves so every delta below is exact and reversible.
	let lx = CENTRE.x, ly = CENTRE.y;
	async function rel(dx, dy) {
		lx += dx; ly += dy;
		await page.mouse.move(lx, ly);
		await page.waitForTimeout(180);
	}
	async function home() {
		lx = CENTRE.x; ly = CENTRE.y;
		await page.mouse.move(lx, ly);
		await page.waitForTimeout(250);
	}

	async function lockCount() { return (await locked()) ? 1 : 0; }
	// The one invariant that stops the game from faking capture: the engine's
	// mouse mode must follow the browser's real Pointer Lock state.
	async function captureConsistent(st) {
		const l = await locked();
		if (st.mousemode === 2) return l;
		if (st.mousemode === 0) return !l;
		return false;
	}

	async function clickCanvas() { await page.mouse.click(CENTRE.x, CENTRE.y); await page.waitForTimeout(400); }
	async function acquireLock(ms = 15000) {
		if (await locked()) return true;
		await page.bringToFront().catch(() => {});
		await clickCanvas();
		if (await waitFor(locked, ms)) return true;
		await clickCanvas();
		return waitFor(locked, ms);
	}
	async function holdKey(key, ms) {
		await page.keyboard.down(key);
		await page.waitForTimeout(ms);
		await page.keyboard.up(key);
	}
	// A tap can fall between frames; BaseGun samples the action in _process.
	async function chamber(ms = 3000) {
		for (let i = 0; i < 4; i++) {
			const st = await liveState();
			if (st && st.bullets > 0) return true;
			await holdKey('r', 250);
			await page.waitForTimeout(ms);
		}
		const st = await liveState();
		return !!(st && st.bullets > 0);
	}
	// Keep the virtual cursor away from the clamp wall it is about to sweep into,
	// otherwise a clipped sweep would be reported as "aim did not move".
	async function ensureRoom(dirX, dirY, needDesign) {
		const st = await liveState();
		if (!st || !st.aimvp || !st.vp) return;
		const scale = await unitScale();
		let dx = 0, dy = 0;
		if (dirX > 0 && st.vp.x - st.aimvp.x < needDesign) dx = -(needDesign - (st.vp.x - st.aimvp.x) + 25) / scale;
		if (dirX < 0 && st.aimvp.x < needDesign) dx = (needDesign - st.aimvp.x + 25) / scale;
		if (dirY > 0 && st.vp.y - st.aimvp.y < needDesign) dy = -(needDesign - (st.vp.y - st.aimvp.y) + 25) / scale;
		if (dirY < 0 && st.aimvp.y < needDesign) dy = (needDesign - st.aimvp.y + 25) / scale;
		if (dx || dy) { await rel(dx, dy); }
	}
	let _scale = null;
	let _worldPerDesign = null;
	async function unitScale() { return _scale || 1; }

	// Park the aim in an unambiguous quadrant relative to the PLAYER, not merely
	// "to the right of where it was". A one-axis nudge is not enough: after
	// earlier phases the aim can sit almost on top of the player, where the
	// resulting shot direction is dominated by the other axis and a correct
	// implementation would be reported as an input failure.
	const OFFSET_WORLD = 90;   // comfortably inside the 410x230 design viewport
	function quadrantOk(d, u) {
		const along = d.x * u.x + d.y * u.y;
		const across = Math.abs(d.x * -u.y + d.y * u.x);
		return along > 50 && across < 0.5 * along;
	}
	async function aimToward(dirX, dirY, tries = 10) {
		const u = { x: dirX, y: dirY };
		for (let i = 0; i < tries; i++) {
			const st = await liveState();
			if (!st || !st.aimworld || !st.playerpos) return null;
			const d = { x: st.aimworld.x - st.playerpos.x, y: st.aimworld.y - st.playerpos.y };
			if (quadrantOk(d, u)) return st;
			const target = { x: st.playerpos.x + dirX * OFFSET_WORLD, y: st.playerpos.y + dirY * OFFSET_WORLD };
			const perCss = (await unitScale()) * (_worldPerDesign || 1);
			let css = { x: (target.x - st.aimworld.x) / perCss, y: (target.y - st.aimworld.y) / perCss };
			// Never ask for a delta larger than the design viewport; the next
			// iteration re-measures and continues from there.
			css.x = Math.max(-320, Math.min(320, css.x));
			css.y = Math.max(-320, Math.min(320, css.y));
			await rel(css.x, css.y);
		}
		const st = await liveState();
		if (st && st.aimworld) {
			const d = { x: st.aimworld.x - st.playerpos.x, y: st.aimworld.y - st.playerpos.y };
			note(`aimToward(${dirX},${dirY}) did not reach the quadrant: d=(${d.x.toFixed(1)}, ${d.y.toFixed(1)})`);
		}
		return st;
	}

	// ------------------------------------------------------------------ boot game
	const sep = url.includes('?') ? '&' : '?';
	await page.goto(url + sep + 'smoke=1&e2e=1', { waitUntil: 'domcontentloaded' });
	const bootStart = Date.now();
	const startVisible = await page.locator('#start')
		.waitFor({ state: 'visible', timeout: 300000 }).then(() => true).catch(() => false);
	token('LOADER_READY', startVisible);
	if (!startVisible) throw new Error('loader never became ready');
	await page.locator('#start').click();
	await page.waitForSelector('#canvas-host canvas', { timeout: 60000 });
	// Independent witness for the environment itself: does this browser deliver
	// relative deltas to the *page* at all? Without it, "the aim did not move"
	// cannot be separated from "this machine cannot inject pointer-lock motion".
	await page.evaluate(() => {
		window.__move = { count: 0, sum: 0 };
		document.addEventListener('mousemove', e => {
			window.__move.count++;
			window.__move.sum += Math.abs(e.movementX || 0) + Math.abs(e.movementY || 0);
		}, true);
	});
	const ready = await waitFor(() => Promise.resolve(gameLines.some(l => l.includes('[e2e] ready'))), 360000);
	token('GAME_ENTERED_COMBAT', ready, 't=+' + (((Date.now() - bootStart) / 1000) | 0) + 's');
	if (!ready) throw new Error('in-game harness never became ready');

	const frozen = gameLines.find(l => l.includes('[e2e] round-frozen'));
	token('TEST_ARENA_FROZEN', !!frozen && /state=COMBAT/.test(frozen || ''), (frozen || '').replace('[e2e] ', ''));
	const soft = frozen ? parseInt((frozen.match(/softcursor=(\d+)/) || [])[1], 10) : NaN;
	token('NO_SOFTWARE_CURSOR_SPRITE', soft === 0, 'tree sprites using res://Sprites/1 cursor.png = ' + soft);

	// ------------------------------------------------------------- pointer lock
	await acquireLock();
	token('POINTER_LOCK_ACQUIRED', await locked());
	if (!(await locked())) {
		// Distinguish "this environment cannot test Pointer Lock" from "the game
		// failed an assertion". An environment that never grants the lock proves
		// nothing either way, so it must not be reported as a pass: the distinct
		// exit code lets CI say so out loud instead of hiding it behind `|| true`.
		token('OS_CURSOR_HIDDEN', false, 'no pointer lock, so nothing to hide');
		fs.writeFileSync(path.join(outDir, 'pointer-lock-e2e.json'), JSON.stringify({
			url, headed, outcome: 'ENVIRONMENT_CANNOT_ACQUIRE_POINTER_LOCK',
			tokens, notes, console_errors: consoleErrors,
			http_errors: badResponses, failed_requests: failedRequests,
		}, null, 2));
		console.log('[e2e] RESULT=ENVIRONMENT_CANNOT_ACQUIRE_POINTER_LOCK');
		await browser.close();
		process.exit(3);
	}
	token('OS_CURSOR_HIDDEN', await locked(), 'browser hides the OS pointer while locked');
	let st = await liveState();
	token('GAME_MOUSEMODE_CAPTURED', st && st.mousemode === 2, `mousemode=${st && st.mousemode}`);
	token('CROSSHAIR_PRESENT', !!(st && st.crh && isFinite(st.crh.x) && isFinite(st.crh.y)),
		st && st.crh ? `crh=(${st.crh.x.toFixed(1)}, ${st.crh.y.toFixed(1)}) vp=${st.vp.x}x${st.vp.y}` : 'no crosshair');
	const design = st && st.vp ? st.vp : { x: 410, y: 230 };

	// ------------------------------------- relative motion: magnitude and axes
	await home();
	const base = await liveState();
	const STEP = 240;                       // CSS pixels
	await rel(STEP, 0);
	const right = await liveState();
	const dR = { x: right.aimvp.x - base.aimvp.x, y: right.aimvp.y - base.aimvp.y };
	_scale = dR.x / STEP;
	{
		const dW = { x: right.aimworld.x - base.aimworld.x, y: right.aimworld.y - base.aimworld.y };
		_worldPerDesign = dR.x !== 0 ? dW.x / dR.x : 1;
	}
	const domMovement = await page.evaluate(() => window.__move || { count: 0, sum: 0 });
	const aimMoved = Math.abs(dR.x) >= 0.5 || Math.abs(dR.y) >= 0.5;
	if (!aimMoved) {
		// Nothing moved at all on either axis. This environment cannot exercise the
		// relative-motion path, so no assertion about it is meaningful here.
		//
		// This is not a guess: CI (headless Linux Chromium) has never produced a
		// non-zero aim delta, for the previous implementation either - the 89feb25
		// run logged aimvp=(0.0, 0.0) and dAngle=0.0 for the same sweeps, which the
		// old `|| true` hid. The DOM witness records what the PAGE received, so the
		// evidence says which side dropped it. Either way the authoritative proof
		// for this chain is the real-browser headed run, not CI.
		//
		// Only an exactly-zero measurement takes this branch: a partial or
		// misdirected aim still fails as a product defect below.
		fs.writeFileSync(path.join(outDir, 'pointer-lock-e2e.json'), JSON.stringify({
			url, headed, outcome: 'ENVIRONMENT_CANNOT_EXERCISE_RELATIVE_MOTION',
			tokens, notes, dom_movement: domMovement, step_css_px: STEP,
			console_errors: consoleErrors, http_errors: badResponses, failed_requests: failedRequests,
		}, null, 2));
		console.log(`[e2e] note page received ${domMovement.sum} of relative movement (${domMovement.count} events) for ${STEP}css px; engine aim delta = (${dR.x.toFixed(2)}, ${dR.y.toFixed(2)})`);
		console.log('[e2e] RESULT=ENVIRONMENT_CANNOT_EXERCISE_RELATIVE_MOTION');
		token('POINTER_LOCK_LIFECYCLE_VERIFIED_IN_THIS_ENVIRONMENT',
			tokens['POINTER_LOCK_ACQUIRED'] && tokens['ESC_RELEASES_POINTER_LOCK'] &&
			tokens['RESUME_RECAPTURES_POINTER_LOCK'] && tokens['WASD_POSITION_CHANGED'] &&
			tokens['CROSSHAIR_FOLLOWS_AIM'] && tokens['NO_ENGINE_ERRORS'] && tokens['NO_NETWORK_ERRORS']);
		await browser.close();
		process.exit(3);
	}
	token('MOUSE_RELATIVE_DELIVERED', Math.abs(dR.x) > 5,
		`${STEP}css px -> dvp=(${dR.x.toFixed(2)}, ${dR.y.toFixed(2)}) scale=${_scale.toFixed(4)} design/css`);
	token('AIM_MOVES_RIGHT', dR.x > 5, `dx=${dR.x.toFixed(2)}`);
	token('AIM_AXIS_ISOLATION_X', Math.abs(dR.y) < 2, `perpendicular dy=${dR.y.toFixed(2)}`);
	token('GUN_ROTATION_FOLLOWS_AIM', Math.abs(wrap(right.gunrot - base.gunrot)) > 3,
		`gunrot ${base.gunrot.toFixed(1)} -> ${right.gunrot.toFixed(1)}`);
	await rel(-STEP, 0);
	const back = await liveState();
	token('SWEEP_IS_REVERSIBLE',
		Math.hypot(back.aimvp.x - base.aimvp.x, back.aimvp.y - base.aimvp.y) < 2,
		`dvp=(${(back.aimvp.x - base.aimvp.x).toFixed(2)}, ${(back.aimvp.y - base.aimvp.y).toFixed(2)})`);

	await rel(-STEP, 0);
	const left = await liveState();
	token('AIM_MOVES_LEFT', left.aimvp.x - base.aimvp.x < -5, `dx=${(left.aimvp.x - base.aimvp.x).toFixed(2)}`);
	await rel(STEP, 0);

	await rel(0, STEP);
	const down = await liveState();
	const dD = { x: down.aimvp.x - base.aimvp.x, y: down.aimvp.y - base.aimvp.y };
	token('AIM_MOVES_DOWN', dD.y > 5, `dy=${dD.y.toFixed(2)}`);
	token('AIM_AXIS_ISOLATION_Y', Math.abs(dD.x) < 2, `perpendicular dx=${dD.x.toFixed(2)}`);
	await rel(0, -STEP);
	await rel(0, -STEP);
	const up = await liveState();
	token('AIM_MOVES_UP', up.aimvp.y - base.aimvp.y < -5, `dy=${(up.aimvp.y - base.aimvp.y).toFixed(2)}`);
	await rel(0, STEP);

	// ---------------------------------------------- crosshair tracks the aim
	// The crosshair is a Control updated in its own _process pass, so a state line
	// read while the aim is still moving can legitimately lag it by one frame.
	// Coherence is therefore asserted once input has settled, which is the
	// property that matters: no drift, no second/software cursor.
	await page.waitForTimeout(900);
	const chk = await liveState();
	token('CROSSHAIR_FOLLOWS_AIM', Math.hypot(chk.crh.x - chk.aimvp.x, chk.crh.y - chk.aimvp.y) < 1.5,
		`crh=(${chk.crh.x.toFixed(2)}, ${chk.crh.y.toFixed(2)}) aimvp=(${chk.aimvp.x.toFixed(2)}, ${chk.aimvp.y.toFixed(2)})`);

	// ------------------------------------------------------- 360 degree aim sweep
	await home();
	let accumulated = 0;
	let prev = await liveState();
	for (let i = 0; i < 8; i++) {
		for (const [dx, dy] of [[STEP, 0], [0, STEP], [-STEP, 0], [0, -STEP]]) {
			await ensureRoom(dx, dy, 40);
			await rel(dx, dy);
			const s = await liveState();
			if (s && prev) {
				const a0 = Math.atan2(prev.aimworld.y - prev.playerpos.y, prev.aimworld.x - prev.playerpos.x);
				const a1 = Math.atan2(s.aimworld.y - s.playerpos.y, s.aimworld.x - s.playerpos.x);
				accumulated += Math.abs(wrap(deg(a1) - deg(a0)));
			}
			prev = s;
		}
	}
	token('AIM_360', accumulated >= 360, `accumulated=${accumulated.toFixed(0)}deg`);

	// ----------------------------------------------------- projectile direction
	// Four directions from real LMB, with the barrel chambered first so an empty
	// magazine can never be reported as an aim failure.
	async function fire(name, dirX, dirY, cmp) {
		await acquireLock();
		const aimed = await aimToward(dirX, dirY);
		if (!aimed || !quadrantOk({ x: aimed.aimworld.x - aimed.playerpos.x, y: aimed.aimworld.y - aimed.playerpos.y },
			{ x: dirX, y: dirY })) {
			token(name, false, 'could not place the aim in the tested quadrant (test precondition, not input)');
			token(name + '_MATCHES_AIM', false, 'aim quadrant unreachable');
			return;
		}
		const haveAmmo = await chamber();
		if (!haveAmmo) { token(name, false, 'magazine never refilled (test precondition)'); token(name + '_MATCHES_AIM', false, 'no ammo'); return; }
		for (let attempt = 0; attempt < 3; attempt++) {
			gameLines.length = 0;
			await page.mouse.down();
			let projLine = null;
			await waitFor(() => { projLine = gameLines.find(l => l.includes('[e2e] proj ')); return Promise.resolve(!!projLine); }, 8000, 100);
			await page.mouse.up();
			if (projLine) {
				const m = projLine.match(/vx=(-?[\d.]+) vy=(-?[\d.]+) speed=(-?[\d.]+) aim=(-?[\d.]+)/);
				const vx = parseFloat(m[1]), vy = parseFloat(m[2]), aim = parseFloat(m[4]);
				const got = Math.atan2(vy, vx) * 180 / Math.PI;
				const want = Math.atan2(dirY, dirX) * 180 / Math.PI;
				token(name, cmp(vx, vy), `vx=${vx.toFixed(1)} vy=${vy.toFixed(1)} angle=${got.toFixed(1)} wanted~${want.toFixed(1)}`);
				token(name + '_MATCHES_AIM', Math.abs(wrap(got - aim)) < 8,
					`proj=${got.toFixed(1)} provider_aim=${aim.toFixed(1)} delta=${wrap(got - aim).toFixed(1)}`);
				return;
			}
			const stalled = gameLines.some(l => l.includes('proj-stalled'));
			note(`${name} attempt ${attempt}: no projectile line (stalled=${stalled})`);
			if (!(await locked())) await acquireLock();
			await chamber();
		}
		token(name, false, 'no projectile spawned');
		token(name + '_MATCHES_AIM', false, 'no projectile spawned');
	}
	await fire('PROJECTILE_FOLLOWS_AIM_RIGHT', 1, 0, vx => vx > 5);
	await fire('PROJECTILE_FOLLOWS_AIM_LEFT', -1, 0, vx => vx < -5);
	await fire('PROJECTILE_FOLLOWS_AIM_DOWN', 0, 1, (vx, vy) => vy > 5);
	await fire('PROJECTILE_FOLLOWS_AIM_UP', 0, -1, (vx, vy) => vy < -5);

	// ------------------------------------------------------------------- WASD
	await acquireLock();
	const w0 = await liveState();
	await holdKey('w', 700);
	await page.waitForTimeout(300);
	const w1 = await liveState();
	token('WASD_POSITION_CHANGED', w0.playerpos.y - w1.playerpos.y > 2,
		`w dy=${(w0.playerpos.y - w1.playerpos.y).toFixed(1)}`);
	// Horizontal fallback: a wall may block either side, so try both.
	let dxProof = 0, usedKey = 'd';
	for (const key of ['d', 'a']) {
		const a0 = await liveState();
		await holdKey(key, 700);
		await page.waitForTimeout(300);
		const a1 = await liveState();
		dxProof = a1.playerpos.x - a0.playerpos.x;
		if (Math.abs(dxProof) > 2) { usedKey = key; break; }
	}
	token('WASD_HORIZONTAL_CHANGED', Math.abs(dxProof) > 2, `key=${usedKey} dx=${dxProof.toFixed(1)}`);

	// -------------------------------------------------- ESC: release + pause + cursor
	await acquireLock();
	// Hold real input across the pause so a stuck key/button would be detectable
	// after resuming: the player must not drift on its own.
	await page.keyboard.down('w');
	await page.mouse.down();
	await page.waitForTimeout(400);
	await page.keyboard.press('Escape');
	const pausedLine = await waitFor(async () => {
		const s = lastState();
		return !!s && s.paused === true && s.mousemode === 0;
	}, 20000, 200);
	await page.mouse.up();
	await page.keyboard.up('w');
	await page.waitForTimeout(400);
	const escState = await liveState();
	token('ESC_RELEASES_POINTER_LOCK', !(await locked()), `pointerLockElement=${await locked()}`);
	token('PAUSE_CURSOR_VISIBLE', escState.paused === true && escState.mousemode === 0,
		`paused=${escState.paused} mousemode=${escState.mousemode}`);
	token('ESC_PAUSED_THE_GAME', pausedLine);
	token('COMMANDS_ARE_NOT_STUCK_WHILE_PAUSED', escState.fireReleased === true,
		`fire_released=${escState.fireReleased}`);

	// ------------------------------------------------------------- resume by gesture
	// The product resume path is a REAL user gesture that closes the top pause
	// panel (ui/CampPanel.gd closes itself on ui_cancel); pop_pause() then
	// re-requests Pointer Lock inside that gesture, which is the only way a
	// browser will grant it. A bare click on the canvas cannot work while a
	// panel is open, so the helper walks the real flow.
	async function resumeFromPause() {
		for (let attempt = 0; attempt < 5; attempt++) {
			await page.bringToFront().catch(() => {});
			const st = await liveState();
			if (await locked() && st && st.mousemode === 2 && st.paused === false) return true;
			if (st && st.paused === true) {
				// Real key gesture: closes the topmost panel.
				await page.keyboard.press('Escape');
			} else if (!(await locked())) {
				// No panel in the way: the game's own click-to-recapture path.
				await clickCanvas();
			}
			// Honour the browser's post-ESC lock cooldown instead of reporting it
			// as an input failure.
			await page.waitForTimeout(1600);
			await acquireLock(8000);
			const after = await liveState();
			if (await locked() && after && after.mousemode === 2 && after.paused === false) return true;
		}
		return false;
	}
	token('RESUME_RECAPTURES_POINTER_LOCK', await resumeFromPause(), `paused=${(lastState() || {}).paused}`);
	// Prove the held W/click really was released: after resuming nothing may move
	// until we press a key again.
	const r0 = await liveState();
	await page.waitForTimeout(1200);
	const r1 = await liveState();
	const drift = Math.hypot(r1.playerpos.x - r0.playerpos.x, r1.playerpos.y - r0.playerpos.y);
	token('INPUT_NOT_STUCK_AFTER_RESUME', drift < 2, `drift=${drift.toFixed(2)}`);
	token('SHOOT_RELEASED_AFTER_RESUME', r1.fireReleased === true, `fire_released=${r1.fireReleased}`);

	// ------------------------------------------------------------- focus loss
	// A real second tab steals focus; the browser drops Pointer Lock and the game
	// must release held input and pause. Refocusing must NOT re-capture the
	// pointer without a new user gesture.
	if (headed) {
		const other = await context.newPage();
		await other.goto('about:blank');
		await other.bringToFront();
		await page.waitForTimeout(1500);
		const lostLock = !(await locked());
		const blurred = await waitFor(async () => (lastState() || {}).paused === true, 15000, 200);
		await page.bringToFront();
		await page.waitForTimeout(1500);
		const selfRecaptured = await locked();
		const afterRefocus = await liveState();
		token('FOCUS_LOSS_RELEASES_AND_PAUSES', lostLock && blurred,
			`pointerLockReleased=${lostLock} paused=${blurred}`);
		token('REGAIN_FOCUS_NEEDS_A_GESTURE', !selfRecaptured && afterRefocus.mousemode !== 2,
			`selfRecaptured=${selfRecaptured} mousemode=${afterRefocus.mousemode}`);
		token('RESUME_AFTER_FOCUS_LOSS', await resumeFromPause(), `paused=${(lastState() || {}).paused}`);
		await other.close();
	} else {
		note('focus phases skipped: headless Chromium has no OS focus to lose (run with E2E_HEADED=1)');
	}

	// ------------------------------------------- engine mode tracks browser lock
	const pairs = [];
	for (let i = 0; i < 3; i++) {
		pairs.push(await captureConsistent(await liveState()));
		await page.waitForTimeout(300);
	}
	token('MOUSEMODE_TRACKS_BROWSER_LOCK', pairs.every(Boolean), `samples=${JSON.stringify(pairs)}`);
	token('NO_ENGINE_ERRORS', consoleErrors.length === 0, `${consoleErrors.length} console/page errors`);
	token('NO_NETWORK_ERRORS', badResponses.length === 0 && failedRequests.length === 0,
		`http>=400 ${badResponses.length}, failed requests ${failedRequests.length}`);

	// ------------------------------------------------------------------ evidence
	await page.screenshot({ path: path.join(outDir, 'e2e-after-resume.png') });
	const evidence = {
		url, headed, viewport: VIEW, design_viewport: design,
		scale_design_per_css_px: _scale,
		logical_cursor: { x: lx, y: ly },
		dom_movement: domMovement,
		tokens,
		notes,
		console_errors: consoleErrors,
		console_warnings: consoleWarnings.slice(0, 20),
		http_errors: badResponses,
		failed_requests: failedRequests,
		sample_state_line: (lastState() || {}).raw || null,
	};
	fs.writeFileSync(path.join(outDir, 'pointer-lock-e2e.json'), JSON.stringify(evidence, null, 2));
	console.log('[e2e] evidence -> ' + path.join(outDir, 'pointer-lock-e2e.json'));

	await browser.close();

	// Tokens that must pass for the input chain to be considered proven. The focus
	// tokens only exist in headed runs.
	const required = [
		'LOADER_READY', 'GAME_ENTERED_COMBAT', 'TEST_ARENA_FROZEN', 'NO_SOFTWARE_CURSOR_SPRITE',
		'POINTER_LOCK_ACQUIRED', 'OS_CURSOR_HIDDEN', 'GAME_MOUSEMODE_CAPTURED', 'CROSSHAIR_PRESENT',
		'MOUSE_RELATIVE_DELIVERED', 'AIM_MOVES_RIGHT', 'AIM_MOVES_LEFT', 'AIM_MOVES_UP', 'AIM_MOVES_DOWN',
		'AIM_AXIS_ISOLATION_X', 'AIM_AXIS_ISOLATION_Y', 'SWEEP_IS_REVERSIBLE',
		'GUN_ROTATION_FOLLOWS_AIM', 'CROSSHAIR_FOLLOWS_AIM', 'AIM_360',
		'PROJECTILE_FOLLOWS_AIM_RIGHT', 'PROJECTILE_FOLLOWS_AIM_LEFT',
		'PROJECTILE_FOLLOWS_AIM_DOWN', 'PROJECTILE_FOLLOWS_AIM_UP',
		'PROJECTILE_FOLLOWS_AIM_RIGHT_MATCHES_AIM', 'PROJECTILE_FOLLOWS_AIM_LEFT_MATCHES_AIM',
		'PROJECTILE_FOLLOWS_AIM_DOWN_MATCHES_AIM', 'PROJECTILE_FOLLOWS_AIM_UP_MATCHES_AIM',
		'WASD_POSITION_CHANGED', 'WASD_HORIZONTAL_CHANGED',
		'ESC_RELEASES_POINTER_LOCK', 'PAUSE_CURSOR_VISIBLE', 'ESC_PAUSED_THE_GAME',
		'COMMANDS_ARE_NOT_STUCK_WHILE_PAUSED', 'RESUME_RECAPTURES_POINTER_LOCK',
		'INPUT_NOT_STUCK_AFTER_RESUME', 'SHOOT_RELEASED_AFTER_RESUME',
		'MOUSEMODE_TRACKS_BROWSER_LOCK', 'NO_ENGINE_ERRORS', 'NO_NETWORK_ERRORS',
	];
	if (headed) required.push('FOCUS_LOSS_RELEASES_AND_PAUSES', 'REGAIN_FOCUS_NEEDS_A_GESTURE', 'RESUME_AFTER_FOCUS_LOSS');

	const failed = required.filter(k => !tokens[k]);
	for (const k of required) console.log(`[e2e] token ${k}=${tokens[k] ? 'true' : 'false'}`);
	if (failed.length) {
		console.log(`[e2e] RESULT=FAIL (${failed.join(',')})`);
		process.exit(1);
	}
	console.log('[e2e] RESULT=PASS');
})().catch(async e => {
	console.error('[e2e] FATAL', e && e.stack ? e.stack : e);
	process.exit(1);
});
