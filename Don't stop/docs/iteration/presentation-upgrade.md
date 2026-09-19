# Don't Stop presentation upgrade

Status: implementation in progress. `HUMAN_ACCEPTED=false`.

Base: `c2ace9c99419a87746e1809517336bdab5ce9d0f`.
Branch: `codex/presentation-upgrade-20260919`.
The user's 2026-09-19 instruction replaces the original all-or-nothing Phase 0 gate
with per-module BEFORE → implementation → rendered AFTER → regression checks.
No merge, deployment or Release is authorized.

## Reference and methods

The delivery brief and original evidence are under the ignored
`evidence/visual-upgrade-20260919/Dont-stop-visual-audit` directory.
One detached base worktree is retained at `archive/visual-upgrade-base`.
Only observation fixtures and optional B11 post-run telemetry are copied into that
worktree; its production gameplay and presentation remain the fixed base.

Camp is exercised by real Playwright input in rendered Chromium. Native Godot
Compatibility fixtures provide additional actual-rendering observations, labelled
as fixtures, not human acceptance or native mouse/keyboard playtesting. No Computer
Use recovery is part of this run.

## Implemented

- Camp: dark industrial surfaces, compact controls, selected row state, cached
  display gun models/textures, integer-scaled previews, current/candidate comparison,
  fixed transaction controls, saved focus/scroll, separate talent payment prices.
- Weapon body REDESIGN: 111, 112, 113, 114, 115, 119, 120, 121, 122, 124.
- Weapon body POLISH: 0, 4, 5, 6, 7, 116, 117, 118, 123.
- KEEP source art: 1, 2, 3, 8, 9. New art is authored integer-grid SVG in the
  original 32×16 frame, imported as shared Godot textures; shop and hand use the
  same `image` resource. Nearest sampling is explicit on the held sprite.
- Muzzle: one existing reusable emitter per gun, short directional family shapes;
  removed the extra 30-particle instance allocated for every shot. No new lights.
- HUD: persistent weapon identity and actual reload state beside magazine/reserve;
  current magazine mapping remains the original real numerator/denominator logic.
  Damage label formatting does not alter damage calculations.
- Fairness presentation: HostileZone and BossUltimate firing styles read `activated`
  rather than only the nominal warning timer. Activation/damage gates are unchanged.
- Shared effects: cache resolved footprint edges, reuse the thermal cone until release,
  keep all essential paths when the 64 optional player decoration slots are exhausted,
  and release those slots on epoch/lifetime cleanup. Gravity rings reuse fixed arrays.
- Projectile heads distinguish missiles, gravity and shards without new trajectories.
- Damage labels use 8px type on the 410x230 canvas, with two display decimals maximum.

## Evidence already checked

All paths below are relative to `evidence/visual-upgrade-20260919`.

- `phase-a-v4-*.png`: all five Camp pages, legendary purchase/equip/unequip, and
  1280×720 / 1366×768 / 1536×864 / 1920×1080 rendered browser views.
- `phase-a-build-4.json`: exact local v4 export identity. Later code changes are
  **not** represented by that export.
- `phase-a-CampPresentation-v4.log`: 38 checks passed.
- `phase-a-B12UI-v4.log`: 75 checks passed.
- `phase-a-B13UI-v4.log`: 137 checks passed.
- `weapons-before-fixed` / `weapons-after-fixed`: 24 bodies and 192 directions,
  fixed observation camera at original scale. Earlier cursor-drifting captures are
  retained but not used as the final framing comparison.
- `weapons-after-atlas.png`, `weapons-held-fixed-atlas.png`: inspected contact sheets.
- `scene-freeze-check.json`: all 19 changed scenes retain non-texture fields.
- `fire-before`: actual production shots at targets and real static walls,
  24 IDs × 2 cases × 5 sampled times; `events.json` retains ammunition/HP observations.
- `states-before`: real HostileZone gate extension reproduced without damage, yet
  the original beam already appeared active. Boss views are configured state
  observations; they are not an end-to-end proof of a naturally occurring ultimate.
- `fire-after-final`: 48 real target/wall cases, six times through 1.6s. No wall case
  damaged its target. `gravity-before-final` and `gravity-after-final` match final
  HP 99976.15 / wall HP 100000, ammunition and anchors. The earlier 1.1s mismatch
  sampled before delayed gravity resolution; it remains in the earlier record.
- `fire-reduced-final`: nine representative families with reduced flash enabled.
- `states-after-final`: 100/60/1/0, reload, unarmed and gate-extension screenshots;
  all four actual-state checks pass. PresentationContracts: 51 passes.
- `world-before`: all eight regions and fifteen real AI roles. Existing region
  palettes, geometry and role markers are retained. Baseline elite filenames collided
  for shared modifiers; the final observer includes both role and modifier in its name.
- `bosses-before-observed`: all four bosses cleared by real fire, 158 checks passed.
  `bosses-after`: B02/B03/B04 phases and ultimates observed; B01's first observation
  missed shockwave before killing the subject. `boss-B01-after-observed`: 37 passes
  after giving the real Phase III attack cycle time to complete. No boss state or HP
  injection was added. Screenshots are native rendering fixtures, not human play.
- `final-PresentationLifecycle.log`: 52 passes over ten real departures/returns;
  optional slots and hostile bursts zero each cycle, orphan nodes zero, warmed node
  count converges (different equipped weapons retain different static node counts).
- `final-menu-10`: Playwright ten menu cycles plus one final restart passed.
  `final-web-uzi-firing.png`: real input, equipped Uzi, magazine 19/24.
  `final-web-unarmed-death.png`: an unarmed manual observation, not an armed-fire proof.
- `build-current-v5.json`: artifact `1ca823f7b1852bf0e72907811dc0b17a95fe086ef0f28932881f705285f33692`.
  `build-baseline-v5.json`: artifact `997ce45970fe99814a0105304c485ddda5b348a6d703896739aff2af95be8528`.

## Failures retained

- Initial Camp B12 UI run failed because an owned detail badge omitted its price.
  Fixed and rerun successfully; the failed log remains.
- `WeaponPoseTable`: 259 checks, one failure on unchanged weapon 3
  `MUZZLE_W3_PROJECTILES_AT_MUZZLE` (approximately 10.04 px).
  The identical failure reproduced in the base worktree. This is a pre-existing
  failing check, not UNVERIFIED, and has not been removed or weakened.
- AmmoBarCoverage's new-session `GUN_EQUIPPED` assertion failed on both original
  and current trees; both start unarmed. It remains a pre-existing failure.
- Initial PresentationContracts compile failures (inherited particle preload and
  declaration order) were fixed; later imports and 51 contracts pass.
- The current B12Strength/B13Strength runs fail 22/3 whole-file manifest hashes
  after presentation edits. The frozen numbers are not being relabelled as fresh.
  Full B12 and B13 runtime benchmarks are being regenerated before their manifests.
- `final-aim` failed FOCUS_LOSS_PAUSES while another browser test had a live window.
  All other 67 checks passed, including fault injection. An isolated core run is
  being used to distinguish focus-test interference from a product regression.

## Performance protocol

Use the existing B11 driver and a standalone Chromium process on AMD RX 7900 XT /
ANGLE D3D11, viewport 1280×760, seed 20260918. Capture and other rendered game
processes are stopped during measurement. Optional `label=presentation-*` emits
the driver's raw packed samples **after** measurement; it adds no serialization
to the measured loop. Preserve full/cold results and derive a separate exact
90-second combat window after 15 seconds of warmup with
`tools/summarize-presentation-perf.js`.

Gates retained from the brief: p95 delta ≤ max(0.8ms, 5%); p99 delta ≤ max(1.5ms,
10%); at most two extra >33.3ms frames per window; no repeatable new >50ms hitch;
CPU p95 delta target ≤ max(0.5ms, 5%). No GPU-time claim without instrumentation.
Peak gauges currently cover the complete run, including warmup, and are labelled
accordingly. Seeds do not guarantee identical realtime combat loads; compare
actions, shots, rounds and load counters as well as timing.

## Remaining work (not waived)

- Validate current muzzle/HUD/activation changes in rendered AFTER and scoped tests.
- Finish attack/impact family treatment, sustained effects and decoration budgets
  after their relevant performance BEFORE; preserve independent originals if blocked.
- E01–E15, 14 elite families, B01–B04, wall/fog/reduced-flash/boundary observations.
- Region R1–R8 and Boss HUD/growth feedback review; retain mature visuals where
  observations do not justify changes.
- Three matched hot Stage39 runs before/after, Stage40 phases/ultimate, projectile,
  laser and VFX-heavy loads; 10-cycle lifecycle and Camp pressure.
- Current full native/Web workflow checks, save/economy/fairness/LOS regressions,
  final real browser entry/return/restart and native platform status.
- Final scoped diff, feature-branch commits/push and PR (Draft until missing
  validation is resolved). No human acceptance claim.
