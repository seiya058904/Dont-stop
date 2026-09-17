# B9 — Normal driver calibration and balance re-measurement

**产品数值：本轮 0 改动。** `git diff 33cd09ed9eea6a33b54f262d5dd9a323ac788111 -- "Don't stop/game/"` 是空的。
唯一变量是测试 driver。B8 的 22 = 1/5、26 = 4/5、29 = 0/5 **确实是 fixture 缺陷造成的低估**，
不能作为继续削弱产品的依据。

状态：`HUMAN_ACCEPTED=false` · `WEB_HUMAN_ACCEPTED=false`

## 交付状态

| 项 | 值 |
| --- | --- |
| B9 PR | [#8](https://github.com/seiya058904/Dont-stop/pull/8) — 全绿后合并 |
| B9 代码提交 | `72a5c0b` |
| 报告提交 | `4588fdc` |
| **最终 main** | **`b720249d97a20890aeba10c5b2f906eadb5ba3cf`** |
| PR CI | Web `35176118397` ✓ 8m04s · Native `35176118386` ✓ 15m34s（setup ✓ / pressure ✓ / contracts ✓）；另有分支 push 触发的 Native `35176045224` ✓ 15m27s |
| 合并后 main CI | Web `35177402358` ✓ 9m45s · Native `35177402372` ✓ 15m27s |
| 页面 | https://seiya058904.github.io/Dont-stop/index.html — HTTP 200，16339 bytes |
| 部署件 | `dontstop-build = b720249d97a20890aeba10c5b2f906eadb5ba3cf` · `dontstop-artifact = 5f86678fe9f149bf2fb837feee565201ff08b271b2b9d3a9a3317cf6cdd6161f` |

Native CI 里跑过、但本地按 §15 没重跑的套件全部通过：
`M10Bosses full` 24/0 · `B5Bosses` 166/0 · `B4Fog` 110/0 · `B6Progression` ✓ ·
`BaselineRegression` ✓ · `M6EncounterAudit` 41 · `M8Encounters` 19 ·
`M10Density stages=22,31` 11/0 · `M10Density probe` 6/0。
（`B5Bosses` 一次就过，没有用到 PR #7 的 3 次 attempt 重试。）

---

## 0. 一句话结论

把 Boss 专属的 16 方向危险规避抽成一个普通关和 Boss 共用的核心
（`M8Runtime.choose_safe_movement`）之后，**同一份产品、同一套 fixture、同一批 seed**：

| stage | OLD driver | NEW driver |
| --- | --- | --- |
| 22 | 1/5 clear，均活 27.9 s，承伤 14.07 | **9/10 clear**，均活 42.2 s，承伤 3.70 |
| 26 | 4/5 clear，均活 41.4 s，承伤 9.02 | **9/10 clear**，均活 42.0 s，承伤 4.89 |
| 29 | 0/5 clear，均活 11.3 s，承伤 10.46 | **3/10 clear**，均活 31.7 s，承伤 9.58 |

Stage 29 的承伤几乎没变（10.46 → 9.58），存活时间却从 11.3 s 涨到 31.7 s ——
**B8 削掉的那 40% 刷怪量买到的不是「能活」，而是「不再被秒」；真正买不到的那部分，是 bot 不会躲。**

结论：`difficulty(22) ≈ difficulty(26) < difficulty(29)`。22 与 26 在 n=10 下不可区分（都是 9/10，
42.2 s vs 42.0 s），而 26 在两个承伤指标上严格更高（4.89 > 3.70 总伤、0.116 > 0.088 每秒）。
29 明显最难：命中率 2.2×、每秒承伤 2.6×、clear rate 0.30。

按 §19：阶梯成立、Stage 22 能稳定通关（9/10）、Stage 29 困难但不是十秒级固定暴毙
（10 次里最快的一次 11.6 s，均值 26.0 s）→ **直接接受 B8 的产品 balance，不做 B10 Nerf。**

---

## 1. Driver 重构 diff（§20.1）

文件：`Don't stop/tests/M8Runtime.gd`（唯一被修改的测量文件）。

```
-		if target_boss and target.is_boss:
-			var best = -INF
-			var wanted = direction
-			... 16 方向评分全部内容 ...
-				if score>best: best=score; direction=candidate
+		direction = choose_safe_movement(direction,target,actors)
```

- 原 `if target_boss and target.is_boss:` 门禁删除，16 方向评分**逐行原样搬进**
  `choose_safe_movement(wanted_direction, target, actors) -> Vector2`。
- **评分数学一字未改**：16 方向、24 px 撞墙探测、38 px 前瞻、射界丢失 −3、
  出场地界 −1.5、贴身怪 −(62−d)*0.2、危险区 −(8+depth*0.6)（circle/line/charge/cone 各自的
  渐变逃逸深度）、弹道预测 −4（`position + velocity*0.3` 18 px 内）。不是复制第二份，是唯一的实现。
- **另外两处行为差异**（只有这两处）：
  1. 新增「无约束就保持不变」的快捷路径 —— 当且仅当 16 个方向里**没有一个**被几何挡住、
     且**没有任何一项惩罚生效**时，直接返回原 `wanted`，不再吸附到最近的 1/16 方向。
     这条被契约 A 钉住（空场里 `wanted (0.6, 0.8)` 原样返回）。
  2. dodge 遥测计数器（只写不读，删掉不影响任何一步移动）。
- **Boss 专属、继续保留**：Boss 目标优先（`LevelServer.boss_instance`）、Boss lead aim
  （`aim_target.velocity*min(flight,0.5)`）、Boss 近身自动 dash（65 px 内，0.85 s CD）。
- **只通过真实 WASD / 真实 dash 移动**：函数只返回一个方向，按键仍由调用方
  `Input.action_press` 发出。函数内没有 teleport、没有无敌、没有改 HP、没有删 projectile、
  没有删 hostile zone、没有强制清怪、没有直接写 `transform`。
- **反应频率保持 10 Hz**：核心仍在原来的位置被调用 —— `bot_clock < 0.1 → return` 之后。
  实测每条 45 s 回合 427–430 次决策（stage 22 批 4008 次、26 批 3997 次、29 批 2993 次），
  即 ~9.5–9.6 次/秒，和重构前同一量级，没有变成每 physics frame 60 次。

## 2. 便宜契约测试（§20.2）

`tests/B9Driver.gd` + `.tscn`（新）：**38 checks / 0 failures / 0 script errors，约 27 秒**。
先用真实 HostileZone / EnemyShot / StaticBody2D 摆出已知场地，再断言核心选出来的方向；
断言用的几何判据是从 `HostileZone.step()` 自己的伤害判据重写的，不是把核心的答案抄回来
（不自我循环论证）。

| 契约 | 断言 | 实测 |
| --- | --- | --- |
| A 空场 | `wanted` 不被无故改变 | 16 方向 0 个被挡、0 项惩罚，`wanted (0.6,0.8)` → 原样返回 |
| B 单个 circle | 危险方向被降权，有安全方向就选安全方向 | 选 `(0.383,-0.924)`，距圆心 **57.4 px**（半径 38）→ 在真实脚印外 |
| C line / beam | 不会走入明确线性危险 | 选 `(0.707,0.707)`，距中心线 **29.1 px**（半宽 8）→ 在伤害带外 |
| D cone | 能选到 cone 外方向 | 选 `(0,-1)`，在真实锥形外；场地布置保证玩家本人不在锥内，此契约不可能受伤 |
| E projectile | 短时预测轨迹会降低该候选 | `wanted` 方向距预测弹道 2.0 px（危险），选的 `(0.707,0.707)` 距 **24.7 px** > 弹体 12 px 命中半径 |
| F wall | 不会选 collision blocked 的移动 | 真实静态板挡住右方；16 个方向 **5 个被挡**并剔除，选出的方向 `test_move` 为 false |
| G all-danger | 16 方向全危险时仍选危险深度最低的方向，不 NaN、不停摆 | 全 16 个都在场里；返回 `(1.0,0.0)` 有限非 NaN；离场心 **158.0 px**（起点 120.0），且**正好等于 16 个里最浅的出口**（最深的只有 82.0） |
| H 普通遭遇战 | `target_boss=false` 时安全评分**确实被调用** | 真实 stage 22 回合：**91 次决策 / 10 s**、1275 个候选被打分、16 发子弹、移动 943 px；`target_boss=true` 走另一分支同样 89 次决策 → 两条路都走同一个核心 |

契约 H 是防倒退的那一条：它保证这个核心不会再退回成 Boss 专属。

## 3. freeze 校验（§20.3）

`tools/b9-freeze.ps1` 在跑长测**之前**冻结 28 个文件：driver、两个契约场景、两套测量 fixture、
伤害探针、启动器、**九个产品伤害入口**、以及 B8 改过的遭遇配置
（`game/config/M5Content.gd`、`DemoConfig.gd`）。跑完之后补入两个启动器
（`b9-boss.ps1`、`b9-regression.ps1`）达到 30 个。

`tools/b9-freeze-audit.ps1` 把「跑批前」和「跑批后」两份 manifest 逐字节对比：

```
pre-batch entries 28, post-batch entries 30
byte-identical across the whole measurement campaign: 25 of 28
files that moved after the manifests were first written:
  CHANGED  tests/B9Normal.gd
  CHANGED  tools/b9-freeze.ps1
  CHANGED  tools/b9-summary.py
```

三个变动的都如实说明，并且都不影响任何一次测量：

- **`tools/b9-summary.py`** —— 只读的证据汇总器（只读 JSON、只打印、只生成 `summary.json`），
  跑批中途我给它加了「多 tag 合并读取」和逐回合明细表。
- **`tools/b9-freeze.ps1`** —— manifest 生成器本身，我往清单里补了两个启动器和一个汇总器。
- **`tests/B9Normal.gd`** —— 新加的**覆盖保护**（见 §11 事件 1）。它在本轮**所有批次跑完之后**
  才加入，且在任何一回合开始**之前**执行，只做一件事：发现输出文件已存在就报错退出，
  永远不写入测量数据。

关键的是：**`tests/M8Runtime.gd`、`tests/B8Probe.gd`、`tests/B8Normal.gd/.tscn`、
`tests/B8BossFair.gd/.tscn`、`tests/B8Contracts.gd/.tscn`、`tools/b8-run.ps1`、
`tools/b8-batch.ps1`、`tools/b9-batch.ps1`，以及全部 11 个产品文件（含 `M5Content.gd`），
跑批前后逐字节相同。** 也就是说没有一条测量定义在测量期间移动过。

另外单独核对了主批次证据文件没有被覆盖（这正是下面事件 1 的隐患）：

```
normal-newdriver-s22/26/29.json  rows=5 seeds=[9101..9105] pin=[7,7,8] gun=[117] hp=[8]
normal-ext-s22/26/29.json        rows=5 seeds=[9201..9205] pin=[7,7,8] gun=[117] hp=[8]
ALL MAIN BATCH FILES INTACT: True
```

## 4. old vs new driver 数据（§20.4–§20.7）

同一产品 SHA、同一 gun 117 / `typical` 天赋升级 / 8 HP、同一 seed 9101–9105、
同一 pin（22→7、26→7、29→8）、同一探针、同一份 `run_stage()`。

### n=5（与 B8 逐一对齐，用于「多少难度来自 driver」）

| stage | driver | clear | 均存活 | hits/s | dmg/s | 承伤 | 移动 | 射击 | alive 均值 | alive 峰 | near80 峰 | proj 峰 | zone 峰 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 22 | old | 1/5 | 27.9 s | 0.70 | 0.50 | 14.07 | 2846 | 53.2 | 13.0 | 36 | 13 | 21 | 9 |
| 22 | new | 4/5 | 39.4 s | 0.18 | 0.10 | 3.96 | 4208 | 75.2 | 12.5 | 40 | 20 | 24 | 8 |
| 26 | old | 4/5 | 41.4 s | 0.26 | 0.22 | 9.02 | 4143 | 79.2 | 15.2 | 41 | 24 | 0 | 8 |
| 26 | new | 5/5 | 45.0 s | 0.15 | 0.12 | 5.50 | 4802 | 86.0 | 20.6 | 66 | 21 | 15 | 9 |
| 29 | old | 0/5 | 11.3 s | 1.08 | 0.92 | 10.46 | 1034 | 21.8 | 25.7 | 73 | 37 | 31 | 5 |
| 29 | new | 3/5 | 36.2 s | 0.25 | 0.21 | 7.76 | 3809 | 69.4 | 76.5 | 145 | 33 | 73 | 6 |

**「多少难度来自产品、多少来自不会躲的 driver」：**

| stage | clear | 均存活 | 承伤 | hits/s | dmg/s |
| --- | --- | --- | --- | --- | --- |
| 22 | 1/5 → 4/5 | 27.9 → 39.4 s | 14.07 → 3.96（−72%） | 0.70 → 0.18（−74%） | 0.50 → 0.10（−80%） |
| 26 | 4/5 → 5/5 | 41.4 → 45.0 s | 9.02 → 5.50（−39%） | 0.26 → 0.15（−42%） | 0.22 → 0.12（−45%） |
| 29 | 0/5 → 3/5 | 11.3 → 36.2 s | 10.46 → 7.76（−26%） | 1.08 → 0.25（−77%） | 0.92 → 0.21（−77%） |

移动距离从 2846/1034 px 涨到 4208/3809 px：旧 driver 在 22/29 上**根本没怎么动就死了**，
新 driver 能跑满 45 s（4820 px ≈ 107 px/s = 满速）。

### n=10（22/26/29 各加 5 个新 seed 9201–9205，用来把 22 vs 26 的次序定下来）

| stage | driver | clear | 均存活 | hits/s | 承伤 | dmg/s | 每次命中承伤 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 22 | new | **9/10** | 42.2 s | 0.163 | 37.01 | 0.088 | 0.536 |
| 26 | new | **9/10** | 42.0 s | 0.138 | 48.93 | 0.116 | 0.844 |
| 29 | new | **3/10** | 31.7 s | 0.354 | 95.76 | 0.302 | 0.855 |

### 阶梯判定（§11：不只看单个 clear rate）

| 指标 | 22 | 26 | 29 | 单调？ |
| --- | --- | --- | --- | --- |
| clear rate（高=易） | 0.90 | 0.90 | 0.30 | ✅ 成立（22/26 并列） |
| 均存活（高=易） | 42.2 s | 42.0 s | 31.7 s | ✅ 成立 |
| 承伤总量（高=难） | 3.70 | 4.89 | 9.58 | ✅ 成立 |
| 每秒承伤（高=难） | 0.088 | 0.116 | 0.302 | ✅ 成立 |
| 每次命中的伤害（高=难） | 0.536 | 0.844 | 0.855 | ✅ 成立 |
| hits/s（高=难） | 0.163 | 0.138 | 0.354 | ❌ 22 比 26 高 0.025 |

6 个指标里 5 个成立。唯一不成立的是 hits/s：22 在 422.2 s 里被打 69 次，26 在 420.4 s 里被打 58 次，
差 11 次（0.025 次/秒）。这是泊松噪声量级（λ=58 时观测到 69 约 1.4σ），**不是可分辨的难度差**。
而两个「游戏到底打到玩家多少」的指标（总承伤、每次命中伤害）都是 26 严格更高。
所以：**`difficulty(22) ≈ difficulty(26) < difficulty(29)`，22 并不比 26 难，26 确实比 29 容易。**

> n=5 时我曾经看到 `22 0.8 / 26 1.0` 的「倒挂」，当时的读数是 22 比 26 难。
> 加到 n=10 之后这个差消失了。**这一轮最重要的一条纪律在这里兑现：不拿 5 个样本的 clear rate 去改产品。**

### damage sources（§20.8，n=5 vs n=5，同一 15 场口径）

| 来源 | old 承伤 | old % | old 命中 | new 承伤 | new % | new 命中 |
| --- | --- | --- | --- | --- | --- | --- |
| normal_contact | 84.35 | 50.3% | 100 | 54.77 | 63.7% | 66 |
| beam_or_hostile_zone | 58.28 | 34.7% | 69 | 11.20 | 13.0% | 13 |
| enemy_projectile | 15.78 | 9.4% | 29 | 9.51 | 11.1% | 22 |
| self_destruct | 5.08 | 3.0% | 6 | 4.38 | 5.1% | 5 |
| arena_hazard | 3.42 | 2.0% | 7 | 3.90 | 4.5% | 5 |
| elite_contact | 0.88 | 0.5% | 1 | 2.27 | 2.6% | 3 |
| **合计** | **167.77** | 100% | 212 | **86.03** | 100% | 114 |

**这是本轮最干净的一条因果证据**：新 driver 让总承伤腰斩（167.77 → 86.03），
但 beam / hostile zone 这一类从 58.28 掉到 11.20（−81%），而身体接触只从 84.35 掉到 54.77（−35%）。
旧 driver 挨的伤害里有 34.7% 是**它自己走进光束和锥形里的** —— 明确预警、有安全空间、它没躲。
这正是「不要为了让旧的不闪避 bot 达到人为目标，而继续削弱一个已经有明确预警和安全空间的游戏」
所指的那部分伤害。

## 5. dodge telemetry（§20.9）

| stage | 决策数 | /回合 | 被挡候选 | 被打分候选 | 危险标记 | 全方向危险 | 选了危险方向 | 原样保留 | 完全卡死 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 22 (n=10) | 4008 | 401 | 11357 | 52771 | 39706 | 518 | 526 | 254 | 14 |
| 26 (n=10) | 3997 | 400 | 13747 | 50205 | 27169 | 222 | 249 | 236 | 39 |
| 29 (n=10) | 2993 | 299 | 18361 | 29527 | 12663 | 267 | 289 | 319 | 150 |
| **合计** | **10998** | — | **43465** | **132503** | **79538** | **1007** | **1064** | **809** | **203** |

- 决策频率 = 10 Hz（由 `bot_clock` 门决定），整批 **10998 次决策**，45 s 回合约 400 次 ——
  bot 的反应速度和重构前同量级，没有变成 60 次/秒的零延迟超人。
  （stage 29 每回合只有 299 次，因为它的回合平均只有 31.7 s。）
- **被拒绝的危险候选**：79538 个危险标记 / 132503 个被打分候选 = **60% 的候选方向当时在某个危险脚印里**。
- **紧急全方向危险**：1007 次决策（9.2%）16 个方向**全部**在危险区内 —— 仍然取最浅出口活下来。

## 6. 是否仍存在难度倒挂（§20.10）

**声明的阶梯 22 / 26 / 29：不倒挂。** 见 §4。

**§14 的 21–29 全面 sanity（新 driver，n=5；22/26/29 用 n=10）**：

| stage | clear | n | hits/s | 承伤 | dmg/s | alive 均值 | alive 峰 | 主要伤害来源 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 21 | 5/5 | 5 | 0.120 | 18.29 | 0.081 | 24.6 | 55 | contact, cone |
| 22 | 9/10 | 10 | 0.163 | 37.01 | 0.088 | 13.4 | 40 | contact, line, cone, shot |
| 24 | 5/5 | 5 | 0.053 | **8.29** | **0.037** | 22.0 | 67 | contact 5.8, cone 2.3 |
| 25 | 4/5 | 5 | 0.254 | **46.49** | **0.207** | 36.2 | 68 | **shot:projectile 24.1**, contact 21.5 |
| 26 | 9/10 | 10 | 0.138 | 48.93 | 0.116 | 18.6 | 66 | contact 38.0, hazard_shock 4.8 |
| 27 | 4/5 | 5 | 0.246 | 45.12 | 0.210 | 47.6 | 94 | contact 33.2, cone 7.5 |
| 28 | 3/5 | 5 | 0.388 | 43.33 | 0.237 | 56.5 | 125 | contact 21.3, line 9.8, shot 3.5 |
| 29 | 3/10 | 10 | 0.354 | 95.76 | 0.302 | 64.5 | **145（触 cap）** | contact 58.8, shot 22.4, detonate 7.0 |

整体趋势是对的：0.081 → 0.302 每秒承伤，21→29 逐步变难。但有**两个局部异常**，如实记录：

**(a) Stage 24 是一个异常低的坑。** 5/5 clear，总承伤 8.29，`projectile_peak` 均值 **0.0** ——
这一轮的 24 关**一个远程 special 都没抽到**，伤害 70% 是身体接触。而 21 关是 0.081、25 关是 0.207，
24 夹在中间却只有 0.037。

**(b) Stage 25 反向高过 26。** 4/5 vs 9/10，0.207 vs 0.116 每秒承伤。
归因很清楚：25 关的 `projectile_peak` 均值 **62.4**（26 关只有 1.5），
伤害的一半来自 `shot:projectile`；26 关 78% 的伤害是身体接触。
24 / 25 / 26 的 `special_ratio` 分别是 0.28 / 0.36 / 0.33 —— **总量相近，构成完全不同**。

也就是说：**B8 校准过的那条「数量阶梯」（刷怪率 / HORDES / interval）确实是单调的，
但实测压力还取决于这一轮 roster 抽到哪些 special。** 24 抽到纯近战，25 抽到重弹幕。

**这两个异常我没有动，理由如下：**
- §14 明说「如果新 driver 下 Stage22 已正常，禁止继续削」——22 现在是 9/10，正常，不动。
- §15 明说「如果 Stage29 survival 从约 11s 显著提高到 30–45s，说明原问题主要来自 fixture，
  产品无需再调」——29 从 11.3 s 均值提到 31.7 s，正是这个情形，不动。
- §13 的第二阶段 balance 只在「明显倒挂」时触发（它举的例子是 22=0/5、26=4/5、29=0/5），
  而现在声明的 22/26/29 阶梯成立。
- 24/25 的异常涉及的是 **roster 抽签的构成**，不是刷怪量，也不是不公平的预警重叠；
  要修也应该在 roster 权重层面单独成轮，而且现在 n=5 的证据强度不够支撑改产品。
- 而且**动 26 只会把坑挖得更深**（26 已经是阶梯上最松的一关）。

→ 记为**交给真人试玩的两个观察点**，不改数值。

## 7. 是否修改了产品 balance（§20.11）

**没有。** 本轮改动清单（`git status`/`git diff` 全量）：

```
 M "Don't stop/tests/B8Probe.gd"      +7   探针 row() 合并 dodge 遥测（只读）
 M "Don't stop/tests/M8Runtime.gd"    driver 重构（见 §1）
 M "Don't stop/tools/b8-batch.ps1"    +9   加 -Scene 参数，默认值不变，B8 调用完全可复现
?? tests/B9Driver.gd/.tscn             新契约场景
?? tests/B9Normal.gd/.tscn             新测量 fixture（继承 B8Normal，只换 driver 与输出目录）
?? tools/b9-*.ps1 / b9-summary.py       启动器与只读汇总器
?? docs/iteration/evidence/b9/          证据
```

`git diff <base> -- "Don't stop/game/"` **为空** —— 遭遇间隔、HORDES、ring_min、chase_speed、
roles、cap、敌人 HP、敌人伤害、hazards、HellMode、Boss、Fog **一个字节都没动**。

## 8. Boss regression（§20.12，§5 A/B）

Boss 产品数值不改（§16）。只验证重构没破坏既有 Boss 测试：用**同一套 B8 fixture**、
同样 seed 4201–4203、同样 authored 8 HP，在旧 driver（B8 存档）和新 driver 之间对跑。

| stage | driver | 结果 | 三次用时 | unavoidable | 死亡瞬间安全点 |
| --- | --- | --- | --- | --- | --- |
| 30 B03 | old | **1/3** | 87.3 / 41.3† / 64.2† | 0 | 22 of 42, 32 of 32 |
| 30 B03 | new | **2/3** | 70.2† / 76.7 / 74.5 | 0 | 47 of 47 |
| 40 B04 | old | **0/3** | 41.0† / 43.8† / 60.7† | 0 | 30/42, 14/32, 25/48 |
| 40 B04 | new | **0/3** | 43.8† / 38.2† / 61.3† | 0 | 41/41, 25/44, 35/46 |

（† = death）

**行为没有实质下降**：B03 从 1/3 变成 2/3，B04 维持 0/3 且三次用时几乎重合
（41.0/43.8/60.7 → 43.8/38.2/61.3）。**12 场真实战斗里 `unavoidable = 0`、`denial streak = 0`、
`denial events = 0`**，每次死亡时都有 14–47 个可达安全点，且都被雾公平门判为 fair。

§17：`B5Bosses` 的「最多 3 次真实 attempt」保留未删；本轮没有碰它。
（趋势报警的接口在那里：每次 attempt 的 clear/death 与用时都会打印，未来如果经常要第 3 次，
就应该当作测试稳定性在退化来处理，而不是继续加 retry。）

## 9. Hell 31–40 = 0 changes 的证明（§20.13）

- `git diff 33cd09ed9eea6a33b54f262d5dd9a323ac788111 -- "Don't stop/game/"` → **空**。
  31–40 的 HP、damage、speed、density、fog、hazards、B04 全部逐字节等同 B8 合并后的状态。
- `game/config/M5Content.gd` 与 `game/config/DemoConfig.gd` 在 B9 freeze 里，且
  pre-batch / post-batch manifest 逐字节相同 → 遭遇表没有被动过。
- `HellMode.gd` / `ArenaVisibility.gd` / `ArenaHazards.gd` / `TacticalEnemy.gd` 攻击表 /
  `BossUltimate.gd` 都不在改动集里（改动集只有上面 §7 那三个测试文件）。
- 链式论证：B8 已用字段级 diff 证明 31–40 有 0 处变化 → 而 B9 相对 B8 的产品目录 0 变化
  → **31–40 相对 B8 之前的状态也是 0 变化**。Hell 真正的 balance 等真人试玩（§18）。

## 10. 全部回归（§20.14 的一部分）

`tools/b9-regression.ps1`，**894 checks / 0 failures / 0 script errors**（约 7 分钟）：

| 套件 | 结果 | 为什么在范围内 |
| --- | --- | --- |
| `B9Driver` | 38 / 0 | 本轮新契约 |
| `B8Contracts` | 52 / 0 | `B8Probe.row()` 合并了 dodge 遥测 |
| `M8Contracts` | 52 / 0 | driver 的基类 |
| `M6Contracts` | 121 / 0 | 同上 |
| `M4Talents` | 233 / 0 | 同上 |
| `M10Growth` | 233 / 0 | 同上 |
| `B3Hazards` | 128 / 0 | 危险区伤害路径 |
| `M10Density stages=22,31` | 11 / 0 | **最强外部检查**：native CI pressure job 用的正是这一条，它断言被 driver 开的回合 `row.clear` 且 `movement>1000` —— 新核心没有把 driving 弄坏 |
| `M10Density probe stages=22,31` | 6 / 0 | 同上 |
| `R3SpawnAudit` | 20 / 0 | driver 走位沿途的出生合法性 |

`M4Talents` / `M10Growth` 各有一条 `2 resources still in use at exit` —— 那是 Godot 退出时的
既有噪声，不是断言；两套都是 0 failures。

按 §15 的判断，本轮**没有**重跑 `B4Fog` / `B5Bosses` / `B6Progression` / `M10Bosses`
（雾、Boss 实现、进度都未触碰；`B5Bosses`/`M10Bosses` 本来就在 native CI 的 `pressure` job 里
每次 push 都跑）。Boss 行为另外由 §8 的 B03/B04 定向 A/B 覆盖。

## 11. 本轮的事件记录（不好看但必须写）

**事件 1：fixture 静默覆盖了自己的证据。**
sanity 扫描第一遍（tag `sanity`，stage 24/25，seeds 9101–9102）跑完后，我为了加样本又用
**同一个 tag** 跑了 seeds 9103–9105 —— `B9Normal` 的 batch 模式是每回合把「本进程累积的 rows」
写回同一个文件名，所以第二次调用**直接替换**了第一次的两行。

- 影响范围：只有 sanity 扫描的 24/25 两个 stage 各 2 行。**主批次没有受影响** ——
  22/26/29 的两次批用了不同 tag（`newdriver` / `ext`），每次都是单进程跑完，
  已逐文件核对 `rows=5`、seed、pin、gun 117、8 HP 全部正确（见 §3）。
- 处理：给 fixture 加了**覆盖保护** —— 输出文件已存在就 `check(false)` 并退出，
  在跑任何一回合之前执行，所以被拒绝的调用不花时间也不写任何东西。
  已实测验证：3.3 秒退出、`FAIL refusing to overwrite existing evidence at ...`、`exit 1`。
- 丢失的两行用**新 tag `sanity5` 重新测量**补回（不是从日志里恢复 —— 日志里的数字不作为证据）。
  24/25 现在是 `sanity5` 单文件 n=5；21/27/28 是 `sanity`(n=2) ∪ `sanity5`(n=3)。
- 这就是为什么 §3 的 freeze 审计会列出 `tests/B9Normal.gd` 变动过：加的就是这个保护。

**事件 2：`b9-summary.py` 在跑批期间被改过。** 它是只读汇总器，不影响任何一次测量，
但仍然出现在 freeze 审计的 diff 里，如实列出。

**事件 3：n=5 的阶梯读数曾经是错的。** 见 §4 末尾 —— 如果我在 n=5 就下结论，
会得出「22 比 26 难」这个错误判断，并可能据此去动产品。加样本把它推翻了。

## 12. 交付物索引

| 项 | 位置 |
| --- | --- |
| driver 重构 | `Don't stop/tests/M8Runtime.gd`（`choose_safe_movement`） |
| 便宜契约测试 | `Don't stop/tests/B9Driver.gd` + `.tscn` |
| 测量 fixture | `Don't stop/tests/B9Normal.gd` + `.tscn`（继承 `B8Normal`） |
| freeze 清单 / 校验 / 漂移审计 | `tools/b9-freeze.ps1` · `b9-freeze.ps1 -Verify` · `b9-freeze-audit.ps1` |
| 批次 / Boss A/B / 回归启动器 | `tools/b9-batch.ps1` · `b9-boss.ps1` · `b9-regression.ps1` |
| old-vs-new 汇总 | `tools/b9-summary.py`（读 `evidence/b8` + `evidence/b9`） |
| 证据 | `docs/iteration/evidence/b9/`（索引见其 `README.md`） |
| 过程存档 | `tools/b8-run.ps1` · `b8-batch.ps1`（B8 口径，唯一变化是加了 `-Scene`，默认值不变） |

## 13. 遗留与建议（交给真人试玩）

1. **Stage 24 / 25 的 roster 构成落差**（§6）。数量阶梯是单调的，压力不是 —— 24 纯近战、
   25 重弹幕。建议在真人试玩里确认「25 比 26 难」是不是玩家真实感受；
   若是，下一轮只调 24/25 的 roster 权重，**不要**再整段动 21–29。
2. **Stage 29 的 horde 基本上打不完**：`alive_mean` 64.5、`alive_peak` 145 = **cap**，
   10 次里活下来的 3 次都是靠满速放风筝跑满 45 s。B8 §3 当时判断「cap 不是约束」
   在新 driver 下已经不再成立。这是最值得真人试玩确认的一点：
   如果玩家觉得 29 是「被潮水推着走」而不是「打得动」，那是 replenishment / cap 的问题，
   不是伤害的问题。
3. **3 次死亡伴随真实的身体围死**（body enclosure）：22/9105、26/9204、28/9105，
   死亡瞬间 49 个探针点里**只有 1 个可达**，且持续 0.8–0.9 s（denial streak 8–9）。
   精确地说：**围死是身体造成的**（可达集合被怪压到 1 个点），而致命一击其中 2 次是
   `contact`、1 次（22/9105）是 `cone` —— 也就是说 22 那一次是「被围住 + 锥形同时覆盖那唯一出口」。
   其余 10 次死亡发生时都有 1–8 个可达且公平的安全点，即 bot 有地方可去而没去成。
   按 §7-A 属于 knob A（`ring_min` / `chase_speed` / `HORDES.windows`），
   但本轮按 §13/§14/§15/§19 不动。
4. E10 光束的 0.65 s 预警仍在项目自己的 0.5–0.8 s 公平带内，未改。

## 14. 需要知道的两条测量口径

- **freeze 清单是本机工作副本的哈希**（`core.autocrlf=true`，检出的被测文件是 CRLF）。
  它用于「同一台机器上跑批前后有没有动过」这个判断，30/30 校验通过；
  它不是跨机器可移植的校验和。B8 的清单同口径。
- **`evidence/b9/normal-smoke-s22.json` 是 harness 冒烟测试**（1 个 seed，确认新 fixture 能跑通），
  不属于任何报告数字。所有汇总只读上面表格里点名的 tag。
