// B11 sustained-load measurement in a real browser, with caching disabled.
//
// Usage: node tools/web-b11-perf.js <url> <stage> <seconds> <label> [evidenceDir]
//
// Two hard-won details are baked in:
//   * `Cache-Control: no-store` on every response. Chromium happily reuses a cached index.pck across
//     page loads, which made a freshly exported build invisible to three consecutive runs - the
//     measurement was of the PREVIOUS build, and the only symptom was a missing line.
//   * it never runs against CI's software renderer, which cannot say anything about a player's machine.
// The same script measures the BEFORE and the AFTER build: same browser, same flags, same GPU path,
// same stage, same duration.
'use strict';
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const url = process.argv[2];
const stage = parseInt(process.argv[3] || '39', 10);
const seconds = parseInt(process.argv[4] || '60', 10);
const label = process.argv[5] || 'run';
const outDir = process.argv[6] || 'b11-perf-evidence';
if (!url) { console.error('usage: node web-b11-perf.js <url> <stage> <seconds> <label> [evidenceDir]'); process.exit(2); }
fs.mkdirSync(outDir, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
	const started = Date.now();
	const browser = await chromium.launch({
		headless: true,
		args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'],
	});
	const page = await (await browser.newContext({ viewport: { width: 1280, height: 760 } })).newPage();
	await page.route('**/*', route => route.continue({ headers: Object.assign({}, route.request().headers(), { 'cache-control': 'no-cache', pragma: 'no-cache' }) }));
	const samples = [];
	const errors = [];
	const markers = [];
	page.on('console', m => {
		const t = m.text();
		if (t.startsWith('[smoke-perf]')) markers.push(t);
		if (t.startsWith('[probe] perf ')) {
			const line = t.slice('[probe] perf '.length);
			const num = k => { const m2 = line.match(new RegExp(k + '=([-\\d.]+)')); return m2 ? parseFloat(m2[1]) : NaN; };
			samples.push({
				avg: num('avg'), p50: num('p50'), p95: num('p95'), p99: num('p99'), max: num('max'),
				fps: num('fps'), frames: num('frames'), enemies: num('enemies'), projectiles: num('projectiles'),
				telegraphs: num('telegraphs'), hazards: num('hazards'), vfx: num('vfx'),
				particles: num('particles'), nodes: num('nodes'), created: num('created'),
				removed: num('removed'), nodes_delta: num('nodes_delta'),
			});
		}
	});
	page.on('pageerror', e => { if (!/currentTime/.test(e.message)) errors.push(e.message); });

	const gpuInfo = await page.evaluate(() => {
		const c = document.createElement('canvas');
		const gl = c.getContext('webgl2') || c.getContext('webgl');
		if (!gl) return null;
		const dbg = gl.getExtension('WEBGL_debug_renderer_info');
		return dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
	}).catch(() => null);

	await page.goto(`${url}?probe=1&perf=1&stage=${stage}&seconds=${seconds}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
	const deadline = Date.now() + (seconds + 150) * 1000;
	while (Date.now() < deadline && samples.length < seconds) await sleep(1000);
	await browser.close();

	const col = key => samples.map(s => s[key]).filter(v => Number.isFinite(v));
	const stat = key => {
		const values = col(key).slice();
		if (!values.length) return null;
		const total = values.reduce((a, b) => a + b, 0);
		values.sort((a, b) => a - b);
		return { n: values.length, avg: total / values.length, min: values[0], p50: values[Math.floor(values.length * 0.5)], max: values[values.length - 1] };
	};
	const windowAvg = (key, from) => {
		const values = col(key).slice(from);
		if (!values.length) return null;
		return values.reduce((a, b) => a + b, 0) / values.length;
	};
	const third = Math.floor(samples.length / 3);
	const summary = {
		label, url, stage, seconds_requested: seconds, samples: samples.length, markers,
		gpu: gpuInfo, wall_clock_s: Math.round((Date.now() - started) / 1000), errors,
		frame_ms: { avg: stat('avg'), p50: stat('p50'), p95: stat('p95'), p99: stat('p99'), max: stat('max') },
		fps: stat('fps'),
		frame_ms_avg_late_third: windowAvg('avg', samples.length - third),
		enemies: stat('enemies'), projectiles: stat('projectiles'), telegraphs: stat('telegraphs'),
		hazards: stat('hazards'), vfx: stat('vfx'), particles: stat('particles'),
		nodes: stat('nodes'), created: stat('created'), removed: stat('removed'),
		first_nodes: samples.length ? samples[0].nodes : null,
		last_nodes: samples.length ? samples[samples.length - 1].nodes : null,
		peak_nodes: col('nodes').length ? Math.max(...col('nodes')) : null,
	};
	fs.writeFileSync(path.join(outDir, `web-perf-${label}-stage${stage}.json`), JSON.stringify({ summary, samples }, null, '\t'));
	const f = v => (v === null || v === undefined ? 'n/a' : v.toFixed(2));
	console.log(`B11 WEB PERF ${label} stage=${stage} samples=${samples.length} markers=${markers.length} fps_avg=${f(summary.fps && summary.fps.avg)} frame_ms_avg=${f(summary.frame_ms.avg && summary.frame_ms.avg.avg)} frame_ms_p95=${f(summary.frame_ms.p95 && summary.frame_ms.p95.avg)} frame_ms_max=${f(summary.frame_ms.max && summary.frame_ms.max.max)} nodes_first=${summary.first_nodes} nodes_last=${summary.last_nodes} peak_nodes=${summary.peak_nodes} peak_enemies=${summary.enemies && summary.enemies.max} peak_projectiles=${summary.projectiles && summary.projectiles.max} peak_telegraphs=${summary.telegraphs && summary.telegraphs.max} gpu="${gpuInfo}"`);
	process.exit(samples.length ? 0 : 1);
})();
