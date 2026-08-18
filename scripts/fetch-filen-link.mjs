#!/usr/bin/env node
// Download a Filen public share link without a browser.
//
// KonstaKANG hosts its LineageOS zips on Filen (app.filen.io), whose share
// links are end-to-end encrypted: the URL fragment carries the decryption
// key, so the file cannot simply be curled. The official SDK exposes the
// same anonymous link-info + chunked-download path the web app uses, which
// is what this script drives.
//
// Usage: node fetch-filen-link.mjs <share-url> <output-file>
//
// Needs @filen/sdk resolvable from this file (npm install --no-save
// @filen/sdk in the repo root works).

import { FilenSDK } from "@filen/sdk";

const [link, dest] = process.argv.slice(2);
if (!link || !dest) {
	console.error("usage: fetch-filen-link.mjs <share-url> <output-file>");
	process.exit(1);
}

// https://app.filen.io/#/d/<uuid>%23<key> (the %23 stays percent-encoded
// inside the fragment; older links use a literal #).
const m = link.match(/#\/d\/([0-9a-f-]{36})(?:%23|#)([^&?#]+)/i);
if (!m) {
	console.error(`cannot parse a Filen share link out of: ${link}`);
	process.exit(1);
}
const uuid = m[1];
let key = decodeURIComponent(m[2]);
// New-style links hex-encode the 32-character key.
if (key.length === 64 && /^[0-9a-fA-F]+$/.test(key)) {
	key = Buffer.from(key, "hex").toString("utf8");
}

const sdk = new FilenSDK({});
const info = await sdk.cloud().filePublicLinkInfo({ uuid, key });
console.error(`downloading ${info.name} (${info.size} bytes, ${info.chunks} chunks)`);

let lastPercent = -10;
let transferred = 0;
await sdk.cloud().downloadFileToLocal({
	uuid: info.uuid,
	bucket: info.bucket,
	region: info.region,
	chunks: info.chunks,
	version: info.version,
	key,
	size: info.size,
	to: dest,
	onProgress: (bytes) => {
		transferred += bytes;
		const percent = Math.floor((transferred / info.size) * 100);
		if (percent >= lastPercent + 10) {
			lastPercent = percent;
			console.error(`  ${percent}%`);
		}
	},
});
console.error(`saved to ${dest}`);
process.exit(0);
