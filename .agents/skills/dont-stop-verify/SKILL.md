---
name: dont-stop-verify
description: Use when running tests, verify.py tiers, manual preflight, Web/Windows exports, M10Bosses, or browser QA gates in the Don't stop Godot repository.
---

# Don't Stop Verification & Export Gates

All commands run from Git root with `"Don't stop/..."` quoted. Always pass `--godot <path>` (or set `$GODOT`, Godot `4.7.2-stable`) since the old workspace portable exe was deduplicated out of `archive/`.

## 1. `verify.py` Tiers
- `verify-fast`: preflight + core contracts + fast regressions (routine edits).
- `verify-native`: full 65 active native cases (59 contracts + 6 pressure, fail-closed, `3756` min checks).
- `verify-web`: single Web export + stamp + browser gates.
- `verify-full`: full native + full Web (incl. `web-save-durable.js` **90** checks).
- `verify-release`: full + Windows x64 export + packaged smoke.
- Local runs use `--jobs 1` and `--candidate` reuse (`output/verify-*`); never relax watchdogs/assertions for local CPU load; never share writable profiles or merge Godot processes.

## 2. Manual Preflight & Native Rules
- Preflight: Godot `--import`, `python3 "Don't stop/tools/b194_import_check.py"` (only first-import font/cursor early diagnostics allowed), `python3 "Don't stop/tools/test-verification-policy.py"`, `node "Don't stop/tools/stress-completion.test.js"`, `python3 "Don't stop/tools/test-menu-soak-policy.py"`.
- Full native acceptance: **never pass `--quit-after` or `--time-scale`** (frame limit can exit 0 prematurely); respect M6/M8 markers and 1800s/2400s budgets; `historical-evidence` is non-blocking.
- `M10Bosses`: run `full` isolated with `--fixed-fps 120` (standalone `only10/20/30` skips cross-boss checks); never nerf bosses, add HP, or pause DPS to pass.

## 3. Export, Stamp & Browser Gates
- Export presets (`export_presets.cfg`): `Web Release` and `Windows x64 Release`. Stamp once via `"Don't stop/tools/stamp-build-identity.py"` and test/deploy the exact stamped bytes.
- Run local HTTP server + Playwright `1.60.0` browser gates (`save-audit-web.js`, `web-save-durable.js`, menu soak, `web-b11-stagerun.js`, etc.) and live check via `"Don't stop/tools/verify-pages-deployment.js"`.
