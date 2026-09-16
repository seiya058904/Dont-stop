// Don't stop — slim online deployment smoke (Playwright + the read-only probe).
//
// Usage:
//   node online-smoke.js <pageUrl> <expectedArtifactDigest> <expectedBuildSha> [outDir] [identityFile]
//
// ---------------------------------------------------------------------------
// WHY THIS REPLACED A 100-MINUTE JOB
// ---------------------------------------------------------------------------
// The deployed-site job used to re-run the whole pre-deploy suite against Pages:
// smoke-web.js (?smoke=1, which boots into COMBAT), web-aim-e2e.js and
// web-menu-return-e2e.js with all five cycles. Its measured cost was 100m22s on a
// healthy main deploy, because the export uses the nothreads template (so every
// screenshot/evaluate waits for the game loop to release the browser main thread)
// and because each extra engine boot pays software-GL shader compilation again.
//
// Two facts make most of that redundant:
//   * the gates already proved behaviour, and they ran against the artifact that
//     is deployed - so the online job's real job is IDENTITY plus "the deployed
//     copy still runs", not "run the behaviour suite a fourth time";
//   * identity cannot come from HTTP 200 or a <title>. It comes from a digest of
//     the payload bytes, stamped into the page at build time and re-checked here
//     against the same bytes fetched from Pages.
//
// So this script asserts, in order:
//   1. the page is served, and carries the build SHA AND the payload digest the
//      workflow computed from the artifact it built;
//   2. the payload files are served and their SHA-256 matches the recorded ones
//      byte for byte (this is "deploy the exact artifact", as a fact);
//   3. the real entry point, with ONLY the read-only observation channel armed
//      (?probe=1 - no driver, no state forcing), reaches the menu, starts a round,
//      closes the panel, moves, aims, pauses and resumes, leaves through the
//      product's own 设置 -> 返回主菜单 route, and starts a second session.
//
// WHAT IT DELIBERATELY DOES NOT DO: re-enter COMBAT to fire a shot. That single
// step was the bulk of the old job's cost (a boot plus the first combat shader
// compile on a software renderer, minutes on CI) and it adds no identity
// information: fire and projectile direction are asserted pre-deploy by
// tools/web-aim-e2e.js, against the very bytes this script has just verified are
// the bytes on Pages. If that trade is ever revisited, the cost is a known
// number (see docs/iteration/CI-OPTIMIZATION.md) rather than a guess.

const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { chromium } = require('playwright');

const pageUrl = process.argv[2];
const expectDigest = process.argv[3] || '';
const expectSha = process.argv[4] || '';
const outDir = process.argv[5] || '.';
const identityFile = process.argv[6] || '';
if (!pageUrl) {
	console.error('usage: node online-smoke.js <pageUrl> <artifactDigest> <buildSha> [outDir] [identityFile]');
	process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

// A whole-run budget so a hang fails the job with a reason instead of burning the
// workflow's timeout. 5 minutes is the ceiling the pipeline is designed around.
const BUDGET_MS = parseInt(process.env.ONLINE_BUDGET_MS || String(5 * 60 * 1000), 10);

const tokens = {};
const notes = [];
const failed = [];
function token(name, ok, extra = '') {
	tokens[name] = !!ok;
	if (!ok) failed.push(name);
	console.log(`[online] ${ok ? 'ok  ' : 'FAIL'} ${name}${extra ? ' ' + extra : ''}`);
}
function note(t) { notes.push(t); console.log('[online] note ' + t); }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const ms = n => `${Math.round(n)}ms`;

let watchdogFired = false;
const watchdog = setTimeout(() => {
	watchdogFired = true;
	console.log(`[online] FAIL WATCHDOG_FIRED after ${ms(BUDGET_MS)}`);
	process.exit(1);
}, BUDGET_MS);
watchdog.unref?.();

const base = pageUrl.replace(/[^/]*$/, '');
const sha256 = buf => crypto.createHash('sha256').update(buf).digest('hex');
const DESIGN = { w: 410, h: 230 };
const MENU_START = { x: 41, y: 136 };

(async () => {
	// =============================================== 1. envelope + byte identity
	let identity = null;
	if (identityFile && fs.existsSync(identityFile)) {
		try { identity = JSON.parse(fs.readFileSync(identityFile, 'utf8')); } catch { identity = null; }
		note('identity file: ' + identityFile);
	} else {
		note('no identity file supplied: the payload is checked for availability and size only, not hashed');
	}

	const pageRes = await fetch(pageUrl, { redirect: 'follow' });
	const html = await pageRes.text();
	token('DEPLOYED_PAGE_IS_SERVED', pageRes.ok && html.length > 200,
		`HTTP ${pageRes.status}, ${html.length} bytes`);
	const meta = name => {
		const m = html.match(new RegExp(`<meta name="${name}" content="([^"]*)"`));
		return m ? m[1] : null;
	};
	const gotDigest = meta('dontstop-artifact');
	const gotSha = meta('dontstop-build');
	note(`deployed page declares build=${gotSha} artifact=${gotDigest}`);
	// Identity, not availability: a 200 or a correct title would pass while Pages
	// was still serving an older build.
	token('DEPLOYED_PAGE_CARRIES_THE_EXPECTED_BUILD',
		!!expectSha && gotSha === expectSha,
		`deployed=${gotSha} expected=${expectSha}`);
	token('DEPLOYED_PAGE_CARRIES_THE_EXPECTED_ARTIFACT_DIGEST',
		!!expectDigest && gotDigest === expectDigest,
		`deployed=${gotDigest} expected=${expectDigest}`);

	const payload = ['index.wasm', 'index.pck', 'index.js'];
	for (const name of payload) {
		const r = await fetch(base + name, { redirect: 'follow' });
		const buf = Buffer.from(await r.arrayBuffer());
		const ok = r.ok && buf.length > 1024;
		token(`RESOURCE_${name.replace(/[^a-z0-9]/gi, '_').toUpperCase()}_IS_SERVED`, ok,
			`HTTP ${r.status}, ${buf.length} bytes`);
		if (identity && Array.isArray(identity.files)) {
			const want = identity.files.find(f => f.name === name);
			if (want) {
				const got = sha256(buf);
				token(`RESOURCE_${name.replace(/[^a-z0-9]/gi, '_').toUpperCase()}_IS_THE_BUILT_BYTES`,
					got === want.sha256,
					`sha256 ${got.slice(0, 16)}… vs built ${String(want.sha256).slice(0, 16)}…`);
			}
		}
	}

	// ============================================ 2. the real entry still works
	// ONE page load, one engine boot, and only the read-only channel armed.
	const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), 'dontstop-online-'));
	const context = await chromium.launchPersistentContext(profileDir, {
		headless: true,
		viewport: { width: 1366, height: 768 },
		args: [
			'--enable-unsafe-swiftshader',
			'--disable-dev-shm-usage',
			'--disable-background-timer-throttling',
			'--disable-renderer-backgrounding',
			'--disable-backgrounding-occluded-windows',
		],
	});
	const page = context.pages()[0] || await context.newPage();

	let rendererCrash = null;
	page.on('crash', () => { rendererCrash = new Date().toISOString(); });
	const consoleErrors = [];
	const pageErrors = [];
	const badResponses = [];
	const failedRequests = [];
	// Same narrow classification as the menu-return gate: a request the browser
	// itself cancelled because the page navigated (net::ERR_ABORTED) carries no
	// HTTP status and is the navigation's artefact, not a broken resource, so it
	// is recorded separately. Every real failure still fails NO_NETWORK_ERRORS.
	const navigationAborts = [];
	let gameLines = [];
	let probeLines = [];
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
			if (!/frames=\d+/.test(t)) return;
			probeLines.push(t);
			return;
		}
		gameLines.push(t);
		if (gameLines.length > 4000) gameLines.splice(0, 2000);
	});
	page.on('pageerror', e => pageErrors.push('pageerror: ' + e.message));
	page.on('response', r => { if (r.status() >= 400) badResponses.push(r.status() + ' ' + r.url()); });
	page.on('requestfailed', r => {
		const why = (r.failure() && r.failure().errorText) || '?';
		const rec = r.url() + ' :: ' + why;
		if (why === 'net::ERR_ABORTED') navigationAborts.push(rec);
		else failedRequests.push(rec);
	});

	const num = (l, re) => { const m = l.match(re); return m ? parseFloat(m[1]) : NaN; };
	const vec = (l, re) => { const m = l.match(re); return m ? { x: parseFloat(m[1]), y: parseFloat(m[2]) } : null; };
	const parse = l => ({
		sess: num(l, /sess=(-?\d+)/), frames: num(l, /frames=(-?\d+)/),
		start: /start=true/.test(l), pause: /pause=true/.test(l),
		panels: num(l, /panels=(-?\d+)/), ingame: /ingame=true/.test(l),
		gun: num(l, /gun=(-?\d+)/),
		player: vec(l, /player=\((-?[\d.]+), (-?[\d.]+)\)/),
		aimvp: vec(l, /aimvp=\((-?[\d.]+), (-?[\d.]+)\)/),
		crh: vec(l, /crh=\((-?[\d.]+), (-?[\d.]+)\)/),
	});
	const stateNow = () => (probeLines.length ? parse(probeLines[probeLines.length - 1]) : null);
	async function waitState(pred, budgetMs, label) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const s = stateNow();
			if (s && pred(s)) return { ok: true, ms: Date.now() - t, state: s };
			await sleep(40);
		}
		return { ok: false, ms: Date.now() - t, state: stateNow(), label };
	}
	// The probe reports a control's rectangle only once it is laid out, so the
	// presence of rects[tag] is the readiness signal. This deliberately does NOT
	// demand a new instance id per panel: Godot recycles instance ids and reuses a
	// panel node across a hide/show, so a rebuilt panel can keep (or be handed
	// back) the id a driver already saw, and an id-based wait then times out even
	// though the panel is on screen and clickable. Readiness is anchored to state
	// instead - which panels are up, and whether the pause stack has settled.
	async function waitRect(tag, budgetMs) {
		const t = Date.now();
		while (Date.now() - t < budgetMs) {
			const r = rects[tag];
			if (r) return { ok: true, rect: r, ms: Date.now() - t };
			await sleep(40);
		}
		return { ok: false, rect: rects[tag] || null, ms: Date.now() - t };
	}
	// A panel pushes the pause stack from _enter_tree, before it is laid out, and
	// drops a key or click that arrives inside that window. Anchored to the
	// product's own state: the stack has to stay non-empty for a whole second.
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

	const shellGone = () => page.waitForFunction(() => {
		const f = document.getElementById('frame');
		return !f || f.style.display === 'none' || f.classList.contains('gone');
	}, { timeout: 240000 }).then(() => true).catch(() => false);

	await page.goto(pageUrl + (pageUrl.includes('?') ? '&' : '?') + 'probe=1', { waitUntil: 'domcontentloaded', timeout: 90000 });
	token('LOADER_SHELL_HIDES_BY_ITSELF', await shellGone(),
		'the shell only reveals the game on the game\'s own completion notice');
	await page.waitForSelector('#canvas-host canvas', { timeout: 60000 });
	const rect = await page.evaluate(() => {
		const c = document.querySelector('#canvas-host canvas');
		const r = c.getBoundingClientRect();
		return { x: r.x, y: r.y, w: r.width, h: r.height };
	});
	token('CANVAS_IS_VISIBLE', !!rect && rect.w > 100 && rect.h > 100, JSON.stringify(rect));
	const toCss = (dx, dy) => ({ x: rect.x + (dx / DESIGN.w) * rect.w, y: rect.y + (dy / DESIGN.h) * rect.h });
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

	const first = await waitState(() => true, 5000, 'first');
	token('PROBE_STATE_IS_FLOWING', !!first.state, first.state ? 'the read-only channel is reporting' : 'no probe line arrived');
	token('REAL_ENTRY_REACHES_THE_MENU',
		!!first.state && !first.state.start && first.state.gun === -1,
		`start=${first.state && first.state.start} gun=${first.state && first.state.gun}`);

	// --- start a round through the product's own menu button
	const fromStart = gameLines.length;
	await clickDesign(MENU_START.x, MENU_START.y);
	const pressed = await waitGameLine(/menu start button pressed/, fromStart, 10000);
	const started = await waitState(s => s.start, 20000, 'round');
	token('START_CLICK_REACHED_THE_MENU', pressed.ok, pressed.ok ? pressed.line.replace('[leave] ', '') : 'no press reached MainUI');
	token('START_OPENS_A_ROUND', started.ok, `start=${started.state && started.state.start} after ${ms(started.ms)}`);
	const panel = await waitState(s => s.panels >= 1, 20000, 'panel');
	const settled = await settlePaused();
	const laidOut = await waitRect('camp-close-button', 8000);
	token('CAMP_PANEL_IS_ON_SCREEN', panel.ok && settled && laidOut.ok,
		`panels=${panel.state && panel.state.panels}, pause stack settled=${settled}, close button on screen after ${ms(laidOut.ms)}`);

	// --- real click on the panel's own 返回 button
	const closed = await clickTag('camp-close-button');
	const gone = await waitState(s => !s.pause && s.panels === 0, 15000, 'closed');
	token('REAL_CLICK_CLOSED_THE_PANEL', closed.ok && gone.ok,
		`panels=${gone.state && gone.state.panels} after ${ms(gone.ms)}`);

	// --- the session is live, and a REAL key moves the body
	// Liveness, not throughput: the probe counter is PAUSABLE, so any advance at
	// all while unpaused means the loop is turning. A rate must not be asserted -
	// CI's software renderer runs this same loop below 1 fps (8 frames / 10 s on
	// the first real run of the sibling gate) where a developer machine vsyncs at
	// 60, so a fixed delta only measures the machine.
	const liveFrom = stateNow();
	const live = await waitState(s => s.frames > liveFrom.frames + 2, 15000, 'live');
	token('SESSION_IS_RUNNING', live.ok, `idle frames advanced ${(live.state || stateNow()).frames - liveFrom.frames} while unpaused`);
	// Hold the key until the body actually moves rather than for a fixed
	// wall-clock slice: at CI's frame rate a 900 ms press can span less than one
	// frame, so a fixed hold measures the renderer instead of the input path.
	// The key stays down for as long as the movement takes, then is released.
	const moveFrom = stateNow();
	await page.keyboard.down('d');
	const moved = await waitState(s => s.player && moveFrom.player && Math.hypot(s.player.x - moveFrom.player.x, s.player.y - moveFrom.player.y) > 1.5, 20000, 'moved');
	await page.keyboard.up('d');
	token('REAL_KEY_MOVED_THE_BODY', moved.ok,
		`held 'd': the body moved ${moved.state && moveFrom.player ? Math.hypot(moved.state.player.x - moveFrom.player.x, moved.state.player.y - moveFrom.player.y).toFixed(1) : 'n/a'} units`);

	// --- a REAL cursor move is what the aim indicator follows
	const aimD = { x: 150, y: 100 };
	const aimCss = toCss(aimD.x, aimD.y);
	await page.mouse.move(aimCss.x, aimCss.y);
	const aimed = await waitState(s => s.aimvp && Math.hypot(s.aimvp.x - aimD.x, s.aimvp.y - aimD.y) < 6, 12000, 'aim');
	const aimState = aimed.state || stateNow();
	const crossErr = aimState && aimState.crh && aimState.aimvp
		? Math.hypot(aimState.crh.x - aimState.aimvp.x, aimState.crh.y - aimState.aimvp.y) : NaN;
	token('REAL_CURSOR_MOVE_IS_WHAT_THE_AIM_FOLLOWS', aimed.ok && crossErr < 3,
		`cursor at design (${aimD.x},${aimD.y}) -> aim (${aimState && aimState.aimvp && aimState.aimvp.x.toFixed(1)},${aimState && aimState.aimvp && aimState.aimvp.y.toFixed(1)}), crosshair delta ${crossErr.toFixed(1)}`);

	// --- pause and resume through the product's own key
	await page.keyboard.press('Escape');
	const opened = await waitState(s => s.panels >= 1, 12000, 'pause');
	const pauseSettled = await settlePaused();
	await page.keyboard.press('Escape');
	const resumed = await waitState(s => s.panels === 0 && !s.pause, 12000, 'resume');
	token('PAUSE_AND_RESUME', opened.ok && pauseSettled && resumed.ok,
		`Esc opened the panel (${ms(opened.ms)}), the stack settled, and Esc closed it again (${ms(resumed.ms)})`);

	// --- leave through the product's own route
	const fromLeave = gameLines.length;
	await page.keyboard.press('Escape');
	await waitState(s => s.panels >= 1, 12000, 'leave-panel');
	await settlePaused();
	await waitRect('camp-settings-button', 6000);
	const settings = await clickTag('camp-settings-button');
	// panels>=2 is the state proof that the settings panel is the one on screen.
	await waitState(s => s.panels >= 2, 12000, 'settings');
	await waitRect('leave-entry', 8000);
	const leaveClick = await clickTag('leave-entry');
	const requested = await waitGameLine(/returning to the main menu/, fromLeave, 20000);
	const menuUp = await waitGameLine(/main menu is up .*ready=true/, fromLeave, 30000);
	const atMenu = await waitState(s => !s.start, 30000, 'menu');
	token('LEAVE_ROUTE_TOOK_EFFECT', settings.ok && leaveClick.ok && requested.ok,
		requested.ok ? requested.line.replace('[leave] ', '') : 'the leave entry was never reached');
	token('GAME_CONFIRMED_MENU_UP', menuUp.ok,
		menuUp.ok ? menuUp.line.replace('[leave] ', '').slice(0, 110) : 'the game never reported the menu being up');
	token('RETURNED_TO_THE_MENU', atMenu.ok, `start=${atMenu.state && atMenu.state.start}`);

	// --- a SECOND session: the one thing the old freeze-on-leave bug destroyed
	const sessBefore = (atMenu.state || stateNow()).sess;
	const fromRestart = gameLines.length;
	await clickDesign(MENU_START.x, MENU_START.y);
	const pressed2 = await waitGameLine(/menu start button pressed/, fromRestart, 10000);
	// The claim is "the returned menu accepted the press and a real, running round
	// opened" - instrumented by the round flag plus the pause-aware frame counter.
	// It is deliberately NOT instrumented by a session-generation bump: starting a
	// round does not change the generation (the menu's own hero is re-parented
	// into the round, so its instance id is unchanged). Only a RETURN to the menu
	// bumps it, because that builds the title scene's fresh hero. Asserting
	// `sess > sessBefore` here would measure the wrong thing and would fail on a
	// healthy build; the five-cycle menu-return gate is where the generation is
	// pinned, once per return.
	const started2 = await waitState(s => s.start, 25000, 'second');
	// The round really began: its camp panel owns the pause stack - which also
	// means the frame counter is frozen ON PURPOSE while it is up. So close it the
	// way a player does and only then require the engine to keep ticking. That
	// liveness after a return is precisely what the old freeze-on-leave bug
	// destroyed, and a frozen session would satisfy every check above and fail
	// only here.
	const panel2 = await waitState(s => s.panels >= 1, 12000, 'second-panel');
	let live2 = false;
	if (panel2.ok) {
		await settlePaused();
		await clickTag('camp-close-button');
		const closed2 = await waitState(s => s.panels === 0 && !s.pause, 12000, 'second-closed');
		const from2 = stateNow();
		live2 = closed2.ok && (await waitState(s => s.frames > from2.frames + 2, 12000, 'second-live')).ok;
	}
	token('START_CLICK_REACHED_THE_MENU_AGAIN', pressed2.ok, pressed2.ok ? pressed2.line.replace('[leave] ', '') : 'the returned menu ignored the press');
	token('SECOND_SESSION_WORKS', pressed2.ok && started2.ok && panel2.ok && live2,
		`a second round opened (start=${started2.state && started2.state.start}, camp panel up), its panel was closed with a real click, and the engine kept advancing frames while unpaused`);
	note(`session generation across the return: ${sessBefore} -> ${(started2.state || stateNow() || {}).sess} (a round start does not bump it; a return does)`);

	await page.screenshot({ path: path.join(outDir, 'online-second-session.png') }).catch(() => {});

	// --- no errors of any kind
	//
	// The same single engine-internal message the browser gates classify as
	// noise is classified here too, identically and narrowly: Godot's own
	// self-list assertion, which can fire while a scene is freed and another is
	// added in the same frame (i.e. exactly across the menu return this script
	// performs). It is not a product failure - the swap is proven by state
	// (a new session generation, the menu reporting ready, no weapon on it) -
	// and it is still reported below as a note rather than swallowed.
	// Godot delivers the assertion and its location as two separate console
	// messages, so no single string carries both halves. See the same filter in
	// tools/web-menu-return-e2e.js for the full note.
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
		(navigationAborts.length ? `, navigation-cancelled ${navigationAborts.length} (net::ERR_ABORTED, recorded not failed)` : ''));
	token('NO_RENDERER_CRASH', rendererCrash === null, rendererCrash || 'no renderer crash');
	token('WITHIN_THE_ONLINE_BUDGET', !watchdogFired, `whole-run budget ${ms(BUDGET_MS)}`);

	clearTimeout(watchdog);
	await context.close();
	fs.rmSync(profileDir, { recursive: true, force: true });
	await page.close?.().catch?.(() => {});

	fs.writeFileSync(path.join(outDir, 'online-smoke.json'), JSON.stringify({
		pageUrl, expectDigest, expectSha, tokens, notes,
		deployed_page: { build: gotSha, artifact: gotDigest },
		console_errors: consoleErrors, page_errors: pageErrors,
		http_errors: badResponses, failed_requests: failedRequests,
		navigation_cancelled_requests: navigationAborts,
	}, null, 2));

	console.log('[online] token counts: ' + Object.keys(tokens).length + ' total, ' + failed.length + ' false');
	if (failed.length) { console.log(`[online] RESULT=FAIL (${failed.join(',')})`); process.exit(1); }
	console.log('[online] RESULT=PASS');
})().catch(e => {
	console.error('[online] FATAL', e && e.stack ? e.stack : e);
	process.exit(1);
});
