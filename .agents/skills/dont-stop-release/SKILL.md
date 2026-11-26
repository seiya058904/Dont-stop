---
name: dont-stop-release
description: Use ONLY when explicitly authorized to prepare, execute, or audit a Release, patch tag, Windows/Web ZIPs, or GitHub Pages delivery in Don't stop.
---

# Don't Stop Release & Delivery Procedure

- Create non-draft patch tags only on verified `main` commits; reuse the exact tested & stamped Pages artifact (never rebuild the same SHA into mismatched bytes).
- Download back published Windows/Web ZIPs and verify SHA-256 sums against release checksums; verify live Pages via `"Don't stop/tools/verify-pages-deployment.js"` (SHA + combined `index.wasm || index.pck || index.js` + per-file hashes).
- Link provenance records, retain failed attempt logs honestly, and never fabricate zero-warning reports.
