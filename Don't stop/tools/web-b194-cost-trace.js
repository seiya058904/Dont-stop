'use strict';

// Separate, bounded diagnostic navigation AFTER acceptance measurement.
// No readPixels, GL wrappers, gameplay fixture, input or quality changes.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { chromium } = require('playwright');
const [url, outDir, buildDir] = process.argv.slice(2);
if (!url || !outDir || !buildDir) throw new Error('usage: web-b194-cost-trace.js <url> <outDir> <buildDir>');
fs.mkdirSync(outDir, { recursive: true });
const report = { diagnostic_only: true, url, platform: process.platform, assets: {}, lines: [], errors: [] };
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
let browser, timer;
async function capture() {
    const args = [...(process.platform === 'win32' ? ['--use-angle=d3d11'] : ['--enable-unsafe-swiftshader']),
        '--enable-gpu', '--ignore-gpu-blocklist', '--disable-background-timer-throttling',
        '--disable-backgrounding-occluded-windows', '--disable-renderer-backgrounding'];
    browser = await chromium.launch({ headless: true, args });
    report.browser = browser.version(); report.args = args;
    const context = await browser.newContext({ viewport: { width: 1536, height: 864 }, deviceScaleFactor: 1, serviceWorkers: 'block' });
    for (const name of ['index.wasm', 'index.pck', 'index.js']) {
        const expected = sha(fs.readFileSync(path.join(buildDir, name)));
        const response = await context.request.get(new URL(name, url).href);
        if (!response.ok()) throw new Error(`HTTP ${response.status()} for ${name}`);
        const actual = sha(await response.body());
        report.assets[name] = { expected, actual };
        if (actual !== expected) throw new Error(`artifact mismatch: ${name}`);
    }
    const page = await context.newPage();
    let ready = false;
    page.on('console', message => {
        const text = message.text();
        report.lines.push({ wall_ms: Date.now(), text });
        if (text.includes('[loader] revealing the running game (game-reported-ready)')) ready = true;
    });
    page.on('pageerror', error => report.errors.push(String(error)));
    const cdp = await browser.newBrowserCDPSession();
    await cdp.send('Tracing.start', {
        categories: 'toplevel,devtools.timeline,v8,blink,cc,gpu,disabled-by-default-gpu.service,disabled-by-default-devtools.timeline',
        transferMode: 'ReturnAsStream', streamCompression: 'gzip',
        options: 'record-until-full',
    });
    report.navigation_wall_ms = Date.now();
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    const deadline = Date.now() + 30000;
    while (!ready && Date.now() < deadline) await sleep(50);
    if (!ready) throw new Error('No game-ready notice within diagnostic bound');
    report.menu_sample_started_wall_ms = Date.now();
    await sleep(8000);
    report.menu_sample_ended_wall_ms = Date.now();
    const complete = new Promise(resolve => cdp.once('Tracing.tracingComplete', resolve));
    await cdp.send('Tracing.end');
    const event = await complete;
    report.trace_data_loss = !!event.dataLossOccurred;
    const chunks = []; let bytes = 0;
    try {
        while (true) {
            const chunk = await cdp.send('IO.read', { handle: event.stream, size: 1024 * 1024 });
            const buffer = Buffer.from(chunk.data, chunk.base64Encoded ? 'base64' : 'utf8');
            bytes += buffer.length;
            if (bytes > 100 * 1024 * 1024) throw new Error('Diagnostic trace exceeds 100 MiB bound');
            chunks.push(buffer);
            if (chunk.eof) break;
        }
    } finally { await cdp.send('IO.close', { handle: event.stream }); }
    fs.writeFileSync(path.join(outDir, 'browser-trace.json.gz'), Buffer.concat(chunks));
    report.trace_bytes = bytes;
    report.state = await page.evaluate(() => ({ loader: window.__dontStopState,
        build_sha: document.querySelector('meta[name="dontstop-build"]')?.content,
        artifact_digest: document.querySelector('meta[name="dontstop-artifact"]')?.content }));
    report.complete = true;
}
Promise.race([capture(), new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('Diagnostic exceeded 75 seconds')), 75000);
})]).catch(error => {
    report.error = String(error.stack || error); process.exitCode = 1;
}).finally(async () => {
    clearTimeout(timer);
    fs.writeFileSync(path.join(outDir, 'cost-trace.json'), JSON.stringify(report, null, 2));
    if (browser) await browser.close();
    console.log(JSON.stringify({ diagnostic_only: true, complete: !!report.complete,
        trace_bytes: report.trace_bytes, error: report.error }));
});
