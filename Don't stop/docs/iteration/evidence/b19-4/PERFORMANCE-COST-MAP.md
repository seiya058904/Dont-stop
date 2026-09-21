# PERFORMANCE COST MAP — investigation, not acceptance

Snapshot: source `c75f2b4` (game code `71ed3cf`), 2026-09-21. No gameplay optimization was made while constructing this map. Unknown costs are not zero. Inclusive scopes cannot be summed into a whole-frame pie chart. Native, exported Windows, hardware Web and Linux software Web are separate populations.

## Current evidence and its limits

| Surface / workload | Evidence | Measured result | Validity |
|---|---|---|---|
| Native, P driver, 15 simulated seconds | `output/b19-4/cost-map-current/c75f2b4-native-P-detail.json` | 2298 frame intervals, 14.887 s measured wall time; max 59.069 ms; two >50 ms frames | Fresh source run, detail observer enabled; zero simultaneous 180+180 gauge samples; NOT formal P |
| Linux SwiftShader, normal menu | `output/b19-4/ci-idb-batch-startup/b193-web-startup.json`, run 35608744336 | Baseline seven menu intervals, max 1400 ms, all >1000 ms | Exact CI artifact of game code 71ed3cf; real failure; does not establish hardware GPU cost |
| Hardware Web, normal menu | `output/b19-4/idb-batch-startup/b193-web-startup.json` | 600 intervals, max 33.33 ms, zero >50 ms | Local export before final error-callback guard; one diagnostic run, not final repeated acceptance |
| Exported Windows | Earlier loading/close evidence only | No current cost decomposition | Must measure separately; Native numbers are not substituted |

## TOP PERFORMANCE COSTS

These are priorities supported by observed magnitude, not additive percentages or a cross-platform benchmark.

| Priority | Path / platform | Cost evidence | Why / confidence | Next action |
|---|---|---|---|---|
| 1 | Menu compositor readback / driver wait, Linux software Web | Repeated 1.0–1.4 s intervals; new trace records 8.620 s in 11 ReadPixels spans | Largest waits occur under LayerTreeHost → ReadPixels → WaitForGetOffset; underlying raster/command cost still unresolved | Compare baseline and full SwiftShader browser backend in A/B/B/A; preserve pixels, workload and gates |
| 2 | First-use shader / hardware Web, older artifact | 1224.125 ms spike; two approximately 590 ms LINK_STATUS waits | Trace identifies blocking shader-status queries; historical evidence only | Reproduce baseline/candidate/baseline with identical seed/artifact protocol and validate visual equivalence; do not claim final ROI yet |
| 3 | Monster move_and_slide, current Native diagnostic | 2210.328 ms / 109901 calls over 15 simulated seconds; 0.962 ms per observed process interval | Source confirms the scope directly surrounds move_and_slide; largest **instrumented** bucket, not proven largest whole-frame subsystem | Attribute wall/crowd physics interaction only after validating pressure coverage |
| 4 | Enemy projectile step, same Native diagnostic | 592.332 ms / 155203 calls; 0.258 ms per observed interval | Inclusive step cost; collision, bounce and lifetime not yet separated | Measure those subscopes if this remains a leading bucket under valid pressure |
| 5 | Observer, historical hardware Web | Detail rAF mean 8.788 ms versus off 7.654 ms | One run each; +1.135 ms is not a reliable isolated cost | Repeat off/detail/detail/off; keep formal sampling separate from detailed attribution |

The uninstrumented remainder is **unknown**, not `frame interval minus sum(scopes)`: intervals include waiting, nested scopes overlap, physics and process tick counts differ, and observer overhead is not isolated. No claim that the top three account for 70–80% is currently defensible.

## Coverage by cost family

| Family | Currently measured | Missing attribution |
|---|---|---|
| CPU / script | Monster process inclusive 359.979 ms; hit handler inclusive 152.078 ms; movement and projectile step above | Enemy AI versus target selection; all path requests / duplicates / cache hits; Boss state machine; Fog; UI; diagnostics and test-driver exclusive time |
| Physics | Monster move_and_slide scope above; collision-pair / active-object gauges; spawn-clearance scope 56.361 ms / 22043 calls | Projectile move_and_collide, wall/crowd work, overlaps, rays/segments, shape creation; engine monitor values are peak windows, not frame CPU costs |
| Render submission | Draw-count timeline; projectile draw callback 9.287 ms total | Sprite/animation, trails, particles, Fog, Canvas geometry, material switches, lights, transparency and VFX CPU submission separated from driver work |
| GPU / driver | Historical shader waits and intrusive software draw brackets | Nonintrusive GPU timing, overdraw/fill, framebuffer work, upload and synchronization attribution on the actual failing Linux runner |
| Allocation / lifecycle | Spawn instantiate 29.465 ms / 731 calls; ready 46.330 ms; finalize 10.706 ms; prepare 51.801 ms | Deletion bursts, arrays/dictionaries, duplicate, shapes, signals, strings/logging, ref cleanup; existing scopes can nest |
| Loading / startup | Resource network timings and named stage markers below | Wasm compilation versus instantiation; synchronous resource parsing, texture decode/upload, audio init and scene instantiation exclusive times |

Historical draw brackets explicitly call readPixels before and after each draw. They identify expensive candidates but serialize rendering and must not be treated as normal frame/GPU timings. The historical CPU profile's large `(idle)` bucket also does not prove the GPU is busy.

## Startup partition — exact CI cold run 1

Navigation-clock markers, in milliseconds. These are elapsed windows, not additive CPU scope timings.

| Window | Time / duration | Interpretation |
|---|---:|---|
| Wasm request | 45.3 → 383.9 / 338.6 | Local CI HTTP transport, not public Internet download |
| PCK request | 45.8 → 509.2 / 463.4 | Parallel with Wasm; do not sum download durations |
| Last large response → Utils ready | 509.2 → 4139.0 / 3629.8 | Mixed engine / compilation / autoload window; not yet split |
| Utils ready → scene preparation | 4139.0 → 4235.1 / 96.1 | Boot setup elapsed time |
| Scene preparation → scene ready | 4235.1 → 6097.4 / 1862.3 | Scene construction/setup, not proven all resource parsing |
| Scene ready → first visible marker | 6097.4 → 8254.5 / 2157.1 | Initial frame/render handover window |
| Visible marker → first hover response | 8254.5 → 12123.0 / 3868.5 | Includes driver scheduling and actual feedback; not all game CPU |

Full gameplay warmup is not scheduled at this Web boot. The old 52–60 s startup and this run are not a controlled A/B/A pair; exclusive historical network/init/load/warmup costs remain incomplete. `overlayRemovedAt` currently marks fade start, not proof that opacity has reached zero.

## TOP FRAME SPIKES / event correlation

| Event | Before / current | Evidence | Cause status |
|---|---:|---|---|
| Historical Web first-combat shader use | 1224.125 → 440.865 → 75.240 ms across exploratory candidates | First-use / particle-share / targeted-prepare traces | Two extra shader variants removed, later work prepared earlier; not repeated A/B/A; preparation itself had draws up to 155.090 ms |
| Current Native first pressure burst | 59.069 ms at process frame 767, physics tick 319, epoch 1, round 1 | First top-up recorded 48 actors / 37.112 ms at effective tick 1; the interval spans effective ticks 0 → 7 | Tick alignment places the fixture top-up within this interval: about 63% is accounted for by that inclusive event; remaining cost is unassigned |
| Current Native subsequent spike | 55.271 ms at process frame 837, physics tick 351 | Previous gauge at 0.433 s reports 55 enemies / 176 shots, weapon 115; spike ends at 0.579 s | Gauge is approximately 146 ms old; first-use/resource/allocation/physics cause unassigned |
| Linux normal menu | Repeated approximately 1400 ms | Seven baseline intervals | Persistent slowdown, not an isolated first-use spike |

The two fresh Native long frames are fully retained in raw evidence. Source confirms event ticks and per-frame `physics_ticks` use the same effective-tick clock, allowing the first top-up to be placed between adjacent samples. This is test-fixture spawn cost, not proof of a normal-player spawn freeze. Boss phase, VFX, resource first use, allocation burst and per-frame query counts are not all recorded. Previous gauges are context only. This is a measurement gap to fix, not evidence those events were absent.

## Experiment decisions and acceptance

Existing particle-variant sharing and targeted preparation are provisional under the supplemental standard: repeatable A/B/A benefit and full visual/behavior equivalence still need verification. The rejected faster-refill and HP experiments remain reverted. No pooling, AI-frequency reduction, particle reduction, resolution change or collision removal follows from this map.

The IndexedDB bulk-enumeration change has functional persistence proof on Linux, including latest-save hash equality. Its isolated timing experiment is not whole-game frame ROI. Startup driver round-trip removal improves measurement overhead, not rendering throughput.

### New trace evidence and one rejected experiment

Run `35610869791` tests `cbcfba0` (unchanged game code). Build/preflight/smoke/menu-return pass; startup remains failed, with cold first response 10.625 / 10.182 / 10.130 s and baseline menu max 1383.3 ms. A separate diagnostic navigation after the failed gate captures 2.18 MB of compressed trace with no reported data loss. It never calls readPixels itself. Evidence: `output/b19-4/ci-cost-trace-startup/cost-trace/`.

The trace contains 11 `GLES2::ReadPixels` spans totaling 8620.419 ms, maximum 1378.620 ms. The largest seven waits have the ancestor chain `LayerTreeHost::DoUpdateLayers → GLES2::ReadPixels → CommandBufferProxyImpl::WaitForGetOffset`. GPU-process `CommandBufferService:PutChanged` spans total 9136.698 ms. These timelines overlap; they are not additive CPU and GPU costs. LinkProgram spans total only 65.539 ms in this diagnostic navigation. This separates persistent compositor/command synchronization from the locally observed cold shader-link stalls; it does not prove a hardware GPU is saturated.

Local source capture identifies six >50 ms LINK_STATUS waits: two spatial default/instanced variants, two particle variants and two Canvas variants. The particle pair differs by an extra duplicate `USERDATA1_USED` define. A narrowly scoped browser-only experiment removes that duplicate, leaving the later identical unconditional definition intact. Corrected, guarded A/B/B/A results (`cost-map-current/shader-startup-checked-*.json`):

| Run | Sum of >50 ms link waits | Menu ready marker |
|---|---:|---:|
| A1 | 2762.190 ms | 5662.345 ms |
| B1 | 2793.475 ms | 5727.205 ms |
| B2 | 2795.095 ms | 5717.480 ms |
| A2 | 2755.250 ms | 5698.080 ms |

Decision: **REJECT**. No repeatable benefit; no shader-normalization change enters the product. These are diagnostic ready markers, not first-interaction acceptance times.

A subsequent read-only capture of existing `transformFeedbackVaryings` calls explains why source similarity was insufficient: the first particle program captures five outputs, while the second also captures `out_userdata1` (`cost-map-current/shader-feedback.json`). They have different link contracts even after duplicate-macro normalization. Treating them as interchangeable programs would risk particle behavior; no program-alias/cache patch is justified by this experiment.

The second single-variable experiment uses Chromium's documented full SwiftShader mode (`--use-gl=angle --use-angle=swiftshader`) versus its WebGL fallback path. [Chromium's SwiftShader documentation](https://chromium.googlesource.com/chromium/src.git/+/refs/heads/main/docs/gpu/swiftshader.md) distinguishes these modes. It ran in separate post-failure diagnostic navigations; acceptance browser arguments and thresholds remained unchanged. GPU feature status and post-trace screenshots verify what actually ran.

Run `35612213295` completed all four diagnostic captures without reported trace data loss. All four loaded identical Wasm/PCK/JS hashes at 1536×864, all reported the same SwiftShader renderer, and A1/B1 screenshots show the complete menu/world. Feature status changes from `gpu_compositing=disabled_software` in A to `enabled` in B. Evidence: `output/b19-4/ci-backend-abba/backend-comparison.json` and the four `cost-trace-*` directories.

| Run order | Menu rAF samples | Mean interval | Max interval | ReadPixels span sum | GPU-process command span max |
|---|---:|---:|---:|---:|---:|
| A1 | 7 | 1323.757 ms | 1399.900 ms | 8682.177 ms | 1383.135 ms |
| B1 | 10 | 773.290 ms | 3783.200 ms | 21.323 ms | 3780.548 ms |
| B2 | 10 | 733.300 ms | 3733.200 ms | 20.216 ms | 3734.562 ms |
| A2 | 7 | 1378.514 ms | 1783.200 ms | 8696.746 ms | 1393.847 ms |

Decision: **REJECT as a startup/performance fix**. B removes the blocking compositor readback path but retains expensive command execution and introduces repeatable approximately 3.7–3.8 s menu intervals. A better mean is insufficient. rAF intervals are not GPU-present timings; command spans include driver/software raster work, not hardware GPU utilization. These short, heavily traced windows are diagnostic, not formal FPS acceptance. Underlying work inside `CommandBufferService:PutChanged` still needs attribution.

The original uninstrumented gate in this run still fails: cold first-response 11.281 / 10.305 / 10.271 s, baseline menu max 1399.9 ms. Build, stable preflight, smoke and menu-return pass. The temporary automatic A/B/B/A workflow block has been removed after obtaining evidence, restoring the preceding required-gate execution path. Standalone trace/reduction tools remain for bounded reproduction; no backend switch enters acceptance or product defaults.

Next measurement order: attribute Linux menu freeze; complete >50 ms event context; establish valid simultaneous pressure; split the largest measured scopes and repeat observer controls. Only then choose one equivalent implementation and run A/B/A or A/B/B/A. Final startup, three-surface H/M/B/P, Boss, soak, visual and human acceptance remain false/pending.

## Test-duration cost map (separate from game frame cost)

The latest recorded local L1 takes 24.594 s; its largest step is import at 6.047 s. The preceding affected L2 takes 161.938 s: menu-return 54.578 s, smoke 48.906 s, startup 26.219 s. These three browser steps occupy about 80% of that L2 wall time. The L2 predates the latest save change; this is scheduling evidence, not final-candidate validation. Optimizing millisecond contract assertions would not address its largest costs.

Historical full Linux contract ranking below comes from `output/b19-4/before-contract-ranking.json`. Adjacent sequential PASSED timestamps include small log overhead; the initial case is excluded and buffered timestamps cannot split startup/runtime/teardown. Do not compare these directly with local Windows timings or claim removing their coverage is a speedup.

| Rank | Historical Linux case | Elapsed seconds |
|---|---|---:|
| 1 | M6EncounterAudit | 414.919 |
| 2 | M8Encounters | 414.841 |
| 3 | M3Weapons | 36.087 |
| 4 | B13TalentEffects | 25.916 |
| 5 | B3Hazards | 20.209 |
| 6 | PresentationLifecycle | 12.656 |
| 7 | B4Fog | 12.095 |
| 8 | B11Stages | 11.630 |
| 9 | B16CombatMix | 10.250 |
| 10 | M4Talents | 6.790 |
| 11 | B14Growth | 6.419 |
| 12 | R1Timeline | 6.416 |
| 13 | B16Pickup | 5.568 |
| 14 | B16Camp | 2.864 |
| 15 | B6Progression | 2.772 |
| 16 | B6Progression --hell-unlock | 2.771 |
| 17 | B14Feedback | 2.307 |
| 18 | B11Fairness | 2.210 |
| 19 | B14Rail | 2.029 |
| 20 | B13UI | 2.028 |
