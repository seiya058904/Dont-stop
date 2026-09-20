# B17 candidate — NOT ACCEPTED

HUMAN_ACCEPTED = false. Draft PR 15 remains a draft; do not merge or deploy.

## Implemented

- Eleven epic/legendary held-weapon auras share a pure visual camp preview. Ordinary weapons retain no high-tier aura. Reduced-flash intensity is respected; hidden previews do not advance animation. Each weapon has a distinct orbit/rail/ember/arc form.
- B04 phase 3 schedules its burst. Four bosses have denser actual projectile waves. Whole waves wait for the existing 180-projectile budget instead of being silently truncated. A fixed angular opening is checked against the actual 12-pixel hit threshold, not the 3-pixel wall shape. Enemy laser/poison pellets and environmental laser/meteor bodies received local pixel treatment.
- Fog necessary boundaries are independent of the 128-decoration budget, deduplicated per physics tick and cleared when producers stop.
- Stages 31–39 scale ordinary spawn cap, interval and horde batch/floor by 1.25–2.0 and ordinary HP by 1.05–1.20. Elite/special caps, speed and damage are unchanged. Fog begins visually at 30 without changing Hell gameplay entry at 31; late light radius is multiplied by 0.88. Meteor radius is 56 and live allowance 3, preserving legal placement and boss suppression.
- Seven prototype purchase caps match their existing effective caps. Historical excess ownership and saved HP remain loadable and retained. Saved calculations no longer mix live base fields or temporary states. Empty-hand stats keep player/build information and show explicit empty-weapon text.
- Reload cancels an active firing action. R1Timeline now uses current global upgrades and real reload/prototype events instead of retired attachment slots.

## Evidence and failures

- `evidence/b17/manifest.json` seals 313 runtime/benchmark sources and ten datasets. B14 evidence is unchanged; new `--b17` gates are independent.
- 24 weapons × bare/late builds were remeasured for 15 seconds with movement and actual fire, seed 20260920. All 48 parameter records match current live calculation. **Weapon 113 late: 81 kills, below retained floor 85. The weapon gate fails; it was not relaxed.**
- 2,304 per-source growth observations and a 72-item registry are recorded. Growth gate: 336 passes. The registry is not a claim that every event/lifecycle combination for all 72 items has been exhaustively tested; see `b17-sources.md`.
- Real normal-health ordinary encounters 29/31/35/38/39 completed; ordinary alive-time fractions were 0.915/0.839/0.903/0.961/0.954.
- Four bosses × three controlled phases emitted complete admitted waves (28 checks). The first normal-health observer did not reset to late-game level: it completed 10/20/30 and **40 ended in death**. A separately retained, fixed-level20 full-growth run then completed all four, at 7.76/13.26/16.81/30.64 seconds with 17.5 HP remaining, without HP replenishment. The first observer's `shots` field used a wrong group name and is not a projectile count; the level20 run corrects that field. Neither autonomous route proves universal human avoidability.
- Fixed 430-zone rendered benchmark, same 15–105 second window: B16 p95/p99/max 7.189/7.597/13.717 ms; B17 7.268/7.718/14.440 ms. Published process time is a proxy; true per-frame CPU and GPU are unavailable.
- Paired stage-39 density observations, seeds 808/809/810, reset level 20, matched density-only baseline: ordinary median counts 22→39, 22→49, 24→41. Ratios 1.77/2.23/1.71. New warm p99 9.368/9.501/9.478 ms. These runs use HP refill and are not survival evidence or four-resolution GPU benchmarks. All attempts remain, including 57.965 ms product-run and 65.597 ms paired-baseline spikes.
- Current native visual tour completed but emitted **22 ObjectDB exit leaks**. A reduced four-resolution UI-only verbose reproduction reported 13 `RefCounted` instances with reference count 0. No leaking `Node` or named resource appeared in that output. Ownership/coroutine attribution is unresolved; this is not fixed or dismissed as harmless.
- A bounded upper trial (seed811) raises current stage39 cap/arrival/horde settings another 50%, corresponding to 3× B16 nominal cap/arrival. Actual ordinary median/peak were 49/70; warm p95/p99/max 8.671/9.166/14.657 ms. HP refill is used; this is not normal gameplay or a claim of 1.5× measured live count.

Selected current checks: B17Saved 13; B17Contracts 20; B17Resources 10; B17RewardMatrix 49; B17CombatMix 72; B16Save 80; B13UpgradeEffects 85; B13TalentEffects 37; M4Talents 233; B13Economy 159; B13Unequip 55; B13UI 138; R1Timeline 41. The log index retains earlier failures as well as their corrected reruns.

## Remaining acceptance

Exported Windows/Web validation and artifact identity are recorded in `b17-delivery.md`. Boss safe-route human observation, exhaustive 72-source event/lifecycle combinations beyond the documented equivalence coverage, rail late-build floor and leak ownership remain open. No claim of complete B17 acceptance is made. New current checks also include B17NativeRules13, PresentationRng8, PresentationLifecycle52, B4Fog110 and B11ShotLayer54. The last two old fixtures were updated to the explicitly authored stage30 visual-fog policy and stage31+ E13 roster respectively; their original failures remain logged.
