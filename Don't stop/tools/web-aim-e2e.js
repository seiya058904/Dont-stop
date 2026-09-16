// Don't Stop — Web mouse-aim and launch-handshake acceptance E2E (Playwright).
//
// Usage: node web-aim-e2e.js <url> [evidenceDir]
//   E2E_HEADED=1        run a real windowed Chromium (required for the OS focus phase)
//   E2E_WATCHDOG_MS=N   whole-run watchdog (default 10 min)
//
// Phases, in order:
//   A  real entry   - the ordinary index.html entry point with ONLY the read-only
//                     observation channel armed (?probe=1: no --smoke driver, no
//                     --e2e harness, no level skip, no state forcing). It asserts
//                     the launch handshake and then the whole aim / crosshair /
//                     360 / WASD / Esc chain on the session a player gets. No Esc
//                     is sent at any point before the aim assertions have passed.
//   F  fault inject - ?noready=1 suppresses the game's completion notice; the
//                     start must FAIL rather than quietly pass through a timer.
//   B  fire chain   - ?smoke=1&e2e=1&probe=1. Firing needs a weapon and a live
//                     combat round, which only the harness can put on the table
//                     (a fresh camp has no equipped weapon and depart() refuses);
//                     the harness is the same one the previous version used, and
//                     the evidence is now read from state instead of pixels.
//
// ---------------------------------------------------------------------------
// WHY THIS IS NO LONGER DRIVEN BY PIXELS
// ---------------------------------------------------------------------------
// Measured on run 35052512912 (real GitHub runner, job "Gate aim-e2e", 9 m 48 s):
// the Web export uses the nothreads template, so the game loop owns the browser
// main thread and every page.screenshot() has to wait for a slot on it. The
// screenshots in phase A cost ~7.5 s each on that runner, and the phase was
// screenshots nearly all the way down:
//
//   calibration load (a whole extra engine boot, only to locate one button)  68 s
//   phase A (3 full captures + 12 crops + 6 pixel-diff evaluates)           230 s
//   phase F                                                                  85 s
//   phase B (harness entry + aim sweep + fire + pause)                       167 s
//
// Two of those were not just slow, they were not evidence:
//   * the fire probe compared the magazine region before/after a click, and the
//     region sits over a scrolling world - the recorded numbers were
//     blocked 15.28 vs idle 6.36 vs shot 20.15, i.e. one noise source larger than
//     the effect it was supposed to detect. It passed by 2.87 units.
//   * "the crosshair is at the cursor" was a ratio of pixel churn between two
//     regions, which cannot distinguish the crosshair from the scene animating.
//
// So both are now read from the game's own read-only state channel
// (autoload/Smoke.gd --probe): bullets in the magazine, the projectile-generation
// counter, the flight vector of the projectile the engine actually created, and
// the crosshair/aim positions - at no page round-trip cost, because the channel
// arrives on the CDP console stream. The pixel captures that remain are the four
// the visual contract genuinely needs (menu, visible crosshair, the stalled
// cover, and a real shot) and nothing else; none of them is a pass/fail input.
//
// The calibration load is gone entirely: the probe reports the rectangle of the
// panel's own controls from the LIVE panel, which is the same locator with one
// fewer engine boot and no chance of measuring a dormant copy of the UI.
//
// Nothing in this file calls _shoot(), writes bullets_count, sets the aim, spawns
// a projectile, skips a real UI step, or changes the pause state to manufacture a
// pass. Every input is a real mouse or keyboard event.

const fs = require('fs');
const os = require('os');
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
// 10 min: the three phases are seconds each now. If this ever needs longer,
// something is wrong and the job has to say so instead of hanging until the
// workflow's own timeout.
const WATCHDOG_MS = parseInt(process.env.E2E_WATCHDOG_MS || String(10 * 60 * 1000), 10);
const VIEW = { w: 1366, h: 768 };
// Design space of the game's ControlUI. Every rectangle the probe reports and
// every point this script clicks is in these units.
const DESIGN = { w: 410, h: 230 };
// The title menu's own start button (MainUI/VBoxContainer/start: P(8,127) S(66,18),
// as the game itself prints it in "[leave] input ... start=[P: (8.0, 127.0) ...]").
const MENU_START = { x: 41, y: 136 };
// One design-space step of mouse travel, expressed in CSS pixels. The same
// geometry the previous version used, so the assertions keep their sensitivity.
const STEP_CSS = 180;

const tokens = {};
const notes = [];
const failedTokens = [];
const timings = [];
// Read-only measurements kept for the evidence file (aim error, aim sweep, the
// fire readings, the machine's frame rate).
const marks = {};
const RUN_T0 = Date.now();

function token(name, ok, extra = '') {
	tokens[name] = !!ok;
	if (!ok) failedTokens.push(name);
	console.log(`[aim-e2e] ${ok ? 'ok  ' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
}
function note(text) { notes.push(text); console.log('[aim-e2e] note ' + text); }
let lastTiming = Date.now();
function timing(name) {
	const now = Date.now();
	timings.push({ name, ms: now - lastTiming });
	console.log(`[aim-e2e] timing ${name.padEnd(30)} ${now - lastTiming}ms`);
	lastTiming = now;
}
const deg = r => r * 180 / Math.PI;
const wrap = a => { while (a > 180) a -= 360; while (a <= -180) a += 360; return a; };
const q = (u, extra) => u + (u.includes('?') ? '&' : '?') + extra;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ms = n => `${Math.round(n)}ms`;

let watchdogFired = false;
let currentPhase = 'startup';
const watchdog = setTimeout(() => {
	watchdogFired = true;
	console.log(`[aim-e2e] FAIL WATCHDOG_FIRED after ${ms(WATCHDOG_MS)} during phase "${currentPhase}"`);
	console.log(`[aim-e2e] timings so far: ${timings.map(t => t.name + '=' + t.ms + 'ms').join(' ')}`);
	process.exit(1);
}, WATCHDOG_MS);
watchdog.unref?.();

(async () => {
	// One persistent profile for the whole run, in a directory this run created
	// and owns. Phase A is therefore a genuine FIRST launch (the previous version
	// had to spend a whole extra engine boot seeding a weapon into it), and the
	// harness load later persists what it grants.
	const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dontstop-aim-e2e-'));
	const context = await chromium.launchPersistentContext(profileDir, {
		headless: !headed,
		viewport: { width: VIEW.w, height: VIEW.h },
		// The page runs the real game continuously, so the renderer must not be
		// throttled or backgrounded mid-phase, and /dev/shm on a CI container is
		// far too small for a Chromium renderer holding a 40 MB Godot payload.
		args: headed ? ['--window-size=1400,900'] : [
			'--enable-unsafe-swiftshader',
			'--disable-dev-shm-usage',
			'--disable-background-timer-throttling',
			'--disable-renderer-backgrounding',
			'--disable-backgrounding-occluded-windows',
		],
	});
	const page = context.pages()[0] || await context.newPage();

	// A dead renderer used to surface as an opaque "Target page ... has been
	// closed" from whatever wait was in flight, which says nothing about where it
	// died. Record it where it happens instead.
	let rendererCrash = null;
	page.on('crash', () => { rendererCrash = new Date().toISOString(); console.log('[aim-e2e] note renderer crashed at ' + rendererCrash); });

	// Error listeners stay attached for every phase, including the real entry, and
	// are never re-armed: a page-level error in ANY load has to fail the gate.
	const consoleErrors = [];
	const pageErrors = [];
	const badResponses = [];
	const failedRequests = [];
	// Requests the browser ITSELF cancelled because the page navigated away. This
	// gate navigates three times, and index.wasm can still be streaming when the
	// next load starts: Chromium reports that as net::ERR_ABORTED. It carries no
	// HTTP status, the same file loads fine on the next navigation, and it is the
	// TEST's own navigation that causes it, so it is recorded here rather than
	// counted as a network failure. Anything else - every real error, and every
	// http>=400 - still fails NO_NETWORK_ERRORS.
	const navigationAborts = [];
	// The read-only probe stream: 4 lines/s, plus one-shot rect and shot events.
	const probeLines = [];
	const projShots = [];
	const rects = {};
	let probeSaveState = null;
	// Everything the game prints that is not the probe channel.
	const gameLines = [];
	page.on('console', m => {
		const t = m.text();
		if (m.type() === 'error') consoleErrors.push(t);
		if (t.startsWith('[probe] rect ')) {
			const g = t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+)/);
			if (g) rects[g[1]] = { id: +g[2], text: g[3], x: +g[4], y: +g[5], w: +g[6], h: +g[7], cx: +g[8], cy: +g[9] };
			return;
		}
		if (t.startsWith('[probe] proj-shot ')) {
			const g = t.match(/n=(-?\d+) vx=(-?[\d.]+) vy=(-?[\d.]+) speed=(-?[\d.]+) aim=(-?[\d.]+)/);
			if (g) projShots.push({ n: +g[1], vx: +g[2], vy: +g[3], speed: +g[4], aim: +g[5] });
			return;
		}
		if (t.startsWith('[probe] ')) {
			if (t.startsWith('[probe] save_state')) { probeSaveState = t.replace('[probe] save_state', '').trim(); return; }
			if (!/frames=\d+/.test(t)) return;
			probeLines.push(t);
			if (probeLines.length > 20000) probeLines.splice(0, 10000);
			return;
		}
		gameLines.push(t);
		if (gameLines.length > 8000) gameLines.splice(0, 4000);
	});
	page.on('pageerror', e => pageErrors.push('pageerror: ' + e.message));
	page.on('response', r => { if (r.status() >= 400) badResponses.push(r.status() + ' ' + r.url()); });
	page.on('requestfailed', r => {
		const why = (r.failure() && r.failure().errorText) || '?';
		const rec = r.url() + ' :: ' + why;
		if (why === 'net::ERR_ABORTED') navigationAborts.push(rec);
		else failedRequests.push(rec);
	});

	// ---------------------------------------------------------------- observation
	const num = (l, re) => { const m = l.match(re); return m ? parseFloat(m[1]) : NaN; };
	const vec = (l, re) => { const m = l.match(re); return m ? { x: parseFloat(m[1]), y: parseFloat(m[2]) } : null; };
	function parseProbe(l) {
		return {
			raw: l,
			sess: num(l, /sess=(-?\d+)/),
			frames: num(l, /frames=(-?\d+)/),
			proj: num(l, /proj=(-?\d+)/),
			start: /start=true/.test(l),
			sm: (l.match(/sm=(\S+)/) || [])[1] || null,
			pause: /pause=true/.test(l),
			panels: num(l, /panels=(-?\d+)/),
			ingame: /ingame=true/.test(l),
			gun: num(l, /gun=(-?\d+)/),
			bullets: num(l, /bullets=(-?\d+)\//),
			bulletsMax: num(l, /bullets=-?\d+\/(-?\d+)/),
			mm: num(l, /mm=(-?\d+)/),
			player: vec(l, /player=\((-?[\d.]+), (-?[\d.]+)\)/),
			aimvp: vec(l, /aimvp=\((-?[\d.]+), (-?[\d.]+)\)/),
			crh: vec(l, /crh=\((-?[\d.]+), (-?[\d.]+)\)/),
			hp: num(l, /hp=(-?[\d.]+)/),
			aimworld: vec(l, /aimworld=\((-?[\d.]+), (-?[\d.]+)\)/),
			projv: vec(l, /projv=\((-?[\d.]+), (-?[\d.]+)\)/),
			projang: num(l, /projang=(-?[\d.]+)/),
			projshots: num(l, /projshots=(-?\d+)/),
			fr: /fr=true/.test(l),
			fps: num(l, /fps=(-?\d+)/),
		};
	}
	const stateNow = () => (probeLines.length ? parseProbe(probeLines[probeLines.length - 1]) : null);
	// Waiting costs no page round trip: the probe arrives on the CDP console
	// channel, so this only polls an array that is already being filled.
	async function waitState(pred, budgetMs, label) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const s = stateNow();
			if (s && pred(s)) return { ok: true, ms: Date.now() - t, state: s };
			await sleep(40);
		}
		return { ok: false, ms: Date.now() - t, state: stateNow(), label };
	}
	// Waits for the probe to have reported again, so a reading taken afterwards
	// cannot be a line printed BEFORE the input it is supposed to describe. The
	// frame counter is deliberately not used for this: it must stay frozen while a
	// panel holds the tree paused, which is exactly when the fire negative control
	// needs a fresh reading.
	async function waitNewProbe(count = 1, budgetMs = 8000) {
		const mark = probeLines.length;
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			if (probeLines.length >= mark + count) return stateNow();
			await sleep(50);
		}
		return stateNow();
	}
	async function waitIn(arr, pred, budgetMs, label) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const hit = arr.find(pred);
			if (hit) return { ok: true, hit, ms: Date.now() - t };
			await sleep(40);
		}
		return { ok: false, ms: Date.now() - t, label };
	}
	// The probe reports a control's rectangle only once the product has put it on
	// screen and laid it out (its width must exceed the 10 px it carries before the
	// container pass), so the presence of rects[tag] is the readiness signal. It
	// deliberately does not demand a NEW instance id: Godot recycles instance ids
	// and reuses a panel node across a hide/show, so an id-based wait times out
	// even though the panel is on screen and clickable.
	async function waitRect(tag, budgetMs) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const r = rects[tag];
			if (r) return { ok: true, rect: r, ms: Date.now() - t };
			await sleep(40);
		}
		return { ok: false, rect: rects[tag] || null, ms: Date.now() - t };
	}
	// A panel pushes itself onto the pause stack from _enter_tree, which runs
	// before it is laid out, and a key or click that arrives inside that window is
	// dropped. Measured on this build: an Esc sent ~60 ms after the open never
	// closed the panel (8001 ms timeout), while the same Esc sent once the panel
	// had settled closed it in under 300 ms. Anchored to the product's own state -
	// the stack has to stay non-empty for a whole second - not to a wall-clock
	// guess, and it returns false if the panel disappears instead, so a flicker
	// cannot satisfy it.
	async function settlePaused(budgetMs = 5000, minMs = 1000) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const s = stateNow();
			if (!s || s.panels < 1) return false;
			if (Date.now() - t >= minMs) return true;
			await sleep(120);
		}
		return false;
	}
	async function waitGameLine(re, from, budgetMs) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const hit = gameLines.slice(from).find(l => re.test(l));
			if (hit) return { ok: true, ms: Date.now() - t, line: hit };
			await sleep(40);
		}
		return { ok: false, ms: Date.now() - t };
	}
	// The shell hides itself ONLY on the game's own completion notice. The
	// predicate runs inside the page (waitForFunction), so polling one DOM flag
	// does not become a page round trip per poll - which mattered: the naive
	// version of this wait was 150 ms x evaluate and the nothreads export makes
	// each evaluate queue behind the game loop.
	// `undefined` is the page-function argument slot, not an omission: passing the
	// options object there would drop the 240 s budget and silently impose
	// Playwright's 30 s default, which a real load (about 60 s on CI) exceeds.
	const shellGone = () => page.waitForFunction(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	}, undefined, { timeout: 240000 }).then(() => true).catch(() => false);
	const shellState = () => page.evaluate(() => window.__dontStopState || null);
	const pointerLocked = () => page.evaluate(() => !!document.pointerLockElement);
	async function canvasRect() {
		return page.evaluate(() => {
			const c = document.querySelector('#canvas-host canvas');
			if (!c) return null;
			const r = c.getBoundingClientRect();
			return { x: r.x, y: r.y, w: r.width, h: r.height };
		});
	}
	// Every key the DRIVER sends, so "no Escape before the aim assertions" is
	// proven from the driver's own record instead of inferred from a log.
	const keysSent = [];
	const press = async k => { keysSent.push(k); await page.keyboard.press(k); };
	const keyDown = async k => { keysSent.push(k); await page.keyboard.down(k); };
	const keyUp = async k => { await page.keyboard.up(k); };

	let rect = null;
	const toCss = (dx, dy) => ({ x: rect.x + (dx / DESIGN.w) * rect.w, y: rect.y + (dy / DESIGN.h) * rect.h });
	const cssToDesign = p => ({ x: (p.x - rect.x) / rect.w * DESIGN.w, y: (p.y - rect.y) / rect.h * DESIGN.h });
	const clickDesign = async (dx, dy) => {
		const c = toCss(dx, dy);
		await page.mouse.move(c.x, c.y); await sleep(110);
		await page.mouse.down(); await sleep(120); await page.mouse.up();
	};
	const clickTag = async tag => {
		const r = rects[tag];
		if (!r) return { ok: false, why: `${tag} was never reported` };
		await clickDesign(r.cx, r.cy);
		return { ok: true, rect: r };
	};
	// A real cursor move, followed by a wait for the OBSERVATION and not for the
	// answer. Two fresh probe readings are required: the first may have been
	// produced from a cursor position sampled just before the move reached the
	// browser, the second cannot be. Where the aim actually ended up is what the
	// assertions below measure - so a wrong aim is measured, never waited away -
	// and the wait itself is wall-clock free, which matters because CI runs this
	// loop below 1 fps where a fixed sleep would measure the machine.
	async function aimAfterMove(cssX, cssY, budgetMs = 15000) {
		await page.mouse.move(cssX, cssY);
		await waitNewProbe(1, 6000);
		const s = await waitNewProbe(1, budgetMs);
		return s;
	}

	// ================================================== Phase A: the real entry
	// The ordinary entry point with only the read-only channel armed. No ?smoke,
	// no ?e2e, no ?tour: nothing that drives the game, grants anything or skips a
	// step. NO Escape key is sent anywhere before the aim assertions have passed.
	currentPhase = 'A:entry';
	await page.goto(q(url, 'probe=1'), { waitUntil: 'domcontentloaded', timeout: 90000 });

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

	const shown = await shellGone();
	token('SHELL_HIDES_WITHOUT_A_START_CLICK', shown, shown ? '' : 'shell never hid by itself');
	if (!shown) throw new Error('loader shell never revealed the game');
	timing('A-shell-revealed');

	// HOW it was revealed is the actual acceptance. There is no timer that can
	// reveal the game at all: the shell's only reveal path is the game's own
	// completion notice, and `revealedBy` records which one it was.
	const st = await shellState();
	token('SHELL_READY_VIA_GAME_NOTICE',
		!!st && st.outcome === 'game-reported-ready' && st.revealedBy === 'game-reported-ready',
		`outcome=${st && st.outcome} revealedBy=${st && st.revealedBy}`);
	token('SHELL_NEVER_REVEALS_ON_A_TIMER', !!st && st.revealedBy === 'game-reported-ready',
		'the shell has no fallback reveal path left, so this can only be the notice');
	token('SHELL_READY_NOT_AN_ERROR', !!st && st.outcome !== 'engine-error', `errorMessage=${st && st.errorMessage}`);
	const stageNames = st && st.stages ? Object.keys(st.stages) : [];
	note('shell stages: ' + JSON.stringify(st && st.stages));
	token('SHELL_TRACKS_LAUNCH_STAGES',
		['download', 'engine-init', 'scene-prep', 'menu'].every(s => stageNames.includes(s)),
		`stages=${stageNames.join(',')}`);
	note(`stall warnings during this healthy start: ${st && st.stallWarnings} ` +
		'(a warning keeps the cover up and is not a reveal, so it is reported rather than asserted)');
	if (st && st.downloadStartedAt && st.engineStartedAt) {
		note(`download + engine bring-up took ${Math.round(st.engineStartedAt - st.downloadStartedAt)}ms`);
	}
	// Deterministic cover for the defect being replaced. The old shell revealed the
	// game when a fixed deadline expired; the deployed site was measured reporting
	// a perfectly healthy notice 20923 ms after that deadline was armed, so the
	// timer - not the game - decided what the player saw.
	const oldTimerPredicate = (armedAt, noticeAt, windowMs) => (noticeAt - armedAt) >= windowMs;
	token('OLD_FIXED_DEADLINE_WOULD_HAVE_MISLABELLED_IT', oldTimerPredicate(0, 20923, 20000),
		'the measured 20923 ms notice was past the old 20 s deadline, which is why a timer may not decide');
	token('ACCEPTANCE_IGNORES_ELAPSED_TIME', !!st && st.outcome === 'game-reported-ready',
		'only the game notice counts, however long the load legitimately took');
	const bootLines = gameLines.filter(l => l.includes('[boot]'));
	note('boot timing: ' + bootLines.map(l => l.replace(/^\[boot\]\s*/, '')).join(' | '));

	rect = await canvasRect();
	token('CANVAS_VISIBLE_AFTER_LOAD', !!rect && rect.w > 100 && rect.h > 100, JSON.stringify(rect));

	// The read-only channel is what every measurement below reads, so prove it is
	// actually flowing before anything is asserted from it.
	const first = await waitState(() => true, 10000, 'first');
	token('PROBE_STATE_IS_FLOWING', !!first.state, first.state ? first.state.raw : 'no probe line arrived');
	if (!first.state) throw new Error('the read-only channel never reported');
	note(`first probe line: ${first.state.raw}`);
	note(`the machine under test reports fps=${first.state.fps} (a rate is reported, never asserted: the product is not a frame-rate test)`);
	marks.fps = first.state.fps;
	// At the title menu there is no round and no equipped weapon. Taken from the
	// product's own state instead of from a screenshot.
	token('REAL_ENTRY_REACHES_THE_MENU',
		!first.state.start && first.state.gun === -1 && first.state.sm !== 'COMBAT',
		`start=${first.state.start} gun=${first.state.gun} sm=${first.state.sm}`);
	await page.screenshot({ path: path.join(outDir, 'aim-01-entry-title.png') });
	timing('A-title-load');
	// --- start a round through the product's own menu button
	const fromStart = gameLines.length;
	await clickDesign(MENU_START.x, MENU_START.y);
	const pressed = await waitGameLine(/menu start button pressed/, fromStart, 15000);
	const started = await waitState(s => s.start, 25000, 'round');
	const panel = await waitState(s => s.panels >= 1, 25000, 'panel');
	const settled = await settlePaused();
	const laidOut = await waitRect('camp-close-button', 12000);
	token('START_CLICK_REACHED_THE_MENU', pressed.ok, pressed.ok ? pressed.line.replace(/^\[leave\]\s*/, '') : 'no press reached MainUI');
	token('START_OPENS_A_ROUND', started.ok, `start=${started.state && started.state.start} after ${ms(started.ms)}`);
	// The locator the deleted calibration load used to provide: the same control,
	// reported by the panel that is actually on screen, in the same load.
	token('CAMP_CLOSE_BUTTON_REPORTED_BY_THE_LIVE_PANEL', laidOut.ok,
		laidOut.rect ? `text="${laidOut.rect.text}" centre=(${laidOut.rect.cx}, ${laidOut.rect.cy}) after ${ms(laidOut.ms)}` : 'no rectangle was reported');
	token('CAMP_PANEL_IS_ON_SCREEN', panel.ok && settled && laidOut.ok,
		`panels=${panel.state && panel.state.panels}, pause stack settled=${settled}`);
	timing('A-round-started');

	// --- a REAL click on the panel's own 返回 [Esc] button closes it
	const closed = await clickTag('camp-close-button');
	const gonePanel = await waitState(s => !s.pause && s.panels === 0, 20000, 'closed');
	token('REAL_CLICK_CLOSED_THE_PANEL', closed.ok && gonePanel.ok,
		`panels=${gonePanel.state && gonePanel.state.panels} after ${ms(gonePanel.ms)}`);
	timing('A-panel-closed');

	// The session is live: the probe's frame counter is pause-aware, so "it moved
	// at all while unpaused" is the whole claim. A RATE is never asserted - CI
	// runs this same loop at ~0.8 fps where a developer machine vsyncs at 60.
	const aimPhaseStart = probeLines.length;
	const liveFrom = stateNow();
	const live = await waitState(s => s.frames > liveFrom.frames + 2, 20000, 'live');
	token('SESSION_IS_RUNNING', live.ok,
		`idle frames advanced ${(live.state || stateNow()).frames - liveFrom.frames} while unpaused`);

	// ============================================================ Phase A: the aim
	const baseCss = { x: rect.x + rect.w * 0.5, y: rect.y + rect.h * 0.5 };
	const base = await aimAfterMove(baseCss.x, baseCss.y);

	// The absolute mapping: 180 CSS px right must land where the cursor is, in the
	// game's own design space - not merely "somewhere further right".
	const rightCss = { x: baseCss.x + STEP_CSS, y: baseCss.y };
	const expectRight = cssToDesign(rightCss);
	const right = await aimAfterMove(rightCss.x, rightCss.y);
	const dR = { x: right.aimvp.x - base.aimvp.x, y: right.aimvp.y - base.aimvp.y };
	const trackingError = Math.hypot(right.aimvp.x - expectRight.x, right.aimvp.y - expectRight.y);
	token('AIM_IS_THE_ABSOLUTE_CURSOR', trackingError < 12,
		`moved ${STEP_CSS}css px right: aim moved (${dR.x.toFixed(1)}, ${dR.y.toFixed(1)}); expected design point (${expectRight.x.toFixed(1)}, ${expectRight.y.toFixed(1)}) vs aimvp (${right.aimvp.x.toFixed(1)}, ${right.aimvp.y.toFixed(1)}); err=${trackingError.toFixed(1)}`);
	token('AIM_MOVES_RIGHT', dR.x > 5, `dx=${dR.x.toFixed(1)}`);
	token('AIM_AXIS_ISOLATION_X', Math.abs(dR.y) < 3, `perpendicular dy=${dR.y.toFixed(1)}`);
	marks.aim_tracking_error_design_px = +trackingError.toFixed(2);

	const leftCss = { x: baseCss.x - STEP_CSS, y: baseCss.y };
	const left = await aimAfterMove(leftCss.x, leftCss.y);
	token('AIM_MOVES_LEFT', left.aimvp.x - base.aimvp.x < -5, `dx=${(left.aimvp.x - base.aimvp.x).toFixed(1)}`);

	const downCss = { x: baseCss.x, y: baseCss.y + STEP_CSS };
	const down = await aimAfterMove(downCss.x, downCss.y);
	token('AIM_MOVES_DOWN', down.aimvp.y - base.aimvp.y > 5, `dy=${(down.aimvp.y - base.aimvp.y).toFixed(1)}`);
	token('AIM_AXIS_ISOLATION_Y', Math.abs(down.aimvp.x - base.aimvp.x) < 3, `perpendicular dx=${(down.aimvp.x - base.aimvp.x).toFixed(1)}`);

	const upCss = { x: baseCss.x, y: baseCss.y - STEP_CSS };
	const up = await aimAfterMove(upCss.x, upCss.y);
	token('AIM_MOVES_UP', up.aimvp.y - base.aimvp.y < -5, `dy=${(up.aimvp.y - base.aimvp.y).toFixed(1)}`);
	timing('A-aim-directions');

	// Returning the cursor to where it started must return the aim exactly - this
	// is the half of "absolute, not relative" that a delta check cannot see.
	const back = await aimAfterMove(baseCss.x, baseCss.y);
	token('CURSOR_RETURNS_EXACTLY',
		Math.hypot(back.aimvp.x - base.aimvp.x, back.aimvp.y - base.aimvp.y) < 2,
		`dvp=(${(back.aimvp.x - base.aimvp.x).toFixed(2)}, ${(back.aimvp.y - base.aimvp.y).toFixed(2)})`);

	// The crosshair claim, now read instead of guessed: the product's own
	// crosshair Control must sit on the aim point the provider reports. The old
	// version compared pixel churn between two regions of an animated scene, which
	// cannot tell the crosshair from the water.
	const chk = await waitNewProbe(1, 6000);
	const crossErr = chk.crh && chk.aimvp ? Math.hypot(chk.crh.x - chk.aimvp.x, chk.crh.y - chk.aimvp.y) : NaN;
	marks.crosshair_vs_aim_design_px = Number.isFinite(crossErr) ? +crossErr.toFixed(2) : null;
	token('CROSSHAIR_FOLLOWS_AIM', !!chk.crh && !!chk.aimvp && crossErr < 2.5,
		`crh=${chk.crh ? `(${chk.crh.x.toFixed(1)}, ${chk.crh.y.toFixed(1)})` : 'unreported'} ` +
		`aimvp=${chk.aimvp ? `(${chk.aimvp.x.toFixed(1)}, ${chk.aimvp.y.toFixed(1)})` : 'unreported'} delta=${crossErr.toFixed(2)}`);
	// And it is really on screen: a crosshair drawn at a valid design point inside
	// the viewport, at the aim point. The capture below is the visual aid, not the
	// judgement.
	const onScreen = !!chk.crh && chk.crh.x >= 0 && chk.crh.x <= DESIGN.w && chk.crh.y >= 0 && chk.crh.y <= DESIGN.h;
	token('CROSSHAIR_IS_ON_SCREEN_AT_THE_AIM_POINT', onScreen && crossErr < 2.5,
		`crh=${chk.crh ? `(${chk.crh.x.toFixed(1)}, ${chk.crh.y.toFixed(1)})` : 'unreported'} inside ${DESIGN.w}x${DESIGN.h}`);
	await page.screenshot({ path: path.join(outDir, 'aim-02-crosshair-visible.png') });
	const mousemodeOk = chk.mm === 1 && !(await pointerLocked());
	token('GAMEPLAY_POINTER_IS_NOT_LOCKED', mousemodeOk,
		`mousemode=${chk.mm} (1 = HIDDEN: product crosshair, un-captured absolute cursor)`);
	timing('A-crosshair');

	// A continuous 360 degree sweep. The swept angle is accumulated between
	// consecutive REAL cursor positions, read in world space (viewport-space aim
	// saturates at the screen edges and cannot show a full revolution). Two laps of
	// a six-point ring: the assertion is the same >= 360 degrees as before, on a
	// sweep that still covers a full revolution twice.
	const RING = 6, LAPS = 2, RING_CSS = 160;
	let accumulated = 0;
	let prev = null;
	for (let lap = 0; lap < LAPS; lap++) {
		for (let i = 0; i < RING; i++) {
			const a = (i / RING) * Math.PI * 2;
			const c = { x: baseCss.x + Math.cos(a) * RING_CSS, y: baseCss.y + Math.sin(a) * RING_CSS };
			const s = await aimAfterMove(c.x, c.y);
			if (s && prev && s.aimworld && s.player && prev.aimworld && prev.player) {
				const a0 = Math.atan2(prev.aimworld.y - prev.player.y, prev.aimworld.x - prev.player.x);
				const a1 = Math.atan2(s.aimworld.y - s.player.y, s.aimworld.x - s.player.x);
				accumulated += Math.abs(wrap(deg(a1) - deg(a0)));
			}
			prev = s;
		}
	}
	marks.aim_360_accumulated_deg = +accumulated.toFixed(0);
	token('AIM_360', accumulated >= 360, `accumulated=${accumulated.toFixed(0)}deg over ${LAPS} full laps of ${RING} real cursor positions`);
	timing('A-aim-360');

	// --- WASD: a REAL key, held until the body actually moves. At CI's frame rate
	// a fixed 700 ms press can span less than one frame, so a fixed hold measures
	// the renderer instead of the input path.
	const w0 = stateNow();
	await keyDown('w');
	const wMoved = await waitState(s => s.player && w0.player && Math.hypot(s.player.x - w0.player.x, s.player.y - w0.player.y) > 2, 25000, 'w-moved');
	await keyUp('w');
	const w1 = wMoved.state || stateNow();
	token('WASD_POSITION_CHANGED', w0.player.y - w1.player.y > 2, `w dy=${(w0.player.y - w1.player.y).toFixed(1)}`);
	let dxProof = 0, usedKey = 'd';
	for (const key of ['d', 'a']) {
		const a0 = stateNow();
		await keyDown(key);
		const moved = await waitState(s => s.player && a0.player && Math.abs(s.player.x - a0.player.x) > 2, 25000, key + '-moved');
		await keyUp(key);
		const a1 = moved.state || stateNow();
		dxProof = a1.player.x - a0.player.x;
		if (Math.abs(dxProof) > 2) { usedKey = key; break; }
	}
	token('WASD_HORIZONTAL_CHANGED', Math.abs(dxProof) > 2, `key=${usedKey} dx=${dxProof.toFixed(1)}`);
	timing('A-wasd');

	// --- before the first Esc of the whole run, prove the aim chain ran without
	// one. Two independent readings: the driver's own key record, and the game's
	// state - no pause panel and no mouse-mode handover ever appeared during the
	// aim phase (a pause shows mousemode 0; the live session is mousemode 1).
	const aimPhase = probeLines.slice(aimPhaseStart);
	const pauseSeen = aimPhase.some(l => /pause=true/.test(l));
	const modeHandover = aimPhase.some(l => / mm=0\b/.test(l));
	token('ESC_NEVER_PRESSED_BEFORE_AIM',
		!keysSent.includes('Escape') && !pauseSeen && !modeHandover,
		`driver sent no Escape; during the aim phase the game reported pause=${pauseSeen} and mouse-mode handover=${modeHandover}`);

	// --- Esc semantics get their own pass, after the no-Esc phase above.
	await keyDown('w');
	await page.mouse.down();
	await press('Escape');
	const pausedOk = await waitState(s => s.pause === true && s.mm === 0, 20000, 'paused');
	await page.mouse.up();
	await keyUp('w');
	// The trigger reading is taken AFTER the real release, and waited for by state.
	// While the button is physically held `fr` is false by definition, so reading
	// the snapshot captured during the hold would report a stuck trigger that was
	// really just a pressed one.
	const frWait = await waitState(s => s.pause === true && s.fr === true, 20000, 'fire-released');
	token('ESC_PAUSED_THE_GAME', pausedOk.ok, `paused=${pausedOk.state && pausedOk.state.pause} mousemode=${pausedOk.state && pausedOk.state.mm}`);
	token('PAUSE_SHOWS_THE_POINTER', !!pausedOk.state && pausedOk.state.mm === 0, `mousemode=${pausedOk.state && pausedOk.state.mm}`);
	token('COMMANDS_ARE_NOT_STUCK_WHILE_PAUSED', frWait.ok,
		`after the real button release, while still paused: paused=${frWait.state && frWait.state.pause} fire_released=${frWait.state && frWait.state.fr}`);

	await press('Escape');
	const resumed = await waitState(s => s.pause === false && s.mm === 1, 20000, 'resumed');
	token('ESC_RESUMES_WITHOUT_RECAPTURE', resumed.ok, `paused=${(stateNow() || {}).pause} mousemode=${(stateNow() || {}).mm}`);
	const b0 = (await waitNewProbe(1, 6000));
	const b1r = await waitState(s => s.frames > b0.frames + 2, 20000, 'drift');
	const b1 = b1r.state || stateNow();
	const drift = Math.hypot(b1.player.x - b0.player.x, b1.player.y - b0.player.y);
	token('INPUT_NOT_STUCK_AFTER_RESUME', drift < 2, `drift=${drift.toFixed(2)} while no key is held`);

	const afterResume = await aimAfterMove(baseCss.x + STEP_CSS, baseCss.y);
	token('AIM_STILL_WORKS_AFTER_RESUME', Math.abs(afterResume.aimvp.x - base.aimvp.x) > 5,
		`dx=${(afterResume.aimvp.x - base.aimvp.x).toFixed(1)}`);
	timing('A-pause-resume');

	if (headed) {
		const other = await context.newPage();
		await other.goto('about:blank');
		await other.bringToFront();
		const blurred = await waitState(s => s.pause === true, 20000, 'blur');
		await page.bringToFront();
		const afterRefocus = await waitNewProbe(1, 6000);
		token('FOCUS_LOSS_PAUSES', blurred.ok, `paused=${blurred.ok}`);
		token('REGAIN_FOCUS_DOES_NOT_SELF_FIRE', afterRefocus.fr === true, `fire_released=${afterRefocus.fr}`);
		await press('Escape');
		token('RESUME_AFTER_FOCUS_LOSS', (await waitState(s => s.pause === false, 20000, 'refocus-resume')).ok);
		await other.close();
	} else {
		note('focus phase skipped: headless Chromium has no OS focus to lose (run with E2E_HEADED=1)');
	}

	token('PAGE_ALIVE_AFTER_NORMAL_ENTRY_INPUT', await page.evaluate(() => !!document.querySelector('#canvas-host canvas')));
	token('NO_POINTER_LOCK_ANYWHERE', !(await pointerLocked()));
	timing('A-done');

	// ============================================== Phase F: fault injection
	// Suppress the game's completion notice on purpose. The shell must NOT reveal
	// the game when nothing ever reports readiness: it keeps the cover, says the
	// load is stuck, and offers a retry. The old behaviour (reveal anyway when a
	// deadline expired) is exactly what made the deployed site look like it had
	// started when the timer had actually given up.
	//
	// The wait for the stall is one waitForFunction, so the predicate polls inside
	// the page instead of costing a page round trip per poll. The window itself
	// (the loader's own 45 s quiet deadline) is the product's, and is not shortened
	// or widened by the test.
	currentPhase = 'F:fault-injection';
	await page.goto(q(url, 'noready=1'), { waitUntil: 'domcontentloaded', timeout: 90000 });
	// ONE atomic observation of the whole contract, because the shell WITHDRAWS a
	// stall hint as soon as the game reports progress again (loader `mark()`), and
	// re-arms the quiet window from there. Reading the parts one round trip apart
	// let the halves disagree - measured locally, "the retry button is visible" from
	// one read and "there is no message" from the next. The predicate polls inside
	// the page, so the wait costs no page round trip, and it resolves only when the
	// notice was suppressed, the cover stayed up, nothing revealed the game, and the
	// player was told the load is slow AND offered a retry - all at the same instant.
	const fault = await page.waitForFunction(() => {
		const s = window.__dontStopState;
		if (!s) return null;
		const f = document.getElementById('frame');
		const retry = document.getElementById('retry');
		const err = document.getElementById('error');
		const snap = {
			outcome: s.outcome,
			revealedBy: s.revealedBy,
			readyNoticeSuppressed: s.readyNoticeSuppressed === true,
			stallWarnings: s.stallWarnings,
			activeStage: s.activeStage,
			coverVisible: !!f && f.style.display !== 'none' && !f.classList.contains('gone'),
			coverOpacity: f ? getComputedStyle(f).opacity : null,
			retryVisible: !!retry && retry.style.display !== 'none',
			errorText: err ? (err.textContent || '').trim().slice(0, 160) : '',
		};
		const core = snap.readyNoticeSuppressed && snap.coverVisible &&
			snap.outcome !== 'game-reported-ready' && snap.revealedBy === null;
		const recoverable = snap.retryVisible && snap.errorText.length > 0;
		return (core && recoverable) ? snap : null;
	// NOTE the `undefined` second argument. Playwright's signature is
	// waitForFunction(pageFunction, arg, options), so an options object handed in
	// as the second argument is passed to the PAGE as the predicate's argument and
	// `timeout`/`polling` are silently dropped - the wait then runs on Playwright's
	// 30 s default and a legitimately slow fault window looks like a hard failure.
	}, undefined, { timeout: 150000, polling: 200 }).then(h => h.jsonValue()).catch(() => null);
	if (!fault) note('the fault injection never produced a single observation where the cover stayed up AND a recoverable-stall message was on screen');
	token('FAULT_INJECTION_SUPPRESSES_NOTICE',
		!!fault && fault.readyNoticeSuppressed === true,
		`readyNoticeSuppressed=${fault && fault.readyNoticeSuppressed}`);
	token('FAULT_INJECTION_KEEPS_THE_COVER',
		!!fault && fault.coverVisible && fault.coverOpacity !== '0',
		`coverVisible=${fault && fault.coverVisible} opacity=${fault && fault.coverOpacity}`);
	token('FAULT_INJECTION_REPORTS_A_RECOVERABLE_STALL',
		!!fault && fault.retryVisible && fault.errorText.length > 0,
		`retryVisible=${fault && fault.retryVisible} message="${fault && fault.errorText}"`);
	// The point of the injection: the Phase A acceptance condition must be FALSE
	// here, i.e. a missing completion notice fails instead of passing late.
	token('FAULT_INJECTION_FAILS_THE_NORMAL_ASSERTION',
		!!fault && fault.outcome !== 'game-reported-ready' && fault.revealedBy === null,
		`outcome=${fault && fault.outcome} revealedBy=${fault && fault.revealedBy} would not satisfy SHELL_READY_VIA_GAME_NOTICE`);
	await page.screenshot({ path: path.join(outDir, 'aim-03-fault-injection-cover.png') });
	timing('F-done');

	// ================================== Phase B: the fire chain, read from state
	// Firing needs a weapon in an equipped hand and a live round. A fresh camp has
	// neither (PlayerData.player_weapon_list is empty on a fresh profile and
	// LevelServer.can_start() refuses to depart), which is why the harness is used
	// here - and it is the SAME harness the previous version used, so the fire
	// contract is not being tested against a weaker setup. What changed is the
	// evidence: bullets, projectile generation and the projectile's own flight
	// vector are read from the product, not inferred from a magazine screenshot.
	currentPhase = 'B:fire-chain';
	await page.goto(q(url, 'smoke=1&e2e=1&probe=1'), { waitUntil: 'domcontentloaded', timeout: 90000 });
	const diagReady = await shellGone();
	token('DIAGNOSTIC_ENTRY_READY', diagReady);
	if (!diagReady) throw new Error('diagnostic entry never became ready');
	const inCombat = await waitGameLine(/\[e2e\] ready/, 0, 300000);
	token('GAME_ENTERED_COMBAT', inCombat.ok, inCombat.ok ? 'the harness froze a real combat round' : 'the harness never became ready');
	if (!inCombat.ok) throw new Error('in-game harness never became ready');
	rect = (await canvasRect()) || rect;
	timing('B-combat-entry');

	// The chain needs a real weapon with a real magazine, and the state channel is
	// where that is checked rather than assumed.
	const armed = await waitState(s => s.sm === 'COMBAT' && s.ingame && s.gun >= 0 && s.bullets >= 0 && s.bulletsMax > 0, 60000, 'armed');
	token('COMBAT_HAS_A_REAL_WEAPON', armed.ok,
		armed.ok ? `sm=${armed.state.sm} gun=${armed.state.gun} magazine=${armed.state.bullets}/${armed.state.bulletsMax}` : 'no equipped weapon with a magazine was reported');

	const baseCssB = { x: rect.x + rect.w * 0.5, y: rect.y + rect.h * 0.5 };
	await aimAfterMove(baseCssB.x, baseCssB.y);

	// --- one real shot, measured before/after on the product's own numbers.
	// `shotsBefore`/`genBefore` are the user-visible truth: a magazine and a
	// projectile-generation counter. The negative control below uses the SAME
	// input with the product's own pause panel up.
	let fireHoldMs = 0;
	let fireEvidence = null;
	async function realShot(name, dirX, dirY, cmp, relocateKey) {
		if (relocateKey) {
			// Level layout is a precondition, not an input property: a muzzle that
			// starts inside a wall kills the projectile on its first physics frame.
			const r0 = stateNow();
			await keyDown(relocateKey);
			await waitState(s => s.player && r0.player && Math.hypot(s.player.x - r0.player.x, s.player.y - r0.player.y) > 4, 20000, 'relocate');
			await keyUp(relocateKey);
		}
		for (let attempt = 0; attempt < 4; attempt++) {
			// The magazine must not be empty. Reloading is a real key, and the wait
			// is on the product reporting rounds again.
			for (let i = 0; i < 4; i++) {
				const s = stateNow();
				if (s && s.bullets > 0) break;
				await press('r');
				await waitState(st => st.bullets > 0, 8000, 'reload');
			}
			const nudge = attempt === 0 ? 0 : (attempt % 2 === 1 ? 0.35 : -0.35);
			const ax = dirX + (dirY !== 0 ? nudge : 0);
			const ay = dirY + (dirX !== 0 ? nudge : 0);
			// The step is applied in CSS pixels because that is the space the real
			// cursor lives in; the design-space point is only read back for the
			// note. Handing a design-space value straight to the mouse move is the
			// mistake that made all four shots leave at the same up-left angle: a
			// design coordinate near the middle is a CSS coordinate near the
			// window's top-left corner, so every target collapsed onto one spot.
			const cssStep = { x: baseCssB.x + ax * STEP_CSS, y: baseCssB.y + ay * STEP_CSS };
			const target = cssToDesign(cssStep);
			await aimAfterMove(cssStep.x, cssStep.y);
			const before = await waitNewProbe(1, 6000);
			const shotsFrom = projShots.length;
			const downAt = Date.now();
			await page.mouse.down();
			// Two independent, engine-side readings of "a shot happened": the
			// projectile-generation counter went up, and the engine actually gave a
			// projectile a flight vector. Both are observations, not test-written
			// numbers. The event search is index-bounded rather than a snapshot, so
			// an event that arrives while we are still waiting is still seen - and
			// bounded below by `shotsFrom`, so a late event from an EARLIER attempt
			// cannot be read as this shot's direction.
			const gen = await waitState(s => s.proj > before.proj, 20000, 'generation');
			const evt = await waitIn(projShots, (e, i) => i >= shotsFrom && e.n > before.proj, 20000, 'flight');
			await page.mouse.up();
			fireHoldMs = Date.now() - downAt;
			const after = await waitNewProbe(2, 8000);
			if (!gen.ok || !evt.ok) {
				note(`${name} attempt ${attempt}: generation=${gen.ok} flight=${evt.ok}`);
				continue;
			}
			const got = Math.atan2(evt.hit.vy, evt.hit.vx) * 180 / Math.PI;
			const want = Math.atan2(dirY, dirX) * 180 / Math.PI;
			token(name, cmp(evt.hit.vx, evt.hit.vy),
				`attempt=${attempt} vx=${evt.hit.vx.toFixed(1)} vy=${evt.hit.vy.toFixed(1)} speed=${evt.hit.speed.toFixed(1)} angle=${got.toFixed(1)} wanted~${want.toFixed(1)}`);
			token(name + '_MATCHES_AIM', Math.abs(wrap(got - evt.hit.aim)) < 8,
				`projectile=${got.toFixed(1)} provider_aim=${evt.hit.aim.toFixed(1)} delta=${wrap(got - evt.hit.aim).toFixed(1)}`);
			return { before, after, evt: evt.hit, gen: gen.state, holdMs: fireHoldMs };
		}
		token(name, false, 'no projectile was observed');
		token(name + '_MATCHES_AIM', false, 'no projectile was observed');
		return null;
	}

	const rightShot = await realShot('PROJECTILE_FOLLOWS_AIM_RIGHT', 1, 0, vx => vx > 5);
	// The user-visible consequence of a real trigger pull, judged on the product's
	// own numbers: fewer rounds in the magazine AND a projectile the engine really
	// created in flight, along the aim it was fired at.
	if (rightShot) {
		fireEvidence = rightShot;
		marks.fire_right = {
			bullets_before: rightShot.before.bullets, bullets_after: rightShot.after.bullets,
			bullets_max: rightShot.before.bulletsMax,
			projectile_generation_before: rightShot.before.proj, projectile_generation_after: rightShot.after.proj,
			projectile_vx: +rightShot.evt.vx.toFixed(2), projectile_vy: +rightShot.evt.vy.toFixed(2),
			projectile_speed: +rightShot.evt.speed.toFixed(2), provider_aim_deg: +rightShot.evt.aim.toFixed(2),
			hold_ms: rightShot.holdMs,
		};
		token('REAL_FIRE_CONSUMES_AMMO',
			rightShot.after.bullets < rightShot.before.bullets &&
			rightShot.after.proj > rightShot.before.proj,
			`bullets ${rightShot.before.bullets} -> ${rightShot.after.bullets} of ${rightShot.before.bulletsMax}, ` +
			`projectile generation ${rightShot.before.proj} -> ${rightShot.after.proj}, ` +
			`projectile flew at ${(Math.atan2(rightShot.evt.vy, rightShot.evt.vx) * 180 / Math.PI).toFixed(1)}deg ` +
			`along provider aim ${rightShot.evt.aim.toFixed(1)}deg`);
	} else {
		token('REAL_FIRE_CONSUMES_AMMO', false, 'no projectile was observed, so no shot was proven');
	}
	timing('B-first-shot');
	await page.screenshot({ path: path.join(outDir, 'aim-04-fired-from-normal-entry.png') });

	await realShot('PROJECTILE_FOLLOWS_AIM_LEFT', -1, 0, vx => vx < -5);
	await realShot('PROJECTILE_FOLLOWS_AIM_DOWN', 0, 1, (vx, vy) => vy > 5);
	await realShot('PROJECTILE_FOLLOWS_AIM_UP', 0, -1, (vx, vy) => vy < -5, 's');
	timing('B-four-directions');

	// --- negative control: the SAME real input while the product's own pause panel
	// holds the tree paused. A paused tree cannot reach the weapon, so the magazine
	// must not move and no projectile may be created. Held for the same wall clock
	// the real shot used, so the two are comparable rather than merely similar.
	const blockedBefore = await waitNewProbe(1, 6000);
	await press('Tab');
	const blockPanel = await waitState(s => s.panels >= 1, 25000, 'blocked-panel');
	const blockSettled = await settlePaused();
	const blockLaidOut = await waitRect('camp-close-button', 12000);
	await page.mouse.down();
	await sleep(Math.max(fireHoldMs, 1200));
	await page.mouse.up();
	const blockedAfter = await waitNewProbe(2, 8000);
	const holdToCompare = Math.max(fireHoldMs, 1200);
	marks.blocked_input = {
		bullets_before: blockedBefore.bullets, bullets_after: blockedAfter.bullets,
		projectile_generation_before: blockedBefore.proj, projectile_generation_after: blockedAfter.proj,
		hold_ms: holdToCompare, panel_open: blockPanel.ok, pause_settled: blockSettled,
	};
	token('BLOCKED_FIRE_DOES_NOT_CONSUME_AMMO',
		blockPanel.ok && blockSettled &&
		blockedAfter.bullets === blockedBefore.bullets && blockedAfter.proj === blockedBefore.proj,
		`panel up=${blockPanel.ok}, pause stack settled=${blockSettled}; held a real trigger for ${holdToCompare}ms ` +
		`(the real shot held ${fireHoldMs}ms): bullets ${blockedBefore.bullets} -> ${blockedAfter.bullets}, ` +
		`projectile generation ${blockedBefore.proj} -> ${blockedAfter.proj}`);

	// Close it the way a player does, with a real click on the panel's own button,
	// and only then require the engine to keep ticking. A session left frozen by a
	// failed resume would satisfy every check above and fail only here.
	const blockedClosed = await clickTag('camp-close-button');
	const blockedGone = await waitState(s => !s.pause && s.panels === 0, 20000, 'blocked-closed');
	const liveFromB = stateNow();
	const liveB = await waitState(s => s.frames > liveFromB.frames + 2, 25000, 'blocked-live');
	token('SESSION_RUNNING_AGAIN_AFTER_BLOCKED_ATTEMPT',
		!!blockLaidOut.ok && blockedClosed.ok && blockedGone.ok && liveB.ok,
		`panel closed with a real click, panels=${(blockedGone.state || {}).panels}, engine advanced ${(liveB.state || stateNow()).frames - liveFromB.frames} frames while unpaused`);
	timing('B-blocked-input');

	// ================================================================== error gates
	// The pixel-independent noise filters are the ones this gate already carried.
	// The ONE addition is the very same NARROW engine-internal classification the
	// sibling gates use, and nothing wider: Godot's own self-list assertion, which
	// can fire while a scene is freed and another is added in the same frame - i.e.
	// exactly across the round/session swaps this gate performs. Godot delivers the
	// assertion and its location as two separate console messages, so no single
	// string carries both halves. It is PRINTED as a note (never swallowed), the raw
	// text stays in the evidence file, and every other error - including all
	// http>=400 - still fails the token. See docs/iteration/CI-OPTIMIZATION.md §7.1
	// for the A/B test that showed it is intermittent and not produced by the
	// read-only channel.
	const KNOWN_ENGINE_NOISE = e =>
		/Condition "p_elem->_root" is true/.test(e) ||
		/at: add \(\.\/core\/templates\/self_list\.h:\d+\)/.test(e);
	for (const e of consoleErrors.filter(KNOWN_ENGINE_NOISE)) {
		note('engine-internal (not a gate): ' + e.replace(/\s+/g, ' ').slice(0, 160));
	}
	const unexpectedErrors = consoleErrors.filter(e =>
		!KNOWN_ENGINE_NOISE(e) &&
		!/WebGL|GL_|AudioContext|download|currentTime|PagedAllocator|ObjectDB|could not be resolved|still in use at exit/i.test(e));
	token('NO_UNEXPECTED_ENGINE_ERRORS', unexpectedErrors.length === 0, unexpectedErrors.slice(0, 3).join(' | '));
	token('NO_PAGE_ERRORS', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));
	token('NO_NETWORK_ERRORS', badResponses.length === 0 && failedRequests.length === 0,
		`http>=400 ${badResponses.length}, failed requests ${failedRequests.length}` +
		(navigationAborts.length ? `, navigation-cancelled ${navigationAborts.length} (net::ERR_ABORTED, recorded not failed)` : ''));
	token('NO_POINTER_LOCK_EVER', !(await pointerLocked()));
	token('NO_RENDERER_CRASH', rendererCrash === null, rendererCrash || 'no renderer crash');
	token('WITHIN_THE_RUN_BUDGET', !watchdogFired, `whole-run watchdog ${ms(WATCHDOG_MS)}`);
	timing('B-errors');

	clearTimeout(watchdog);
	await context.close();
	fs.rmSync(profileDir, { recursive: true, force: true });

	const wall = Date.now() - RUN_T0;
	console.log('[aim-e2e] ---- phase timings ----');
	for (const t of timings) console.log(`[aim-e2e] timing ${t.name.padEnd(30)} ${t.ms}ms`);
	console.log(`[aim-e2e] WALL_CLOCK ${wall}ms`);
	fs.writeFileSync(path.join(outDir, 'web-aim-e2e.json'), JSON.stringify({
		url, headed, viewport: VIEW, design: DESIGN, tokens, notes, marks,
		wall_clock_ms: wall, phase_timings: timings,
		boot_timing_lines: bootLines,
		camp_close_button: rects['camp-close-button'] || null,
		probe_save_state: probeSaveState,
		console_errors: consoleErrors, page_errors: pageErrors,
		http_errors: badResponses, failed_requests: failedRequests,
		navigation_cancelled_requests: navigationAborts,
		sample_probe_line: (stateNow() || {}).raw || null,
		projectile_events: projShots,
		escape_sent_by_driver: keysSent.filter(k => k === 'Escape').length,
	}, null, 2));

	const required = [
		'SINGLE_START_ENTRY_POINT', 'LOADING_FEEDBACK_PRESENT', 'SHELL_HIDES_WITHOUT_A_START_CLICK',
		'SHELL_READY_VIA_GAME_NOTICE', 'SHELL_NEVER_REVEALS_ON_A_TIMER', 'SHELL_READY_NOT_AN_ERROR',
		'SHELL_TRACKS_LAUNCH_STAGES', 'ACCEPTANCE_IGNORES_ELAPSED_TIME',
		'OLD_FIXED_DEADLINE_WOULD_HAVE_MISLABELLED_IT',
		'CANVAS_VISIBLE_AFTER_LOAD', 'PROBE_STATE_IS_FLOWING', 'REAL_ENTRY_REACHES_THE_MENU',
		'START_CLICK_REACHED_THE_MENU', 'START_OPENS_A_ROUND',
		'CAMP_CLOSE_BUTTON_REPORTED_BY_THE_LIVE_PANEL', 'CAMP_PANEL_IS_ON_SCREEN',
		'REAL_CLICK_CLOSED_THE_PANEL', 'SESSION_IS_RUNNING', 'ESC_NEVER_PRESSED_BEFORE_AIM',
		'AIM_IS_THE_ABSOLUTE_CURSOR', 'AIM_MOVES_RIGHT', 'AIM_MOVES_LEFT', 'AIM_MOVES_UP', 'AIM_MOVES_DOWN',
		'AIM_AXIS_ISOLATION_X', 'AIM_AXIS_ISOLATION_Y', 'CURSOR_RETURNS_EXACTLY',
		'CROSSHAIR_FOLLOWS_AIM', 'CROSSHAIR_IS_ON_SCREEN_AT_THE_AIM_POINT',
		'GAMEPLAY_POINTER_IS_NOT_LOCKED', 'AIM_360',
		'WASD_POSITION_CHANGED', 'WASD_HORIZONTAL_CHANGED',
		'ESC_PAUSED_THE_GAME', 'PAUSE_SHOWS_THE_POINTER', 'COMMANDS_ARE_NOT_STUCK_WHILE_PAUSED',
		'ESC_RESUMES_WITHOUT_RECAPTURE', 'INPUT_NOT_STUCK_AFTER_RESUME', 'AIM_STILL_WORKS_AFTER_RESUME',
		'PAGE_ALIVE_AFTER_NORMAL_ENTRY_INPUT', 'NO_POINTER_LOCK_ANYWHERE',
		'FAULT_INJECTION_SUPPRESSES_NOTICE', 'FAULT_INJECTION_KEEPS_THE_COVER',
		'FAULT_INJECTION_REPORTS_A_RECOVERABLE_STALL', 'FAULT_INJECTION_FAILS_THE_NORMAL_ASSERTION',
		'DIAGNOSTIC_ENTRY_READY', 'GAME_ENTERED_COMBAT', 'COMBAT_HAS_A_REAL_WEAPON',
		'PROJECTILE_FOLLOWS_AIM_RIGHT', 'PROJECTILE_FOLLOWS_AIM_LEFT',
		'PROJECTILE_FOLLOWS_AIM_DOWN', 'PROJECTILE_FOLLOWS_AIM_UP',
		'PROJECTILE_FOLLOWS_AIM_RIGHT_MATCHES_AIM', 'PROJECTILE_FOLLOWS_AIM_LEFT_MATCHES_AIM',
		'PROJECTILE_FOLLOWS_AIM_DOWN_MATCHES_AIM', 'PROJECTILE_FOLLOWS_AIM_UP_MATCHES_AIM',
		'REAL_FIRE_CONSUMES_AMMO', 'BLOCKED_FIRE_DOES_NOT_CONSUME_AMMO',
		'SESSION_RUNNING_AGAIN_AFTER_BLOCKED_ATTEMPT',
		'NO_UNEXPECTED_ENGINE_ERRORS', 'NO_PAGE_ERRORS', 'NO_NETWORK_ERRORS',
		'NO_POINTER_LOCK_EVER', 'NO_RENDERER_CRASH', 'WITHIN_THE_RUN_BUDGET',
	];
	if (headed) required.push('FOCUS_LOSS_PAUSES', 'REGAIN_FOCUS_DOES_NOT_SELF_FIRE', 'RESUME_AFTER_FOCUS_LOSS');

	const failed = required.filter(k => !tokens[k]);
	for (const k of required) console.log(`[aim-e2e] token ${k}=${tokens[k] ? 'true' : 'false'}`);
	console.log(`[aim-e2e] token counts: ${required.length} required, ${failed.length} false, ${Object.keys(tokens).length} total`);
	if (failed.length) {
		console.log(`[aim-e2e] RESULT=FAIL (${failed.join(',')})`);
		process.exit(1);
	}
	console.log('[aim-e2e] RESULT=PASS');
})().catch(async e => {
	console.error('[aim-e2e] FATAL', e && e.stack ? e.stack : e);
	process.exit(1);
});
