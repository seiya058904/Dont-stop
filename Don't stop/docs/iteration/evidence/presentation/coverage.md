# Visual coverage and retained decisions

All decisions refer to BASE_SHA `c2ace9c99419a87746e1809517336bdab5ce9d0f`.
Production names, IDs, numeric balance, saves, map geometry, input and camera policy
are retained. The brief's three rename suggestions remain suggestions: weapon 4
“异形者步枪”, 6 “持续束流枪”, 8 “五联霰弹枪”. They are not applied.

## Camp migration

| Area | Preserved behavior | Presentation |
| --- | --- | --- |
| Header | Wallet, unsaved/retry state, settings/tools, return | Compact hierarchy; save retry remains directly accessible |
| Weapons | Name/ID/mechanism search, category, five qualities, owned filter, sort, purchase/equip/unequip | Selected rows, shared weapon resource, cached integer preview, real current/candidate values, fixed action area |
| Upgrades | Existing one-time/rank rules and payments | Same list/detail/action hierarchy; actual successful transaction feedback |
| Supply | Magazine packages and health availability/prices | Existing purchases with consistent detail/action layout |
| Talents | Both gold and talent-point payments, actual next rank and maximum rank | Each payment states its own price; no duplicated economy model |
| Departure | All 40 stages remain selectable | Consistent selected-row and detail hierarchy |

Evidence: `phase-a-v4-*`, `final-web-*`, CampPresentation, B12UI, B13UI,
B13Economy and the real Web save/fault-injection runs. Four viewport sizes were
viewed. The v6 purchase feedback captures additionally show the real 60-gold
deduction, current equipment and settled success message.

## Weapons and attack families

The complete 24-row [matrix](weapon-matrix.json) records 10 REDESIGN, 9 POLISH and
5 KEEP decisions. The five retained compact source silhouettes remained legible
in actual body and held views. Former shared silhouettes now differ for
120/9, 121/8 and 112/114/4. Hand, shop and HUD use the same image resource.

Actual firing covers ordinary projectiles and spread, pulse/rail/arc, fan/thermal,
ricochet/fragments, rockets/homing, gravity/returning and rotary/burst. One reused
muzzle emitter gives each family a brief directional shape. Essential resolved
paths remain; only optional endpoint decoration is budgeted. Thermal and gravity
reuse their visual nodes/arrays without changing ticks or pull. All 24 target and
24 wall cases passed in each final paired capture. The delayed gravity endpoint
is sampled through 1.6 seconds. Beam 6's first 4/5-tick variance and matched repeat
are retained, rather than hiding a transient discrepancy.

## Enemies, elites and bosses

These are actual rendered observations in `world-before`, `world-after-final`,
`bosses-before-observed`, `bosses-after`, and `boss-B01-after-observed`. Native
observers freeze camera framing; they do not constitute human control acceptance.

| IDs | Final decision and reason |
| --- | --- |
| E01, E02 | KEEP body/contact cues; additional persistent halos would obscure ordinary threat density |
| E03, E11 | KEEP heavy/side-pressure identities and actual motion; existing charge family provides the readable route |
| E04 | KEEP locked path and direction arrows; B11Fairness verifies lock does not resume tracking |
| E05 | KEEP bounded projectile body/tail; no new permanent aiming line |
| E06 | KEEP fuse and owner-bound blast warning; existing cancellation contracts retained |
| E07 | KEEP actual summon buds and cap-aware spawning; no false spawn indicator added |
| E08 | KEEP short actual-heal connection; no persistent green network |
| E09 | KEEP directional shield arc and break state, avoiding an all-direction defense implication |
| E10 | POLISH shared activation semantics; retain fixed artillery marker and wall clipping |
| E12 | KEEP enemy fan/death footprint and hostile palette, distinct from player fan 115 |
| E13 | KEEP control waveform/ring and real root/immune feedback |
| E14 | POLISH shared activation semantics; retain TRACK/LOCK/FIRE, clipping and FogPierce |
| E15 | KEEP poison boundary/timer and exit behavior; extra bubbles are unnecessary at full density |
| All 14 elite modifier families | KEEP existing family color, bracket and label. Complete atlas covers 18 role/modifier combinations, including all four boss roles |
| B01 | POLISH shared activation semantics; retain actual slam/shockwave perimeter and phase markers |
| B02 | POLISH actual ultimate activation edge; retain moving egg, poison/control and wall behavior |
| B03 | POLISH activation edge; retain declared sweep and four resolved laser paths |
| B04 | POLISH activation edge; retain actual drifting safe center and visible safe-circle priority |

The original telegraph already has contrast edges, timers, arrows and family
palettes. The confirmed defect was premature active-looking paint during extended
fairness waiting. The change reads the actual activation flag without changing
the wait or damage. Boss observations use real weapon damage and actual AI;
the durable observer's 400 HP is test setup, not the authored 8-HP difficulty.

## Regions, HUD and growth

R1 through R8 were viewed individually. Their static palettes, geometry and
existing vents/poison/hazard distinctions are retained. No ambient layer, new
light or full-screen shader was added; the conditional ambient suggestions did
not justify increasing full-density noise.

HUD now groups real weapon identity, actual magazine count and reload state;
wallet/experience remain secondary. Boss thresholds and phase labels are kept.
Damage display rounds 0.875 to 0.88 while retaining source damage, and never
prints zero for a positive fractional hit. Camp transaction feedback is tied to
successful results only. Existing talent trigger behavior remains covered by
M4Talents and B13TalentEffects; no new rolls or parallel cooldown state exist.

## Evidence limits

Screenshots are observations, not performance claims. Hardware performance is
recorded separately in the main ledger. Windows standalone startup and native
rendering fixtures are verified, but native human mouse/keyboard acceptance is
not. The baseline weapon-3 muzzle, fresh-session AmmoBarCoverage and Web focus
failures remain explicitly failed. `HUMAN_ACCEPTED=false`.

## Observer setup details

The warning before/after pair deliberately advances a real HostileZone past its
nominal warning while the visibility gate is still waiting; it does not shorten
or bypass the production damage gate. BossUltimate state-sheet images set the
observer's visual state explicitly; separate boss runs exercise real AI phases
and attacks. The shield text sheet calls the existing feedback channel with an
explicit status string to test legibility; it is not presented as a filmed T19
proc. Real talent behavior is covered by the separate gameplay regression tests.

The latest label uses Godot's default alpha material, retaining the 8px text and
dark outline without a redundant CanvasItemMaterial. Its bright/dark rendering
comparison is `status-default-material-comparison.png`; States6 and Contracts52
pass. Performance results for that revision remain separate from v10 failures.
