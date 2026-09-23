// Verify that GitHub Pages serves the exact Web payload produced by this build.
// Gameplay and browser interaction are covered by the pre-deploy Web gates; this
// opt-in post-deploy check only validates published identity and bytes.
//
// Usage:
//   node verify-pages-deployment.js <pageUrl> <expectedBuildSha> <identityFile> [outDir]

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const [, , pageUrl, expectedSha, identityFile, outDir = '.'] = process.argv;
if (!pageUrl || !expectedSha || !identityFile) {
	console.error('usage: node verify-pages-deployment.js <pageUrl> <expectedBuildSha> <identityFile> [outDir]');
	process.exit(2);
}

fs.mkdirSync(outDir, { recursive: true });
const payloadNames = ['index.wasm', 'index.pck', 'index.js'];
const tokens = {};
const failures = [];
const notes = [];
const payloadResults = {};

function token(name, ok, detail = '') {
	tokens[name] = !!ok;
	if (!ok) failures.push(name);
	console.log(`[pages] ${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ` ${detail}` : ''}`);
}

function meta(html, name) {
	const match = html.match(new RegExp(`<meta name="${name}" content="([^"]*)"`));
	return match ? match[1] : null;
}

async function hashResponse(response, aggregateHash) {
	const hash = crypto.createHash('sha256');
	let bytes = 0;
	if (!response.body) return { sha256: hash.digest('hex'), bytes };
	for await (const chunk of response.body) {
		const data = Buffer.from(chunk);
		hash.update(data);
		aggregateHash.update(data);
		bytes += data.length;
	}
	return { sha256: hash.digest('hex'), bytes };
}

async function main() {
	const identity = JSON.parse(fs.readFileSync(identityFile, 'utf8'));
	const identityValid = identity.build_sha === expectedSha
		&& /^[a-f0-9]{64}$/.test(identity.artifact_digest || '')
		&& identity.digest_algo === 'sha256(index.wasm || index.pck || index.js)'
		&& payloadNames.every(name => identity.payload && identity.payload[name]
			&& /^[a-f0-9]{64}$/.test(identity.payload[name].sha256 || '')
			&& Number.isInteger(identity.payload[name].bytes));
	token('BUILD_IDENTITY_IS_VALID', identityValid,
		`build=${identity.build_sha || 'missing'} digest=${identity.artifact_digest || 'missing'}`);
	if (!identityValid) throw new Error('build identity is missing or does not match this workflow run');

	const requestOptions = () => ({ signal: AbortSignal.timeout(90000), redirect: 'follow' });
	let html = '';
	try {
		const pageResponse = await fetch(pageUrl, requestOptions());
		html = await pageResponse.text();
		token('DEPLOYED_PAGE_IS_SERVED', pageResponse.ok && html.length > 200,
			`HTTP ${pageResponse.status}, ${Buffer.byteLength(html)} bytes`);
	} catch (error) {
		token('DEPLOYED_PAGE_IS_SERVED', false, error.message);
	}

	const deployedSha = meta(html, 'dontstop-build');
	const deployedDigest = meta(html, 'dontstop-artifact');
	notes.push(`deployed page declares build=${deployedSha} artifact=${deployedDigest}`);
	token('DEPLOYED_PAGE_MATCHES_THIS_BUILD', deployedSha === expectedSha,
		`deployed=${deployedSha} expected=${expectedSha}`);
	token('DEPLOYED_PAGE_MATCHES_THIS_ARTIFACT', deployedDigest === identity.artifact_digest,
		`deployed=${deployedDigest} expected=${identity.artifact_digest}`);

	const baseUrl = new URL('.', pageUrl);
	const aggregateHash = crypto.createHash('sha256');
	for (const name of payloadNames) {
		const expected = identity.payload[name];
		try {
			const response = await fetch(new URL(name, baseUrl), requestOptions());
			const actual = await hashResponse(response, aggregateHash);
			const served = response.ok && actual.bytes > 1024;
			payloadResults[name] = { status: response.status, ...actual };
			token(`RESOURCE_${name.replace(/[^a-z0-9]/gi, '_').toUpperCase()}_IS_SERVED`, served,
				`HTTP ${response.status}, ${actual.bytes} bytes`);
			token(`RESOURCE_${name.replace(/[^a-z0-9]/gi, '_').toUpperCase()}_MATCHES_BUILD`,
				served && actual.bytes === expected.bytes && actual.sha256 === expected.sha256,
				`sha256=${actual.sha256} expected=${expected.sha256}`);
		} catch (error) {
			payloadResults[name] = { error: error.message };
			token(`RESOURCE_${name.replace(/[^a-z0-9]/gi, '_').toUpperCase()}_IS_SERVED`, false, error.message);
			token(`RESOURCE_${name.replace(/[^a-z0-9]/gi, '_').toUpperCase()}_MATCHES_BUILD`, false, 'resource could not be verified');
		}
	}

	const aggregateDigest = aggregateHash.digest('hex');
	token('DEPLOYED_PAYLOAD_MATCHES_BUILD_DIGEST', aggregateDigest === identity.artifact_digest,
		`sha256=${aggregateDigest} expected=${identity.artifact_digest}`);

	const result = {
		pageUrl,
		expectedBuildSha: expectedSha,
		expectedArtifactDigest: identity.artifact_digest,
		deployedBuildSha: deployedSha,
		deployedArtifactDigest: deployedDigest,
		payload: payloadResults,
		aggregatePayloadDigest: aggregateDigest,
		tokens,
		notes,
		result: failures.length ? 'FAIL' : 'PASS',
		failures,
	};
	fs.writeFileSync(path.join(outDir, 'pages-deployment-verification.json'), JSON.stringify(result, null, 2));
	console.log(`[pages] RESULT=${result.result}${failures.length ? ` (${failures.join(',')})` : ''}`);
	console.log(`[pages] build=${expectedSha} artifact=${identity.artifact_digest}`);
	return failures.length ? 1 : 0;
}

main().then(code => { process.exitCode = code; }).catch(error => {
	console.error(`[pages] RESULT=FAIL ${error.stack || error.message}`);
	try {
		fs.writeFileSync(path.join(outDir, 'pages-deployment-verification.json'), JSON.stringify({
			pageUrl, expectedBuildSha: expectedSha, result: 'FAIL', error: error.message,
		}, null, 2));
	} catch { /* keep the original verification failure visible */ }
	process.exitCode = 1;
});
