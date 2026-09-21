'use strict';
// Real WebGL1/2 context lifecycle; tests the exact production cache installer.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

(async () => {
	const html = fs.readFileSync(process.argv[2] || path.join(__dirname, '../web/loader.html'), 'utf8');
	const begin = html.indexOf('(function installScissorStateCache()');
	const end = html.indexOf('})();', begin) + 5;
	if (begin < 0 || end < begin) throw new Error('cache installer missing');
	const browser = await chromium.launch({ args: ['--enable-unsafe-swiftshader'] });
	try {
		const page = await browser.newPage();
		await page.addInitScript({ content: html.slice(begin, end) });
		await page.goto('data:text/html,<title>SCISSOR lifecycle contract</title>');
		const rows = await page.evaluate(async () => {
			const result = [];
			for (const type of ['webgl', 'webgl2']) {
				const canvas = document.createElement('canvas');
				const other = document.createElement('canvas');
				const gl = canvas.getContext(type), gl2 = other.getContext(type);
				if (!gl || !gl2) throw new Error(type + ' unavailable');
				const row = { type, initial: gl.getParameter(gl.SCISSOR_TEST) === false };
				gl.enable(gl.SCISSOR_TEST);
				row.enabled = gl.getParameter(gl.SCISSOR_TEST) === true;
				row.multiple_contexts = gl2.getParameter(gl2.SCISSOR_TEST) === false;
				gl.disable(gl.SCISSOR_TEST);
				row.disabled = gl.getParameter(gl.SCISSOR_TEST) === false;
				gl.enable(gl.SCISSOR_TEST);
				const extension = gl.getExtension('WEBGL_lose_context');
				if (!extension) throw new Error('WEBGL_lose_context unavailable');
				const lost = new Promise(resolve => canvas.addEventListener('webglcontextlost', event => {
					event.preventDefault(); resolve();
				}, { once: true }));
				extension.loseContext();
				await Promise.race([lost, new Promise((_, reject) => setTimeout(() => reject(new Error('context loss timeout')), 5000))]);
				row.lost = gl.getParameter(gl.SCISSOR_TEST) === null;
				gl.enable(gl.SCISSOR_TEST);
				row.lost_enable = gl.getParameter(gl.SCISSOR_TEST) === null;
				const restored = new Promise(resolve => canvas.addEventListener('webglcontextrestored', resolve, { once: true }));
				await new Promise(resolve => setTimeout(resolve, 100));
				extension.restoreContext();
				await Promise.race([restored, new Promise((_, reject) => setTimeout(() => reject(new Error('context restore timeout')), 5000))]);
				row.restored_default = gl.getParameter(gl.SCISSOR_TEST) === false;
				gl.enable(gl.SCISSOR_TEST);
				row.restored_enable = gl.getParameter(gl.SCISSOR_TEST) === true;
				row.other_context_unchanged = gl2.getParameter(gl2.SCISSOR_TEST) === false;
				result.push(row);
			}
			return result;
		});
		console.log(JSON.stringify(rows, null, 2));
		if (!rows.every(row => Object.entries(row).every(([k, v]) => k === 'type' || v === true))) process.exitCode = 1;
	} finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
