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

- `evidence/b17/manifest.json` seals 296 runtime/benchmark sources and eight datasets. B14 evidence is unchanged; new `--b17` gates are independent.
- 24 weapons × bare/late builds were remeasured for 15 seconds with movement and actual fire, seed 20260920. All 48 parameter records match current live calculation. **Weapon 113 late: 81 kills, below retained floor 85. The weapon gate fails; it was not relaxed.**
- 2,304 per-source growth observations and a 72-item registry are recorded. Growth gate: 336 passes. The registry is not a claim that every event/lifecycle combination for all 72 items has been exhaustively tested; see `b17-sources.md`.
- Real normal-health ordinary encounters 29/31/35/38/39 completed; ordinary alive-time fractions were 0.915/0.839/0.903/0.961/0.954.
- Four bosses × three controlled phases emitted complete admitted waves (28 checks). Separate normal-health autonomous observations completed 10/20/30; **40 ended in death**. Controlled-phase HP refill is explicitly not survival evidence. The survival observer's `shots` field used a wrong group name and must not be treated as a projectile count.
- Fixed 430-zone rendered benchmark, same 15–105 second window: p95 7.268 ms, p99 7.718 ms, max 14.440 ms. Published process time is a proxy; true per-frame CPU and GPU are unavailable.
- Paired stage-39 density observations, seeds 808/809/810, reset level 20, matched density-only baseline: ordinary median counts 22→39, 22→49, 24→41. Ratios 1.77/2.23/1.71. New warm p99 9.368/9.501/9.478 ms. These runs use HP refill and are not survival evidence or four-resolution GPU benchmarks. All attempts remain, including 57.965 ms product-run and 65.597 ms paired-baseline spikes.
- Current native visual tour completed but emitted **22 ObjectDB exit leaks**. A reduced four-resolution UI-only verbose reproduction reported 13 `RefCounted` instances with reference count 0. No leaking `Node` or named resource appeared in that output. Ownership/coroutine attribution is unresolved; this is not fixed or dismissed as harmless.

Selected current checks: B17Saved 13; B17Contracts 20; B17Resources 10; B17RewardMatrix 49; B17CombatMix 72; B16Save 80; B13UpgradeEffects 85; B13TalentEffects 37; M4Talents 233; B13Economy 159; B13Unequip 55; B13UI 138; R1Timeline 41. The log index retains earlier failures as well as their corrected reruns.

## Remaining acceptance

Exported Windows/Web validation and artifact identity are recorded separately when complete. Boss safe-route human observation, exhaustive 72-source event combinations, B04 normal-health completion, rail late-build floor and leak ownership remain open. No claim of complete B17 acceptance is made.
