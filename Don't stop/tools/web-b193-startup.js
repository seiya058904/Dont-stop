'use strict';

// B19.3 startup closure: real Chromium, real mouse input, and the loader's
// independent rAF/long-task trace. This intentionally does not arm Smoke or
// any gameplay stress driver, so the first-menu window remains a normal launch.
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { chromium } = require('playwright');

const baseUrl = process.argv[2];
const outDir = process.argv[3] || path.join(__dirname, '..', 'output', 'playwright', 'b19-3-startup');
if (!baseUrl) {
	console.error('usage: node web-b193-startup.js <url> [evidenceDir]');
	process.exit(2);
}
fs.mkdirSync(outDir, { recursive: true });

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const headed = process.env.B193_HEADLESS !== '1';
const viewport = { width: 1536, height: 864 };
const design = { width: 410, height: 230 };
const runCount = Number(process.env.B194_RUNS || 3);
const detailed = process.env.B194_EVIDENCE === '1';
const maxLoadMs = Number(process.env.B194_MAX_LOAD_MS || 120000);
if (!Number.isInteger(runCount) || runCount < 1) throw new Error('B194_RUNS must be a positive integer');

function sha256(buffer) {
	return crypto.createHash('sha256').update(buffer).digest('hex');
}

function localBuildIdentity() {
	const dir = process.env.B193_BUILD_DIR || path.join(__dirname, '..', 'build', 'web');
	const files = {};
	for (const name of ['index.wasm', 'index.pck', 'index.js']) {
		const file = path.join(dir, name);
		if (!fs.existsSync(file)) throw new Error(`missing local build file: ${file}`);
		const body = fs.readFileSync(file);
		files[name] = { bytes: body.length, sha256: sha256(body) };
	}
	files.identity = sha256(Buffer.from(['index.wasm', 'index.pck', 'index.js'].map(name => files[name].sha256).join('')));
	return files;
}

function snapshotState(page) {
	return page.evaluate(() => JSON.parse(JSON.stringify(window.__dontStopState || null)));
}

async function waitForLine(lines, pattern, timeoutMs, started = Date.now()) {
	while (Date.now() - started < timeoutMs) {
		const hit = lines.find(line => pattern.test(line.text));
		if (hit) return { ok: true, elapsed_ms: hit.wall_ms - started, line: hit.text };
		await sleep(40);
	}
	return { ok: false, elapsed_ms: Date.now() - started, line: null };
}

async function waitForReady(page, lines) {
	const started = Date.now();
	await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
	const ready = await page.waitForFunction(
		() => window.__dontStopState && window.__dontStopState.outcome === 'game-reported-ready',
		undefined,
		{ timeout: maxLoadMs },
	).then(() => true).catch(() => false);
	const readyWallMs = Date.now() - started;
	const canvasReady = await page.waitForSelector('#canvas-host canvas', { timeout: 30000 }).then(() => true).catch(() => false);
	return {
		ok: ready && canvasReady,
		wall_ms: readyWallMs,
		canvas_ready_wall_ms: Date.now() - started,
		post_ready_settle_ms: 0,
		state: await snapshotState(page),
		lines: lines.slice(),
	};
}

function pointInCanvas(rect, x, y) {
	return {
		x: rect.x + (x / design.width) * rect.width,
		y: rect.y + (y / design.height) * rect.height,
	};
}

async function clickDesign(page, rect, x, y) {
	const point = pointInCanvas(rect, x, y);
	await page.mouse.move(point.x, point.y);
	const started = Date.now();
	await page.mouse.down();
	await page.mouse.up();
	return started;
}

async function moveDesign(page, rect, x, y) {
	const point = pointInCanvas(rect, x, y);
	const started = Date.now();
	await page.mouse.move(point.x, point.y);
	return started;
}

async function capturePage(browser, label, interact, reuseContext) {
	const context = reuseContext || await browser.newContext({ viewport, deviceScaleFactor: 1, serviceWorkers: 'block' });
	const page = reuseContext ? (context.startupPage || (context.startupPage = await context.newPage())) : await context.newPage();
	await page.bringToFront();
	await page.addInitScript(() => {
		if (window.__startupVisibility) return;
		window.__startupVisibility = [{ t_ms: performance.now(), state: document.visibilityState }];
		document.addEventListener('visibilitychange', () => window.__startupVisibility.push({ t_ms: performance.now(), state: document.visibilityState }));
	});
	const lines = [];
	const pageErrors = [];
	const httpErrors = [];
	page.on('console', message => lines.push({
		wall_ms: Date.now(), type: message.type(), text: message.text(),
	}));
	page.on('pageerror', error => pageErrors.push(String(error.message || error)));
	page.on('requestfailed', request => httpErrors.push(`REQUEST_FAILED ${request.url()} ${request.failure()?.errorText || ''}`));
	page.on('response', response => {
		if (response.status() >= 400) httpErrors.push(`${response.status()} ${response.url()}`);
	});
	try {
		const ready = await waitForReady(page, lines);
		if (!ready.ok) {
			return { label, ready, lines, pageErrors, httpErrors };
		}
		const result = await interact(page, lines, ready);
		const timing = await page.evaluate(() => ({
			resources: performance.getEntriesByType('resource').map(e => e.toJSON()),
			navigation: performance.getEntriesByType('navigation').map(e => e.toJSON()),
			visibility: window.__startupVisibility,
			title: document.title,
			build_sha: document.querySelector('meta[name="dontstop-build"]')?.content,
			artifact_digest: document.querySelector('meta[name="dontstop-artifact"]')?.content,
		}));
		return {
			label,
			ready,
			result,
			timing,
			lines,
			pageErrors,
			httpErrors,
		};
	} catch (error) {
		return { label, error: String(error.stack || error), lines, pageErrors, httpErrors };
	} finally {
		page.removeAllListeners('console');
		page.removeAllListeners('pageerror');
		page.removeAllListeners('response');
		page.removeAllListeners('requestfailed');
		if (!reuseContext) await context.close();
	}
}

const reportPath = path.join(outDir, 'b193-web-startup.json');
const report = { url: baseUrl, headed, viewport, captured_at: new Date().toISOString(), WEB_STARTUP_GATE: 'FAIL' };
let browser;
(async () => {
	const local = localBuildIdentity();
	report.build = { local, served: {} };
	const launchOptions = {
		headless: !headed,
		args: [...(process.platform === 'win32' ? ['--use-angle=d3d11'] : ['--enable-unsafe-swiftshader']), '--enable-gpu', '--ignore-gpu-blocklist',
			'--disable-background-timer-throttling', '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding'],
	};
	browser = await chromium.launch(launchOptions);
	const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
	const served = report.build.served;
	for (const name of ['index.wasm', 'index.pck', 'index.js']) {
		const response = await context.request.get(new URL(name, baseUrl).href);
		if (!response.ok()) throw new Error(`HTTP ${response.status()} for ${name}`);
		const body = await response.body();
		served[name] = { bytes: body.length, sha256: sha256(body), matches_local: sha256(body) === local[name].sha256 };
		if (!served[name].matches_local) throw new Error(`served/local hash mismatch for ${name}`);
	}
	await context.close();

	const interact = async (page, lines) => {
		const rect = await page.locator('#canvas-host canvas').boundingBox();
		if (!rect) throw new Error('game canvas did not have a bounding box');
		const hoverAt = await moveDesign(page, rect, 41, 136);
		const hover = await waitForLine(lines, /\[startup\] stage=menu-first-hover/, 1500, hoverAt);
		const firstResponseAt = await page.evaluate(() => performance.now());
		const settingsAt = await clickDesign(page, rect, 41, 180);
		const settings = await waitForLine(lines, /\[startup\] stage=settings-feedback/, 3000, settingsAt);
		await clickDesign(page, rect, 153, 207.5); // close settings
		await sleep(250);
		const startAt = await clickDesign(page, rect, 41, 136);
		const start = await waitForLine(lines, /\[startup\] stage=first-start-feedback/, 4000, startAt);
		return {
			canvas: rect,
			hover,
			settings,
			start,
			first_response_nav_ms: firstResponseAt,
			state: await snapshotState(page),
		};
	};
	const cold = report.cold = [], warm = report.warm = [];
	for (let i = 0; i < runCount; i++) {
		// A new ordinary profile per cold run supplies a real disk HTTP cache.
		// Incognito contexts retransferred the large PCK/Wasm even on warm navigation.
		const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'dontstop-startup-'));
		const context = await chromium.launchPersistentContext(profile, {
			...launchOptions, viewport, deviceScaleFactor: 1, serviceWorkers: 'block',
		});
		context.startupPage = context.pages()[0];
		try {
			cold.push(await capturePage(browser, `cold-${i + 1}`, interact, context));
			// Same context and origin, with normal HTTP cache semantics. No routing,
			// cache-disabling headers or interception that secretly disables caching.
			warm.push(await capturePage(browser, `warm-${i + 1}`, interact, context));
		} finally { await context.close(); }
	}
	// Sample the undisturbed menu AFTER the cold runs, so this extra navigation
	// cannot precompile the first cold run's Wasm/shaders before timing it.
	const baseline = await capturePage(browser, 'baseline', async (page) => {
		const summary = await page.waitForFunction(
			() => window.__dontStopState?.frame?.summary,
			undefined, { timeout: 30000 },
		).then(() => true).catch(() => false);
		const state = await snapshotState(page);
		if (detailed) await page.screenshot({ path: path.join(outDir, 'b193-web-menu-baseline.png') });
		return { summary_observed: summary, state };
	});
	const interaction = cold[0];

	Object.assign(report, {
		url: baseUrl,
		headed,
		viewport,
		build: { local, served },
		baseline,
		interaction,
		cold,
		warm,
		captured_at: new Date().toISOString(),
	});
	const stats = runs => {
		const values = runs.map(run => run.result?.first_response_nav_ms);
		if (!values.every(Number.isFinite)) return { runs_ms: values, median_ms: null, max_ms: null };
		const sorted = values.slice().sort((a, b) => a - b);
		return { runs_ms: values, median_ms: sorted[Math.floor(sorted.length / 2)], max_ms: Math.max(...values) };
	};
	const coldStats = stats(cold), warmStats = stats(warm);
	const startupMs = coldStats.median_ms;
	const gate = baseline.ready?.ok && baseline.result?.summary_observed
		&& baseline.result?.state?.frame?.summary?.max_ms <= 250
		&& [...cold, ...warm].every(run => run.ready?.ok && !run.error
			&& ['hover', 'settings', 'start'].every(key => run.result?.[key]?.ok && run.result[key].elapsed_ms >= 0 && run.result[key].elapsed_ms <= 100)
			&& Number.isFinite(run.result?.first_response_nav_ms) && run.result.first_response_nav_ms <= 10000)
		&& [baseline, ...cold, ...warm].every(run => !run.pageErrors.length && !run.httpErrors.length
			&& !run.ready?.state?.errorMessage
			&& !run.lines.some(line => /SCRIPT ERROR:|^ERROR:/.test(line.text)));
	report.WEB_STARTUP_TO_INTERACTIVE_MENU_MS = startupMs;
	report.WEB_STARTUP_TARGET_MS = 5000;
	report.WEB_STARTUP_HARD_LIMIT_MS = 10000;
	report.WEB_STARTUP_GATE = gate ? 'PASS' : 'FAIL';
	report.PUBLIC_STARTUP = coldStats;
	report.WARM_STARTUP = warmStats;
	report.WARM_RESOURCE_CACHE = warm.map(run => ({
		label: run.label,
		files: ['index.wasm', 'index.pck'].map(name => {
			const entry = run.timing?.resources.find(e => new URL(e.name).pathname.endsWith('/' + name));
			return { name, transfer_bytes: entry?.transferSize ?? null,
				cache_hit: !!entry && entry.transferSize === 0 && entry.encodedBodySize > 0 };
		}),
	}));
	report.acceptance_sample_count = runCount;
	report.cache_protocol = 'Independent empty persistent profile per cold run; same page/profile warm navigation, normal HTTP cache headers, no routing or cache override.';
	fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
	console.log(JSON.stringify({
		report: reportPath,
		gate: report.WEB_STARTUP_GATE,
		cold: coldStats,
		warm: warmStats,
		baseline_ready_ms: baseline.ready && baseline.ready.wall_ms,
		baseline_frame_summary: baseline.result && baseline.result.state && baseline.result.state.frame && baseline.result.state.frame.summary,
		hover: interaction.result && interaction.result.hover,
		settings: interaction.result && interaction.result.settings,
		start: interaction.result && interaction.result.start,
		page_errors: [...(baseline.pageErrors || []), ...(interaction.pageErrors || [])],
		http_errors: [...(baseline.httpErrors || []), ...(interaction.httpErrors || [])],
	}, null, 2));
	if (!gate) process.exitCode = 1;
})().catch(error => {
	report.WEB_STARTUP_GATE = 'FAIL';
	report.fatal_error = String(error.stack || error);
	fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
	console.error('[b193-web-startup] FATAL', report.fatal_error);
	process.exitCode = 1;
}).finally(async () => {
	if (browser) await browser.close();
});
