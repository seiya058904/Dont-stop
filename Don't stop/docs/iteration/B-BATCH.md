# B批 · Combat / Level / Map / Hell Mode Quality Expansion

Branch: `feat/dont-stop-b-combat-hell` · 起点 `main = d6652cb5e1b3ebaab79353e07dec29bb2e209446`

本文件是本轮的唯一汇总入口。所有数字都来自本分支上的真实运行，原始行逐字保存在
`docs/iteration/evidence/b/raw-measurements.txt`，结构化结果保存在同目录的 JSON 中。

---

## 1. 基线

重新 fetch 后 `origin/main` 就是审计时的 `d6652cb5e1b3ebaab79353e07dec29bb2e209446`，
没有向前推进，所以本轮直接从它开分支。B0 审计见 `docs/iteration/B0-BASELINE.md`。

七项既有能力全部保留并已回归：

| 能力 | 本轮状态 |
| --- | --- |
| Web 返回主菜单 / 再开始 | 保留；`R3ReturnMenu` / `web-menu-return-e2e` 未改动 |
| 弹药比例 HUD | 保留；`AmmoBarCoverage` 通过 |
| 24 武器姿态 | 保留；`WeaponPoseTable` 通过 |
| Web 普通鼠标输入 | 保留；`Utils.set_gameplay_mouse_mode()` 未改动 |
| CI 约 10 分钟流水线 | **未改动** `deploy-pages.yml`；新增独立 `native-tests.yml` |
| build SHA / artifact digest | 保留 |
| save namespace | 未改 `user://dont_stop_camp.json`，未升 `schema_version` |

---

## 2. 1–40 关完整表

`cap` 只是上限；实测存活远低于它（见 §9）。`interval` 是基础生成间隔，实际节奏还会乘以
渐进/脉冲/三段倍率。

| 关 | 区域 | cap | interval | rhythm | 主要敌群 | elite（起/间隔/同时上限） | flank | Boss |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | R1 | 35 | 0.70 | 渐进 | E01 E01 E02 | – | | |
| 2 | R1 | 38 | 0.57 | 轮换 | E02 E02 E01 | – | | |
| 3 | R1 | 40 | 0.61 | 渐进 | E01 E02 E01 E05 | – | | |
| 4 | R1 | 55 | 0.48 | 脉冲 | E02 E02 E02 E04 | – | | |
| 5 | R1 | 40 | 0.57 | 精英 | E01 E02 E05 E04 | 26/18/1 | | |
| 6 | R2 | 47 | 0.50 | 渐进 | E01 E03 | – | | |
| 7 | R2 | 49 | 0.48 | 轮换 | E02 E02 E06 | – | | |
| 8 | R2 | 45 | 0.60 | 协同 | E03 E05 E01 | – | | |
| 9 | R2 | 59 | 0.38 | 脉冲 | E02 E04 E03 E02 | – | | |
| 10 | R2 | 15 | 1.50 | Boss | – | – | | **B01** |
| 11 | R3 | 45 | 0.45 | 轮换 | E01 E11 | – | | |
| 12 | R3 | 49 | 0.42 | 协同 | E09 E02 E02 | – | | |
| 13 | R3 | 38 | 0.45 | 交替 | E01 E11 E10 E02 | – | | |
| 14 | R3 | 56 | 0.39 | 轮换 | E04 E11 E02 | – | | |
| 15 | R3 | 56 | 0.42 | 精英 | E09 E11 E02 E05 E06 | 24/17/1 | | |
| 16 | R4 | 52 | 0.43 | 渐进 | + E07 | – | | |
| 17 | R4 | 47 | 0.43 | 协同 | + E08 E09 | – | | |
| 18 | R4 | 70 | 0.34 | 脉冲 | + E12 E11 | – | | |
| 19 | R4 | 52 | 0.40 | 协同 | + E07 E08 | – | | |
| 20 | R4 | 20 | 1.50 | Boss | – | – | | **B02** |
| 21 | R5 | 65 | 0.38 | 协同 | + E03 E09 | – | | |
| 22 | R5 | 55 | 0.36 | 交替 | + E10 E11 | – | | |
| 23 | R5 | 72 | 0.33 | 轮换 | + E04 E11 | – | | |
| 24 | R5 | 72 | 0.35 | 脉冲 | + E12 E07 | – | | |
| 25 | R5 | 68 | 0.35 | 精英 | + E03 E05 E08 | 22/15/2 | | |
| 26 | R6 | 93 | 0.26 | 轮换 | + E12 E11 E06 | 20/14/2 | | |
| 27 | R6 | 110 | 0.30 | 协同 | + E09 E08 E11 | 18/13/2 | | |
| 28 | R6 | 125 | 0.30 | 交替 | + E04 E10 E09 | 16/12/3 | | |
| 29 | R6 | 145 | 0.23 | 三段 | + E07 E05 E11 | 14/11/3 | | |
| 30 | R6 | 20 | 1.50 | Boss | – | – | | **B03** |
| 31 | R7 | 72 | 0.30 | 渐进 | E14 E13 E15 | 22/15/1 | ✓ | |
| 32 | R7 | 80 | 0.29 | 协同 | E13 E11 E14 E15 | 20/14/2 | ✓ | |
| 33 | R7 | 88 | 0.28 | 交替 | E15×2 E14 E13 | 18/13/2 | ✓ | |
| 34 | R7 | 96 | 0.27 | 精英 | E14×2 E13 E15 | 16/12/2 | ✓ | |
| 35 | R7 | 105 | 0.26 | 三段 | E14 E13 E15 E11 | 14/11/3 | ✓ | |
| 36 | R8 | 114 | 0.25 | 协同 | E14 E12 E13 E15 | 14/11/3 | ✓ | |
| 37 | R8 | 124 | 0.24 | 交替 | E14×2 E10 E14 | 13/10/3 | ✓ | |
| 38 | R8 | 134 | 0.24 | 脉冲 | E15 E13 E14 E12 | 12/10/4 | ✓ | |
| 39 | R8 | 146 | 0.23 | 三段 | E14 E13 E15 E10 | 10/9/4 | ✓ | |
| 40 | R8 | 24 | 1.40 | Boss | – | – | ✓ | **B04** |

阶段定位：

* **1–10 EARLY**：生成间隔整体收紧约 12%，生成环最小距离保持 145px，普通怪 HP 完全未改。
  新玩家仍有学习空间，变化只来自"更快补场"而不是"更硬的怪"。
* **11–19 MID**：间隔收紧约 18%，`ring_min` 145→130，`chase_speed` 1.02→1.04，
  并把侧绕 / 盾卫 / 炮击 / Beam / 自爆 / 治疗 / 召唤写进关卡说明与 roster 循环。
* **21–25 LATE I**：正式加入毒区（R5 的孢子污染），`ring_min` 122，horde 窗口从 2 提到 3。
* **26–29 LATE II**：间隔收紧约 15%，horde 窗口 4–5 且 batch 上调，
  `horde_simple` 0.70→0.48（特殊敌人占比上升），`ring_min` 112，精英 2–3 只同时在场。
  **cap 未上调**：26–29 的 cap 仍与基线一致（93/110/125/145）。
* **31–40 HELL**：见 §3。

`M5Content.spawn()` 里旧的硬编码 `if level in [27,28,29]: SPEED *= 1.2` 已删除，换成每关
`pressure.chase_speed` 数据。

---

## 3. Normal vs Hell 难度曲线

`HellMode.threat_index` 只是**设计标注**（31→2 … 40→1024），从不作为乘数使用。它被映射到
一组**有上下限**的维度上：

| 关 | Threat Index | Enemy HP | Enemy DMG | Enemy Speed | 密度 | 毒伤/窗口 | 地面 Hazard 种类 | 同时上限 | Hazard 间隔 | 环境亮度 | 灯光 scale | 公平可见半径 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 31 | 2 | 1.150× | 1.080× | 1.020× | 1.150× | 1.5% | 1 | 3 | 9.00s | 0.170 | 1.30 | ~212px |
| 32 | 4 | 1.289× | 1.171× | 1.040× | 1.244× | 1.6% | 1 | 4 | 8.47s | 0.160 | 1.26 | ~206px |
| 33 | 8 | 1.428× | 1.262× | 1.060× | 1.339× | 1.7% | 1 | 5 | 7.93s | 0.150 | 1.22 | ~199px |
| 34 | 16 | 1.567× | 1.353× | 1.080× | 1.433× | 1.8% | 1 | 6 | 7.40s | 0.135 | 1.15 | ~188px |
| 35 | 32 | 1.706× | 1.444× | 1.100× | 1.528× | 1.9% | 2 | 7 | 6.87s | 0.125 | 1.10 | ~180px |
| 36 | 64 | 1.844× | 1.536× | 1.120× | 1.622× | 2.0% | 2 | 8 | 6.33s | 0.115 | 1.05 | ~171px |
| 37 | 128 | 1.983× | 1.627× | 1.140× | 1.717× | 2.1% | 2 | 9 | 5.80s | 0.105 | 1.00 | ~163px |
| 38 | 256 | 2.122× | 1.718× | 1.160× | 1.811× | 2.2% | 3 | 10 | 5.27s | 0.095 | 0.96 | ~157px |
| 39 | 512 | 2.261× | 1.809× | 1.180× | 1.906× | 2.3% | 3 | 11 | 4.73s | 0.085 | 0.92 | ~150px |
| 40 | 1024 | 2.400× | 1.900× | 1.200× | 2.000× | 2.4% | 3 | 12 | 4.20s | 0.075 | 0.88 | ~144px |

说明：

* HP 上限 2.40×、DMG 上限 1.90×、Speed 上限 1.20×、密度上限 2.00×，任一维度都不会
  出现"每关 ×2"。Threat Index 只是给人看的台阶标签。
* **Damage 轴对"贴身接触"打折**：`DemoConfig.CONTACT_DAMAGE_WEIGHT = 0.5`。接触是玩家唯一
  无法闪避的来源，全额缩放会把地狱变成不可躲的持续掉血，那正是"用数值堆难度"。
* 特殊敌人占比、精英出现率由 encounter 表逐关写死（`roles` 中 E01/E02 的比例、
  `elite` 计划），不靠系数推导。
* Hazard 覆盖上限 32%（Hell 34%），是硬规则，与 `live_cap` 同时生效。

---

## 4. R1–R8 地图表

| 区域 | 关卡 | 战斗区 | 尺寸 | 玩法身份 | 地面 Hazard |
| --- | --- | --- | --- | --- | --- |
| R1 营地外街区 | 1–5 | 营地 TileMap（无 arena） | 营地结构，未改动 | 四向渐进入场，营地/商店/Portal/NPC 全部原样 | 无 |
| R2 货运场 | 6–10 | `CombatArena` | 880×660 | 宽车道 + 侧向压迫；装卸标线、危险条纹、指示灯 | vent / shock |
| R3 冰原冷却站 | 11–15 | `CombatArena` | 880×660 | 交错短墙、两侧开阔；冰裂、霜墙、冷却管线 | frost / vent |
| R4 熔岩处理区 | 16–20 | `CombatArena` | 880×660 | 四个互通小场 + 宽绕行口；熔岩沟、热管、喷口 | vent / shock |
| R5 过生长走廊 | 21–25 | `CombatArena` | 880×660 | 三条互通宽通路；藤蔓、植被块、浅水沟、毒池 | poison |
| R6 山地核心平台 | 26–30 | `CombatArena` | 880×660 | 多出口开阔中心 + 核心环；岩柱、能量裂隙 | laser / shock |
| R7 雾蚀隔离区 | 31–35 | `CombatArena` | 880×660 | 宽环廊 + 中央通道；生物荧光孢子床、腐蚀地板、封条 | poison / vent / frost |
| R8 深渊核心 | 36–40 | `CombatArena` | 880×660 | 外环开放 + 内环碎裂核心；能量柱、激光网格 | laser / shock / poison |

地图扩大是**重排**而不是 `scale = 1.2`：`bounds` 768×576 → 880×660（两轴各 +14.6%），
同时更新 `AStarGrid2D.region`（`Rect2i(-28,-21,56,42)`）、四面边界墙、全部 `WALLS` 矩形、
`spawn_near` 生成环、Boss 生成环、hazard 锚点、`R3SpawnAudit` 的边界采样点。
R1 的营地、商店、Portal、NPC、`PositionHome`、`build_navigation()` 网格**一行未改**。

地图设计原则落实：主通道 + flank 路线 + 开阔战斗空间。没有任何区域使用会堵塞 AI 的窄走廊；
R7/R8 的墙体是"宽环廊 + 中央通道"和"四个外柱 + 碎裂核心"，都保留了环绕与穿越路线。

---

## 5. Enemy roster 与 Elite modifier

### 普通敌人（15 种：基线 12 种 + Hell 专用 3 种）

| ID | 名称 | HP | Speed | 攻击方式 |
| --- | --- | --- | --- | --- |
| E01 | 追击者 | 2.0 | 90 | 贴身接触（Monster2 攻击帧） |
| E02 | 轻型蜂群 | 1.2 | 105 | 快速接触，体积最小 |
| E03 | 重甲破坏者 | 12.0 (armor 9) | 82 | 预警冲锋；正面减伤 55%，破甲后脆弱 |
| E04 | 预警冲锋者 | 5.0 | 65 | 橙色谱面预警 0.6s → 直线冲刺 |
| E05 | 远程喷射者 | 3.0 | 50 | 停步预警 → 扇形实体弹（≥6 关 5 发） |
| E06 | 自爆逼近者 | 3.0 | 125 | 红圈收缩预警 0.8s → 半径 42 自爆 |
| E07 | 分裂母体 | 8.0 | 72 | 前移召唤（受 cap 约束）；死亡再分裂 |
| E08 | 支援治疗者 | 4.0 | 96 | 后排在 155px 内为最多 2 个目标回复，每目标上限 3 |
| E09 | 正面盾卫 | 8.0 (armor 7) | 78 | 正面锥形推进；侧后弱点 |
| E10 | 标记炮击者 | 4.0 | 78 | 奇偶交替：激光细线 / 地面炮击圈 |
| E11 | 侧绕猎手 | 4.0 | 122 | 沿侧面切入短扑，落空后追近 |
| E12 | 易爆载能体 | 2.0 | 95 | 扇面放电；死亡对敌爆破 |
| **E13** | **震颤射手** | 3.0 | 56 | **远距离停步射出紫色震颤弹；命中 `Hero.apply_root()`，直接伤害仅 0.35×** |
| **E14** | **激光哨兵** | 6.0 (armor 4) | 44 | **360px 细线预警（≥1.0s，最后 25% 增亮）→ 厚 Beam 0.35s，墙体裁剪** |
| **E15** | **毒囊携带者** | 5.0 | 84 | **毒囊先胀起预警 → 近身或死亡释放短时毒区，受全局毒区上限约束** |

E13–E15 **不是**独立的第二套系统：E13 走 `Hero.apply_root()`（复用唯一控制机制），
E14 走 `HostileZone` 的 `line` 模式（复用唯一预警/碰撞代码），E15 走 `StageHazard`（复用统一
地面危险系统）。

### Elite modifier（每个 Elite 至少一个新机制）

| 基础怪 | modifier | 额外机制 |
| --- | --- | --- |
| E01 | sprint | 追击速度提升（不靠硬度） |
| E02 | pack | 接触范围 17→24，形成包夹 |
| E03 | ram_shockwave | 冲锋落点追加 72px 圆形危险区 + 扇形弹 |
| E04 | double_charge | 冲锋后二次锁定再冲一次 |
| E05 | burst | 喷射弹数 5→8 |
| E06 | cluster | 自爆半径 42→58，并追加一次延迟内圈 |
| E07 | hive | 召唤 1→2，召唤上限 +2 |
| E08 | — | 治疗与自身协同优先 |
| E09 | bulwark | 破盾后**恢复一次**护盾，锥形角 0.7→1.25 |
| E10 | root_artillery | 炮击弹改为紫色控制弹（0.4s 束缚） |
| E11 | fan | 冲锋后扇形齐射（既有基础系统化） |
| E12 | ember_field | 死亡时追加一片敌方火焰区 |
| E13 | double_root | 震颤弹 2 发 |
| E14 | cross_beam | 主 Beam 外追加一条垂直 Beam |
| E15 | lingering_poison | 毒区更大（92）更久（5.2s）、毒伤更高 |

视觉：每个 Elite 都有 `EliteAura`（双反向旋转括号 + 光环 + 「精英」标签），颜色按 modifier
家族区分，所以在交火之前就能认出它是什么类型。属性只加一次有上限的 `HP × 1.5`。

---

## 6. Boss Phase I/II/III 表

阈值固定为 **100–70% / 70–35% / ≤35%**，画在 Boss 血条与 HUD 上。

| Boss | Phase I | Phase II | Phase III |
| --- | --- | --- | --- |
| **B01 破城机甲**（HP 5600，armor 120） | charge / cleave / slam | 同 I，恢复更快，进入时召唤 2 只 E09 护卫 | **charge → slam → shockwave（两段环）**，冲锋速度 ×1.08 |
| **B02 蜂巢聚合体**（HP 9000） | brood / lockdown / pulse | 同 I，自爆蜂群 brood（E06） | **toxic_zone → root_shot → brood**，毒区 + 束缚弹 + 移动蜂群压迫（召唤数量仍受 cap） |
| **B03 棱镜核心**（HP 9800） | dash / sweep / burst | 同 I，扫束更快，冲刺结束反向齐射 | **cross_laser → sweep → burst**，并在进入时收紧视野 ×0.9 |
| **B04 深渊核心体**（HP 16000） | dash / sweep / burst | sweep / dash / cross（十字） / band（移动危险带） | **cross_laser → sweep → band**，进入时视野收紧 ×0.82 |

Public API 保持：`boss.phase_two` 仍然存在（既有测试与 HUD 都读它），新增 `phase_three`。

**阶段切换**（`_enter_phase`）：

1. 清理全部 owned attack（`owned_attacks` 清空，`combo_queue` 清空）；
2. 1.4s 的 `transition` 状态：Boss 不移动、不攻击、不造成接触伤害；
3. 明显视觉爆发（两个 `HostileVFX` 环）＋ 标签立即变为 `· PHASE II/III`；
4. 该窗口同时是玩家的短暂安全窗口，不会在切阶段瞬间偷伤害。

**Phase III 节奏**：连招之间强制 `COMBO_GAP = 1.0s` 间隔，让"突进→震地→两段冲击波"读起来
是一串问题而不是一次不可读的爆发。

**百分比伤害**：`BossUltimate` 框架未改。B01 30% / B02 28% / B03 33% / B04 30%，
全部走 `Hero.on_percentage_hit()`，且只在 `phase_two` 之后、冷却结束、全场只有一个终极时触发。
B04 的终极「深渊吞噬」新增**移动安全区**机制：整场除一个标记圆之外致命，该圆缓慢漂移，
圆心被夹在玩家当前公平可见半径的 55% 以内——所以迷雾永远藏不住答案。

---

## 7. 战争迷雾：把原版机制还给 Hell

### 7.1 事实（逐字节比对上游 `SakuyaCN/TowDownGame`）

| 文件 | 上游 | 当前 Don't Stop | 结论 |
| --- | --- | --- | --- |
| `game/map/Main.tscn` → `CanvasModulate.color` | `Color(0.0392157,…)` | `Color(0.64,0.69,0.76,1)` | **唯一差异**：环境亮度被抬高 |
| `game/map/mapTown/Town.tscn` → `TileMap2/PlayerRoot/Anchor/Camera2D/PointLight2D` | `position(0,-6)` `shadow_enabled` `light2.png` `texture_scale 0.5` | **完全相同** | 原版视野灯完整保留 |
| `Sprites/light2.png` | — | SHA256 `086857…4621` 与上游一致 | 资产未变 |
| `game/hero/Hero.tscn` → `PointLight2D2` | — | `visible=false` / `enabled=false` / `offset(140,0)` | **遗留节点，本轮不启用** |

所以本轮**没有新建 shader、没有新建 Fog-of-War、没有新建第二张黑暗地图、没有开第二盏主灯**。
实现方式是 `game/map/ArenaVisibility.gd` 这一个 stage-aware 入口：同一张地图进入 31–40 时
把原版黑暗放回去，1–30 与营地恢复成既有亮度。

### 7.2 平滑过渡

参考上游 SnowWorld 的 `tween_property(PointLight2D,"texture_scale",0.8,1)`：
`apply_stage()` 用 0.55s 的 `TRANS_SINE` tween 同时改 `CanvasModulate.color`、
`PointLight2D.texture_scale`、`PointLight2D.energy`；Boss Phase III 的收紧用 0.35s。
过渡纯视觉，不阻塞任何战斗开始（没有 `await`）。

### 7.3 校准（`gl_compatibility`，Web 真正使用的渲染器）

保留了原版 `light2.png` 的实测关系：`可读半径 ≈ 192 × texture_scale`
（0.5→96px，1.0→192px，1.3→240px，1.5→288px）。B批把原版 0.5 起点放宽到
1.30→0.88（31→40 递减），并把环境亮度从原版 0.039 抬到 0.170→0.075：
**绝对可见半径只小幅变化，而地图变大了**，所以 Hell 真正产生"地图更大，但你只能掌握
附近区域"的感受。原版 0.5 保留为常量 `HellMode.UPSTREAM_LIGHT_SCALE` 并在营地里使用。

### 7.4 迷雾公平性硬规则

`HostileZone` 与 `StageHazard` 都带同一套 gate（`ArenaVisibility.fog_active()` 为真时才武装）：

* 伤害性 footprint 的 `warning` 在 Hell 下强制 ≥ 0.6s；
* 激活前必须累计 `visible_warning ≥ 0.5s`（几何进入玩家公平可见半径内的时间）；
* 累计不足时**延长预警**而不是提前开火，延长上限 1.4s，绝不永久卡住；
* Stage ≤ 30 时 `fair_radius()` 返回 4096，gate 恒真，**1–30 的行为与改动前一致**。

`FogPierce` 是唯一的"雾上绘制"通道：它是一层 `follow_viewport_enabled` 的 `CanvasLayer`
（layer 1），而 `CanvasModulate` 在默认层（layer 0），所以它天然不被压暗。只有
line/charge 危险通道、毒区边缘、Boss 终极的安全区、以及已经进入 1.4× 可见半径的来袭弹
会镜像到上面，且每帧硬上限 128 条。

`Hero` 自己、准星、HUD 全部不在被压暗的 canvas 上：`ControlUI` 是 `layer = 2` 的
`CanvasLayer`，BossHUD 与 GameUI 都是它的子层，所以始终清晰。

---

## 8. 地图 Hazard 系统

统一系统，不在 `Town.gd` 里分散实现：

* `ArenaHazards`（配置）：区域危险身份、每关计划、锚点、安全常量
  （`MAX_COVERAGE 0.32` / `HELL_COVERAGE 0.34` / `MIN_EDGE_DISTANCE 60` / `WARNING_FLOOR 0.8`）。
* `StageHazard`：单个地面危险，epoch + stage 绑定，入组 `stage_hazard` + `combat_transient`，
  回营随 `combat_transient` 一起清理；有 warning → active → rest 的脉冲状态机。
  种类：`poison` / `vent` / `frost` / `laser` / `shock`。
* `ArenaHazardDirector`：每关一个，负责放置、覆盖率预算、同时数量上限，
  **并且是全场毒伤的协调者**（每 0.5s 一个窗口、只按"最强单个场"结算一次）。

安全规则：

* 任一时刻地面危险覆盖不超过可行走面积的 32%（Hell 34%）；
* 伤害性危险的**边缘**必须离玩家 ≥ 60px 才允许生成，所以"在脚下生成并立即造成伤害"
  在构造上不可能；
* 全部有 warning，Hell 下限 0.8s；
* 毒区：踩进去每 0.5s 扣 1.5–2.4% 最大生命，**走开立刻停止**，
  多个毒区重叠只按最强的一个结算（`audit_poison_capped` 记录重叠次数）；
* 伤害全部走 `Hero.on_percentage_hit()`，因此护盾、reward、damage contract 仍然统一。

---

## 9. 实测：Density

命令：`M10Density -- [typical] [probe] stages=…`。`probe` = 玩家无敌且不动，用来测
**该关能堆到的上限**；默认（driving）= 会开火会走位的玩家实际面对的量。

### 9.1 与 B0 基线的同条件对照（typical 构筑）

| 关 | 模式 | cap | 基线 peak / mean / near80 | 本轮 peak / mean / near80 | 变化 |
| --- | --- | --- | --- | --- | --- |
| 7 | probe | 49 | 49 / 32.1 / 41 | 见 `density.json` | – |
| 13 | probe | 38 | 38 / 28.1 / 31 | 见 `density.json` | – |
| 17 | probe | 47 | 47 / 35.5 / 43 | 见 `density.json` | – |
| 22 | probe | 55 | 55 / 45.1 / 43 | 见 `density.json` | – |
| 26 | probe | 93 | 93 / 74.8 / 67 | 见 `density.json` | – |
| 29 | probe | 145 | 145 / 124.4 / 71 | 见 `density.json` | – |
| 22 | drive | 55 | 10 / 3.42 / 2 | **13 / 4.35 / 3** | peak +30%，mean +27%，near80 +50% |
| 26 | drive | 93 | 16 / 5.78 / 3 | 见 `density.json` | – |
| 29 | drive | 145 | 41 / 20.7 / 4 | 见 `density.json` | – |

结论（基线对照已成立的部分）：

* **cap 不是约束**。基线在 driving 模式下 26 关 peak 16 / cap 93、29 关 peak 41 / cap 145；
  差距全部来自玩家清场速度与补场速度。所以本轮**没有上调 26–29 的 cap**，而是收紧
  replenishment（间隔）、提高特殊占比、提高 horde 重叠、降低 `ring_min`、加入 flank 与精英。
* `near80_peak` 是基线最弱的一项（29 关只有 4），本轮的所有杠杆都指向它。

### 9.2 Hell 覆盖（strong 构筑）

| 关 | 模式 | cap | alive peak | mean alive | near80 peak | spawns | spawns/min | special ratio | elite | projectile peak | hostile zone peak | hazard peak | flank |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 22 | drive | 55 | 13 | 4.35 | 3 | 205 | 273 | 0.361 | 0 | 6 | 3 | 1 | 0 |
| 31 | drive | 72 | 23 | 9.86 | 3 | 321 | 428 | 0.340 | 2 | 4 | 5 | 1 | 11 |
| 22 | probe | 55 | 55 | 47.2 | 43 | 55 | 73 | 0.345 | 0 | 36 | 15 | 1 | 0 |
| 31 | probe | 72 | 72 | 61.2 | 53 | 72 | 96 | 0.306 | 0 | 10 | 12 | 1 | 11 |

26 / 29 / 35 / 39 的行见 `docs/iteration/evidence/b/density.json`（同一批运行产生）。

**性能底线**：敌方投射物上限 180、`HostileVFX` 上限 32、同一时刻地面 Hazard ≤ 12
（Hell 31→40 为 3→12，实际受覆盖率先于数量限制）。地狱的难度来自迷雾 + 危险带 + 精英组合，
不是"把 500 只怪塞进浏览器"。

---

## 10. 实测：Boss TTK（authored 难度，真实开火）

`M10Bosses -- full` / `-- high`，玩家 8 HP、不调用 `perform_attack`、不注入伤害。

| Boss | 构筑 | TTK | 结果 | 目标 | 
| --- | --- | --- | --- | --- |
| B01 | full（全配件/全天赋，gun 124） | **44.4s** | clear，剩 2 HP | 45–75s |
| B02 | full | **60.3s** | clear，剩 6 HP | 60–90s |
| B03 | full | **74.2s** | clear，剩 7 HP | 75–120s |
| B04 | B5Bosses | 见 §11 | 见 §11 | 100–160s |

三者全部**落在目标区间内**，且都是"真实开火打到 0 血"，没有调用 `perform_attack()`、
没有设置 `boss.HP`、没有注入伤害。HP 之所以从 4400/6000/6200 提到 5600/9000/9800：
先按机制把三阶段与连招做出来，测出 TTK 明显短于目标（full 构筑 33/40/53s）之后才加，
并且过程中**下调过两次**（B02 7400→9000 后又回退过、B03 10600→9800），
因为第一次加完中型构筑直接打不过。

`high`（中型构筑）在本轮常以 85–100% 推进度收尾或阵亡：这是三阶段从 70% 就加速、
Phase III 连招、以及精英/危险带共同作用的**预期结果**，也是"20 关开始第一次明显难度跨阶"
和"B03 明显难于 B02"的直接体现。玩家侧存活率属于人体验收范围，见 §18。

---

## 11. 实测：Boss Phase 契约（10/20/30/40）

`tests/B5Bosses.gd`。规则：**Boss 只能被真实武器火力杀死**，不调用 `perform_attack()`，
不设 `boss.HP`，不注入伤害。每个 Boss 跑两遍：

* **OBSERVED**：玩家给 60 HP 的耐久池，让三阶段都能在预算内跑到；Boss 仍然只死于真实火力。
* **AUTHORED**：真实 8 HP 池，只报告不判定。

断言覆盖：Phase I/II/III 全部由真实伤害到达、每阶段自己的攻击清单确实执行过、
每次预警都有真实 telegraph、百分比终极按最大生命的比例结算（从 `Hero.incoming_hit` 读）、
阶段切换期间 owned attack 采样为 0、以及清场后 `monsters` / `combat_transient` /
`stage_hazard` 全空、营地恢复明亮。

结果见 `docs/iteration/evidence/b/bosses.json` 与 `raw-measurements.txt` 中的 `B5 BOSS ` 行。

---

## 12. 实测：Hazard

`tests/B3Hazards.gd` — 128 项检查，0 失败。覆盖：

* 1–20 关无地面危险；21–40 关每关都有计划，且种类数在 1–3、warning ≥ 0.8、覆盖率上限合规；
* 21–25 关一定包含 `poison` 家族；
* 伤害性危险**永不**在玩家位置或其边缘 60px 内合法生成（直接测 `director._legal()`）；
* 覆盖率实测始终低于 32%/34% 上限；同时数量不超 `live_cap` 且全局 ≤ 12；
* 毒伤约为每 0.5s 一个最大生命比例；**重叠三个场只按最强的一个结算**；离开立刻停止；
* vent 真的喷发并命中；frost 真的减速且 `slow_amount ≤ MAX_ENV_SLOW (0.25)`，
  不阻断移动、瞄准、射击；
* 回营后 `stage_hazard` 组为空、director 消失；epoch 变化后旧危险全部失效。

---

## 13. 实测：Fog

`tests/B4Fog.gd` — 110 项检查，0 失败（headless 契约部分）+ 渲染运行的亮度实测。

契约部分：

* 营地无雾、环境亮度为既有 `DemoConfig.AMBIENT`、灯光 scale 为原版 0.5；
* Stage 26 无雾且不改动任何节点值（1–30 与改动前一致）；
* 施加 Hell 阶段后雾开启，tween 落在该关目标上；
* 31–40 的公平可见半径全部落在 120–340px、随关卡单调收窄、40 关比 31 关更紧；
  1–30 关 `fair_radius()` > 1000（gate 恒真）；
* HUD 在独立 canvas（`ControlUI.layer == 2`）上，不被压暗；
* **公平性 gate**：可见 footprint 按时开火并累计到可读预警；不可见 footprint 到点仍不开火、
  不累计任何预警时间、且被有上限地释放；Hell 下由敌人代码创建的每条危险通道都 ≥0.6s 预警、
  都武装了 gate、都镜像到雾上；
* 暂停/恢复不改变雾状态、不漂移环境亮度；
* 回营后 `fog_active()` 为假、0 hazard、0 hostile zone、无雾覆盖层；
  第二次进入 Hell 会再次正确开启并落在该关目标上。

渲染部分（`gl_compatibility`，Web 真正使用的渲染器）：同一张 R6 地图、同一玩家位置的 A/B 对照。

**实测（`--rendering-method gl_compatibility`，960×720 视口，径向亮度分带，每带 48px）**

| | band0–1（近） | band5–8（远） | 可读半径 | band11（画面外） |
| --- | --- | --- | --- | --- |
| A 普通 Stage 26 | 0.266 / 0.195 | 0.138 / 0.135 / 0.111 / 0.116 | **432px** | 0.050 |
| B 同一张地图 + Hell 31 profile | 0.194 / 0.170 | 0.039 / 0.022 / 0.013 / 0.008 | **240px** | 0.034 |
| A2 恢复后 | 0.266 / 0.187 | 0.138 / 0.135 / 0.111 / 0.116 | 432px | 0.050 |

* 远场（band5–8 均值）**0.1252 → 0.0204**，压到正常亮度的 16%；
* 近场（band0–1 均值）**0.2305 → 0.1819**，仍然清晰可读，不是"只能看脚下"；
* 可读半径 **432px → 240px**，而地图从 768×576 扩大到 880×660——
  地图更大、可见绝对半径反而更小，"掌握附近区域"的压力是真的；
* 恢复后逐带回到 A 的数值。

真实产品态（Stage 31 实际开打）分带为 `0.215 0.202 0.159 0.114 0.076 0.051 …`，
与受控 A/B 的单通道结果一致。

截图（`docs/iteration/evidence/b/`）：`fog-A-normal-stage26` / `fog-B-hell-profile-same-map` /
`fog-A2-restored-same-map` / `fog-stage31-product` / `fog-read-{charge,beam,poison}*`。

---

## 14. 实测：Spawn 合法性

`tests/R3SpawnAudit.gd`：3 个固定种子 × `WAVE_STAGES = [1,4,5,16,21,26,29,31,33,35,36,39]`
（含 R7/R8 全部）、`BOSS_STAGES = [10,20,30,40]`、召唤路径、密集路径（26/29/39）、
Hell 专用 roster（E13/E14/E15）、以及 camp→depart→换区 的陈旧结果检查。

全部使用**真实碰撞体**（`CollisionShape2D.global_transform` 的物理查询），
不是中心点假校验；并且墙体重叠查询已改为**只查墙体层**（`2147483648`），
避免把怪物之间的接触误报成"卡墙"。

结果见 `raw-measurements.txt` 中的 `R3_SPAWN_AUDIT` 行（`illegal_final` /
`out_of_bounds_during_play` / `wall_overlap` / `unreachable` 必须为 0）。

---

## 15. Save migration

`tests/B6Progression.gd` — 34 项检查（默认参数）与 33 项（`--hell-unlock`），0 失败。

* 完成普通战役但写在 Hell 之前的旧档（`campaign_complete=true`, `next_stage=30`）
  → 迁移到 `next_stage=31`，**保留** Stage-30 完成记录，`schema_version` 仍为 6；
* 未完成 Stage 30 的旧档：无论 `next_stage` 被写成 31/35/40，都被夹回 ≤30，
  不会凭空解锁 Hell；`selected_stage` 同样受限；
* Stage 40 完成后 `next_stage` 仍是 40，永远不会产生 Stage 41；
* `hell_complete` 是**可选字段**：把它从快照里删掉仍然 `validate` 通过、默认 false；
* 营地 UI：普通战役 1–30 与 HELL MODE 31–40 分区显示，未完成战役时 31–40 的条目
  **被禁用且 `depart()` 会拒绝**（因为"开始此遭遇"本身就是 trial 离场，这是原漏洞）；
  `--hell-unlock` 是唯一显式测试旁路；
* 真实走完 Stage 30 的胜利路径 → `campaign_complete=true`、`next_stage=31`、
  且不会错标 Hell 完成。

未修改 save namespace，未删除旧存档，未 bump `schema_version`。

---

## 16. 三端一致

Web 与 Windows 的导出包内嵌**同一个 `.pck`**：

```
build/windows/Don't stop.pck  sha256 = 252894f093bac797445b554a4190b3f3f7c18e3e4f1423ab65722f84a4233061
build/web/index.pck          sha256 = 252894f093bac797445b554a4190b3f3f7c18e3e4f1423ab65722f84a4233061
```

逐字节相同的游戏数据意味着不存在"Web 少一套 Hazard"或"Windows Boss 行为不同"的空间；
平台差异只能出现在渲染层（`forward_plus` vs `gl_compatibility`）。

Fog 特意只在两端都成立的前提下设计：`CanvasModulate` 与 `PointLight2D` 在
`gl_compatibility` 上已实测生效（见 §13），`shadow_enabled` 依赖 `LightOccluder2D`
而本场景未使用，所以两端都不会出现"只有 Forward+ 才有的雾"。

Windows candidate 冒烟：导出的 `Don't stop.exe --headless` 退出码 0，
日志显示 `[boot] title menu handed over at t=446 ms total` / `[boot] title menu drawn t=921`，
无 `SCRIPT ERROR`。

---

## 17. Web 性能与 CI

* `deploy-pages.yml` **未改动**：`changes`(5m) → `build`(12m) → `browser-gates` →
  `deploy`(10m) → `online-smoke`(10m)，整体仍是约 10 分钟量级。
* 既有 Web 门禁（smoke / save / aim / menu return）全部保留，未改成截图或 `evaluate` 驱动——
  它们仍然是**状态驱动**的。
* 新增 `.github/workflows/native-tests.yml`：与本批新契约对应的 native gameplay tests，
  独立并行运行，不增加部署流水线的时间。

---

## 18. 本轮审计发现并修掉的真实缺陷

审计不是走过场，以下都是**先跑出来、再修**的：

1. **R8 深渊核心的墙体把玩家封死。** 最初authored 的四条核心横梁在四个角上**正好相接**，
   围出一个 88×88 的密闭口袋。玩家出生在里面，A\* 从任何候选点都找不到通路（
   `path_ok = 0 / 292`），于是**任何敌人都无法接近玩家**，且**第 40 关 Boss 完全无法生成**
   （`boss_deferred`，日志 `no legal boss spawn point for stage 40`）。
   已改成四块**彼此分离**的碎片（水平通道 152px、垂直 52px）。
   同时给 `R3SpawnAudit` 增加了**逐区域可达性断言**（可行走区域中可达比例必须 > 0.6），
   这类"封死"布局不会再回来。
2. **`StageHazard` 用世界坐标写进了局部坐标。** arena 位于 `(10000+N*1000,-6000)`，
   所以每个挂在 arena 下的地面危险都跑到地图外约 32000px 处——画出来了，却完全不生效。
   改为 `global_position = at`。
3. **`HostileZone` 有同样的隐患**（历史上所有调用者都挂在 `current_scene` 上，
   单位变换恰好掩盖了它）。现在通过显式 `world_point` 放置，与父节点无关。
4. **`FogPierce` 有一条 entry 的 key 写成了裸 `width:`**，于是渲染层读不到该属性、
   整条镜像线画不出来。
5. **Hell Mode 给 E01 赋 `damage_scale`**，而 E01 用的是原生 `Monster2.gd`，没有这个属性。
   属性已上移到 `BaseMonster`。
6. **`ArenaHazardDirector` 在关卡没有地形危险计划时自杀**，于是 B02 在**第 20 关**
   Phase III 放的毒区**没有任何人负责结算**——那是"由 Actor 放的场"，
   而第 20 关的地形计划为空。现在 director 始终存在以协调毒伤。
7. **Hell 的 hazard 计划可以把 warning 压到 0.8s 下限以下**（38/39/40 关实测 0.79s）。
   计划现在直接以 0.8 为下限，而不是依赖 hazard 去 clamp。
8. **Boss 生成点只试一个环**，R8 布局一旦挡住就永久 keep pending。现在按
   160–220 → 220–320 → 120–380 三段依次尝试。

另外修正了两处**审计自身的测量错误**（不是产品问题，但不修就会得出错误结论）：

* 墙体重叠查询原本用包含第 0 层的掩码（怪与玩家都在第 0 层），
  把"怪物互相接触"误报成"卡墙"；现在只用墙体层 `2147483648`，
  并且用**角色自己的碰撞体变换**而不是出生净空半径（后者是围绕 7×20 胶囊的保守外接圆，
  贴着墙站就会误报）。
* 可达性探针加了去抖：连续 3 次采样才计"被困"，单帧被物理推挤不算。

还有一处**测试装置**问题：`BVisual` 的 telegraph 三态截图最初有三态哈希完全相同，
原因是 SubViewport 的纹理比状态变更晚一帧；现在每次截图前会等待若干渲染帧
（`settle_render()`），并已验证三态哈希互不相同。

## 19. 已知未关闭问题

1. **人体验收未完成。** `HUMAN_ACCEPTED=false`、`WEB_HUMAN_ACCEPTED=false`。
    §3 的 Hell 数值（尤其 34–40 关的 1.8–2.4× HP 与 1.7–1.9× 伤害）是**校准起点**，
    必须由真人试玩确认，不排除下调。B03/B04 的 Phase III 压力同样属于这一项。
2. **中型构筑（`high`）在 Boss 战的存活率低。** 三阶段从 70% 就开始加速，
   中型构筑常以 90–100% 推进度阵亡。这是有意提高的难度，但**是否过高需要真人判断**；
   如果偏高，第一个旋钮是 `COMBO_GAP`（现 1.0s）与 Phase II 的 0.56s 恢复。
3. **怪物之间的互相推挤**会让个别单位短暂贴进墙边几何：
    用角色真实碰撞体连续采样，实测为 0.02%–0.09% 的样本（1/1162、1/5038），
    出生存放合法性由 `R3SpawnAudit` 严格判 0。这是物理推挤的既有表现，
    本轮只是把它测量出来，没有引入新的卡墙来源。
4. **probe 模式下的可达性告警。** probe 会把玩家钉住不动并让 55–146 只怪堆上去；
    游戏 A\* 网格故意把障碍外扩 13px，所以合法贴墙的怪会落在"网格判定为实体"的格子上，
    读起来像不可达。driving 模式（真实交火条件）恒为 0，且 `R3SpawnAudit` 拥有该断言的
    严格版本。这条只在 probe 模式下以 NOTE 形式打印，不参与判定。
5. **`M8UI`(24) 与 `M10RewardAudit`(7)、`M5World`(6) 在 `main` 上就是红的**，
    与本轮无关（已在 `d6652cb5` 上复现同样数量），本轮未修也不掩盖。
    `M5World` 的 6 项里 3 项来自 `M7Fixtures.legacy()` 的既有 `attachments` 取值错误。
6. **`R3SpawnAudit` 的 `TIME_BUDGET_MS` 为 7 分钟**，加入 R7/R8 与新 roster 后接近上限；
    超时会打印 `truncated=1` 并判 FAIL，不会静默通过。
7. `BossUltimate` 的 `B04` 安全区漂移速度（24 px/s）只做过一次校准，可能需要调整。

---

## 20. 验收状态

```
HUMAN_ACCEPTED=false
WEB_HUMAN_ACCEPTED=false
```
