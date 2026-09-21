'use strict';
// Isolated UI contract, not a real-game startup/performance result.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

(async () => {
	const browser = await chromium.launch({ headless: true });
	try {
		let html = fs.readFileSync(path.join(__dirname, '../web/loader.html'), 'utf8')
			.replace('$GODOT_HEAD_INCLUDE', '').replace('$GODOT_CONFIG', '{}')
			.replace(/<script src="\$GODOT_URL"[^>]*><\/script>/, '');
		const mock = `<script>class Engine { startGame(options) { window.testProgress = options.onProgress; return new Promise(resolve => window.testEngineStarted = resolve); } static isWebGLAvailable() { return true; } }</script>`;
		html = html.replace('<script>', mock + '<script>');
		for (const width of [1536, 390]) {
			const page = await browser.newPage({ viewport: { width, height: 864 } });
			await page.setContent(html);
			await page.evaluate(() => testProgress(100, 100));
			let state = await page.evaluate(() => window.__dontStopState);
			assert.equal(state.completedStageFraction, 1 / 3, 'download completion is not boot completion');
			assert.equal(state.overlayRemovedAt, null);
			assert.ok(!(await page.locator('#status').textContent()).includes('100%'));
			await page.evaluate(() => testEngineStarted());
			await page.evaluate(() => window.__dontStop.stage('scene-prep'));
			await page.evaluate(() => testProgress(50, 100));
			state = await page.evaluate(() => window.__dontStopState);
			assert.equal(state.completedStageFraction, 2 / 3, 'late download reports cannot regress progress');
			const bounds = await page.locator('#bar').boundingBox();
			assert.ok(bounds.x >= 0 && bounds.x + bounds.width <= width);
			await page.evaluate(() => window.__dontStop.ready());
			state = await page.evaluate(() => window.__dontStopState);
			assert.equal(state.completedStageFraction, 1);
			assert.equal(state.outcome, 'game-reported-ready');
			assert.ok(state.overlayRemovedAt - state.readyNoticeAt < 20, 'no artificial completion wait');
			await page.close();
		}
		console.log('PASS loader: real-stage monotonic progress, no early 100%, immediate ready handover, desktop/mobile bounds');
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
