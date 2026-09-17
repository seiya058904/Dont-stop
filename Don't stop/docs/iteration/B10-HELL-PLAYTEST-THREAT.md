# B10 — Hell Playtest Access + Special Enemy Threat Revision

> **SUPERSEDED BY B11.** This document describes the "Hell Playtest / 地狱试玩" selector that B11
> deleted. It was a misreading of the requirement: the product has no trial stage, no locked stage and
> no preview mode, and Stage 1-40 are all permanently selectable from ONE normal stage list. The
> measurements and the enemy-threat analysis below are still the record of what was built at the time;
> **anything in here that describes the playtest entry, the lock, or the per-attack lead values is no
> longer true of the product.** See `B11-FAIR-FIGHT-AND-PERF.md` for the current rules.

**本轮产品改动分两块：**（1）让 31–40 真正可以在正式 Web 里被真人打开；（2）在不增加怪物数量、
不涨 HP / 伤害的前提下，提高**特殊怪的单位战术威胁**。
Stage 29 密度、Boss 框架、Hell 31–40 的 HP/damage/speed/fog/hazard 全部未动。

状态：`HUMAN_ACCEPTED=false` · `WEB_HUMAN_ACCEPTED=false`

---

## 1. 为什么之前 31–40 无法真人试玩

**结论：不是 A，不是 B，是 C + D —— 而且根因是「唯一的旁路只存在于原生命令行」。**

具体证据链（先读代码、再在真实浏览器里复核，不是猜）：

**(1) UI 其实是暴露的 —— 排除 B。**
`ui/CampPanel.gd` 的 `stage_list()` 一直会渲染 `———— HELL MODE ————` 标题和 31–40 的按钮。
真实浏览器里也确认了这一段存在。

**(2) 正式解锁链路本身是对的 —— 排除 A。**
`LevelServer.victory()`：通关 30 → `Demo.campaign_complete = true`；`Town.gd` 把 `next_stage`
推到 31；`CampSnapshot.normalize()` 把旧档的 `next_stage 30 → 31` 迁移过来，且不升 schema。
`tests/M5World.gd` / `tests/B6Progression.gd` 一直在覆盖这条链路。

**(3) 真正卡住的是解锁条件本身。**
`CampPanel.stage_unlocked()`：

```gdscript
	if Demo.campaign_complete: return true
	return "--hell-unlock" in OS.get_cmdline_user_args()
```

31–40 的按钮 `disabled = locked`，`depart()` 也会二次拒绝。也就是说，未通关 30 的存档**只能**靠
`--hell-unlock` 这个原生命令行开关进去。

**(4) 那个开关在浏览器里根本传不进去。**
`web/loader.html` 只把**五个**查询参数映射成引擎参数：

```js
if (params.has('smoke')) { GODOT_CONFIG.args = ['--smoke']; ... }
if (params.has('probe')) { ... }
```

`smoke / nw / e2e / tour / probe` —— 没有 `hell-unlock`，也没有任何通用映射。
Web 版里 `OS.get_cmdline_user_args()` 因此永远是空的，**`--hell-unlock` 在浏览器中不可达**。

**(5) 存档层还会主动把它挡住 —— 这是 D。**
`CampSnapshot.normalize()`：未通关的存档 `next_stage` / `selected_stage` 一律被夹回 ≤30，
所以就算手改存档也进不去。这条规则本身是对的（防作弊），它只是让「唯一入口」问题更彻底。

**所以真实原因是一句话：** 31–40 的正式门禁是「通关 30」，而唯一的旁路是一个**只在原生端存在、
且从未接到 Web 查询参数上**的测试开关。B批实现 Hell 时留了这个开关给测试用，但没有留下
任何真人可用的入口 —— 于是 Hell 从来没有人真正玩到过。

**真实浏览器证据**（本地 Web 导出 + Chromium，`tools/web-hell-playtest-e2e.js`）：

```
A_HELL_PLAYTEST_ENTRY_IS_VISIBLE=true
A_FORMAL_HELL_ENTRIES_ARE_LOCKED_IN_THE_BROWSER=true   <- 探测通道对禁用的 31/35/40 一个矩形都不报
A_FRESH_PROFILE_IS_NOT_A_COMPLETED_CAMPAIGN=true
```

---

## 2. 最终如何提供 Hell Playtest

在营地「出发」页里加了一个**明确标注的**入口，而不是隐藏作弊命令：

```
普通战役 1—30
  继续：…
  [1]…[30]

———— HELL MODE ————                <- 正式区，未解锁时按钮全部保持禁用（一个字都没改）
  [31]…[40] · 未解锁
  [ HELL PLAYTEST · 地狱模式试玩（31—40） ]     <- 新入口

（点下去之后，正式区被替换成独立试玩选择器）
———— HELL PLAYTEST · 地狱试玩 31—40 ————
  试玩模式：可自由进入 31—40。不记录通关，不改变正式进度，不影响存档指针。
  [31]…[40] · 试玩
  [ 退出试玩 · 返回正式关卡表 ]
```

实现要点（`ui/CampPanel.gd`）：

* 新增 `var hell_playtest := false` 与 `stage_playtestable(stage)`：**只**在试玩选择器打开时，
  且**只**对 `HellMode.is_hell()` 的 31–40 返回 true。正式门禁 `stage_unlocked()` 的语义
  **一个字没改**，`--hell-unlock` 也照旧可用。
* `depart(stage, trial, playtest)` 新增第三个可选参数，默认 false —— 所有既有调用行为不变。
* 正式按钮保持 `disabled`，文案也不变；试玩入口是**另一个**选择器。

---

## 3. 是否污染正式 progression：**没有任何污染**

这是本轮最需要证明的一条，所以它被写成了 10 条契约（`tests/B10Playtest.gd`，51 checks / 0 failures）。

**机制上**：试玩出发走的是既有的 **trial 通道**（`depart(stage, true)` → `Town.depart(stage,true)`
→ `Demo.trial = true`），而 `LevelServer.victory()` 里**所有**进度写入本来就在 trial 之外：

```gdscript
	if not Demo.trial:
		Demo.next_stage = stages[...]
		if level == 30: Demo.campaign_complete = true
		if level == 40: Demo.hell_complete = true
```

所以「试玩通关 40 会不会把地狱标记成已完成」在代码结构上就不可能。

**实测**（stub 服务下的真实回合，`B10Playtest` 输出）：

| 断言 | 结果 |
| --- | --- |
| 试玩出发确实是 trial 出发 | PASS |
| 试玩通关 31 之后 `next_stage` 不变（12 → 12） | PASS |
| 试玩通关 31 之后 `campaign_complete` 仍为 false | PASS |
| **试玩通关 40 之后 `hell_complete` 仍为 false** | PASS |
| 试玩通关 40 之后 `next_stage` 不变 | PASS |
| 清掉 40 的试玩**确实**是靠 Boss 真死结束的（`victory()` 拒绝活的 Boss，所以回到营地即证明击杀） | PASS |
| 31 / 32 / 35 / 38 可以连续试玩，每次都是真的在跑（实测时钟/刷怪/Boss 动作三者之一在推进） | PASS |
| 试玩过的 `snapshot()` 仍然是产品接受的状态，且 `normalize()` 对它是**恒等**（不需要被修复） | PASS |
| schema_version 仍是 6，去掉 `hell_complete` 的旧档仍然 validate | PASS |
| 非试玩出发会清掉 playtest 标记，且不带走迷雾 | PASS |

其中一条是修出来的：试玩会让 `selected_stage` 停在 31，而 `CampSnapshot.normalize()` 在
未通关时本来会把它夹回 30 ——「写出去的状态是加载时会被修正的状态」是个隐患，所以在
`Demo.snapshot()` 里加了同一道夹取，磁盘上的存档永远是产品愿意接受的状态。`next_stage`
（真正的进度指针）依然完全不碰。

---

## 4. 哪些特殊怪被修改 / 5. Before → After

（见 §6 的审计表；改动的共同根因见 §6。）

## 6. 特殊怪威胁审计（SpecialThreatAudit）

### 为什么需要它

真人的反馈不是「特殊怪太少」，而是「看到它不需要改变打法」。**clear rate 看不到这件事，
伤害表也看不到**：一个玩家从不需要反应的攻击，在两者里都是隐形的。所以新增
`tests/B10Threat.gd`，对每一种特殊攻击量三件事：

* **standing** 玩家完全不动 —— 值得怕的攻击必须打中。
* **strafe** 玩家全程只按一个方向满速跑 —— 就是「一直绕圈就自己躲掉了」那种打法。
* **dodge** 玩家跑真实的 B9 移动核心（`M8Runtime.choose_safe_movement`，Boss 与普通关共用的
  那套 16 方向危险扫描）—— 大多数攻击**应该**能躲掉，这才是「危险但公平」。

命中数从 `Hero.damage_taken` 上数，按 instance id 归属到被测的那一只；不是它打的记为
`foreign_hits`，不会被算进去。每一场都是真实 actor 的真实攻击：不注入伤害、不强制出招。
fixture 只做三件被明确记录的事：把玩家放回本回合自己的出生点（让每场可比）、放宽血量、
抬高被测怪的 HP（让它活满窗口）。

### 审计过程中被修掉的三个「量具自己坏了」的坑

这三条都是我的问题，不是产品的问题，但都会直接制造假数据，所以记录在案：

1. 一开始我照抄 `tests/M5World.gd` 关掉了玩家的 `_physics_process` —— 结果三个场景**完全一样**
   （玩家根本动不了）。现在审计开着玩家物理，并在文件里写明原因。
2. 审计跑在**一个还在正常出怪的回合里**：关卡自己的小怪在两次试验之间打玩家（首版记到
   16 次 `foreign_hits`），并且把「是否出招」判断用的 transient 基线抬高 —— 于是大部分怪
   看起来**从不攻击**。现在审计在出发后 `LevelServer.timerStop()` 接管竞技场（state 仍是
   COMBAT，敌人 AI 与迷雾判定照常），并在每场前清掉 monsters / transients / StageHazard /
   ArenaHazardDirector。
3. 最难发现的一条：**攻击还没落地就结算了**。原来在「检测到出招」后固定等 0.9 s 就记分，
   而 E05 的弹丸速度只有 85 px/s，穿过 150 px 的试验距离需要约 1.8 s —— 它还在半空中，
   试验就结束了、actor 也被释放了。于是弹幕类在 standing 场景里被记成 **0 命中**。
   现在改成等竞技场**重新安静下来**（transient 数回到基线）才算这一次攻击结束。

**修完之后 E05 的 standing 从 0 变成 5.0 命中/场** —— 也就是说，如果没有第 3 条，
我会拿着「弹幕类站着不动都打不中」这个假结论去改产品。

### 根因：所有锁定式攻击都在预警起点做「零预测快照」

`game/monster/TacticalEnemy.gd:choose_attack()`：

```gdscript
	locked_direction = global_position.direction_to(Utils.player.global_position)
	locked_point = Utils.player.global_position
```

这两行在**预警开始的那一刻**执行一次，而且**完全没有预判**。玩家速度约 106 px/s：

* 0.65 s 预警 → 玩家能走约 69 px，而光束是一条 280 px 长、**8 px 宽**的静态直线；
* 0.95 s 预警 → 玩家能走约 95 px，而炮击圈半径只有 **40 px**。

所以「轻轻挪一步」就把整个攻击废掉了，这不是伤害不够，是**瞄准在开火前就已经过期**。
唯一的例外是 Boss：`dash` 用 `locked_point + player.velocity*0.25`，`lockdown` 用
`…*0.7` —— **普通特殊怪一个预判都没有**。

### 最终机制（Laser / Barrage）

**Laser（E10 光束、E14 哨兵）**
* **晚锁定**：预警前 55% **持续跟踪**玩家（`LOCK_TRACK_SHARE`），后 45% 冻结。
  冻结时施加 **0.15–0.35 s** 的有限预判（用户建议区间下沿），不是完美预测。
  于是「一开始挪一步」不再有效 —— 玩家必须**在锁定之后**再次改变方向才躲得掉。
* **Elite / 双线**：E14 的精英版在开火后做**有限扫射**（`sweep ≈ 0.42 rad ≈ 24°`），
  有明确方向（`orbit_side`），不是无脑扫屏。
* **公平**：预警依旧清晰且比伤害帧早 0.25–0.4 s 以上；没有瞬发、没有隐形 beam、
  没有 360° 完美跟踪、没有锁到伤害帧。

**Barrage / projectile（E05、E10 炮击、E13 控制弹）**
* 因为锁定改成「晚锁定 + 有限预判」，扇形弹幕的**中心弹自然变成预判弹**，两侧仍是扇形 ——
  正好是用户要的 Predictive Burst。
* **速度分化**（不同类保持区别）：E05 普通弹 85/95 → **120**、预判中心弹 → **145**；
  E10 炮击弹幕 115 → **140**；E13 束缚弹 130 → **150**，样式仍是紫色 root 弹，可辨识。

**Charge（E04 / E11）**：同样获得晚锁定 + 有限预判；E04 精英的「两段冲锋」保留，
中间仍有 0.4 s 明确 recover 警告，不做无限连锁。

**Artillery（E10）**：炮击圈跟随预警 55% 后带预判冻结；精英炮击者额外多标一个沿玩家速度
方向的区域，逼玩家换路线，而不是「离开第一个圈」就完事。

**Root / Control（E13）**：仍然只走 `Hero.apply_root()`，不新造 stun；CC 免疫原样保留；
束缚弹拿到有限预判与更快速度，可读性靠既有的紫色 root 弹样式。

**Self-destruct（E06）**：预警圈同样跟随 55% 后冻结 —— 「从旁边走过去」不再是免费的。
没有加瞬移爆炸。

**Boss（§19）**：Boss 复用同一套 `zone()` / `_begin()` 模块，所以它自然继承「晚锁定」；
Boss 的 HP、阶段数、percentage 伤害、全局伤害**都没有动**。

---

## 7–16

（回归、性能、PR、SHA、Pages、地址见文末「交付状态」。）

---

## 4. 哪些特殊怪被修改

**只有两个文件被改**（`git diff main -- "Don't stop/game/"`）：

```
 Don't stop/game/monster/DemoEnemy.gd      +114   E04 冲锋 / E05 弹幕
 Don't stop/game/monster/TacticalEnemy.gd   +81   E06/E10/E11/E12/E13/E14 + 全部 Boss 共用的 _begin()
```

`M5Content.gd`（含 31–40 全部遭遇表、cap、HORDES、interval、ring_min）、`HellMode.gd`、
`DemoConfig.gd`、`ArenaVisibility.gd`、`StageHazard.gd` **一个字节都没动**。

| 怪 | 机制 | 是否修改 |
| --- | --- | --- |
| E04 预警冲锋者 | 固定方向冲刺 | ✅ 晚锁定 + 有限预判；**冲锋距离按距离计算** |
| E05 远程喷射者 | 停步实体弹 | ✅ 晚锁定 + **弹道飞行时间预判**；弹速 85/95 → 120/145 |
| E06 自爆逼近者 | 近身预警自爆 | ✅ 预警圈同样跟随 55% 后冻结（未加瞬移爆炸） |
| E10 标记炮击者 | 炮击 + 蓄力射线 | ✅ 两种都改；炮击弹速 115 → 140；精英多标一个区域 |
| E11 侧绕猎手 | 侧切 + 冲撞 | ✅ 晚锁定 + 有限预判 |
| E12 易爆载能体 | 扇面放电 | ✅ 晚锁定 + 有限预判 |
| E13 震颤射手 | 束缚弹 | ✅ 有限预判 + 弹速 130 → 150；仍只走 `Hero.apply_root()` |
| E14 激光哨兵 | 长距离射线 | ✅ 晚锁定 + **精英有限扫射 ~24°** |
| E07/E08/E09 | 召唤 / 治疗 / 盾卫 | ❌ 未改（本轮不是目标） |
| Boss B01–B04 | — | ❌ HP / 阶段 / percentage / 全局伤害全未改；只是**继承**了同一套 `_begin()` 所以自然获得晚锁定 |

## 5. SpecialThreatAudit 结果（Before → After）

单位：**每次试验的命中数**（每格 n=3–4 次试验，stage 24，`foreign_hits=0`）。

| id | 名称 | Before 站桩 / 单向跑 / 反应闪避 | After 站桩 / 单向跑 / 反应闪避 |
| --- | --- | --- | --- |
| E04 | 预警冲锋者 | 0.00 / 0.00 / 0.00 | **1.00** / 0.00 / 0.00 |
| E05 | 远程喷射者 | 5.00 / 0.00 / 0.00 | 5.00 / 0.00 / 0.00 |
| E06 | 自爆逼近者 | 1.00 / 0.00 / 0.00 | 1.00 / 0.00 / 0.00 |
| E10 | 标记炮击者 | 2.00 / 0.00 / 0.00 | 2.00 / **1.00** / 0.00 |
| E11 | 侧绕猎手 | 1.00 / 0.00 / 0.00 | 1.00 / **0.67** / 0.00 |
| E12 | 易爆载能体 | 2.00 / 0.00 / 0.00 | 2.00 / 0.00 / 0.00 |
| E13 | 震颤射手 | 3.00 / 0.00 / 0.00 | 3.00 / **1.00** / 0.00 |
| E14 | 激光哨兵 | 2.00 / 0.00 / 0.00 | 2.00 / **1.00** / 0.00 |

**最重要的两行读数：**

* **改之前：8 种特殊怪里，有 8 种对「全程只按一个方向满速跑」的玩家命中数为 0。**
  这就是「反正继续绕圈就自己躲掉了」的量化版本 —— 不是伤害不够，是**瞄准在开火前就过期了**。
* **改之后：4 种（E10 / E11 / E13 / E14）开始打得中单向跑的玩家**，而**反应闪避仍然全部躲得掉**
  —— 安全区仍然存在，玩家仍然「看得懂、躲得掉」。

**没有达成的部分，如实列出（不改数值、留给真人试玩判断）：**

1. **E05 / E06 / E12 对单向跑仍然 0。** 原因不是瞄准而是**速度**：
   E05 的弹丸 120 px/s、E12 本体 95 px/s、E06 虽然 125 px/s 但攻击距离只有 34 px —— 玩家 106 px/s
   直接**跑出它们的攻击范围**，E05 的弹丸还会在 3.2 s 寿命内追不上。
   这是设计上「跑掉就行」的属性，不是本轮要修的瞄准问题；要动就得动敌人**速度**（`HellMode.SPEED_*`
   是最小的一条轴，且 31–40 的数值本轮冻结）。
2. **E04 的站桩命中也只有 1.00。** 它的 `charged` 命中半径是 19 px，冲锋修正后仍常常「擦身而过」。
3. **反应闪避一列全 0**：B9 那套 16 方向危险扫描确实很强，所以这一列更像「上限」而不是「真人水平」。
   真人的避让不如它，这也是为什么**真人试玩必须接手判断 Hell 到底够不够难**。

## 21. 攻击 UI 可读性

* 预警 → 锁定 → 开火 的三段是可读的，而且**锁定那一刻本身就是可见的**：footprint 在预警前 55%
  会**跟着玩家走**，后 45% 停住 —— 玩家看到线/圈「不再跟着我」就是锁定发生了，随后才是伤害帧。
  这比加一条 debug 线更直接，也不需要放大字号。
* 颜色语言沿用既有映射，未改：Charge 橙、Self-destruct 红、Laser 青/洋红（`zone(...,"laser")`）、
  Root 紫（`"root"` + 紫色 root 弹）、Poison 绿、Artillery 高对比地面圈。
* 精英 E14 的扫射有**明确方向**（`orbit_side`），不是无脑扫屏。
* 没有新增「只有一条 debug line」的提示；所有视觉都走既有的 `HostileZone` / `CombatTelegraph` / `HostileVFX`。

## 24. 浏览器视觉证据（本轮的诚实边界）

真实浏览器（本地 Web 导出 + Chromium，`tools/web-hell-playtest-e2e.js`）截图：

| 文件 | 内容 |
| --- | --- |
| `browser/10-hell-locked.png` | 营地「出发」页：`普通战役 1—30` + **可见可点的 `HELL PLAYTEST · 地狱模式试玩（31—40）`**，正式 31–40 未报出任何矩形（即仍锁定） |
| `browser/11-hell-playtest-selector.png` | 试玩选择器：`———— HELL PLAYTEST · 地狱试玩 31—40 ————`、说明文字「不记录通关，不改变正式进度，不影响存档指针」、**`R7 · 31 雾蚀初现 · 试玩` 处于可用状态**（下一行 `R7 · 32 雨裂都市 · 试玩`） |
| `browser/60-second-session-selector.png` | 返回主菜单、重新开始之后的**第二个 session**，试玩入口仍然可用 |

**没有拿到的证据，以及原因：** 「31 / 35 / 40 各自进入一回合再回营地」这一段（脚本里的 C 阶段）
**没有在浏览器里跑通**。脚本的 A（入口可见、正式门禁仍锁）、B（点开选择器、31/35/40 都变为可用）、
F（第二个 session 仍然可用）都通过，C 阶段停在「打开出发页后没报出试玩入口」。
排查中确认并修掉了三个 driver 自身的问题（列表滚动、探测矩形只报屏幕内控件、旧面板被复用），
A/B/F 因此转绿，C 阶段仍有一步没定位到 —— 而**产品侧的完整链路已经由
`tests/B10Playtest.gd` 的 51 条契约在真实回合里证明了**（含「试玩通关 40 但不写 `hell_complete`」）。
也就是说：**入口本身在真实浏览器里已被证明可用；「逐个关卡进出」的浏览器脚本尚未完成。**
这条不当作已完成上报。

另外，§24 要求的**逐种攻击的 telegraph 截图（Laser warning/fire、Barrage、Charge、Artillery、
Root、Self-destruct）本轮没有采集**：它们需要在浏览器里驱动普通关打到特定怪出手，成本远高于
本轮余量。攻击行为本身有 `B10Threat` 的量化证据（真实 actor、真实攻击、三场景命中数），
但「视觉上是不是 debug 图形」这一条只有代码与既有 telegraph 复用作为依据，**没有截图**。

## 25. 性能

* **没有增加任何数量**：`special_ratio`、`cap`、`HORDES`、刷怪率、弹幕发数**全部未改**。
  E10 的炮击弹幕仍是 6/12 发、E05 仍是 1/5(+3) 发、Boss 的 barrages 一发未加。
* `game/monster/EnemyShot.gd:37` 的 **180 发弹幕上限原样保留**，`EnemyBarrage` 的 wave 结构未改。
* 本轮的威胁来自 **pattern 与瞄准质量**，不是弹量 —— 与 §25 的要求一致。
* 新增的每帧成本只有：预警期间一次 `Vector2` 运算（跟踪锁）与每帧更新最多 2 个 footprint 的位置；
  没有新增节点、没有新增分组、没有新增 draw call。
* Web 帧率：本地导出实测 `fps=6~7`（软件渲染 Chromium，SwiftShader），与改动前同量级；
  真实浏览器（用户的机器）由 CI 的 Web gates 覆盖。

## 17 / 18 / 19 / 20

* **§17 Normal 20–30：** 没有做第二次数量提升。20–30 的「更需要主动应对 special」只通过单位威胁实现：
  E10（28 关炮击/射线）、E11（23/28/29 侧绕）、E13/E14（Hell 专属）等现在会打得中单向跑的玩家。
* **§18 Stage 29 密度：** `M5Content.gd` 完全未改，cap 145 / interval 0.32 / HORDES 一字未动。
  **29 的怪物数量没有增加，也没有 Nerf。**
* **§19 Boss：** HP、阶段数、percentage 伤害、全局 Boss 伤害**全部未改**。Boss 因为复用
  `_begin()`/`zone()` 而**自然继承**了晚锁定，这正是 §19 允许的那一种；`M10Bosses full` 24/0 通过。
* **§20 Hell 31–40：** `M5Content.gd` / `HellMode.gd` 未改 ⇒ HP / damage / speed / density / Fog / Hazard
  全部保持原值。本轮对 Hell 做的事只有一件：**把它交到用户手里**。

## 27. 回归与 Web gates

见「交付状态」的 native 结果。受影响面按改动选：`B10Playtest`、`B10Threat`、`B9Driver`、
`B8Contracts`、`M8Contracts`、`M10Bosses full`、`M10Density stages=22,31`（含 probe）、`R3SpawnAudit`
—— **256 checks / 0 failures**。

**没有修改 CI 架构**：`native-tests.yml` 与 `deploy-pages.yml` 的 job/矩阵结构一个字节未动
（B10Playtest 是否要加入 native contracts job，留给下一轮决定，本轮不改门禁拓扑）。
现有 Web gates（smoke / save-audit / aim-core / aim-fault / menu-return）由 CI 运行并保持绿。

## 22 / 23

* §22 的三场景审计已实现并运行（见 §5、§6）。
* §23：攻击逻辑只使用 `Utils.player.global_position` / `.velocity` / `.SPEED` 与自身攻击状态。
  **没有**读测试状态、没有读未来输入、没有读 fixture seed、没有读安全方向评分器。

