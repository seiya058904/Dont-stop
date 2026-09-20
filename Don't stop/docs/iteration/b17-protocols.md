# B17 source and presentation protocols

## Source reading and formulas

The 72-row registry in `b17-sources.md` is generated from the actual reward registry, upgrade definitions and talent definitions. Raw definitions retain their duration, cooldown, values and units where authored. Missing fields mean not separately authored, not zero. Individual event coverage is deliberately distinguished from a passive delta.

|Source group|Calculation / event|Refresh / persistence|Evidence|
|---|---|---|---|
|All 24 upgrades|`EffectiveStats.calculate` deduplicates IDs; current and future guns share ownership. `damage` adds to T01/base percent, `damage_mul` multiplies independently; magazine/reload multipliers multiply; crit adds probability points.|`Demo.refresh` updates held/owned guns; schema6 global IDs restore once.|B13UpgradeEffects uses an independent field formula on guns 0 and 6 (85 checks); B17 growth matrix and all-24 firing supplement it.|
|All 24 talents|Definition values apply by rank. T02 becomes per-tick damage for thermal and overflow damage above rotary 24/s; charged cooldown remains separate from charge time.|Rank snapshot is taken on emission where context-based; movement/shield/resource state has its own live consumer.|B13TalentEffects 37, M4Talents 233, B17CombatMix 72; these are separate from 2,304 passive observations.|
|R0/R1|Immediate +10 gold / full heal; not an additional persistent stat multiplier.|One-off reward entry is removed; historical purchase record persists.|B17Resources actual wallet/HP assertions.|
|R2/R3/R4/R5/R6/R7/R9/R10/R11|Caps 4/4/10/6/6/3/3/1/4 respectively. R2 max HP, R3 incoming chance, R4 direct doubling, R5 speed, R6 third-hit extra damage, R7 kill drop, R9 charged hit, R10 first 100 kills, R11 direct extra damage.|New purchases stop at cap. B17Saved restores recorded excess counts and exact HP without replaying growth. R10 lifetime counter persists.|Reward matrix first/max direct events; selected independent HP/resource checks; B17Saved 13. Random-proc observations are not claimed as a probability-distribution proof.|
|R8|Three direct kills within one second activate +0.2 fire-rate contribution; rank controls duration, not additive amplitude.|Remaining buff and kill window persist; removal reverses only an active buff.|B17Resources actual activation; R1Timeline lifecycle.|
|R12/R13/R15/R16|Direct burn/slow/hit-counter/critical-fragment hooks; no recursive direct callbacks from derived damage.|CombatReward state has hits/kills/cooldown/armed/movement fields and explicit save/restore.|24-reward matrix observations; exhaustive event ordering across every combination is not claimed.|
|R14|Elite/Boss hunter multiplier is applied once, tracked by `hunter_applied`; this is an explicit exception to direct-only hooks.|Read at hit resolution, then marked in resolved context.|Source-read `Combat.hit`; reward matrix. It is not part of the saved base-stat calculation.|
|R17/R18/R19/R21|Incoming armed reduction / direct-kill healing / low-HP emergency healing / direct-kill reserve gain.|Cooldown and counters persist; percentage damage does not consume R17 reduction.|B17Resources exact HP and reserve changes.|
|R20/R22/R23|Ordinary-target impulse / 2s movement momentum / pickup bonus.|R22 activation refreshes guns and movement; pickup cache is per physics frame.|Reward matrix; B17CombatMix uses actual reward states; B16Pickup and source-level consumers.|

Formula example checked against actual target HP: `(scene base damage + level damage) × weapon power × (1 + 0.15 T01 + 0.15 A114) × (1 + 0.5 R9)`, then cents rounding. The target's HP delta, not the calculator output, is the assertion. Purchase-order permutation is checked for A114+A110. This does not claim identical seeded RNG outcomes under arbitrary random-proc purchase permutations.

Magazine floors to an integer and at least 1; reload has the product's minimum; crit clamps to 0–1; range is length, radius is not area, rotary 24/s is distinct from thermal 10 tick/s. `StatLedger` is explanatory provenance; marginal “without this item” differences must not be added together as total growth.

## Native and derived event qualifications

|Path|depth / native|Direct crit and prototype hit/kill hooks|Native linked A9/fission hit; T11/T19/T24/A124 kill gains|T10 kill stacks|
|---|---|---|---|---|
|Arc roots|0 / true|Eligible|Eligible|Eligible|
|Arc later hops|1 / true|Ineligible|Eligible, with global cooldown/cap|Eligible|
|Weapon-native fragments (first three)|1 / inherited true|Ineligible|Eligible|Eligible|
|Additional growth fragments|1 / false|Ineligible|Ineligible|Eligible|
|Thermal primary contact|0 / true|Eligible|Eligible|Eligible|
|Burn records, including heat-related DoT|1 / false|Ineligible|Ineligible|Eligible|
|Growth explosion / secondary proc|1 / false|Ineligible|Ineligible|Eligible|

The matrix follows `Combat.hit`, `Combat.chain`, `MechanismProjectile`, `BaseMonster.apply_burn/onDie` and `Demo.on_kill`. B17NativeRules independently drives depth1 true/false actual kills and asserts reserve +1 per five native kills, one +0.2 HP cooldown event, ceil(8% magazine) refill, five shield reductions totaling 1.75s, untouched direct-only prototype state, and T10 stacks. B17CombatMix separately fires all weapon families with three sources. No depth flattening was introduced.

Delayed context damage remains frozen; hit-time prototype rules such as R14 are live by existing design. The saved calculator correction isolates validation inputs, not every live combat callback. Save/load, pause/death/switch/return and proc eligibility are distinct contracts and are not conflated.

## Impeccable / UI verification

Used local Impeccable 4.3.1 at `C:/Users/admin/.agents/skills/impeccable/SKILL.md`, its `scripts/impeccable.cmd context`, and audit/critique/layout/harden/animate/polish references plus craft-floor. Applied hierarchy, contrast, stable layout and clear state copy to Godot Control/Canvas. DOM/ARIA checks do not apply. No React/framework installation or UI redesign was introduced.

|Surface|Current evidence|Boundary|
|---|---|---|
|Camp five pages, carry and detail|Exported native and Web four sizes; native weapon preview; Web real purchase and paid talent ranks|Detail body is intentionally scrollable; actions remain separate.|
|Empty stats, five tabs|Exported native four sizes; B13UI 138 checks|No placeholder gun.|
|Search, across-page navigation, full-rank state|Exported Web mouse/key flow and screenshots|Zero-result / every long string combination not exhaustively imaged.|
|Save/payment/refund/unequip|B16Save 80; B17Saved 13; B13Economy 159; B13Unequip 55|Automated state contracts, not a screenshot of every modal.|
|Settings/pause, main menu and combat HUD|Existing retained implementation plus current boot/exit and in-game captures|No claim of fresh exhaustive visual coverage of every settings/error/BossHUD state.|
|Eleven high-tier guns|Exported native dark and normal OFF/ON, eight directions, six-second idle/move/fire clips; ordinary0 control|Visual quality and avoidability still need human acceptance.|

Native engine framebuffers are actual physical render output (e.g. 1366×766 inside a requested 1366×768 window with aspect preservation), not a 410×230 image rescaled afterward. Separate DPI-aware OS window captures confirm the physical client at all four sizes. OS captures remain local because they include window chrome; repository evidence uses game framebuffers only.
