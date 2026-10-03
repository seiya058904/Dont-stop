# 2026-10-03 quality iteration

Baseline: `origin/main` at `d6aab1d539b155bb2c3a603085403d2800878d38`.
The baseline was exported and played before editing. Existing encounter, weapon,
talent, save and presentation contracts were inspected alongside rendered play.

## Acceptance criteria

- Loading has a coherent composition on Web and Windows, truthful progress,
  a working retry path, and a reduced-motion alternative.
- The player remains visible from the first frame after entering or leaving an
  arena; aiming and recoil cannot retain the previous arena's transform.
- HP and reload feedback reflect actual gameplay state, including fractional HP,
  interrupted reloads, healing and pause. Damage distortion leaves the HUD legible.
- Improve a reproduced rendering stall without reducing combat load or changing
  damage, costs, talents, rewards, spawn rules or gameplay RNG.
- Export both targets; run real input flows and regression checks; disclose
  incomplete checks and remaining frame spikes.

## Changes and rationale

- **Startup:** shared original generated citadel artwork (116 KiB WebP), restrained
  drifting particles, three measured work stages, readable controls and a soft
  handover. The existing pixel wordmark and gold/slate palette remain. Web embeds
  the same image, so export hosting needs no additional asset request. Windows
  imports it with lossy compression. There is no artificial minimum loading time.
  The stalled-start retry button previously had no listener until an error also
  occurred; both retry paths now work. Errors stop the busy animation. The cover
  still requires the game's real ready notification before revealing the canvas.
- **Camera:** baseline stage 39/40 entry showed empty black space while two
  smoothing layers travelled from camp to a distant arena. Teleports now reset
  both layers, interpolation and recoil. Aim lead uses bounded screen coordinates
  and time-based smoothing instead of an unbounded world-coordinate feedback loop
  updated every fifth frame. Boss instructions now describe the actual objective,
  and the opening toast sits below its health bar.
- **Combat readability:** fractional HP, an exact numeric readout and a short amber
  loss trail; reload duration/progress read directly from the gun's timer; an
  explicit empty-reserve state; distinct player damage numbers. Hit flash has one
  scene-owned material/tween and appears under HUD/reticle. Reduced flash is
  respected. Dash ghosts and node-bound tweens retire with their scene/round.
- **Rendering:** cold Web traces identified expensive lit shader variants for
  small emissive tracer/muzzle/smoke effects. Those effects now use unshaded ink;
  projectile lights, sprite shading, particle count, lifetime and motion remain.
  Experiments removing lights or changing particle implementation did not produce
  a useful gain and were discarded.
- **Verification:** 62 new native assertions cover camera transitions and combat
  readouts; the browser loader test covers real DOM lifecycle/fault handling at
  three sizes. These gates are included in CI. The existing real-input playtest
  now follows current camp controls and checks player visibility at arena entry
  through the existing read-only probe.

No numeric balance changes were justified by this pass. The demo's starting
resources are deliberate configuration, not a wallet defect. Full-build balance
and every possible talent/weapon combination are not claimed as exhaustively
validated.

## Measured performance

Local machine: Ryzen 7 9700X, Radeon RX 7900 XT; Godot 4.7.2
(`ed1daf0bf`). Browser: Playwright 1.62.1 / Chromium 151, ANGLE D3D11,
1280×720. Windows release: Vulkan Forward+, 1536×864, 160 Hz monitor.
Values below are process/RAF frame intervals, **not GPU presentation latency**.

| Workload | Baseline | Final |
| --- | --- | --- |
| Fresh Web context, weapon 0 first shot, maximum frame | 233.33 ms; trace run 266.65 ms | 50.00 ms in both independent final runs |
| Same context, second/third shot and first dash, maximum frame | 16.67 ms | 16.67 ms |
| Web stage 39 / D / 35 s, p95 / p99 | 18.95 / 20.50 ms | 18.84 / 20.86 ms |
| Web same run, maximum / frames >33 / >50 ms | 37.58 ms / 2 / 0 | 56.78 ms / 3 / 1 |
| Windows stage 39 / D / 35 s, p95 / p99 | 11.68 / 12.57 ms | 12.24 / 13.04 ms |
| Windows same run, maximum / frames >33 / >50 ms | 37.42 ms / 1 / 0 | 71.38 ms / 3 / 2 |

Both D runs request seed `20260918`, peak at 180 enemies and complete 35 seconds
of combat. Valid Windows measurements have zero paused milliseconds. Invalid
focus-interrupted attempts were excluded. Final Windows >50 ms samples occur in
the first 0.13 seconds of arena entry. The camera correction changes the visible
scene and some screen-dependent combat placement, so these sustained runs are
regression observations, not proof of identical per-frame workloads or a steady
FPS improvement. The measured improvement is the cold first-shot stall.

The baseline Web stress run logged an ObjectDB `slot >= slot_max` error during
return to menu. Final stress and repeated menu-return runs did not reproduce it;
this observation does not establish an engine-level root cause.

## Validation performed

- Clean import; Web Release and Windows x64 Release exports completed.
- 51 distinct completed native case configurations: **2,883 functional assertions,
  no failed assertions or script errors**. 38 configurations also have no logged
  shutdown errors. This is not a claim of an entirely clean legacy test suite.
- Final strict gates: CameraTransitions (38), CombatReadability (24),
  BaselineRegression (4), B194Contracts (6), B17Contracts (20),
  PresentationLifecycle (52), P0HudParity (13), B11Fairness (61), B11Stages (57).
- `M10Bosses full with40`: 32 assertions, actual four-boss attack/ultimate,
  damage/resolution/cleanup paths; 164 seconds, clean exit. This does not claim
  a player clear of every boss.
- Real browser input: legal purchases and firing of weapons 113/115/119/124 in
  separate normal-HP departures to 39, plus stage 40 opening; all entries keep the
  player visible. Fresh saved-camp reloads preserve purchased loadouts.
- Weapon 6 beam also completes fresh-context firing, dash, combat and reload
  checks without errors. Its first-shot maximum is 66.67 ms (no paired baseline
  claim); subsequent shots/dash are 16.67 ms.
- Real browser aim/input gate: 61 required tokens pass. Three menu-return cycles
  pass. No engine, page or network errors in these final runs. Headless OS focus
  switching is not exercised by the aim gate.
- Loader DOM checks: 1280×720, 3840×2160, 390×844; artwork parity/decoding, layout
  bounds, reduced motion, real stage callbacks, stalled and fatal retry (including
  keyboard), and explicit ready handover. Only the engine is stubbed for these
  fault checks; separate browser tests run the actual exported engine.
- Actual Windows release loading/menu frames captured, and Web loading,
  battle/HUD, portrait and failure states visually inspected.
- JavaScript syntax and `git diff --check` pass.

Local raw logs, before/after exports, traces and captures are retained outside the
repository at `D:\temp\dont-stop-20261003`. Key directories: `before-cold`,
`before-cold-trace`, `before-dense`, `final-cold-1`, `final-cold-2`, `final-dense`,
`final-camera-gates`, `final-boss`, `final-loader`, `final-playtest`, `final-aim`,
`final-menu-return`, `final-web`, `final-windows`, `final-native-boot`.
Native timing: `before-native-controlled-D.log`, `final-native-final-D.log`.

## Limits and remaining risks

- Dense combat/arena entry still has occasional long frames. Low-end GPUs,
  Safari/mobile GPU drivers and prolonged thermal load were not benchmarked.
- Some older headless scenes report resources/RIDs still in use on immediate
  shutdown despite passing assertions. The B12UI leak signature and selected
  Ogg shutdown warnings also reproduce on the extracted exact baseline. They
  remain tracked as test teardown debt; do not interpret every legacy warning
  as individually proven harmless. New suites and actual release exit paths are
  clean in the final checks.
- B5Bosses exceeded the local 240-second limit after 115 passing checks;
  M6EncounterAudit was interrupted as a long-running evidence generator. Neither
  is counted as completed. The full native nightly workflow retains these gates.
- Automated inputs and visual inspection do not establish subjective human
  acceptance of audio, feel or artwork; no such acceptance is claimed.

## Reproduction examples

Use the pinned Godot executable with the nested project as `--path`:

```text
Godot --headless --path "Don't stop" --editor --import --quit
Godot --headless --path "Don't stop" res://tests/CameraTransitions.tscn
Godot --headless --path "Don't stop" res://tests/CombatReadability.tscn
Godot --headless --path "Don't stop" --export-release "Web Release" <output>/index.html
Godot --headless --path "Don't stop" --export-release "Windows x64 Release" <output>/DontStop.exe
node "Don't stop/tools/web-loader-check.js" <export-url> <evidence-dir>
node "Don't stop/tools/web-playtest-revision.js" <export-url> <evidence-dir>
node "Don't stop/tools/web-first-shot.js" <export-url> <evidence-dir> 0
DontStop.exe -- --stress --stress-stage=39 --stress-seconds=35 --stress-scenario=D --stress-seed=20260918
```

Use isolated browser/save profiles. GPU benchmarks must run serially; verify
completed combat duration and zero pauses before comparing results.
