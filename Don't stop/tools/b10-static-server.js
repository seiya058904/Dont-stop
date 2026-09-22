// B10 static server for the local Web export.
//
// Minimal, dependency-free, and it exists so the browser evidence is taken against a real HTTP
// origin rather than file:// (a Godot Web build needs fetch + WebAssembly streaming, and the
// loader's own query-parameter mapping only runs on a real page load).
//
// MIME types that matter: .wasm must be application/wasm or the engine falls back to a slow
// non-streaming instantiate, and .pck must not be sniffed as text.
//
// Usage: node tools/b10-static-server.js <root> <port> [--cache]
// --cache is only for an immutable startup candidate's warm-cache measurement.
const http = require('http');
const fs = require('fs');
const path = require('path');

const root = process.argv[2];
const port = parseInt(process.argv[3] || '8199', 10);
if (!root) { console.error('usage: node b10-static-server.js <root> <port>'); process.exit(2); }

const MIME = {
	'.html': 'text/html; charset=utf-8',
	'.js': 'text/javascript; charset=utf-8',
	'.mjs': 'text/javascript; charset=utf-8',
	'.wasm': 'application/wasm',
	'.pck': 'application/octet-stream',
	'.png': 'image/png',
	'.json': 'application/json; charset=utf-8',
	'.otf': 'font/otf',
	'.ttf': 'font/ttf',
	'.svg': 'image/svg+xml',
	'.css': 'text/css; charset=utf-8',
	'.zip': 'application/zip',
	'.map': 'application/json; charset=utf-8',
};

const server = http.createServer((req, res) => {
	let rel = decodeURIComponent(req.url.split('?')[0]);
	if (rel === '/' || rel === '') rel = '/index.html';
	const full = path.join(root, rel);
	if (!full.startsWith(path.resolve(root))) { res.writeHead(403).end('forbidden'); return; }
	fs.stat(full, (err, stat) => {
		if (err || !stat.isFile()) { res.writeHead(404).end('not found'); return; }
		res.writeHead(200, {
			'Content-Type': MIME[path.extname(full).toLowerCase()] || 'application/octet-stream',
			'Content-Length': stat.size,
			// The export uses the nothreads template, so cross-origin isolation is not required;
			// the headers are sent anyway because they are harmless here and they are what a
			// threaded build would need.
			'Cross-Origin-Opener-Policy': 'same-origin',
			'Cross-Origin-Embedder-Policy': 'require-corp',
			'Cache-Control': process.argv[4] === '--cache' ? 'public, max-age=60' : 'no-store',
		});
		fs.createReadStream(full).pipe(res);
	});
});
server.listen(port, '127.0.0.1', () => console.log(`[b10-static] serving ${root} at http://127.0.0.1:${port}/`));
