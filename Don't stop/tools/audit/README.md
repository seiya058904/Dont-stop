# 2026-10-10 supplementary audit regressions

Run from the repository root. These checks supplement the original 64 active
native invocations; they do not replace any native or full Web acceptance gate.

```bash
python "Don't stop/tools/audit/verify-candidate-identity.py" "Don't stop/tools/verify.py"
node "Don't stop/tools/audit/web-confirm-byte-exact.cjs" "Don't stop/game/config/CampSaveStore.gd"
node "Don't stop/tools/audit/web-confirm-types.cjs" "Don't stop/game/config/CampSaveStore.gd"
node "Don't stop/tools/audit/web-confirm-real-idb.cjs" "Don't stop/game/config/CampSaveStore.gd" output/audit-idb
```

The first check executes the real verification orchestration with an observing
runner stub and a fake engine-version query. It deliberately starts no Godot
process. Twelve cases cover prepared/reused candidate identity, additional and
missing product files, engine identity, and the existing mutable docs/tools
policy. Fresh untracked product files must be staged before preparation.

The next two checks extract the production `WEB_CONFIRM` constant verbatim and
exercise it with a small asynchronous IndexedDB adapter. They cover four byte
identity cases and thirteen typed-view, diagnostic, and transaction cases. They
are JavaScript unit contracts, not browser acceptance.

The last check requires Playwright 1.60.0 and Chromium. Resolve Playwright using
`NODE_PATH` or `PLAYWRIGHT_MODULE`; an optional third argument selects a Chromium
executable. It uses a new local HTTP origin and browser context, real IndexedDB
transactions, and the unchanged production bridge and 18-second deadline.
Eleven cases include byte aliases, real read/write transaction aborts, missing
rows, and an exact row whose completion is observed after the hard deadline.
Its short intentional event-loop stall is a fault injection, not a performance
measurement. No existing game profile is opened.

Gameplay and save recovery regressions are integrated into the existing
`B11Fairness`, `B3Hazards`, `R1Persistence`, and `R1RecoveryUI` scenes. Their
original assertions, manifest entries, parameters, and watchdogs are retained.
