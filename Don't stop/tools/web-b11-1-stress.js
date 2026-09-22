// B11 dense-attack stress measurement, in a real browser, against a real Web export.
//
// Usage:
//   node tools/web-b11-1-stress.js <baseUrl> <evidenceDir> <label> <scenario> [key=value ...]
//
//   scenario   A | B | C | D | P                 (see game/diag/B11Stress.gd)
//   key=value  stage=39 seconds=90 seed=20260918 lasers=4 root=2.0 park=1 pressure_births=4
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
	const query = Object.assign({ label, stress: '1', scenario, stage: '39', seconds: '90', seed: '20260918' }, overrides);
	const url = `${base}?` + new URLSearchParams(Object.entries(query).map(([k, v]) => [k, String(v)])).toString();
	const spikes = [];
	const buckets = [];
	const markers = [];
	let summary = null;
	let convergence = null;
	let captureCount=0;
	const visualQueue=[];
	const visualStates=[];
	let visualDone=false;
	let peak = null;
	let cpu = null;
	// B11.2 adds two report lines. They are parsed separately instead of growing `[stress-peak]`, so
	// a B11.1-era consumer of this JSON keeps reading exactly the fields it always read.
	let load = null;
	let ink = null;
	let loadBuild = null;
	let settling = null;
	let steady = null;
	let pressureFrames = null;
	let benchmark = null;
	let rawFrames = null;
	const errors = [];
	// Every line the page printed, bounded. The engine's own script errors arrive here, and a
	// harness that reports "no summary line" without showing them is how a whole measurement round
	// gets spent guessing.
	const allConsole = [];

	const browser = await chromium.launch({
		headless: process.env.B19_HEADLESS === "1",
		args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist', '--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding'],
	});
	let memoryProcess = null;
	const memoryFile = path.resolve(outDir,`process-memory-${label}.json`);
	if (process.env.B192_MEMORY === '1') {
		const session = await browser.newBrowserCDPSession();
		const info = await session.send('SystemInfo.getProcessInfo');
		const root = info.processInfo.find(p => p.type === 'browser');
		if (!root) throw new Error('Cannot identify owned browser process');
		memoryProcess = require('child_process').spawn('python',[path.join(__dirname,'b192-process-memory.py'),String(root.id),memoryFile],{stdio:'ignore',windowsHide:true});
		await session.detach();
	}
	const viewport = {width:Number(process.env.B192_WIDTH || 1536),height:Number(process.env.B192_HEIGHT || 864)};
	const context = await browser.newContext({ viewport, deviceScaleFactor:1, serviceWorkers:'block' });
	const page = await context.newPage();
	await page.addInitScript(() => {
		const trace = window.__b194Frames = { gaps: [], ends: [], longTasks: [], visibility: [] };
		let last = null;
		const tick = now => {
			if (last !== null) { trace.gaps.push(now - last); trace.ends.push(now); }
			last = now;
			requestAnimationFrame(tick);
		};
		requestAnimationFrame(tick);
		document.addEventListener('visibilitychange', () => trace.visibility.push({ t: performance.now(), state: document.visibilityState }));
		new PerformanceObserver(list => {
			for (const e of list.getEntries()) trace.longTasks.push({ start_ms: e.startTime, duration_ms: e.duration });
		}).observe({ type: 'longtask', buffered: true });
	});

	// Chromium happily reuses a cached index.pck across page loads, which made a freshly exported
	// build invisible to earlier rounds of this project: the measurement was of the PREVIOUS build
	// and the only symptom was a missing line.
	const loadedResources = [];
	const verified = {};
	for (const name of ['index.wasm','index.pck','index.js']) {
		const resourceUrl = new URL(name,base).href;
		const response = await context.request.get(resourceUrl);
		if (!response.ok()) throw new Error(`HTTP ${response.status()}: ${resourceUrl}`);
		const body = await response.body();
		const sha256 = crypto.createHash('sha256').update(body).digest('hex');
		if (sha256 !== build[name]?.sha256) throw new Error(`served/local hash mismatch: ${name}`);
		verified[resourceUrl] = {body,contentType:response.headers()['content-type'],sha256};
	}
	await page.route('**/*', async route => {
		const asset = verified[route.request().url()];
		if (asset) {
			loadedResources.push({url:route.request().url(),sha256:asset.sha256,bytes:asset.body.length});
			await route.fulfill({status:200,body:asset.body,contentType:asset.contentType});
		} else await route.continue();
	});

	page.on('console', m => {
		const t = m.text();
		if(t.startsWith('B192_VISUAL ')) { const state=JSON.parse(t.slice(12)); visualStates.push(state); visualQueue.push(state.name); }
		if(t==='B192_VISUAL_DONE') visualDone=true;
		if (m.type() === "error" || t.startsWith("[stress] ")) console.log(t);
		if (t.startsWith('ERROR:') || t.startsWith('SCRIPT ERROR:')) errors.push(t);
		if (t.startsWith('[stress-convergence] ')) convergence=JSON.parse(t.slice('[stress-convergence] '.length));
		if (t.startsWith('[stress-frames] ')) {
			rawFrames = JSON.parse(t.slice('[stress-frames] '.length));
			return; // Store once, outside the bounded human-readable console log.
		}
		if (t.startsWith('[stress-pressure-frames] ')) {
			pressureFrames = JSON.parse(t.slice('[stress-pressure-frames] '.length));
			return; // Store the phase arrays outside the bounded human-readable console log.
		}
		if (allConsole.length < 600) allConsole.push(`${m.type()}: ${t}`);
		if (t.startsWith('[spike] ')) spikes.push(parseKv(t.slice('[spike] '.length)));
		else if (t.startsWith('[stress-bucket] ')) buckets.push(parseKv(t.slice('[stress-bucket] '.length)));
		else if (t.startsWith('[stress-summary] ')) { summary = parseKv(t.slice('[stress-summary] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-cpu] ')) { cpu = parseKv(t.slice('[stress-cpu] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-peak] ')) { peak = parseKv(t.slice('[stress-peak] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-load] ')) { load = parseKv(t.slice('[stress-load] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-load-build] ')) { loadBuild = parseKv(t.slice('[stress-load-build] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-settling] ')) { settling = parseKv(t.slice('[stress-settling] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-steady] ')) { steady = parseKv(t.slice('[stress-steady] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-benchmark] ')) { benchmark = parseKv(t.slice('[stress-benchmark] '.length)); markers.push(t); }
		else if (t.startsWith('[stress-ink] ')) { ink = parseKv(t.slice('[stress-ink] '.length)); markers.push(t); }
		else if (t.startsWith('[stress] ') || t.startsWith('[stress-')) markers.push(t);
	});
	page.on('pageerror', e => errors.push(e.stack || e.message));

	const gpu = await page.evaluate(() => {
		const c = document.createElement('canvas');
		const gl = c.getContext('webgl2') || c.getContext('webgl');
		if (!gl) return null;
		const dbg = gl.getExtension('WEBGL_debug_renderer_info');
		return dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
	}).catch(() => null);

	const visibilityEvents = [];
	await page.exposeFunction('b191Visibility', value => visibilityEvents.push(value));
	await page.addInitScript(() => {
		const report = () => window.b191Visibility({time:performance.now(),visibility:document.visibilityState,focus:document.hasFocus(),dpr:devicePixelRatio});
		document.addEventListener('visibilitychange',report); window.addEventListener('focus',report); window.addEventListener('blur',report);
	});
	const traceSession = process.env.B192_TRACE === '1' ? await context.newCDPSession(page) : null;
	const traceEvents = [];
	if (traceSession) {
		traceSession.on('Tracing.dataCollected', value => traceEvents.push(...value.value));
		await traceSession.send('Tracing.start',{categories:'devtools.timeline,v8,disabled-by-default-v8.cpu_profiler,blink.user_timing,gpu',options:'sampling-frequency=1000'});
	}
	if (traceSession) await page.addInitScript(() => {
		window.b192ShaderWaits = []; window.b192GlSizes = {};
		window.b192GlParameters = {total:0,byPname:{},slow:[],stacks:[]};
		const sources = new WeakMap(), programs = new WeakMap();
		for (const type of [WebGLRenderingContext,WebGL2RenderingContext]) {
			const proto=type.prototype;
			for (const name of ['viewport','texImage2D','texStorage2D','renderbufferStorage']) {
				const fn=proto[name]; if (!fn) continue;
				proto[name]=function(...args){const key=name+':'+args.filter(a=>typeof a==='number').join(',');window.b192GlSizes[key]=(window.b192GlSizes[key]||0)+1;return fn.apply(this,args);};
			}
			const source=proto.shaderSource, attach=proto.attachShader, query=proto.getProgramParameter;
			proto.shaderSource=function(shader,text){sources.set(shader,text);return source.call(this,shader,text);};
			proto.attachShader=function(program,shader){const list=programs.get(program)||[];list.push(shader);programs.set(program,list);return attach.call(this,program,shader);};
			proto.getProgramParameter=function(program,key){const start=performance.now();const value=query.call(this,program,key);const duration=performance.now()-start;if(duration>10)window.b192ShaderWaits.push({start,duration,key,sources:(programs.get(program)||[]).map(s=>sources.get(s))});return value;};
			const getParameter=proto.getParameter;
			if (getParameter) proto.getParameter=function(...args){
				const started=performance.now();
				try { return getParameter.apply(this,args); }
				finally {
					const duration=performance.now()-started;
					const key=String(args[0]);
					const bucket=window.b192GlParameters.byPname[key] || {count:0,total_ms:0,max_ms:0};
					bucket.count += 1; bucket.total_ms += duration; bucket.max_ms = Math.max(bucket.max_ms,duration);
					window.b192GlParameters.byPname[key]=bucket;
					window.b192GlParameters.total += 1;
					if (duration > 0.5 && window.b192GlParameters.slow.length < 128) window.b192GlParameters.slow.push({pname:key,duration_ms:duration});
					if (duration > 0.5 && window.b192GlParameters.stacks.length < 32) window.b192GlParameters.stacks.push({pname:key,duration_ms:duration,stack:(new Error()).stack});
				}
			};
		}
	});
	const started = Date.now();
	await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
	await page.bringToFront();
	await page.locator('canvas').click({ position: { x: 12, y: 12 }, timeout: 60000 });
	// A round is 45 s and the driver runs rounds until the requested window is covered, so the wall
	// clock bound has to allow the boot plus the whole accumulation plus a margin.
	const wallBudgetMs = ((parseInt(query.seconds, 10) || 90) + 240) * 1000;
	while (Date.now() - started < wallBudgetMs && !visualDone && (summary === null || (query.camp_cycles && convergence === null))) {
		await sleep(1000);
		while(visualQueue.length) await page.screenshot({path:path.join(outDir,`${label}-${visualQueue.shift()}.png`)});
		if (process.env.B192_CAPTURE === '1' && captureCount < 5 && allConsole.some(t=>t.includes('depart=true'))) {
			await page.screenshot({path:path.join(outDir,`capture-${label}-${captureCount++}.png`)});
		}
	}
	const browserTiming = await page.evaluate(() => ({ ...window.__b194Frames,
		marks: performance.getEntriesByType('mark').filter(e => e.name.startsWith('b194-')).map(e => e.toJSON()),
		meaning: 'requestAnimationFrame wall intervals, not GPU present completion',
	})).catch(() => null);
	const surface = await page.evaluate(() => ({visibility:document.visibilityState,focus:document.hasFocus(),dpr:devicePixelRatio,canvas:[...document.querySelectorAll('canvas')].map(c=>({width:c.width,height:c.height,cssWidth:c.getBoundingClientRect().width,cssHeight:c.getBoundingClientRect().height}))})).catch(()=>null);
	if (traceSession) {
		fs.writeFileSync(path.join(outDir,`shader-waits-${label}.json`),JSON.stringify(await page.evaluate(()=>window.b192ShaderWaits)));
		fs.writeFileSync(path.join(outDir,`gl-sizes-${label}.json`),JSON.stringify(await page.evaluate(()=>window.b192GlSizes)));
		fs.writeFileSync(path.join(outDir,`gl-parameters-${label}.json`),JSON.stringify(await page.evaluate(()=>window.b192GlParameters)));
		const completed = new Promise(resolve=>traceSession.once('Tracing.tracingComplete',resolve));
		await traceSession.send('Tracing.end'); await completed;
		fs.writeFileSync(path.join(outDir,`trace-${label}.json`),JSON.stringify({traceEvents}));
	}
	await browser.close();
	if (memoryProcess) {
		await Promise.race([new Promise(resolve=>memoryProcess.once('exit',resolve)),sleep(5000)]);
		if (memoryProcess.exitCode === null) memoryProcess.kill();
	}
	if (rawFrames && !rawFrames.memory_static_available) {
		if (peak) { peak.memory_static = null; peak.orphans = null; }
		if (load) { load.mem_peak_mb = null; load.orphans_peak = null; }
	}
	if (rawFrames && pressureFrames) {
		rawFrames.pressure = pressureFrames;
		rawFrames.pressure_measurement_valid = pressureFrames.pressure_measurement_valid;
	}

	const n = k => (summary && Number.isFinite(parseFloat(summary[k])) ? parseFloat(summary[k]) : null);
	const p = k => (peak && Number.isFinite(parseFloat(peak[k])) ? parseFloat(peak[k]) : null);
	const report = {
		browserTiming,
		visualStates, visualDone,
		label, scenario, convergence, loadedResources, server_root:process.env.B11_BUILD_DIR, surface, visibilityEvents, source_variant: query.source || "unspecified", workload_scenario: scenario, url, build, gpu, errors,
		process_memory: fs.existsSync(memoryFile) ? JSON.parse(fs.readFileSync(memoryFile,"utf8")) : null,
		headed: process.env.B19_HEADLESS !== "1", browser_version: browser.version(), viewport,
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
		load,
		ink,
		load_build: loadBuild,
		settling,
		steady,
		pressure: pressureFrames,
		benchmark,
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
	if (pressureFrames) {
		const projectileMode = pressureFrames.projectile_target_mode || 'legacy';
		console.log(`  pressure phase=${pressureFrames.phase} enemy_target=${pressureFrames.target_enemies} projectile_target_mode=${projectileMode} ` +
			`time_to_target_s=${f(pressureFrames.time_to_target_s)} steady_s=${f(pressureFrames.steady_seconds)} ` +
			`steady_p95=${f(steady && steady.p95)} steady_p99=${f(steady && steady.p99)} ` +
			`over16_67=${steady && steady.over16_67} over25=${steady && steady.over25} over33=${steady && steady.over33} ` +
			`over50=${steady && steady.over50} max=${f(steady && steady.max)} valid=${pressureFrames.pressure_measurement_valid}`);
	}
	if (benchmark) {
		console.log(`  benchmark average_fps=${f(benchmark.average_fps)} p50=${f(benchmark.p50)} p95=${f(benchmark.p95)} ` +
			`p99=${f(benchmark.p99)} 1pct_low_fps=${f(benchmark['1pct_low_fps'])} max=${f(benchmark.max)}`);
	}
	for (const b of buckets) {
		console.log(`  bucket[${b.family}] ${b.name} n=${b.n} share=${f(b.share)} avg=${f(b.avg)} p95=${f(b.p95)} p99=${f(b.p99)} max=${f(b.max)} over33=${b.over33} over50=${b.over50}`);
	}
	const pressureOk = scenario !== 'P' || Boolean(pressureFrames && pressureFrames.pressure_measurement_valid);
	process.exit((summary || visualDone) && !errors.length && !rawFrames?.measurement_timeout && pressureOk ? 0 : 1);
})();
