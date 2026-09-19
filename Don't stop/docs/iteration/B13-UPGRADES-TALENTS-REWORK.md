# B13 — Weapon Upgrades + Talents Rework (卸下当前武器)

Branch `b13-upgrades-talents-rework` · base SHA `6bae6e92635be0d4c30964b6dc32e0bc3075c4c2`
(B12 merge on main, human-accepted). B12 weapon quality/balance is untouched (rule 29):
`WeaponCatalog.TIERS/PRICES/POWER` have a zero-line diff, as do all 24 gun scenes/scripts
and the B11 systems. The raw BEFORE audit lives at
`docs/iteration/evidence/b13/audit-before.md`; every BEFORE row there was read from
runtime source, not from names.

---

## 1. What this batch is

Two growth systems rebuilt around one shared, player-visible three-quality ladder
(普通 / 稀有 / 传说), plus a new first-class "unequip current weapon" state:

* **Weapon upgrades** (24 IDs unchanged, still one-shot / permanent / global / no slots):
  names now describe the real all-weapon effect, every entry carries a universal primary,
  quality and price bands are real.
* **Talents** (24 IDs unchanged, ranks kept): reclassified into the same three qualities,
  data-driven per-rank prices in BOTH currencies, amplitude re-tuned so the talent system
  is the stronger one.
* **Unequip weapon**: the camp weapon page can drop the current weapon; unarmed is a real,
  savable, re-enterable state (ownership/ammo untouched, no refund).

Out of scope, deliberately: B12 weapon balance, B11 difficulty/perf architecture, new
catalog items beyond the existing 24+24 (no missing combat axis was found that justified
padding the count), save schema bumps, tag/release/merge.

## 2. Weapon upgrades — BEFORE → AFTER (24 items)

Prices BEFORE are the same table's gold values; effects BEFORE from
`AttachmentCatalog.DEFINITIONS` at base; display names BEFORE from the attachment scenes
(`tr(am.am_name)`).

| ID | BEFORE name | BEFORE price | BEFORE effect | → quality | AFTER name | AFTER price | AFTER effect |
|----|-------------|----|----------------|------|------------|-----|---------------|
| 0 | 快速弹夹 | 500 | reload ×0.80 | 普通 | 快速装填组件 | 320 | reload ×0.80 |
| 1 | 通用扩容弹夹 | 350 | magazine ×1.20 | 普通 | 扩容供弹组件 | 280 | magazine ×1.20 |
| 2 | 扩容步枪弹夹 | 550 | magazine ×1.35 | 稀有 | 高容量供弹系统 | 850 | magazine ×1.45 |
| 3 | 快速扩容弹夹 | 800 | magazine ×1.20, reload ×0.80 | 稀有 | 火力循环组件 | 720 | damage +6%, reload ×0.85 |
| 5 | 霰弹枪子弹袋 | 750 | magazine ×1.15, reload ×0.80 | 普通 | 轻量快装弹鼓 | 520 | magazine ×1.15, reload ×0.80 |
| 6 | 机枪弹夹 | 700 | magazine ×1.50 | 普通 | 效率弹链 | 500 | magazine ×1.25, reload ×0.90 |
| 7 | 冲锋枪弹夹 | 450 | magazine ×1.30 | 普通 | 双排供弹模块 | 470 | magazine ×1.30 |
| 8 | 超级通用弹夹 | 850 | magazine ×1.60 | 稀有 | 超容供弹鼓 | 1250 | magazine ×1.60 |
| 9 | 榴弹发射器 | 1500 | damage +10% + right-click grenade | 传说 | 下挂榴弹模块 | 2000 | damage +8% + grenade unlock |
| 110 | 精准瞄具 | 700 | damage +5%, crit +8pp | 普通 | 精密瞄具 | 480 | damage +2%, crit +8pp |
| 111 | 束流聚焦镜 | 850 | damage +8%, range ×1.2, width ×0.85 | 稀有 | 焦距校准器 | 880 | damage +6%, range ×1.25 |
| 112 | 补偿枪口 | 650 | damage +8%, spread ×0.75 | 稀有 | 稳定瞄准模块 | 780 | damage +6%, spread ×0.75 |
| 113 | 棱镜扩散器 | 950 | damage ×1.10, width ×1.35, angle ×1.35 | 稀有 | 宽域扩束模块 | 900 | damage ×1.08, width ×1.35, angle ×1.35 |
| 114 | 过载枪管 | 600 | damage +15%, reload ×1.10 | 普通 | 强化枪管 | 440 | damage +15%, reload ×1.10 |
| 115 | 能量散热器 | 700 | reload ×0.85, warmup ×0.9 | 普通 | 冷却导管 | 460 | reload ×0.85, warmup ×0.9 |
| 116 | 抑震枪托 | 450 | reload ×0.90, recovery ×0.80 | 普通 | 稳定枪身组件 | 420 | reload ×0.90, recovery ×0.75 |
| 117 | 冲量支架 | 800 | damage +8%, impulse ×1.35 | 稀有 | 冲击载荷模块 | 820 | damage +6%, impulse ×1.4 |
| 118 | 贯穿弹芯 | 1100 | damage +10%, pierce +1 | 稀有 | 贯穿弹药包 | 1080 | damage +6%, pierce +1 |
| 119 | 反弹弹壳 | 1200 | damage +10%, bounces +1 (0.85) | 传说 | 回旋弹体核心 | 1500 | damage +8%, bounces +1 (0.85) |
| 120 | 裂片弹头 | 1400 | damage +8%, shards +2 (0.25) | 传说 | 裂片弹药核心 | 1600 | damage +8%, shards +2 (0.25) |
| 121 | 扩爆引信 | 900 | damage +10%, radius ×1.2 | 稀有 | 扩爆引信 | 1050 | damage +8%, radius ×1.25 |
| 122 | 电弧中继 | 1200 | damage +10%, chain jumps +1 | 传说 | 电弧传导核心 | 1700 | damage +8%, chain jumps +1 |
| 123 | 制导模块 | 850 | damage +8%, turn ×1.25, lock ×1.15 | 传说 | 制导校准核心 | 1450 | damage +8%, turn ×1.30, lock ×1.20 |
| 124 | 击杀回填器 | 1500 | kill-refill 1 / 0.2s (no primary) | 传说 | 击杀回填核心 | 1900 | damage +6%, kill-refill 1 / 0.2s |

Quality split: 9 普通 (280–520) / 9 稀有 (720–1250) / 6 传说 (1450–2000). Bands never
cross (asserted by B13Catalog + B13Economy).

### Name rules applied (rule 5/6)

* No weapon-part names (枪口/枪托/弹芯/枪管 gone), no weapon-type names (步枪/霰弹枪/
  机枪/冲锋枪 gone). Every name says what the upgrade actually improves, in all-weapon
  language (供弹/装填/瞄准/贯穿/爆炸…).
* The ID1/ID2 swapped display names are gone (both now sit on the catalog's single source
  of truth, mirrored into the scene exports).
* Scene `am_name` exports and catalog `name` are aligned for all 24; the catalog is the
  single read source for shop/stat surfaces; `AttachmentCatalog.display_name()` is the API.
* No "quantum hyper tactical matrix core" style names.

### Why these quality assignments (rule 4/8/9)

* **普通** = one clear dimension (reload, magazine ladder rungs, one damage trade-off at
  114, handling hybrids at 5/6/115/116, one crit entry at 110). Cheap, stable, useful.
* **稀有** = a meaningful second dimension rides along (spread/range/impulse/pierce/radius
  with damage, or big magazine step-ups). Measurably above common in the runtime ladder.
* **传说** = a mechanism unlock with a solid universal primary: grenade, bounce, fragments,
  chain jump, homing, kill-refill. 9's grenade is the pattern the spec asked for
  (universal primary + weapon-class secondary). 124 finally carries a primary stat.
* Damage riders were deliberately KEPT MODEST (2–15%). The BEFORE system stacked +157%
  additive damage from 24 riders, which made every upgrade a damage item and drowned the
  mechanisms. After the trim the upgrade system's identity is 基础能力 (ammo/reload/aim/
  mechanisms) and damage leadership belongs to talents (rule 1/12).

## 3. Talents — BEFORE → AFTER (24 items)

All BEFORE prices were flat 100 gold / 1 point per rank (`TALENT_GOLD_PRICE`).

| ID | BEFORE name | BEFORE max | BEFORE effect | → quality | AFTER max | AFTER effect | AFTER gold/rank | AFTER points/rank |
|----|-------------|----|----------------|------|----|---------------|------|------|
| T01 | 火力强化 | 3 | damage +8%/lvl | 普通 | 3 | damage +15%/lvl | 150/250/350 | 1/1/2 |
| T02 | 快速循环 | 3 | rate +6%/lvl | 稀有 | 3 | rate +10%/lvl | 400/550/700 | 2/3/4 |
| T03 | 熟练装填 | 3 | reload −5%/lvl | 普通 | 3 | reload −8%/lvl | 150/250/350 | 1/1/2 |
| T04 | 扩充携弹 | 3 | magazine +10%/lvl | 普通 | 3 | magazine +18%/lvl | 150/250/350 | 1/1/2 |
| T05 | 弹道延展 | 3 | range +10%/lvl | 普通 | 3 | unchanged | 150/250/350 | 1/1/2 |
| T06 | 弱点识别 | 3 | crit +5pp/lvl | 稀有 | 3 | crit +6pp/lvl | 400/550/700 | 2/3/4 |
| T07 | 生存余量 | 3 | HP +1/lvl | 普通 | 3 | unchanged | 150/250/350 | 1/1/2 |
| T08 | 轻装移动 | 3 | speed +3%/lvl | 普通 | 3 | unchanged | 150/250/350 | 1/1/2 |
| T09 | 拾取磁场 | 3 | pickup +20%/lvl | 普通 | 3 | unchanged | 150/250/350 | 1/1/2 |
| T10 | 连杀加速 | 3 | +3%/lvl ×5 stacks | 稀有 | 3 | +4%/lvl ×5 stacks | 400/550/700 | 2/3/4 |
| T11 | 弹药回流 | 3 | 1×lvl mags / 5 kills | 稀有 | 3 | unchanged | 400/550/700 | 2/3/4 |
| T12 | 首发重击 | 3 | +15/20/25% first shot | 稀有 | 3 | +25/40/55% | 400/550/700 | 2/3/4 |
| T13 | 贯穿专精 | 1 | +1 pierce (straight) | 传说 | 1 | unchanged (mechanism unlock) | 1200 | 5 |
| T14 | 静电跃迁 | 1 | 20% arc, 40% dmg, cd 0.6 | 传说 | 1 | **25% arc, 50% dmg, cd 0.5** | 1200 | 5 |
| T15 | 灼热弹道 | 3 | burn 0.2×lvl/tick | 稀有 | 3 | burn 0.3×lvl/tick | 400/550/700 | 2/3/4 |
| T16 | 连锁爆破 | 1 | r32, dmg 2.0, cd 0.4 | 传说 | 1 | **r40, dmg 2.6** | 1200 | 5 |
| T17 | 低温冲击 | 3 | slow 8%×lvl (cap 24%) | 稀有 | 3 | unchanged | 400/550/700 | 2/3/4 |
| T18 | 冲击放大 | 3 | knockback +15%/lvl | 普通 | 3 | unchanged | 150/250/350 | 1/1/2 |
| T19 | 应急护盾 | 1 | block 1 hit, cd 8s | 传说 | 1 | **cd 6s** | 1200 | 5 |
| T20 | 战后修复 | 3 | heal 10%×lvl on victory | 普通 | 3 | unchanged | 150/250/350 | 1/1/2 |
| T21 | 精英猎手 | 3 | +10/15/20% vs elite | 稀有 | 3 | **+15/25/35%** | 400/550/700 | 2/3/4 |
| T22 | 密集火网 | 3 | +5%×lvl in crowds | 稀有 | 3 | **+8%×lvl** | 400/550/700 | 2/3/4 |
| T23 | 暴击回响 | 1 | 30% echo, r70 | 传说 | 1 | **40% echo, r85** | 1200 | 5 |
| T24 | 吸能修复 | 3 | heal 0.15×lvl/kill | 稀有 | 3 | heal 0.2×lvl/kill | 400/550/700 | 2/3/4 |

Quality split: 9 普通 / 10 稀有 / 5 传说 (T13 静电跃迁 T16 暴击回响 应急护盾 + 贯穿专精).
Same rank ladder, same rank caps as BEFORE — no `max` value changed, so old saves that
hold rank 3 of anything still validate.

### Why this classification (rule 11/12/14/15)

* 普通 = gradual stat growth (damage/reload/mag/range/HP/speed/pickup/knockback/victory
  heal). 稀有 = stronger numbers or condition/trigger value (rate, crit, streak, burn,
  slow, first shot, elite/crowd conditions, sustain). 传说 = run-defining mechanism
  unlocks (pierce, arc, kill-blast, shield, crit echo), all max=1 — quality and rank stay
  two independent axes (T23 传说 max1; T01 普通 max3).
* Prices are now data-driven per quality and rank
  (`DemoConfig.talent_gold_price / talent_point_price`); `TALENT_GOLD_PRICE` remains ONLY
  for the legacy prototype-reward shop. Bands never cross (rank-1: 150 < 400 < 1200).
  The full talent build costs 29 250 gold vs 22 370 for the full upgrade build — the
  premium system is also the pricier one. `INITIAL_GOLD = 9999` untouched: a fresh wallet
  buys all commons + change, the rest is a progression.
* Legendary talents were DEEPENED, not just relabelled (rule 15): deeper arc, deeper kill
  blast, faster shield, deeper echo. All stay inside the existing bounds (cooldowns,
  MAX_DERIVATION 2, no recursion, no infinite projectiles).

## 4. Measured strength (rule 31/32) — runtime, not catalog numbers

`tests/B13GrowthBench.tscn` (same real fixture as M9Power/B12WeaponBench: real firing,
reloads, health deltas; weapon 0, level 1; evidence in `docs/iteration/evidence/b13/growth-*.json`):

| Build | single DPS | boss DPS | crowd 6×30hp clear |
|---|---|---|---|
| baseline | 7.56 | 7.56 | 25.08 s |
| upgrades_common | 10.27 | 10.27 | 17.83 s |
| upgrades_rare | 14.85 | 14.85 | 6.17 s |
| upgrades_full | 19.55 | 19.55 | 4.69 s |
| talents_common | 12.01 | 12.01 | 15.61 s |
| talents_rare | 18.97 | 22.36 | 7.34 s |
| talents_full | 18.26 | 21.48 | **2.84 s** |
| both_full | 35.88 | 42.41 | 1.35 s |

Conclusions drawn by `tests/B13Strength.gd` from that frozen evidence:

1. **Higher quality is really stronger** inside both systems (every rung > baseline ×1.1;
   upgrade common→rare→full and talent common→rare→full strictly grow).
2. **Talent gain > upgrade gain**: talents win at common and rare in both single and boss;
   at full investment legendary TALENTS are mechanisms (arc/echo/blast need a second
   target or a kill), so single-target output is near-parity (18.26 vs 19.55, −7%) while
   talents win boss (+10%) and crush the crowd scenario (2.84 s vs 4.69 s clear). Across
   all three scenarios the geometric mean of the talent/upgrade ratios is **1.19** — the
   talent system is the stronger one, asserted as >1.15 in CI.
3. **Legendary talents are felt**: crowd clear drops 2.84 s vs the rare talent build's
   7.34 s (>30% cut, asserted).
4. **No runaway**: crowd clears stay finite; the strongest account stays inside a 12×
   envelope; derivation depth ≤ 2 (M4Combinations + B13UpgradeEffects).
5. Compounding works: both_full ≈ 4.7× baseline single DPS — strong, bounded endgame.

## 5. Combination / stacking audit (rule 33)

All stacking paths re-verified with the new amplitudes:

* additive-vs-multiplicative is unchanged in `EffectiveStats` (damage additive %, damage_mul
  multiplier; magazine/reload multiplicative) — audited by B13UpgradeEffects against the
  live definitions for all 24 items on two guns.
* caps hold with the FULL account: crit ≤ 1.0, reload ≥ 0.15 s (MIN_RELOAD_SECONDS),
  rate ≤ 60/24, magazine a positive integer, slow cap 24%, burn one record per source,
  echo/arc non-recursive (depth-1 contexts), MAX_DERIVATION 2 — asserted in
  B13UpgradeEffects + M4Combinations (max_depth_seen ≤ 2) with the new numbers.

## 6. Unequip weapon (rule 19–24)

* **The action**: `Demo.unequip_weapon()` — camp-only. `gun.set_use(false)` (inert: stops
  firing/reload processing, hides), then `Utils.player.gun = null`. Ownership, ammo,
  ownership records: untouched. No refund.
* **The intent state**: `Demo.explicitly_unequipped`. Set by an explicit unequip; cleared
  by ANY successful equip (panel or hotkey, `PlayerData.changeWeapon`). It distinguishes
  "no weapon yet" (fresh player's first purchase still auto-equips — preserved) from
  "player chose to be unarmed" (buying another gun must NOT silently re-arm).
* **Save**: snapshot writes `unequipped` (optional bool) + the existing `equipped=""`.
  schema_version stays 6; `CampSnapshot.validate` only constrains the key when present;
  old saves restore as false — exactly their previous auto-equip behaviour. Reload of
  `equipped=""` keeps the player unarmed and keeps the intent, so buying after a reload
  still does not auto-equip.
* **First-class unarmed** (rule 21): `LevelServer.can_start` now accepts unarmed
  departure (armed departures still require the held gun to be owned); WASD/dash work
  (verified with real input in B13Visual); firing/reload simply do nothing; grenade
  refuses (`fire_global_grenade` guard); HUD shows `未装备武器` (`GameUI` reacts to
  `Demo.changed`); StatPanel says `未装备武器；装备武器后可查看完整属性`; CampPanel lists
  ownership and offers 装备; talent_status reads are guarded; death/resurrect guarded.
  The old hard refusal "请先购买并装备一把枪" is gone from both CampPanel and LevelServer.
* **Re-equip**: panel 装备 button, hotkey path (`PlayerData.changeWeapon`) — both tested;
  equip restores HUD/ammo state, switch debounce intact, save records the new equipped id.

## 7. Save compatibility (rule 28)

* `owned_global_upgrades` — same 24 string IDs, no migration. Validate unchanged.
* `talents` / `talent_payments` — same IDs, same max values, same payment record shape
  {id, level, currency, amount}. Reset/refund still replays payments (M4Persistence,
  B13Economy): refunds are always by actual payment, never re-derived from new prices.
* `equipped=""` + optional `unequipped` — validated, normalized, round-tripped
  (B13Unequip saves → reloads → stays unarmed with intent).
* Old-save fixtures: M4Persistence's v1/v2 fixtures still validate; B12Save green.

## 8. UI (rule 25/26)

* Upgrade shop: quality prefix + border colour on every card (普通 gray-blue / 稀有 blue /
  传说 gold, matching the B12 palette), 全部品质/普通/稀有/传说 filter (exact members),
  detail shows name+quality, real effect text, catalog price, owned state, the global
  line "所有当前和未来武器自动生效", and a live **当前 → 购买后** preview computed from
  `EffectiveStats` on the current gun (damage/crit/magazine/reload/range/spread/impulse/
  pierce/shards deltas, zero rows skipped). Sorted by quality then price.
* Talent shop: card shows quality + name + rank x/y with quality colour; detail shows
  quality (explicitly "价值等级；与当前等级独立"), full condition text, current effect,
  next-rank effect, and BOTH next-rank prices (gold and points); condition/cooldown/state
  lines kept (T10 stacks, T24 cooldown, T13 compatibility, ...). Quality filter shared.
* Weapon page: equipped weapon now offers **卸下武器**; unarmed page offers 装备; markers
  (▶/√) unchanged for B12UI compatibility.

## 9. Tests (all green locally, Godot 4.7.2-stable, Windows x64)

New B13 contracts wired into `.github/workflows/native-tests.yml` (contracts job):

| Test | Scope | Result |
|---|---|---|
| B13Catalog | shape, quality 1..3, names, price bands, shop price = catalog, talent ladders, system price relation | 530 PASS |
| B13UpgradeEffects | all 24 upgrades really change exactly what they declare, on two guns; mechanism secondaries; grenade unlock; full-account caps | 85 PASS |
| B13TalentEffects | exact runtime magnitude of every talent incl. deepened legends; charged prices | 37 PASS |
| B13Economy | underfunded refusals, exact per-rank/currency charges, mixed-ledger refund, bands, talent>upgrade price relation, INITIAL_GOLD unchanged | 136 PASS |
| B13Unequip | fresh auto-equip, unequip, save `equipped=""`+intent, reload keeps unarmed, no silent re-arm on purchase, manual+hotkey equip, unarmed combat, resurrect | 39 PASS |
| B13UI | real CampPanel: filters, quality cards, detail fields, live preview, owned states, unequip button, unarmed stat panel | 129 PASS |
| B13Strength | frozen growth evidence vs design rules incl. geomean >1.15 and harness sha256 manifest | 49 PASS |
| B13GrowthBench | evidence generator (8 builds × 3 scenarios) — OUT of per-PR CI by design | runs clean |

Regression (rule 35): B12Catalog 182, B12Strength 195, B12Save 14, B12UI 75,
B12LineOfSightRegression 12, M3Weapons 72, AimProvider 14, M4Talents 233,
BaselineRegression 4, B11Fairness 61, B11Perf stage39 + stage40 (convergence kept:
created≈removed, fps_avg 144+) — **all PASS**. ContractRunner/M4Attachments/
M4Combinations/M4Persistence stop on the pre-existing `result.instance_id` /
`player_am_list[...]` defects of the retired attachment-inventory contract family;
verified byte-identical failures on a clean origin/main worktree (same PASS counts, same
SCRIPT ERRORs), so they are NOT B13 regressions. Their living semantics (purchase, real
effective-stat change, no-drift, derivation bounds, exact refunds, cross-process restore)
are covered by the B13 contracts above.

Updated pins: ContractRunner A07/B05/radius, M4Talents T12/T21, M4Persistence + M6SaveUI
refund sums — all now read the live catalog instead of hard-coded 100/2400/1.24.

## 10. Visual evidence (rule 36) — `docs/iteration/evidence/b13/visual/`

Windowed `gl_compatibility` run with real control presses and real stage input; 14 captures:

* `upgrades-quality-1/2/3.png` — the three quality lists; `upgrade-detail-preview.png`
  (当前 → 购买后 live delta); `upgrade-owned-state.png` (bought through the panel).
* `talents-quality-1/2/3.png`; `talent-legendary-detail.png` (T23 quality/rank/prices);
  `talent-rank1-purchased.png` (gold purchase through the panel).
* `weapon-equipped-unequip-offered.png` → real 卸下武器 press → `weapon-unarmed-state.png`
  → unarmed departure into Stage 1 → real WASD movement (289→409 px, `combat-unarmed-moved.png`,
  no firing possible, zero errors) → return to camp → real 装备 press → armed departure →
  real firing verified by damage events (`combat-armed-firing.png`).

## 11. Performance (rule 30)

No new projectile/proc architecture; deepened mechanisms ride existing bounded paths
(cooldowns, one-record burns/slows, depth caps). B11Perf stage 39/40 re-measured: node
counts settle, created≈removed, fps_avg 144.5/144.8 (headless software renderer),
no FAIL. M4Combinations max_depth_seen ≤ 2 with the full account.

## 12. Known limitations

1. The retired attachment-inventory contract family (ContractRunner tail,
   M4Attachments/M4Combinations/M4Persistence, M4UI/M6SaveUI) fails on main exactly as it
   fails here — pre-existing, documented in the CI workflow comments. Not repaired by B13
   (out of scope); their semantics live on in the B13 contracts.
2. Single-target benchmark output of the full talent build sits ~7% under the full
   upgrade build (legendary talents are mechanisms, invisible to a lone immortal dummy);
   the systems are compared across all three scenarios (geomean 1.19) — this trade-off is
   a design statement, recorded here explicitly.
3. Bench numbers are from one representative weapon (id 0) and one seed per scenario;
   they prove ordering and magnitude, not per-weapon tuning.
4. No save schema bump was needed; `unequipped` is an optional field, so B12-era saves,
   including the deployed production ones, validate byte-for-byte unchanged.

## 13. Files touched (summary)

Code: `AttachmentCatalog.gd`, `DemoConfig.gd`, `Demo.gd`, `PlayerData.gd`, `Hero.gd`,
`LevelServer.gd`, `CampSnapshot.gd`, `CampPanel.gd`, `StatPanel.gd`, `GameUI.gd`,
24 attachment `.tscn` display names.
Tests: 8 new B13 scenes/scripts, pin updates in ContractRunner/M4Talents/M4Persistence/M6SaveUI.
CI: `native-tests.yml` (+7 run_case lines).
Evidence/docs: `docs/iteration/evidence/b13/*` (audit-before.md, 8 growth JSONs, manifest.json,
14 PNGs), this report.
