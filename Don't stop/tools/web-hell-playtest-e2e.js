// Don't stop — B10 Hell playtest access, real-browser acceptance.
//
// Usage: node tools/web-hell-playtest-e2e.js <url> [evidenceDir]
//   E2E_HEADED=1        windowed Chromium
//   E2E_WATCHDOG_MS=N   whole-run watchdog (default 20 min)
//
// WHAT THIS PROVES, AND WHY IT IS DRIVEN THIS WAY
// ----------------------------------------------
// The blocker this round started from: Stage 31-40 shipped but a human could not reach them in
// the shipped Web build, because the only bypass was the native `--hell-unlock` command-line
// flag, and web/loader.html maps exactly five query parameters - none of them that one.
//
// So the acceptance is walked the way a PLAYER walks it: real mouse and keyboard, on the real
// controls, from the real entry point. Nothing here calls depart(), writes selected_stage, or
// forces a stage number. It:
//
//   1. proves the FORMAL gate is still shut in the browser: the official 31-40 entries are
//      disabled, and the read-only probe reports no rectangle for them, because the probe only
//      reports an ENABLED stage button that is really on screen;
//   2. clicks the labelled HELL PLAYTEST entry and proves those same buttons are now reported -
//      the rectangle appearing IS the enabled state, read off the live panel;
//   3. clicks stage 31, then the departure button the entry opens, and proves from the game's own
//      state channel that a real round at stage 31 started WITH the Hell darkness applied and
//      with the frame counter advancing;
//   4. plays the round out (survival timer for 31/35, death for the stage-40 boss round, whose
//      own configured duration is zero by design), returns to camp, and proves the darkness is
//      gone and the campaign was not touched;
//   5. does it again for 35 and 40 - including the stage that would otherwise set hell_complete;
//   6. leaves to the main menu and comes back in, then reaches stage 31 again, so the whole route
//      is proven in a SECOND session and not only the first.
//
// Every assertion is a comparison of numbers the product printed about itself on its own
// read-only channel (?probe=1, autoload/Smoke.gd), not a pixel diff.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { chromium } = require('playwright');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
if (!url) { console.error('usage: node web-hell-playtest-e2e.js <url> [evidenceDir]'); process.exit(2); }
fs.mkdirSync(outDir, { recursive: true });

const headed = process.env.E2E_HEADED === '1';
const WATCHDOG_MS = parseInt(process.env.E2E_WATCHDOG_MS || String(20 * 60 * 1000), 10);
const VIEW = { w: 1366, h: 768 };
const DESIGN = { w: 410, h: 230 };
const MENU_START = { x: 41, y: 136 };
const ROUND_BUDGET_MS = parseInt(process.env.E2E_ROUND_MS || '240000', 10);

const tokens = {};
const notes = [];
const failedTokens = [];
const timings = [];
const marks = {};
const RUN_T0 = Date.now();

function token(name, ok, extra = '') {
	tokens[name] = !!ok;
	if (!ok) failedTokens.push(name);
	console.log(`[hell-e2e] ${ok ? 'ok  ' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
}
function note(text) { notes.push(text); console.log('[hell-e2e] note ' + text); }
const q = (u, extra) => u + (u.includes('?') ? '&' : '?') + extra;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ms = n => `${Math.round(n)}ms`;

let watchdogFired = false;
let currentPhase = 'startup';
const watchdog = setTimeout(() => {
	watchdogFired = true;
	console.log(`[hell-e2e] FAIL WATCHDOG_FIRED after ${ms(WATCHDOG_MS)} during phase "${currentPhase}"`);
	console.log(`[hell-e2e] timing so far: ${timings.map(t => t.name + '=' + ms(t.ms)).join(' ')}`);
	process.exit(1);
}, WATCHDOG_MS);
watchdog.unref?.();

(async () => {
	const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dontstop-hell-e2e-'));
	const context = await chromium.launchPersistentContext(profileDir, {
		headless: !headed,
		viewport: { width: VIEW.w, height: VIEW.h },
		args: headed ? ['--window-size=1400,900'] : [
			'--enable-unsafe-swiftshader',
			'--disable-dev-shm-usage',
			'--disable-background-timer-throttling',
			'--disable-renderer-backgrounding',
			'--disable-backgrounding-occluded-windows',
		],
	});
	const page = context.pages()[0] || await context.newPage();

	const consoleErrors = [];
	const pageErrors = [];
	const badResponses = [];
	const failedRequests = [];
	const navigationAborts = [];
	let gameLines = [];
	let probeLines = [];
	let probeSaveState = null;
	const rects = {};

	page.on('console', m => {
		const t = m.text();
		if (m.type() === 'error') consoleErrors.push(t);
		if (t.startsWith('[probe] rect ')) {
			const g = t.match(/rect (\S+) id=(\d+) text="([^"]*)" x=([\d.-]+) y=([\d.-]+) w=([\d.-]+) h=([\d.-]+) cx=([\d.-]+) cy=([\d.-]+)/);
			if (g) rects[g[1]] = { id: +g[2], text: g[3], x: +g[4], y: +g[5], w: +g[6], h: +g[7], cx: +g[8], cy: +g[9] };
			return;
		}
		if (t.startsWith('[probe] ')) {
			if (t.startsWith('[probe] save_state')) { probeSaveState = t.replace('[probe] save_state', '').trim(); return; }
			if (!/frames=\d+/.test(t)) return;
			probeLines.push(t);
			if (probeLines.length > 8000) probeLines.splice(0, 4000);
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
		if (why === 'net::ERR_ABORTED') navigationAborts.push(rec); else failedRequests.push(rec);
	});

	const num = (l, re) => { const m = l.match(re); return m ? parseFloat(m[1]) : NaN; };
	function parseProbe(l) {
		return {
			raw: l,
			sess: num(l, /sess=(-?\d+)/),
			frames: num(l, /frames=(-?\d+)/),
			start: /start=true/.test(l),
			pause: /pause=true/.test(l),
			panels: num(l, /panels=(-?\d+)/),
			ingame: /ingame=true/.test(l),
			gun: num(l, /gun=(-?\d+)/),
			lstate: (l.match(/sm=(\S+)/) || [])[1],
			stage: num(l, /stage=(-?\d+)/),
			campaign: /camp=true/.test(l),
			hellc: /hellc=true/.test(l),
			next: num(l, /next=(-?\d+)/),
			sel: num(l, /sel=(-?\d+)/),
			pt: num(l, /pt=(-?\d+)/),
			fog: /fog=true/.test(l),
			scroll: num(l, /scroll=(-?\d+)/),
		};
	}
	const stateNow = () => (probeLines.length ? parseProbe(probeLines[probeLines.length - 1]) : null);
	async function waitState(pred, budgetMs, label) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const s = stateNow();
			if (s && pred(s)) return { ok: true, ms: Date.now() - t, state: s };
			await sleep(40);
		}
		return { ok: false, ms: Date.now() - t, state: stateNow(), timedOut: true, label };
	}
	async function waitRect(tag, budgetMs) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			if (rects[tag]) return { ok: true, rect: rects[tag], ms: Date.now() - t };
			await sleep(40);
		}
		return { ok: false, rect: rects[tag] || null, ms: Date.now() - t };
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
	async function settlePaused(budgetMs = 6000, minMs = 1000) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const s = stateNow();
			if (!s || s.panels < 1) return false;
			if (Date.now() - t >= minMs) return true;
			await sleep(120);
		}
		return false;
	}
	async function phase(name, fn) {
		currentPhase = name;
		const t = Date.now();
		try { return await fn(); } finally { timings.push({ name, ms: Date.now() - t }); }
	}

	const shellGone = () => page.waitForFunction(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	}, { timeout: 300000 }).then(() => true).catch(() => false);

	let rect = null;
	const toCss = (dx, dy) => ({ x: rect.x + (dx / DESIGN.w) * rect.w, y: rect.y + (dy / DESIGN.h) * rect.h });
	async function clickDesign(dx, dy) {
		const c = toCss(dx, dy);
		await page.mouse.move(c.x, c.y);
		await sleep(100);
		await page.mouse.down();
		await sleep(110);
		await page.mouse.up();
	}
	async function clickTag(tag) {
		const r = rects[tag];
		if (!r) return { ok: false, why: `${tag} was never reported by the game` };
		await clickDesign(r.cx, r.cy);
		return { ok: true, rect: r };
	}
	async function shot(name) {
		try { await page.screenshot({ path: path.join(outDir, name) }); } catch (err) { note('screenshot ' + name + ' failed: ' + (err && err.message)); }
	}

	// ------------------------------------------------------------------ scrolling
	// The camp's stage list is dozens of rows long, so the Hell section - and the playtest entry
	// below it - are outside the scroll viewport until the list is scrolled. The probe now
	// reports a rectangle only for a control that is REALLY inside its scroll viewport, so a
	// reported rectangle is always clickable, and the driver finds it the way a player does: by
	// putting the pointer over the list and turning the wheel. Real input, no synthetic scrolling.
	const LIST_POINT = { x: 80, y: 140 };
	function forget(tag) { delete rects[tag]; }
	async function pointerOverList() {
		const c = toCss(LIST_POINT.x, LIST_POINT.y);
		await page.mouse.move(c.x, c.y);
		await sleep(120);
	}
	// Scrolls until the PRODUCT reports the listing at the top, instead of guessing a turn count.
	// A guessed count is what made the first version of this driver work in one phase and fail in
	// the next: after the selector was opened the list kept its old offset, 30 fast wheel events
	// did not return it to the top, and the subsequent downward search never passed the control.
	// Wheels up for a bounded number of turns. It deliberately does NOT gate on the product
	// reporting scroll === 0: on the software renderer this build turns at ~6 fps, and a wheel
	// event only takes effect on a frame, so a fixed turn count that is generous is more reliable
	// than a condition that has to be observed between frames. The reading is still recorded, so a
	// failure can say where the list actually was.
	async function scrollListTop(turns = 24) {
		await pointerOverList();
		for (let i = 0; i < turns; i++) { await page.mouse.wheel(0, -700); await sleep(120); }
		await sleep(400);
		const s = stateNow();
		notes.push('scrollListTop finished, product reports scroll=' + (s && s.scroll));
		return s ? s.scroll === 0 : false;
	}
	async function scrollToTag(tag, budgetMs = 25000) {
		if (rects[tag]) return { ok: true, rect: rects[tag], ms: 0, turns: 0 };
		const t = Date.now();
		await pointerOverList();
		let turns = 0;
		while (Date.now() - t < budgetMs) {
			await page.mouse.wheel(0, 320);
			await sleep(170);
			turns++;
			if (rects[tag]) return { ok: true, rect: rects[tag], ms: Date.now() - t, turns };
			if (turns > 80) break;
		}
		return { ok: false, ms: Date.now() - t, turns };
	}
	// Scrolls the list from the top until the control is reported, which is what a person does.
	async function findInList(tag, budgetMs = 25000) {
		forget(tag);
		// TRY FIRST. The playtest entry and the playtest stage rows are deliberately at the TOP of
		// the list, so in the normal case the control is already on screen and no scrolling is
		// needed at all. Only if it is genuinely absent does the driver search the rest of the
		// list, which is also what a person does.
		await sleep(600);
		if (rects[tag]) return { ok: true, rect: rects[tag], ms: 0, turns: 0 };
		await scrollListTop();
		if (rects[tag]) return { ok: true, rect: rects[tag], ms: 0, turns: 0 };
		const found = await scrollToTag(tag, budgetMs);
		if (found.ok) return found;
		await scrollListTop();
		return scrollToTag(tag, budgetMs);
	}

	// ===================================================== Phase 0: fixture (setup only)
	await phase('fixture-seed-profile', async () => {
		await page.goto(q(url, 'smoke=1&e2e=1'), { waitUntil: 'domcontentloaded', timeout: 60000 });
		const seeded = await waitGameLine(/\[e2e\] ready/, 0, 300000);
		note('fixture: profile seeded so the camp owns a weapon and can depart; setup only, not an assertion');
		token('FIXTURE_PROFILE_SEEDED', seeded.ok);
	});

	// ===================================================== Phase A: load the acceptance page
	rect = null; probeLines = []; gameLines = []; Object.keys(rects).forEach(k => delete rects[k]);
	await phase('acceptance-load', async () => {
		await page.goto(q(url, 'probe=1'), { waitUntil: 'domcontentloaded', timeout: 60000 });
		token('SHELL_HIDES_WITHOUT_A_START_CLICK', await shellGone());
		await waitState(() => true, 2000, 'first-state');
		rect = await page.evaluate(() => {
			const c = document.querySelector('#canvas-host canvas');
			if (!c) return null;
			const r = c.getBoundingClientRect();
			return { x: r.x, y: r.y, w: r.width, h: r.height };
		});
		token('CANVAS_VISIBLE', !!rect && rect.w > 100 && rect.h > 100, JSON.stringify(rect));
		const st = stateNow();
		token('PROBE_STATE_IS_FLOWING', !!st, st ? st.raw.slice(0, 100) : 'no probe line arrived');
		const harness = gameLines.filter(l => l.startsWith('[smoke]') || l.includes('[e2e] ready') || l.includes('[e2e] state='));
		token('PROBE_IS_THE_ONLY_HARNESS', harness.length === 0,
			harness.length ? harness.slice(0, 2).join(' | ') : 'the acceptance page runs no smoke driver and no e2e stream');
	});

	// Clicking the menu's own start button is the only way a player reaches the camp.
	async function clickMenuStart(label) {
		const from = gameLines.length;
		await clickDesign(MENU_START.x, MENU_START.y);
		const pressed = await waitGameLine(/menu start button pressed/, from, 8000);
		token(`${label}_START_CLICK_REACHED_THE_MENU`, pressed.ok,
			pressed.ok ? pressed.line.replace('[leave] ', '') : 'no mouse press reached MainUI');
		const camp = await waitState(s => s.start && s.panels >= 1, 30000, `${label}-camp`);
		return camp;
	}

	// The camp panel opens on the weapon tab; the stage list is one more real click.
	async function openStageTab(label) {
		await settlePaused();
		const tab = await waitRect('camp-stage-tab', 12000);
		if (!tab.ok) { token(`${label}_STAGE_TAB_IS_REPORTED`, false, 'the stage tab was never reported'); return false; }
		token(`${label}_STAGE_TAB_IS_REPORTED`, true, `"${tab.rect.text}"`);
		await clickTag('camp-stage-tab');
		await sleep(700);
		return true;
	}

	// ---- 1. the formal gate is shut, in the UI the player actually sees ---------------------
	await phase('formal-gate-shut', async () => {
		const camp = await clickMenuStart('A');
		token('A_ENTERED_CAMP_FROM_THE_MENU', camp.ok,
			`start=${camp.state && camp.state.start} panels=${camp.state && camp.state.panels} after ${ms(camp.ms)}`);
		await openStageTab('A');
		const entry = await findInList('hell-playtest-button');
		token('A_HELL_PLAYTEST_ENTRY_IS_VISIBLE', entry.ok,
			entry.ok ? `"${entry.rect.text}" at (${entry.rect.cx.toFixed(0)},${entry.rect.cy.toFixed(0)}) design units after ${entry.turns} wheel turns` : 'the entry was never reachable by scrolling the list');
		await sleep(1500);
		// _probe_report_stage reports a stage button only when it is ENABLED and ON SCREEN, so the
		// ABSENCE of the rectangle is the product's own statement that the entry is locked.
		const reported = Object.keys(rects).filter(k => k.startsWith('stage-'));
		token('A_FORMAL_HELL_ENTRIES_ARE_LOCKED_IN_THE_BROWSER', reported.length === 0,
			reported.length ? `reported: ${reported.join(',')}` : 'no rectangle was reported for the disabled 31/35/40 entries');
		const st = stateNow();
		token('A_FRESH_PROFILE_IS_NOT_A_COMPLETED_CAMPAIGN', st && !st.campaign && !st.hellc,
			`campaign_complete=${st && st.campaign} hell_complete=${st && st.hellc} next=${st && st.next}`);
		await shot('10-hell-locked.png');
	});

	// ---- 2. the playtest entry opens the selector ------------------------------------------
	await phase('playtest-selector', async () => {
		const clicked = await clickTag('hell-playtest-button');
		token('B_PLAYTEST_ENTRY_CLICK_IS_REPORTED', clicked.ok, clicked.ok ? JSON.stringify(clicked.rect) : clicked.why);
		// The list re-renders in place, so the top of it is where the newly enabled stages now
		// live: scroll back up and look for them, exactly as a player would.
		const opened = await findInList('stage-31');
		token('B_PLAYTEST_SELECTOR_REPORTS_STAGE_31_AS_ENABLED', opened.ok,
			opened.ok ? `"${opened.rect.text}" at (${opened.rect.cx.toFixed(0)},${opened.rect.cy.toFixed(0)})` : 'stage 31 was still not reported as an enabled, on-screen control');
		// 31..40 is ten rows and the scroll viewport shows only the first few, so 35 and 40 are
		// genuinely below the fold and have to be scrolled to - which is exactly what the probe's
		// on-screen filter is for.
		const r35 = await findInList('stage-35', 20000);
		token('B_SELECTOR_REPORTS_STAGE_35_AFTER_SCROLLING', r35.ok, r35.ok ? `after ${r35.turns} wheel turns` : 'stage 35 was never on screen');
		const r40 = await findInList('stage-40', 20000);
		token('B_SELECTOR_REPORTS_STAGE_40_AFTER_SCROLLING', r40.ok, r40.ok ? `after ${r40.turns} wheel turns` : 'stage 40 was never on screen');
		const exit = await scrollToTag('hell-playtest-exit-button', 12000);
		token('B_SELECTOR_HAS_A_WAY_BACK', exit.ok, exit.ok ? `"${exit.rect.text}"` : 'no exit entry was reachable');
		const st = stateNow();
		token('B_OPENING_THE_SELECTOR_DID_NOT_TOUCH_PROGRESSION', st && !st.campaign && !st.hellc,
			`campaign_complete=${st && st.campaign} hell_complete=${st && st.hellc} next=${st && st.next}`);
		await shot('11-hell-playtest-selector.png');
	});

	// The results panel a finished round shows owns the pause stack; a second round cannot
	// depart until it is closed, and the product's own button is what closes it.
	async function clearRoundEndPanels(label) {
		for (let i = 0; i < 6; i++) {
			const s = stateNow();
			if (!s || s.panels === 0) return true;
			if (rects['scoreboard-ok']) { await clickTag('scoreboard-ok'); forget('scoreboard-ok'); await sleep(600); continue; }
			if (rects['deathboard-cancel']) { await clickTag('deathboard-cancel'); forget('deathboard-cancel'); await sleep(600); continue; }
			await page.keyboard.press('Escape');
			await sleep(600);
		}
		const s = stateNow();
		note(`${label}: after clearing round-end panels, panels=${s && s.panels}`);
		return !s || s.panels === 0;
	}

	// Play one Hell stage through the visible entry and come back to camp.
	async function playAndReturn(stage, label) {
		const mark = {};
		await phase(`${label}-enter`, async () => {
			const before = stateNow();
			mark.before = { next: before.next, campaign: before.campaign, hellc: before.hellc, sel: before.sel };
			// EACH ROUND STARTS FROM A FRESH CAMP PANEL, which is what a player gets and what the
			// product expects: the panel is created on demand and destroyed when it closes, so a
			// fresh one always opens with the selector CLOSED and the list at the TOP. Reusing the
			// previous phase's panel instead left the selector already open and the list scrolled
			// to the bottom, and this driver then reported "not reachable" for controls that were
			// simply not where a fresh panel would put them.
			if (stateNow() && stateNow().panels > 0) {
				await settlePaused();
				if (rects['camp-close-button']) { await clickTag('camp-close-button'); forget('camp-close-button'); }
				await waitState(s => s.panels === 0, 12000, `${label}-closed`);
			}
			await page.keyboard.press('Escape');
			const panelUp = await waitState(s => s.panels >= 1, 12000, `${label}-panel`);
			token(`${label}_CAMP_PANEL_OPENED_FRESH`, panelUp.ok, `panels=${panelUp.state && panelUp.state.panels}`);
			await openStageTab(label);
			// The camp panel is rebuilt every time it opens, so the playtest selector starts
			// CLOSED again for every round - which is the product's own design and is asserted in
			// tests/B10Playtest.gd. The driver therefore re-opens it with a real click each time.
			// The selector may ALREADY be open: a camp panel that stays on the pause stack keeps
			// its state, so a panel left in playtest mode by an earlier phase is still in it.
			// Looking only for the entry made this driver report "not reachable" for a control
			// that had correctly been replaced by the selector.
			const selector = await findInList('hell-playtest-button');
			if (selector.ok) {
				token(`${label}_PLAYTEST_ENTRY_IS_REACHABLE`, true, `after ${selector.turns} wheel turns`);
				await clickTag('hell-playtest-button');
				await sleep(800);
			} else {
				const already = await findInList('stage-31');
				token(`${label}_PLAYTEST_ENTRY_IS_REACHABLE`, already.ok,
					already.ok ? 'the selector was already open, so the entry is correctly absent'
					           : 'neither the entry nor the open selector was reachable');
			}
			// The stage tab auto-opens the FIRST stage's detail pane, so a departure button is
			// always reported for stage 1. Forgetting it here is what stops this driver pressing
			// "depart" on the wrong stage - which is exactly what a first version of this script
			// did: it reported three Hell rounds while actually playing stage 1 three times.
			forget('camp-depart-button');
			const entry = await findInList(`stage-${stage}`);
			token(`${label}_STAGE_ENTRY_IS_REPORTED`, entry.ok,
				entry.ok ? `"${entry.rect.text}" at (${entry.rect.cy.toFixed(0)}) after ${entry.turns} wheel turns` : `stage ${stage} entry was never reachable`);
			if (entry.ok) await clickTag(`stage-${stage}`);
			// A NEW departure button is what the entry click produces; waiting for a fresh
			// instance id is the proof the detail pane really switched to this stage.
			const depart = await waitRect('camp-depart-button', 12000);
			token(`${label}_DEPART_BUTTON_IS_REPORTED`, depart.ok, depart.ok ? `"${depart.rect.text}"` : 'the detail pane reported no departure button');
			await settlePaused();
			await clickTag('camp-depart-button');
			const live = await waitState(s => s.lstate === 'COMBAT' && s.stage === stage, 40000, `${label}-combat`);
			token(`${label}_ROUND_STARTED_AT_STAGE`, live.ok, `state=${live.state && live.state.lstate} stage=${live.state && live.state.stage} after ${ms(live.ms)}`);
			token(`${label}_HELL_DARKNESS_IS_APPLIED`, live.ok && live.state.fog, `fog=${live.state && live.state.fog} (ArenaVisibility.fog_active())`);
			token(`${label}_ROUND_IS_MARKED_AS_A_PLAYTEST`, live.ok && live.state.pt === stage, `pt=${live.state && live.state.pt}`);
			const f0 = stateNow();
			const moving = await waitState(s => s.frames > f0.frames + 2, 20000, `${label}-frames`);
			token(`${label}_ROUND_IS_REALLY_RUNNING`, moving.ok,
				`frames advanced ${(moving.state || stateNow()).frames - f0.frames} while in COMBAT`);
			mark.entered = { stage: live.state && live.state.stage, fog: live.state && live.state.fog, pt: live.state && live.state.pt };
			await shot(`${label}-in-hell.png`);
		});

		await phase(`${label}-return`, async () => {
			// The round ends the way the product ends it: the survival clock runs out, or the
			// player dies. Nothing here forces either - the driver only clicks the panel the
			// product itself puts on screen when a round is over.
			const t0 = Date.now();
			let ended = { ok: false, ms: 0, state: null };
			while (Date.now() - t0 < ROUND_BUDGET_MS) {
				const s = stateNow();
				if (s && s.lstate === 'CAMP') { ended = { ok: true, ms: Date.now() - t0, state: s }; break; }
				if (rects['deathboard-cancel']) { await clickTag('deathboard-cancel'); await sleep(800); }
				if (rects['scoreboard-ok']) { await clickTag('scoreboard-ok'); await sleep(800); }
				await sleep(200);
			}
			token(`${label}_ROUND_ENDED_AND_RETURNED_TO_CAMP`, ended.ok,
				`state=${ended.state && ended.state.lstate} after ${ms(ended.ms)}`);
			const s = ended.state || stateNow();
			token(`${label}_CAMP_IS_BRIGHT_AGAIN`, s && !s.fog, `fog=${s && s.fog}`);
			mark.after = { next: s.next, campaign: s.campaign, hellc: s.hellc, sel: s.sel, fog: s.fog };
			token(`${label}_PROGRESSION_POINTER_UNMOVED`, s.next === mark.before.next, `next_stage ${mark.before.next} -> ${s.next}`);
			token(`${label}_CAMPAIGN_STILL_NOT_COMPLETE`, !s.campaign && !s.hellc,
				`campaign_complete=${s.campaign} hell_complete=${s.hellc}`);
			await shot(`${label}-back-in-camp.png`);
			await clearRoundEndPanels(label);
		});
		marks[label] = mark;
		return mark;
	}

	await phase('play-31-35-40', async () => {
		await playAndReturn(31, 'C31');
		await playAndReturn(35, 'C35');
		await playAndReturn(40, 'C40');
	});

	// ---- 6. leave to the main menu, come back in, and reach stage 31 again -------------------
	await phase('second-session', async () => {
		if (!stateNow() || stateNow().panels === 0) {
			await page.keyboard.press('Escape');
			await waitState(s => s.panels >= 1, 10000, 'leave-panel');
		}
		await settlePaused();
		await waitRect('camp-settings-button', 10000);
		await clickTag('camp-settings-button');
		await waitState(s => s.panels >= 2, 12000, 'settings-panel');
		const from = gameLines.length;
		await waitRect('leave-entry', 10000);
		await clickTag('leave-entry');
		const menuUp = await waitGameLine(/main menu is up .*ready=true/, from, 30000);
		token('F_LEAVE_ENTRY_RETURNED_TO_THE_MAIN_MENU', menuUp.ok,
			menuUp.ok ? menuUp.line.replace('[leave] ', '').slice(0, 120) : 'the game never reported the menu being up');
		const atMenu = await waitState(s => !s.start && s.panels === 0 && s.gun === -1, 30000, 'at-menu');
		token('F_MENU_IS_LIVE_AGAIN', atMenu.ok, `start=${atMenu.state && atMenu.state.start} gun=${atMenu.state && atMenu.state.gun} panels=${atMenu.state && atMenu.state.panels}`);
		const camp = await clickMenuStart('F');
		token('F_SECOND_SESSION_STARTED', camp.ok, `start=${camp.state && camp.state.start} after ${ms(camp.ms)}`);
		await openStageTab('F');
		const entry = await findInList('hell-playtest-button');
		if (entry.ok) await clickTag('hell-playtest-button');
		const opened = await findInList('stage-31');
		token('F_PLAYTEST_ENTRY_WORKS_IN_A_SECOND_SESSION', entry.ok && opened.ok,
			opened.ok ? `stage 31 re-enabled at (${opened.rect.cx.toFixed(0)},${opened.rect.cy.toFixed(0)})` : 'stage 31 was not reported again');
		await shot('60-second-session-selector.png');
		const s = stateNow();
		token('F_SECOND_SESSION_SAVE_IS_STILL_A_CAMPAIGN_IN_PROGRESS', s && !s.campaign && !s.hellc,
			`campaign_complete=${s && s.campaign} hell_complete=${s && s.hellc} next=${s && s.next} save=${probeSaveState}`);
	});

	// ===================================================== Phase Z: error audit
	await phase('error-audit', async () => {
		const KNOWN_ENGINE_NOISE = e =>
			/Condition "p_elem->_root" is true/.test(e) ||
			/at: add \(\.\/core\/templates\/self_list\.h:\d+\)/.test(e);
		for (const e of consoleErrors.filter(KNOWN_ENGINE_NOISE)) {
			note('engine-internal (not a gate): ' + e.replace(/\s+/g, ' ').slice(0, 160));
		}
		const unexpected = consoleErrors.filter(e =>
			!KNOWN_ENGINE_NOISE(e) &&
			!/WebGL|GL_|AudioContext|download|currentTime|PagedAllocator|ObjectDB|could not be resolved|still in use at exit/i.test(e));
		token('NO_UNEXPECTED_ENGINE_ERRORS', unexpected.length === 0, unexpected.slice(0, 3).join(' | '));
		token('NO_PAGE_ERRORS', pageErrors.length === 0, pageErrors.slice(0, 3).join(' | '));
		token('NO_NETWORK_ERRORS', badResponses.length === 0 && failedRequests.length === 0,
			`http>=400 ${badResponses.length}, failed requests ${failedRequests.length}` +
			(navigationAborts.length ? `, navigation-cancelled ${navigationAborts.length}` : ''));
		token('WATCHDOG_DID_NOT_FIRE', !watchdogFired, `whole-run budget ${ms(WATCHDOG_MS)}`);
	});

	const wallMs = Date.now() - RUN_T0;
	console.log('\n[hell-e2e] ---- phase timings ----');
	for (const t of timings) console.log(`[hell-e2e] timing ${t.name.padEnd(30)} ${ms(t.ms)}`);
	console.log(`[hell-e2e] timing ${'WALL_CLOCK'.padEnd(30)} ${ms(wallMs)}`);

	fs.writeFileSync(path.join(outDir, 'web-hell-playtest-e2e.json'), JSON.stringify({
		url, headed, tokens, notes, timings, wall_clock_ms: wallMs, rounds: marks,
		probe: { transport: 'read-only ?probe=1 console channel (autoload/Smoke.gd)', save_state: probeSaveState },
		rects_reported_by_the_game: rects,
		console_errors: consoleErrors, page_errors: pageErrors,
		http_errors: badResponses, failed_requests: failedRequests,
		navigation_cancelled_requests: navigationAborts,
	}, null, 2));

	await context.close();
	fs.rmSync(profileDir, { recursive: true, force: true });
	clearTimeout(watchdog);

	const failed = Object.keys(tokens).filter(k => !tokens[k]);
	console.log(`[hell-e2e] token counts: ${Object.keys(tokens).length} total, ${failed.length} false`);
	for (const k of Object.keys(tokens)) console.log(`[hell-e2e] token ${k}=${tokens[k] ? 'true' : 'false'}`);
	if (failed.length) { console.log(`[hell-e2e] RESULT=FAIL (${failed.join(',')})`); process.exit(1); }
	console.log('[hell-e2e] RESULT=PASS');
})().catch(e => { console.error('[hell-e2e] FATAL', e && e.stack ? e.stack : e); process.exit(1); });
