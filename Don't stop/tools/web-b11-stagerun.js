// B11 real-run verification: walk stages 31/35/39/40 in ONE browser session and read the evidence.
//
// Usage: node tools/web-b11-stagerun.js <url> [evidenceDir]
//
// The game does the walk (`?stage-tour=1`), because reaching four rows of a forty-row listing with
// wheel events is a renderer-dependent problem that produced no usable evidence across several
// attempts. What this script does is the part a page CAN do reliably: arm the read-only probe channel
// alongside the tour, collect the per-stage evidence lines and the live telegraph report, and assert
// on them.
'use strict';
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const url = process.argv[2];
const outDir = process.argv[3] || 'b11-stagerun-evidence';
if (!url) { console.error('usage: node web-b11-stagerun.js <url> [evidenceDir]'); process.exit(2); }
fs.mkdirSync(outDir, { recursive: true });

const sleep = ms => new Promise(r => setTimeout(r, ms));
const STAGES = [31, 35, 39, 40];
const tokens = [];
const notes = [];
const tourLines = [];
const zoneLines = [];
const perfLines = [];
const consoleErrors = [];
function token(name, ok, detail) {
	tokens.push({ name, ok: !!ok, detail: detail === undefined ? null : String(detail) });
	console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' :: ' + detail : ''}`);
}

(async () => {
	const started = Date.now();
	const browser = await chromium.launch({
		headless: true,
		args: ['--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist'],
	});
	const page = await (await browser.newContext({ viewport: { width: 1280, height: 760 } })).newPage();

	page.on('console', m => {
		const t = m.text();
		if (m.type() === 'error' && !t.startsWith('[probe]')) consoleErrors.push(t);
		if (t.startsWith('[stage-tour]')) { tourLines.push(t); console.log(t); return; }
		if (t.startsWith('[probe] zones ')) {
			const m = t.match(/^\[probe\] zones count=(\d+) rows=(.*)$/);
			if (m) zoneLines.push({ count: +m[1], rows: m[2] });
			return;
		}
		if (t.startsWith('[probe] perf ')) { perfLines.push(t.slice('[probe] perf '.length)); return; }
	});
	page.on('pageerror', e => consoleErrors.push('pageerror: ' + e.message));

	try {
		await page.goto(url + '?stage-tour=1&probe=1', { waitUntil: 'domcontentloaded', timeout: 60000 });
		// Four stages, ~9 s of real play each, plus the camp round trips.
		const deadline = Date.now() + 300000;
		while (Date.now() < deadline && !tourLines.some(l => l.includes('complete'))) await sleep(1000);
		const done = tourLines.some(l => l.includes('complete'));
		token('TOUR_REACHED_ITS_END', done, done ? 'the game printed the completion line' : 'the tour did not finish inside the budget');

		for (const stage of STAGES) {
			const line = tourLines.find(l => l.includes('stage=' + stage + ' departed='));
			token(`S${stage}_TOUR_LINE_PRESENT`, !!line, line || 'no line for this stage');
			if (!line) continue;
			const f = k => { const m = line.match(new RegExp(k + '=([^\\s]+)')); return m ? m[1] : null; };
			token(`S${stage}_DEPARTURE_WAS_ACCEPTED`, f('departed') === 'true', f('departed'));
			token(`S${stage}_REALLY_ENTERED_COMBAT`, f('state') === 'COMBAT', `state=${f('state')}`);
			token(`S${stage}_RAN_AS_THE_REQUESTED_STAGE`, f('level') === String(stage), `level=${f('level')}`);
			token(`S${stage}_HELL_DARKNESS_IS_APPLIED`, f('fog') === 'true', `fog=${f('fog')}`);
			token(`S${stage}_REALLY_SPAWNED_ENEMIES`, parseInt(f('monsters_peak'), 10) > 0, `peak=${f('monsters_peak')}`);
			token(`S${stage}_PLAYER_COULD_MOVE`, parseInt(f('moving_frames'), 10) > 0, `moving frames=${f('moving_frames')}`);
			token(`S${stage}_LEFT_THE_CAMPAIGN_POINTER_ALONE`, f('next') === '1', `next=${f('next')}`);
			token(`S${stage}_CLAIMED_NO_COMPLETION`, f('campaign') === 'false' && f('hell') === 'false',
				`campaign=${f('campaign')} hell=${f('hell')}`);
		}

		// ---- the laser, read off the game's own telegraph channel ------------------------------------
		// Each entry is `<mode>:<style>:a=<activated>:t=<seconds to fire>:w=<warning>:len=..:dir=x,y:frozen=0|1`.
		// Rows are `name=value` pairs joined by `;` inside a row joined by `|`, because a comma used to be
		// load-bearing inside the direction and any reader that split on it silently saw nothing.
		const seen = { frozen: 0, turnedWhileFrozen: 0, turnedDeclared: 0, fired: 0, lineSeen: 0, maxZones: 0, samples: zoneLines.length };
		const frozenDir = {};
		const turned = [];
		const lanes = [];
		for (const sample of zoneLines) {
			seen.maxZones = Math.max(seen.maxZones, sample.count);
			if (!sample.rows) continue;
			for (const entry of sample.rows.split('|')) {
				const fields = {};
				for (const pair of entry.split(';')) {
					const eq = pair.indexOf('=');
					if (eq > 0) fields[pair.slice(0, eq)] = pair.slice(eq + 1);
				}
				if (fields.mode !== 'line') continue;
				seen.lineSeen++;
				const remaining = parseFloat(fields.t);
				const frozen = fields.frozen === '1';
				const activated = fields.active === 'true';
				const dirX = parseFloat(fields.dx), dirY = parseFloat(fields.dy);
				// Identity matters: two lanes of the same length are otherwise indistinguishable, so a sequence
				// of samples from different lanes looks exactly like one lane turning.
				const key = String(fields.id);
				const sweeps = parseFloat(fields.sweep) !== 0;
				if (lanes.length < 8) lanes.push(`${fields.style} id=${key} len=${fields.len} t=${remaining.toFixed(2)} active=${activated} frozen=${frozen} sweep=${fields.sweep}`);
				if (frozen && remaining > 0) {
					seen.frozen++;
					if (frozenDir[key] && (Math.abs(frozenDir[key].x - dirX) > 0.02 || Math.abs(frozenDir[key].y - dirY) > 0.02) && turned.length < 6) {
						// A lane may only turn if the attack DECLARED a sweep. A static lane that turns is the
						// defect this batch removes; a declared sweep that turns is the authored mechanic.
						if (sweeps) seen.turnedDeclared++; else { seen.turnedWhileFrozen++; turned.push(`id=${key} len=${fields.len} ${frozenDir[key].x.toFixed(2)} -> ${dirX.toFixed(2)} with ${remaining.toFixed(2)}s left`); }
					}
					frozenDir[key] = { x: dirX, y: dirY };
				}
				if (activated && frozen) seen.fired++;
			}
		}
		notes.push(`zone report: ${seen.samples} samples, up to ${seen.maxZones} live footprints, ${seen.lineSeen} lane observations`);
		for (const l of lanes.slice(0, 4)) notes.push('  lane ' + l);
		token('C_LINE_FOOTPRINTS_WERE_OBSERVED', seen.lineSeen > 0, `${seen.lineSeen} lane observations across ${seen.samples} samples (up to ${seen.maxZones} live footprints)`);
		token('C_A_FROZEN_LANE_WAS_OBSERVED_WITH_TIME_TO_RUN', seen.frozen > 0, `${seen.frozen} samples of a frozen lane before it fired`);
		token('C_A_STATIC_FROZEN_LANE_NEVER_TURNED', seen.turnedWhileFrozen === 0,
			turned.join(' | ') || `no static frozen lane changed direction (${seen.turnedDeclared} samples from lanes that declare a sweep)`);
		token('C_A_FROZEN_LANE_FIRED_AT_ITS_FROZEN_GEOMETRY', seen.fired > 0, `${seen.fired} samples of a frozen lane in its active phase`);

		token('PERF_CHANNEL_WAS_LIVE', perfLines.length > 0, `${perfLines.length} one-second performance lines`);
		// The engine's audio worklet raises `currentTime` on a null node when the browser has not been
		// given a user gesture, which no automated run can provide. It is reported, and it is not an
		// assertion about this build.
		const audioOnly = consoleErrors.filter(e => /currentTime/.test(e));
		const realErrors = consoleErrors.filter(e => !/currentTime/.test(e));
		token('NO_PAGE_ERRORS', realErrors.length === 0, realErrors.slice(0, 3).join(' | ') || `${audioOnly.length} audio-autoplay notices ignored`);
	} catch (err) {
		token('DRIVER_COMPLETED', false, String(err && err.message));
	}

	const result = {
		url, wall_clock_ms: Date.now() - started, tokens, notes,
		tour_lines: tourLines, zone_samples: zoneLines.length, perf: perfLines,
		console_errors: consoleErrors.slice(0, 20),
	};
	fs.writeFileSync(path.join(outDir, 'b11-stagerun.json'), JSON.stringify(result, null, '\t'));
	try { await page.screenshot({ path: path.join(outDir, 'stagerun.png') }); } catch (e) { notes.push('screenshot failed: ' + e.message); }
	await browser.close();
	const failed = tokens.filter(t => !t.ok);
	console.log(`\nB11_STAGERUN tokens=${tokens.length} failures=${failed.length} wall_clock=${Math.round((Date.now() - started) / 1000)}s`);
	for (const f of failed) console.log('  FAIL ' + f.name + (f.detail ? ' :: ' + f.detail : ''));
	process.exit(failed.length ? 1 : 0);
})();
