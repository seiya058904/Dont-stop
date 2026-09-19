# B13 Baseline Audit — BEFORE (read from source at 6bae6e92635be0d4c30964b6dc32e0bc3075c4c2)

Every row below was read from the actual runtime source, not from any name or UI text:
upgrade effects live in `game/config/AttachmentCatalog.gd` DEFINITIONS, upgrade display names
live in the attachment scene exports (`game/attachments/*.tscn` → `am_name`, shown via
`tr(am.am_name)`), upgrade prices live in `AttachmentCatalog.PRICES` (the scene `money`
getter returns the catalog price), talent effects/prices live in `game/config/DemoConfig.gd`
TALENTS + `TALENT_GOLD_PRICE`, purchase flow in `autoload/Demo.gd try_purchase`, stat
application in `game/config/EffectiveStats.gd`.

## Weapon Upgrade Matrix (24 items, BEFORE)

| ID | scene file | BEFORE display name | price(gold) | actual effect | all weapons benefit | weapon-type lock in name | DPS/handling/utility | save key |
|----|-----------|---------------------|-------------|----------------|---------------------|--------------------------|----------------------|----------|
| 0  | QuickdrawMagazine | 快速弹夹 | 500 | reload ×0.80 | yes | no (but says "magazine", effect is reload) | handling | owned_global_upgrades "0" |
| 1  | UniversalExtendedMagazines | 通用扩容弹夹 | 350 | magazine ×1.20 | yes | no | magazine | "1" |
| 2  | ExtendedRifleMagazine | 扩容步枪弹夹 | 550 | magazine ×1.35 | yes | **YES — "rifle"** | magazine | "2" |
| 3  | QuickExpansionMagazine | 快速扩容弹夹 | 800 | magazine ×1.20, reload ×0.80 | yes | no | magazine+handling | "3" |
| 5  | ShotgunShellPouch | 霰弹枪子弹袋 | 750 | magazine ×1.15, reload ×0.80 | yes | **YES — "shotgun"** | magazine+handling | "5" |
| 6  | MachineGunMagazine | 机枪弹夹 | 700 | magazine ×1.50 | yes | **YES — "machine gun"** | magazine | "6" |
| 7  | SubmachineGunMagazine | 冲锋枪弹夹 | 450 | magazine ×1.30 | yes | **YES — "SMG"** | magazine | "7" |
| 8  | SuperUniversalMagazine | 超级通用弹夹 | 850 | magazine ×1.60 | yes | no | magazine | "8" |
| 9  | GrenadeLauncher | 榴弹发射器 | 1500 | damage +10%; right-click grenade (cd 2s, 35% dmg) | yes (grenade is a real all-weapon unlock) | no | damage+mechanism | "9" |
| 110 | A110 | 精准瞄具 | 700 | damage +5%, crit +8pp | yes | no | damage/crit | "110" |
| 111 | A111 | 束流聚焦镜 | 850 | damage +8%, range ×1.2, width ×0.85 | yes (width only matters to beams) | **YES — "束流" sounds beam-only** | damage/range | "111" |
| 112 | A112 | 补偿枪口 | 650 | damage +8%, spread ×0.75 | yes | **"枪口" muzzle-part name** | damage/accuracy | "112" |
| 113 | A113 | 棱镜扩散器 | 950 | damage ×1.10, width ×1.35, angle ×1.35 | partial (width/angle only for beam/cone) | beam-flavoured | damage/coverage | "113" |
| 114 | A114 | 过载枪管 | 600 | damage +15%, reload ×1.10 (penalty) | yes | **"枪管" barrel-part name** | damage (handling cost) | "114" |
| 115 | A115 | 能量散热器 | 700 | reload ×0.85, warmup ×0.9 | yes (warmup only charge weapons) | **"能量" energy-flavoured** | handling | "115" |
| 116 | A116 | 抑震枪托 | 450 | reload ×0.90, recovery ×0.80 | yes | **"枪托" stock-part name** | handling | "116" |
| 117 | A117 | 冲量支架 | 800 | damage +8%, impulse ×1.35 | yes | underbarrel-part name | damage/control | "117" |
| 118 | A118 | 贯穿弹芯 | 1100 | damage +10%, pierce +1 | yes | ammunition-part name | damage/pierce | "118" |
| 119 | A119 | 反弹弹壳 | 1200 | damage +10%, bounces +1 (retention 0.85) | partial (bounce only exists on ricochet weapons; primary damage universal) | ammunition-part name | damage/mechanism | "119" |
| 120 | A120 | 裂片弹头 | 1400 | damage +8%, shards +2 (25%) | yes (fragments work on ordinary projectiles) | ammunition-part name | damage/mechanism | "120" |
| 121 | A121 | 扩爆引信 | 900 | damage +10%, radius ×1.2 | partial (radius only explosive weapons; primary damage universal) | ammunition-part name | damage/mechanism | "121" |
| 122 | A122 | 电弧中继 | 1200 | damage +10%, chain jumps +1 | partial (chain only weapon 112; primary damage universal) | tactical-part name | damage/mechanism | "122" |
| 123 | A123 | 制导模块 | 850 | damage +8%, turn ×1.25, lock ×1.15 | partial (homing only weapon 120; primary damage universal) | tactical-part name | damage/mechanism | "123" |
| 124 | A124 | 击杀回填器 | 1500 | refill 1 round on direct kill (cd 0.2s); **no primary stat at all** | yes | no | utility only | "124" |

### BEFORE problems recorded (facts, not guesses)

1. **Names are weapon-part names (枪口/枪托/枪管/弹芯) and weapon-type names (步枪/霰弹枪/机枪/冲锋枪)**
   while every effect is global. ID 2 is literally named "rifle magazine" and gives all weapons +35%.
2. **ID 1 / ID 2 display names are swapped relative to their scene file names**
   (UniversalExtendedMagazines.tscn shows "EXTENDED RIFLE MAGAZINE" → 扩容步枪弹夹;
   ExtendedRifleMagazine.tscn shows "UNIVERSAL EXTENDED MAGAZINE" → 通用扩容弹夹).
3. **IDs 0-9 have no catalog `name`** — the shop shows scene-export names, the catalog only has `info`.
4. **No quality dimension exists**; prices are scattered with no bands
   (450 reload/mag items vs 700 pure +8% damage items).
5. **Strength layering is unclear**: +8% damage items (112/111/123) cost more than +50% magazine (6).
6. **ID 124 has no primary effect** — its only value is a 1-round kill refund.
7. Mechanism secondaries (bounces/chain/homing/radius) only help 1-2 weapons each, and several
   items have no meaningful universal primary (119/122/123 before the damage rider was the only
   universal part; all do carry a damage rider today — kept and strengthened).

## Talent Matrix (24 items, BEFORE)

All talents cost exactly `TALENT_GOLD_PRICE = 100` gold or 1 talent point per rank (Demo.try_purchase).

| ID | name | max | per-rank effect (actual runtime) | trigger | type | combat impact | save/refund |
|----|------|-----|----------------------------------|---------|------|---------------|-------------|
| T01 | 火力强化 | 3 | damage +8%/lvl (additive %) | passive | 被动 | high (pure damage) | talents + talent_payments |
| T02 | 快速循环 | 3 | fire rate +6%/lvl (cycle) | passive | 被动 | high (rate) | same |
| T03 | 熟练装填 | 3 | reload −5%/lvl (min 0.15s) | passive | 被动 | medium | same |
| T04 | 扩充携弹 | 3 | magazine +10%/lvl | passive | 被动 | medium | same |
| T05 | 弹道延展 | 3 | range/lifetime +10%/lvl | passive | 被动 | medium | same |
| T06 | 弱点识别 | 3 | crit +5pp/lvl (×1.5) | passive | 被动 | high | same |
| T07 | 生存余量 | 3 | max HP +1/lvl | passive | 被动 | survival | same + applied_talent_hp |
| T08 | 轻装移动 | 3 | base speed +3%/lvl | passive | 被动 | utility | same |
| T09 | 拾取磁场 | 3 | pickup radius +20%/lvl | passive | 被动 | utility | same |
| T10 | 连杀加速 | 3 | fire rate +3%/lvl per kill stack, 5 stacks, 4s | 5s kill window | 条件 | medium-high (up to +45% rate at rank3 full stack) | same |
| T11 | 弹药回流 | 3 | +1×lvl reserve mags per 5 direct kills | 5 kills | 条件 | sustain | same |
| T12 | 首发重击 | 3 | first shot after real reload +15/20/25% | after reload | 条件 | medium | same |
| T13 | 贯穿专精 | 1 | +1 pierce for straight shots (cap 8 total) | passive (straight only) | 机制 | medium-high | same |
| T14 | 静电跃迁 | 1 | 20% on-hit arc to 1 extra target, 40% dmg, cd 0.6s | direct hit | 机制 | high vs crowds | same |
| T15 | 灼热弹道 | 3 | burn 0.2×lvl per 0.25s tick, 1.5s | direct hit | 机制 | medium | same (target.burns) |
| T16 | 连锁爆破 | 1 | direct-kill explosion r32 dmg2, cd 0.4s | direct kill | 机制 | high vs crowds | same (blast_cooldown) |
| T17 | 低温冲击 | 3 | slow 8%×lvl (cap 24%), 1.5s, boss ÷4 | direct hit | 机制 | control | same (target.slows) |
| T18 | 冲击放大 | 3 | knockback +15%/lvl (normal enemies) | passive | 被动 | utility | same |
| T19 | 应急护盾 | 1 | block one damaging hit, cd 8s | combat hit | 机制 | survival | same |
| T20 | 战后修复 | 3 | heal 10%×lvl max HP on encounter victory | victory | 条件 | survival | same |
| T21 | 精英猎手 | 3 | +10/15/20% dmg to elites (not boss) | vs elite | 条件 | situational | same |
| T22 | 密集火网 | 3 | +5%×lvl dmg when ≥3 enemies within 100 | crowd condition | 条件 | medium-high vs hordes | same (crowd_active) |
| T23 | 暴击回响 | 1 | crit echoes 30% dmg to 1 nearby target, cd 0.15s | direct crit | 机制 | high with crit builds | same |
| T24 | 吸能修复 | 3 | heal 0.15×lvl on direct kill, cd 0.5s | direct kill | 机制 | sustain | same (heal_cooldown) |

### BEFORE problems recorded

1. **Flat price for every rank of every talent** (100 gold / 1 point) — no quality expression at all.
2. **No quality dimension**; a +8%-damage passive and a run-changing crit echo cost the same.
3. **Amplitude band is narrow**: most passives are +3%…+10% per rank, so "advanced talent" never
   feels advanced.
4. Names are mostly accurate (T01 火力强化/damage, T03 熟练装填/reload are correct); T04 扩充携弹
   means magazine; T10 连杀加速 means kill-streak rate — no name/effect mismatch of the upgrade
   system's scale. The work here is classification + amplitude + price, not renames.

## Baseline stat snapshot (weapon 0 base build, no upgrades, no talents, level 1)

Verified by the B13 benchmark's baseline phase (see evidence/b13/growth JSON): weapon 0
base_stats = damage 1.0, rate 5.0, magazine 12, reload 1.0, power ×1.0.

## Ownership/save facts (BEFORE)

- Upgrades: `owned_global_upgrades` array of string IDs; one-shot, permanent, global, no slots.
- Save validate: IDs must exist in `Utils.am_dict`, no duplicates (CampSnapshot.validate).
- Talents: `talents` dict id→rank, `talent_payments` ledger {id, level, currency, amount};
  reset/refund replays the ledger (Demo.reset_preview / reset_talents).
- `equipped` is written as weapon id string, `""` when unarmed — already legal in schema v6.
- `Hero.playerWeaponListChange()` auto-equips the first newly added gun when `gun == null`
  and `not Demo.loading` — there is no "player chose to stay unarmed" state today.
- CampPanel weapon page: equipped gun shows a disabled `当前装备` button; no unequip exists.
- CampPanel `_depart_with` refuses departure without an equipped gun.
