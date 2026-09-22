# B19.4: immobilization removal and bounded performance investigation

2026-09-22. Base: `8b346e6`; branch: `fix/b194-performance-startup-ci`. Local uncommitted candidate. No push or release.

## Latest follow-up: sustained-frame cost (2026-09-22)

This section supersedes the older candidate tables below. **Performance improved, but stable 160 FPS and formal maximum-density acceptance are not achieved.** All results are monotonic process-frame intervals, not GPU presentation measurements. Peak/average FPS alone is not acceptance.

Retained changes:

- `CombatArena.gd` remembers only exhausted placement searches inside an explicitly bracketed, synchronous birth-only batch. `LevelServer.onMonsterCreate()` and the pressure driver's refill bracket those batches. New actors can only occupy more space; successful placements still perform current collision checks. The cache clears at batch end, includes geometry, transform, radius and physics tick, preserves RNG consumption and never survives movement/removal. This removes repeated searches of the same full ring without changing legal positions or birth budgets.
- `ArcDischarge.gd` batches contact sparks into one `draw_multiline` call. Endpoints, contact count, animation, fading, hits and the earlier retained edge paths remain. The fixed render comparison differs at 48/94,300 pixels at age 0 and 64 at age 0.08 (small line-join corners), and is identical at age 0.16; it is not claimed pixel-identical. The standalone render fixture produced shutdown rendering-resource errors; production pressure runs had no such errors.
- `B11Stress.gd` counts deaths when they happen, then does not subtract the same corpse again at delayed deletion. Independent 10 Hz scans verify the counter; mismatches reject acceptance. The population floor now applies to every render observation, preventing brief dips from slipping between gauges. Birth-only refill loops reuse a local live count instead of rescanning all actors on each failed placement. These observer changes reduce diagnostic overhead, not ordinary gameplay cost.

The first matched native detail pair (15 seconds after first target arrival, including dips) reduced placement queries from 1,219,033 / 2,955.844 ms to 304,339 / 789.162 ms. p95 fell from 17.641 to 10.458 ms; p99 from 52.362 to 14.402 ms; kills increased from 1,334 to 1,517. Adding contact batching then measured p95 9.179 / p99 12.992 ms. These are sequential single-run observations, not a randomized proof of exact percentage gain. The final outer refill-batch boundary and observer corrections came afterward.

The final three-surface run used **diagnostic mode**, Stage 39, seed 20260920, held W112, continuous circular movement, real HP/AI/attacks, rapid kills/refills, target/cap 180 and natural projectiles. All ~45 seconds of the authored round are reported below, including initial buildup and population dips. It did not find the required continuous qualified 15-second window. These whole-round results must not be presented as steady-state or compared directly with the earlier 15-second slices.

| Surface | Mean FPS | p95 ms | p99 ms | Max ms | >50 ms frames | Kills / births | Projectile births | Travel px |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Native source | 323.71 | 8.431 | 12.166 | 54.052 | 2 | 4657 / 4830 | 129 | 5231 |
| Windows release | 399.52 | 6.987 | 9.557 | 18.873 | 0 | 4654 / 4834 | 99 | 5231 |
| Hardware browser | 148.91 | 14.390 | 17.825 | 38.585 | 0 | 4462 / 4642 | 134 | 5198 |

All three reached 180 alive and had **zero counter mismatches**, but real killing caused sub-160 intervals. Independent post-first-second samples averaged 164.94 / 170.52 / 171.13 alive (native / Windows / Web); 94/429, 62/434 and 70/426 samples were below 160. Therefore `pressure_measurement_valid=false` is a real workload-gate failure, not now a counter error. Neither the floor, settling time, birth budget, enemy HP nor weapon damage was relaxed. Native/Windows exited 0 with 16/20 ObjectDB leak warnings; browser had no script errors and exited 1 for the failed pressure gate. Automated visibility/focus are true; HUMAN_ACCEPTED=false.

Remaining-cost checks used the same Web export, one short full control and one sample per hypothesis. Whole-combat p95 was 13.79 ms with everything enabled, 14.38 ms with only light shadows disabled, and 13.90 ms with arc-dominated gun drawing hidden. All retained real killing/refill/movement and had no script errors. No useful shadow improvement was observed, so that experimental source change was removed. Hiding gun drawing no longer gives the large improvement seen before the arc patches; it is not evidence that all gun rendering is free, and the muzzle isolation limitation below still applies. The final export restores normal shadows and normal weapon drawing.

Using the already captured 45-second samples, Web frames with no physics step averaged 3.347 ms; those with one step averaged 11.707 ms (p95 16.640). Windows was 1.723 versus 6.914 ms; native 1.955 versus 8.053 ms. This locates remaining cost in frames containing physics work, not exclusively in the physics engine: AI, births, weapon hits, observer work and rendering also occur there. Detailed native scopes still measured monster movement at 1,821.410 ms per 15-second slice; spawn clearance was 793.774 ms, while A* was only 87.779 ms. No low-return A* cache, collision removal, reduced update rate, lower enemy count or art downgrade was added.

Validation: import, B192Spawn (134 checks), B11Fairness (61) and B194Pressure (14, including corpse lifecycle, real-factory/RNG parity and strict window resets) pass. Web and Windows export checks pass; the final Web export removes the rejected shadow experiment. Earlier immobilization/fairness checks below remain applicable; no broad suite was repeated merely for completeness. Final diff/identity checks are recorded with the local evidence.

Evidence: `output/b19-4/spawn-batch/`, `arc-batch/`, `combined/` (before live-counter correction), `verified-pressure/` (corrected three-surface samples, summary, physics buckets, final checks and source identity), and `shadows/` (two hypotheses sharing one control). The only production optimizations in this follow-up are exhausted-search reuse and contact drawing batching; the earlier movement-dust and root/hazard changes remain. No commit/push.

## Result and scope

- Enemy HP bars remain hidden. Removed Hero immobilization/immunity timers and movement/dash blocks, all control payloads/calls, dedicated purple control rendering, HUD entry and camp lesson. Deleted RootFeedback and RootLessonPanel plus their UID files.
- E10/E13/B02 attacks now use ordinary damage/projectiles. Pellet counts, speeds, wave intervals, recovery and existing direct-damage multipliers are preserved. B02 ultimate keeps its damage and timing.
- All authored environmental hazard plans from Stage 21 onward select only the existing meteor family; earlier stages remain empty. Existing stage cadence/caps/meteor geometry are retained. Monster-owned poison/laser attacks remain real combat load.
- ArcDischarge now retains edge draw commands between its existing 35 Hz shape changes. Canvas modulation performs continuous fading; a child CanvasItem draws the same continuously animated contact sparks. No damage, targeting, firing rate, edge/contact count or geometry changes.

## Experiment boundary

A planned 8-condition × 3-surface matrix was excessive and cancelled at the user’s request to reduce testing. Completed: 8 native diagnostic conditions, 1 Windows diagnostic condition (enemy art hidden), then one final full-load candidate run per surface. The earlier pilot and cancelled partial runs are not used as controls. These are coded, randomized ablations, not a true human double-blind study.

Same Stage 39, seed 20260920, held W112, moving/circling player, real mixed enemies, rapid kills/refills, target/maximum 180, natural AI projectiles; 1536×864 window, uncapped engine. The diagnostic `mode=ablation` stops 15 wall seconds after first reaching target. Statistics include every process-frame interval after that first arrival, including refill dips and long frames. They are engine process intervals, not GPU presentation timing.

**Formal pressure acceptance remains false.** The continuously qualified high-density window is shorter than 15 seconds because rapid killing/refill changes population. No formal gate was relaxed. These short runs cannot establish stable 60/160 FPS or cross-platform optimization significance.

## Native ablations before the arc change

| Condition | Average FPS | p95 ms | p99 ms | Kills |
|---|---:|---:|---:|---:|
| native-01: detail_observer | 162.13 | 18.73 | 46.75 | 1367 |
| native-02: full | 160.17 | 21.79 | 42.19 | 1362 |
| native-03: gun_drawing | 272.11 | 13.98 | 25.09 | 1429 |
| native-04: hostile_vfx | 162.95 | 20.25 | 46.08 | 1342 |
| native-05: full | 166.35 | 21.03 | 52.10 | 1310 |
| native-06: enemy_art | 196.07 | 19.09 | 34.43 | 1360 |
| native-07: no_churn | 236.19 | 10.89 | 12.24 | 0 |
| native-08: particles | 176.71 | 19.54 | 41.23 | 1411 |

Gun drawing isolation is dominated by hiding ArcDischarge; TierMuzzle can make itself visible again in pulse(), so this does not prove complete muzzle isolation. The durable/no-churn condition changes HP and eliminates kills/refills; player travel also drops to ~153 px from ~1700 px. It is a confounded diagnostic clue, never a comparable acceptance workload.

The two full native controls give p95 21.03–21.79 ms. Hiding arc-dominated gun drawing yields p95 13.98 ms while retaining 1429 kills. Enemy artwork has a smaller observed effect; hostile VFX/particles did not show a comparable reduction in these single runs. These observations do not establish that those subsystems cost nothing.

Detailed native sampling recorded spawn-clearance 2204.699 ms, monster movement 1981.456 ms, hit processing 212.966 ms, spawn preparation 134.339 ms and instantiate 59.839 ms over the diagnostic window. Inclusive scopes overlap and must not be added. Churn/spawn collision validation and monster movement remain strong CPU investigation candidates; this does not justify reducing enemies or projectile load.

## Earlier full-load candidate, one short run per surface

| Surface | Average FPS | p95 ms | p99 ms | Maximum ms | Kills / births | Projectile births | Travel px |
|---|---:|---:|---:|---:|---:|---:|---:|
| Native source | 192.35 | 16.69 | 43.17 | 84.78 | 1346 / 1513 | 40 | 1742 |
| Windows release export | 263.87 | 12.57 | 20.63 | 57.53 | 1491 / 1563 | 35 | 1697 |
| Hardware browser | 69.31 | 32.43 | 70.92 | 1287.26 | 1155 / 1335 | 43 | 1600 |

Native p95 improves by approximately 21–23% versus the two controls, with comparable kill/refill/travel workload. Its p99 remains within the noisy control range: the tail is not solved. There is no matched full-load before-control for the current Windows/Web export, so their candidate numbers are not claimed as measured improvement. Do not compare these 15-second diagnostic windows directly with older steady-state numbers.

Native/Windows use Forward+; browser uses GL Compatibility on hardware ANGLE/D3D11, AMD RX 7900 XT, Chromium 151.0.7922.34. Browser reports visible=true and focus=true; this is automated visibility evidence, not user confirmation. HUMAN_ACCEPTED=false. Browser had no script errors, but a 1287.26 ms frame remains. Its cause was not traced in this final short run; earlier shader observations cannot establish the cause of this specific frame. Reported texture size 5755×3224 is also recorded for future investigation, not yet established as a bug.

## Checks and limitations

- Import passes (including final candidate), B194Contracts 6 checks pass.
- Removal/attack contract B194Combat: 69 checks pass.
- B11Fairness: 61; B11ShotLayer: 54; B3Hazards: 128; B8Contracts: 52 checks pass. The B8 attribution fixture now sets is_elite explicitly because camp Stage 1 refuses production elite admission; the real contact/damage path is still tested.
- Earlier affected L1 also passed BaselineRegression, B192Safety and B19Contracts. No additional full suite was run for the visual-only arc change.
- Web and Windows release exports succeed. Native/Windows short runs exit 0 with existing ObjectDB leak warnings (17 and 15 respectively); not resolved here.
- Browser harness exits 1 because the strict pressure acceptance gate is false, despite successful execution and no script errors. This is not a passed performance acceptance.
- Initial browser launch attempts failed before sampling (missing NODE_PATH, then relative server root caused HTTP 403). Used bundled Playwright via NODE_PATH and restarted the local server with an absolute root; no dependency installation or product-server changes.
- git diff --check passes. No commit/push. No extra repeated performance runs after these three candidate samples.

## Evidence and reproduction

Raw local evidence: `output/b19-4/no-control/`. `blind-r2/key.json` maps coded experiments; `*-result.json` contains metrics. Final `arc-retained.json`, `arc-windows.json`, `stress-arc-web-P.json` contain logs/frames/surface and export identity. `final-comparison.json` and `summarize-final.py` reproduce the fixed analysis window. `source-identity-final.json` hashes the tested source. Logs include each verification named above.

Native reproduction: set B19_OUT to a fresh output directory, then run `python tools/b192-run.py native <unique-label> -- --stress --stress-scenario=P --stress-stage=39 --stress-seconds=15 --stress-seed=20260920 --stress-measurement=light --stress-benchmark=uncapped --stress-mode=ablation`. Windows uses the same options with platform `windows` and B19_WINDOWS_EXE pointing to the new release export. Serve the Web export with an absolute root; use the existing web-b11-1-stress.js harness with the same options.

Next focused investigation: correlate remaining long frames with spawn-clearance/movement and browser first-use rendering. Choose one hypothesis and one bounded control; do not repeat the full three-surface ablation matrix. Stable 160 FPS/180 FPS peak and even stable 60 FPS remain unproven.

## Follow-up: first-movement freeze isolated and removed (2026-09-22)

This follow-up changes only the Hero movement-dust emitter in `game/hero/Hero.tscn`, plus its explanation in `Hero.gd`. The earlier immobilization/meteor/arc changes remain in place.

A matched 15-second Web trace pair identified two blocking WebGL LINK_STATUS queries inside combat: 594.94 ms and 604.00 ms, beginning 744.7 ms and 1345.4 ms after the browser combat-start marker. Their particle simulation shader introduces spherical emission and omits the color ramp. This matches Hero’s six-particle running dust, whose emission is enabled by gunAnim() on movement. After replacing only that emitter with CPUParticles2D, no >10 ms shader waits were recorded inside combat. Expensive menu/preparation shader compilation still exists outside this measured combat window.

The count (6), lifetime (0.4 s), emission/explosiveness, fixed simulation rate (30 Hz), radius, direction, velocity, acceleration, size curve and color are retained. A local fixture compares 20 scalar/vector fields plus curve data against Godot’s built-in GPU-to-CPU conversion: 21 checks, zero differences. CPU/GPU random trajectories are not asserted pixel-identical. The node path is retained, so existing movement timing is unchanged. This removes a dedicated first-use shader path instead of moving that same cost into a longer loading pass. API reference: [Godot CPUParticles2D](https://docs.godotengine.org/en/stable/classes/class_cpuparticles2d.html).

| Web run | Mean FPS | p95 ms | p99 ms | Max ms | Kills / births | Enemy projectile births | Travel px |
|---|---:|---:|---:|---:|---:|---:|---:|
| trace-before | 59.53 | 48.62 | 105.46 | 1266.83 | 1094 / 1267 | 32 | 1645 |
| trace-after | 61.54 | 48.59 | 80.75 | 144.09 | 1212 / 1391 | 28 | 1760 |
| dust-final | 82.95 | 28.49 | 51.35 | 119.69 | 1294 / 1473 | 55 | 1703 |

The first two rows both enable the same tracing/wrappers; the third disables tracing. Each row uses all process-frame gaps after first target arrival, including density dips. Trace overhead is substantial, so compare the trace pair to isolate the compile stall; do not attribute the entire traced-to-untraced FPS difference to the patch. The final lightweight sample remains one diagnostic window, not a stable-FPS acceptance. No pressure validation threshold changed; all three runs retain valid=false and the Web harness correctly exits 1 for that gate, with no script errors. Peak enemies remain 180; W112, player movement, fast kills/refills and natural AI projectiles remain enabled.

The final untraced result is about 83 average FPS, but p95 28.49 ms / p99 51.35 ms and 119.69 ms maximum still fail a stable 60/160 FPS claim. This fixes the reproduced >1-second first-move freeze; it does not fix all high-density stutter.

The suspicious 5755×3224 viewport-texture report was checked against actual WebGL calls. Depth buffer is 1536×864 and the main rendered viewport is 1536×861; there is no evidence of a 5755×3224 render target. Do not lower render resolution based on that diagnostic string. Repeated framebuffer-binding queries were also small in this trace: 1682 calls, 2.935 ms total, maximum 0.045 ms, so they are not a supported next optimization target.

Validation: import passes; B194Combat 69 checks pass; dust conversion parity 21 checks pass; Web and Windows release exports pass; git diff --check passes. Native/Windows performance is not remeasured in this follow-up, and prior platform numbers are not relabeled as results for this patch. Automated browser visibility/focus are true; HUMAN_ACCEPTED remains false. An initial local parity fixture used a mismatching SceneState node-path lookup and was corrected to node-name lookup before the passing comparison; this was a test-fixture issue, not a production parse failure.

Raw evidence: `output/b19-4/long-frame/{stress-trace-before-P.json,stress-trace-after-P.json,stress-dust-final-P.json}`, `shader-waits-*.json`, `gl-sizes-*.json`, `comparison.json`, `dust-parity.log`, `B194Combat-dust.log`, export logs and `source-identity.json`. The shader traces retain sources and timestamps. Exactly two traced pressure runs and one final untraced pressure run were used in this follow-up; no repeated matrix. The already measured spawn-clearance/movement CPU costs remain the next focused steady-load investigation; no speculative collision/spawn change is included here.
