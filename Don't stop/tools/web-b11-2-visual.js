// B11.2 real-browser visual acceptance: Stage 39 dense attacks and a Hell round, screenshotted.
//
// Usage: node tools/web-b11-2-visual.js <baseUrl> <outDir>
//
// WHY THIS EXISTS. `tests/B11ZoneVisual.gd` already reads pixels off real rendered frames, but it
// reads them in a NATIVE window. The delivered product is the Web export, and the two changes this
// round made are both about what the player SEES: an active footprint that no longer repaints, and
// the fog mirror moving from `_draw()` to `step()`. So the same two claims are also captured in the
// real delivered renderer, in the real browser, on the real GPU - as images a human can look at.
//
// WHAT IT CANNOT DECIDE. A still cannot show flicker or smoothness; that is what the consecutive
// frame series in `B11ZoneVisual` is for. These shots are for "does the picture still look right",
// and they are named by phase so the report can point at the exact frame it is talking about.
//
// It reuses the stress driver's own page protocol (`?stress=1`) rather than inventing a second one,
// so the load profile in the images is the same profile the measurement runs use.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const url = process.argv[2];
const outDir = process.argv[3] || '.';
if (!url) { console.error('usage: node web-b11-2-visual.js <baseUrl> <outDir>'); process.exit(2); }
fs.mkdirSync(outDir, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function capture(page, out, prefix, count, gapMs) {
	const files = [];
	for (let i = 0; i < count; i++) {
		await sleep(gapMs);
		const file = path.join(out, `${prefix}-${i + 1}.png`);
		await page.screenshot({ path: file });
		files.push(path.basename(file));
	}
	return files;
}

async function phase(browser, label, params, out, shots, rampMs, gapMs) {
	const context = await browser.newContext({ viewport: { width: 1280, height: 760 } });
	const page = await context.newPage();
	const errors = [];
	let ready = false;
	page.on('console', m => {
		const t = m.text();
		if (t.startsWith('[stress] effective scenario=')) ready = true;
		if (m.type() === 'error') errors.push(t);
	});
	page.on('pageerror', e => errors.push(String(e)));
	const q = new URLSearchParams(Object.assign({ stress: '1', scenario: 'D', stage: '39', seed: '20260918' }, params));
	await page.goto(`${url}?${q.toString()}`, { waitUntil: 'domcontentloaded', timeout: 60000 });
	// Wait for the driver to finish shaping its own load profile, then let the amplifiers ramp:
	// the whole point of profile D is that the picture is BUSY, and an empty arena proves nothing.
	const deadline = Date.now() + 90000;
	while (!ready && Date.now() < deadline) await sleep(250);
	if (!ready) {
		console.error(`[b11.2-visual] ${label}: the stress driver never announced its profile`);
		await context.close();
		return { label, files: [], errors, armed: false };
	}
	await sleep(rampMs);
	const files = await capture(page, out, label, shots, gapMs);
	await context.close();
	return { label, files, errors, armed: true };
}

const main = async () => {
	const browser = await chromium.launch({ args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'] });
	let gpu = '';
	try {
		const probe = await browser.newPage();
		await probe.goto('about:blank');
		gpu = await probe.evaluate(() => {
			const c = document.createElement('canvas');
			const gl = c.getContext('webgl');
			if (!gl) return 'no webgl';
			const ext = gl.getExtension('WEBGL_debug_renderer_info');
			return ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);
		});
		await probe.close();
	} catch (e) { gpu = 'probe failed: ' + e.message; }

	const result = { url, gpu, phases: [] };
	// Stage 39, worst-load profile: the case the human report is about.
	result.phases.push(await phase(browser, 'stage39-dense',
		{ stage: '39', seconds: '40', enemies: '80', lasers: '4', root: '2.0', barrage: '6', park: '1' },
		outDir, 5, 9000, 1000));
	// A Hell round: the fog mirror only exists there, and it is the layer the repaint change moved.
	result.phases.push(await phase(browser, 'hell-dense',
		{ stage: '33', seconds: '40', enemies: '60', lasers: '4', root: '1.5', barrage: '4', park: '1' },
		outDir, 4, 9000, 1200));
	await browser.close();

	fs.writeFileSync(path.join(outDir, 'b11-2-visual.json'), JSON.stringify(result, null, '\t'));
	console.log(`[b11.2-visual] gpu=${gpu}`);
	for (const p of result.phases) {
		console.log(`[b11.2-visual] ${p.armed ? 'OK' : 'NO-ARM'} ${p.label} shots=${p.files.length} console_errors=${p.errors.length} ${p.files.join(' ')}`);
		for (const e of p.errors.slice(0, 3)) console.log(`[b11.2-visual]   error: ${e}`);
	}
	const bad = result.phases.filter(p => !p.armed || p.errors.length);
	process.exit(bad.length ? 1 : 0);
};

main().catch(e => { console.error(e); process.exit(1); });
