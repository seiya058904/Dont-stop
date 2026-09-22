// B11 dense-attack stress measurement, in a real browser, against a real Web export.
//
// Usage:
//   node tools/web-b11-1-stress.js <baseUrl> <evidenceDir> <label> <scenario> [key=value ...]
//
//   scenario   A | B | C | D                     (see game/diag/B11Stress.gd)
//   key=value  stage=39 seconds=90 seed=20260918 lasers=4 root=2.0 park=1
//              enemies=60 barrage=6 iso=vfx,labels,trails,fogcore,tddecor,particles
//
// B11.2 re-pointed the same four scenario names at four LOAD PROFILES (normal / dense enemies /
// dense attacks / worst visual load) and added the two density amplifiers and the visual-isolation
// switches. Everything the page reports is unchanged in shape: `[spike]` still gives one line per
// second, `[stress-summary]`/`[stress-cpu]`/`[stress-peak]`/`[stress-bucket]` are as they were, and
// the new `[stress-load]` and `[stress-ink]` lines carry the engine-level and redundancy counters.
//
// What it does NOT do, deliberately:
//   * it never runs against CI's software renderer. A software rasteriser reports its own
//     frame times, and this round is about the frame times a PLAYER's GPU path produces.
//   * it does not sample `?probe=1`. The stress driver publishes everything it needs on its own
//     channels. Arming the probe as well would add a 0.25 s-cadence subtree walk to a measurement
//     whose whole subject is single-frame spikes.
//   * it does not average the run into one number. `[spike]` gives one line per second so the
//     hitch can be located in the timeline, `[stress-bucket]` gives the same frame pool split by
//     what was happening on each frame, and `[stress-peak]` gives the peaks.
//
// The build under test is identified by the hashes of the three files the page actually loads, so
// a BEFORE run and an AFTER run can be told apart even when both are served from the same port.
'use strict';
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const base = process.argv[2];
const outDir = process.argv[3] || 'b11-1-stress-evidence';
const label = process.argv[4] || 'run';
const scenario = process.argv[5] || 'A';
const overrides = {};
for (const arg of process.argv.slice(6)) {
	const i = arg.indexOf('=');
	if (i > 0) overrides[arg.slice(0, i)] = arg.slice(i + 1);
}
if (!base) {
	console.error('usage: node web-b11-1-stress.js <baseUrl> <evidenceDir> <label> <scenario> [key=value ...]');
	process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

function hashBuild() {
	// Located from the served directory, not from the URL: the same three files the loader fetches.
	const dir = process.env.B11_BUILD_DIR || path.join(__dirname, '..', 'build', 'web');
	const result = {};
	for (const name of ['index.wasm', 'index.pck', 'index.js']) {
		const file = path.join(dir, name);
		if (!fs.existsSync(file)) { result[name] = null; continue; }
		const buf = fs.readFileSync(file);
		result[name] = { bytes: buf.length, sha256: crypto.createHash('sha256').update(buf).digest('hex') };
	}
	const identity = crypto.createHash('sha256');
	for (const name of ['index.wasm', 'index.pck', 'index.js']) {
		if (result[name]) identity.update(result[name].sha256);
	}
	result.identity = identity.digest('hex');
	return result;
}

function parseKv(line) {
	const out = {};
	for (const pair of line.split(' ')) {
		const i = pair.indexOf('=');
		if (i > 0) out[pair.slice(0, i)] = pair.slice(i + 1);
	}
	return out;
}

(async () => {
	const build = hashBuild();
	const query = Object.assign({ stress: '1', scenario, stage: '39', seconds: '90', seed: '20260918' }, overrides);
	const url = `${base}?` + new URLSearchParams(Object.entries(query).map(([k, v]) => [k, String(v)])).toString();
	const spikes = [];
	const buckets = [];
	const markers = [];
	let summary = null;
	let peak = null;
	let cpu = null;
	// B11.2 adds two report lines. They are parsed separately instead of growing `[stress-peak]`, so
	// a B11.1-era consumer of this JSON keeps reading exactly the fields it always read.
	let load = null;
	let ink = null;
	let rawFrames = null;
	const errors = [];
	// Every line the page printed, bounded. The engine's own script errors arrive here, and a
	// harness that reports "no summary line" without showing them is how a whole measurement round
	// gets spent guessing.
	const allConsole = [];
	const observations = [];
	let needsActivation = false;

	const browser = await chromium.launch({
		headless: false,
		// Codex may keep another headed tab in front of this isolated measurement
		// window.  Preserve real D3D11 rendering while preventing Chromium from
		// reducing the game tab to a one-frame-per-second background timer budget.
		args: [
			'--use-angle=d3d11',
			'--disable-background-timer-throttling',
			'--disable-backgrounding-occluded-windows',
			'--disable-renderer-backgrounding',
		],
	});
	const context = await browser.newContext({ viewport: { width: 1280, height: 760 } });
	const page = await context.newPage();
	await page.bringToFront();
	// Chromium happily reuses a cached index.pck across page loads, which made a freshly exported
	// build invisible to earlier rounds of this project: the measurement was of the PREVIOUS build
	// and the only symptom was a missing line.
	await page.route('**/*', route => route.continue({
		headers: Object.assign({}, route.request().headers(), { 'cache-control': 'no-cache', pragma: 'no-cache' }),
	}));

	page.on('console', m => {
		const t = m.text();
		if (t.includes('depart=true state=COMBAT')) needsActivation = true;
		if (t.startsWith('B18_')) { observations.push(t); console.log(t.slice(0,250)); }
		if (t.startsWith('[stress] ')) console.log(t);
		if (t.startsWith('[stress-frames] ')) {
			rawFrames = JSON.parse(t.slice('[stress-frames] '.length));
			return; // Store once, outside the bounded human-readable console log.
		}
		if (allConsole.length < 600) allConsole.push(`${m.type()}: ${t}`);
		if (t.startsWith('[spike] ')) spikes.push(parseKv(t.slice('[spike] '.length)));
		else if (t.startsWith('[stress-bucket] ')) buckets.push(parseKv(t.slice('[stress-bucket] '.length)));
		else if (t.startsWith('[stress-summary] ')) { summary = parseKv(t.slice('[stress-summary] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-cpu] ')) { cpu = parseKv(t.slice('[stress-cpu] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-peak] ')) { peak = parseKv(t.slice('[stress-peak] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-load] ')) { load = parseKv(t.slice('[stress-load] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-ink] ')) { ink = parseKv(t.slice('[stress-ink] '.length)); markers.push(t); }
		else if (t.startsWith('[stress] ') || t.startsWith('[stress-')) markers.push(t);
	});
	page.on('pageerror', e => { if (!/currentTime/.test(e.message)) errors.push(e.message); });

	const gpu = await page.evaluate(() => {
		const c = document.createElement('canvas');
		const gl = c.getContext('webgl2') || c.getContext('webgl');
		if (!gl) return null;
		const dbg = gl.getExtension('WEBGL_debug_renderer_info');
		return dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
	}).catch(() => null);

	const started = Date.now();
	await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
	// A round is 45 s and the driver runs rounds until the requested window is covered, so the wall
	// clock bound has to allow the boot plus the whole accumulation plus a margin.
	const wallBudgetMs = ((parseInt(query.seconds, 10) || 90) + 240) * 1000;
	while (Date.now() - started < wallBudgetMs && summary === null) {
		if (needsActivation) {
			needsActivation = false;
			await page.bringToFront();
			await page.mouse.click(640,380);
		}
		await sleep(1000);
	}
	const browserVersion = browser.version();
	const surface = await page.evaluate(() => ({dpr:devicePixelRatio,visibility:document.visibilityState,width:innerWidth,height:innerHeight,canvas:[...document.querySelectorAll('canvas')].map(c=>({width:c.width,height:c.height}))})).catch(()=>null);
	await browser.close();

	const n = k => (summary && Number.isFinite(parseFloat(summary[k])) ? parseFloat(summary[k]) : null);
	const p = k => (peak && Number.isFinite(parseFloat(peak[k])) ? parseFloat(peak[k]) : null);
	const report = {
		label, scenario, url, build, gpu, errors, browserVersion, surface, observations,
		wall_clock_s: Math.round((Date.now() - started) / 1000),
		seconds_requested: parseInt(query.seconds, 10) || 90,
		rounds: summary ? parseFloat(summary.rounds) : null,
		frames: summary ? parseFloat(summary.frames) : null,
		combat_s: summary ? parseFloat(summary.combat_s) : null,
		frame_ms: summary ? { avg: n('avg'), p50: n('p50'), p95: n('p95'), p99: n('p99'), max: n('max') } : null,
		spikes: summary ? { over25: n('over25'), over33: n('over33'), over50: n('over50'), slow_run_ms: n('slow_run_ms') } : null,

		amplified: summary ? n('amplified') : null,
		cpu,
		peaks: peak,
		load,
		ink,
		raw_frames: rawFrames,
		bucket_rows: buckets,
		per_second: spikes,
		markers,
		console: allConsole,
	};
	fs.writeFileSync(path.join(outDir, `stress-${label}-${scenario}.json`), JSON.stringify(report, null, '\t'));

	const f = v => (v === null || v === undefined || Number.isNaN(v) ? 'n/a' : Number(v).toFixed(2));
	console.log(`B11.1 STRESS ${label}/${scenario} frames=${report.frames} combat_s=${f(report.combat_s)} ` +
		`avg=${f(report.frame_ms && report.frame_ms.avg)} p95=${f(report.frame_ms && report.frame_ms.p95)} ` +
		`p99=${f(report.frame_ms && report.frame_ms.p99)} max=${f(report.frame_ms && report.frame_ms.max)} ` +
		`over25=${report.spikes && report.spikes.over25} over33=${report.spikes && report.spikes.over33} ` +
		`over50=${report.spikes && report.spikes.over50} slow_run_ms=${f(report.spikes && report.spikes.slow_run_ms)} ` +
		`ENGINE_WINDOW_PEAK_MONITOR physics_max_ms=${f(cpu && cpu.physics_max_ms)} process_max_ms=${f(cpu && cpu.process_max_ms)} ` +
		`identity=${build.identity ? build.identity.slice(0, 16) : 'n/a'} gpu="${gpu}"`);
	if (load) {
		console.log(`  load objects_peak=${load.objects_peak} orphans_peak=${load.orphans_peak} ` +
			`canvas_items_peak=${load.canvas_items_peak} draws_avg=${f(load.draws_avg)} draws_peak=${load.draws_peak} ` +
			`path_per_s=${f(load.path_per_s)} created_per_s=${f(load.created_per_s)} removed_per_s=${f(load.removed_per_s)} ` +
			`enemies_peak=${load.enemies_peak} projectiles_peak=${load.projectiles_peak} ` +
			`hazards_peak=${load.hazards_peak} zones_peak=${load.zones_peak} vfx_peak=${load.vfx_peak} labels_peak=${load.labels_peak}`);
	}
	if (ink) {
		console.log(`  ink fog_push_lines=${ink.fog_push_lines} fog_ensure_scans=${ink.fog_ensure_scans} ` +
			`fog_canvas_hits=${ink.fog_canvas_hits} fog_scans=${ink.fog_scans} ` +
			`fog_appended=${ink.fog_appended} fog_dropped=${ink.fog_dropped} ` +
			`fog_draws=${ink.fog_draws} fog_entries_drawn=${ink.fog_entries_drawn} ` +
			`fog_draw_usec=${ink.fog_draw_usec} shoots=${ink.shoots} ` +
			`shot_exceptions=${ink.shot_exceptions} shot_fog_mirrors=${ink.shot_fog_mirrors} ` +
			`hazard_draws=${ink.hazard_draws} telegraph_draws=${ink.telegraph_draws} ` +
			`td_cache_hits=${ink.telegraph_cache_hits} td_cache_rebuilds=${ink.telegraph_cache_rebuilds} ` +
			`status_walks=${ink.status_walks} status_walks_empty=${ink.status_walks_empty} ` +
			`label_tweens=${ink.label_tweens} labels_created=${ink.labels_created}`);
	}
	for (const b of buckets) {
		console.log(`  bucket[${b.family}] ${b.name} n=${b.n} share=${f(b.share)} avg=${f(b.avg)} p95=${f(b.p95)} p99=${f(b.p99)} max=${f(b.max)} over33=${b.over33} over50=${b.over50}`);
	}
	process.exit(summary ? 0 : 1);
})();
