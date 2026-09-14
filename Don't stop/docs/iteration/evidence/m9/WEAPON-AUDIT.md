# Weapon Presentation and Power Audit

All damage values come from actual firing, reloads and target health changes. Raw damage excludes POWER and critical hits. Final samples use a level-one, unupgraded build; live high/full Boss runs are separate.

The crowd fixture uses six 30-HP targets at x=40/60 and y=-14/0/14 relative to the reference muzzle area, within the shortest weapon reach. Earlier wider/censored crowds are superseded. Single/Boss-dummy windows last 15 seconds; burst/reload details remain in source JSON.

| ID | Weapon | Tier | Price | Raw DPS | Final DPS | Raw crowd s | Final crowd s | Presentation |
|---|---|---|---|---|---|---|---|---|
| 1 | [冲击波霰弹枪](weapons-visual-final-v2/m8/m9-weapon-1.png) | 1 | 60 | 1.47 | 1.91 | 65.78 | 52.05 | PASS |
| 3 | [Baby冲锋枪](weapons-visual-final-v2/m8/m9-weapon-3.png) | 1 | 90 | 2.70 | 5.41 | 66.96 | 33.53 | PASS |
| 9 | [Uzi](weapons-visual-final-v2/m8/m9-weapon-9.png) | 1 | 120 | 3.30 | 5.28 | 53.86 | 34.24 | PASS |
| 0 | [冲击波步枪](weapons-visual-final-v2/m8/m9-weapon-0.png) | 2 | 240 | 6.30 | 7.56 | 28.81 | 25.07 | PASS |
| 2 | [轻型狙击枪](weapons-visual-final-v2/m8/m9-weapon-2.png) | 2 | 260 | 6.67 | 9.89 | 26.75 | 21.68 | PASS |
| 5 | [帝国霰弹枪](weapons-visual-final-v2/m8/m9-weapon-5.png) | 2 | 290 | 4.00 | 5.52 | 33.77 | 24.66 | PASS |
| 8 | [RebalShotgun](weapons-visual-final-v2/m8/m9-weapon-8.png) | 2 | 320 | 2.17 | 3.88 | 26.84 | 15.90 | PASS |
| 123 | [三连发卡宾](weapons-visual-final-v2/m8/m9-weapon-123.png) | 2 | 350 | 3.80 | 8.40 | 49.05 | 22.98 | PASS |
| 7 | [异形者机枪](weapons-visual-final-v2/m8/m9-weapon-7.png) | 2 | 380 | 7.60 | 10.87 | 23.41 | 16.34 | PASS |
| 117 | [反弹重弹枪](weapons-visual-final-v2/m8/m9-weapon-117.png) | 3 | 700 | 6.40 | 17.20 | 29.83 | 10.28 | PASS |
| 118 | [裂片发射器](weapons-visual-final-v2/m8/m9-weapon-118.png) | 3 | 760 | 7.00 | 15.20 | 14.90 | 7.40 | PASS |
| 4 | [异形者枪步](weapons-visual-final-v2/m8/m9-weapon-4.png) | 4 | 1300 | 11.33 | 17.62 | 15.68 | 10.12 | PASS |
| 112 | [跃迁电弧枪](weapons-visual-final-v2/m8/m9-weapon-112.png) | 4 | 1500 | 4.80 | 19.87 | 17.00 | 3.12 | PASS |
| 115 | [扇面脉冲炮](weapons-visual-final-v2/m8/m9-weapon-115.png) | 4 | 1550 | 6.72 | 16.56 | 3.59 | 1.03 | PASS |
| 114 | [等离子榴炮](weapons-visual-final-v2/m8/m9-weapon-114.png) | 4 | 1600 | 4.53 | 20.47 | 19.20 | 3.82 | PASS |
| 116 | [热流喷射器](weapons-visual-final-v2/m8/m9-weapon-116.png) | 4 | 1700 | 7.33 | 27.26 | 9.03 | 2.02 | PASS |
| 6 | [BoomBoi](weapons-visual-final-v2/m8/m9-weapon-6.png) | 4 | 1750 | 7.47 | 14.60 | 23.20 | 11.30 | PASS |
| 122 | [回旋锯盘](weapons-visual-final-v2/m8/m9-weapon-122.png) | 4 | 1800 | 9.80 | 32.34 | 10.14 | 4.23 | PASS |
| 111 | [棱镜脉冲枪](weapons-visual-final-v2/m8/m9-weapon-111.png) | 5 | 2600 | 14.08 | 30.40 | 13.83 | 8.27 | PASS |
| 113 | [蓄能轨道炮](weapons-visual-final-v2/m8/m9-weapon-113.png) | 5 | 2800 | 5.83 | 29.68 | 18.55 | 5.31 | PASS |
| 119 | [散射火箭炮](weapons-visual-final-v2/m8/m9-weapon-119.png) | 5 | 3000 | 3.60 | 15.84 | 16.82 | 3.88 | PASS |
| 120 | [微型追踪导弹](weapons-visual-final-v2/m8/m9-weapon-120.png) | 5 | 3200 | 8.96 | 33.73 | 14.77 | 4.22 | PASS |
| 121 | [引力榴弹器](weapons-visual-final-v2/m8/m9-weapon-121.png) | 5 | 3400 | 5.00 | 23.84 | 5.27 | 1.96 | PASS |
| 124 | [加速转管机枪](weapons-visual-final-v2/m8/m9-weapon-124.png) | 5 | 3600 | 16.00 | 38.00 | 11.22 | 3.86 | PASS |

## Tier decisions

- ID 0: I → II. Raw sustained output competes with Tier II single-target weapons.
- ID 4: III → IV. Strong raw sustained fire; raise rating/price without reducing damage.
- BoomBoi (6): III → IV. Long, continuous and easy-to-place finite beam provides safety value beyond its DPS.
- Cone (115): III → IV. Excellent measured grouped-target clear, offset by short reach.
- Prism (111): IV → V. High raw close-target output plus independently wall-clipped branches.
- Within Tier I, the slower measured shotgun is now 60 gold and Baby is 90 gold; Uzi remains 120. This price-only adjustment follows the power measurements and does not change their damage results.
- All other ratings were reviewed using the matrix. POWER multipliers are unchanged. Crowd, range, homing/control and exposure differences permit matchup reversals; tier is not a DPS-only ordering.

## Range interpretation

The CSV separates the primary path from observed visible extent. A projectile stopped by an enemy does not demonstrate its empty-space maximum. Explosion radii, fragments, homing turns and returning paths cannot be represented faithfully by one straight-line range value. M9Paths and retained M3/M4/M6 suites cover those conditional paths. Captures show real runtime primitives, not human aesthetic approval.
