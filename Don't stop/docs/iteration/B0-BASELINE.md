# B批 · B0 基线审计

生产基线（本轮开始前重新 fetch 确认）：

```
origin/main = d6652cb5e1b3ebaab79353e07dec29bb2e209446
Merge pull request #4 from seiya058904/feat/dont-stop-revision
```

本轮分支：`feat/dont-stop-b-combat-hell`，起点即上述 SHA。

## 0. 已完成能力确认（必须不丢）

| 能力 | 位置 | 状态 |
| --- | --- | --- |
| Web 返回主菜单 / 再开始修复 | `ee3ea1d fix(web): root-cause the return-to-menu restart failure`、`tests/R3ReturnMenu.gd`、`tools/web-menu-return-e2e.js` | 保留 |
| 弹药比例 HUD | `ee3ea1d`、`tests/AmmoBarCoverage.gd` | 保留 |
| 24 武器姿态修复 | `ee3ea1d`、`tests/WeaponPoseTable.gd` | 保留 |
| Web 普通鼠标输入方案 | `Utils.set_gameplay_mouse_mode()`、`tools/web-aim-e2e.js` | 保留 |
| CI 约 10 分钟新流水线 | `.github/workflows/deploy-pages.yml` jobs：`changes`(5m) → `build`(12m) → `browser-gates` → `deploy`(10m) → `online-smoke`(10m) | 保留 |
| build SHA / artifact digest | `tools/stamp-build-identity.py`、`tools/pck-audit.py` | 保留 |
| save namespace 兼容 | `Demo.save_path`、`schema_version 6`、`CampSnapshot.validate/normalize` | 保留 |

## 1. 1–30 关现有配置（`M5Content.encounters()` → `DemoConfig.ENCOUNTERS`）

Region 分配：1–5 R1，6–10 R2，11–15 R3，16–20 R4，21–25 R5，26–30 R6。

| 关 | 区域 | cap | interval | rhythm | roles | seconds | Horde | Rush | Elite | Boss |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | R1 | 35 | 0.80 | 渐进 | E01 E01 E02 | 45 | – | – | – | – |
| 2 | R1 | 38 | 0.65 | 轮换 | E02 E02 E01 | 45 | – | – | – | – |
| 3 | R1 | 40 | 0.70 | 渐进 | E01 E02 E01 E05 | 45 | – | – | – | – |
| 4 | R1 | 55 | 0.55 | 脉冲 | E02 E02 E02 E04 | 45 | – | – | – | – |
| 5 | R1 | 40 | 0.65 | 精英 | E01 E02 E05 E04 | 45 | – | – | 30s 起 1 只 ×1.5HP | – |
| 6 | R2 | 47 | 0.57 | 渐进 | E01 E03 | 45 | – | – | – | – |
| 7 | R2 | 49 | 0.55 | 轮换 | E02 E02 E06 | 45 | – | – | – | – |
| 8 | R2 | 45 | 0.68 | 协同 | E03 E05 E01 | 45 | – | – | – | – |
| 9 | R2 | 59 | 0.43 | 脉冲 | E02 E04 E03 E02 | 45 | – | – | – | – |
| 10 | R2 | 15 | 1.50 | Boss | – | 0 | – | – | – | **B01** |
| 11 | R3 | 45 | 0.55 | 轮换 | E01 E11 | 45 | – | – | – | – |
| 12 | R3 | 49 | 0.51 | 协同 | E09 E02 E02 | 45 | – | – | – | – |
| 13 | R3 | 38 | 0.55 | 交替 | E01 E11 E10 E02 | 45 | – | – | – | – |
| 14 | R3 | 56 | 0.47 | 轮换 | E04 E11 E02 | 45 | – | – | – | – |
| 15 | R3 | 56 | 0.51 | 精英 | E09 E11 E02 E05 E06 | 45 | – | – | 30s 起 1 只 | – |
| 16 | R4 | 52 | 0.53 | 渐进 | E01 E02 E07 ×2 … | 45 | – | 有 | – | – |
| 17 | R4 | 47 | 0.53 | 协同 | E01 E02 E08 E09 E06 | 45 | – | 有 | – | – |
| 18 | R4 | 70 | 0.39 | 脉冲 | E01 E02 E12 E11 | 45 | – | 有 | – | – |
| 19 | R4 | 52 | 0.49 | 协同 | E01 E02 E07 E08 E06 | 45 | – | 有 | – | – |
| 20 | R4 | 20 | 1.60 | Boss | – | 0 | – | – | – | **B02** |
| 21 | R5 | 65 | 0.42 | 协同 | + E03 E09 | 45 | batch4/4.0s×2 | 8 发 | – | – |
| 22 | R5 | 55 | 0.40 | 交替 | + E10 E11 | 45 | batch4/3.8s×2 | 8 发 | – | – |
| 23 | R5 | 72 | 0.37 | 轮换 | + E04 E11 | 45 | batch4/3.7s×2 | 8 发 | – | – |
| 24 | R5 | 72 | 0.39 | 脉冲 | + E12 E07 | 45 | batch5/3.4s×2 | 8 发 | – | – |
| 25 | R5 | 68 | 0.39 | 精英 | + E03 E05 E08 | 45 | batch5/3.1s×2 | 8 发 | 30s 起 1 只 | – |
| 26 | R6 | 93 | 0.29 | 轮换 | + E12 E11 E06 | 45 | batch6/3.0s×2 | 8 发 | – | – |
| 27 | R6 | 110 | 0.37 | 协同 | + E09 E08 E11 | 45 | batch12/2.2s×3 | 8 发 | – | – |
| 28 | R6 | 125 | 0.37 | 交替 | + E04 E10 E09 | 45 | batch14/2.0s×3 | 8 发 | – | – |
| 29 | R6 | 145 | 0.27 | 三段 | + E07 E05 E11 | 45 | batch16/1.8s×3 | 8 发 | – | – |
| 30 | R6 | 20 | 1.60 | Boss | – | 0 | – | – | – | **B03** |

生成节奏乘数（`LevelServer.onMonsterCreate`）：phase<0.2 → ×1.3；<0.8 → ×0.7；否则 ×1.5。
脉冲 rhythm → `fmod(t,10)<4 ? 0.5 : 1.8`；三段 → `[1.3,0.7,0.5]` 每 15 秒。
16 关起 `spawn_index%4==0` 每发多带一只；16 关起半场一次 Rush（26+ 为 8 发、21+ 为 6 发、其余 4 发），间隔 0.3s，方向 `spawn_index % sides`。
27/28/29 关 `E01/E02` 额外 `SPEED ×= 1.2`（`M5Content.spawn`）。

> **B0 结论 1**：26–29 关 cap 已到 93/110/125/145。本轮严禁以翻倍 cap 作为主要难度手段。

## 2. R1–R6 区域与实际地图大小

| Region | 名称 | 战斗区来源 | 实际尺寸 |
| --- | --- | --- | --- |
| R1 | 营地外街区 | `Town.tscn` TileMap（营地本体）；`getPoint()` 取 `Level_1` 子节点随机点 | 营地结构，**非** `CombatArena` |
| R2–R6 | 货运场/冰原冷却站/熔岩处理区/过生长走廊/山地核心平台 | `CombatArena.gd`（`Town.prepare_region()` 在 `(10000+N*1000, -6000)` 实例化） | **768 × 576**（`bounds = Rect2(-384,-288,768,576)`） |

R1 特殊结构（`Town.gd`）：`PositionHome(264,117)`、`RewardNpc`、`openShop`、`PortalRoot` 7 个 Portal、`Level_1/5/11/16/21/26` 的 `pos_start`、`TileMap3` 地面、`build_navigation()` 网格 `Rect2i(-10,18,58,34)`。
R1 不创建 arena，`spawn_point()` 走 `Town.build_navigation()` 分支（145–280px 环带 + 可达性 + 真实碰撞器净空）。
Boss 关：`Town.depart()` 用 `spawn_near(player,160,220,radius_for(boss))`；未取到合法点时 `_boss_pending` 延迟重试（`M5Content.audit_boss_deferred/retry`）。

`AStarGrid2D`（arena）：`region = Rect2i(-24,-18,48,36)`、`cell_size 16`、`offset (8,8)`；solid 判定 = 出 `bounds.grow(-16)` 或落在任一 `obstacles` 的 `grow(13)` 内。

### 现有墙体（`M5Content.WALLS`）
```
R2: (-260,-185,105,70) (150,-185,105,70) (-260,105,105,70) (150,105,105,70)
R3: (-255,-130,190,24) (55,-15,210,24) (-225,110,170,24)
R4: (-245,-120,150,24) (95,-120,150,24) (-245,95,150,24) (95,95,150,24) (-245,-40,24,70) (221,-40,24,70)
R5: (-135,-225,26,155) (-135,60,26,155) (109,-225,26,155) (109,60,26,155)
R6: (-175,-135,55,55) (120,-135,55,55) (-175,80,55,55) (120,80,55,55)
```
外围边界墙由 `CombatArena._ready()` 生成：`Rect2(-400,-304,800,16)`、`Rect2(-400,288,800,16)`、`Rect2(-400,-288,16,576)`、`Rect2(384,-288,16,576)`。

## 3. 12 种敌人真实攻击方式

| ID | 名称 | HP | Speed | 实现 | 真实攻击 |
| --- | --- | --- | --- | --- | --- |
| E01 | 追击者 | 2.0 | 90 | `Monster2.gd` 本体 | 纯接触（`contact` 由 AnimationPlayer/`AtkTimer` 触发） |
| E02 | 轻型蜂群 | 1.2 | 105 | `DemoEnemy.gd` | 接触 <17px，0.8s 冷却，`sprite_body.scale 0.65` |
| E03 | 重甲破坏者 | 12.0 armor 9 | 82 | `TacticalEnemy.gd` | charge（`zone("charge")` 预警 0.65/0.5s，dash 265，`armor` 正面减伤 55%，破甲后脆） |
| E04 | 预警冲锋者 | 5.0 | 65 | `DemoEnemy.gd` | warn 0.6s（`CombatTelegraph.paint("charge",…,108,19)`）→ dash 240 0.45s |
| E05 | 远程喷射者 | 3.0 | 50 | `DemoEnemy.gd` | warn 0.75s → 5 发（≥6 关）/1 发（<6 关）扇形 `EnemyShot` |
| E06 | 自爆逼近者 | 3.0 | 125 | `TacticalEnemy.gd` | `zone("circle",42,0.8)` 预警 → 半径 42 内 1 点伤害 + 自毁 |
| E07 | 分裂母体 | 8.0 | 72 | `TacticalEnemy.gd` | `summon(1)`（cap 3，总 3）；死亡再 `summon(2)`；子体 `summoned=true` 不再生产 |
| E08 | 支援治疗者 | 4.0 | 96 | `TacticalEnemy.gd` | 155px 内最多 2 目标，每目标累计上限 3 HP，`Combat.trace` 绿线 |
| E09 | 正面盾卫 | 8.0 armor 7 | 78 | `TacticalEnemy.gd` | `zone("cone",60,delay)`；正面 1.05 rad 内 armour 抵消 55% |
| E10 | 标记炮击者 | 4.0 | 78 | `TacticalEnemy.gd` | 奇偶交替：`zone("line",280,0.85,0.3)` beam / `zone("circle",locked_point,40,0.95)` artillery → `barrage("fan",6/12)` |
| E11 | 侧绕猎手 | 4.0 | 122 | `TacticalEnemy.gd` | `zone("charge")` dash 310；Elite 时 dash 后 `barrage("fan",10,120,0.9)` |
| E12 | 易爆载能体 | 2.0 | 95 | `TacticalEnemy.gd` | `zone("cone",60,delay)`；死亡 `HostileZone` 对敌爆破（`friendly_context`，depth<MAX_DERIVATION=2） |

**关键：12 种敌人中没有任何一种使用 `Hero.apply_root()`。** `apply_root` 目前只被 `BossUltimate` B02 的 ultimate 使用。

## 4. B01 / B02 / B03 当前攻击循环

`TacticalEnemy.choose_attack()` → `perform_attack()`，`attack_index` 循环取模。

- **B01 破城机甲** hp 4400 speed 84 armor 120，reach 260（charge 轮）/95
  - `idx%3==1` charge（290 / phase_two 330）→ `zone("charge").damage=0` → `phase="dash"`
  - `idx%3==2` cleave `zone("cone",125).angle=0.95`
  - `idx%3==0` slam `zone("circle",85/phase_two 100)` → `barrage("ring",19/23,1/2,115)`
  - Phase II（HP≤50%）：`phase_two=true`、清理 owned_attacks、`orbit_side*=-1`、`summon(2,"E09")`、`ultimate_cooldown=3.0`、标签 `" · PHASE II"`
- **B02 蜂巢聚合体** hp 6000 speed 76
  - `idx%3==1` brood `zone("summon",34/42).damage=0` → `summon(3,"E02"/"E06")` + `barrage("ring",24/28,2/3,115)`
  - `idx%3==2` lockdown 3 个 `zone("circle")`（65@0.95 / 48@1.35 / phase_two 45@1.55）
  - `idx%3==0` pulse `zone("cone",160).angle=0.9` → `barrage("fan",17/23,2/3,130,1.3)`
  - 召唤 cap：`children_ids ≤ 8`、`summon_total ≤ 24`、且服从 `ENCOUNTERS[level].cap`
- **B03 棱镜核心** hp 6200 speed 115（Normal Final Boss）
  - `idx%3==1` dash（440，带 0.25s 速度预判，`zone("charge")`）
  - `idx%3==2` sweep `zone("line",330,0.9,0.85).sweep=orbit_side*(1.0/1.3)`
  - `idx%3==0` burst `zone("cone",240).damage=0` → `barrage("fan",13/17,2/3,160,1.0)`
  - Phase II：dash 结束反向 `barrage("fan",9,140,0.8)`
- **BossUltimate**（`BossUltimate.gd`）：仅 `is_boss and phase_two and ultimate_cooldown<=0 and boss_ultimate 组为空` 触发，`ultimate_cooldown = 15.0`
  - B01 重压震荡：`fraction 0.30`，`radius 160`，warning 1.6s
  - B02 母巢巨卵：`fraction 0.28`，`radius 18` 移动圆，warning 1.6s，命中后 `apply_root()`，存活 4.0s
  - B03 棱镜坍缩：`fraction 0.33`，4 向 `lengths[i]` 射线（墙裁剪），warning 1.5s

## 5. HostileZone / CombatTelegraph / HostileVFX

- `HostileZone.gd`：`mode ∈ {circle, line, charge, cone, summon}`；`epoch` 绑定（`epoch != LevelServer.epoch` 或非 COMBAT → `queue_free`）；`owner_ref` 死亡即清理；入组 `combat_transient` + `hostile_zone`；`z_index = -1`。
  - 伤害：`circle` 半径内 / `line|charge` 到线段距离 ≤ `width+6` / `cone` 半径内且夹角 ≤ `angle`；均需 `Combat.clear_line`。
  - `friendly_context`（E12 死亡爆破）走 `Combat.explosion_context`，对敌不对玩家。
  - 视觉预算：`hostile_zone` 组 >32 时 `full_detail=false`，只省略 redundant origin halo。
  - warning 视觉采样 30Hz，最后 150ms 与激活边沿恢复物理帧率。
- `CombatTelegraph.gd`：静态 `paint(canvas,kind,direction,radius,length,width,angle,progress,active,sweep,cache,detail)`。当前配色固定在**橙色系**（`edge Color(1,0.55+0.22p,0.19,…)`、`fill Color(0.95,0.23,0.08,…)`、active `Color(1,0.86,0.52)`），**没有按攻击类型区分颜色**。有 charge 流动箭头、cone 进度弧、circle 收缩环 + 计时环、summon 三花苞。
- `HostileVFX.gd`：静态 `alive` 计数器，`alive >= 32` 直接 return（上限 32）；`lifetime 0.28`；入组 `combat_transient` + `hostile_vfx`；`z_index = 6`；橙色冲击环 + 8 方向火花。

## 6. EnemyShot / EnemyBarrage

- `EnemyShot.gd`（CharacterBody2D）：`owner_ref`、`velocity`、`damage`；`TacticalEnemy.shot()` 在 `enemy_projectiles` 组 ≥ **180** 时返回 false（投射物上限 180）。`DemoEnemy` 的 E05 分支**绕过**该上限直接 `add_child`（既有偏差，B1 修正为统一走 `shot()` 计数路径）。
- `EnemyBarrage.gd`：`kind ∈ {fan, ring}`、`count`、`waves`、`speed`、`spread`、`shift`（ring 0.24 / fan 0.18 × `orbit_side`）。

## 7. Hero 的 root / percentage hit

- `Hero.apply_root(seconds=0.45) -> bool`：条件 `not is_dead and LevelServer.state=="COMBAT" and root_remaining<=0 and cc_immunity<=0`；`root_remaining = clampf(seconds,0.4,0.5)`；`root_epoch = LevelServer.epoch`；中断 dash；`Utils.showHitLabel("束缚")`。
- `Hero._physics_process`：`root_epoch != LevelServer.epoch` → root/cc 归零；`root_remaining>0` → `velocity = Vector2.ZERO`（**仍可瞄准、开火、装填**，只有 dash 在 `_input` 被 `root_remaining<=0` 挡住）；root 结束 → `cc_immunity = 1.2`。
- `Hero.on_percentage_hit(fraction, attacker)`：`incoming_percentage = true` → `onHit(player_hp_max*clampf(fraction,0,0.35), attacker, 0.0)` → 复位。走完整的护盾 / reward / contract 管线，且**跳过** `NORMAL_INCOMING/BOSS_INCOMING` 乘数。
- `Hero._draw`：root 时紫环 + 交叉线 + 半径 22 填充；免疫期青绿弧。
- **唯一调用点**：`BossUltimate.gd:56`。E13 将是第二个调用点。

## 8. PointLight2D / CanvasModulate（Fog 基础设施调查结论）

与上游 `SakuyaCN/TowDownGame` 逐字节比对：

| 文件 | 上游 | 当前 Don't Stop | 差异 |
| --- | --- | --- | --- |
| `game/map/Main.tscn` → `CanvasModulate.color` | `Color(0.0392157,0.0392157,0.0392157,1)` | `Color(0.64,0.69,0.76,1)` | **唯一差异**：环境亮度被抬高 |
| `game/map/mapTown/Town.tscn` → `TileMap2/PlayerRoot/Anchor/Camera2D/PointLight2D` | `position(0,-6)` `shadow_enabled=true` `texture=Sprites/light2.png` `texture_scale=0.5` | **完全相同**（含 `Camera2D` 的 `process_callback=0` / `position_smoothing_enabled=true`） | 无 |
| `Sprites/light2.png` | — | SHA256 与上游一致 `086857505B679CCDEDE704D4AFE9E86A3D2A1E9361263CABD5F5406E7A264621` | 无 |
| `game/map/SnowWorld/SnowWorld.gd` | `create_tween().tween_property($PlayerRoot/Anchor/Camera2D/PointLight2D,"texture_scale",0.8,1)` | 无（R1–R6 未做视野过渡） | 上游的平滑扩张参考 |
| `game/map/Moon/Moon.tscn` | 同类 `CanvasModulate + Camera2D/PointLight2D + light2.png` | 无 | — |

> **B0 结论 2（Fog 第一参考源已确认）**：原版 Fog 基础设施在当前 Don't Stop 中**完整保留**，包括玩家视野灯本体与贴图。二创只把 `Main.tscn` 的 `CanvasModulate` 抬亮。因此本轮 Fog 的实现方式是：
> **同一张地图，在 Stage 31–40 动态恢复原版暗环境 + 复用既有 `Camera2D/PointLight2D`**，不新建第二套 shader/Fog-of-War，也不新建第二盏主灯。
>
> `Hero.tscn/PointLight2D2`（`visible=false` / `enabled=false` / `offset(140,0)` / `texture_scale=0.3` / `texture=game/hero/Light (1).png`）是**遗留节点**，不是原版地图视野灯，本轮不启用（避免双灯亮度叠加）。

## 9. Camp stage progression

- `LevelServer.victory()`：`Demo.next_stage = stages[mini(stages.find(level)+1,stages.size()-1)]`；`level == 30` → `Demo.campaign_complete = true`；`stage 30` 时 `next_stage` 会被 index 钳制在 30。
- `Demo.depart(stage,is_trial)` / `Town.depart()` → `LevelServer.can_start(stage)` 检查 `DemoConfig.ENCOUNTERS.has(stage)`。
- `Town.getPoint()` / `onNextLevel()` 用硬编码区间 `[1..5] [6..10] … [26..30]` 决定 R1 生成点与 Portal 指向 —— **31–40 需要新增分支（R7/R8 走 arena，不需要 Portal 链，但需要不落入 `else` 的 undefined 分支）**。
- `CampPanel.stage_list()` 逐条列出 `DemoConfig.ENCOUNTERS`，`(id-1)%5==0` 打 Region 标题；**没有任何锁定逻辑**，任何 `id` 都能 `depart(id,true)`（`trial=true`）。

## 10. save migration

- `schema_version = 6`（`Demo.snapshot()` / `create_new_save()`）。
- `CampSnapshot.validate()`：`int(data.schema_version) in [1,2,3,4,5,6]`；要求 `ENCOUNTERS.has(next_stage)` 且 `ENCOUNTERS.has(selected_stage)`；不拒绝额外未知字段。
- `CampSnapshot.normalize()`：v1→v6 逐级补齐，末尾强制 `result.schema_version = 6`。
- `Demo.load_camp()`：先 `validate` 再 `normalize`，`normalize` 之后才写 `campaign_complete / next_stage / selected_stage`。
- namespace：`user://dont_stop_camp.json`（`Demo.save_path`），本轮**不改**。

> **B0 结论 3**：迁移点应放在 `CampSnapshot.normalize()`：`campaign_complete == true && next_stage == 30` → `next_stage = 31`。因为 `validate()` 在 `normalize()` 之前跑，而 31 会加入 `ENCOUNTERS`，所以 validate 对旧档（next_stage=30）与新档（31）都通过，**无需 bump schema_version**。

## 11. M9 Boss / M10 Density / SpawnAudit 现状

- `tests/M9Bosses.gd` → `extends M8Runtime`；现有 Boss 证据目录 `docs/iteration/evidence/m9/*`（`barrage-final.json`、`beam-final.json`、`boss-full.json`、`boss-high.json`、`power-final.json`、`m9-region-*.png`、`m9-weapon-*.png`）。
- `tests/M10Density.gd`：`for stage in [22,26,29]`（`probe` 模式 `[7,13,17,22,26,29]`）；每关 55s 上限；记录 `alive_peak / mean_alive / near80_peak / spawns / simple_spawns / simple_ratio / illegal_near_spawns / clear / movement / shots / seconds`；输出 `docs/iteration/evidence/m10/density.json`。
- `tests/R3SpawnAudit.gd`：`SEEDS=[11,808,4242]`；`WAVE_STAGES=[1,4,5,16,21,26,29]`；`BOSS_STAGES=[10,20,30]`；`EMISSIONS_PER_ROUND=5`、`DENSE_EMISSIONS=8`；`TIME_BUDGET_MS=420000`；统计 `samples / invalid_candidates / retries / deferred / illegal_final / out_of_bounds_during_play / wall_overlap / unreachable / refusals`。**全部使用真实碰撞器做物理形状查询，无中心点假校验。**
- 测试基类：`M8Runtime.gd extends M3Weapons.gd`，提供 `boot()`（`SubViewport 410×230` + `Main.tscn`）、`configure(gun,full)`、`fire_at()`、`driving` 自动机（含 telegraph/墙/敌人/投射物避让评分 + dash）。
- `tools/run-m11.py` 等服务在**不可变快照**上运行：复制源码到 `archive/workspace-support/test-temp`，`--render` 时把鼠标模式替换为 `MOUSE_MODE_VISIBLE` 并屏蔽 `warp_mouse`，`--headless` 或 `--rendering-method gl_compatibility --position -10000,-10000 --resolution 1366x768 --minimized`。

## 12. 性能底线（现有）

| 上限 | 值 | 位置 |
| --- | --- | --- |
| 敌方投射物 | 180 | `TacticalEnemy.shot()` |
| HostileVFX | 32 | `HostileVFX.alive` |
| telegraph 细节降级 | `hostile_zone` 组 > 32 | `HostileZone._draw` |
| Arena 生成点候选 | 全网格（56×42 = 2352 单元，`cells` 约千级） | `CombatArena.spawn_near` |
| Renderer | `forward_plus`（桌面）/ `gl_compatibility`（mobile & web） | `project.godot` |
| 渲染线程 | Web 为 nothreads | CI 目标 |

## 13. B 批架构决策（对照上表）

| 决策 | 内容 |
| --- | --- |
| 敌人攻击 UI | 扩展 `CombatTelegraph.paint()` 增加 `style` 维度（按攻击类型调色），**不改** `HostileZone` 的碰撞/伤害判定 |
| 地图 Hazard | 新建 `StageHazard.gd` + `ArenaHazardDirector.gd`，统一 epoch/stage 绑定、入组 `stage_hazard` + `combat_transient`、回营 `return_to_camp()` 已按 `combat_transient` 清理故自动覆盖；**不写进 `Town.gd`** |
| 毒区伤害 | 走 `Hero.on_percentage_hit()`，不直接改 `player_hp`；重叠设上限；离开立即停 |
| 控制攻击 | 复用 `Hero.apply_root()`，**不新增第二套 stun** |
| 视野/迷雾 | `ArenaVisibility.gd` 单点管理 `CanvasModulate` + 既有 `Camera2D/PointLight2D`；`stage<=30` 正常亮度、`stage>=31` 暗环境 + 玩家灯 + Hell profile；Tween 过渡（参考上游 SnowWorld）；回营/回菜单/二次开始/暂停恢复全部重设 |
| 迷雾公平性 | `HostileZone` / `BossUltimate` 增加"可见警告门"：几何进入玩家可见半径累计 ≥0.5–0.8s 才允许造成伤害；stages ≤30 可见半径极大 → 行为与现状完全一致 |
| 地图扩大 | `CombatArena.bounds` 768×576 → **880×660**（+14.6% / +14.6%），同步更新 `AStarGrid2D.region`、外围边界墙、`WALLS` 重排、`spawn_near` 环带、Boss 生成环带。**R1 营地完全不改。** |
| Hell Threat Index | `HellMode.gd`：`31→2, 32→4 … 40→1024` 仅作为**设计索引**，映射到**有上限**的多维：HP ×1.15→2.4、DMG ×1.08→1.9、SPEED ×1.02→1.20、同时参战密度 ×1.15→2.0、special ratio↑、elite↑、hazard 1→最多 3 类、fog 逐步收紧 |
| Boss | 3 PHASE（100–70 / 70–35 / ≤35），保留 `boss_ultimate` 百分比框架与现有三类基础攻击；新增 B04 且不复用 B03 资产 |
| 存档 | 不做 schema bump；迁移在 `CampSnapshot.normalize()`；`hell_complete` 作为可选字段（旧档缺省 false，`validate` 不强制要求） |
| CI | 不重做 `deploy-pages.yml`；只补 native gameplay tests（B1/B3/B4/B5/B6 五个新场景）并扩展现有三个 |
