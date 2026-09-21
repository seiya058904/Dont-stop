# B19.4 — work in progress

The full objective remains open. Draft PR #17 is under CI verification; no merge, deployment or final candidate acceptance has been performed.

| Item | Before | Current evidence | Target | Status |
|---|---:|---:|---|---|
| Public cold startup | 52.5–60.1 s (supplied CI evidence) | Not tested after deployment | median ≤5 s, hard ≤10 s | Pending |
| Local cold contexts | Old local artifact ready 10.36 s | 5.958 / 5.851 / 5.792 s; median 5.851 s, independent browser profiles | ≤10 s | Diagnostic only |
| Local warm navigation | — | median 2.300 s; all three WASM/PCK cache hits verified | ≤3 s | Local diagnostic PASS |
| Real menu interactions | Old hover marker only observed mouse movement | Start-button hover, Settings, Start all <100 ms in startup-cold-first | <100 ms | Local diagnostic PASS |
| Menu 10 s | Old local artifact had 1 s intervals, not yet attributed | max 18.79 ms, over50=0 | No freeze | Local diagnostic PASS |
| Native full workflow | 18m56s | Workflow changes not yet run in GitHub | ≤10 min required | Pending |
| Web workflow to online | 10m45s | Workflow changes not yet run in GitHub | ≤10 min | Pending |
| Local L1 | No bounded affected runner | 23.828 s, 5 contracts plus import | ≤120 s | Measured PASS; rerun final candidate |
| Local L2 | No bounded affected runner | 158.515 s, 7 contracts + startup/smoke/menu-return | ≤300 s | Measured PASS; rerun final candidate |
| Web first-use P max | 1224.125 ms | 75.24 ms after measured Canvas preparation; diagnostic load only | Explain >50 ms; remove freezes | Not accepted |
| Formal H/M/B/P, three surfaces | Prior B19.3 remains not attained | Not run; candidate not stable | Original gates retained | Pending |

## Confirmed findings and retained experiments

1. Full Web warmup gated the drawn menu and synchronously compiled many gameplay variants. Web no longer schedules that full pass at boot; the real frame-post-draw/loader handshake remains. Native warmup is unchanged.
2. Trace identifies the 1.22 s first-combat stall as two ~0.59 s particle shader LINK_STATUS waits. Their generated fragment source differs from an already compiled variant only by color-ramp sampling. BulletSmoke now supplies a constant-white ramp (multiplicative identity), retaining its original tint, scale, particle count, timing and animation. Same 15 s P trace: max 1224.125 → 440.865 ms; the two extra particle compiles disappear. An explicit camp-departure experiment prepares just the measured Canvas variants in separate drawn frames: the next same-workload 15 s P diagnostic falls to max 75.24 ms, p95 17.70 ms / p99 21.43 ms. Preparation is separately recorded: about 538 ms total, individual draws 1.675–155.090 ms. This remains a diagnostic candidate, pending real camp-input/cancellation and broader first-use verification; it is not full weapon warmup or menu gating.
3. Native 15 s P scoped totals: monster_move 2045 ms / 108850 calls; enemy_shot_step 608 ms / 156670 calls. These are inclusive scoped diagnostic totals, not per-frame CPU percentiles. They do not justify a pathfinding or collision behavior change.
4. Web required summary previously checked only export success. It now depends on startup, smoke and menu-return; preflight runs before export and both protected context names are preserved. Full native/browser matrices remain manual/nightly. GitHub timing improvement is not yet proven.
5. The existing SCISSOR cache retained enabled=true across context loss/restore. Exact production-installer tests on real WebGL1 and WebGL2 fail before and pass after lifecycle invalidation; steady-state reads do not add driver queries.
6. B17's intermittent four-object/two-resource exit warning was traced in three verbose runs to Cephalopod.ogg stream/playback references. A 100 ms stop-to-exit window still reproduced the Ogg playback leak. Clearing streams and freeing audio nodes did not reliably fix it and were reverted. A 400 ms drain in the existing Demo.finish_quit() passed three verbose B17 runs and the subsequent L1. Only the quit window changes; startup/gameplay audio is unaffected. Separate Native stress ObjectDB warnings still require verification.

## Measurement and verification changes

- Formal timing gates now use the full frame window; hot/first-5-second views are diagnostic breakdowns only. Injecting 150 ms early frames into an otherwise healthy measured trace correctly fails the full-window gate (`output/b19-4/full-window-gate-test.json`).
- TIME_PROCESS/TIME_PHYSICS_PROCESS are explicitly ENGINE_WINDOW_PEAK_MONITOR values. CPU percentile/bucket claims from those values were removed.
- Long frames retain process frame, physics tick, epoch, round and preceding load-sample/event indices. Gauges separately label alive, drawing-enabled and on-screen counts. Adjacent-sample 180+180 durations are labelled sampled coverage, not continuous proof.
- Same-build 30 s P observer comparison: steady browser rAF mean off 7.654 ms, light 7.388 ms, detail 8.788 ms. Detail-minus-off is +1.135 ms; light-minus-off -0.266 ms is run variation, not negative instrumentation cost. One run per mode, common workload driver remains enabled; this is a bounded estimate, not an isolated CPU benchmark.
- Important coverage failure: light/detail gauges show zero adjacent-sample duration at simultaneous 180+180. Separate peaks reach 180, but the amplifier only tops up at most 48 actors every 4 s while weapons kill them. These results cannot establish formal sustained P acceptance.
- Real mouse-only Start → camp stage tab → stage 1 → departure reached COMBAT with no script/page errors. Handler marker followed departure input by about 1 ms; browser max interval Start-to-departure 68.755 ms and departure-onward 149.995 ms. Screenshot confirms arena entry. This check uses the read-only probe and is not formal performance sampling.
- Browser stress captures independent rAF intervals and long tasks. It does not label rAF as GPU presentation completion.
- Startup setup failures now preserve a FAIL report and close Chromium; unreachable-server and wrong-artifact fault injections both returned exit 1 with the error retained. Failed network requests also fail the gate.
- Startup uses correct Playwright timeout arguments and separates ready from canvas/settle. Three cold contexts and three same-context warm navigations are separate from the undisturbed menu sample; the first navigation is not pre-warmed by that sample. Failures return nonzero.
- A lazy-script compile contract catches B11Stress parse errors that ordinary import can miss. The first diagnostic exposed a PackedFloat32Array.max() mistake; it was stopped, corrected, and the direct contract now passes.
- b194-local.py maps changed paths to existing affected suites, limits L1/L2 wall time, exports nothing, and retains detailed command output on failure. Diagnostics cannot be represented as formal acceptance.
- PCK audit: 2721 entries, 39.21 MiB payload, no leakage patterns matched. No content-removal optimization was made.

## Evidence index

All paths below are relative to the Godot project. Raw trace files are local ignored evidence, not shipped resources.

- `output/b19-4/startup-persistent-cache/b193-web-startup.json`: three fresh ordinary profiles, cold median 5851.435 ms / max 5958.290 ms; warm median 2300.135 ms / max 2326.010 ms. Both large assets have transferSize=0 and full nonzero encodedBodySize on every warm navigation. This supersedes earlier shared-browser-process cold and uncached repeat-navigation results for current startup reporting.
- `output/b19-4/startup-cache-reuse/b193-web-startup.json`: three cold contexts median 2858.705 ms / max 5861.590 ms; same-page repeated navigation median 2393.165 ms / max 2419.780 ms. Menu max 18.765 ms, no >50 ms frames. WASM/PCK transferSize remains full on all repeated navigations despite cacheable response headers; this is not proven cached-start acceptance.
- `output/b19-4/startup-fault-unreachable/`, `startup-fault-hash/`: setup failure reports, nonzero exit verified.
- `output/b19-4/startup-cold-first/b193-web-startup.json`: first cold-context sequence and resource timing; warm transfers still occurred.
- `output/b19-4/diagnostic/b194-p-detail-fixed.json`: 15 s Native P diagnostic, 26.078 s total wall time; 17 ObjectDB exit warnings remain.
- `output/b19-4/first-use-trace/`: before trace, original shaders and long-frame correlation.
- `output/b19-4/real-camp-departure/`: mouse-driven camp departure, timing log and inspected combat screenshot.
- `output/b19-4/observer-comparison.json`, `observer-off/`, `observer-light/`, `observer-detail/`: identical build `cbb194795025d090…`, 30 s each, no full CDP trace; invalid simultaneous-load coverage retained explicitly.
- `output/b19-4/b17-audio-node-release/`, `b17-audio-drain/`, `b17-production-drain/`: node deletion fails intermittently; extended drain passes three exploratory and three production-helper runs.
- `output/b19-4/l2-20260921-194851/summary.json`: all affected L2 checks pass in 158.515 s on the restored build; startup 22.860 s, smoke 48.281 s, menu-return 54.890 s.
- `output/b19-4/l1-20260921-194802/summary.json`: all L1 checks pass in 23.828 s after the shutdown correction.
- `output/b19-4/l1-20260921-194201/summary.json`: new preparation timing code compiles; L1 fails after 15.610 s on the recurring B17 audio exit warning.
- `output/b19-4/targeted-prepare-trace/`: 15 s P diagnostic, identity `cbb194795025d090…`; preparation console timing and browser trace retained. Runtime script compile contracts passed; the associated L1 failed on the recurring B17 audio resource warning.
- `output/b19-4/b17-audio-recheck/`, `b17-audio-release/`: three before and three stream-release runs, plus minimal audio isolation; no production shutdown change retained.
- `output/b19-4/particle-share-trace/`: after trace, identity `d414e173fcef0298…`; not a final candidate.
- `output/b19-4/scissor-before.json`, `scissor-after.json`: WebGL1/2 lifecycle A/B.
- `output/b19-4/l1-20260921-190856/summary.json`: bounded L1 pass.
- `output/b19-4/l2-20260921-191635/summary.json`: bounded L2 pass; startup 22.766 s, smoke 47.828 s, menu-return 53.719 s.
- `output/b19-4/before-ci-timeline.md`: actual baseline workflow Gantt and per-step durations, runs 35586630201 / 35586630134.

## Rejected pressure experiment

The P rig tried ordinary population refill alongside its existing deferred projectile refill (every 4 physics ticks). Same 15 s workload still recorded zero simultaneous 180+180 gauge samples, while max frame rose to 250.41 ms and p99 to 103.91 ms. Refill events reached about 95 ms for only 0–4 successful additions; measured spawn-clearance scope totaled 847.330 ms. This unhelpful refill change was reverted. Evidence: `output/b19-4/pressure-refill/`, build identity `7b86af357ba75d66…`. The Web export was subsequently rebuilt from the restored source (`restored-candidate-export.log`); it no longer contains the rejected refill change.

The same run validates the preparation timing split: synchronous load <=0.815 ms, construction <=0.610 ms and add/emit <=0.205 ms per measured item, versus draw windows up to 143.725 ms. The large cost is first rendering, not synchronous resource load for these five items.

## Historical test timing evidence

The previous Linux contracts job is dominated by M6EncounterAudit 414.919 s and M8Encounters 414.841 s, followed by M3Weapons 36.087 s, B13TalentEffects 25.916 s and B3Hazards 20.209 s. The first two alone account for about 830 s; removing them from the required path addresses the largest cost without shortening their test duration. `output/b19-4/before-contract-ranking.json` retains the top-20 ranking from adjacent sequential completion timestamps. These are historical CI wall times, not local Windows measurements or a startup/runtime/teardown split; the latter is still pending.

## CI candidate verification

Draft PR: https://github.com/seiya058904/Dont-stop/pull/17, first snapshot `d987a1f`. Run `35596753173` stopped its required path in about 50 s because the fresh importer reads the project font/cursor before generating their cache. Only seven distinct early diagnostics occurred; both protected summaries failed and browser gates were skipped. This verifies fail-fast behavior, not a successful timing result.

The import validator now accepts only those exact font/cursor diagnostics before the first filesystem scan, only after both source and generated files exist and are nonempty. Any later error, other resource error or script error still fails. B194Contracts actually loads both resources after import. The same validator is used by local L1/L2; five classification cases and L1 (23.547 s) pass. A clean-cache project copy completed an ordered-log import in 21.588 s, then passed all five B194 runtime checks (`output/b19-4/clean-import/ordered-import.log`, `runtime.log`).

## Software-renderer and save follow-up

PR run `35597223049` passed Build Web (87 s), Stable preflight and smoke, but failed startup and menu-return. CI cold interactive times were 24.393/23.090/23.450 s; the menu showed roughly 1 s frame gaps after the loader handed over at 5.450 s. Input feedback gates failed. This is not a successful required-path timing sample.

Forced SwiftShader on the local Windows host reproduces long menu intervals in both headless and headed Chromium without changing resolution or visuals. The headed diagnostic reached max 331.215 ms and first Start 590 ms. A separate instrumented headless trace reached max 933.300 ms. Its longest GPU-process WebGL command-buffer flush spans 960.340 ms wall time but only 0.809 ms of that thread's CPU time; JS WebGL calls do not account for the steady-state gap. This locates a wait in the GPU command path, not yet its underlying cause. Instrumented runs are diagnostic only. Disabling browser frame-rate limiting and GPU vsync did not help (max 920.160 ms, Start feedback absent); those experimental flags were not retained in production tools. Evidence: `output/b19-4/swiftshader-unthrottled/`. Evidence: `output/b19-4/headed-swiftshader-profile/`, `swiftshader-gl-trace/`.

The CI menu-return failure was solely save readability after reload; its interaction checks passed. Added probe-only, read-only save diagnostics (path/existence/persistence/result). Local L1 passes in 23.843 s; the rebuilt local menu-return run passes all 53 checks in 53.554 s, including save reload. The CI save failure remains unresolved, not waived. Evidence: `output/b19-4/l1-20260921-201913/`, `save-diagnostic-menu/`.

## Resumed diagnosis (2026-09-21, browser-clock measurement)

- Live baseline rechecked: HEAD `8454be34a8a146a8ad81a8d66320754fe0a46b43`, origin/main and public Pages `41a490888088dffceda307986b5e4e69bda85423`; public artifact digest `59d25cd2bf77936de115eeb19297036398c746fd533aac7ddc68d2c325018a0d`. Godot remains `4.7.2.stable.official.ed1daf0bf`. Exact existing Windows/Web hashes and entry dirty paths are retained in `output/b19-4/resume-baseline.json`.
- Startup now timestamps existing game stage messages inside the loader on the navigation clock, before console transport or Playwright polling. Missing first-hover timestamps fail closed. Reports also identify the actual WebGL renderer, drawing-buffer dimensions, Chromium version and launch arguments. Payload bytes were reused; only the generated HTML was refreshed for the local check.
- Bounded hardware-backed startup check: cold 5860.455 ms, warm 2209.160 ms; hover 6 ms, Settings 21 ms, Start 67 ms; undisturbed menu max 16.670 ms, zero >50 ms intervals. One diagnostic sample, not three-run final acceptance. Evidence: `output/b19-4/browser-clock-startup/`. L1 passed in 23.829 s (`l1-20260921-203528/`).
- A readback-instrumented SwiftShader experiment localizes rendering cost to the default lit Canvas shader: a 329–342-instance draw takes 115–125 ms; glow/tonemap draws take about 15–20 ms. Each diagnostic draw was bracketed by a one-pixel synchronous readback, so these values are deliberately NOT formal frame timings. The shader sources and per-draw observations are retained in `draw-diagnostic.json` and `program-27.glsl` / `program-33.glsl`. This explains where the GPU command queue is spending work; it does not justify disabling lighting/glow, reducing resolution or waiving the CI interaction gate.
- Switching to SwiftShader's WebGL-fallback mode did not fix responsiveness: menu max 216.66 ms, every sampled frame >100 ms, Settings 361 ms and Start 435 ms. This launch-flag experiment remains only in ignored diagnostics (`swiftshader-webgl-mode/`). No renderer flag was retained in production tools.
- The existing menu-return test with forced SwiftShader passed all 53 checks in 83.675 s, including reload/save readability (`save-software-diagnostic/`). Therefore the CI save failure is still not reproduced locally or explained; the read-only save diagnostics must be collected on CI before changing save behavior.

## Remaining completion gates (unchanged)

- Resolve remaining repeatable first-use freezes and verify all requested first-use actions, Boss phases and return/second combat.
- Finish same-workload observer off/light/detail comparison, visible simultaneous pressure proof and hotspot attribution.
- Produce Top 20 slow-test timing breakdown and validate failure-injection behavior; repeat L1/L2 for the final candidate.
- Complete three PR-like workflow timings and public cold/warm startup measurements, separating network and initialization.
- Freeze one candidate SHA, export Windows/Web once, run final H/M/B/P, Boss, soak and visual/audio checks from those bytes.
- Update the existing draft PR after resolving the failed gates. Squash merge only after required checks and final candidate evidence satisfy the objective; then verify Pages identity and public startup.

```text
WEB_STARTUP_ACCEPTED=false
CI_TIME_ACCEPTED=false
LOCAL_TEST_TIME_ACCEPTED=false
ENGINEERING_PERF_ACCEPTED=false
HUMAN_ACCEPTED=false
```
