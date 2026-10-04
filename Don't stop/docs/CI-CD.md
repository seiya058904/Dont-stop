# CI/CD stages and release identity

Routine target: PR safety in 3–5 minutes; main push to verified live Pages in at
most 6 minutes, preferably 5. Measure real runs, including runner queues, cache
misses, deployment and CDN verification. A timeout is a watchdog, not proof of
meeting the target.

## Daily PR safety

`deploy-pages.yml` checks scope, imports once, exports once and runs the existing
loader, smoke and one-cycle menu-return drivers. Browser drivers run concurrently
on the same runner with the same export and one Playwright installation. Their
original assertions and game timeouts remain intact; the first failure stops the
other driver. The menu driver still includes pause, save/reload and the final
restart after return. No game or test scene is modified.

Native suites: B194Contracts, P0SaveSanity, BaselineRegression, CombatReadability,
WeaponVisualPose, CampPresentation, CameraTransitions, B17Contracts, M3Weapons,
LegacyHpCompatibility and B17Saved. These include all eight former daily Web
preflight suites and all three former legacy-HP suites. P0SaveSanity runs once.
The standalone `verify-legacy-hp.yml` is removed.

The established `Stable preflight` and `Web required gate` check names remain as
small PR summaries. A failed/cancelled candidate cannot produce a passing summary.
Documentation-only changes complete the scope step and summaries without Godot,
Node, browser, export or deployment. Scope comparison fetches only the base
commit instead of all Git history; unknown/empty scope builds conservatively.

## Main release

One candidate runner: scope → cached engine/template → one checked import →
B194Contracts (boot resources and lazy script compilation) + P0SaveSanity →
final Web export → SHA/payload stamp → unchanged real loader + gameplay/input
smoke → recompute candidate identity → upload those tested bytes.

One production runner: deploy that Pages artifact → fetch live HTML and all
three payloads → verify build SHA, declared digest, per-file sizes/hashes and
aggregate SHA-256 → retain timestamped verification evidence. Production
verification is mandatory on every deploying push. CDN propagation has four
bounded attempts; stale SHA or mismatched bytes always fail. Browser behavior
is tested before deployment against exactly the artifact being published.

There is no rebuild, artifact download for daily browser gates, main menu-return,
main PR-summary dependency, or second browser installation on this path.
Production runs do not cancel each other mid-deployment/verification; PR updates
can supersede older PR runs. A docs-only push intentionally leaves the last
game release online; its build SHA is the last deploying commit.

PR checks must pass before merging code into main. Branch protection was absent
when audited; this change does not modify remote repository settings. Direct
main pushes receive the small release gate, not the full PR safety suite.

## Full acceptance

Both full workflows run manually, when a Release is published, and on the first
day of each month (Web at 03:17 UTC, native at 04:17 UTC), replacing daily full
acceptance. Release runs validate the release ref and do not redeploy production.
Manual Web deployment requires `deploy=true` on main and successful full gates.

Web: all six existing matrix entries: smoke, save-audit, aim-core, aim-fault,
menu-return and stages-fair. Menu-return defaults to one continuous 20-cycle
session plus restart; its 25-minute watchdog and 30-minute job budget remain.
Manual dispatch also offers the original five-cycle acceptance option. Matrix
fail-fast stops other gates after a failure; diagnostic uploads still run.

Native: every previous distinct contract, pressure and optional historical
invocation remains. Setup imports once, validates the import and transfers its
`.godot` state to contracts/pressure/historical consumers, which do not import
again. BaselineRegression/B17Contracts/M3Weapons no longer repeat in setup and
contracts. B194Contracts and LegacyHpCompatibility are included in contracts.
Existing pressure durations and historical informational-only policy remain.
Windows packaging stays a separate manual workflow.

## Caches and evidence

All Linux jobs share the pinned engine cache. Web caches only the extracted
notthreads release template instead of a roughly 600 MB multi-platform archive.
The browser cache contains pinned Playwright node_modules and Chromium; hosted
Ubuntu 24.04 supplies system libraries. Cache misses download the pinned tools,
and a cold cache must still pass actual browser execution.

Identity is SHA-256 of `index.wasm || index.pck || index.js`, with separate size
and SHA-256 records for each payload. Main verifies it locally after testing and
again from live Pages. `build-identity`, `candidate-evidence` and
`pages-verification-evidence` preserve diagnostic and release proof.

Before-refactor reference: main run 37163554212 at 49e3645 took 5m55s to workflow
completion, but skipped online identity verification. Earlier main runs took
6m22s, 6m35s and 8m25s with the same missing daily verification. The latest PR
Web run took 6m10s, alongside a separate 36-second legacy-HP workflow. New timings
must be taken from actual Actions timestamps and `verified-at.txt`, not estimates.
