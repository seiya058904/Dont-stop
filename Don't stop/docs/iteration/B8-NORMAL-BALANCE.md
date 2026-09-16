# B8 · Normal Late-Game Balance Calibration

## 交付状态

| 项 | 值 |
| --- | --- |
| 起点 main | `594bdcd180cc96a8ab2fe62b16b48e241afae257`（执行前重新 fetch 确认） |
| B8 feature branch | `feat/dont-stop-b8-normal-late-balance` |
| 游戏部署字节（起点） | 仍为 B批合并 SHA `46e8f6c9fe5abb1c8f89c2ad625e8a42b85e6bf5` |
| 状态 | `WEB_DEPLOYED_FOR_HUMAN_REVIEW` · `HUMAN_ACCEPTED=false` · `WEB_HUMAN_ACCEPTED=false` |

本文件是 B8 的唯一汇总入口。所有数字来自真实运行；逐行原始数据保存在
`docs/iteration/evidence/b8/`。本轮**没有新增地图 / 敌人 / Boss / Hazard / Fog / UI**。

---

## 0. 执行纪律：先冻结量具，再跑长测

上一轮的教训是"边跑长测边改 probe"。本轮按六步执行：审计脚本 → 修装置 → 用便宜场景验证
探针 → 冻结 → 再跑长测。

**冻结清单位于 `docs/iteration/evidence/b8/freeze.sha256`（19 个文件的 sha256，含探针、
fixture、driver 与全局伤害入口）。整批跑完后重新校验：**

```
frozen files verified: 19, changed: 0
```

**量具本身被作废过两次，两次都记录在案：**

1. **第一次 baseline 序列作废。** 探针把死亡快照采样放在 `_sample()` 里，而 `_sample()`
   一开始就 `if LevelServer.state != "COMBAT": return`。玩家一死 `LevelServer._timeout()`
   立刻把 state 翻成 `DEAD`，于是**每一次死亡快照都是空的**。改为在
   `Hero.damage_taken` 回调里抓快照（那一刻场景必定还活着），并补了一条契约断言把这个
   竞态钉住。该次数据全部丢弃并重跑。
2. **第一次 final 5-seed 批次作废。** 我自己的调参脚本用
   `re.sub(r'"interval":[\d.]+', ...)` 改 encounter 的 `interval`，但同一行上
   `elite.interval` 也是同名 key，于是**25–29 关的精英投放间隔被连带改成了 0.33–0.36 秒**
   （原值 11–15 秒），`Town.gd:200` 读的正是这个字段，等于把 25–29 的精英变成无限刷新。
   该次数据全部丢弃，修好后重跑。
   为防止这类"行级 diff 看不出来"的事故，新增 `tools/b8-diff-table.py`，它按**字段**把
   在表与 git 上的原表逐项对比（见 §3）。

**探针验证（`tests/B8Contracts.gd`，52 checks / 0 failures）** 在每次冻结前都跑过，覆盖：

- `damage_taken` 与 `incoming_hit` 对每一次命中报出**逐位相同**的 raw/applied；
- 伤害数学未变：普通命中仍乘 `NORMAL_INCOMING`、弹幕小伤害仍绕过 1 点下限（0.35）、
  `minimum_pressure` 仍生效（2.625）、百分比仍按最大生命结算且不乘倍率（30.0）；
- **被吸收的命中不计入账本**：T19 护盾吸收、死亡状态、暂停状态三种情况下两个信号都不发；
- 九条玩家受伤路径各自报出自己的机制标签（`contact` / `artillery` / `beam` /
  `shot:projectile` / `control_shot:root` / `hazard_vent` / `percentage`…）；
- 逃生探针在空场能给出逃生（29/29）、被真实脚印完全封锁时能给出"无逃生"（0/29）、
  毒区不算封锁、雾门未释放的脚印不算封锁。

---

## 1. 修改前：22 / 26 / 29 的 5-seed 数据

口径（全部与 B批 失败那次相同）：typical 构筑、gun 117、`M8Runtime._process` **driver 一字未改**、
8 HP、`depart(stage,true)` 试炼、固定 5 个 seed（9101–9105），并额外把 `player_level` 钉在该关
在复现序列里的起始等级（22/26/29 → 7/7/8），这样 5 个样本是同一个构筑、只变随机数。

| stage | 结果 | 平均存活 | 平均 alive | alive 峰值 | 平均刷怪/秒 |
| --- | --- | --- | --- | --- | --- |
| 22 | **0/5 clear** | 17.0 s | 19.3 | 28–49 | 4.8–5.8 |
| 26 | **2/5 clear** | 32.2 s | 23.7 | 35–61 | 6.7–9.6 |
| 29 | **0/5 clear** | 9.0 s | 42.4 | **74–145（触及 cap 145）** | 13.1–15.2 |

复现序列（`mode=baseline`，按 B批 原样跑 7/13/17/22/26/29，等级自然成长）同样复现了报告中的
失败：**22 死 14.0 s、26 死 13.0 s、29 死 7.7 s**。

## 2. 修改前：各伤害来源占比

15 场（22/26/29 × 5 seed），共 217 次命中、179.25 伤害：

| 分类 | 伤害 | 占比 | 命中 |
| --- | --- | --- | --- |
| normal contact | 109.38 | **61.0%** | 130 |
| beam / hostile zone | 52.85 | 29.5% | 62 |
| enemy projectile | 10.73 | 6.0% | 18 |
| self destruct | 5.25 | 2.9% | 6 |
| arena hazard | 1.05 | 0.6% | 1 |

按机制标签：`contact` **61.0%** / `line` 12.3% / `cone` 11.9% / `shot:projectile` 6.0% /
`circle` 5.3% / `detonate` 2.9% / `hazard_laser` 0.6%。

**结论：21–29 的死亡主体是身体压力（contact 61%），不是天降秒杀。** 这与"主要是不可避免的
重叠伤害"完全不同，也直接决定了 §3 选哪两个旋钮。

## 3. 到底动了哪些旋钮

§7 的旋钮优先级里，contact 占 61% → 属于 **A. 近身包围 / 身体压力**，处方是
`ring_min` / `chase_speed` / `HORDES.windows`；同时 §7 B 说"45 秒连续同强度淹没"要用
horde 窗口修。**最终只留两个旋钮族，并且是整段 21–29 一起做，以保证曲线单调：**

| 旋钮 | 做法 | 依据 |
| --- | --- | --- |
| `HORDES`（batch/window/step/windows） | 整段 21–29 逐级放宽 | 29 关开局实测 **13.12–15.15 刷怪/秒**，单场峰值存活 74–**145（触及 cap 145）**。这不是"高压→短恢复→再高压"，是 45 秒洪水 |
| `interval`（补员间隔） | 整段 21–29 逐级放宽 | 同上，且它也是"恢复窗口"的一部分 |
| 22 关 `roles` | 第二个 `E09` → `E01`（special 40%→30%） | §7 C：special 仍决定玩法（E10/E11 保留）但同屏压制型不能过多 |

**明确没有动的：**

- **`cap` 一行未改**（65/55/72/72/68/93/110/125/145 全部原值）。§3 已经证明 cap 不是有效约束。
- **`ring_min` 没有大改。** 前几轮我一度把 22 从 122 抬到 146、29 从 112 抬到 138，但
  `Town.ring()` 的注释写明了设计意图——"late and Hell stages close it from 145 px to ~108 px"，
  即这条轴是**随关卡收紧**的。我的抬升把整条轴反了过来，还留下 122→146→122 的锯齿。
  已回退，只保留 §7 明确要求的"26–29 略微增加生成距离"：**26–29 统一 +4 px**。
- **`chase_speed` 完全回退到原值**（1.06×5, 1.08, 1.10, 1.12, 1.14），保留它自己干净的斜坡。

最终表（`tools/b8-tuning-table.py` 从源码直接读出）：

```
 st  cap interval h_simple ring_min chase elite | horde(batch,window,step,floor,windows)
 21   65     0.44     0.60    122.0  1.06     - | {"batch":4,"window":4.6,"step":0.34,"floor":6,"windows":2}
 22   55     0.44     0.58    122.0  1.06     - | {"batch":4,"window":4.5,"step":0.34,"floor":6,"windows":2}
 23   72      0.4     0.58    122.0  1.06     - | {"batch":5,"window":4.2,"step":0.32,"floor":7,"windows":2}
 24   72     0.38     0.58    122.0  1.06     - | {"batch":5,"window":3.9,"step":0.30,"floor":9,"windows":2}
 25   68     0.36     0.56    122.0  1.06     2 | {"batch":6,"window":3.6,"step":0.28,"floor":9,"windows":2}
 26   93     0.34     0.54    122.0  1.08     2 | {"batch":6,"window":3.4,"step":0.28,"floor":10,"windows":2}
 27  110     0.33     0.52    120.0   1.1     2 | {"batch":7,"window":3.1,"step":0.26,"floor":14,"windows":3}
 28  125     0.33     0.50    118.0  1.12     3 | {"batch":8,"window":2.8,"step":0.24,"floor":16,"windows":3}
 29  145     0.32     0.48    116.0  1.14     3 | {"batch":10,"window":2.4,"step":0.22,"floor":18,"windows":3}
```

`ring_min` 非升、`interval` 非升、`chase_speed` 非降、horde 强度逐级升——四个旋钮的斜坡都是单调的。

`tools/b8-diff-table.py` 的字段级对比（相对原表）：**21–29 共 14 处字段变化，30–40 共 0 处。**

## 4. 修改后：22 / 26 / 29 的 5-seed clear rate（同一 5 个 seed、同一构筑）

| stage | 修改前 | 修改后 | 目标 | 压力变化 |
| --- | --- | --- | --- | --- |
| 22 | 0/5（均 17.0 s） | **1/5（均 27.9 s）** | ~4/5 | alive 峰值 28–49 → 16–36 |
| 26 | 2/5（均 32.2 s） | **4/5（均 41.4 s）** | ~3/5 | 刷怪 6.7–9.6/s → 5.1–6.8/s |
| 29 | 0/5（均 9.0 s） | **0/5（均 11.3 s）** | ~2–3/5 | 刷怪 13.1–15.2/s → 7.9–9.1/s；alive 峰值 74–145 → 46–73 |

改动是**有效**的：29 关开局刷怪速度 −40%、峰值存活 −50%；26 关直接翻倍到 4/5 并超过目标。
但 22 与 29 **没有达到目标**，原因见 §9。

## 5. 21–29 最终难度阶梯

5-seed 批次 + §14 要求的 sanity sweep（每关 1 seed）：

| stage | 21 | 22 | 24 | 25 | 26 | 27 | 28 | 29 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 实测 | clear | 1/5 | clear | 死 17.1 s | 4/5 | 死 10.5 s | 死 7.7 s | 0/5 |

**阶梯没有稳定成立。** 实测顺序是 21 ≈ 24 > 26 > 22 > 25 > 27 > 28 > 29，而设计意图是
22 > 26 > 29（越后越难）。没有任何一关出现"越后越容易"的系统性倒挂（21/24 能通、25–29 難），
但 **26 比 22 容易**这一条是明确的倒挂，原因见 §9。

## 6. Boss 公平性抽样（§11）：B03 / B04 各 3 场真实 8HP

同一强构筑（gun 124 + 全天赋）、`target_boss=true`、**真实开火**、无强制攻击、无注入伤害。

| Boss | 场次 | 结果 | 时间 | 致命机制 | 参与封锁判定的高危脚印 | 死亡瞬间可达安全点 | 确认封锁事件 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| B03（30 关） | 1 | clear | 87.3 s | — | — | — | 0 |
| B03 | 2 | death | 41.3 s | `hazard_laser`（场地激光） | 1 | **22 / 22 安全** | 0 |
| B03 | 3 | death | 64.2 s | `boss_percentage`（大招） | 1 | **32 / 32 安全** | 0 |
| B04（40 关） | 1 | death | 41.0 s | `hazard_laser` | 2 | **30 / 42 安全** | 0 |
| B04 | 2 | death | 43.8 s | `hazard_shock` | 5（含 1 line） | **14 / 32 安全** | 0 |
| B04 | 3 | death | 60.7 s | `hazard_shock` | 4（含 1 line） | **25 / 48 安全** | 0 |

（"参与封锁判定的高危脚印"是探针用于判定"是否无路可逃"的集合，**不含毒区**——毒区离开即停
伤害，只能惩罚站桩，不能封锁移动。"可达安全点"是 49 个候选点里通过 `test_move` 真实可达、
且不被任何脚印覆盖的数量。）

**B03：1/3 clear。B04：0/3 clear。`unavoidable = 0`（六场全部）。**

**结论：高波动不是来自 unavoidable overlap。** 六次死亡全部发生在**可达安全点大量存在**的时
刻（14–32 个候选点安全，探针在 32–48 个可达点里采样），"连续 3 个采样无任何公平逃生点"的
确认封锁事件**一次都没有发生**。B04 三次死亡时迷雾均为开启状态，而探针的公平判定把
`hazard_laser` / `hazard_shock` 记为 `fair`——说明雾门规则生效，没有任何一次死亡来自
"尚未在视野内出现过就被释放"的脚印。

补充观察（供真人试玩参考，本轮不改）：**B03/B04 的死亡主要来自场地 Hazard（激光/冲击带），
不是 Boss 本体的攻击。** B04 三场都在 Phase II 结束（8 HP 池下 41–61 s），与 B批记录的
"8HP 三阶段 Boss 近似硬币投掷"一致。

## 7. Hell 31–40：**未改**（证明）

- `tools/b8-diff-table.py` 字段级对比：**31–40 共 0 处字段变化**（脚本会列出 cap / interval /
  rhythm / elite / pressure / roles / seconds / region / boss 九类字段的任何差异）。
- `HORDES` 常量 diff 只涉及第 21–29 行。
- 本轮**没有触碰** `HellMode.gd`（31=2 … 40=1024 的 Threat Index、HP/DMG/Speed/density 轴）、
  `ArenaVisibility.gd`（雾）、`ArenaHazards.gd`（Hazard 计划/覆盖率）、`TacticalEnemy.gd` 的
  攻击表与 3 阶段契约、`BossUltimate.gd` 的数值。
- 回归中 stage 31 的实测与 B批 一致（强构筑 clear，flank 11 次，illegal 0，closest 110 px）。

Normal 与 Hell 的间隔也保持：**31 关开局即带迷雾（31 关对 22/26 关：迷雾、flank、E13–E15
特殊敌人、精英计划、Hazard 计划），30→31 仍然是模式跳变。**

## 8. 相关回归（§15 的最小受影响集）

| 场景 | 结果 | 为什么要跑 |
| --- | --- | --- |
| `B8Contracts` | **52 / 0** | 量具自证 |
| `M8Contracts` | **52 / 0** | `Hero.onHit` 签名变更后的伤害/电报契约 |
| `M6Contracts` | **121 / 0** | 零伤害预警、暂停冻结 |
| `M4Talents` | **233 / 0** | T19 吸收、T24、受伤路径 |
| `M10Growth` | **233 / 0** | root / percentage / slow |
| `B3Hazards` | **128 / 0** | Hazard 伤害路径被穿入了机制标签 |
| `M10Density stages=22,31`（强构筑 driving） | **11 / 0** | **这正是 native CI pressure job 的硬门禁**：stage 22 必须 clear。实测 stage 22 clear 44.9 s、alive_mean 3.1、峰值 9、illegal 0、wall 0、stuck 0 |
| `M10Density probe stages=22,31` | **6 / 0** | CI 的 probe 门禁 |
| `R3SpawnAudit` | **20 / 0** | `ring_min` 改的正是它采样的到达环；每区域连通性断言全过 |

**按 §15 故意没有重跑**：`B4Fog`、`B5Bosses`、`B6Progression`、`M10Bosses`——本轮没有改
雾、Boss 行为、存档或进度。它们在 native CI 每次 push 时仍会跑。

## 9. 未达成项与结论（诚实记录）

**未达成的是 §6 的验收目标本身，不是"改动没生效"。** 目标：22 ≈ 4/5、26 ≈ 3/5、29 ≈ 2–3/5。
实测：22 = 1/5、26 = 4/5、29 = 0/5。

原因是可量化的，而且**不是关卡设计不公平**：

- 8 HP 池下，每次命中至少 0.875（`HostileZone` 对任何脚印伤害强制 1.0 下限，再乘
  `NORMAL_INCOMING`），所以**挨 9 次就死**。
- 要活满 45 秒，受伤频率必须低于 **0.2 次/秒**。
- 实测这个 driver 的受伤频率稳定在 **0.6–1.2 次/秒**（§1 表 "hits/s" 列），而且**几乎不受刷怪
  速度影响**——因为伤害来源是"它不会躲的攻击"：E10 的 280 px 光束（0.65 s 预警、有视线门控、
  有安全地）、E09/E12 的锥形、E05 的 5 连弹幕。把刷怪量砍掉 40%，这些攻击的**命中节奏不变**，
  只是排队的人少了。
- 关键证据：`M8Runtime._process` 里那套 16 方向预言式闪避**只在 `target_boss and target.is_boss`
  时启用**。普通关卡的 driver 完全不躲 zone 与弹幕。它死在明确预警、有安全地的技能上。
- 同一关卡的对照：**强构筑（gun 124 + 全天赋）在 stage 22 实测 alive_mean 3.1、峰值 9**，
  178 次刷怪只维持 9 只存活；typical 构筑在 34 只存活里被埋。**stage 22 不是不公平，它是 DPS 检查。**

按 §12 的原则（"不要为了让自动 driver 稳定通关而把 Boss 做弱，自动 driver 不是产品玩家"），
我没有为了凑 clear rate 去削弱这些攻击，也没有为了凑目标去删掉 E10（它就是 22 关
"炮击与盾卫封锁走廊"的身份）。因此本轮**到此为止**，把差距原样上报。

**公平性抽样（§7 的判定）**：Normal 15 场里 10 次死亡，其中 **2 次**（都在 stage 22）死亡瞬间
"没有任何公平可达安全点"；但这 2 次探针总共只能找到 **1–2 个可达候选点（共 49 个）**，
即玩家是被身体/几何**卡住**的，而不是脚印组合把场地封死。修改前同样的数是 3 次。
Boss 六场是 0 次确认封锁。

**下一步建议（留给真人试玩后决定）**：

1. **让 driver 在普通关卡也使用它已有的闪避逻辑**（把 `target_boss` 的预言式避让对 zone/弹幕
   打开）。这是 fixture 变更，需要单独一轮并重测全部基线——但它才是"4/5 clear"的真正前置条件。
2. 或者接受 21–29 的现状：强构筑可通、typical 构筑是硬挑战，把 clear-rate 目标改成
   真人试玩数据来定。
3. 若确认 E10 的 0.65 s 预警对真人偏短，再单独讨论（它在项目自己的雾公平规则 0.5–0.8 s 的
   区间内，因此本轮未动）。

## 10. 本轮新增/修改的文件

**产品代码**

- `Don't stop/game/hero/Hero.gd`：新增观测信号 `damage_taken(raw, applied, source, attacker)`；
  `onHit` 增加可选 `source`，`on_percentage_hit` 增加可选 `source`。**伤害管线不读回该值。**
- `Don't stop/game/monster/{DemoEnemy,TacticalEnemy,EnemyShot,HostileZone,BossUltimate}.gd`、
  `game/monster/Monster 2/Monster2.gd`、`game/map/{StageHazard,ArenaHazardDirector}.gd`：
  九条玩家受伤调用点各自声明机制标签（+ `EnemyShot` 带上攻击族，用于区分弹幕环与单体弹）。
- `Don't stop/game/config/M5Content.gd`：Normal 21–29 的 `HORDES`、`interval`、22 关 `roles`、
  26–29 的 `ring_min`（+4）。

**测试与工具**

- `Don't stop/tests/B8Probe.gd`：死亡来源账本 + 逃生可达性探针（含雾门公平判定与视线门控）。
- `Don't stop/tests/B8Normal.gd` / `.tscn`：21–29 driving fixture（`mode=baseline` 复现、
  `mode=batch` 固定 seed + 钉等级）。
- `Don't stop/tests/B8BossFair.gd` / `.tscn`：Boss 公平性抽样 + 判定。
- `Don't stop/tests/B8Contracts.gd` / `.tscn`：52 条量具契约。
- `Don't stop/tools/b8-run.ps1`：argv 数组式启动器（启动前打印最终 argv，无 heredoc）。
- `Don't stop/tools/b8-batch.ps1`、`b8-extension.ps1`、`b8-regression.ps1`：批次脚本。
- `Don't stop/tools/b8-summary.py`、`b8-tuning-table.py`、`b8-diff-table.py`：证据汇总与
  源码表核对。

## 11. 证据索引

见 `docs/iteration/evidence/b8/README.md`。
