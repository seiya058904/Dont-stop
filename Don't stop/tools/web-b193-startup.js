'use strict';

// B19.3 startup closure: real Chromium, real mouse input, and the loader's
// independent rAF/long-task trace. This intentionally does not arm Smoke or
// any gameplay stress driver, so the first-menu window remains a normal launch.
const fs = require('fs');
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

async function waitForLine(lines, pattern, timeoutMs) {
	const started = Date.now();
	while (Date.now() - started < timeoutMs) {
		const hit = lines.find(line => pattern.test(line.text));
		if (hit) return { ok: true, elapsed_ms: Date.now() - started, line: hit.text };
		await sleep(40);
	}
	return { ok: false, elapsed_ms: Date.now() - started, line: null };
}

async function waitForReady(page, lines) {
	const started = Date.now();
	await page.goto(baseUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
	const ready = await page.waitForFunction(
		() => window.__dontStopState && window.__dontStopState.outcome === 'game-reported-ready',
		{ timeout: 120000 },
	).then(() => true).catch(() => false);
		await page.waitForSelector('#canvas-host canvas', { timeout: 30000 }).catch(() => {});
		await page.waitForTimeout(500);
	return {
		ok: ready,
		wall_ms: Date.now() - started,
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
	await sleep(100);
	await page.mouse.down();
	await sleep(110);
	await page.mouse.up();
}

async function moveDesign(page, rect, x, y) {
	const point = pointInCanvas(rect, x, y);
	await page.mouse.move(point.x, point.y);
	await sleep(180);
}

async function capturePage(browser, label, interact) {
	const context = await browser.newContext({ viewport, deviceScaleFactor: 1, serviceWorkers: 'block' });
	const page = await context.newPage();
	const lines = [];
	const pageErrors = [];
	const httpErrors = [];
	page.on('console', message => lines.push({
		wall_ms: Date.now(), type: message.type(), text: message.text(),
	}));
	page.on('pageerror', error => pageErrors.push(String(error.message || error)));
	page.on('response', response => {
		if (response.status() >= 400) httpErrors.push(`${response.status()} ${response.url()}`);
	});
	try {
		const ready = await waitForReady(page, lines);
		if (!ready.ok) {
			return { label, ready, lines, pageErrors, httpErrors };
		}
		const result = await interact(page, lines, ready);
		return {
			label,
			ready: { wall_ms: ready.wall_ms, state: ready.state },
			result,
			lines,
			pageErrors,
			httpErrors,
		};
	} finally {
		await context.close();
	}
}

(async () => {
	const local = localBuildIdentity();
	const browser = await chromium.launch({
		headless: !headed,
		args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'],
	});
	const context = await browser.newContext({ viewport, serviceWorkers: 'block' });
	const served = {};
	for (const name of ['index.wasm', 'index.pck', 'index.js']) {
		const response = await context.request.get(new URL(name, baseUrl).href);
		if (!response.ok()) throw new Error(`HTTP ${response.status()} for ${name}`);
		const body = await response.body();
		served[name] = { bytes: body.length, sha256: sha256(body), matches_local: sha256(body) === local[name].sha256 };
		if (!served[name].matches_local) throw new Error(`served/local hash mismatch for ${name}`);
	}
	await context.close();

	const baseline = await capturePage(browser, 'baseline', async (page, lines) => {
		const summary = await page.waitForFunction(
			() => window.__dontStopState && window.__dontStopState.frame && window.__dontStopState.frame.summary,
			{ timeout: 30000 },
		).then(() => true).catch(() => false);
		await page.screenshot({ path: path.join(outDir, 'b193-web-menu-baseline.png') });
		return { summary_observed: summary, state: await snapshotState(page) };
	});

	const interaction = await capturePage(browser, 'interaction', async (page, lines) => {
		const rect = await page.locator('#canvas-host canvas').boundingBox();
		if (!rect) throw new Error('game canvas did not have a bounding box');
		await page.screenshot({ path: path.join(outDir, 'b193-web-menu-before-input.png') });
		await moveDesign(page, rect, 41, 136); // hover without pressing the real start button
		const hover = await waitForLine(lines, /\[startup\] stage=menu-first-hover/, 1500);
		await clickDesign(page, rect, 41, 180); // settings
		const settings = await waitForLine(lines, /\[startup\] stage=settings-feedback/, 3000);
		await page.screenshot({ path: path.join(outDir, 'b193-web-settings.png') });
		await clickDesign(page, rect, 153, 207.5); // close settings
		await sleep(250);
		await clickDesign(page, rect, 41, 136); // start
		const start = await waitForLine(lines, /\[startup\] stage=first-start-feedback/, 4000);
		await page.screenshot({ path: path.join(outDir, 'b193-web-after-start.png') });
		return {
			canvas: rect,
			hover,
			settings,
			start,
			state: await snapshotState(page),
		};
	});

	const report = {
		url: baseUrl,
		headed,
		viewport,
		build: { local, served },
		baseline,
		interaction,
		captured_at: new Date().toISOString(),
	};
	const reportPath = path.join(outDir, 'b193-web-startup.json');
	fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
	console.log(JSON.stringify({
		report: reportPath,
		baseline_ready_ms: baseline.ready && baseline.ready.wall_ms,
		baseline_frame_summary: baseline.result && baseline.result.state && baseline.result.state.frame && baseline.result.state.frame.summary,
		hover: interaction.result && interaction.result.hover,
		settings: interaction.result && interaction.result.settings,
		start: interaction.result && interaction.result.start,
		page_errors: [...(baseline.pageErrors || []), ...(interaction.pageErrors || [])],
		http_errors: [...(baseline.httpErrors || []), ...(interaction.httpErrors || [])],
	}, null, 2));
	await browser.close();
})().catch(error => {
	console.error('[b193-web-startup] FATAL', error && error.stack ? error.stack : error);
	process.exit(1);
});
