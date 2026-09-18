// B11.1 dense-attack stress measurement, in a real browser, against a real Web export.
//
// Usage:
//   node tools/web-b11-1-stress.js <baseUrl> <evidenceDir> <label> <scenario> [key=value ...]
//
//   scenario   A | B | C | D                     (see game/diag/B11Stress.gd)
//   key=value  stage=39 seconds=90 seed=20260918 lasers=4 root=2.0 park=1
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
	const errors = [];
	// Every line the page printed, bounded. The engine's own script errors arrive here, and a
	// harness that reports "no summary line" without showing them is how a whole measurement round
	// gets spent guessing.
	const allConsole = [];

	const browser = await chromium.launch({
		headless: true,
		args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'],
	});
	const context = await browser.newContext({ viewport: { width: 1280, height: 760 } });
	const page = await context.newPage();
	// Chromium happily reuses a cached index.pck across page loads, which made a freshly exported
	// build invisible to earlier rounds of this project: the measurement was of the PREVIOUS build
	// and the only symptom was a missing line.
	await page.route('**/*', route => route.continue({
		headers: Object.assign({}, route.request().headers(), { 'cache-control': 'no-cache', pragma: 'no-cache' }),
	}));

	page.on('console', m => {
		const t = m.text();
		if (allConsole.length < 600) allConsole.push(`${m.type()}: ${t}`);
		if (t.startsWith('[spike] ')) spikes.push(parseKv(t.slice('[spike] '.length)));
		else if (t.startsWith('[stress-bucket] ')) buckets.push(parseKv(t.slice('[stress-bucket] '.length)));
		else if (t.startsWith('[stress-summary] ')) { summary = parseKv(t.slice('[stress-summary] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-cpu] ')) { cpu = parseKv(t.slice('[stress-cpu] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-peak] ')) { peak = parseKv(t.slice('[stress-peak] '.length)); markers.push(t); }
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
	while (Date.now() - started < wallBudgetMs && summary === null) await sleep(1000);
	await browser.close();

	const n = k => (summary && Number.isFinite(parseFloat(summary[k])) ? parseFloat(summary[k]) : null);
	const p = k => (peak && Number.isFinite(parseFloat(peak[k])) ? parseFloat(peak[k]) : null);
	const report = {
		label, scenario, url, build, gpu, errors,
		wall_clock_s: Math.round((Date.now() - started) / 1000),
		seconds_requested: parseInt(query.seconds, 10) || 90,
		rounds: summary ? parseFloat(summary.rounds) : null,
		frames: summary ? parseFloat(summary.frames) : null,
		combat_s: summary ? parseFloat(summary.combat_s) : null,
		frame_ms: summary ? { avg: n('avg'), p50: n('p50'), p95: n('p95'), p99: n('p99'), max: n('max') } : null,
		spikes: summary ? { over25: n('over25'), over33: n('over33'), over50: n('over50'), slow_run_ms: n('slow_run_ms') } : null,
		root: summary ? {
			windows: n('root_windows'),
			driver_applied: parseFloat(summary.driver_roots.split('/')[0]),
			driver_attempts: parseFloat(summary.driver_roots.split('/')[1]),
		} : null,
		amplified: summary ? n('amplified') : null,
		cpu,
		peaks: peak,
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
		`phys_avg=${f(cpu && cpu.phys_avg)} phys_p95=${f(cpu && cpu.phys_p95)} phys_max=${f(cpu && cpu.phys_max)} ` +
		`identity=${build.identity ? build.identity.slice(0, 16) : 'n/a'} gpu="${gpu}"`);
	for (const b of buckets) {
		console.log(`  bucket[${b.family}] ${b.name} n=${b.n} share=${f(b.share)} avg=${f(b.avg)} p95=${f(b.p95)} p99=${f(b.p99)} max=${f(b.max)} over33=${b.over33} over50=${b.over50}`);
	}
	process.exit(summary ? 0 : 1);
})();
