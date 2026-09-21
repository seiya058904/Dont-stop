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
| 1 | Menu render/driver path, Linux software Web | Repeated 1.0–1.4 s intervals, no gameplay pressure driver | Render/driver is a candidate supported by separate Windows software-renderer diagnostics; Linux per-stage attribution still missing | Capture exact Linux browser trace and distinguish submission, synchronization, rasterization and waiting before selecting a change |
| 2 | First-use shader / hardware Web, older artifact | 1224.125 ms spike; two approximately 590 ms LINK_STATUS waits | Trace identifies blocking shader-status queries; historical evidence only | Reproduce baseline/candidate/baseline with identical seed/artifact protocol and validate visual equivalence; do not claim final ROI yet |
| 3 | Monster movement, current Native diagnostic | 2210.328 ms / 109901 calls over 15 simulated seconds; 0.962 ms per observed process interval | Largest **instrumented** bucket, not proven largest whole-frame subsystem | Split movement calculations from physics calls and crowd interaction only after validating pressure coverage |
| 4 | Enemy projectile step, same Native diagnostic | 592.332 ms / 155203 calls; 0.258 ms per observed interval | Inclusive step cost; collision, bounce and lifetime not yet separated | Measure those subscopes if this remains a leading bucket under valid pressure |
| 5 | Observer, historical hardware Web | Detail rAF mean 8.788 ms versus off 7.654 ms | One run each; +1.135 ms is not a reliable isolated cost | Repeat off/detail/detail/off; keep formal sampling separate from detailed attribution |

The uninstrumented remainder is **unknown**, not `frame interval minus sum(scopes)`: intervals include waiting, nested scopes overlap, physics and process tick counts differ, and observer overhead is not isolated. No claim that the top three account for 70–80% is currently defensible.

## Coverage by cost family

| Family | Currently measured | Missing attribution |
|---|---|---|
| CPU / script | Monster process inclusive 359.979 ms; hit handler inclusive 152.078 ms; movement and projectile step above | Enemy AI versus target selection; all path requests / duplicates / cache hits; Boss state machine; Fog; UI; diagnostics and test-driver exclusive time |
| Physics | Collision-pair / active-object gauges; spawn-clearance scope 56.361 ms / 22043 calls | move_and_slide versus move_and_collide, wall/crowd work, overlaps, rays/segments, shape creation; engine monitor values are peak windows, not frame CPU costs |
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
| Current Native first pressure burst | 59.069 ms at process frame 767, physics tick 319, epoch 1, round 1 | First top-up recorded 48 actors / 37.112 ms | Nearby event is a candidate; existing event lacks exact process-frame timestamp, so not a causal assignment |
| Current Native subsequent spike | 55.271 ms at process frame 837, physics tick 351 | Previous gauge at 0.433 s reports 55 enemies / 176 shots, weapon 115; spike ends at 0.579 s | Gauge is approximately 146 ms old; first-use/resource/allocation/physics cause unassigned |
| Linux normal menu | Repeated approximately 1400 ms | Seven baseline intervals | Persistent slowdown, not an isolated first-use spike |

The two fresh Native long frames are fully retained in raw evidence, but Boss phase, exact spawn frame, VFX, resource first use, allocation burst and per-frame query counts are not all recorded. Previous gauges are context only. This is a measurement gap to fix, not evidence those events were absent.

## Experiment decisions and acceptance

Existing particle-variant sharing and targeted preparation are provisional under the supplemental standard: repeatable A/B/A benefit and full visual/behavior equivalence still need verification. The rejected faster-refill and HP experiments remain reverted. No pooling, AI-frequency reduction, particle reduction, resolution change or collision removal follows from this map.

The IndexedDB bulk-enumeration change has functional persistence proof on Linux, including latest-save hash equality. Its isolated timing experiment is not whole-game frame ROI. Startup driver round-trip removal improves measurement overhead, not rendering throughput.

Next measurement order: attribute Linux menu freeze; complete >50 ms event context; establish valid simultaneous pressure; split the largest measured scopes and repeat observer controls. Only then choose one equivalent implementation and run A/B/A or A/B/B/A. Final startup, three-surface H/M/B/P, Boss, soak, visual and human acceptance remain false/pending.
