# Don't Stop visual upgrade — implementation and validation

`PARTIALLY_IMPLEMENTED` / acceptance pending. The planned visual scope is implemented,
but the unresolved performance/test limitations below prevent a blanket acceptance claim.
`HUMAN_ACCEPTED=false`. Draft PR: https://github.com/seiya058904/Dont-stop/pull/15

## Scope and build identity

- BASE_SHA: `c2ace9c99419a87746e1809517336bdab5ce9d0f`.
- Feature branch: `codex/presentation-upgrade-20260919`.
- Playable production SHA: `5d5d3eb9506671250e8fbd3ac19b8f8fbde0c53c` (v12).
- Web artifact: `8881c1be6872add7c1b80f43b3dd4da857447d646568de2f2db73cff178c879d`.
- Windows build: `build/windows/Don't stop.exe`; Web files: `build/web/index.html`.
- One original-production worktree: `archive/visual-upgrade-base`. Added observation
  fixtures are identified separately; modified production is never labelled BEFORE.

The user's 2026-09-19 instruction replaced the global Phase0 gate with per-module
BEFORE → implementation → actual rendered AFTER → regression. Playwright + Chromium
is the browser method. Native Godot Compatibility fixtures and exported Vulkan/Forward+
smoke are separate methods, not Computer Use or human acceptance. No global rules,
Skills, MCP/security configuration, dependency installation, merge, deployment or Release.

## Implemented scope

| Area | Result |
|---|---|
| Camp, all five pages | Dark industrial hierarchy, selected rows, integer previews, current/candidate stats, fixed real transaction actions, focus/scroll, success-only feedback; actual purchase/equip/unload/filter/sort/payment/rank/save behavior retained |
| 24 weapon bodies | REDESIGN 111/112/113/114/115/119/120/121/122/124; POLISH 0/4/5/6/7/116/117/118/123; KEEP 1/2/3/8/9 |
| Shared weapon resources | 19 authored 32×16 integer-grid SVG textures; shop/hand/HUD share the same resource; nearest sampling, unchanged anchors |
| Attack families | Short reusable directional muzzle shapes; removed per-shot 30-particle allocation; distinguish projectile heads; actual resolved paths retained |
| Shared effects | Cached footprint geometry, reused thermal cone, fixed gravity arrays, 64 optional player-decoration slots plus existing 32 hostile bursts; no new lights/fullscreen shaders |
| Enemies/Bosses | Actual activation flag controls hostile/Boss firing paint during fairness extensions; existing damage gates, geometry, AI and mature role/elite markers retained |
| Regions/HUD/growth | All eight regions reviewed and retained; actual weapon/reload beside magazine; readable fractional damage and nonnumeric status; existing talent triggers retained |

Full [Camp migration/enemy/Boss/region decisions](evidence/presentation/coverage.md)
and [24-weapon matrix](evidence/presentation/weapon-matrix.json) are committed.
Rename suggestions remain suggestions: 4 “异形者步枪”, 6 “持续束流枪”, 8 “五联霰弹枪”.

## Freeze and visual evidence

- [Thirteen protected files](evidence/presentation/protected-files.json) are byte-identical
  to BASE_SHA, including balance/save/AI/geometry/fog/BossHUD. All 19 scene edits retain
  non-texture fields; all 192 held anchor records match the original.
- Complete production shoot-animation and Camp-render RNG sequences match baseline on
  headless, rendered native and Chromium. Pinned Godot 4.7.2 legacy draws are preserved:
  shot 2 headless/3 rendered, BoomBoi display recreation 2 headless/4 rendered.
- Camp five pages and four viewports (1280×720, 1366×768, 1536×864, 1920×1080) were
  actually viewed. Final v12 1280×760 flow separately confirms ordinary/legendary,
  unowned/owned, comparison, purchase, equip/unload and reload persistence.
- Real purchases: 9999→9939 (ordinary), then 9939→6339 (legendary). On restart,
  original Demo startup refills the wallet to at least 9999; owned guns persist.
- Final 24 target +24 wall captures pass; reduced-flash checks cover nine families
  in 18 target/wall cases. Six times through1.6s include delayed gravity resolution.
  47/48 full event dictionaries exactly match baseline. Beam6's4/5-tick sampling
  boundary was independently repeated with four ticks on both sides; its script is unchanged.
- All15 enemy roles, all8 regions,18 elite combinations covering14 modifier families,
  and all4 actual Boss phase/ultimate paths were viewed. Durable Boss observers use400HP,
  not an authored8HP clear claim. Explicit state/footprint/status fixtures are labelled.
- Lifecycle: ten departures/returns and ten browser menu cycles; optional effects and
  hostile bursts return to zero, no growing orphan count or residual input.

[Selected screenshots and evidence index](evidence/presentation/README.md).
Complete local gallery: `evidence/visual-upgrade-20260919/review.html`.
Raw paths in the matrix are local evidence paths, not claims that all images are in Git.

## Performed checks

| Checks | Result |
|---|---|
| BaselineRegression / B11Stages / B11Fairness / B6Progression | 4 /57 /61 /41 passes; Hell progression41 |
| B3Hazards / B4Fog | 128 /110 passes |
| B12 Catalog / Save / UI / LOS | 182 /14 /75 /12 passes |
| Fresh B12 measurements + Strength | 72 real scenarios, regenerated manifest,195 passes |
| B13 Catalog / UpgradeEffects / TalentEffects / Economy / Unequip / UI | 530 /85 /37 /158 /52 /137 passes |
| Fresh B13 measurements + Strength | 8 builds×3 real scenarios, regenerated manifest,143 passes |
| M4Talents / M3Weapons | 233 /72 passes |
| PresentationContracts / States / Lifecycle | 52 /6 /52 passes |
| Final Camp / RNG / CampPressure | 38;8 headless+9 rendered+paired full Web sequences;242 passes |
| M6 / M8 encounters / M10Bosses / M10Density | 30 zero-cleanup-failure encounters;30/60 checks;24 passes;11/6 passes |
| Browser | Actual normal-entry/save/reload/menu/input flows; stage route42 checks; final purchase/equip screenshots viewed |
| Windows v12 export smoke | Vulkan/Forward+, start/Camp/depart/switch/fire PASS, exit0; not native human playtesting |

Checks ran at their relevant implementation revisions; historical images are not
mislabelled as the final binary. Final Camp cache changes do not alter B12/B13 measured
combat inputs. Build identities, raw samples and outcome logs distinguish revisions.

## Performance and acceptance limits

[Full hardware table, counters, raw-data archive and reproduction](evidence/presentation/performance.md).
Chromium/AMD RX7900XT/ANGLE D3D11,1280×760,seed20260918; exact15..105 combat-second
windows, three runs each normal/dense/mixed/Stage40, screenshot capture separate.

- Final comparison uses v11 normal/mixed/Stage40 and v12 dense; numeric frame
  p95/p99/extra->33.3 gates pass in12/12 pairs. The full earlier v11 table is retained.
- Dense clean run 1 process and mixed run 1 physics/run 2 process proxy gates **fail**. They remain failed, not UNVERIFIED.
  Godot's monitors publish one-second maxima, so these repeated samples do not prove
  independent per-frame CPU durations or isolate a stable added cost.
- Dense clean run 1 has one 78.8ms hot hitch; runs 2/3 have none. The first run
  overlapped archive compression; it remains recorded and was replaced by that
  explicitly named clean run before reading the replacement outcome.
- Stage40 hot-window >50ms flags remain in2/3 AFTER runs. Every original run has a
  similar~132ms early hitch at12–14.9s; AFTER at12.9–17.4s straddles the fixed15s
  warmup boundary. Full timeline is retained; no window was moved to obtain a pass.
- Mixed AFTER still has absolute60–142ms hitches. Relative improvement is not smoothness acceptance.
- GPU time, true per-frame CPU and Web release static memory: **N/A**, unavailable
  through the configured monitors. Missing values are not0 and are not a performance pass.
- Camp final v12 native synchronous290-call measurement: p50 7.240→3.213ms,
  p95 10.904→6.734ms, max14.002→7.531ms. Warmed closed nodes281/283 stable,
  orphans0. Both sample collectors retain152672bytes; cleanup results are included.
  This is method cost, not physical-input or GPU-completion latency.

## Failed checks and corrections retained

- Baseline-confirmed failures: weapon3 muzzle offset(~10.04px) in WeaponPoseTable;
  fresh unarmed AmmoBarCoverage; Windows Chromium FOCUS_LOSS_PAUSES; SaveRunner and
  ContractRunner `instance_id` dictionary errors. Forced-quit exit0 is not a pass.
  Linux Web CI focus pass does not replace the Windows failure.
- Introduced price-badge omission, premature activated paint, nonnumeric shield text
  becoming0, global RNG drift, and headless Camp four-draw compensation were corrected
  and retested. Their failed logs remain. No assertion was deleted or threshold lowered.
- Earlier v6/v10 performance failures are retained, including the pre-RNG-fix runs.
  Invalid queued/freed Camp observer v7-v9 produced false zero-draw Web evidence;
  corrected full-render v10/v12 observations replace its evidence, not its failure record.
- B13Strength's original read-only-array `.sort()` error was fixed by duplicating the
  constant array; all checks remain. Measurements were regenerated before manifests.
- Same-SHA CI B5Bosses results differed; local AFTER reproduced B02's two payload
  assertions failing while baseline passed166. The observer said it held still but
  still emitted close-range dash input. Test-only commit `1121603` suppresses dash
  while the observer holds position. Targeted original/new B02 runs both pass 37,
  including real landed percentage damage. No Boss payload/AI/timing or assertion
  changed. Complete native CI now passes on both push and PR runs; all failed attempts remain recorded.

## Delivery boundary

Feature branch commits/pushes and Draft PR are authorized. Main still equals the fixed
baseline at the latest fetch. Native human acceptance and unresolved performance
acceptance are not supplied by this tool run. No deployment or Release was performed.
`HUMAN_ACCEPTED=false`.

## Final CI closeout

Gameplay/test revision `11216033cd84ab84e4ebdf377848489e1b92605c`:
[native PR run](https://github.com/seiya058904/Dont-stop/actions/runs/35450919275),
[native push run](https://github.com/seiya058904/Dont-stop/actions/runs/35450915626),
and [Web run](https://github.com/seiya058904/Dont-stop/actions/runs/35450919484)
all succeeded. Native contracts and pressure passed, including the full corrected
B5 observer. All six Web gates passed. Deployment and deployed-site smoke were skipped.
Final evidence and performance-report tools do not change production code; the
playable v12 identity above remains the one actually exercised locally.

Owned browser/test processes and local preview servers were stopped after validation.
Generated test sidecars and the unused baseline Windows export were removed by exact
path; the single baseline worktree and its valid Web reference remain available.

## Targeted performance closeout / visual freeze

[Bounded tail analysis](evidence/presentation/performance-tail-closeout.md) reproduces
the existing fixed-window results and aligns the saved raw frames with events and
interval timers. No production code changed and no new runtime measurements were run.
The three proxy failures remain FAIL. Dense, Stage40 boundary, and mixed long-frame
attribution remain unresolved; baseline long-frame presence does not prove no regression.
Windows v12 EXE/PCK hashes were rechecked; 1121603 and b4d0749 do not change its production code.
Visual implementation is frozen, PR remains Draft, HUMAN_ACCEPTED=false; await human feedback.
